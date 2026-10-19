"""Exercise packaging failures, destination protection and exclusive build locking."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main
from unittest.mock import patch
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_game as packager

class PackagingTest(TestCase):
    def test_source_directories_cannot_be_output(self):
        for path in [packager.PROJECT, packager.PROJECT / 'assets', packager.PROJECT.parent]:
            with self.subTest(path=path), self.assertRaises(packager.BuildError):
                packager.output_location(str(path))
        self.assertEqual(packager.output_location(str(packager.PROJECT / 'builds')), packager.PROJECT / 'builds')

    def test_failed_export_is_not_reported_as_success(self):
        with TemporaryDirectory() as directory:
            log = Path(directory) / 'export.log'
            def failed(command, **kwargs):
                kwargs['stdout'].write(b'ERROR: missing release template\n')
                return subprocess.CompletedProcess(command, 1)
            with patch.object(packager.subprocess, 'run', side_effect=failed):
                with self.assertRaisesRegex(packager.BuildError, 'missing release template'):
                    packager.run_godot('Godot', [], log)

    def test_error_log_rejects_zero_exit_code(self):
        with TemporaryDirectory() as directory:
            def misleading(command, **kwargs):
                kwargs['stdout'].write(b'SCRIPT ERROR: failed dependency\n')
                return subprocess.CompletedProcess(command, 0)
            with patch.object(packager.subprocess, 'run', side_effect=misleading):
                with self.assertRaisesRegex(packager.BuildError, 'failed dependency'):
                    packager.run_godot('Godot', [], Path(directory) / 'export.log')

    def test_incomplete_windows_export_never_creates_final_zip(self):
        with TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / 'Conquer.exe').write_bytes(b'incomplete')
            destination = folder / 'Windows.zip'
            with self.assertRaises(packager.BuildError):
                packager.finish_windows(folder, destination, 'test', 'license')
            self.assertFalse(destination.exists())

    def test_concurrent_builds_are_rejected_and_lock_releases(self):
        with packager.project_lock():
            with self.assertRaises(packager.BuildError):
                with packager.project_lock():
                    self.fail('Concurrent packaging must not proceed')
        with packager.project_lock():
            pass

if __name__ == '__main__':
    main()
