"""Weather sounds (procedural, CC0): rain beds (light / heavy / on a wooden-tile roof / on a tin roof),
typhoon howl, snow hush, thunder (near / far), wind gusts, and wet footsteps (splashy hard ground, wet grass)."""
import numpy as np
from dsp import *          # noqa: F401,F403
from registry import sfx
from gen_amb import st, scatter_loop, wrap_add
from gen_sfx import heel_toe, thump, _dirt, STEP_DB


# =================================================================== rain
def _drops(rng, n, rate, lo, hi, amp=(0.05, 0.3), dur=(0.002, 0.008)):
    """Dense random tiny clicks: individual raindrops hitting ground / leaves."""
    return grains(rng, n, int(n / SR * rate), lo, hi, dur, shape=lambda r: r.beta(1.2, 6), amp=amp)


def _rain_bed(rng, n, strength):
    """Hiss of distant rain + nearby drops + gusting intensity."""
    g = 0.75 + 0.25 * smooth_rand(rng, n, 0.12, 0.0, 1.0)
    hiss = bp(pink(rng, n), 900 + 900 * strength, 9000) * 0.35 * g
    body = lp(pink(rng, n), 600 + 500 * strength) * (0.15 + 0.25 * strength) * g
    near = _drops(rng, n, 220 + 1600 * strength, 1500, 9000, (0.03, 0.25 + 0.2 * strength))
    near = hp(near, 1200)
    return hiss + body + near * (0.6 + 0.4 * strength)


