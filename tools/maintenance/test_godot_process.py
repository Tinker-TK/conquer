"""Exercise real child termination and bounded files, including misleading PASS output."""
from pathlib import Path
import os
import sys
import tempfile
import unittest

from godot_process import run_guarded


class ProcessGuardsTest(unittest.TestCase):
    def run_child(self, code, *, timeout=3, limit=65536):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        out = Path(directory.name)
        result = run_guarded([sys.executable, '-u', '-c', code, str(out / 'engine.log')],
                             cwd=out, env=dict(os.environ, PYTHONIOENCODING='utf-8'), log_path=out / 'console.log',
                             engine_log=out / 'engine.log', timeout=timeout, max_log_bytes=limit)
        return result, out

    def test_normal_completion_and_unicode(self):
        result, out = self.run_child("print('PASS: \\u6210\\u529f')")
        self.assertEqual(result.exit_code, 0)
        self.assertFalse(result.stopped)
        self.assertIn('成功', (out / 'console.log').read_text(encoding='utf-8'))

    def test_assertion_stops_a_hung_process(self):
        result, out = self.run_child("import time; print('SCRIPT ERROR: Assertion failed: bad health'); time.sleep(30)")
        self.assertEqual(result.stopped, 'engine error')
        self.assertLess(result.seconds, 3)
        self.assertIn('bad health', result.errors[0])
        self.assertNotEqual(result.exit_code, 0)

    def test_pass_and_zero_exit_do_not_hide_errors(self):
        result, _ = self.run_child("print('SCRIPT ERROR: Assertion failed'); print('PASS')")
        self.assertTrue(result.errors)
        self.assertEqual(result.stopped, 'engine error')

    def test_stdout_flood_is_bounded(self):
        result, out = self.run_child("import os\nwhile True: os.write(1, b'x' * 16384)")
        self.assertIn('log limit', result.stopped)
        self.assertLessEqual((out / 'console.log').stat().st_size, 65536)
        self.assertLess(result.seconds, 3)

    def test_direct_engine_file_flood_is_bounded(self):
        result, out = self.run_child("import sys,time\nwith open(sys.argv[1], 'wb', buffering=0) as f:\n while True: f.write(b'x' * 16384); time.sleep(.001)")
        self.assertIn('log limit', result.stopped)
        self.assertLessEqual((out / 'engine.log').stat().st_size, 65536)
        self.assertIn(b'LOG TRUNCATED', (out / 'engine.log').read_bytes())

    def test_wall_clock_timeout(self):
        result, _ = self.run_child('import time; time.sleep(30)', timeout=.2)
        self.assertIn('timeout', result.stopped)
        self.assertLess(result.seconds, 2)

    def test_combined_engine_and_stdout_budget(self):
        result, out = self.run_child("import os,sys,time\nwith open(sys.argv[1], 'wb', buffering=0) as f:\n while True: f.write(b'x' * 4096); os.write(1,b'x' * 4096); time.sleep(.001)")
        self.assertIn('log limit', result.stopped)
        self.assertLessEqual(sum((out / name).stat().st_size for name in ['console.log', 'engine.log']), 65536)

    def test_known_certificate_warning_is_ignored(self):
        result, _ = self.run_child("print('ERROR: Failed to read the root certificate store.'); print('PASS')")
        self.assertEqual(result.exit_code, 0)
        self.assertFalse(result.errors)
        self.assertFalse(result.stopped)


if __name__ == '__main__':
    unittest.main()
