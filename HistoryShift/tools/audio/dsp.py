"""Small DSP toolkit for the offline sound generator (numpy + scipy).

Everything here is original procedural synthesis (no samples) and is released
as CC0 together with the generated files.
"""
import numpy as np
from scipy import signal

SR = 44100


def secs(n):
    return n / SR


def N(t):
    return int(round(t * SR))


def tt(n):
    return np.arange(n) / SR


# ------------------------------------------------------------------ noise
def white(rng, n):
    return rng.uniform(-1.0, 1.0, n)


def pink(rng, n):
    # Voss-McCartney approximation through an IIR (Paul Kellet's filter)
    w = rng.standard_normal(n)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    y = signal.lfilter(b, a, w)
    return y / (np.max(np.abs(y)) + 1e-9)


def brown(rng, n):
    y = np.cumsum(rng.standard_normal(n))
    y = signal.lfilter([1, -1], [1, -0.999], y)
    return y / (np.max(np.abs(y)) + 1e-9)


# ------------------------------------------------------------------ filters
def _sos(kind, f, order=2, q=None):
    nyq = SR * 0.5
    if kind == "bp":
        lo, hi = f
        lo = max(lo, 10.0)
        hi = min(hi, nyq * 0.98)
        return signal.butter(order, [lo / nyq, hi / nyq], btype="band", output="sos")
    f = min(max(f, 10.0), nyq * 0.98)
    return signal.butter(order, f / nyq, btype="low" if kind == "lp" else "high", output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lp", f, order), x)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("hp", f, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bp", (lo, hi), order), x)


def reson(x, f, q):
    """2-pole resonator (constant peak gain-ish)."""
    w = 2 * np.pi * f / SR
    r = np.exp(-w / (2 * q))
    b = [(1 - r * r) * 0.5, 0, -(1 - r * r) * 0.5]
    a = [1, -2 * r * np.cos(w), r * r]
    return signal.lfilter(b, a, x)


def tv_lp(x, cut, chunk=256):
    """Time-varying one-pole lowpass; cut is an array (Hz) same length as x."""
    out = np.empty_like(x)
    z = 0.0
    for i in range(0, len(x), chunk):
        c = float(np.mean(cut[i:i + chunk]))
        a = np.exp(-2 * np.pi * c / SR)
        seg, zf = signal.lfilter([1 - a], [1, -a], x[i:i + chunk], zi=[z * a])
        out[i:i + chunk] = seg
        z = seg[-1] if len(seg) else z
    return out


def tv_bp(x, center, q=2.0, chunk=256):
    """Time-varying resonant bandpass (state-variable filter, block-wise coeffs)."""
    out = np.empty_like(x)
    lp_ = 0.0
    bp_ = 0.0
    for i in range(0, len(x), chunk):
        f = float(np.clip(np.mean(center[i:i + chunk]), 20.0, SR * 0.2))
        F = 2 * np.sin(np.pi * f / SR)
        D = 1.0 / q
        seg = x[i:i + chunk]
        o = np.empty_like(seg)
        for k in range(len(seg)):
            hp_ = seg[k] - lp_ - D * bp_
            bp_ += F * hp_
            lp_ += F * bp_
            o[k] = bp_
        out[i:i + chunk] = o
    return out


# ------------------------------------------------------------------ envelopes
def env_exp(n, decay, attack=0.002):
    t = tt(n)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t / max(decay, 1e-5))


def env_ad(n, attack, release, curve=2.0):
    t = tt(n)
    d = secs(n)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    r = np.clip((d - t) / max(release, 1e-5), 0, 1) ** curve
    return a * r


def env_bell(n, peak=0.5, p=2.0):
    x = np.linspace(0, 1, n)
    return np.where(x < peak, (x / peak) ** p, ((1 - x) / (1 - peak)) ** p)


def smooth_rand(rng, n, rate, lo=0.0, hi=1.0):
    """Smoothed random control signal with given average rate (Hz)."""
    k = max(4, int(secs(n) * rate) + 4)
    pts = rng.uniform(lo, hi, k)
    xs = np.linspace(0, n, k)
    return np.interp(np.arange(n), xs, pts)


