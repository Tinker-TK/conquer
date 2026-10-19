"""离线程序合成占位音：没有 API key 时也能打通生成、处理、试听、回归全链路。

这些不是 AI 生成，清单里许可写 CC0-1.0、作者写“项目程序合成（占位）”。
ElevenLabs 版本生成后按同一分类并存，方便 A/B。
"""
import numpy as np

SR = 48000


def _n(seconds: float) -> int:
    return max(1, int(round(SR * seconds)))


def _t(n: int) -> np.ndarray:
    return (np.arange(n, dtype=np.float32) / SR).astype(np.float32)


def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def _noise(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n).astype(np.float32)


def _exp(n: int, decay: float, attack: float = 0.002) -> np.ndarray:
    t = _t(n)
    rise = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    return (rise * np.exp(-t / max(decay, 1e-5))).astype(np.float32)


def _sine(freq: float, n: int, phase: float = 0.0) -> np.ndarray:
    return np.sin(2 * np.pi * freq * _t(n) + phase).astype(np.float32)


def _sweep(f0: float, f1: float, n: int) -> np.ndarray:
    t = _t(n)
    span = max(t[-1], 1e-6)
    phase = 2 * np.pi * (f0 * t + 0.5 * (f1 - f0) * t * t / span)
    return np.sin(phase).astype(np.float32)


def _filter(x: np.ndarray, lo: float | None = None, hi: float | None = None) -> np.ndarray:
    """平滑的频域带限，避免 FIR 设计的额外依赖。"""
    if x.size < 8 or (lo is None and hi is None):
        return x
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    mask = np.ones_like(freqs)
    if hi is not None:
        mask *= 1.0 / (1.0 + np.exp(np.clip((freqs - hi) / max(hi * 0.12, 1.0), -60, 60)))
    if lo is not None:
        mask *= 1.0 / (1.0 + np.exp(np.clip((lo - freqs) / max(lo * 0.12, 1.0), -60, 60)))
    return np.fft.irfft(spectrum * mask, len(x)).astype(np.float32)


def _mix(*parts: tuple[np.ndarray, float]) -> np.ndarray:
    length = max(part[0].size for part in parts)
    out = np.zeros(length, dtype=np.float32)
    for samples, gain in parts:
        out[:samples.size] += samples * gain
    return out


def _place(target: np.ndarray, source: np.ndarray, at: float, gain: float = 1.0) -> None:
    start = int(at * SR)
    end = min(target.size, start + source.size)
    if start < target.size:
        target[start:end] += source[:end - start] * gain


def _pluck(freq: float, seconds: float, decay: float, harmonics: int = 5) -> np.ndarray:
    n = _n(seconds)
    tone = np.zeros(n, dtype=np.float32)
    for h in range(1, harmonics + 1):
        tone += (_sine(freq * h, n) / (h ** 1.7)).astype(np.float32)
    return tone * _exp(n, decay, 0.004)


# ---------------------------------------------------------------- 界面音效

def ui_click() -> np.ndarray:
    n = _n(0.09)
    rng = _rng(11)
    tick = _noise(n, rng) * _exp(n, 0.0022, 0.0004)
    body = _mix((_sine(1450, n), 0.7), (_sine(2650, n), 0.3)) * _exp(n, 0.012, 0.0006)
    return _filter(tick * 0.18 + body * 0.32, lo=350, hi=9000)


def ui_hover() -> np.ndarray:
    n = _n(0.06)
    rng = _rng(12)
    tick = _noise(n, rng) * _exp(n, 0.0018, 0.0003)
    body = _sine(2100, n) * _exp(n, 0.007, 0.0004)
    return _filter(tick * 0.10 + body * 0.12, lo=1200, hi=9000)


def ui_confirm() -> np.ndarray:
    n = _n(0.6)
    out = np.zeros(n, dtype=np.float32)
    _place(out, _pluck(659.25, 0.5, 0.20, 3), 0.0, 0.55)
    _place(out, _pluck(880.0, 0.45, 0.22, 3), 0.115, 0.45)
    _place(out, _filter(_noise(_n(0.12), _rng(13)) * _exp(_n(0.12), 0.05), lo=3000), 0.1, 0.05)
    return _filter(out, lo=180)


