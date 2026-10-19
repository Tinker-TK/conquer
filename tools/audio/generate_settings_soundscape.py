"""Generate original, reproducible CC0 loops for the game's volume channels."""
from array import array
from pathlib import Path
import hashlib
import json
import math
import random
import wave

ROOT = Path(__file__).resolve().parents[2]
RATE = 22050
SECONDS = 16
COUNT = RATE * SECONDS
OUTPUT = ROOT / 'assets/audio/soundscape'


def write(name, samples):
    path = OUTPUT / (name + '.wav')
    peak = max(abs(value) for value in samples) or 1
    pcm = array('h', (round(value / peak * 24000) for value in samples))
    with wave.open(str(path), 'wb') as target:
        target.setparams((1, 2, RATE, len(pcm), 'NONE', 'not compressed'))
        target.writeframes(pcm.tobytes())
    return path


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # A minor pentatonic plucked-string phrase, with tails wrapped into the loop.
    music = [0.0] * COUNT
    phrase = [57, 64, 69, 72, 64, 69, 76, 72, 53, 60, 65, 69, 60, 65, 72, 69,
              55, 62, 67, 71, 62, 67, 74, 71, 57, 64, 69, 72, 76, 72, 69, 64]
    for beat, note in enumerate(phrase):
        frequency = 440 * 2 ** ((note - 69) / 12)
        start = round(beat * .5 * RATE)
        for i in range(RATE * 2):
            t = i / RATE
            envelope = min(1, t / .008) * math.exp(-3.3 * t)
            tone = sum(math.sin(2 * math.pi * frequency * h * t) / h ** 2 for h in (1, 2, 3, 4))
            music[(start + i) % COUNT] += .35 * envelope * tone
    rng = random.Random(107)
    wind, rain = [], []
    low, mid = 0.0, 0.0
    for i in range(COUNT):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += .012 * (noise - low)
        mid += .2 * (noise - mid)
        # Periodic envelopes avoid an abrupt gain change at the loop boundary.
        wind.append(low * (1 + .3 * math.sin(2 * math.pi * t / 8)))
        rain.append((noise - mid + .3 * low) * (.7 + .1 * math.sin(2 * math.pi * t / 16)))
    # Blend noise across the seam (music is already periodic).
    for samples in (wind, rain):
        seam = RATE // 5
        for i in range(seam):
            factor = i / seam
            samples[i] = samples[-seam + i] * (1 - factor) + samples[i] * factor
    entries = []
    for name, title, category, samples in [
        ('journey', '征途 · 原创拨弦背景音乐', 'music', music),
        ('wind', '原野 · 原创风声环境音', 'ambience', wind),
        ('rain', '雨天 · 原创雨声环境音', 'ambience', rain),
    ]:
        path = write(name, samples)
        entries.append(dict(path='res://' + path.relative_to(ROOT).as_posix(), title=title,
                            category=category, author='项目原创程序合成',
                            source='res://tools/audio/generate_settings_soundscape.py', license='CC0-1.0',
                            notes='游戏音量通道使用的 16 秒循环；试听库中单次播放。',
                            changes='原创合成，22050 Hz 单声道 PCM；归一化并处理循环接缝。',
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    manifest_path = ROOT / 'assets/audio/library/manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    paths = {entry['path'] for entry in entries}
    manifest['files'] = [entry for entry in manifest['files'] if entry['path'] not in paths] + entries
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Generated 3 original soundscape loops and updated manifest.')


if __name__ == '__main__':
    main()
