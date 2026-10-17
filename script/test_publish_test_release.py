from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from subprocess import CompletedProcess
import tempfile
import unittest
import zipfile

from publish_test_release import publish_release, release_metadata, release_notes


class TestReleasePublication(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sha = 'a' * 40
        self.metadata = release_metadata(self.sha, 47, datetime(2026, 10, 16, 18, tzinfo=timezone.utc))
        self.archive = Path(self.temp.name) / 'source.zip'
        with zipfile.ZipFile(self.archive, 'w') as package:
            package.writestr('oasx-release.txt', self.sha)
            package.writestr('oasx-channel.txt', 'test')
        self.calls = []
        self.notes = []

    def gh(self, *arguments, check=True):
        self.calls.append(arguments)
        if arguments[:2] == ('release', 'view'):
            return CompletedProcess(arguments, 1, '', '')
        if '--notes-file' in arguments:
            self.notes.append(Path(arguments[arguments.index('--notes-file') + 1]).read_text(encoding='utf-8'))
        if arguments[:2] == ('release', 'upload'):
            archive = Path(arguments[3])
            self.assertEqual(archive.read_bytes(), self.archive.read_bytes())
        if arguments[0] == 'api':
            return CompletedProcess(arguments, 0, json.dumps({'assets': [
                {'name': self.metadata.compatibility_asset},
                {'name': f'oasx_test_{"b" * 40}_windows.zip'},
                {'name': 'unrelated.txt'},
            ]}), '')
        return CompletedProcess(arguments, 0, '', '')

    def test_filename_matches_personal_release_pattern(self):
        self.assertEqual(self.metadata.asset, 'oasx_v2026.10.17.47_windows.zip')
        self.assertEqual(self.metadata.tag, 'test-2026.10.17.47')

    def test_notes_use_the_actual_code_version(self):
        notes = release_notes('# 2026-10-17（测试版）\n\n适用版本：`old`。\n\n- 修复启动显示。', self.metadata)
        self.assertIn('代码版本：`aaaaaaa`', notes)
        self.assertNotIn('old', notes)
        self.assertIn('- 修复启动显示。', notes)

    def test_rejects_wrong_or_stable_package_before_publishing(self):
        for version, channel in [('b' * 40, 'test'), (self.sha, 'stable')]:
            with zipfile.ZipFile(self.archive, 'w') as package:
                package.writestr('oasx-release.txt', version)
                package.writestr('oasx-channel.txt', channel)
            with self.assertRaises(ValueError):
                publish_release('neko-mm/OASX', self.archive, '- 更新', self.metadata, self.gh)
            self.assertEqual(self.calls, [])

    def test_new_release_is_published_only_after_upload(self):
        publish_release('neko-mm/OASX', self.archive, '- 更新', self.metadata, self.gh)
        create = next(call for call in self.calls if call[:3] == ('release', 'create', self.metadata.tag))
        self.assertIn('--draft', create)
        self.assertIn('--prerelease', create)
        self.assertIn('--latest=false', create)
        upload = next(i for i, call in enumerate(self.calls) if call[:3] == ('release', 'upload', self.metadata.tag))
        publish = next(i for i, call in enumerate(self.calls) if call[:3] == ('release', 'edit', self.metadata.tag))
        self.assertLess(upload, publish)

    def test_old_launcher_endpoint_and_filename_remain_available(self):
        publish_release('neko-mm/OASX', self.archive, '- 更新', self.metadata, self.gh)
        upload = next(call for call in self.calls if call[:3] == ('release', 'upload', 'oasx-master'))
        self.assertEqual(Path(upload[3]).name, self.metadata.compatibility_asset)
        deleted = [call[3] for call in self.calls if call[:2] == ('release', 'delete-asset')]
        self.assertEqual(deleted, [f'oasx_test_{"b" * 40}_windows.zip'])

    def test_upload_failure_does_not_publish_empty_release(self):
        def failed_upload(*args, check=True):
            if args[:2] == ('release', 'upload'):
                raise RuntimeError('上传失败')
            return self.gh(*args, check=check)
        with self.assertRaisesRegex(RuntimeError, '上传失败'):
            publish_release('neko-mm/OASX', self.archive, '- 更新', self.metadata, failed_upload)
        self.assertFalse(any(call[:2] == ('release', 'edit') for call in self.calls))

    def test_matching_compatibility_asset_is_not_replaced(self):
        def existing_asset(*args, check=True):
            if args[0] == 'api':
                return CompletedProcess(args, 0, json.dumps({'assets': [{
                    'name': self.metadata.compatibility_asset,
                    'digest': 'sha256:' + hashlib.sha256(self.archive.read_bytes()).hexdigest(),
                }]}), '')
            return self.gh(*args, check=check)
        publish_release('neko-mm/OASX', self.archive, '- 更新', self.metadata, existing_asset)
        self.assertFalse(any(call[:3] == ('release', 'upload', 'oasx-master') for call in self.calls))


if __name__ == '__main__':
    unittest.main()
