"""Check simultaneous invocations do not share active logs or user files."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get('GODOT_EXE', 'D:/Godot4/Godot_v4.6.2-stable_win64_console.exe'))


@unittest.skipUnless(GODOT.is_file(), 'Godot executable is unavailable')
class ConcurrentChecksTest(unittest.TestCase):
    def test_same_label_has_distinct_process_logs_and_userdata(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            command = [sys.executable, '-B', str(ROOT / 'tools/maintenance/run_checks.py'),
                       '--godot', str(GODOT), '--out', str(out), '--checks', 'new-unit']
            flags = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
            children = [subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         env=dict(os.environ, PYTHONIOENCODING='utf-8'), **flags) for _ in range(2)]
            reports = []
            try:
                for process in children:
                    log = process.communicate(timeout=20)[0].decode('utf-8')
                    self.assertEqual(process.returncode, 0, log)
                    reports.append(json.loads(log.strip().splitlines()[-1]))
            finally:
                for process in children:
                    if process.poll() is None:
                        process.kill()
                    process.communicate(timeout=5)
            self.assertNotEqual(reports[0]['session_id'], reports[1]['session_id'])
            for report in reports:
                self.assertTrue((out / 'userdata' / report['session_id']).is_dir())
            self.assertTrue(json.loads((out / 'results.json').read_text(encoding='utf-8'))[0]['passed'])
            self.assertIn('NEW_UNIT_ENHANCEMENT_LOGIC_PASS', (out / 'new-unit.engine.log').read_text(encoding='utf-8'))
            self.assertFalse(list(out.glob('.*.log')))


if __name__ == '__main__':
    unittest.main()
