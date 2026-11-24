"""Ambience beds (stereo loops) and ambient spot one-shots (birds, bells, insects...)."""
import numpy as np
from dsp import *          # noqa: F401,F403
from registry import sfx
from gen_sfx import temple_bell_core, thump, _clack


def st(rng, fn, n, spread=0.8):
    """Two decorrelated renders -> stereo."""
    a = fn(np.random.default_rng(rng.integers(1 << 30)), n)
    b = fn(np.random.default_rng(rng.integers(1 << 30)), n)
    m = (a + b) * 0.5
    return np.stack([m + (a - m) * spread, m + (b - m) * spread])


def scatter_st(rng, n, count, make, spread=0.9, pos=None):
    """Place mono events at random times / pans into a stereo buffer."""
    y = np.zeros((2, n))
    for k in range(count):
        ev = make(rng)
        at = int(rng.uniform(0, n - 1)) if pos is None else int(pos(rng, k) * n)
        p = rng.uniform(-spread, spread)
        s = pan(ev, p)
        for c in range(2):
            place(y[c], s[c], at)
    return y


def wrap_add(dst, src, at):
    """Add src into a loop buffer with wrap-around (keeps loops seamless)."""
    n = dst.shape[-1]
    idx = (np.arange(src.shape[-1]) + at) % n
    if dst.ndim == 1:
        np.add.at(dst, idx, src)
    else:
        for c in range(dst.shape[0]):
            np.add.at(dst[c], idx, src[c])


def scatter_loop(rng, n, count, make, spread=0.9, gain=(0.5, 1.0)):
    y = np.zeros((2, n))
    for k in range(count):
        ev = make(rng) * rng.uniform(*gain)
        wrap_add(y, pan(ev, rng.uniform(-spread, spread)), int(rng.uniform(0, n)))
    return y


# =================================================================== wind
def _wind(rng, n, strength):
    g = smooth_rand(rng, n, 0.15, 0.3, 1.0) * smooth_rand(rng, n, 0.6, 0.6, 1.0)
    base = pink(rng, n)
    c = 300 + 900 * strength * g
    y = tv_lp(base, c) * (0.4 + 0.6 * g)
    y += bp(base, 1500, 5000) * g ** 2 * 0.08 * strength
    if strength > 0.8:
        f = 600 + 300 * smooth_rand(rng, n, 0.3)
        y += np.sin(2 * np.pi * np.cumsum(f) / SR) * g ** 3 * 0.03
    return y


@sfx("amb_wind_light", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_wind_light(rng, i):
    """Light breeze bed."""
    n = N(32)
    y = st(rng, lambda r, m: _wind(r, m, 0.5), n, 0.9)
    return make_loop(norm_rms(y, -24), 2.0)


@sfx("amb_wind_strong", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_wind_strong(rng, i):
    """Strong gusting wind (mountain, open sea, heights)."""
    n = N(32)
    y = st(rng, lambda r, m: _wind(r, m, 1.0), n, 0.9)
    return make_loop(norm_rms(y, -20), 2.0)


# =================================================================== birds (spot one-shots, mono)
def chirp(rng, f0, f1, d, harm=0.15):
    n = N(d)
    f = np.interp(np.linspace(0, 1, n), [0, 1], [f0, f1])
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + harm * np.sin(2 * ph)) * env_bell(n, 0.3, 1.5)


@sfx("bird_uguisu", n=3, db=-12, bus="Ambience")
def bird_uguisu(rng, i):
    """Japanese bush warbler 'hoo-hokekyo'."""
    y = np.zeros(N(2.6))
    n1 = N(rng.uniform(0.8, 1.1))
    f = np.interp(np.linspace(0, 1, n1), [0, 0.7, 1], [1150, 1250, 1300]) * (1 + 0.004 * np.sin(np.linspace(0, 60, n1)))
    hoo = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n1, 0.15, 0.2, 1.2)
    place(y, hoo, 0)
    at = n1 + N(0.12)
    for (a, b, d) in [(2300, 2100, 0.08), (2600, 2700, 0.1), (2900, 1800, 0.26)]:
        c = chirp(rng, a, b, d, 0.1)
        place(y, c, at)
        at += len(c) + N(0.03)
    return norm_peak(fade(conv(y, ir_room(rng, 0.9, 0.2, 7000), 0.25)), -2)


