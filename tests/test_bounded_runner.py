from __future__ import annotations

import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "run_bounded.py"


def bounded(*command: str, max_bytes: int = 4096, max_seconds: float = 5) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--max-bytes",
            str(max_bytes),
            "--max-seconds",
            str(max_seconds),
            "--",
            *command,
        ],
        capture_output=True,
        timeout=max_seconds + 3,
        check=False,
    )


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


if __name__ == "__main__":
    unittest.main()
