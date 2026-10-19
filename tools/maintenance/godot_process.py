"""Supervise a Godot process with bounded logs and a wall-clock deadline."""
from pathlib import Path
import codecs
from dataclasses import dataclass
import os
import math
import subprocess
import threading
import time


def is_engine_error(line: str) -> bool:
    return ('ERROR:' in line or 'Assertion failed' in line) and (
        'Failed to read the root certificate store' not in line)


@dataclass
class ProcessResult:
    exit_code: int | None
    seconds: float
    stopped: str
    errors: list[str]


def _cap_log(path: Path, limit: int) -> None:
    """Keep the beginning and end of an engine file that overshot the polling limit."""
    if not path.exists() or path.stat().st_size <= limit:
        return
    notice = b'\n[LOG TRUNCATED: process output limit exceeded]\n'
    half = (limit - len(notice)) // 2
    with path.open('rb') as stream:
        beginning = stream.read(half)
        stream.seek(-half, os.SEEK_END)
        ending = stream.read(half)
    path.write_bytes(beginning + notice + ending)


def run_guarded(command: list[str], *, cwd: Path, env: dict[str, str],
                log_path: Path, engine_log: Path, timeout: float = 60,
                max_log_bytes: int = 16 * 1024 * 1024,
                stop_on_error: bool = True) -> ProcessResult:
    """Stop on engine errors, excessive combined output, or a real-time timeout.

    stdout is drained continuously into a capped file, never accumulated in memory.
    The caller must pass engine_log to Godot with --log-file. Its independent file
    is polled too; any small polling overshoot is trimmed after the child exits.
    """
    if not math.isfinite(timeout) or timeout <= 0 or max_log_bytes < 1024:
        raise ValueError('timeout must be positive and log limit at least 1024 bytes')
    log_path.parent.mkdir(parents=True, exist_ok=True)
    # A reused label must never evaluate an earlier process's engine output.
    engine_log.write_bytes(b'')
    started = time.monotonic()
    overflow = threading.Event()
    failure = threading.Event()
    errors: list[str] = []
    captured = 0
    stopped = ''

    def record(line: str) -> None:
        if is_engine_error(line):
            if len(errors) < 32 and line[:2048] not in errors:
                errors.append(line[:2048])
            failure.set()

    flags = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    with log_path.open('wb') as output:
        try:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, bufsize=0, **flags)
        except OSError as exc:
            message = 'Could not launch process: ' + str(exc)
            output.write(message.encode('utf-8', errors='replace')[:max_log_bytes])
            return ProcessResult(None, round(time.monotonic() - started, 2),
                                 'launch failed', [message])

        def consume() -> None:
            nonlocal captured
            decoder = codecs.getincrementaldecoder('utf-8')(errors='replace')
            pending = ''
            try:
                while chunk := process.stdout.read(16384):
                    remaining = max(0, max_log_bytes - captured)
                    output.write(chunk[:remaining])
                    captured += len(chunk)
                    if captured >= max_log_bytes:
                        overflow.set()
                    pending += decoder.decode(chunk)
                    lines = pending.split('\n')
                    pending = lines.pop()
                    for line in lines:
                        record(line.rstrip('\r'))
                    # A child that never writes newlines must also stay bounded.
                    if len(pending) > 4096:
                        record(pending)
                        pending = pending[-256:]
                record(pending + decoder.decode(b'', final=True))
            except (OSError, ValueError) as exc:
                errors.append('Could not capture process output: ' + str(exc))
                failure.set()

        reader = threading.Thread(target=consume, daemon=True)
        reader.start()
        try:
            while process.poll() is None:
                if stop_on_error and failure.is_set():
                    stopped = 'engine error'
                elif overflow.is_set() or captured + engine_log.stat().st_size >= max_log_bytes:
                    stopped = 'log limit exceeded (%d bytes)' % max_log_bytes
                elif time.monotonic() - started >= timeout:
                    stopped = 'timeout after %g seconds' % timeout
                if stopped:
                    process.kill()
                    break
                time.sleep(0.02)
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            reader.join(timeout=5)
            process.stdout.close()
        # Also inspect fast-exiting children: quit(0)/PASS cannot mask an error.
        if not stopped and stop_on_error and failure.is_set():
            stopped = 'engine error'
        if not stopped and (overflow.is_set() or captured + engine_log.stat().st_size >= max_log_bytes):
            stopped = 'log limit exceeded (%d bytes)' % max_log_bytes
    # Keep the persisted pair within the combined budget, including polling overshoot.
    engine_budget = min(engine_log.stat().st_size, max_log_bytes // 2)
    console_budget = min(log_path.stat().st_size, max_log_bytes - engine_budget)
    _cap_log(log_path, console_budget)
    _cap_log(engine_log, max_log_bytes - log_path.stat().st_size)
    return ProcessResult(process.returncode, round(time.monotonic() - started, 2), stopped, errors)