@sfx("bird_chirp", n=6, db=-14, bus="Ambience")
def bird_chirp(rng, i):
    """Small songbird phrases (sparrow / white-eye)."""
    n = N(1.6)
    y = np.zeros(n)
    at = 0
    for k in range(rng.integers(3, 9)):
        f0 = rng.uniform(3000, 6500)
        c = chirp(rng, f0, f0 * rng.uniform(0.6, 1.3), rng.uniform(0.03, 0.09), 0.05)
        place(y, c, at)
        at += len(c) + N(rng.uniform(0.02, 0.18))
    return norm_peak(fade(conv(y, ir_room(rng, 0.7, 0.15, 8000), 0.2)), -2)


@sfx("bird_hiyodori", n=2, db=-13, bus="Ambience")
def bird_hiyodori(rng, i):
    """Brown-eared bulbul 'piii-yo' (harsh)."""
    y = np.zeros(N(1.2))
    a = chirp(rng, 3200, 3600, 0.25, 0.4)
    b = chirp(rng, 3800, 2400, 0.3, 0.4)
    place(y, a, 0)
    place(y, b, len(a) + N(0.05))
    y += bp(np.random.default_rng(1).uniform(-1, 1, len(y)), 2500, 5000) * np.abs(y) * 0.5
    return norm_peak(fade(y), -2)


@sfx("bird_crow", n=3, db=-11, bus="Ambience")
def bird_crow(rng, i):
    """Large-billed crow 'kaa kaa'."""
    y = np.zeros(N(2.0))
    at = 0
    for k in range(rng.integers(2, 4)):
        d = rng.uniform(0.28, 0.4)
        m = N(d)
        f0 = np.interp(np.linspace(0, 1, m), [0, 0.3, 1], [rng.uniform(550, 650), rng.uniform(700, 800), rng.uniform(450, 550)])
        ph = 2 * np.pi * np.cumsum(f0) / SR
        src = sum(np.sin(h * ph) / h for h in range(1, 14)) + white(rng, m) * 0.5
        v = reson(src, 1200, 3) + reson(src, 2200, 4) * 0.7
        place(y, v * env_ad(m, 0.03, d * 0.6), at)
        at += m + N(rng.uniform(0.15, 0.3))
    return norm_peak(fade(conv(y, ir_room(rng, 1.4, 0.3, 5000), 0.3)), -2)


@sfx("bird_kite", n=2, db=-13, bus="Ambience")
def bird_kite(rng, i):
    """Black kite (tobi) 'pii-hyororo' high above."""
    y = np.zeros(N(2.4))
    a = chirp(rng, 2800, 3100, 0.55, 0.05)
    place(y, a, 0)
    at = len(a) + N(0.05)
    for k in range(6):
        c = chirp(rng, 2900 - k * 120, 2200 - k * 100, 0.09, 0.05)
        place(y, c, at)
        at += len(c) + N(0.015)
    return norm_peak(fade(conv(y, ir_room(rng, 1.8, 0.45, 6000), 0.35)), -2)


@sfx("bird_owl", n=2, db=-12, bus="Ambience")
def bird_owl(rng, i):
    """Ural owl hoots at night."""
    y = np.zeros(N(2.4))
    for k, (at, d) in enumerate([(0.0, 0.35), (0.55, 0.25), (0.95, 0.5)]):
        m = N(d)
        f = np.interp(np.linspace(0, 1, m), [0, 1], [430, 380])
        h = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_bell(m, 0.4, 1.3) + bp(white(rng, m), 300, 900) * 0.08
        place(y, h, N(at))
    return norm_peak(fade(conv(y, ir_room(rng, 1.8, 0.45, 3000), 0.35)), -2)