def ui_cancel() -> np.ndarray:
    n = _n(0.45)
    out = np.zeros(n, dtype=np.float32)
    _place(out, _pluck(440.0, 0.4, 0.16, 3), 0.0, 0.5)
    _place(out, _pluck(329.63, 0.4, 0.18, 3), 0.10, 0.5)
    return _filter(out, lo=120, hi=4000)


def ui_error() -> np.ndarray:
    n = _n(0.3)
    t = _t(n)
    gate = (np.sin(2 * np.pi * 18 * t) > 0.1).astype(np.float32)
    buzz = (_sine(132, n) * 0.6 + _sine(198, n) * 0.25) * gate
    return _filter(buzz * _exp(n, 0.22, 0.01), lo=80, hi=1500)


def ui_coin() -> np.ndarray:
    n = _n(0.55)
    out = np.zeros(n, dtype=np.float32)
    for index, (freq, delay) in enumerate(((2093, 0.0), (2793, 0.045), (3136, 0.1), (4186, 0.14))):
        _place(out, _sine(freq * (1 + 0.002 * index), n) * _exp(n, 0.16 - index * 0.02, 0.001), delay, 0.22)
    rng = _rng(14)
    _place(out, _filter(_noise(_n(0.03), rng) * _exp(_n(0.03), 0.006), lo=4000), 0.0, 0.18)
    return _filter(out, lo=900)


# ---------------------------------------------------------------- 卡牌音效

def card_draw() -> np.ndarray:
    n = _n(0.4)
    rng = _rng(21)
    friction = _filter(_noise(n, rng), lo=1400, hi=7000)
    t = _t(n)
    shape = np.clip(t / 0.03, 0, 1) * np.clip((0.4 - t) / 0.18, 0, 1)
    slide = _sine(320, n) * 0.05 * np.exp(-t / 0.08)
    return friction * shape * 0.5 + slide


def card_play() -> np.ndarray:
    n = _n(0.35)
    rng = _rng(22)
    snap = _filter(_noise(_n(0.05), rng) * _exp(_n(0.05), 0.008, 0.0005), lo=1800)
    thump = _sweep(170, 95, _n(0.16)) * _exp(_n(0.16), 0.06, 0.001)
    paper = _filter(_noise(_n(0.12), rng) * _exp(_n(0.12), 0.035), lo=2000, hi=8000) * 0.25
    out = np.zeros(n, dtype=np.float32)
    _place(out, snap, 0.0, 0.5)
    _place(out, thump, 0.004, 0.5)
    _place(out, paper, 0.01, 0.4)
    return out


def card_shuffle() -> np.ndarray:
    n = _n(0.85)
    rng = _rng(23)
    out = np.zeros(n, dtype=np.float32)
    for _ in range(9):
        start = float(rng.uniform(0.0, 0.7))
        length = _n(float(rng.uniform(0.035, 0.06)))
        burst = _filter(_noise(length, rng) * _exp(length, 0.02), lo=2200, hi=8000)
        _place(out, burst, start, float(rng.uniform(0.2, 0.45)))
    bed = _filter(_noise(n, rng), lo=1500, hi=6000) * _exp(n, 0.45) * 0.06
    return out + bed


def card_upgrade() -> np.ndarray:
    n = _n(0.95)
    out = np.zeros(n, dtype=np.float32)
    for index, note in enumerate((440.0, 523.25, 659.25, 880.0, 1046.5)):
        _place(out, _pluck(note, 0.7, 0.28, 4), index * 0.09, 0.3)
    rng = _rng(24)
    shimmer = _filter(_noise(n, rng), lo=5000, hi=12000) * _exp(n, 0.5, 0.12) * 0.05
    return out + shimmer


# ---------------------------------------------------------------- 战斗音效

