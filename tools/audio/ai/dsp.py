"""音频后处理：读入原始生成结果，裁剪、归一、补循环接缝，输出 Godot 可导入的 OGG。

只依赖 numpy + soundfile；soundfile 未安装时给出明确提示，不静默降级。
"""
from pathlib import Path
import math

import numpy as np
import soundfile as sf


def read(path: Path) -> tuple[np.ndarray, int]:
    data, rate = sf.read(str(path), always_2d=True, dtype='float32')
    return data, int(rate)


def to_mono(data: np.ndarray) -> np.ndarray:
    if data.ndim == 1:
        return data.astype(np.float32, copy=False)
    return data.mean(axis=1).astype(np.float32)


def resample(x: np.ndarray, rate_in: int, rate_out: int) -> np.ndarray:
    """FFT 重采样，短音频足够干净，避免引入 scipy 依赖。"""
    if rate_in == rate_out or len(x) == 0:
        return x.astype(np.float32, copy=False)
    n_in = len(x)
    n_out = max(1, int(round(n_in * rate_out / rate_in)))
    spectrum = np.fft.rfft(x)
    bins = n_out // 2 + 1
    if bins <= spectrum.size:
        target = spectrum[:bins].copy()
    else:
        target = np.zeros(bins, dtype=spectrum.dtype)
        target[:spectrum.size] = spectrum
    y = np.fft.irfft(target, n_out).astype(np.float32)
    return (y * (n_out / n_in)).astype(np.float32)


def peak_db(x: np.ndarray) -> float:
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    return -math.inf if peak <= 0 else 20 * math.log10(peak)


def rms_db(x: np.ndarray) -> float:
    if x.size == 0:
        return -math.inf
    rms = float(np.sqrt(np.mean(np.square(x))))
    return -math.inf if rms <= 0 else 20 * math.log10(rms)


def trim(x: np.ndarray, rate: int, threshold_db: float = -46.0,
         pre_ms: float = 6.0, post_ms: float = 40.0) -> np.ndarray:
    """按包络裁掉首尾静音，保留起音前的少量余量，不切掉瞬态。"""
    if x.size == 0:
        return x
    window = max(1, int(rate * 0.001))
    envelope = np.convolve(np.abs(x), np.ones(window, dtype=np.float32) / window, mode='same')
    threshold = 10 ** (threshold_db / 20)
    above = np.flatnonzero(envelope > threshold)
    if above.size == 0:
        return x
    start = max(0, int(above[0]) - int(rate * pre_ms / 1000))
    end = min(len(x), int(above[-1]) + int(rate * post_ms / 1000))
    return x[start:end].copy()


def fade(x: np.ndarray, rate: int, fade_in_ms: float = 2.5, fade_out_ms: float = 12.0) -> np.ndarray:
    y = x.copy()
    fade_in = min(len(y), int(rate * fade_in_ms / 1000))
    fade_out = min(len(y), int(rate * fade_out_ms / 1000))
    if fade_in > 0:
        y[:fade_in] *= np.linspace(0.0, 1.0, fade_in, dtype=np.float32)
    if fade_out > 0:
        y[-fade_out:] *= np.linspace(1.0, 0.0, fade_out, dtype=np.float32)
    return y


def normalize_peak(x: np.ndarray, target_dbfs: float) -> np.ndarray:
    current = peak_db(x)
    if not math.isfinite(current):
        return x
    return (x * (10 ** ((target_dbfs - current) / 20))).astype(np.float32)


def soft_limit(x: np.ndarray, ceiling: float = 0.985) -> np.ndarray:
    """只在归一化后仍然越界时兜底，正常素材不该走到这里。"""
    return np.tanh(x / ceiling) * ceiling if np.max(np.abs(x), initial=0.0) > ceiling else x


def loop_blend(x: np.ndarray, rate: int, blend_seconds: float) -> np.ndarray:
    """把尾巴等功率交叉淡入到开头，得到首尾相接的循环。"""
    length = int(rate * blend_seconds)
    length = min(length, len(x) // 3)
    if length < 64:
        return x
    head = x[:length]
    tail = x[-length:]
    theta = np.linspace(0.0, math.pi / 2, length, endpoint=False, dtype=np.float32)
    blended = tail * np.cos(theta) + head * np.sin(theta)
    y = x[:-length].copy()
    y[:length] = blended
    return y


def features(x: np.ndarray, rate: int) -> dict:
    if x.size == 0:
        return {'duration_seconds': 0.0}
    envelope = np.abs(x)
    peak_index = int(np.argmax(envelope))
    peak = float(envelope[peak_index])
    attack = peak_index / rate
    after = envelope[peak_index:]
    quiet = np.flatnonzero(after < peak * 0.01) if peak > 0 else np.array([], dtype=int)
    tail = (quiet[0] / rate) if quiet.size else (len(after) / rate)
    spectrum = np.abs(np.fft.rfft(x))
    freqs = np.fft.rfftfreq(len(x), 1 / rate)
    total = float(spectrum.sum())
    centroid = float((spectrum * freqs).sum() / total) if total > 0 else 0.0
    zero_crossings = int(np.sum(np.diff(np.signbit(x))))
    return {
        'duration_seconds': round(len(x) / rate, 3),
        'peak_dbfs': round(peak_db(x), 2),
        'rms_dbfs': round(rms_db(x), 2),
        'crest_db': round(peak_db(x) - rms_db(x), 2),
        'spectral_centroid_hz': round(centroid, 1),
        'zero_cross_rate': round(zero_crossings / max(len(x) - 1, 1), 4),
        'attack_ms': round(attack * 1000, 1),
        'tail_ms': round(tail * 1000, 1),
    }


def _write_stream(path: Path, x: np.ndarray, rate: int, format: str, subtype: str) -> None:
    """分块写入：libsndfile 的 Vorbis 编码器吃不下整段长音频，一次写完会爆栈。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    clip = np.clip(x, -1.0, 1.0)
    with sf.SoundFile(str(path), 'w', samplerate=rate, channels=1, format=format, subtype=subtype) as target:
        for start in range(0, len(clip), 32768):
            target.write(clip[start:start + 32768])


def write_ogg(path: Path, x: np.ndarray, rate: int) -> None:
    _write_stream(path, x, rate, 'OGG', 'VORBIS')


def write_wav(path: Path, x: np.ndarray, rate: int) -> None:
    _write_stream(path, x, rate, 'WAV', 'PCM_16')
