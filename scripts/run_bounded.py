#!/usr/bin/env python3
"""Run one command with bounded output, deadline, and process-tree cleanup."""

from __future__ import annotations

import argparse
import os
import selectors
import signal
import subprocess
import sys
import time

TIMEOUT_MARKER = "omarchy-protonvpn: command timed out\n"
OVERFLOW_MARKER = "omarchy-protonvpn: command output exceeded the safety limit\n"


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


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-bytes", type=int, default=262_144)
    parser.add_argument("--max-seconds", type=float, default=30)
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

    deadline = time.monotonic() + args.max_seconds
    timed_out = False
    overflow = False
    try:
        while selector.get_map() and not interrupted:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            events = selector.select(remaining)
            if not events:
                timed_out = True
                break
            for key, _mask in events:
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
    finally:
        if process.poll() is None:
            terminate_tree(process)
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
