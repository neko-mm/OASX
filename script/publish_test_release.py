import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile


@dataclass(frozen=True)
class ReleaseMetadata:
    sha: str
    version: str

    @property
    def tag(self):
        return f'test-{self.version[1:]}'

    @property
    def asset(self):
        return f'oasx_{self.version}_windows.zip'

    @property
    def compatibility_asset(self):
        return f'oasx_test_{self.sha}_windows.zip'


def release_metadata(sha, run_number, now=None):
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or run_number < 1:
        raise ValueError('源代码版本或构建序号无效')
    local = (now or datetime.now(timezone.utc)).astimezone(timezone(timedelta(hours=8)))
    return ReleaseMetadata(sha, f'v{local.year}.{local.month}.{local.day}.{run_number}')


def release_notes(source, metadata):
    lines = source.splitlines()
    if lines and lines[0].startswith('# '):
        lines.pop(0)
    lines = [line for line in lines if not line.startswith('适用版本：')]
    body = '\n'.join(lines).strip()
    return f'# OASX 测试版 {metadata.version}\n\n代码版本：`{metadata.sha[:7]}`。\n\n{body}\n'


def validate_archive(archive, sha):
    with zipfile.ZipFile(archive) as package:
        version = package.read('oasx-release.txt').decode('utf-8-sig').strip()
        channel = package.read('oasx-channel.txt').decode('utf-8-sig').strip()
    if version != sha or channel != 'test':
        raise ValueError('安装包版本或更新渠道与测试版发布信息不一致')


def run_gh(*arguments, check=True):
    return subprocess.run(['gh', *arguments], check=check, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def publish_release(repository, archive, notes, metadata, gh=run_gh):
    validate_archive(archive, metadata.sha)
    with tempfile.TemporaryDirectory(prefix='oasx-publish-') as temp:
        work = Path(temp)
        asset = work / metadata.asset
        compatibility = work / metadata.compatibility_asset
        note_file = work / 'release-notes.md'
        shutil.copyfile(archive, asset)
        shutil.copyfile(archive, compatibility)
        note_file.write_text(release_notes(notes, metadata), encoding='utf-8')

        exists = gh('release', 'view', metadata.tag, '--repo', repository, check=False)
        if exists.returncode != 0:
            gh('release', 'create', metadata.tag, '--repo', repository,
               '--target', metadata.sha, '--title', f'OASX 测试版 {metadata.version}',
               '--notes-file', str(note_file), '--draft', '--prerelease', '--latest=false')
        gh('release', 'upload', metadata.tag, str(asset), '--repo', repository, '--clobber')
        gh('release', 'edit', metadata.tag, '--repo', repository,
           '--title', f'OASX 测试版 {metadata.version}', '--notes-file', str(note_file),
           '--draft=false', '--prerelease', '--latest=false')

        # 旧启动器只识别固定入口中的 oasx_test_<提交号> 文件。
        channel = gh('release', 'view', 'oasx-master', '--repo', repository, check=False)
        if channel.returncode != 0:
            gh('release', 'create', 'oasx-master', '--repo', repository,
               '--target', metadata.sha, '--title', 'OASX 测试版更新通道',
               '--notes-file', str(note_file), '--prerelease', '--latest=false')
        assets = gh('api', f'repos/{repository}/releases/tags/oasx-master')
        previous_assets = json.loads(assets.stdout)['assets']
        digest = 'sha256:' + hashlib.sha256(compatibility.read_bytes()).hexdigest()
        already_uploaded = any(previous['name'] == metadata.compatibility_asset and
                               previous.get('digest') == digest for previous in previous_assets)
        if not already_uploaded:
            gh('release', 'upload', 'oasx-master', str(compatibility),
               '--repo', repository, '--clobber')
        gh('release', 'edit', 'oasx-master', '--repo', repository,
           '--title', 'OASX 测试版更新通道', '--notes-file', str(note_file))
        for previous in previous_assets:
            name = previous['name']
            if name.startswith('oasx_test_') and name != metadata.compatibility_asset:
                gh('release', 'delete-asset', 'oasx-master', name,
                   '--repo', repository, '--yes')
    return metadata.tag


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', required=True)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--run-number', required=True, type=int)
    parser.add_argument('--notes', type=Path, default=Path('CHANGELATEST.md'))
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--archive', type=Path)
    source.add_argument('--package-dir', type=Path)
    args = parser.parse_args()
    metadata = release_metadata(args.sha, args.run_number)
    with tempfile.TemporaryDirectory(prefix='oasx-package-') as temp:
        archive = args.archive
        if archive is None:
            archive = Path(shutil.make_archive(str(Path(temp) / 'package'), 'zip', args.package_dir))
        tag = publish_release(args.repo, archive, args.notes.read_text(encoding='utf-8'), metadata)
        print(f'https://github.com/{args.repo}/releases/tag/{tag}')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error))