def sword_swing() -> np.ndarray:
    n = _n(0.65)
    rng = _rng(31)
    source = _noise(n, rng)
    low = _filter(source, lo=250, hi=900)
    mid = _filter(source, lo=900, hi=2200)
    high = _filter(source, lo=2200, hi=6000)
    t = _t(n) / 0.65
    envelope = np.sin(np.pi * np.clip(t, 0, 1) ** 0.65).astype(np.float32)
    sweep = (low * (1 - t) + mid * (0.5 + 0.5 * np.sin(np.pi * t)) + high * t).astype(np.float32)
    return sweep * envelope * 0.9


def blade_clash() -> np.ndarray:
    n = _n(0.7)
    rng = _rng(32)
    out = np.zeros(n, dtype=np.float32)
    for freq, decay, phase in ((1180, 0.18, 0.3), (1780, 0.14, 1.1), (2460, 0.11, 2.0), (3310, 0.08, 0.7), (4120, 0.06, 1.6)):
        _place(out, _sine(freq, n, phase) * _exp(n, decay, 0.0008), 0.0, 0.22)
    crack = _filter(_noise(_n(0.04), rng) * _exp(_n(0.04), 0.006), lo=2500)
    _place(out, crack, 0.0, 0.6)
    return _filter(out, lo=400)


def flesh_hit() -> np.ndarray:
    n = _n(0.45)
    rng = _rng(33)
    thump = _sweep(110, 62, _n(0.22)) * _exp(_n(0.22), 0.08, 0.001)
    body = _filter(_noise(_n(0.16), rng) * _exp(_n(0.16), 0.045), lo=120, hi=1200)
    cloth = _filter(_noise(_n(0.2), rng) * _exp(_n(0.2), 0.06), lo=900, hi=3500) * 0.25
    out = np.zeros(n, dtype=np.float32)
    _place(out, thump, 0.0, 0.8)
    _place(out, body, 0.0, 0.55)
    _place(out, cloth, 0.01, 0.4)
    return out


def heavy_impact() -> np.ndarray:
    n = _n(0.85)
    rng = _rng(34)
    boom = _sweep(78, 36, _n(0.5)) * _exp(_n(0.5), 0.2, 0.002)
    blast = _filter(_noise(_n(0.35), rng) * _exp(_n(0.35), 0.09), lo=60, hi=900)
    out = np.zeros(n, dtype=np.float32)
    _place(out, boom, 0.0, 0.9)
    _place(out, blast, 0.0, 0.5)
    for delay in (0.045, 0.085, 0.13):
        splinter = _filter(_noise(_n(0.05), rng) * _exp(_n(0.05), 0.012), lo=1800)
        _place(out, splinter, delay, 0.22)
    return out


def bow_release() -> np.ndarray:
    n = _n(0.45)
    rng = _rng(35)
    string = _pluck(196.0, 0.3, 0.05, 4) * 0.5
    thwip = _filter(_noise(_n(0.12), rng) * _exp(_n(0.12), 0.03), lo=700, hi=5000)
    air = _filter(_noise(n, rng), lo=1200, hi=6000) * _exp(n, 0.09, 0.01) * 0.12
    out = np.zeros(n, dtype=np.float32)
    _place(out, string, 0.0, 0.6)
    _place(out, thwip, 0.0, 0.5)
    return out + air


def fire_cast() -> np.ndarray:
    n = _n(1.1)
    rng = _rng(36)
    t = _t(n)
    swell = np.clip(t / 0.35, 0, 1) * np.exp(-np.clip(t - 0.35, 0, None) / 0.28)
    base = _filter(_noise(n, rng), lo=180, hi=1800) * swell
    out = base.astype(np.float32) * 0.7 + _sweep(90, 150, n) * swell * 0.15
    for _ in range(16):
        at = float(rng.uniform(0.0, 0.95))
        length = _n(float(rng.uniform(0.008, 0.02)))
        crackle = _filter(_noise(length, rng) * _exp(length, 0.004), lo=2500)
        _place(out, crackle, at, float(rng.uniform(0.1, 0.25)))
    return out


