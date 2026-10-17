"""Character voice lines and the announcer, made with Kokoro text-to-speech
(Apache 2.0 weights) and roughed up for an arcade feel.

Kokoro lives outside the repo, on D: (see docs/AUDIO.md):

    "D:/Hyperdisc Arena/refs/voice/venv/Scripts/python" tools/audio/make_voices.py OUT_DIR [speaker ...]

Writes OUT_DIR/<speaker>/<line>.wav for every speaker (or the ones named).
A speaker is a voice recipe: one Kokoro voice or a blend, a pitch shift and
a tempo, and how hard the arcade processing pushes it.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_sfx import RATE, level, resample, write_wav  # noqa: E402

KOKORO_DIR = "D:/Hyperdisc Arena/refs/voice/models"

# What each character says. Kokoro reads punctuation, so "!" adds energy.
LINES = {
    "mick": {
        "select": "Mick Magnum. Let's rock.",
        "throw_1": "Hah!", "throw_2": "Hyah!", "throw_3": "Huh!",
        "power": "Eat this!",
        "special": "Danger... zone!",
        "catch_1": "Hup!", "catch_2": "Got it!",
        "knocked": "Oof!",
        "win": "Too easy, dude.",
        "lose": "No way, man...",
    },
    "announcer": {
        "title": "Hyper Disc Arena!",
        "ready": "Ready...",
        "go": "Go!",
        "point": "Point!",
        "set": "Set!",
        "match_point": "Match point!",
        "game": "Game!",
        "power": "Power throw!",
        "winner": "Winner!",
    },
}

# speaker: (character, voices {name: weight}, pitch, tempo, drive, echo, description)
# pitch scales the voice's pitch (and formants) by resampling; tempo is the
# final speaking speed; drive is saturation (1 = clean); echo adds an arena
# PA slapback for the announcer.
SPEAKERS = {
    "mick_a": ("mick", {"am_fenrir": 1.0}, 0.94, 1.05, 2.2, 0.0, "Fenrir, a touch lower: gravelly action hero"),
    "mick_b": ("mick", {"am_onyx": 1.0}, 0.97, 1.08, 2.0, 0.0, "Onyx: deep and smooth"),
    "mick_c": ("mick", {"am_michael": 0.5, "am_fenrir": 0.5}, 0.92, 1.05, 2.6, 0.0,
               "Michael and Fenrir blend, lower and grittier"),
    "mick_d": ("mick", {"am_puck": 1.0}, 0.9, 1.1, 2.4, 0.0, "Puck, pitched down: cocky surfer"),
    "announcer_a": ("announcer", {"am_adam": 1.0}, 0.86, 0.95, 2.8, 0.22, "Adam, deep, with arena echo"),
    "announcer_b": ("announcer", {"am_onyx": 1.0}, 0.9, 0.92, 2.4, 0.22, "Onyx, big and booming, with arena echo"),
    "announcer_c": ("announcer", {"bm_george": 1.0}, 0.92, 0.95, 2.2, 0.18, "George: British commentator"),
    "announcer_d": ("announcer", {"am_santa": 0.6, "am_adam": 0.4}, 0.95, 0.95, 3.0, 0.25,
                    "Santa and Adam blend: gravelly monster-truck voice"),
}


def kokoro():
    from kokoro_onnx import Kokoro
    return Kokoro(os.path.join(KOKORO_DIR, "kokoro-v1.0.onnx"), os.path.join(KOKORO_DIR, "voices-v1.0.bin"))


def voice_style(k, voices):
    total = sum(voices.values())
    return sum(k.get_voice_style(name) * (w / total) for name, w in voices.items())


def biquad(x, b, a):
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, s in enumerate(x):
        o = b[0] * s + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1, y2, y1 = x1, s, y1, o
        y[i] = o
    return y


def highpass(x, f, q=0.707):
    w = 2 * np.pi * f / RATE
    al = np.sin(w) / (2 * q)
    c = np.cos(w)
    b = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2])
    a = np.array([1 + al, -2 * c, 1 - al])
    return biquad(x, b / a[0], a / a[0])


def lowpass(x, f, q=0.707):
    w = 2 * np.pi * f / RATE
    al = np.sin(w) / (2 * q)
    c = np.cos(w)
    b = np.array([(1 - c) / 2, 1 - c, (1 - c) / 2])
    a = np.array([1 + al, -2 * c, 1 - al])
    return biquad(x, b / a[0], a / a[0])


def peak_eq(x, f, gain_db, q=1.0):
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f / RATE
    al = np.sin(w) / (2 * q)
    c = np.cos(w)
    b = np.array([1 + al * A, -2 * c, 1 - al * A])
    a = np.array([1 + al / A, -2 * c, 1 - al / A])
    return biquad(x, b / a[0], a / a[0])


def compress(x, threshold_db=-24.0, ratio=4.0, attack=0.003, release=0.08):
    """Feed-forward compressor: evens out the line so it cuts through."""
    t = 10 ** (threshold_db / 20)
    a_att = np.exp(-1 / (RATE * attack))
    a_rel = np.exp(-1 / (RATE * release))
    env = 0.0
    out = np.empty_like(x)
    for i, s in enumerate(x):
        r = abs(s)
        env = a_att * env + (1 - a_att) * r if r > env else a_rel * env + (1 - a_rel) * r
        gain = 1.0 if env <= t else (t * (env / t) ** (1 / ratio)) / env
        out[i] = s * gain
    return out


def trim(x, floor=0.02):
    loud = np.where(np.abs(x) > floor * np.abs(x).max())[0]
    if not len(loud):
        return x
    a = max(0, loud[0] - int(RATE * 0.01))
    b = min(len(x), loud[-1] + int(RATE * 0.06))
    return x[a:b]


def arcade(x, drive, echo):
    """Shape a clean TTS line into an arcade voice sample."""
    x = highpass(x, 110)
    x = peak_eq(x, 250, -2.0, 0.8)    # less boxiness
    x = peak_eq(x, 2800, 5.0, 0.9)    # presence: cuts through the music
    x = compress(x, -26, 5.0)
    x = x / max(np.abs(x).max(), 1e-9)
    x = np.tanh(x * drive) / np.tanh(drive)   # saturation: grit and energy
    x = lowpass(x, 9500)                       # a little Neo Geo band-limit
    if echo > 0:
        d1, d2 = int(RATE * 0.09), int(RATE * 0.19)
        y = np.concatenate([x, np.zeros(d2 + int(RATE * 0.2))])
        y[d1:d1 + len(x)] += x * echo
        y[d2:d2 + len(x)] += x * echo * 0.55
        x = lowpass(y, 7000) * 0.35 + y * 0.65
    x = trim(x)
    fade = min(len(x) // 5, int(RATE * 0.05))
    x[-fade:] *= np.linspace(1, 0, fade)
    return level(x, -15.0)


def say(k, speaker, text):
    _char, voices, pitch, tempo, drive, echo, _desc = SPEAKERS[speaker]
    # Resampling by `pitch` also changes speed, so ask Kokoro for the
    # difference: the line ends up at `tempo`.
    samples, sr = k.create(text, voice=voice_style(k, voices), speed=tempo / pitch, lang="en-us")
    x = resample(np.asarray(samples, float), int(sr * pitch))
    return arcade(x, drive, echo)


def main():
    out = sys.argv[1]
    speakers = sys.argv[2:] or list(SPEAKERS)
    k = kokoro()
    for sp in speakers:
        os.makedirs(os.path.join(out, sp), exist_ok=True)
        for line, text in LINES[SPEAKERS[sp][0]].items():
            write_wav(os.path.join(out, sp, line + ".wav"), say(k, sp, text))
        print("wrote", sp)


if __name__ == "__main__":
    main()
