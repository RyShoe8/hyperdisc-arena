"""Synthesised arcade sound effects: punchy, short and dry, in the spirit of
Neo Geo sports games. Each recipe is a function returning mono float samples
at 44.1 kHz; the seed makes each take repeatable.

    python tools/audio/synth_sfx.py OUT_DIR [name ...]

Writes OUT_DIR/<name>.wav for every recipe (or the ones named).
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_sfx import RATE, write_wav  # noqa: E402


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def env(n, attack, decay_shape=3.0):
    """Attack ramp then a power-curve decay to zero."""
    a = max(1, int(RATE * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    e[a:] = np.linspace(1, 0, n - a) ** decay_shape
    return e


def sweep_sine(f0, f1, seconds, curve=2.0):
    """Sine whose pitch glides from f0 to f1 (exponential-ish)."""
    t = t_axis(seconds)
    k = (t / seconds) ** (1 / curve)
    f = f0 * (f1 / f0) ** k
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def bandpass(x, centre, q):
    """Resonant band-pass (state-variable filter); centre may vary per sample."""
    centre = np.broadcast_to(np.asarray(centre, float), x.shape)
    low = band = 0.0
    out = np.empty_like(x)
    damp = 1.0 / q
    for i, s in enumerate(x):
        f = 2 * np.sin(np.pi * min(centre[i], RATE / 6) / RATE)
        high = s - low - damp * band
        band += f * high
        low += f * band
        out[i] = band
    return out


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    out = np.empty_like(x)
    y = 0.0
    for i, s in enumerate(x):
        y = (1 - a) * s + a * y
        out[i] = y
    return out


def norm(y, peak_db=-1.0):
    y = y - np.mean(y)
    y[:32] *= np.linspace(0, 1, 32)
    y[-64:] *= np.linspace(1, 0, 64)
    return y / max(np.abs(y).max(), 1e-9) * 10 ** (peak_db / 20)


# --- Recipes ------------------------------------------------------------------

def disc_whoosh(seed=0, seconds=0.32, lo=500, hi=2600):
    """A thrown disc cutting the air: band-passed noise sweeping up then down,
    with a fast flutter from the spin."""
    rng = np.random.default_rng(seed)
    n = int(RATE * seconds)
    t = np.linspace(0, 1, n)
    centre = lo + (hi - lo) * np.sin(np.pi * t ** 0.7)
    noise = rng.standard_normal(n)
    y = bandpass(noise, centre, 3.0)
    flutter = 1 + 0.35 * np.sin(2 * np.pi * (38 + 10 * seed) * t * seconds)
    return norm(y * flutter * env(n, 0.06, 1.6), -3.0)


def disc_crack(seed=0):
    """The snap of the release: a click, a bright noise burst and a low knock."""
    rng = np.random.default_rng(seed)
    n = int(RATE * 0.16)
    click = np.zeros(n)
    click[:40] = np.hanning(80)[40:] * rng.choice([-1, 1])
    burst = bandpass(rng.standard_normal(n), 3200 + 400 * seed, 1.4) * env(n, 0.001, 8)
    knock = sweep_sine(260, 90, 0.16, 1.0) * env(n, 0.002, 4)
    return norm(click * 0.8 + burst * 1.0 + knock * 0.7, -2.0)


def power_whoosh(seed=0, seconds=0.75):
    """A power throw: a deeper, longer roar with a rising whine on top."""
    rng = np.random.default_rng(seed)
    n = int(RATE * seconds)
    t = np.linspace(0, 1, n)
    roar = bandpass(rng.standard_normal(n), 250 + 1600 * np.sin(np.pi * t ** 0.6), 2.0)
    whine = sweep_sine(700 + 80 * seed, 2400, seconds, 0.8) * np.sin(np.pi * t) ** 2
    y = roar * env(n, 0.04, 1.2) + whine * 0.18
    return norm(y, -1.0)


def special_launch(seed=0, seconds=1.1):
    """A special move: a synth riser into a blast."""
    rng = np.random.default_rng(seed)
    n = int(RATE * seconds)
    t = t_axis(seconds)
    f = 120 * (16 ** (t / seconds) ** 1.5)
    saw = 2 * ((np.cumsum(f) / RATE) % 1.0) - 1
    saw += 2 * ((np.cumsum(f * 1.01) / RATE) % 1.0) - 1
    saw = lowpass(saw, 3000) * np.linspace(0.2, 1, n)
    blast_n = int(RATE * 0.5)
    blast = np.zeros(n)
    tail = bandpass(rng.standard_normal(blast_n), 900, 0.8) * env(blast_n, 0.002, 3)
    blast[n - blast_n:] = tail[: blast_n]
    y = saw * 0.5 * env(n, 0.3, 0.4) + blast
    return norm(y, -1.0)


def catch_pop(seed=0, weight=1.0):
    """A disc slapping into hands: a low thump under a short leathery pop."""
    rng = np.random.default_rng(seed)
    n = int(RATE * 0.22)
    thump = sweep_sine(150 * weight, 48, 0.22, 0.7) * env(n, 0.002, 3.5)
    pop = bandpass(rng.standard_normal(n), 1400 + 300 * seed, 2.2) * env(n, 0.0008, 14)
    snap = bandpass(rng.standard_normal(n), 4200, 1.5) * env(n, 0.0005, 30)
    return norm(thump * 1.0 + pop * 0.9 + snap * 0.35, -1.0)


def block_clank(seed=0):
    """A block: a hard, ringing deflection."""
    rng = np.random.default_rng(seed)
    n = int(RATE * 0.3)
    t = t_axis(0.3)
    modes = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) * a
                for f, d, a in [(520, 18, 1.0), (1310, 26, 0.6), (2730, 40, 0.35)])
    hit = bandpass(rng.standard_normal(n), 2000, 1.0) * env(n, 0.0005, 20)
    thud = sweep_sine(120, 50, 0.3, 0.7) * env(n, 0.002, 5)
    return norm(modes * 0.7 + hit + thud * 0.6, -2.0)


def wall_tock(seed=0, pitch=1.0):
    """The disc hitting the side wall: a plastic tock with a short ring."""
    rng = np.random.default_rng(seed)
    n = int(RATE * 0.25)
    t = t_axis(0.25)
    modes = sum(np.sin(2 * np.pi * f * pitch * t) * np.exp(-t * d) * a
                for f, d, a in [(640, 30, 1.0), (1530, 45, 0.55), (3120, 70, 0.3)])
    click = bandpass(rng.standard_normal(n), 3000, 1.2) * env(n, 0.0003, 25)
    return norm(modes + click * 0.8, -2.0)


def net_thwack(seed=0):
    """Into the net: a soft thump and a short rattle of mesh."""
    rng = np.random.default_rng(seed)
    n = int(RATE * 0.35)
    t = np.linspace(0, 1, n)
    thump = sweep_sine(110, 55, 0.35, 0.6) * env(n, 0.004, 4)
    rattle = bandpass(rng.standard_normal(n), 2400, 3.0) * (0.5 + 0.5 * np.sin(2 * np.pi * 70 * t * 0.35)) \
        * env(n, 0.01, 2.5)
    return norm(thump + rattle * 0.5, -3.0)


def sand_thud(seed=0):
    """The disc landing in sand: a dull, gritty thud."""
    rng = np.random.default_rng(seed)
    n = int(RATE * 0.2)
    thud = sweep_sine(90, 40, 0.2, 0.6) * env(n, 0.003, 4)
    grit = lowpass(rng.standard_normal(n), 2500) * env(n, 0.002, 6)
    return norm(thud + grit * 0.6, -4.0)


RECIPES = {
    "synth_whoosh_1": lambda: disc_whoosh(0),
    "synth_whoosh_2": lambda: disc_whoosh(1, 0.28, 700, 3200),
    "synth_whoosh_3": lambda: disc_whoosh(2, 0.36, 380, 2000),
    "synth_crack_1": lambda: disc_crack(0),
    "synth_crack_2": lambda: disc_crack(1),
    "synth_power_1": lambda: power_whoosh(0),
    "synth_power_2": lambda: power_whoosh(1, 0.9),
    "synth_special_1": lambda: special_launch(0),
    "synth_catch_1": lambda: catch_pop(0),
    "synth_catch_2": lambda: catch_pop(1, 1.3),
    "synth_catch_3": lambda: catch_pop(2, 0.8),
    "synth_block_1": lambda: block_clank(0),
    "synth_wall_1": lambda: wall_tock(0),
    "synth_wall_2": lambda: wall_tock(1, 0.8),
    "synth_wall_3": lambda: wall_tock(2, 1.25),
    "synth_net_1": lambda: net_thwack(0),
    "synth_ground_1": lambda: sand_thud(0),
}


if __name__ == "__main__":
    out = sys.argv[1]
    names = sys.argv[2:] or list(RECIPES)
    os.makedirs(out, exist_ok=True)
    for name in names:
        write_wav(os.path.join(out, name + ".wav"), RECIPES[name]())
        print("wrote", name)
