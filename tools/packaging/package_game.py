"""Build shareable release ZIPs; used by the Godot one-click packaging panel."""
from pathlib import Path
from contextlib import contextmanager
from datetime import datetime
import argparse
import hashlib
import json
import os
import plistlib
import re
import stat
import struct
import subprocess
import sys
import uuid
import zipfile

PROJECT = Path(__file__).resolve().parents[2]
PRESETS = {'windows': 'Windows Desktop', 'macos': 'macOS'}
COMMON_README = '''CONQUER! 征服战线 · 朋友测试版
打包时间：{stamp}

启动游戏 → 开始征途 → 选择地图起点进入战斗。
战场视野：WASD 移动镜头；鼠标中键拖动；滚轮缩放。
设置中可以调整音量、全屏和减少动效。
路线工坊支持导入路线 JSON；也可直接使用内置地图。
反馈问题时，请附上操作步骤、截图、系统版本和显卡/芯片型号。
'''
WINDOWS_README = '''
Windows 启动：
1. 解压整个 ZIP，再双击 Conquer.exe。不需要安装 Godot。
2. Conquer.exe 和 Conquer.pck 必须保持在同一个文件夹。
3. 遇到显卡报错或黑屏，可双击 Start-Compatibility.cmd 使用 OpenGL 模式。
本包为 Windows x64 版本。
日志位置：%APPDATA%\\Godot\\app_userdata\\ballsprite\\logs\\godot.log
'''
MAC_README = '''
Mac 启动：
1. 在 Mac 上直接双击 ZIP，用系统自带归档工具解压。
2. 双击 {app}；也可以拖进“应用程序”文件夹。不需要安装 Godot。
3. 本测试包使用临时签名（ad-hoc），尚未经过 Apple 公证。
   首次启动如被拦截，请先尝试打开一次，再到“系统设置 → 隐私与安全性”
   点击针对本游戏的“仍要打开”，然后确认“打开”。
   Apple 官方说明：https://support.apple.com/zh-cn/102445
4. 遇到显卡问题，可使用同目录 Start-Compatibility.command。
本包同时包含 Intel 和 Apple Silicon 两种架构。
请直接传递 ZIP 并在 Mac 上解压，以保留程序可执行权限。
日志位置：~/Library/Application Support/Godot/app_userdata/ballsprite/logs/godot.log
'''

class BuildError(Exception):
    pass

def output_location(value: str) -> Path:
    path = Path(value).expanduser().resolve()
    # Never add .gdignore to, or put generated files into, a source directory.
    if path.is_relative_to(PROJECT) and not path.is_relative_to(PROJECT / 'builds'):
        raise BuildError('项目内请使用 builds 目录；也可以选择项目外的目录。')
    if PROJECT.is_relative_to(path):
        raise BuildError('输出目录不能是项目目录或其上级目录，请选择 builds 或项目外的目录。')
    return path

def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    # Atomic replacement lets the editor read progress while the build runs.
    os.replace(temporary, path)

@contextmanager
def project_lock():
    path = PROJECT / '.maintenance' / 'packaging' / 'build.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as handle:
        if path.stat().st_size == 0:
            handle.write(b'0')
            handle.flush()
        handle.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise BuildError('已有打包任务正在运行，请等待完成后再开始。') from error
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == 'nt':
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle, fcntl.LOCK_UN)

def run_godot(godot: str, arguments: list[str], log: Path) -> str:
    command = [godot, '--headless', '--path', str(PROJECT), *arguments]
    kwargs = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    with log.open('wb') as output:
        process = subprocess.run(command, cwd=PROJECT, stdout=output, stderr=subprocess.STDOUT,
                                 timeout=900, **kwargs)
    text = log.read_text(encoding='utf-8', errors='replace')
    errors = [line for line in text.splitlines() if ('ERROR:' in line or 'SCRIPT ERROR:' in line)
              and 'Failed to read the root certificate store' not in line]
    if process.returncode != 0 or errors:
        detail = '\n'.join(errors[:6]) or text[-2000:]
        raise BuildError(f'Godot 执行失败（退出码 {process.returncode}）。\n{detail}\n日志：{log}')
    return text