@sfx("bird_gull", n=2, db=-13, bus="Ambience")
def bird_gull(rng, i):
    """Black-tailed gull (umineko) mewing near the sea."""
    y = np.zeros(N(1.6))
    at = 0
    for k in range(rng.integers(2, 4)):
        d = rng.uniform(0.25, 0.4)
        m = N(d)
        f0 = np.interp(np.linspace(0, 1, m), [0, 0.4, 1], [900, 1300, 800])
        ph = 2 * np.pi * np.cumsum(f0) / SR
        src = sum(np.sin(h * ph) / h ** 1.3 for h in range(1, 8))
        place(y, reson(src, 1800, 3) * env_bell(m, 0.3), at)
        at += m + N(rng.uniform(0.08, 0.2))
    return norm_peak(fade(conv(y, ir_room(rng, 1.4, 0.3, 5000), 0.3)), -2)


@sfx("amb_birds_day", n=1, loop=True, stereo=True, db=-12, bus="Ambience")
def amb_birds_day(rng, i):
    """Distant forest birds bed (sparse, loopable)."""
    n = N(40)
    y = scatter_loop(rng, n, 45, lambda r: lp(bird_chirp(r, 0), 6000), 0.9, (0.15, 0.5))
    y += scatter_loop(rng, n, 3, lambda r: bird_uguisu(r, 0), 0.8, (0.2, 0.4))
    y += st(rng, lambda r, m: _wind(r, m, 0.25), n, 0.9) * 0.05
    return make_loop(norm_rms(y, -30), 1.5)


# =================================================================== insects / frogs
def cicada_minmin(rng, n):
    """Robust cicada (minmin-zemi) 'miiin min min min mii'."""
    t = tt(n)
    y = np.zeros(n)
    at = 0
    while at < n:
        d = rng.uniform(4.0, 7.0)
        m = N(d)
        tm = tt(m)
        rate = np.interp(tm, [0, d * 0.2, d * 0.8, d], [1.5, 3.2, 3.2, 1.0])
        am = 0.55 + 0.45 * np.sin(2 * np.pi * np.cumsum(rate) / SR) ** 2
        car = 2 * np.pi * np.cumsum(np.full(m, rng.uniform(3600, 4200))) / SR
        tone = np.sin(car) * (0.5 + 0.5 * np.sin(2 * np.pi * 180 * tm)) + bp(white(rng, m), 3000, 7000) * 0.3
        place(y, tone * am * env_ad(m, 0.5, 1.2, 1.2), at)
        at += m + N(rng.uniform(1.0, 4.0))
    return y


def cicada_abura(rng, n):
    """Large brown cicada (abura-zemi) continuous sizzling."""
    y = bp(white(rng, n), 2500, 9000) * (0.5 + 0.5 * smooth_rand(rng, n, 0.3))
    y *= 0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 85 * tt(n)))
    return y


def higurashi(rng, n):
    """Evening cicada 'kana-kana-kana'."""
    y = np.zeros(n)
    at = 0
    while at < n:
        reps = rng.integers(10, 20)
        f0 = rng.uniform(4300, 4800)
        for k in range(reps):
            d = 0.1
            m = N(d)
            f = np.interp(np.linspace(0, 1, m), [0, 1], [f0 * 1.06, f0 * 0.94]) * (1 - 0.15 * k / reps)
            place(y, np.sin(2 * np.pi * np.cumsum(f) / SR) * env_bell(m, 0.2, 1.5) * (1 - 0.6 * k / reps), at + N(k * 0.135))
        at += N(reps * 0.135 + rng.uniform(2.0, 5.0))
    return y


@sfx("amb_cicada_summer", n=1, loop=True, stereo=True, db=-12, bus="Ambience")
def amb_cicada_summer(rng, i):
    """Summer daytime cicadas (minmin + abura-zemi) in the trees."""
    n = N(30)
    y = st(rng, lambda r, m: cicada_abura(r, m), n, 0.7) * 0.25
    for k in range(4):
        r2 = np.random.default_rng(rng.integers(1 << 30))
        y += pan(lp(cicada_minmin(r2, n), 9000), rng.uniform(-0.8, 0.8)) * rng.uniform(0.3, 0.7)
    return make_loop(norm_rms(y, -24), 2.0)