def ice_cast() -> np.ndarray:
    n = _n(0.95)
    rng = _rng(37)
    t = _t(n)
    swell = np.clip(t / 0.18, 0, 1) * np.exp(-np.clip(t - 0.18, 0, None) / 0.3)
    out = np.zeros(n, dtype=np.float32)
    for freq in (2637, 3136, 3951, 4699):
        out += (_sine(freq, n) * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t + freq)) * 0.05).astype(np.float32)
    sparkle = _filter(_noise(n, rng), lo=4500, hi=12000) * swell * 0.2
    return (out * swell + sparkle).astype(np.float32)


def explosion() -> np.ndarray:
    n = _n(1.3)
    rng = _rng(38)
    white = _noise(n, rng)
    brown = np.cumsum(white).astype(np.float32)
    brown /= max(float(np.max(np.abs(brown))), 1e-6)
    blast = _filter(white * _exp(n, 0.18, 0.002), hi=3500) * 0.65
    rumble = _filter(brown * _exp(n, 0.55, 0.004), hi=260) * 1.1
    sub = _sweep(62, 34, n) * _exp(n, 0.4, 0.003) * 0.5
    out = blast + rumble + sub
    for _ in range(22):
        at = float(rng.uniform(0.05, 1.1))
        length = _n(float(rng.uniform(0.006, 0.02)))
        debris = _filter(_noise(length, rng) * _exp(length, 0.004), lo=1200)
        _place(out, debris, at, float(rng.uniform(0.05, 0.16)))
    return out.astype(np.float32)


# ---------------------------------------------------------------- 环境音循环

def amb_campfire() -> np.ndarray:
    seconds = 14.0
    n = _n(seconds)
    rng = _rng(41)
    rumble = _filter(_noise(n, rng), hi=220) * 0.5
    hiss = _filter(_noise(n, rng), lo=900, hi=4000) * 0.02
    out = rumble + hiss
    for _ in range(150):
        at = float(rng.uniform(0.0, seconds))
        length = _n(float(rng.uniform(0.006, 0.03)))
        pop = _filter(_noise(length, rng) * _exp(length, 0.008), lo=1400, hi=9000)
        _place(out, pop, at, float(rng.uniform(0.05, 0.3)))
    return out.astype(np.float32)


def amb_forest_day() -> np.ndarray:
    seconds = 14.0
    n = _n(seconds)
    rng = _rng(42)
    leaves = _filter(_noise(n, rng), lo=300, hi=2600)
    t = _t(n)
    sway = (0.55 + 0.45 * np.sin(2 * np.pi * t / 7.0)).astype(np.float32)
    out = leaves * sway * 0.35
    for _ in range(26):
        at = float(rng.uniform(0.0, seconds - 0.4))
        start = float(rng.uniform(2400, 3600))
        length = _n(float(rng.uniform(0.06, 0.12)))
        chirp = _sweep(start, start * float(rng.uniform(1.1, 1.35)), length) * _exp(length, 0.05, 0.005)
        _place(out, chirp, at, float(rng.uniform(0.03, 0.09)))
    return out.astype(np.float32)


def amb_rain_stone() -> np.ndarray:
    seconds = 14.0
    n = _n(seconds)
    rng = _rng(43)
    t = _t(n)
    rain = _filter(_noise(n, rng), lo=500, hi=9000)
    rain *= (0.8 + 0.2 * np.sin(2 * np.pi * t / 5.0)).astype(np.float32) * 0.4
    out = rain
    for _ in range(70):
        at = float(rng.uniform(0.0, seconds))
        length = _n(0.012)
        drop = _filter(_noise(length, rng) * _exp(length, 0.004), lo=2000, hi=9000)
        _place(out, drop, at, float(rng.uniform(0.02, 0.07)))
    return out.astype(np.float32)


# ---------------------------------------------------------------- 背景音乐循环