def notices(godot: str, logs: Path) -> str:
    destination = logs / 'godot-licenses.txt'
    text = run_godot(godot, ['--script', 'res://tools/packaging/license_dump.gd', '--', str(destination), '--no-mcp-server'], logs / 'licenses.log')
    if 'LICENSE_DUMP_PASS' not in text or not destination.is_file():
        raise BuildError('引擎许可说明生成失败，请检查 licenses.log。')
    parts = [destination.read_text(encoding='utf-8')]
    for relative in ['assets/fonts/numbers/README.md', 'assets/fonts/numbers/lilita_one/OFL.txt',
                     'assets/fonts/numbers/jersey10/OFL.txt', 'assets/effect/godot_vfx_library/LICENSE',
                     'assets/effect/pixel_vfx/README.md', 'assets/audio/combat/CREDITS.md',
                     'assets/audio/combat/licenses/kenney-rpg.txt',
                     'assets/audio/combat/licenses/kenney-impact.txt',
                     'assets/audio/library/CREDITS.md',
                     'assets/audio/library/licenses/qubodup-notes.txt',
                     'assets/audio/library/licenses/kenney-impact-full.txt',
                     'assets/audio/library/licenses/kenney-rpg-full.txt']:
        source = PROJECT / relative
        if source.is_file():
            parts.append('\n\n' + '=' * 72 + '\n' + relative + '\n\n' + source.read_text(encoding='utf-8-sig'))
    return '\n'.join(parts)

