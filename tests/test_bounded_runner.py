from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "run_bounded.py"


def runner_command(*command: str, max_bytes: int = 4096, max_seconds: float = 5, lock: bool = False) -> list[str]:
    return [
        sys.executable,
        str(RUNNER),
        "--max-bytes",
        str(max_bytes),
        "--max-seconds",
        str(max_seconds),
        *(["--lock"] if lock else []),
        "--",
        *command,
    ]


def bounded(
    *command: str,
    max_bytes: int = 4096,
    max_seconds: float = 5,
    lock: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        runner_command(*command, max_bytes=max_bytes, max_seconds=max_seconds, lock=lock),
        capture_output=True,
        timeout=max_seconds + 3,
        check=False,
        env=env,
    )


def env_with_runtime(runtime: str | None) -> dict[str, str]:
    env = os.environ.copy()
    env.pop("XDG_RUNTIME_DIR", None)
    if runtime is not None:
        env["XDG_RUNTIME_DIR"] = runtime
    return env


class BoundedRunnerTests(unittest.TestCase):
    def test_preserves_output_and_exit_code(self) -> None:
        result = bounded(sys.executable, "-c", "import sys; print('ok'); print('bad', file=sys.stderr); raise SystemExit(7)")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, b"ok\n")
        self.assertEqual(result.stderr, b"bad\n")

    def test_reports_a_crash_after_output_as_128_plus_signal(self) -> None:
        result = bounded(
            sys.executable,
            "-c",
            "import os,signal,sys; print('Status: Connected'); sys.stdout.flush(); os.kill(os.getpid(), signal.SIGSEGV)",
        )
        self.assertEqual(result.returncode, 139)
        self.assertEqual(result.stdout, b"Status: Connected\n")

    def test_forces_stable_non_colored_output(self) -> None:
        result = bounded(
            sys.executable,
            "-c",
            "import os; print(os.environ.get('LC_ALL')); print(os.environ.get('NO_COLOR'))",
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"C\n1\n")

    def test_caps_a_producer_while_it_runs(self) -> None:
        result = bounded(sys.executable, "-c", "print('A' * 300000)")
        self.assertEqual(result.returncode, 125)
        self.assertLessEqual(len(result.stdout), 4096)
        self.assertLessEqual(len(result.stderr), 4096)
        self.assertIn(b"safety limit", result.stderr)

    def test_caps_stderr_including_the_runner_marker(self) -> None:
        result = bounded(sys.executable, "-c", "import sys; print('E' * 300000, file=sys.stderr)")
        self.assertEqual(result.returncode, 125)
        self.assertLessEqual(len(result.stderr), 4096)

    def test_times_out_and_reaps_descendants(self) -> None:
        marker = Path(tempfile.mkdtemp()) / "survived"
        script = (
            "import subprocess,sys,time; "
            "subprocess.Popen(['sleep','20']); "
            "time.sleep(2); "
            "open(sys.argv[1],'w').write('alive')"
        )
        started = time.monotonic()
        result = bounded(sys.executable, "-c", script, str(marker), max_seconds=0.3)
        self.assertEqual(result.returncode, 124)
        self.assertLess(time.monotonic() - started, 2)
        time.sleep(2)
        self.assertFalse(marker.exists())

    def test_waits_for_the_exit_code_after_the_pipes_close(self) -> None:
        script = "import os,time; os.close(1); os.close(2); time.sleep(0.3); raise SystemExit(3)"
        result = bounded(sys.executable, "-c", script)
        self.assertEqual(result.returncode, 3)

    def test_returns_promptly_when_a_background_process_holds_the_pipes(self) -> None:
        marker = Path(tempfile.mkdtemp()) / "survived"
        script = f"echo done; (sleep 2; echo alive > '{marker}') & exit 0"
        started = time.monotonic()
        result = bounded("/bin/sh", "-c", script, max_seconds=10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"done\n")
        self.assertLess(time.monotonic() - started, 2)
        time.sleep(2.5)
        self.assertFalse(marker.exists())

    def test_lock_serializes_runs(self) -> None:
        runtime = tempfile.mkdtemp()
        log = Path(runtime) / "log"
        script = (
            "import sys,time; "
            "open(sys.argv[1],'a').write('start\\n'); "
            "time.sleep(0.4); "
            "open(sys.argv[1],'a').write('end\\n')"
        )
        command = runner_command(sys.executable, "-c", script, str(log), lock=True)
        env = env_with_runtime(runtime)
        first = subprocess.Popen(command, env=env)
        second = subprocess.Popen(command, env=env)
        self.assertEqual(first.wait(timeout=8), 0)
        self.assertEqual(second.wait(timeout=8), 0)
        self.assertEqual(log.read_text(), "start\nend\nstart\nend\n")
        self.assertEqual(os.stat(Path(runtime) / "omarchy-protonvpn.lock").st_mode & 0o777, 0o600)

    def test_lock_wait_counts_toward_the_deadline(self) -> None:
        runtime = tempfile.mkdtemp()
        env = env_with_runtime(runtime)
        holder = subprocess.Popen(runner_command("sleep", "3", max_seconds=5, lock=True), env=env)
        try:
            time.sleep(0.3)
            started = time.monotonic()
            result = bounded("true", max_seconds=0.5, lock=True, env=env)
            self.assertEqual(result.returncode, 124)
            self.assertIn(b"timed out", result.stderr)
            self.assertLess(time.monotonic() - started, 2)
        finally:
            holder.terminate()
            holder.wait(timeout=5)

    def test_lock_without_a_runtime_dir_runs_unlocked(self) -> None:
        result = bounded("echo", "ok", lock=True, env=env_with_runtime(None))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"ok\n")


if __name__ == "__main__":
    unittest.main()