@sfx("amb_higurashi", n=1, loop=True, stereo=True, db=-12, bus="Ambience")
def amb_higurashi(rng, i):
    """Evening higurashi cicadas, distant and echoing."""
    n = N(30)
    y = np.zeros((2, n))
    for k in range(4):
        r2 = np.random.default_rng(rng.integers(1 << 30))
        y += pan(conv(higurashi(r2, n), ir_room(r2, 1.5, 0.4, 6000), 0.4), rng.uniform(-0.9, 0.9)) * rng.uniform(0.3, 0.8)
    return make_loop(norm_rms(y, -26), 2.0)


def suzumushi(rng, n):
    """Bell cricket 'riiin': tonal pulse-train chirps."""
    y = np.zeros(n)
    f = rng.uniform(4300, 4700)
    at = 0
    while at < n:
        d = rng.uniform(0.25, 0.5)
        m = N(d)
        pr = rng.uniform(28, 40)
        tone = np.sin(2 * np.pi * f * tt(m)) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * pr * tt(m))))
        place(y, lp(tone, 7000) * env_ad(m, 0.02, 0.08), at)
        at += m + N(rng.uniform(0.6, 1.6))
    return y


def korogi(rng, n):
    """Field cricket 'koro koro riii'."""
    y = np.zeros(n)
    f = rng.uniform(3800, 4300)
    at = 0
    while at < n:
        reps = rng.integers(3, 7)
        for k in range(reps):
            m = N(0.045)
            place(y, np.sin(2 * np.pi * f * tt(m)) * env_bell(m, 0.3), at + N(k * 0.06))
        at += N(reps * 0.06 + rng.uniform(0.3, 0.9))
    return y


@sfx("amb_night_insects", n=1, loop=True, stereo=True, db=-12, bus="Ambience")
def amb_night_insects(rng, i):
    """Autumn night: suzumushi, korogi and a soft breeze."""
    n = N(30)
    y = np.zeros((2, n))
    for k in range(6):
        r2 = np.random.default_rng(rng.integers(1 << 30))
        y += pan(suzumushi(r2, n), rng.uniform(-0.9, 0.9)) * rng.uniform(0.2, 0.6)
    for k in range(8):
        r2 = np.random.default_rng(rng.integers(1 << 30))
        y += pan(korogi(r2, n), rng.uniform(-0.9, 0.9)) * rng.uniform(0.1, 0.4)
    y += st(rng, lambda r, m: _wind(r, m, 0.2), n) * 0.1
    return make_loop(norm_rms(y, -27), 2.0)


@sfx("amb_frogs", n=1, loop=True, stereo=True, db=-12, bus="Ambience")
def amb_frogs(rng, i):
    """Rice-paddy frogs chorus (kero kero)."""
    n = N(30)

    def croak(r):
        reps = r.integers(2, 6)
        f = r.uniform(500, 1100)
        out = np.zeros(N(1.2))
        for k in range(reps):
            m = N(0.07)
            ph = 2 * np.pi * f * tt(m)
            src = np.sign(np.sin(ph)) * 0.4 + np.sin(ph)
            place(out, reson(src, f * 2.2, 3) * env_bell(m, 0.3), N(k * 0.12))
        return out
    y = scatter_loop(rng, n, 160, croak, 0.95, (0.1, 0.6))
    return make_loop(norm_rms(y, -26), 2.0)


# =================================================================== water
@sfx("amb_sea_waves", n=1, loop=True, stereo=True, db=-8, bus="Ambience")
def amb_sea_waves(rng, i):
    """Waves breaking on the shore with foam hiss (loop)."""
    n = N(36)
    y = st(rng, lambda r, m: lp(brown(r, m), 250) * 0.5, n, 0.6)
    at = 0.0
    while at < 36:
        d = rng.uniform(5.0, 8.0)
        m = N(d)
        tm = np.linspace(0, 1, m)
        env = np.interp(tm, [0, 0.3, 0.38, 1], [0.05, 0.6, 1.0, 0.0]) ** 1.3
        def one(r, mm):
            nz = pink(r, mm)
            c = np.interp(np.linspace(0, 1, mm), [0, 0.35, 0.5, 1], [400, 1400, 3500, 1800])
            return tv_lp(nz, c) * 0.8 + bp(white(r, mm), 3000, 9000) * np.clip(np.linspace(0, 1, mm) * 3 - 1, 0, 1) * 0.15
        w = st(rng, one, m, 0.7) * env
        wrap_add(y, w * rng.uniform(0.6, 1.0), N(at))
        at += d * rng.uniform(0.55, 0.85)
    return make_loop(norm_rms(y, -20), 2.5)