@sfx("amb_rain_light", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_rain_light(rng, i):
    """Light rain outdoors: soft hiss and sparse drops on leaves and earth (loop)."""
    n = N(30)
    y = st(rng, lambda r, m: _rain_bed(r, m, 0.3), n, 0.9)
    return make_loop(norm_rms(y, -24), 2.0)


@sfx("amb_rain_heavy", n=1, loop=True, stereo=True, db=-8, bus="Ambience")
def amb_rain_heavy(rng, i):
    """Heavy downpour outdoors: dense roar, splashing, gutters overflowing (loop)."""
    n = N(30)
    y = st(rng, lambda r, m: _rain_bed(r, m, 1.0), n, 0.9)

    def gush(r, m):   # water pouring off eaves / gutters
        return bp(white(r, m), 400, 2500) * (0.5 + 0.5 * smooth_rand(r, m, 4.0)) * 0.12
    y += st(rng, gush, n, 0.5)
    return make_loop(norm_rms(y, -19), 2.0)


@sfx("amb_rain_roof_wood", n=1, loop=True, stereo=True, db=-9, bus="Ambience")
def amb_rain_roof_wood(rng, i):
    """Rain heard indoors under a tiled / board / thatched roof: muffled patter + drips from the eaves into puddles."""
    n = N(28)

    def roof(r, m):
        pat = _drops(r, m, 900, 300, 2500, (0.05, 0.3), (0.004, 0.012))
        pat = lp(pat, 1800) + lp(pink(r, m), 400) * 0.25
        return pat * (0.8 + 0.2 * smooth_rand(r, m, 0.2))
    y = st(rng, roof, n, 0.7)

    def drip(r):
        m = N(0.12)
        return bubble(m, r.uniform(500, 1400), r.uniform(0.02, 0.05), r.uniform(0.3, 0.7), r.uniform(0.2, 0.5))
    y += scatter_loop(rng, n, 90, drip, 0.8, (0.2, 0.7))
    return make_loop(norm_rms(y, -23), 2.0)


@sfx("amb_rain_roof_tin", n=1, loop=True, stereo=True, db=-10, bus="Ambience")
def amb_rain_roof_tin(rng, i):
    """Rain on a corrugated tin / sheet-metal roof (Meiji-Showa sheds, steel ship decks): bright metallic pings."""
    n = N(26)

    def ping(r):
        m = N(0.18)
        f = r.uniform(1800, 4200)
        return modal(m, [f, f * 1.73, f * 2.61], [0.03, 0.02, 0.012], [0.5, 0.3, 0.15], r, 0.05) * r.uniform(0.2, 1.0)
    y = scatter_loop(rng, n, int(26 * 260), ping, 0.9, (0.05, 0.5))
    y += st(rng, lambda r, m: bp(pink(r, m), 1500, 7000) * 0.12 + lp(brown(r, m), 160) * 0.2, n, 0.6)
    return make_loop(norm_rms(y, -23), 2.0)


@sfx("amb_storm_wind", n=1, loop=True, stereo=True, db=-8, bus="Ambience")
def amb_storm_wind(rng, i):
    """Typhoon: howling wind with whistling through gaps, roaring gusts and lashing rain (loop)."""
    n = N(32)

    def howl(r, m):
        g = smooth_rand(r, m, 0.25, 0.3, 1.0) * smooth_rand(r, m, 1.1, 0.6, 1.0)
        base = tv_lp(pink(r, m), 250 + 1400 * g) * (0.5 + 0.5 * g)
        whistle = np.zeros(m)
        for k in range(3):
            f = r.uniform(380, 900) * (1 + 0.25 * smooth_rand(r, m, 0.5, -1, 1))
            whistle += np.sin(2 * np.pi * np.cumsum(f) / SR) * g ** 3 * 0.035
        lash = hp(_drops(r, m, 1800, 1500, 9000, (0.05, 0.35)), 1500) * g * 0.5
        return base + whistle + lash + lp(brown(r, m), 90) * 0.4 * g
    y = st(rng, howl, n, 0.9)
    return make_loop(norm_rms(y, -17), 2.5)


@sfx("amb_snow_hush", n=1, loop=True, stereo=True, db=-16, bus="Ambience")
def amb_snow_hush(rng, i):
    """Snowfall: an almost silent, muffled air with the soft hiss of flakes and an occasional clump falling from a branch."""
    n = N(30)
    y = st(rng, lambda r, m: lp(pink(r, m), 350) * 0.3 + bp(white(r, m), 2500, 7000) * 0.015, n, 0.9)

    def flump(r):
        m = N(0.6)
        return lp(white(r, m), 500) * env_ad(m, 0.01, 0.5) * 0.8
    y += scatter_loop(rng, n, 5, flump, 0.9, (0.2, 0.6))
    return make_loop(norm_rms(y, -30), 2.0)


# =================================================================== thunder / gusts
def _thunder(rng, dur, crack, rumble_f):
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    # 雷鳴: 近いと最初に裂ける音（高域の破裂）、その後に長く転がる低音（反射の重なり）
    if crack > 0:
        c = N(0.35)
        y[:c] += hp(white(rng, c), 900) * env_exp(c, 0.06, 0.002) * crack
    env = np.interp(t, [0, 0.15, 0.6, dur * 0.45, dur], [0, 1.0, 0.75, 0.4, 0.0]) ** 1.4
    roll = smooth_rand(rng, n, 2.5, 0.2, 1.0) ** 2
    y += tv_lp(brown(rng, n), rumble_f * (0.6 + 0.8 * roll)) * env * (0.6 + 0.6 * roll)
    y += lp(pink(rng, n), rumble_f * 1.8) * env * 0.2
    return fade(y, 0.002, 0.4)


@sfx("thunder_near", n=3, db=-2, bus="Ambience")
def thunder_near(rng, i):
    """Close lightning strike: sharp crack then long rolling rumble."""
    return norm_peak(outdoor_tail(rng, _thunder(rng, rng.uniform(5.0, 7.0), 1.0, 320), 1.8, 0.3), -1)


@sfx("thunder_far", n=3, db=-6, bus="Ambience")
def thunder_far(rng, i):
    """Distant thunder: low, soft rolling rumble without the crack."""
    return norm_peak(_thunder(rng, rng.uniform(6.0, 9.0), 0.0, 150), -2)


@sfx("wind_gust", n=3, db=-6, bus="Ambience")
def wind_gust(rng, i):
    """A single strong gust sweeping past (rising and falling roar with leaf rustle)."""
    n = N(rng.uniform(2.5, 3.8))
    e = env_bell(n, rng.uniform(0.35, 0.55), 1.6)
    y = tv_lp(pink(rng, n), 300 + 1500 * e) * e
    y += bp(white(rng, n), 2500, 8000) * e ** 2 * 0.12
    return norm_peak(fade(y, 0.02, 0.2), -2)


# =================================================================== wet footsteps
def _wet_hard(rng, n, s):
    """Foot on wet stone / boards / paving: a firm tap plus a thin splash of a film of water."""
    t = tt(n)
    y = thump(rng, n, 200, 0.015, 0.6 * s)
    y += click(n, rng, 1200, 7000, 0.002) * 0.6 * s
    y += bp(white(rng, n), 1500, 7000) * env_ad(n, 0.004, secs(n) - 0.01) * np.exp(-t / 0.05) * 0.55 * s
    for _ in range(int(3 + 4 * s)):
        y += np.roll(bubble(n, rng.uniform(1200, 3200), rng.uniform(0.004, 0.015), rng.uniform(0.2, 0.6), rng.uniform(0.04, 0.15)), N(rng.uniform(0.005, 0.08)))
    return y


def _wet_grass(rng, n, s):
    """Foot in rain-soaked grass: swish of wet blades and a soft squelch."""
    t = tt(n)
    y = thump(rng, n, 140, 0.03, 0.6 * s)
    sw = bp(white(rng, n), 1200, 7000) * env_ad(n, 0.02, secs(n) - 0.03) * np.exp(-t / 0.09) * 0.55 * s
    sq = tv_bp(white(rng, n), np.linspace(1100, 450, n), 3.5) * env_ad(n, 0.015, secs(n) - 0.02) * np.exp(-t / 0.06) * 0.5 * s
    y += sw + sq
    for _ in range(3):
        y += np.roll(bubble(n, rng.uniform(600, 1600), rng.uniform(0.01, 0.03), 0.4, 0.08 * s), N(rng.uniform(0.02, 0.12)))
    return y


def _syn(part, run):
    def fn(rng, i):
        return norm_peak(heel_toe(rng, run, part), -1)
    return fn


sfx("step_wet", n=6, db=-5, note="footstep on rain-wet stone / boards / paving (walk)")(_syn(_wet_hard, False))
sfx("step_wet_run", n=4, db=-3, note="footstep on rain-wet hard ground (run)")(_syn(_wet_hard, True))
sfx("step_wet_grass", n=6, db=-6, note="footstep in rain-soaked grass (walk)")(_syn(_wet_grass, False))
sfx("step_wet_grass_run", n=4, db=-4, note="footstep in rain-soaked grass (run)")(_syn(_wet_grass, True))
