#!/usr/bin/env python3
"""Run one command with bounded output, deadline, and process-tree cleanup."""

from __future__ import annotations

import argparse
import fcntl
import os
import selectors
import signal
import subprocess
import sys
import time

TIMEOUT_MARKER = "omarchy-protonvpn: command timed out\n"
OVERFLOW_MARKER = "omarchy-protonvpn: command output exceeded the safety limit\n"
LOCK_NAME = "omarchy-protonvpn.lock"
LOCK_POLL_SECONDS = 0.05
POLL_SECONDS = 0.1
# How long output may keep flowing after the command exits. Past this, the
# pipes are held by a background process the command left behind.
EXIT_GRACE_SECONDS = 0.5


def terminate_tree(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except OSError:
        try:
            process.terminate()
        except OSError:
            pass
    try:
        process.wait(timeout=0.25)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except OSError:
        try:
            process.kill()
        except OSError:
            pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass


def terminate_group(pgid: int) -> None:
    """Stop what is left of the command's process group after it exited."""
    try:
        os.killpg(pgid, signal.SIGTERM)
    except OSError:
        return
    give_up = time.monotonic() + 0.25
    while time.monotonic() < give_up:
        try:
            os.killpg(pgid, 0)
        except OSError:
            return
        time.sleep(0.02)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except OSError:
        pass


def acquire_lock(deadline: float) -> tuple[int | None, bool]:
    """Take the per-user lock; return (fd, timed_out).

    Without a usable runtime directory the command runs unlocked: the lock
    only orders this plugin's own calls, so it must never block them outright.
    """
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if not runtime or not os.path.isabs(runtime):
        return None, False
    try:
        fd = os.open(
            os.path.join(runtime, LOCK_NAME),
            os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
        )
    except OSError:
        return None, False
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd, False
        except BlockingIOError:
            pass
        except OSError:
            os.close(fd)
            return None, False
        if time.monotonic() >= deadline:
            os.close(fd)
            return None, True
        time.sleep(LOCK_POLL_SECONDS)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-bytes", type=int, default=262_144)
    parser.add_argument("--max-seconds", type=float, default=30)
    parser.add_argument("--lock", action="store_true", help="wait for other locked runs; the wait counts toward the deadline")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command or args.max_bytes < 1 or args.max_seconds <= 0:
        parser.error("a command, positive byte limit, and positive deadline are required")
    return args


def write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        try:
            written = os.write(fd, view)
        except BrokenPipeError:
            return
        view = view[written:]


def run(argv: list[str]) -> int:
    args = parse_args(argv)
    deadline = time.monotonic() + args.max_seconds
    if args.lock:
        _lock_fd, lock_timed_out = acquire_lock(deadline)
        if lock_timed_out:
            write_all(2, TIMEOUT_MARKER.encode()[: args.max_bytes])
            return 124

    child_env = os.environ.copy()
    child_env["LC_ALL"] = "C"
    child_env["NO_COLOR"] = "1"
    try:
        process = subprocess.Popen(
            args.command,
            env=child_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
            close_fds=True,
            bufsize=0,
        )
    except OSError as error:
        print(f"omarchy-protonvpn: {error}", file=sys.stderr)
        return 126

    interrupted = False

    def handle_signal(_signum: int, _frame: object) -> None:
        nonlocal interrupted
        interrupted = True
        terminate_tree(process)

    previous_term = signal.signal(signal.SIGTERM, handle_signal)
    previous_int = signal.signal(signal.SIGINT, handle_signal)
    selector = selectors.DefaultSelector()
    counts: dict[int, int] = {}
    outputs: dict[int, int] = {}
    stderr_pipe_fd = process.stderr.fileno() if process.stderr is not None else -1
    for stream, output_fd in ((process.stdout, 1), (process.stderr, 2)):
        if stream is not None:
            selector.register(stream, selectors.EVENT_READ)
            counts[stream.fileno()] = 0
            outputs[stream.fileno()] = output_fd

    timed_out = False
    overflow = False
    orphaned = False
    exited_at: float | None = None
    try:
        while selector.get_map() and not interrupted:
            now = time.monotonic()
            remaining = deadline - now
            if remaining <= 0:
                timed_out = True
                break
            if exited_at is None and process.poll() is not None:
                exited_at = now
            if exited_at is not None and now - exited_at >= EXIT_GRACE_SECONDS:
                orphaned = True
                break
            for key, _mask in selector.select(min(remaining, POLL_SECONDS)):
                fd = key.fd
                try:
                    chunk = os.read(fd, 8192)
                except OSError:
                    chunk = b""
                if not chunk:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                remaining_bytes = args.max_bytes - counts[fd]
                if remaining_bytes <= 0:
                    overflow = True
                    break
                if len(chunk) > remaining_bytes:
                    write_all(outputs[fd], chunk[:remaining_bytes])
                    counts[fd] = args.max_bytes
                    overflow = True
                    break
                write_all(outputs[fd], chunk)
                counts[fd] += len(chunk)
            if overflow:
                break
        # Both pipes can close before the command exits; its exit code is
        # still the result, so wait for it within the same deadline.
        while not (timed_out or overflow or interrupted) and process.poll() is None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            try:
                process.wait(timeout=min(remaining, POLL_SECONDS))
            except subprocess.TimeoutExpired:
                pass
    finally:
        if process.poll() is None:
            terminate_tree(process)
        elif orphaned:
            terminate_group(process.pid)
        for key in list(selector.get_map().values()):
            try:
                selector.unregister(key.fileobj)
                key.fileobj.close()
            except OSError:
                pass
        selector.close()
        signal.signal(signal.SIGTERM, previous_term)
        signal.signal(signal.SIGINT, previous_int)

    def write_marker(marker: str) -> None:
        used = counts.get(stderr_pipe_fd, 0)
        room = max(0, args.max_bytes - used)
        if room:
            write_all(2, marker.encode()[:room])

    if timed_out:
        write_marker(TIMEOUT_MARKER)
        return 124
    if overflow:
        write_marker(OVERFLOW_MARKER)
        return 125
    if interrupted:
        return 130
    if process.returncode is None:
        return 1
    # A signal-killed child reports -signum; use the shell's 128 + signum so
    # callers can tell a crash (139 for SIGSEGV) from an ordinary failure.
    return 128 - process.returncode if process.returncode < 0 else process.returncode


if __name__ == "__main__":
    raise SystemExit(run(sys.argv[1:]))