@sfx("amb_lapping", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_lapping(rng, i):
    """Water lapping against a pier / hull (gentle)."""
    n = N(20)

    def lap(r):
        m = N(r.uniform(0.3, 0.8))
        out = bp(white(r, m), 200, 1500) * env_bell(m, 0.3) * 0.6
        for k in range(4):
            place(out, bubble(N(0.05), r.uniform(300, 900), 0.03, 0.4, 0.3), N(r.uniform(0, 0.3)))
        return out
    y = scatter_loop(rng, n, 50, lap, 0.7, (0.3, 1.0))
    y += st(rng, lambda r, m: lp(brown(r, m), 200) * 0.3, n)
    return make_loop(norm_rms(y, -24), 1.5)


@sfx("amb_river", n=1, loop=True, stereo=True, db=-9, bus="Ambience")
def amb_river(rng, i):
    """River / stream babbling over stones (loop)."""
    n = N(24)

    def babble(r, m):
        out = bp(pink(r, m), 300, 3000) * (0.5 + 0.5 * smooth_rand(r, m, 3)) * 0.4
        for k in range(int(m / SR * 70)):
            place(out, bubble(N(0.04), r.uniform(500, 3500), r.uniform(0.006, 0.03), r.uniform(0.2, 0.9), r.uniform(0.05, 0.35)), r.uniform(0, m))
        return out
    y = st(rng, babble, n, 0.9)
    return make_loop(norm_rms(y, -22), 1.5)


# =================================================================== people / town
VOWELS = {"a": (800, 1200), "i": (300, 2300), "u": (350, 1300), "e": (500, 1900), "o": (500, 850)}


def babble_voice(rng, n, f0, dist=0.0):
    """Unintelligible Japanese-like speech: syllables of formant-filtered buzz."""
    y = np.zeros(n)
    at = int(rng.uniform(0, SR))
    while at < n:
        words = rng.integers(2, 7)
        for w in range(words):
            d = rng.uniform(0.09, 0.2)
            m = N(d)
            v = VOWELS[rng.choice(list(VOWELS))]
            ff = f0 * (1 + 0.15 * rng.uniform(-1, 1)) * np.interp(np.linspace(0, 1, m), [0, 1], [1.05, 0.95])
            ph = 2 * np.pi * np.cumsum(ff) / SR
            src = sum(np.sin(h * ph) / h for h in range(1, 18)) + white(rng, m) * 0.08
            syl = reson(src, v[0], 5) + reson(src, v[1], 8) * 0.6
            if rng.uniform() < 0.5:   # consonant
                syl[:N(0.02)] += bp(white(rng, N(0.02)), 2500, 7000) * 0.8
            place(y, syl * env_bell(m, 0.3, 1.2), at)
            at += m
        at += N(rng.uniform(0.3, 2.5))
    return y


@sfx("amb_crowd_town", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_crowd_town(rng, i):
    """Town / market murmur: many distant voices, footsteps and wares (loop)."""
    n = N(30)
    y = np.zeros((2, n))
    for k in range(16):
        r2 = np.random.default_rng(rng.integers(1 << 30))
        f0 = rng.choice([rng.uniform(100, 140), rng.uniform(190, 260)])
        v = lp(babble_voice(r2, n, f0), rng.uniform(1800, 3500)) * rng.uniform(0.2, 0.7)
        y += pan(v, rng.uniform(-0.9, 0.9))
    y = np.stack([conv(y[0], ir_room(rng, 1.2, 0.3, 4000), 0.5), conv(y[1], ir_room(rng, 1.2, 0.3, 4000), 0.5)])
    y += scatter_loop(rng, n, 60, lambda r: lp(thump(r, N(0.15), 180, 0.02, 0.4) + bp(white(r, N(0.15)), 500, 2500) * env_exp(N(0.15), 0.02) * 0.3, 2500), 0.9, (0.05, 0.25))
    y += scatter_loop(rng, n, 10, lambda r: lp(_clack(r, N(0.1), r.uniform(800, 1500), 0.4), 3000), 0.9, (0.05, 0.2))
    return make_loop(norm_rms(y, -24), 2.0)


@sfx("amb_battle_distant", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_battle_distant(rng, i):
    """Distant battle: war cries, drums, conch and scattered gunfire (sengoku field)."""
    n = N(30)
    y = np.zeros((2, n))
    for k in range(20):
        r2 = np.random.default_rng(rng.integers(1 << 30))
        y += pan(lp(babble_voice(r2, n, rng.uniform(120, 170)), 1500) * 0.4, rng.uniform(-0.9, 0.9))

    def shot(r):
        m = N(1.5)
        return lp(lp(white(r, m), 400) * np.exp(-tt(m) / 0.12) * 2 + lp(brown(r, m), 120) * np.exp(-tt(m) / 0.5), 900)
    y += scatter_loop(rng, n, 18, shot, 0.9, (0.2, 0.7))
    from gen_sfx import taiko
    y += scatter_loop(rng, n, 40, lambda r: lp(taiko(r, 60, 0.8), 800), 0.6, (0.2, 0.5))
    y = np.stack([conv(y[0], ir_room(rng, 2.5, 0.6, 2500), 0.6), conv(y[1], ir_room(rng, 2.5, 0.6, 2500), 0.6)])
    return make_loop(norm_rms(y, -24), 2.0)


# =================================================================== bells
@sfx("temple_bell", n=1, db=-4, bus="Ambience")
def temple_bell(rng, i):
    """Bonshō temple bell: beam strike, deep hum with beating partials, long decay."""
    d = 16.0
    y = temple_bell_core(rng, 128.0, d)
    y += thump(rng, N(d), 80, 0.06, 1.0) * 0.6
    return norm_peak(fade(conv(y, ir_room(rng, 3.0, 0.8, 3000), 0.25), 0.001, 2.0), -1)


@sfx("wind_chime", n=3, db=-14, bus="Ambience")
def wind_chime(rng, i):
    """Furin glass wind chime (summer)."""
    n = N(2.4)
    y = np.zeros(n)
    for k in range(rng.integers(1, 4)):
        f = rng.uniform(2600, 3300)
        place(y, modal(N(2.0), [f, f * 2.37, f * 4.1], [0.8, 0.4, 0.2], [0.5, 0.2, 0.08], rng) + click(N(2.0), rng, 3000, 9000) * 0.2, N(rng.uniform(0, 0.4)))
    return norm_peak(fade(y), -2)


@sfx("dog_bark", n=2, db=-12, bus="Ambience")
def dog_bark(rng, i):
    """Distant village dog barking."""
    y = np.zeros(N(1.6))
    at = 0
    for k in range(rng.integers(1, 4)):
        d = rng.uniform(0.12, 0.18)
        m = N(d)
        f0 = np.interp(np.linspace(0, 1, m), [0, 0.3, 1], [400, 650, 350])
        ph = 2 * np.pi * np.cumsum(f0) / SR
        src = sum(np.sin(h * ph) / h for h in range(1, 12)) + white(rng, m) * 0.6
        v = reson(src, 900, 3) + reson(src, 1800, 4) * 0.6
        place(y, v * env_ad(m, 0.01, d * 0.7), at)
        at += m + N(rng.uniform(0.2, 0.35))
    return norm_peak(fade(lp(conv(y, ir_room(rng, 1.5, 0.35, 4000), 0.4), 3500)), -2)


@sfx("train_whistle", n=1, db=-8, bus="Ambience")
def train_whistle(rng, i):
    """Distant steam locomotive whistle (Meiji/Taisho/Showa railway)."""
    d = 2.2
    n = N(d)
    t = tt(n)
    y = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((540, 0.5), (680, 0.4), (810, 0.3))) + bp(white(rng, n), 500, 2500) * 0.15
    y *= env_ad(n, 0.1, 0.5) * np.where(t < 0.5, 1, np.where(t < 0.65, 0.2, 1))
    return norm_peak(fade(lp(outdoor_tail(rng, y, 2.5, 0.6), 4000)), -2)


# =================================================================== interiors / vehicles beds
@sfx("amb_room_wood", n=1, loop=True, stereo=True, db=-14, bus="Ambience")
def amb_room_wood(rng, i):
    """Quiet wooden room tone with distant outdoor bleed and the odd creak."""
    n = N(20)
    y = st(rng, lambda r, m: lp(brown(r, m), 180) * 0.6 + lp(pink(r, m), 700) * 0.15, n)
    def creak(r):
        m = N(0.6)
        rate = np.full(m, r.uniform(30, 80))
        pulses = (np.diff(np.floor(np.cumsum(rate) / SR), prepend=0) > 0).astype(float)
        return lp(reson(pulses, r.uniform(300, 500), 10) * env_bell(m, 0.5), 2000) * 0.3
    y += scatter_loop(rng, n, 3, creak, 0.6, (0.2, 0.5))
    return make_loop(norm_rms(y, -36), 1.5)


@sfx("amb_room_modern", n=1, loop=True, stereo=True, db=-14, bus="Ambience")
def amb_room_modern(rng, i):
    """Brick / concrete building: soft ventilation and electrical hum."""
    n = N(20)
    t = tt(n)
    y = st(rng, lambda r, m: lp(pink(r, m), 900) * 0.4, n)
    hum = (np.sin(2 * np.pi * 50 * t) * 0.3 + np.sin(2 * np.pi * 100 * t) * 0.15) * 0.3
    y += np.stack([hum, hum])
    return make_loop(norm_rms(y, -36), 1.5)


@sfx("amb_ship_wood", n=1, loop=True, stereo=True, db=-8, bus="Ambience")
def amb_ship_wood(rng, i):
    """Wooden ship: hull and rigging creaks, water against the planks (loop)."""
    n = N(30)

    def creak(r):
        d = r.uniform(0.5, 1.6)
        m = N(d)
        rate = np.interp(tt(m), [0, d * 0.5, d], [r.uniform(10, 25), r.uniform(60, 160), r.uniform(15, 40)])
        pulses = (np.diff(np.floor(np.cumsum(rate) / SR), prepend=0) > 0).astype(float)
        return (reson(pulses, r.uniform(200, 450), 9) + reson(pulses, r.uniform(700, 1200), 12) * 0.4) * env_bell(m, 0.5)
    y = scatter_loop(rng, n, 22, creak, 0.9, (0.2, 0.9))
    lap = amb_lapping(rng, 0)
    y += np.tile(lap, (1, n // lap.shape[1] + 1))[:, :n] * 0.8
    y += st(rng, lambda r, m: lp(brown(r, m), 150) * 0.4, n)
    return make_loop(norm_rms(y, -22), 2.0)


@sfx("amb_ship_steel", n=1, loop=True, stereo=True, db=-8, bus="Ambience")
def amb_ship_steel(rng, i):
    """Steel warship interior: turbines, blowers, 60 Hz hum, distant machinery."""
    n = N(24)
    t = tt(n)
    hum = np.sin(2 * np.pi * 60 * t) * 0.25 + np.sin(2 * np.pi * 120 * t) * 0.12 + np.sin(2 * np.pi * 180 * t) * 0.05
    turb = np.sin(2 * np.pi * 410 * t + 0.3 * np.sin(2 * np.pi * 0.2 * t)) * 0.03
    y = st(rng, lambda r, m: lp(brown(r, m), 120) * 0.9 + bp(pink(r, m), 200, 1800) * 0.25, n)
    y += np.stack([hum + turb, hum + turb])
    thumps = np.zeros(n)
    for k in range(int(24 * 3.0)):
        place(thumps, lp(white(rng, N(0.08)), 200) * np.exp(-tt(N(0.08)) / 0.03) * 0.3, N(k / 3.0))
    y += np.stack([thumps, thumps])
    return make_loop(norm_rms(y, -20), 1.0)


@sfx("amb_lab", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_lab(rng, i):
    """2026 time lab: server fans, 50 Hz hum, the machine's slow pulsing drone."""
    n = N(24)
    t = tt(n)
    y = st(rng, lambda r, m: bp(pink(r, m), 300, 4000) * 0.35 + lp(brown(r, m), 100) * 0.3, n)
    hum = np.sin(2 * np.pi * 50 * t) * 0.2 + np.sin(2 * np.pi * 150 * t) * 0.06
    fan = np.sin(2 * np.pi * 183 * t) * 0.03
    drone = sum(np.sin(2 * np.pi * f * t + k) for k, f in enumerate((110, 164.8, 220.5))) * 0.04 * (0.6 + 0.4 * np.sin(2 * np.pi * t / 6.0))
    y += np.stack([hum + fan + drone, hum + fan * 0.8 + drone])
    return make_loop(norm_rms(y, -26), 1.0)


@sfx("lab_beep", n=3, db=-16, bus="Ambience")
def lab_beep(rng, i):
    """Instrument beeps in the lab."""
    n = N(0.5)
    y = np.zeros(n)
    for k in range(rng.integers(1, 4)):
        m = N(0.07)
        place(y, np.sin(2 * np.pi * rng.choice([1320, 1760, 2093]) * tt(m)) * env_ad(m, 0.003, 0.02), N(k * 0.11))
    return norm_peak(fade(y), -3)


@sfx("amb_city_traffic", n=1, loop=True, stereo=True, db=-9, bus="Ambience")
def amb_city_traffic(rng, i):
    """2026 city street: road rumble, cars passing, distant crossing signal."""
    n = N(40)
    y = st(rng, lambda r, m: lp(pink(r, m), 600) * 0.4 + lp(brown(r, m), 120) * 0.4, n)

    def passby(r):
        d = r.uniform(2.5, 4.5)
        m = N(d)
        tm = np.linspace(-1, 1, m)
        g = 1 / (1 + (tm * r.uniform(3, 6)) ** 2)
        tire = bp(white(r, m), 400, 3000) * g
        f = np.interp(tm, [-1, 0, 1], [r.uniform(95, 115), 100, r.uniform(80, 90)])
        eng = np.sin(2 * np.pi * np.cumsum(f) / SR) * g * 0.3
        return tire + eng
    for k in range(16):
        ev = passby(rng) * rng.uniform(0.3, 1.0)
        p0 = rng.uniform(-1, 1)
        m = ev.shape[0]
        pr = np.linspace(p0, -p0, m)
        a = (pr + 1) * np.pi / 4
        wrap_add(y, np.stack([ev * np.cos(a), ev * np.sin(a)]), int(rng.uniform(0, n)))
    sig = np.zeros(N(3.0))
    for k in range(6):
        place(sig, chirp(rng, 2600, 1900, 0.12, 0.0) * 0.3, N(k * 0.45))
    wrap_add(y, pan(lp(sig, 4000) * 0.15, 0.6), N(12))
    return make_loop(norm_rms(y, -22), 2.0)


@sfx("amb_factory", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_factory(rng, i):
    """Meiji silk mill / ironworks: rhythmic machinery and belts."""
    n = N(16)
    y = st(rng, lambda r, m: lp(brown(r, m), 200) * 0.5 + bp(pink(r, m), 500, 3000) * 0.2, n)
    y = make_loop(y, 1.0)
    n = y.shape[1]
    rhythm = np.zeros(n)
    for k in range(int(n / SR * 4)):
        wrap_add(rhythm, _clack(rng, N(0.08), rng.uniform(600, 900), 0.5 if k % 2 else 0.8), N(k / 4.0))
    y += np.stack([rhythm, rhythm * 0.9])
    return norm_rms(y, -24)
