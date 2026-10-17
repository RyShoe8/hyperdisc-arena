"""Turns raw library sounds into the game's sound effects.

    python tools/audio/process_sfx.py [SOURCE_DIR]

SOURCE_DIR defaults to ../refs/sfx/picked (Sonniss GDC bundle files, fetched
by refs/sfx/remote_zip.py; royalty free, no attribution required). Each
recipe below picks a source, finds where the sound actually starts, keeps
either the first hit (impacts) or a fixed length (whooshes, crowds), mixes to
mono, resamples to 44.1 kHz, fades out, levels it by loudness (so every take of
a sound plays equally loud), and writes a 16-bit WAV
to assets/sfx/.
"""
import os
import struct
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "refs", "sfx", "picked")
OUT = os.path.join(ROOT, "assets", "sfx")
RATE = 44100

# out name: (source file, mode, max seconds, loudness dB)
# Loudness is the RMS of the sound's active part (within 20 dB of its peak),
# capped so the peak stays under -0.5 dBFS.
# mode "hit" keeps the first transient and its decay; "len" keeps max seconds;
# "loop" is "len" with its end crossfaded into its start for seamless looping.
RECIPES = {
    "throw_whoosh_1": ("throw_whoosh_a.wav", "len", 0.45, -17.0),
    "throw_whoosh_2": ("throw_whoosh_b.wav", "len", 0.45, -17.0),
    "throw_whoosh_3": ("throw_whoosh_c.wav", "len", 0.4, -17.0),
    "throw_whoosh_4": ("throw_whoosh_d.wav", "len", 0.5, -17.0),
    "throw_whoosh_5": ("throw_whoosh_e.wav", "len", 0.45, -17.0),
    "power_whoosh_1": ("power_whoosh_large.wav", "len", 0.9, -15.0),
    "power_whoosh_2": ("power_whip.wav", "len", 0.8, -15.0),
    "power_whoosh_3": ("power_doppler.wav", "len", 1.0, -15.0),
    "special_launch_1": ("power_scifi_passby.wav", "len", 1.4, -15.0),
    "catch_1": ("catch_keeper_punch.wav", "hit", 0.4, -15.0),
    "catch_2": ("catch_punch_heavy.wav", "hit", 0.4, -15.0),
    "catch_3": ("catch_deep_punch.wav", "hit", 0.4, -15.0),
    "catch_4": ("catch_clean_deep.wav", "hit", 0.45, -15.0),
    "catch_5": ("catch_body_thump.wav", "hit", 0.4, -15.0),
    "catch_body_1": ("catch_low_thud.wav", "hit", 0.35, -18.0),
    "catch_body_2": ("catch_grab.wav", "hit", 0.35, -18.0),
    "block_1": ("catch_blocked.wav", "hit", 0.4, -16.0),
    "block_2": ("block_metal_heavy.wav", "hit", 0.4, -16.0),
    "wall_1": ("wall_ad_board.wav", "hit", 0.45, -16.0),
    "wall_2": ("wall_metal_slam.wav", "hit", 0.5, -17.0),
    "net_1": ("net_soccer.wav", "hit", 0.5, -18.0),
    "ground": ("ground_gravel.wav", "hit", 0.3, -20.0),
    "crowd_goal_1": ("crowd_goal_swell.wav", "len", 4.0, -16.0),
    "crowd_goal_2": ("crowd_goal_female.wav", "len", 4.0, -16.0),
    "crowd_cheer": ("crowd_cheers.wav", "len", 3.5, -16.0),
    "crowd_miss": ("crowd_miss.wav", "len", 3.0, -17.0),
    "crowd_bed": ("crowd_bed_clapping.wav", "loop", 20.0, -29.0),
    "whistle": ("whistle_ref.wav", "hit", 1.0, -15.0),
    "buzzer": ("buzzer.wav", "len", 1.2, -20.0),
}

# Per-character sounds: each character gets their own copies of these, in
# assets/sfx/characters/<id>/, so any of them can be swapped for that
# character alone (and voice lines layered on later). For now each copy is
# one of the shared takes, pitched to suit the character: heavy hitters
# lower, quick ones higher.
CHARACTER_SOUNDS = {
    # id: (pitch, throw_whoosh takes, power_whoosh takes, special_launch takes)
    "mick": (0.92, [1, 2, 5], [1, 2], [1]),
    "keno": (0.82, [1, 4, 5], [1, 3], [1]),
    "vanessa": (0.96, [2, 4, 5], [2, 3], [1]),
    "pete": (1.0, [1, 3, 5], [1, 2], [1]),
    "steve": (1.08, [2, 3, 5], [2, 3], [1]),
    "tiffany": (1.15, [3, 4, 5], [1, 2], [1]),
}