def _pad(freq: float, n: int, tremolo: float = 0.15) -> np.ndarray:
    t = _t(n)
    tone = np.zeros(n, dtype=np.float32)
    for h, gain in ((1, 0.5), (2, 0.22), (3, 0.12), (4, 0.06)):
        tone += (_sine(freq * h, n) * gain).astype(np.float32)
    return (tone * (1 - tremolo + tremolo * np.sin(2 * np.pi * 0.18 * t))).astype(np.float32)


def bgm_battle_ember() -> np.ndarray:
    beat = 60.0 / 112.0
    bars = 4
    n = _n(beat * 8 * bars)
    out = np.zeros(n, dtype=np.float32)
    rng = _rng(51)
    for bar in range(bars):
        base = bar * beat * 8
        for step in (0, 3, 4, 6):
            kick = _sweep(95, 42, _n(0.18)) * _exp(_n(0.18), 0.06, 0.001)
            _place(out, kick, base + step * beat, 0.55)
        for step in (2, 6):
            snare = _filter(_noise(_n(0.12), rng) * _exp(_n(0.12), 0.03), lo=1200, hi=6000)
            _place(out, snare, base + step * beat, 0.18)
        for step in range(8):
            if step % 2 == 0:
                _place(out, _pluck(73.42 if step < 4 else 55.0, beat * 0.9, 0.35, 3), base + step * beat, 0.22)
        stab = np.zeros(_n(beat * 1.6), dtype=np.float32)
        for freq in (146.83, 174.61, 220.0):
            stab += _pad(freq, stab.size, 0.0) * 0.12
        _place(out, stab * _exp(stab.size, 0.5, 0.02), base, 0.16)
    drone = _pad(73.42, n, 0.25) * 0.16 + _pad(110.0, n, 0.2) * 0.10 + _pad(146.83, n, 0.15) * 0.05
    return (out + drone).astype(np.float32)


def bgm_camp_calm() -> np.ndarray:
    beat = 60.0 / 78.0
    n = _n(beat * 16)
    out = np.zeros(n, dtype=np.float32)
    chords = [(220.0, 261.63, 329.63), (174.61, 220.0, 261.63), (196.0, 246.94, 293.66), (164.81, 196.0, 246.94)]
    for index in range(16):
        chord = chords[(index // 4) % len(chords)]
        note = chord[index % len(chord)] * (2 if index % 4 == 3 else 1)
        _place(out, _pluck(note, beat * 1.4, 0.45, 4), index * beat, 0.22)
    pad = np.zeros(n, dtype=np.float32)
    for index, chord in enumerate(chords):
        segment = _pad(chord[0] / 2, _n(beat * 4), 0.2) * 0.10
        _place(pad, segment, index * beat * 4, 1.0)
    return (out + pad).astype(np.float32)


REGISTRY = {
    'ui_click': ui_click,
    'ui_hover': ui_hover,
    'ui_confirm': ui_confirm,
    'ui_cancel': ui_cancel,
    'ui_error': ui_error,
    'ui_coin': ui_coin,
    'card_draw': card_draw,
    'card_play': card_play,
    'card_shuffle': card_shuffle,
    'card_upgrade': card_upgrade,
    'sword_swing': sword_swing,
    'blade_clash': blade_clash,
    'flesh_hit': flesh_hit,
    'heavy_impact': heavy_impact,
    'bow_release': bow_release,
    'fire_cast': fire_cast,
    'ice_cast': ice_cast,
    'explosion': explosion,
    'amb_campfire': amb_campfire,
    'amb_forest_day': amb_forest_day,
    'amb_rain_stone': amb_rain_stone,
    'bgm_battle_ember': bgm_battle_ember,
    'bgm_camp_calm': bgm_camp_calm,
}


def render(name: str) -> np.ndarray:
    if name not in REGISTRY:
        raise KeyError(f'unknown procedural recipe: {name}')
    samples = REGISTRY[name]()
    if not np.all(np.isfinite(samples)):
        raise ValueError(f'non-finite samples in {name}')
    return samples.astype(np.float32)
