"""ElevenLabs 音效接口的最小客户端：只用标准库，失败信息直白，便于批量重跑。

免费档额度很小（约 1 万 credits/月，指定时长时按 40 credits/秒计），
所以每条提示词都显式给 duration，并在本地缓存，重跑不会重复扣费。
"""
from pathlib import Path
import json
import os
import time
import urllib.error
import urllib.request

from . import spec

ENDPOINT = 'https://api.elevenlabs.io/v1/sound-generation'
SUBSCRIPTION = 'https://api.elevenlabs.io/v1/user/subscription'
CREDITS_PER_SECOND = 40


class ElevenLabsError(RuntimeError):
    pass


def api_key() -> str | None:
    for name in ('ELEVENLABS_API_KEY', 'ELEVEN_LABS_API_KEY'):
        value = os.environ.get(name, '').strip()
        if value:
            return value
    candidates = [
        spec.AI_ROOT / '.elevenlabs_key',
        Path.home() / '.elevenlabs' / 'api_key',
    ]
    for path in candidates:
        if path.is_file():
            value = path.read_text(encoding='utf-8').strip()
            if value:
                return value
    return None


def _request(url: str, key: str, payload: dict | None = None, timeout: float = 180) -> tuple[bytes, str]:
    data = json.dumps(payload).encode('utf-8') if payload is not None else None
    request = urllib.request.Request(url, data=data, method='POST' if data else 'GET')
    request.add_header('xi-api-key', key)
    request.add_header('Accept', 'audio/mpeg, audio/wav, application/json')
    if data:
        request.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read(), response.headers.get('Content-Type', '')
    except urllib.error.HTTPError as exc:
        body = exc.read().decode('utf-8', errors='replace')[:800]
        raise ElevenLabsError(f'HTTP {exc.code}: {body}') from exc
    except urllib.error.URLError as exc:
        raise ElevenLabsError(f'网络不可达: {exc.reason}') from exc


def subscription(key: str | None = None) -> dict:
    key = key or api_key()
    if not key:
        raise ElevenLabsError('缺少 API key')
    body, _ = _request(SUBSCRIPTION, key)
    return json.loads(body.decode('utf-8'))


def estimate_credits(seconds: float) -> int:
    return int(round(seconds * CREDITS_PER_SECOND))


def generate(text: str, duration: float, influence: float = 0.55, loop: bool = False,
             key: str | None = None, attempts: int = 3) -> tuple[bytes, str]:
    """返回 (音频字节, 输出格式)。格式优先 WAV，循环音效退回 MP3。"""
    key = key or api_key()
    if not key:
        raise ElevenLabsError(
            '缺少 ELEVENLABS_API_KEY。可设环境变量，或把 key 写进 '
            'tools/audio/ai/.elevenlabs_key（已在 .gitignore 中忽略）。')
    preferred = 'mp3_44100_128' if loop else 'wav_48000'
    payload = {
        'text': text[:450],
        'duration_seconds': round(float(duration), 2),
        'prompt_influence': round(float(influence), 2),
    }
    if loop:
        payload['loop'] = True
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        for output_format in (preferred, None):
            url = ENDPOINT if output_format is None else f'{ENDPOINT}?output_format={output_format}'
            try:
                audio, content_type = _request(url, key, payload)
                if not audio:
                    raise ElevenLabsError('返回空音频')
                return audio, (output_format or content_type or 'mp3')
            except ElevenLabsError as exc:
                last_error = exc
                message = str(exc)
                if 'HTTP 401' in message or 'HTTP 402' in message:
                    raise
                if 'HTTP 429' in message:
                    time.sleep(2.5 * attempt)
                elif output_format is not None:
                    continue
        time.sleep(1.2 * attempt)
    raise ElevenLabsError(f'生成失败: {last_error}')