def read_wav(path):
    """Minimal WAV reader: PCM 16/24/32-bit and 32-bit float, any channels."""
    data = open(path, "rb").read()
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE", path
    pos, fmt, fmt_body, raw = 12, None, b"", None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
            fmt_body = body
        elif cid == b"data":
            raw = body
        pos += 8 + size + (size & 1)
    tag, channels, rate, _, _, bits = fmt
    if tag == 0xFFFE and len(fmt_body) >= 26:  # extensible: real format in the sub-format GUID
        tag = struct.unpack("<H", fmt_body[24:26])[0]
    if bits == 16:
        x = np.frombuffer(raw[:len(raw) // 2 * 2], "<i2").astype(np.float32) / 32768
    elif bits == 24:
        b = np.frombuffer(raw[:len(raw) // 3 * 3], np.uint8).reshape(-1, 3)
        v = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        v = np.where(v >= 1 << 23, v - (1 << 24), v)
        x = v.astype(np.float32) / (1 << 23)
    elif bits == 32 and tag == 3:
        x = np.frombuffer(raw[:len(raw) // 4 * 4], "<f4").astype(np.float32)
    elif bits == 32:
        x = np.frombuffer(raw[:len(raw) // 4 * 4], "<i4").astype(np.float32) / (1 << 31)
    else:
        raise ValueError(f"{path}: {bits}-bit not supported")
    x = x[: len(x) // channels * channels].reshape(-1, channels)
    return x, rate


def resample(x, rate):
    if rate == RATE:
        return x
    n = int(round(len(x) * RATE / rate))
    spec = np.fft.rfft(x)
    out_bins = n // 2 + 1
    if out_bins <= len(spec):
        spec = spec[:out_bins]
    else:
        spec = np.concatenate([spec, np.zeros(out_bins - len(spec), complex)])
    return np.fft.irfft(spec, n) * (n / len(x))


def envelope(x, win=256):
    k = np.ones(win) / win
    return np.sqrt(np.convolve(x * x, k, mode="same"))


def level(y, loud_db):
    """Scales y so its active part has the given RMS loudness (dBFS)."""
    e = envelope(y, 441)
    active = y[e > e.max() * 0.1]
    rms = np.sqrt(np.mean(active * active)) if len(active) else 1e-6
    gain = min(10 ** (loud_db / 20) / max(rms, 1e-9), 10 ** (-0.5 / 20) / max(np.abs(y).max(), 1e-9))
    return y * gain


def process(src, mode, max_len, loud_db):
    x, rate = read_wav(src)
    # Very long ambiences: only read what we need (plus some lead-in).
    x = x[: int(rate * (max_len + 5))]
    mono = x.mean(axis=1)
    env = envelope(mono, max(64, rate // 200))
    loud = env.max()
    start = int(np.argmax(env > loud * 0.05))
    start = max(0, start - int(rate * 0.004))
    y = mono[start:start + int(rate * max_len)]
    if mode == "hit":
        # Keep the first hit: stop once it has decayed well below its peak.
        e = envelope(y, max(64, rate // 200))
        peak_at = int(np.argmax(e[: int(rate * 0.15)]))
        tail = np.where(e[peak_at:] < e[peak_at] * 0.03)[0]
        if len(tail):
            y = y[: peak_at + tail[0] + int(rate * 0.03)]
    y = resample(y, rate)
    if mode == "loop":
        n = int(RATE * 1.0)
        ramp = np.linspace(0, 1, n)
        head, tail = y[:n].copy(), y[-n:]
        y = y[:-n]
        y[:n] = head * ramp + tail * (1 - ramp)
        return level(y, loud_db)
    fade = min(len(y) // 4, int(RATE * (0.08 if mode == "hit" else 0.3)))
    if fade > 0:
        y[-fade:] *= np.linspace(1, 0, fade) ** 2
    y[: min(32, len(y))] *= np.linspace(0, 1, min(32, len(y)))  # click-free start
    y = level(y, loud_db)
    return y


def write_wav(path, y):
    pcm = (np.clip(y, -1, 1) * 32767).astype("<i2").tobytes()
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt ")
        fh.write(struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16))
        fh.write(b"data" + struct.pack("<I", len(pcm)) + pcm)


def pitched(y, pitch, loud_db):
    """Raises (pitch > 1) or lowers the pitch, changing the length to match."""
    return level(resample(y, int(RATE * pitch)), loud_db)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for name, (src, mode, max_len, loud) in RECIPES.items():
        path = os.path.join(SRC, src)
        if not os.path.exists(path):
            print("missing", src)
            continue
        y = process(path, mode, max_len, loud)
        made[name] = (y, loud)
        write_wav(os.path.join(OUT, name + ".wav"), y)
        print(f"{name:16s} {len(y) / RATE:5.2f}s  from {src}")
    for cid, (pitch, throws, powers, specials) in CHARACTER_SOUNDS.items():
        out = os.path.join(OUT, "characters", cid)
        os.makedirs(out, exist_ok=True)
        for sound, takes in (("throw_whoosh", throws), ("power_whoosh", powers), ("special_launch", specials)):
            for i, take in enumerate(takes, 1):
                y, loud = made[f"{sound}_{take}"]
                write_wav(os.path.join(out, f"{sound}_{i}.wav"), pitched(y, pitch, loud))
        print(f"characters/{cid}: pitch {pitch}")