def verify_zip(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise BuildError(f'ZIP 完整性校验失败：{bad}')

def finish_windows(folder: Path, destination: Path, stamp: str, license_text: str) -> None:
    if not (folder / 'Conquer.exe').is_file() or not (folder / 'Conquer.pck').is_file():
        raise BuildError('Windows 导出未产生 exe 和 pck；请保持 Windows 预设使用外置 PCK。')
    (folder / 'README-测试说明.txt').write_text(COMMON_README.format(stamp=stamp) + WINDOWS_README, encoding='utf-8-sig')
    (folder / 'THIRD-PARTY-NOTICES.txt').write_text(license_text, encoding='utf-8')
    (folder / 'Start-Compatibility.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "%~dp0Conquer.exe" --rendering-method gl_compatibility --rendering-driver opengl3\n', encoding='ascii', newline='\r\n')
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for source in sorted(folder.rglob('*')):
            if source.is_file():
                archive.write(source, folder.name + '/' + source.relative_to(folder).as_posix())
    verify_zip(destination)

def verify_mac(path: Path) -> tuple[str, str]:
    with zipfile.ZipFile(path) as archive:
        plist_paths = [name for name in archive.namelist() if name.endswith('.app/Contents/Info.plist')]
        if len(plist_paths) != 1:
            raise BuildError('Mac ZIP 中没有唯一的 .app 程序。')
        app = plist_paths[0].removesuffix('/Contents/Info.plist')
        info = plistlib.loads(archive.read(plist_paths[0]))
        executable = app + '/Contents/MacOS/' + info['CFBundleExecutable']
        if not archive.getinfo(executable).external_attr >> 16 & stat.S_IXUSR:
            raise BuildError('Mac 程序缺少可执行权限，请从 Godot 直接导出 ZIP。')
        with archive.open(executable) as binary:
            header = binary.read(48)
        if len(header) < 48 or header[:4] != bytes.fromhex('cafebabe') or struct.unpack_from('>I', header, 4)[0] != 2:
            raise BuildError('Mac 程序不是包含两种架构的 universal 包。')
        cpus = {struct.unpack_from('>I', header, offset)[0] for offset in [8, 28]}
        if cpus != {0x01000007, 0x0100000C}:
            raise BuildError('Mac 程序没有同时包含 Intel 和 Apple Silicon 架构。')
        if app + '/Contents/_CodeSignature/CodeResources' not in archive.namelist():
            raise BuildError('Mac 程序缺少签名，请启用 Mac 预设内的临时签名。')
        return app, executable

def finish_mac(path: Path, stamp: str, license_text: str) -> None:
    app, executable = verify_mac(path)
    # Preserve the original archive entries, symlinks, modes and signed app bytes.
    with zipfile.ZipFile(path, 'a', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr('README-测试说明.txt', (COMMON_README.format(stamp=stamp) + MAC_README.format(app=app)).encode('utf-8-sig'))
        archive.writestr('THIRD-PARTY-NOTICES.txt', license_text)
        launcher = zipfile.ZipInfo('Start-Compatibility.command')
        launcher.create_system = 3
        launcher.external_attr = (stat.S_IFREG | 0o755) << 16
        launcher.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(launcher, '#!/bin/sh\nSCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"\nexec "$SCRIPT_DIR/' + executable + '" --rendering-method gl_compatibility --rendering-driver opengl3\n')
    verify_zip(path)
    verify_mac(path)

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def build(args, report: dict) -> None:
    output = output_location(args.output)
    godot = Path(args.godot).expanduser().resolve()
    if not godot.is_file():
        raise BuildError('未找到 Godot 程序，请从 Godot 编辑器的一键打包按钮启动。')
    date = datetime.now()
    job = output / date.strftime('%Y-%m-%d') / (date.strftime('%H%M%S') + '-' + uuid.uuid4().hex[:6])
    logs = job / 'logs'
    logs.mkdir(parents=True)
    if output.is_relative_to(PROJECT):
        (output / '.gdignore').touch(exist_ok=True)
    report['folder'] = str(job)
    def progress(message):
        report['status'] = message
        write_json(Path(args.result), report)
        print(message, flush=True)
    progress('正在准备项目和打包说明…')
    version = subprocess.check_output([str(godot), '--version'], timeout=15).decode('utf-8', errors='replace').strip()
    version_match = re.match(r'4\.(\d+)\.', version)
    if version_match is None or int(version_match.group(1)) < 6:
        raise BuildError('请使用 Godot 4.6 或更新的 Godot 4 版本打开项目后打包。')
    license_text = notices(str(godot), logs)
    selected = ['windows', 'macos'] if args.platform == 'both' else [args.platform]
    for target in selected:
        label = 'Windows' if target == 'windows' else 'Mac'
        progress(f'正在导出 {label}，请稍候…')
        destination = job / ('Conquer-Windows-x64.zip' if target == 'windows' else 'Conquer-macOS-universal.zip')
        pending = destination.with_name(destination.stem + '.building.zip')
        if target == 'windows':
            folder = job / 'Conquer-Windows-x64'
            folder.mkdir()
            export_file = folder / 'Conquer.exe'
        else:
            export_file = pending
        export_log = logs / (target + '-export.log')
        report['log'] = str(export_log)
        run_godot(str(godot), ['--export-release', PRESETS[target], str(export_file)], export_log)
        progress(f'正在压缩和检查 {label} ZIP…')
        if target == 'windows':
            finish_windows(folder, pending, date.isoformat(timespec='seconds'), license_text)
        else:
            finish_mac(pending, date.isoformat(timespec='seconds'), license_text)
        pending.rename(destination)
        report['packages'].append(str(destination))
    checksums = [sha256(Path(path)) + '  ' + Path(path).name for path in report['packages']]
    (job / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='ascii')
    report.update(ok=True, status='打包完成', engine=version, mode='release')
    write_json(job / 'build-info.json', report)
    progress('打包完成')

def main(argv=None):
    # Godot reads subprocess output as UTF-8, including on Chinese Windows.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['windows', 'macos', 'both'], required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', default=str(PROJECT / 'builds'))
    parser.add_argument('--result', required=True)
    args = parser.parse_args(argv)
    report = {'ok': False, 'status': '正在准备', 'folder': '', 'packages': []}
    try:
        with project_lock():
            build(args, report)
    except (BuildError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, ValueError, KeyError) as error:
        report.update(ok=False, status='打包失败', error=str(error))
        print(str(error), file=sys.stderr)
    write_json(Path(args.result), report)
    return 0 if report['ok'] else 1

if __name__ == '__main__':
    sys.exit(main())
