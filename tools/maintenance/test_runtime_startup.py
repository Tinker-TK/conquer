"""Godot integration tests for startup rejection and invalid-unit quarantine."""
from pathlib import Path
import os
import tempfile
import unittest

from godot_process import is_engine_error, run_guarded


ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get('GODOT_EXE', 'D:/Godot4/Godot_v4.6.2-stable_win64_console.exe'))


@unittest.skipUnless(GODOT.is_file(), 'Godot executable is unavailable')
class StartupContractTest(unittest.TestCase):
    def run_godot(self, script, flags):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        out = Path(directory.name)
        env = dict(os.environ, APPDATA=str(out), LOCALAPPDATA=str(out), TEMP=str(out), TMP=str(out))
        engine_log = out / 'engine.log'
        command = [str(GODOT), '--headless', '--path', str(ROOT), '--fixed-fps', '60',
                   '--log-file', str(engine_log), '--script', 'res://' + script,
                   '--', '--no-mcp-server', *flags]
        result = run_guarded(command, cwd=ROOT, env=env, log_path=out / 'console.log',
                             engine_log=engine_log, timeout=10, max_log_bytes=1024 * 1024,
                             stop_on_error=False)
        return result, engine_log.read_text(encoding='utf-8', errors='replace')

    def test_unknown_regression_never_runs_smoke(self):
        result, log = self.run_godot('tests/card_framework_test_runner.gd', ['--does-not-exist-regression'])
        self.assertEqual(result.exit_code, 2)
        self.assertIn('UNKNOWN_REGRESSION', log)
        self.assertNotIn('CARD_FRAMEWORK_SMOKE_PASS', log)

    def test_missing_global_stops_with_one_diagnostic(self):
        result, log = self.run_godot('tests/fixtures/runtime_failure_runner.gd', ['--missing-global'])
        self.assertEqual(result.exit_code, 1)
        self.assertEqual(log.count('RUNTIME_STARTUP_FAILED:'), 1)
        self.assertNotIn('Invalid access', log)

    def test_missing_unit_data_is_rejected_without_followup_errors(self):
        self.assert_unit_rejection('--missing-data')

    def test_missing_required_child_is_rejected_without_followup_errors(self):
        self.assert_unit_rejection('--missing-sprite')

    def test_entry_watchdog_uses_a_wall_clock_deadline(self):
        result, log = self.run_godot('tests/card_framework_test_runner.gd',
                                     ['--game-session-regression', '--test-timeout=0.05'])
        self.assertEqual(result.exit_code, 1)
        self.assertIn('TEST_TIMEOUT: wall-clock deadline exceeded', log)
        self.assertLess(result.seconds, 3)

    def test_legacy_session_entry_still_uses_the_safe_loader(self):
        result, log = self.run_godot('tests/game_session_smoke.gd', [])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('GAME_SESSION_SMOKE_PASS', log)
        self.assertFalse(result.errors)

    def assert_unit_rejection(self, flag):
        result, log = self.run_godot('tests/fixtures/runtime_failure_runner.gd', [flag])
        self.assertEqual(result.exit_code, 1)
        self.assertEqual(log.count('UNIT_INITIALIZATION_FAILED:'), 1)
        errors = [line for line in log.splitlines() if is_engine_error(line)]
        self.assertEqual(len(errors), 1, errors)
        self.assertIn('rejected=true; registered=false; alive=false', log)
        self.assertIn('UNIT_REJECTION_CLEANUP: freed=true', log)


if __name__ == '__main__':
    unittest.main()