def fade(x, fin=0.003, fout=0.01):
    n = len(x)
    a = min(N(fin), n // 2)
    b = min(N(fout), n // 2)
    y = x.copy()
    if a > 0:
        y[:a] *= np.linspace(0, 1, a)
    if b > 0:
        y[-b:] *= np.linspace(1, 0, b) ** 2
    return y


# ------------------------------------------------------------------ building blocks
def modal(n, freqs, decays, amps, rng=None, jitter=0.0):
    t = tt(n)
    y = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        if rng is not None and jitter > 0:
            f *= 1 + rng.uniform(-jitter, jitter)
        ph = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
        y += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / d)
    return y


def click(n, rng, lo=1500, hi=9000, dur=0.002):
    m = min(n, max(8, N(dur)))
    y = np.zeros(n)
    y[:m] = bp(white(rng, m), lo, hi) * np.exp(-np.arange(m) / (m / 4))
    return y


def place(dst, src, at, gain=1.0):
    i = int(at)
    if i >= len(dst) or i + len(src) <= 0:
        return dst
    s0 = max(0, -i)
    i0 = max(0, i)
    m = min(len(src) - s0, len(dst) - i0)
    dst[i0:i0 + m] += src[s0:s0 + m] * gain
    return dst


def grains(rng, n, count, lo, hi, dur=(0.0008, 0.004), shape=None, amp=(0.2, 1.0), span=None):
    """Scatter short filtered noise grains (gravel crunch, debris, crackle)."""
    y = np.zeros(n)
    span = span if span is not None else n
    for _ in range(count):
        if shape is None:
            at = rng.uniform(0, span)
        else:
            at = shape(rng) * span
        d = rng.uniform(*dur)
        m = max(8, N(d))
        g = white(rng, m) * np.exp(-np.arange(m) / (m / 3.5))
        f0 = rng.uniform(lo, hi)
        g = bp(g, f0 * 0.6, min(f0 * 1.6, SR * 0.45))
        place(y, g, at, rng.uniform(*amp))
    return y


def bubble(n, f0, dur, rise=0.3, amp=1.0, rng=None):
    m = min(n, N(dur))
    t = tt(m)
    f = f0 * (1 + rise * t / max(dur, 1e-4))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.zeros(n)
    y[:m] = np.sin(ph) * np.exp(-t / (dur / 3.0)) * amp
    return y


def ks_pluck(f0, dur, rng, bright=0.6, decay=0.996, os=4, pick=0.12):
    """Karplus-Strong plucked string synthesised at os x rate then decimated."""
    sr = SR * os
    n = int(dur * sr)
    D = sr / f0
    L = int(np.floor(D - 0.5))
    exc = rng.uniform(-1, 1, L)
    # pick position comb + brightness lowpass on the excitation
    k = max(1, int(L * pick))
    exc = exc - np.concatenate([np.zeros(k), exc[:-k]])
    b_, a_ = signal.butter(1, min(0.99, 2000 * (0.5 + bright * 3) / (sr / 2)))
    exc = signal.lfilter(b_, a_, exc)
    x = np.zeros(n)
    x[:L] = exc
    a = np.zeros(L + 2)
    a[0] = 1.0
    a[L] = -decay * 0.5
    a[L + 1] = -decay * 0.5
    y = signal.lfilter([1.0], a, x)
    y = signal.resample_poly(y, 1, os)
    return y / (np.max(np.abs(y)) + 1e-9)


def ir_room(rng, length, decay, lp_hz=6000, early=None, stereo=False):
    n = N(length)
    t = tt(n)

    def one():
        e = white(rng, n) * np.exp(-t / decay)
        e = lp(e, lp_hz)
        if early:
            for (d, g) in early:
                i = N(d)
                if i < n:
                    e[i] += g
        e[0] = 1.0
        return e / np.sqrt(np.sum(e ** 2))
    if stereo:
        return np.stack([one(), one()])
    return one()


def conv(x, ir, wet=0.3):
    y = signal.fftconvolve(x, ir)[:len(x)]
    return x * (1 - wet * 0.5) + y * wet


def outdoor_tail(rng, x, length=1.6, wet=0.35, echoes=((0.31, 0.35), (0.58, 0.22), (0.93, 0.12))):
    """Sparse outdoor reflections (hills / buildings) + diffuse tail."""
    n = len(x) + N(length)
    y = np.zeros(n)
    y[:len(x)] = x
    ir = ir_room(rng, length, length / 5.0, lp_hz=2500)
    d = signal.fftconvolve(x, ir)[:n]
    d = d / (np.max(np.abs(d)) + 1e-9) * np.max(np.abs(x))
    y += np.pad(d, (0, n - len(d))) * wet * 0.4
    for (dt, g) in echoes:
        e = lp(x, 1800) * g * 0.5
        place(y, e, N(dt))
    return y


def make_loop(x, xfade):
    """Make x seamlessly loopable: returns len(x)-xfade samples (works on 1D or 2D [ch, n])."""
    k = N(xfade)
    if x.ndim == 1:
        L = len(x) - k
        out = x[:L].copy()
        w = np.linspace(0, np.pi / 2, k)
        out[:k] = x[:k] * np.sin(w) + x[L:L + k] * np.cos(w)
        return out
    return np.stack([make_loop(c, xfade) for c in x])


def norm_peak(x, db=-1.0):
    p = np.max(np.abs(x)) + 1e-12
    return x * (10 ** (db / 20) / p)


def norm_rms(x, db=-20.0, peak_db=-1.0):
    r = np.sqrt(np.mean(x ** 2)) + 1e-12
    y = x * (10 ** (db / 20) / r)
    p = np.max(np.abs(y))
    lim = 10 ** (peak_db / 20)
    if p > lim:
        y = soft_limit(y, lim)
    return y


def soft_limit(x, lim=0.9):
    return np.tanh(x / lim) * lim


def pan(x, p):
    """p in [-1, 1] -> stereo [2, n] equal power."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)])


def resample(x, ratio):
    """ratio > 1 -> higher pitch / shorter."""
    from fractions import Fraction
    fr = Fraction(1 / ratio).limit_denominator(64)
    return signal.resample_poly(x, fr.numerator, fr.denominator)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)
