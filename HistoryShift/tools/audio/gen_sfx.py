"""Footsteps, weapons, impacts, destruction, vehicles, interaction and UI sounds."""
import numpy as np
from dsp import *          # noqa: F401,F403
from registry import sfx, kenney, kload

K_IMP = "x_impact-sounds/Audio/"
K_RPG = "x_rpg-audio/Audio/"
K_UI = "x_interface-sounds/Audio/"
K_UI2 = "x_ui-audio/Audio/"
K_SCI = "x_sci-fi-sounds/Audio/"


def five(prefix, a=0, b=5):
    return ["%s_%03d.ogg" % (prefix, i) for i in range(a, b)]


# =================================================================== footsteps
def thump(rng, n, f=180.0, dec=0.025, amp=1.0):
    """Body weight: low filtered noise + a short sine 'thud'."""
    t = tt(n)
    y = lp(white(rng, n), f * 1.6, 2) * np.exp(-t / dec) * 2.2
    y += np.sin(2 * np.pi * f * 0.55 * t * (1 - t * 2)) * np.exp(-t / (dec * 1.1)) * 0.6
    return y * amp * np.clip(t / 0.0015, 0, 1)


def heel_toe(rng, run, part):
    """Builds a footstep from part(rng, n, strength) for heel and toe."""
    n = N(0.45 if not run else 0.35)
    y = np.zeros(n)
    gap = rng.uniform(0.045, 0.085) if not run else rng.uniform(0.022, 0.04)
    at = N(rng.uniform(0.004, 0.012))
    place(y, part(rng, n, 1.0 if not run else 1.35), at)
    place(y, part(rng, n, rng.uniform(0.45, 0.7) if not run else rng.uniform(0.6, 0.9)), at + N(gap))
    return fade(y, 0.001, 0.05)


def _gravel(rng, n, s):
    y = thump(rng, n, 150, 0.02, 0.5 * s)
    y += grains(rng, n, int(70 * s) + 25, 1500, 7000, (0.0006, 0.003), shape=lambda r: r.beta(1.2, 5), amp=(0.1, 0.8), span=N(0.22))
    y += bp(white(rng, n), 700, 4500) * env_exp(n, 0.045) * 0.35 * s
    return y


def _sand(rng, n, s):
    y = thump(rng, n, 120, 0.025, 0.4 * s)
    sw = bp(white(rng, n), 900, 5000) * env_ad(n, 0.02, secs(n) - 0.03) * env_exp(n, 0.07) * 0.6 * s
    y += sw + grains(rng, n, 18, 2500, 8000, (0.0005, 0.0015), shape=lambda r: r.beta(1.5, 4), amp=(0.05, 0.25), span=N(0.15))
    return y


def _dirt(rng, n, s):
    y = thump(rng, n, 170, 0.03, 0.9 * s)
    y += bp(white(rng, n), 300, 2500) * env_exp(n, 0.03) * 0.5 * s
    y += grains(rng, n, 12, 1000, 4000, (0.001, 0.003), shape=lambda r: r.beta(1.2, 4), amp=(0.05, 0.3), span=N(0.12))
    return y


def _stone(rng, n, s):
    t = tt(n)
    y = thump(rng, n, 220, 0.012, 0.6 * s)
    y += click(n, rng, 1200, 9000, 0.0025) * 1.2 * s
    y += modal(n, [rng.uniform(900, 1300), rng.uniform(1900, 2600), rng.uniform(3300, 4200)], [0.012, 0.008, 0.006],
               [0.25, 0.18, 0.1], rng) * s
    y += bp(white(rng, n), 2000, 8000) * np.exp(-t / 0.04) * 0.12 * s   # grit scuff
    return y


def _tatami(rng, n, s):
    t = tt(n)
    y = lp(white(rng, n), 260, 2) * np.exp(-t / 0.035) * 1.6 * s       # muffled straw-core thud
    y += np.sin(2 * np.pi * 85 * t) * np.exp(-t / 0.03) * 0.25 * s
    rus = bp(white(rng, n), 2500, 9000) * env_ad(n, 0.015, secs(n) - 0.02) * np.exp(-t / 0.06) * 0.22 * s
    return y + rus + grains(rng, n, 14, 3000, 9000, (0.0004, 0.0012), amp=(0.02, 0.12), span=N(0.09))


def _metal(rng, n, s):
    t = tt(n)
    y = thump(rng, n, 140, 0.03, 1.0 * s)
    base = rng.uniform(170, 240)
    ratios = [1.0, 2.32, 3.9, 6.1, 8.7, 11.8]
    y += modal(n, [base * r for r in ratios], [0.25, 0.16, 0.1, 0.07, 0.05, 0.03], [0.22, 0.16, 0.12, 0.08, 0.05, 0.03], rng, 0.04) * s
    y += click(n, rng, 1500, 7000, 0.002) * 0.6 * s
    return y * np.clip(t / 0.001, 0, 1)


def _water(rng, n, s):
    t = tt(n)
    y = bp(white(rng, n), 350, 3500) * env_ad(n, 0.01, secs(n) - 0.015) * np.exp(-t / 0.08) * 0.9 * s
    y += lp(white(rng, n), 300) * np.exp(-t / 0.04) * 1.2 * s
    for _ in range(int(6 + 6 * s)):
        b = bubble(n, rng.uniform(700, 2600), rng.uniform(0.008, 0.03), rng.uniform(0.2, 0.6), rng.uniform(0.05, 0.25))
        y += np.roll(b, N(rng.uniform(0.01, 0.2)))
    return y


def _mud(rng, n, s):
    t = tt(n)
    sq = tv_bp(white(rng, n), np.linspace(1400, 350, n), 4.0) * env_ad(n, 0.02, secs(n) - 0.03) * np.exp(-t / 0.09) * 1.2 * s
    y = thump(rng, n, 120, 0.04, 0.9 * s) + sq
    for _ in range(4):
        y += np.roll(bubble(n, rng.uniform(220, 520), rng.uniform(0.02, 0.05), 0.5, 0.25 * s), N(rng.uniform(0.04, 0.22)))
    return y


SYN_SURF = {"gravel": _gravel, "sand": _sand, "stone": _stone, "tatami": _tatami, "metal": _metal, "water": _water,
            "mud": _mud, "dirt_s": _dirt}
STEP_DB = {"gravel": -5, "sand": -7, "stone": -6, "tatami": -10, "metal": -4, "water": -4, "mud": -5, "dirt": -5,
           "grass": -6, "wood": -5, "concrete": -6, "snow": -6, "carpet": -9}


def _syn_step(surf, run):
    part = SYN_SURF[surf]

    def fn(rng, i):
        return norm_peak(heel_toe(rng, run, part), -1)
    return fn


for _s in ["gravel", "sand", "stone", "tatami", "metal", "water", "mud"]:
    sfx("step_" + _s, n=6, db=STEP_DB[_s], note="footstep on %s (walk), heel+toe synthesis" % _s)(_syn_step(_s, False))
    sfx("step_" + _s + "_run", n=4, db=STEP_DB[_s] + 2, note="footstep on %s (run)" % _s)(_syn_step(_s, True))


def run_variant(scuff_lo, scuff_hi):
    """Turn a Kenney walk footstep into a running one: harder, shorter, + scuff layer."""
    def proc(x, rng, i):
        y = resample(x, 1.06)
        n = len(y)
        e = np.clip(tt(n) / 0.002, 0, 1) * np.exp(-tt(n) / 0.12)
        y = y * (0.6 + 0.8 * e)
        y = soft_limit(y * 1.6, 0.95)
        y += bp(white(rng, n), scuff_lo, scuff_hi) * env_exp(n, 0.05, 0.004) * 0.25
        return norm_peak(y, -1)
    return proc


def walk_proc(x, rng, i):
    return norm_peak(fade(x, 0.0005, 0.02), -1)


kenney("step_dirt", [K_RPG + "footstep0%d.ogg" % i for i in range(10)], walk_proc, db=STEP_DB["dirt"], note="footstep on dirt/earth road")
kenney("step_dirt_run", [K_RPG + "footstep0%d.ogg" % i for i in (1, 3, 5, 7)], run_variant(600, 3000), db=STEP_DB["dirt"] + 2)
for _s, _k in [("grass", "footstep_grass"), ("wood", "footstep_wood"), ("concrete", "footstep_concrete"),
               ("snow", "footstep_snow"), ("carpet", "footstep_carpet")]:
    kenney("step_" + _s, [K_IMP + f for f in five(_k)], walk_proc, db=STEP_DB[_s], note="footstep on " + _s)
    kenney("step_" + _s + "_run", [K_IMP + f for f in five(_k, 0, 4)],
           run_variant(*({"grass": (2500, 8000), "wood": (400, 2500), "concrete": (1500, 7000), "snow": (1500, 6000),
                          "carpet": (2000, 7000)}[_s])), db=STEP_DB[_s] + 2)


def _land(part, body_f=110, mul=1.6):
    def fn(rng, i):
        n = N(0.7)
        y = thump(rng, n, body_f, 0.06, 1.6)
        y = place(y, part(rng, n, mul), N(0.004))
        y = place(y, part(rng, n, mul * 0.5), N(0.05))
        y += bp(white(rng, n), 800, 5000) * env_exp(n, 0.08, 0.01) * 0.2   # clothes
        return norm_peak(fade(y, 0.001, 0.1), -1)
    return fn


sfx("land_soft", n=3, db=-3, note="landing on earth/grass/sand")(_land(_dirt))
sfx("land_hard", n=3, db=-3, note="landing on stone/concrete")(_land(_stone, 140))
def _boards(r, n, s):
    """Hollow wooden floor (raised boards / engawa): thud + low board resonances."""
    return thump(r, n, 160, 0.05, s) + modal(n, [r.uniform(110, 150), r.uniform(260, 330), r.uniform(520, 640)],
                                            [0.08, 0.05, 0.03], [0.5, 0.3, 0.15], r) * s


sfx("land_wood", n=3, db=-3, note="landing on wooden floor")(_land(_boards, 120))
sfx("land_metal", n=3, db=-3, note="landing on steel deck")(_land(_metal, 120, 1.4))
sfx("land_water", n=3, db=-2, note="landing in shallow water")(_land(_water, 100, 1.5))
sfx("land_tatami", n=3, db=-5, note="landing on tatami")(_land(_tatami, 100, 1.5))


# --------------------------------------------------------------- hooves
def _hoof(kind):
    def fn(rng, i):
        n = N(0.3)
        t = tt(n)
        if kind == "stone":
            y = click(n, rng, 800, 6000, 0.003) * 1.4
            y += modal(n, [rng.uniform(700, 900), rng.uniform(1400, 1800), rng.uniform(2600, 3100)], [0.03, 0.02, 0.012], [0.5, 0.3, 0.15], rng)
            y += thump(rng, n, 200, 0.02, 0.7)
        elif kind == "wood":
            y = thump(rng, n, 160, 0.035, 1.2) + modal(n, [rng.uniform(140, 180), rng.uniform(330, 420), rng.uniform(800, 1000)], [0.07, 0.05, 0.02], [0.6, 0.35, 0.2], rng)
            y += click(n, rng, 700, 4000, 0.002) * 0.6
        elif kind == "grass":
            y = thump(rng, n, 130, 0.04, 1.2) + bp(white(rng, n), 2500, 8000) * env_exp(n, 0.06, 0.005) * 0.25
        else:
            y = thump(rng, n, 150, 0.035, 1.3) + bp(white(rng, n), 400, 2500) * env_exp(n, 0.04) * 0.4
            y += grains(rng, n, 10, 1200, 5000, (0.001, 0.003), amp=(0.05, 0.3), span=N(0.1))
        return norm_peak(fade(y * np.clip(t / 0.0008, 0, 1), 0.0005, 0.06), -1)
    return fn


for _k in ["dirt", "stone", "wood", "grass"]:
    sfx("hoof_" + _k, n=5, db=-3, note="horse hoof on " + _k)(_hoof(_k))


@sfx("horse_snort", n=3, db=-6)
def horse_snort(rng, i):
    """Horse snort / lip flutter."""
    n = N(rng.uniform(0.6, 0.9))
    t = tt(n)
    flutter = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(22, 32) * t)
    y = bp(white(rng, n), 300, 2200) * env_bell(n, 0.25, 1.5) * (0.5 + 0.7 * flutter)
    y += bp(white(rng, n), 2000, 6000) * env_exp(n, 0.15, 0.01) * 0.3
    return norm_peak(fade(y), -2)


@sfx("horse_neigh", n=2, db=-4)
def horse_neigh(rng, i):
    """Horse whinny: vibrato harmonic source through nasal formants."""
    d = rng.uniform(1.3, 1.6)
    n = N(d)
    t = tt(n)
    f0 = np.interp(t, [0, 0.12, 0.5, d], [600, 1050, 820, 420]) * (1 + 0.05 * np.sin(2 * np.pi * 9 * t) * np.clip(t / 0.3, 0, 1))
    ph = 2 * np.pi * np.cumsum(f0) / SR
    src = sum(np.sin(k * ph) / k ** 1.2 for k in range(1, 12))
    src += white(rng, n) * 0.25
    y = reson(src, 900, 4) * 0.6 + reson(src, 1800, 6) * 0.5 + reson(src, 3000, 8) * 0.25
    y *= env_ad(n, 0.06, d * 0.55, 1.5) * (0.75 + 0.25 * np.sin(2 * np.pi * 13 * t))
    return norm_peak(fade(conv(y, ir_room(rng, 0.8, 0.15, 4000), 0.15)), -2)


# =================================================================== weapons
def gunshot(rng, crack=1.0, boom_f=80.0, boom_dec=0.06, body_dec=0.05, bloom=0.0, tail=1.4, tail_wet=0.35,
            mech=0.0, bright=7000.0, length=0.35):
    n = N(length)
    t = tt(n)
    y = np.zeros(n)
    # supersonic crack / muzzle report
    y += click(n, rng, 800, 12000, 0.0012) * 2.2 * crack
    y += bp(white(rng, n), 200, bright) * np.exp(-t / body_dec) * 1.3
    y += lp(white(rng, n), 400) * np.exp(-t / boom_dec) * 2.5
    y += np.sin(2 * np.pi * boom_f * t * (1 - 0.6 * t)) * np.exp(-t / boom_dec) * 1.2
    if bloom > 0:   # black powder: slower, rolling bloom
        b = lp(white(rng, n), 900) * env_ad(n, 0.01, length * 0.9, 1.5) * np.exp(-t / bloom) * 1.6
        y += b
    if mech > 0:
        y = place(y, click(N(0.05), rng, 2000, 9000, 0.003) * mech, N(0.002))
    y = soft_limit(y * 1.2, 0.95)
    y = outdoor_tail(rng, y, tail, tail_wet)
    return norm_peak(fade(y, 0.0003, 0.3), -0.5)


sfx("gun_matchlock", n=3, db=0, note="hinawaju matchlock: black powder boom with long rolling tail")(
    lambda r, i: gunshot(r, crack=0.7, boom_f=58, boom_dec=0.09, body_dec=0.09, bloom=0.22, tail=2.4, tail_wet=0.5, length=0.6, bright=5000))
sfx("gun_blackpowder_rifle", n=3, db=0, note="Murata rifle (black powder cartridge)")(
    lambda r, i: gunshot(r, crack=1.0, boom_f=70, boom_dec=0.07, body_dec=0.06, bloom=0.12, tail=2.0, tail_wet=0.45, length=0.5, mech=0.3))
sfx("gun_rifle", n=3, db=0, note="Type 38 rifle (smokeless): sharp crack")(
    lambda r, i: gunshot(r, crack=1.4, boom_f=90, boom_dec=0.05, body_dec=0.035, tail=1.6, tail_wet=0.38, length=0.35, mech=0.25, bright=9000))
sfx("gun_pistol", n=3, db=-2, note="pistol")(
    lambda r, i: gunshot(r, crack=1.0, boom_f=120, boom_dec=0.03, body_dec=0.025, tail=1.0, tail_wet=0.3, length=0.25, mech=0.5, bright=8000))
sfx("gun_lmg", n=4, db=-2, note="light machine gun single round (short tail for bursts)")(
    lambda r, i: gunshot(r, crack=1.3, boom_f=95, boom_dec=0.035, body_dec=0.03, tail=0.6, tail_wet=0.25, length=0.18, mech=0.6, bright=9000))


@sfx("gun_pan_flash", n=2, db=-6)
def pan_flash(rng, i):
    """Matchlock priming pan ignition fizz (the beat before the shot)."""
    n = N(0.3)
    t = tt(n)
    y = bp(white(rng, n), 1500, 9000) * env_ad(n, 0.004, 0.25, 1.5) * 0.7
    y += grains(rng, n, 40, 2000, 9000, (0.0004, 0.0015), amp=(0.1, 0.7), span=N(0.2))
    y += click(n, rng, 600, 4000, 0.004) * 0.6
    return norm_peak(fade(y), -2)


@sfx("gun_energy", n=3, db=-3)
def gun_energy(rng, i):
    """Time-gun (sci-fi) shot: pitch-falling FM zap with bright tail."""
    n = N(0.45)
    t = tt(n)
    f = 2400 * np.exp(-t * rng.uniform(9, 13)) + 180
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph + 2.5 * np.sin(ph * 0.5)) * np.exp(-t / 0.12)
    y += bp(white(rng, n), 3000, 12000) * np.exp(-t / 0.02) * 0.5
    y += np.sin(2 * np.pi * 90 * t) * np.exp(-t / 0.05) * 0.6
    return norm_peak(fade(conv(y, ir_room(rng, 0.7, 0.15, 7000), 0.3)), -1)


@sfx("gun_empty", n=2, db=-8)
def gun_empty(rng, i):
    """Dry click of an empty / failed gun."""
    n = N(0.15)
    y = click(n, rng, 2000, 10000, 0.0015) + modal(n, [rng.uniform(2500, 3200), rng.uniform(5200, 6500)], [0.01, 0.006], [0.25, 0.12], rng)
    return norm_peak(fade(y), -3)


def _clack(rng, n, f=2600, amp=1.0):
    return (click(n, rng, 1500, 10000, 0.002) * 1.2 + modal(n, [f, f * 1.7, f * 2.6], [0.015, 0.01, 0.006], [0.4, 0.25, 0.12], rng, 0.05)) * amp


@sfx("reload_bolt", n=2, db=-6)
def reload_bolt(rng, i):
    """Bolt action: up, back, (cartridge), forward, down."""
    n = N(1.0)
    y = np.zeros(n)
    for at, f, a in [(0.02, 2200, 0.7), (0.12, 1800, 1.0), (0.3, 3200, 0.5), (0.52, 2000, 1.0), (0.62, 2600, 0.8)]:
        place(y, _clack(rng, N(0.08), f * rng.uniform(0.9, 1.1), a), N(at + rng.uniform(-0.01, 0.01)))
    y += bp(white(rng, n), 1500, 6000) * (env_ad(n, 0.1, 0.8) * 0.0)
    for a, b in [(0.12, 0.25), (0.52, 0.6)]:     # bolt slide scrape
        m = N(b - a)
        place(y, bp(white(rng, m), 2000, 8000) * env_bell(m, 0.5) * 0.12, N(a))
    return norm_peak(fade(y), -2)


@sfx("reload_pistol", n=2, db=-7)
def reload_pistol(rng, i):
    """Pistol magazine out / in / slide."""
    n = N(0.9)
    y = np.zeros(n)
    for at, f, a in [(0.03, 1800, 0.6), (0.4, 2400, 1.0), (0.7, 3000, 0.9)]:
        place(y, _clack(rng, N(0.08), f, a), N(at))
    return norm_peak(fade(y), -2)


@sfx("reload_matchlock", n=2, db=-7)
def reload_matchlock(rng, i):
    """Matchlock: powder pour, ball drop, ramrod strokes (karuka)."""
    n = N(1.6)
    y = np.zeros(n)
    m = N(0.35)
    place(y, grains(rng, m, 120, 3000, 9000, (0.0003, 0.001), amp=(0.05, 0.3)) * env_bell(m, 0.3), N(0.02))
    place(y, _clack(rng, N(0.06), 1500, 0.6), N(0.42))
    for k in range(3):
        m = N(0.18)
        stroke = bp(white(rng, m), 600, 4000) * env_bell(m, 0.6 if k % 2 == 0 else 0.4) * 0.5
        stroke += np.roll(_clack(rng, m, 900, 0.5), int(m * 0.8))
        place(y, stroke, N(0.62 + k * 0.28))
    return norm_peak(fade(y), -2)


@sfx("reload_energy", n=1, db=-8)
def reload_energy(rng, i):
    """Time-gun recharge whine."""
    n = N(0.8)
    t = tt(n)
    f = 300 + 1600 * (t / secs(n)) ** 1.5
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_bell(n, 0.8) * 0.5 + _clack(rng, n, 3000, 0.0)
    return norm_peak(fade(y), -3)


# ---- bow
@sfx("bow_draw", n=2, db=-9)
def bow_draw(rng, i):
    """Bamboo bow creak while drawing."""
    n = N(0.7)
    rate = np.interp(tt(n), [0, 0.7], [rng.uniform(25, 40), rng.uniform(70, 110)])
    ph = np.cumsum(rate) / SR
    pulses = (np.diff(np.floor(ph), prepend=0) > 0).astype(float) * (0.5 + 0.5 * rng.uniform(0, 1, n))
    y = reson(pulses, rng.uniform(700, 900), 12) + reson(pulses, rng.uniform(1600, 2100), 14) * 0.6
    y += bp(white(rng, n), 1500, 5000) * 0.04
    return norm_peak(fade(y * env_bell(n, 0.7, 1.2), 0.02, 0.1), -3)


@sfx("bow_release", n=3, db=-3)
def bow_release(rng, i):
    """Yumi string release: low twang + string slap + arrow whoosh."""
    n = N(0.7)
    t = tt(n)
    tw = ks_pluck(rng.uniform(95, 130), 0.7, rng, bright=0.3, decay=0.985)[:n]
    tw = np.pad(tw, (0, n - len(tw)))
    y = tw * 0.9 + click(n, rng, 500, 5000, 0.003) * 1.2
    y += bp(white(rng, n), 500, 3000) * env_ad(n, 0.01, 0.25) * np.exp(-t / 0.08) * 0.5
    return norm_peak(fade(y), -1)


@sfx("arrow_whiz", n=2, db=-8)
def arrow_whiz(rng, i):
    """Arrow passing by."""
    n = N(0.45)
    c = np.interp(tt(n), [0, 0.2, 0.45], [1800, 1100, 700])
    y = tv_bp(white(rng, n), c, 3) * env_bell(n, 0.45, 2.0)
    return norm_peak(fade(y), -3)


@sfx("arrow_hit_wood", n=3, db=-4)
def arrow_hit_wood(rng, i):
    """Arrow thunks into wood and the shaft vibrates."""
    n = N(0.5)
    t = tt(n)
    y = thump(rng, n, 300, 0.012, 1.0) + modal(n, [rng.uniform(450, 600), rng.uniform(1100, 1400)], [0.02, 0.01], [0.6, 0.3], rng)
    y += np.sin(2 * np.pi * rng.uniform(180, 260) * t) * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(25, 35) * t)) * np.exp(-t / 0.12) * 0.25
    return norm_peak(fade(y), -1)


# ---- melee
def whoosh(rng, d, f0, f1, f2, q=2.5, ring=0.0):
    n = N(d)
    c = np.interp(np.linspace(0, 1, n), [0, 0.45, 1], [f0, f1, f2])
    y = tv_bp(white(rng, n), c, q) * env_bell(n, 0.45, 1.8)
    if ring > 0:
        y += np.sin(2 * np.pi * rng.uniform(4200, 5200) * tt(n)) * env_bell(n, 0.5, 2) * ring
    return norm_peak(fade(y, 0.005, 0.03), -2)


sfx("swing_blade", n=4, db=-6, note="katana / tachi swing")(lambda r, i: whoosh(r, r.uniform(0.22, 0.3), 500, 1700, 700, 3.0, 0.04))
sfx("swing_heavy", n=2, db=-4, note="heavy two-handed swing")(lambda r, i: whoosh(r, r.uniform(0.38, 0.45), 300, 1100, 400, 2.2, 0.03))
sfx("swing_spear", n=3, db=-6, note="spear / naginata thrust")(lambda r, i: whoosh(r, r.uniform(0.18, 0.22), 400, 1300, 900, 2.0))
sfx("swing_fist", n=3, db=-9, note="punch swing")(lambda r, i: whoosh(r, r.uniform(0.12, 0.16), 300, 900, 500, 1.6))


def metal_clash(rng, base, dec, bright=1.0, scrape=0.2, length=1.0):
    n = N(length)
    t = tt(n)
    ratios = [1.0, 1.59, 2.14, 2.83, 3.71, 4.52, 5.9]
    y = modal(n, [base * r for r in ratios], [dec * k for k in [1, 0.8, 0.7, 0.55, 0.45, 0.35, 0.25]],
              [0.5, 0.45, 0.35, 0.3, 0.2, 0.15, 0.1], rng, 0.03) * bright
    y += click(n, rng, 2000, 12000, 0.002) * 1.4
    y += bp(white(rng, n), 3000, 10000) * np.exp(-t / 0.05) * scrape
    return norm_peak(fade(conv(y, ir_room(rng, 0.5, 0.08, 8000), 0.12), 0.0005, 0.1), -1)


sfx("sword_clash", n=4, db=-3, note="blade on blade")(lambda r, i: metal_clash(r, r.uniform(1500, 2100), 0.25, 1.0, 0.3))
sfx("sword_parry", n=2, db=-2, note="successful parry: bright long ring")(lambda r, i: metal_clash(r, r.uniform(1900, 2300), 0.55, 1.2, 0.5, 1.4))
sfx("sword_block", n=3, db=-4, note="blocked blow: dull")(lambda r, i: metal_clash(r, r.uniform(700, 1000), 0.08, 0.6, 0.1, 0.5))


def _slice_proc(x, rng, i):
    return norm_peak(fade(x), -1)


kenney("sword_draw", [K_RPG + "drawKnife1.ogg", K_RPG + "drawKnife2.ogg", K_RPG + "drawKnife3.ogg"], _slice_proc, db=-8,
       note="drawing a blade from the saya")


@sfx("hit_blade", n=4, db=-3)
def hit_blade(rng, i):
    """Blade strike on a body (armour/cloth): thud + slice."""
    n = N(0.4)
    t = tt(n)
    y = thump(rng, n, 140, 0.04, 1.4) + bp(white(rng, n), 2500, 9000) * env_exp(n, 0.04, 0.003) * 0.6
    y += lp(white(rng, n), 900) * np.exp(-t / 0.05) * 0.8
    return norm_peak(fade(y), -1)


def _punch(x, rng, i):
    return norm_peak(fade(x), -1)


kenney("hit_punch", [K_IMP + f for f in five("impactPunch_medium")], _punch, db=-3, note="fist hit")
kenney("hit_kick", [K_IMP + f for f in five("impactPunch_heavy")], _punch, db=-2, note="kick / heavy hit")
kenney("body_fall", [K_IMP + f for f in five("impactSoft_heavy", 0, 4)], _punch, db=-4, note="body falls")
kenney("hurt_player", [K_IMP + f for f in five("impactSoft_medium", 0, 4)], _punch, db=-3, note="player takes damage")


# ---- bullet impacts
@sfx("impact_dirt", n=4, db=-6)
def impact_dirt(rng, i):
    """Bullet into earth: puff + grit."""
    n = N(0.35)
    y = thump(rng, n, 200, 0.02, 1.0) + bp(white(rng, n), 600, 4000) * env_exp(n, 0.05, 0.002) * 0.6
    y += grains(rng, n, 25, 1500, 7000, (0.0005, 0.002), shape=lambda r: r.beta(1, 3), amp=(0.05, 0.4), span=N(0.25))
    return norm_peak(fade(y), -1)


@sfx("impact_stone", n=4, db=-5)
def impact_stone(rng, i):
    """Bullet on stone, some with a ricochet whine."""
    n = N(0.7)
    t = tt(n)
    y = click(n, rng, 1500, 11000, 0.002) * 1.5 + modal(n, [rng.uniform(1500, 2500), rng.uniform(3500, 4800)], [0.01, 0.006], [0.4, 0.2], rng)
    y += grains(rng, n, 15, 2000, 8000, (0.0005, 0.002), amp=(0.05, 0.3), span=N(0.15))
    if i % 2 == 1:
        d = rng.uniform(0.35, 0.5)
        m = N(d)
        f = np.interp(tt(m), [0, d], [rng.uniform(3200, 4200), rng.uniform(1200, 1700)])
        w = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(m, 0.01, d * 0.8) * 0.35
        place(y, w, N(0.01))
    return norm_peak(fade(y), -1)


@sfx("ricochet", n=3, db=-6)
def ricochet(rng, i):
    """Ricochet whine."""
    d = rng.uniform(0.35, 0.6)
    n = N(d)
    f = np.interp(tt(n), [0, d], [rng.uniform(3000, 4500), rng.uniform(900, 1500)])
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.005, d * 0.8) + click(n, rng) * 0.8
    return norm_peak(fade(y), -2)


@sfx("bullet_whiz", n=3, db=-8)
def bullet_whiz(rng, i):
    """Bullet passing close by."""
    n = N(0.18)
    c = np.interp(tt(n), [0, 0.09, 0.18], [5000, 3000, 1800])
    y = tv_bp(white(rng, n), c, 4) * env_bell(n, 0.5, 2)
    return norm_peak(fade(y), -2)


kenney("impact_wood", [K_IMP + f for f in five("impactWood_light")], _punch, db=-5, note="bullet / blow on wood")
kenney("impact_metal", [K_IMP + f for f in five("impactMetal_light")], _punch, db=-6, note="bullet on metal")
kenney("impact_flesh", [K_IMP + f for f in five("impactPunch_medium", 0, 4)], lambda x, r, i: norm_peak(lp(x, 2500), -1), db=-4, note="hit on a body (muffled)")
kenney("impact_glass", [K_IMP + f for f in five("impactGlass_light", 0, 4)], _punch, db=-6, note="glass hit")
kenney("impact_plank", [K_IMP + f for f in five("impactPlank_medium", 0, 5)], _punch, db=-5, note="plank / wooden prop hit")


# =================================================================== explosions
def explosion(rng, size=1.0, length=3.5, debris=1.0):
    n = N(length)
    t = tt(n)
    y = click(n, rng, 300, 9000, 0.004) * 2.0
    y += lp(white(rng, n), 600 + 1500 / size) * env_ad(n, 0.004, length * 0.95, 2.5) * np.exp(-t / (0.35 * size)) * 2.5
    y += lp(brown(rng, n), 150) * env_ad(n, 0.02, length, 1.5) * np.exp(-t / (0.9 * size)) * 3.0
    y += np.sin(2 * np.pi * (45 / size ** 0.3) * t * (1 - 0.3 * t / length)) * np.exp(-t / (0.25 * size)) * 1.5
    y += bp(white(rng, n), 1500, 8000) * np.exp(-t / 0.05) * 0.7
    if debris > 0:
        y += grains(rng, n, int(140 * debris), 800, 7000, (0.001, 0.006), shape=lambda r: r.uniform(0.04, 0.8), amp=(0.02, 0.25))
    y = soft_limit(y, 0.9)
    y = outdoor_tail(rng, y, 2.0 * size, 0.4)
    return norm_peak(fade(y, 0.0005, 0.6), -0.3)


sfx("explosion_large", n=3, db=0, note="barrel / dynamite / shell explosion")(lambda r, i: explosion(r, 1.4, 3.6, 1.2))
sfx("explosion_small", n=3, db=-1, note="horoku-dama / grenade")(lambda r, i: explosion(r, 0.8, 2.2, 0.6))


@sfx("cannon_fire", n=3, db=0)
def cannon_fire(rng, i):
    """Ozutsu / field gun / naval gun report: deep boom and rolling echo."""
    n = N(1.2)
    t = tt(n)
    y = click(n, rng, 200, 6000, 0.005) * 1.5
    y += lp(white(rng, n), 500) * np.exp(-t / 0.18) * 2.5
    y += np.sin(2 * np.pi * rng.uniform(38, 48) * t * (1 - 0.4 * t)) * np.exp(-t / 0.22) * 2.0
    y += lp(brown(rng, n), 120) * env_ad(n, 0.01, 1.1) * 1.5
    y = soft_limit(y, 0.9)
    y = outdoor_tail(rng, y, 3.0, 0.55, ((0.45, 0.4), (0.9, 0.3), (1.6, 0.18), (2.3, 0.1)))
    return norm_peak(fade(y, 0.0005, 0.8), -0.3)


@sfx("shell_whistle", n=2, db=-6)
def shell_whistle(rng, i):
    """Incoming shell / rocket whistle (pitch falling)."""
    d = 1.4
    n = N(d)
    f = np.interp(tt(n), [0, d], [rng.uniform(1600, 2000), rng.uniform(500, 700)])
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.4, 0.05, 1) * 0.5 + bp(white(rng, n), 800, 3000) * env_ad(n, 0.6, 0.05) * 0.3
    return norm_peak(fade(y), -3)


@sfx("fuse_loop", n=1, loop=True, db=-8)
def fuse_loop(rng, i):
    """Burning fuse: fizzing sparkle (loop)."""
    n = N(2.5)
    y = bp(white(rng, n), 2000, 9000) * (0.25 + 0.1 * smooth_rand(rng, n, 12))
    y += grains(rng, n, 400, 2500, 10000, (0.0003, 0.0012), amp=(0.05, 0.6))
    return make_loop(norm_peak(y, -3), 0.2)


@sfx("rocket_loop", n=1, loop=True, db=-5)
def rocket_loop(rng, i):
    """Bo-hiya fire arrow rocket hiss/roar (loop)."""
    n = N(2.4)
    y = bp(white(rng, n), 300, 6000) * (0.6 + 0.4 * smooth_rand(rng, n, 25)) + lp(brown(rng, n), 300) * 0.6
    y += grains(rng, n, 200, 1500, 8000, (0.0005, 0.002), amp=(0.05, 0.5))
    return make_loop(norm_peak(y, -2), 0.2)


# =================================================================== destruction
def wood_crack(rng, n, amp=1.0):
    y = click(n, rng, 500, 9000, 0.003) * 1.5 * amp
    y += modal(n, [rng.uniform(300, 600), rng.uniform(900, 1500), rng.uniform(2000, 3200)], [0.03, 0.02, 0.012], [0.5, 0.35, 0.2], rng) * amp
    return y


@sfx("break_wood", n=4, db=-2)
def break_wood(rng, i):
    """Timber snapping and splintering."""
    n = N(1.4)
    t = tt(n)
    y = thump(rng, n, 110, 0.06, 1.2)
    for k in range(rng.integers(3, 7)):
        place(y, wood_crack(rng, N(0.15), rng.uniform(0.3, 1.0)), N(rng.beta(1.2, 3) * 0.6))
    y += grains(rng, n, 80, 1200, 6000, (0.001, 0.004), shape=lambda r: r.beta(1.5, 3), amp=(0.03, 0.3), span=N(0.9))
    groan = np.interp(t, [0, 1.2], [rng.uniform(140, 200), rng.uniform(90, 120)])
    y += reson(white(rng, n) * 0.3, 400, 8) * env_ad(n, 0.05, 0.8) * 0.3 + np.sin(2 * np.pi * np.cumsum(groan) / SR) * env_ad(n, 0.1, 0.9) * 0.08
    return norm_peak(fade(y, 0.001, 0.3), -1)


@sfx("break_plaster", n=3, db=-3)
def break_plaster(rng, i):
    """Plaster / mud-wall (shikkui, tsuchikabe) crumbling."""
    n = N(1.6)
    y = thump(rng, n, 120, 0.05, 1.2)
    y += grains(rng, n, 260, 600, 5000, (0.001, 0.005), shape=lambda r: r.beta(1.3, 2.5), amp=(0.02, 0.35), span=N(1.3))
    y += bp(white(rng, n), 400, 3000) * env_ad(n, 0.02, 1.4, 2) * 0.25
    return norm_peak(fade(y, 0.001, 0.3), -1)


@sfx("break_stone", n=3, db=-2)
def break_stone(rng, i):
    """Stone blocks cracking and tumbling."""
    n = N(1.8)
    y = thump(rng, n, 90, 0.08, 1.6)
    for k in range(rng.integers(4, 8)):
        m = N(0.3)
        hitk = thump(rng, m, rng.uniform(120, 220), 0.03, rng.uniform(0.3, 0.9)) + click(m, rng, 800, 7000) * 0.5
        place(y, hitk, N(rng.beta(1.2, 2.5) * 1.3))
    y += grains(rng, n, 140, 700, 6000, (0.001, 0.004), shape=lambda r: r.beta(1.2, 3), amp=(0.02, 0.3), span=N(1.5))
    y += lp(brown(rng, n), 200) * env_ad(n, 0.05, 1.5) * 0.5
    return norm_peak(fade(y, 0.001, 0.3), -1)


@sfx("break_glass", n=3, db=-3)
def break_glass(rng, i):
    """Window glass shattering with tinkling shards."""
    n = N(1.5)
    y = click(n, rng, 2000, 14000, 0.003) * 2.0 + bp(white(rng, n), 3000, 12000) * env_exp(n, 0.05, 0.001) * 0.8
    for k in range(60):
        m = N(0.2)
        f = rng.uniform(2500, 9000)
        sh = modal(m, [f, f * rng.uniform(1.3, 1.7), f * rng.uniform(2.1, 2.7)], [0.03, 0.02, 0.012], [0.3, 0.2, 0.1], rng)
        place(y, sh, N(rng.beta(1.2, 3) * 1.1), rng.uniform(0.05, 0.4))
    return norm_peak(fade(y, 0.0005, 0.3), -1)


@sfx("break_metal", n=3, db=-2)
def break_metal(rng, i):
    """Sheet metal / iron fitting smash and groan."""
    n = N(1.8)
    t = tt(n)
    base = rng.uniform(110, 160)
    y = modal(n, [base * r for r in [1, 1.83, 2.9, 4.1, 5.6, 7.3]], [0.6, 0.45, 0.35, 0.25, 0.18, 0.12], [0.5, 0.4, 0.3, 0.2, 0.15, 0.1], rng, 0.05)
    y += click(n, rng, 800, 8000, 0.004) * 1.5 + thump(rng, n, 100, 0.06, 1.0)
    g = np.interp(t, [0, 1.6], [rng.uniform(250, 350), rng.uniform(150, 200)])
    y += reson(np.sign(np.sin(2 * np.pi * np.cumsum(g) / SR)) * 0.2, 900, 6) * env_ad(n, 0.3, 1.2) * 0.4
    return norm_peak(fade(y, 0.001, 0.3), -1)


@sfx("break_tiles", n=3, db=-3)
def break_tiles(rng, i):
    """Kawara roof tiles sliding and clattering down."""
    n = N(2.0)
    y = np.zeros(n)
    at = 0.0
    k = 0
    while at < 1.7:
        m = N(0.25)
        f = rng.uniform(1200, 3200)
        c = modal(m, [f, f * 1.48, f * 2.3], [0.03, 0.02, 0.01], [0.5, 0.3, 0.15], rng) + click(m, rng, 1500, 9000) * 0.6
        place(y, c, N(at), rng.uniform(0.2, 1.0) * (1 - at / 2.2))
        at += rng.exponential(0.05 + 0.04 * k / 20)
        k += 1
    y += bp(white(rng, n), 1500, 6000) * env_ad(n, 0.3, 1.5) * 0.06   # sliding scrape
    return norm_peak(fade(y, 0.001, 0.3), -1)


@sfx("collapse_building", n=2, db=0)
def collapse_building(rng, i):
    """Whole building collapse: rumble, beams snapping, tiles, debris rain."""
    d = 5.0
    n = N(d)
    t = tt(n)
    y = lp(brown(rng, n), 180) * env_ad(n, 0.4, 3.5, 1.5) * 2.0
    y += lp(white(rng, n), 700) * env_ad(n, 0.3, 3.0, 2) * 0.6
    for k in range(14):
        place(y, wood_crack(rng, N(0.2), rng.uniform(0.3, 1.0)), N(rng.uniform(0.0, 2.8)))
    for k in range(5):
        place(y, thump(rng, N(0.4), rng.uniform(70, 120), 0.1, rng.uniform(0.8, 1.5)), N(rng.uniform(0.8, 3.2)))
    y += grains(rng, n, 600, 600, 7000, (0.001, 0.006), shape=lambda r: r.beta(2, 2.5), amp=(0.02, 0.25), span=N(4.6))
    y = soft_limit(y, 0.9)
    y = outdoor_tail(rng, y, 2.0, 0.35)
    return norm_peak(fade(y, 0.01, 0.8), -0.5)


@sfx("collapse_small", n=2, db=-1)
def collapse_small(rng, i):
    """Wall section / shed collapse."""
    n = N(2.4)
    y = lp(brown(rng, n), 200) * env_ad(n, 0.1, 2.0, 2) * 1.5
    for k in range(6):
        place(y, wood_crack(rng, N(0.2), rng.uniform(0.3, 0.9)), N(rng.uniform(0.0, 1.2)))
    y += grains(rng, n, 220, 700, 6000, (0.001, 0.005), shape=lambda r: r.beta(1.5, 3), amp=(0.02, 0.25), span=N(2.0))
    return norm_peak(fade(y, 0.005, 0.5), -1)


@sfx("debris", n=3, db=-6)
def debris(rng, i):
    """Small debris pieces falling."""
    n = N(1.2)
    y = grains(rng, n, 90, 800, 6000, (0.001, 0.005), shape=lambda r: r.beta(1.2, 3), amp=(0.05, 0.4))
    return norm_peak(fade(y, 0.001, 0.3), -2)


@sfx("tree_fall", n=2, db=-1)
def tree_fall(rng, i):
    """Tree trunk breaks, crown swishes down, heavy thud."""
    d = 3.2
    n = N(d)
    y = np.zeros(n)
    for k in range(6):
        place(y, wood_crack(rng, N(0.15), rng.uniform(0.4, 1.0)), N(rng.uniform(0, 0.6)))
    m = N(1.6)
    place(y, tv_bp(white(rng, m), np.linspace(1500, 4000, m), 1.5) * env_ad(m, 1.2, 0.3) * 0.6, N(0.7))
    place(y, thump(rng, N(0.8), 70, 0.15, 2.0) + grains(rng, N(0.8), 120, 1500, 7000, amp=(0.02, 0.2)), N(2.3))
    return norm_peak(fade(y, 0.001, 0.4), -1)


@sfx("fire_ignite", n=2, db=-4)
def fire_ignite(rng, i):
    """Fire catching: whoomp."""
    n = N(1.4)
    c = np.interp(tt(n), [0, 0.3, 1.4], [200, 1500, 600])
    y = tv_bp(white(rng, n), c, 1.2) * env_ad(n, 0.15, 1.1) + lp(brown(rng, n), 200) * env_ad(n, 0.1, 1.2) * 0.8
    return norm_peak(fade(y), -1)


@sfx("fire_loop", n=1, loop=True, db=-6, stereo=False)
def fire_loop(rng, i):
    """Burning wooden building: roar + crackle + pops (loop)."""
    n = N(6.0)
    roar = lp(brown(rng, n), 400) * (0.6 + 0.4 * smooth_rand(rng, n, 3)) * 1.2
    roar += bp(pink(rng, n), 300, 2000) * (0.3 + 0.3 * smooth_rand(rng, n, 6)) * 0.6
    cr = grains(rng, n, 900, 1500, 9000, (0.0003, 0.002), amp=(0.02, 0.5))
    for k in range(30):
        place(cr, click(N(0.03), rng, 500, 6000, 0.004), rng.uniform(0, n), rng.uniform(0.3, 1.0))
    return make_loop(norm_peak(roar + cr, -2), 0.4)


@sfx("creak_structure", n=3, db=-6)
def creak_structure(rng, i):
    """Damaged timber frame creaking."""
    d = rng.uniform(0.8, 1.4)
    n = N(d)
    rate = np.interp(tt(n), [0, d * 0.5, d], [rng.uniform(15, 30), rng.uniform(80, 140), rng.uniform(30, 60)])
    ph = np.cumsum(rate) / SR
    pulses = (np.diff(np.floor(ph), prepend=0) > 0).astype(float)
    y = reson(pulses, rng.uniform(250, 400), 10) + reson(pulses, rng.uniform(700, 1000), 12) * 0.5
    return norm_peak(fade(y * env_bell(n, 0.5, 1.2), 0.02, 0.1), -3)


# =================================================================== vehicles
@sfx("car_engine_loop", n=1, loop=True, db=-4)
def car_engine_loop(rng, i):
    """Four-cylinder petrol engine at ~1500 rpm (pitch scaled in game)."""
    fire_hz = 50.0
    d = 2.0
    n = N(d)
    y = np.zeros(n)
    period = SR / fire_hz
    k = 0
    while k * period < n:
        m = N(0.05)
        a = rng.uniform(0.8, 1.0) * (1.0 if k % 4 else 0.9)
        pulse = modal(m, [rng.uniform(110, 130), rng.uniform(280, 320), 620], [0.012, 0.008, 0.004], [1.0, 0.5, 0.2], rng) + lp(white(rng, m), 1200) * np.exp(-tt(m) / 0.006) * 0.6
        place(y, pulse * a, k * period)
        k += 1
    y += bp(white(rng, n), 1500, 5000) * 0.03 + np.sin(2 * np.pi * 25 * tt(n)) * 0.15
    return make_loop(norm_peak(lp(y, 3500), -2), 0.1)


@sfx("car_start", n=1, db=-4)
def car_start(rng, i):
    """Starter crank and the engine catching."""
    n = N(1.6)
    y = np.zeros(n)
    for k in range(8):
        place(y, modal(N(0.08), [180, 420], [0.02, 0.01], [0.6, 0.3], rng) + click(N(0.08), rng, 800, 5000) * 0.3, N(k * 0.09))
    for k in range(30):
        place(y, lp(white(rng, N(0.04)), 900) * np.exp(-tt(N(0.04)) / 0.008) * (0.4 + k / 40), N(0.75 + k * 0.028))
    return norm_peak(fade(y), -2)


@sfx("car_horn_old", n=1, db=-3)
def car_horn_old(rng, i):
    """Bulb horn 'honk' (Meiji/Taisho/early Showa car)."""
    n = N(0.55)
    t = tt(n)
    f = np.interp(t, [0, 0.05, 0.5], [260, 330, 300])
    ph = 2 * np.pi * np.cumsum(f) / SR
    src = np.sign(np.sin(ph)) * 0.6 + np.sin(2 * ph) * 0.3
    y = reson(src, 700, 3) + reson(src, 1500, 4) * 0.5
    return norm_peak(fade(y * env_ad(n, 0.02, 0.15)), -2)


@sfx("car_horn_modern", n=1, db=-6)
def car_horn_modern(rng, i):
    """Modern dual-tone car horn (2026 hub)."""
    n = N(0.4)
    t = tt(n)
    y = sum(np.sign(np.sin(2 * np.pi * f * t)) for f in (420, 500)) * 0.4
    return norm_peak(fade(lp(y, 3000) * env_ad(n, 0.01, 0.05)), -3)


@sfx("tire_skid", n=1, loop=True, db=-8)
def tire_skid(rng, i):
    """Tyre squeal on a dirt / paved road (loop)."""
    n = N(1.5)
    t = tt(n)
    f = 900 + 120 * smooth_rand(rng, n, 6, -1, 1)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35 + bp(white(rng, n), 600, 4000) * 0.5
    return make_loop(norm_peak(y, -3), 0.1)


@sfx("car_crash", n=2, db=-1)
def car_crash(rng, i):
    """Vehicle collision: crunch of metal and glass."""
    n = N(1.6)
    y = break_metal(rng, 0) * 0.8
    y = np.pad(y, (0, max(0, n - len(y))))[:n]
    g = break_glass(rng, 0) * 0.4
    y[:len(g)] += g[:n] if len(g) <= n else g[:n]
    y += thump(rng, n, 80, 0.1, 1.5)
    return norm_peak(fade(y), -0.5)


@sfx("plane_engine_loop", n=1, loop=True, db=-2)
def plane_engine_loop(rng, i):
    """Radial piston engine + three-blade propeller (loop)."""
    d = 2.0
    n = N(d)
    t = tt(n)
    fire = 120.0
    y = np.zeros(n)
    period = SR / fire
    k = 0
    while k * period < n:
        m = N(0.02)
        place(y, lp(white(rng, m), 2000) * np.exp(-tt(m) / 0.004) * rng.uniform(0.7, 1.0), k * period)
        k += 1
    blade = 100.0
    y += (0.5 + 0.5 * np.sin(2 * np.pi * blade * t)) ** 3 * bp(white(rng, n), 200, 3000) * 0.8
    y += np.sin(2 * np.pi * blade * t) * 0.25 + np.sin(2 * np.pi * 2 * blade * t) * 0.1
    return make_loop(norm_peak(y, -2), 0.1)


@sfx("boat_motor_loop", n=1, loop=True, db=-6)
def boat_motor_loop(rng, i):
    """Small launch / hot-bulb engine putt-putt (loop)."""
    d = 2.0
    n = N(d)
    y = np.zeros(n)
    rate = 8.0
    for k in range(int(d * rate)):
        m = N(0.08)
        place(y, (lp(white(rng, m), 600) * np.exp(-tt(m) / 0.02) + np.sin(2 * np.pi * 70 * tt(m)) * np.exp(-tt(m) / 0.03)) * rng.uniform(0.8, 1.0), N(k / rate))
    y += bp(white(rng, n), 300, 1500) * 0.05
    return make_loop(norm_peak(y, -2), 0.05)


@sfx("ship_steam_loop", n=1, loop=True, db=-6)
def ship_steam_loop(rng, i):
    """Reciprocating steam engine: chuffs and rod clanks (loop)."""
    d = 3.0
    n = N(d)
    y = np.zeros(n)
    rate = 2.0
    for k in range(int(d * rate * 2)):
        m = N(0.25)
        place(y, bp(white(rng, m), 300, 3000) * env_ad(m, 0.01, 0.22) * (1.0 if k % 2 == 0 else 0.6), N(k / (rate * 2)))
        place(y, modal(N(0.1), [rng.uniform(300, 380), 900], [0.03, 0.01], [0.3, 0.1], rng), N(k / (rate * 2) + 0.12))
    y += lp(brown(rng, n), 120) * 0.4
    return make_loop(norm_peak(y, -2), 0.1)


@sfx("ship_whistle", n=1, db=-2)
def ship_whistle(rng, i):
    """Steam whistle of a steamship (chord of organ-pipe tones)."""
    d = 2.6
    n = N(d)
    t = tt(n)
    y = sum(np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t) for f in (175, 220, 262)) * 0.3
    y += bp(white(rng, n), 300, 2000) * 0.15
    y = y * env_ad(n, 0.12, 0.6)
    return norm_peak(fade(outdoor_tail(rng, y, 2.5, 0.5)), -1)


@sfx("oar_stroke", n=3, db=-8)
def oar_stroke(rng, i):
    """Oar / scull (ro) stroke: wooden creak + water swirl."""
    n = N(1.0)
    y = np.roll(creak_structure(rng, 0)[:N(0.6)] * 0.4, 0)
    y = np.pad(y, (0, n - len(y)))
    y += _water(rng, n, 0.6) * 0.5
    return norm_peak(fade(y), -2)


@sfx("hull_hit_wood", n=3, db=-3)
def hull_hit_wood(rng, i):
    """Shot / ram hitting a wooden hull."""
    n = N(0.8)
    y = thump(rng, n, 90, 0.08, 1.6) + modal(n, [rng.uniform(90, 130), rng.uniform(220, 300), rng.uniform(500, 700)], [0.15, 0.08, 0.04], [0.6, 0.3, 0.15], rng)
    y += wood_crack(rng, n, 0.6)
    return norm_peak(fade(y), -1)


@sfx("hull_hit_steel", n=3, db=-3)
def hull_hit_steel(rng, i):
    """Shot / ram hitting a steel hull (deep clang)."""
    return break_metal(rng, i)


# =================================================================== water
@sfx("splash_small", n=3, db=-4)
def splash_small(rng, i):
    """Small object into water."""
    n = N(0.8)
    y = _water(rng, n, 1.4)
    return norm_peak(fade(y), -1)


@sfx("splash_big", n=2, db=-1)
def splash_big(rng, i):
    """Large splash (debris, person, shell)."""
    n = N(2.2)
    t = tt(n)
    y = lp(white(rng, n), 500) * np.exp(-t / 0.08) * 2 + bp(white(rng, n), 400, 6000) * env_ad(n, 0.01, 2.0, 2) * np.exp(-t / 0.4)
    for k in range(80):
        place(y, bubble(N(0.05), rng.uniform(400, 2500), rng.uniform(0.01, 0.04), 0.4, 1.0), N(rng.beta(1.5, 3) * 1.8), rng.uniform(0.05, 0.3))
    y += grains(rng, n, 200, 2000, 9000, (0.001, 0.004), shape=lambda r: r.uniform(0.15, 1.2) / 2.2, amp=(0.02, 0.15))
    return norm_peak(fade(y), -1)


@sfx("swim_stroke", n=3, db=-7)
def swim_stroke(rng, i):
    """Swimming stroke."""
    n = N(0.7)
    y = bp(white(rng, n), 300, 3000) * env_bell(n, 0.35, 1.5) * 0.6
    for k in range(10):
        place(y, bubble(N(0.04), rng.uniform(500, 1800), 0.02, 0.4, 0.2), N(rng.uniform(0.1, 0.5)))
    return norm_peak(fade(y), -2)


# =================================================================== interaction / craft
kenney("pickup_coins", [K_RPG + "handleCoins.ogg", K_RPG + "handleCoins2.ogg"], _punch, db=-6, note="mon / coins picked up")
kenney("pickup_leather", [K_RPG + "handleSmallLeather.ogg", K_RPG + "handleSmallLeather2.ogg", K_RPG + "dropLeather.ogg"], _punch, db=-6,
       note="bag / leather loot")
kenney("cloth", [K_RPG + "cloth%d.ogg" % k for k in (1, 2, 3, 4)], _punch, db=-8, note="clothes rustle")
kenney("pickup_weapon", [K_RPG + "beltHandle1.ogg", K_RPG + "beltHandle2.ogg", K_RPG + "clothBelt.ogg"], _punch, db=-6, note="weapon picked up")
kenney("book_page", [K_RPG + "bookFlip1.ogg", K_RPG + "bookFlip2.ogg", K_RPG + "bookFlip3.ogg"], _punch, db=-6, note="page turn (exam / notes)")
kenney("book_open", [K_RPG + "bookOpen.ogg"], _punch, db=-6)
kenney("book_close", [K_RPG + "bookClose.ogg"], _punch, db=-6)
kenney("paper_place", [K_RPG + "bookPlace1.ogg", K_RPG + "bookPlace2.ogg", K_RPG + "bookPlace3.ogg"], _punch, db=-6)
kenney("door_wood_open", [K_RPG + "doorOpen_1.ogg", K_RPG + "doorOpen_2.ogg"], _punch, db=-5, note="hinged wooden door")
kenney("door_wood_close", [K_RPG + "doorClose_%d.ogg" % k for k in (1, 2, 3, 4)], _punch, db=-5)
kenney("door_modern_open", [K_SCI + "doorOpen_000.ogg", K_SCI + "doorOpen_001.ogg"], _punch, db=-6, note="lab sliding door")
kenney("door_modern_close", [K_SCI + "doorClose_000.ogg", K_SCI + "doorClose_001.ogg"], _punch, db=-6)
kenney("latch", [K_RPG + "metalLatch.ogg", K_RPG + "metalClick.ogg"], _punch, db=-6, note="latch / bolt / lock")
kenney("creak_wood", [K_RPG + "creak1.ogg", K_RPG + "creak2.ogg", K_RPG + "creak3.ogg"], _punch, db=-7, note="floorboard / hull creak")
kenney("chop", [K_RPG + "chop.ogg"], _punch, db=-4, note="axe / chisel chop")
kenney("pot_metal", [K_RPG + "metalPot1.ogg", K_RPG + "metalPot2.ogg", K_RPG + "metalPot3.ogg"], _punch, db=-6, note="kettle / pot")
kenney("bell_impact", [K_IMP + f for f in five("impactBell_heavy", 0, 3)], _punch, db=-6, note="ship's bell / alarm bell strike")


def slide(rng, d, f, close):
    n = N(d)
    t = tt(n)
    rumble = lp(white(rng, n), f) * (0.6 + 0.4 * smooth_rand(rng, n, 40)) * env_bell(n, 0.3 if not close else 0.6, 1.2)
    y = rumble + grains(rng, n, 30, 800, 3000, (0.001, 0.003), amp=(0.02, 0.15))
    if close:
        place(y, thump(rng, N(0.15), 220, 0.015, 1.0) + modal(N(0.15), [rng.uniform(500, 700), rng.uniform(1300, 1600)], [0.02, 0.01], [0.4, 0.2], rng), int(n * 0.92))
    return norm_peak(fade(y, 0.01, 0.05), -2)


sfx("door_slide_open", n=2, db=-6, note="fusuma / shoji sliding open")(lambda r, i: slide(r, r.uniform(0.45, 0.6), 900, False))
sfx("door_slide_close", n=2, db=-6, note="fusuma / shoji sliding shut with a soft knock")(lambda r, i: slide(r, r.uniform(0.45, 0.6), 900, True))
sfx("door_heavy_slide", n=1, db=-4, note="kura / warehouse heavy door")(lambda r, i: slide(r, 1.3, 400, True))


@sfx("valve_turn", n=2, db=-6)
def valve_turn(rng, i):
    """Steel valve wheel turning (ships)."""
    n = N(1.2)
    rate = rng.uniform(18, 26)
    y = np.zeros(n)
    for k in range(int(1.0 * rate)):
        place(y, _clack(rng, N(0.03), rng.uniform(1800, 2400), 0.3), N(k / rate))
    y += reson(bp(white(rng, n), 400, 3000), 1200, 10) * env_bell(n, 0.5) * 0.2
    return norm_peak(fade(y), -2)


@sfx("lever", n=2, db=-6)
def lever(rng, i):
    """Mechanical lever / switch clunk."""
    n = N(0.3)
    y = thump(rng, n, 200, 0.02, 0.8) + _clack(rng, n, 1500, 0.8)
    return norm_peak(fade(y), -2)


def anvil(rng, i, hot=True):
    n = N(1.2)
    t = tt(n)
    base = rng.uniform(1100, 1300)
    y = modal(n, [base, base * 2.43, base * 3.9, base * 5.2], [0.35, 0.22, 0.15, 0.1], [0.6, 0.4, 0.25, 0.15], rng, 0.02)
    y = y * (0.5 if hot else 1.0)
    y += thump(rng, n, 300, 0.015, 1.0) + click(n, rng, 1500, 9000, 0.002)
    return norm_peak(fade(conv(y, ir_room(rng, 0.6, 0.12, 6000), 0.2)), -1)


sfx("craft_hammer", n=4, db=-3, note="hammer on hot steel / anvil (smithy)")(lambda r, i: anvil(r, i, True))
sfx("craft_hammer_wood", n=3, db=-4, note="mallet on wood / chisel (carpentry)")(
    lambda r, i: norm_peak(fade(thump(r, N(0.4), 220, 0.03, 1.2) + modal(N(0.4), [r.uniform(500, 700), r.uniform(1200, 1500)], [0.04, 0.02], [0.5, 0.25], r) + click(N(0.4), r, 800, 6000) * 0.6), -1))


@sfx("craft_saw", n=3, db=-5)
def craft_saw(rng, i):
    """Japanese pull saw (nokogiri) strokes."""
    n = N(1.5)
    y = np.zeros(n)
    for k in range(3):
        m = N(0.42)
        tooth = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rng.uniform(250, 350) * tt(m)))
        s = bp(white(rng, m), 1500, 7000) * tooth * env_bell(m, 0.6, 1.5)
        place(y, s, N(k * 0.48))
    return norm_peak(fade(y), -2)


@sfx("craft_plane", n=2, db=-6)
def craft_plane(rng, i):
    """Kanna (hand plane) shaving."""
    n = N(0.8)
    y = bp(white(rng, n), 2000, 8000) * env_bell(n, 0.3, 1.2) * (0.7 + 0.3 * smooth_rand(rng, n, 60))
    return norm_peak(fade(y), -2)


@sfx("craft_bellows", n=2, db=-6)
def craft_bellows(rng, i):
    """Fuigo bellows pumping air into the forge."""
    n = N(1.2)
    y = lp(white(rng, n), 900) * env_bell(n, 0.4, 1.5) + lp(brown(rng, n), 200) * env_bell(n, 0.5) * 0.5
    return norm_peak(fade(y), -2)


@sfx("craft_quench", n=1, db=-4)
def craft_quench(rng, i):
    """Quenching hot steel in water (yaki-ire)."""
    n = N(1.8)
    t = tt(n)
    y = bp(white(rng, n), 2000, 10000) * np.exp(-t / 0.5) * 0.8
    for k in range(120):
        place(y, bubble(N(0.03), rng.uniform(600, 3000), 0.015, 0.5, 0.3), N(rng.beta(1.2, 3) * 1.6))
    return norm_peak(fade(y), -1)


@sfx("craft_loom", n=2, db=-6)
def craft_loom(rng, i):
    """Loom batten beat and shuttle."""
    n = N(0.9)
    y = thump(rng, n, 180, 0.03, 1.0) + modal(n, [rng.uniform(400, 550), 1100], [0.03, 0.015], [0.5, 0.2], rng)
    place(y, bp(white(rng, N(0.3)), 1500, 5000) * env_bell(N(0.3), 0.5) * 0.3, N(0.4))
    return norm_peak(fade(y), -2)


@sfx("craft_grind", n=2, db=-6)
def craft_grind(rng, i):
    """Grinding / mixing (yagen drug grinder, mortar)."""
    n = N(1.2)
    y = bp(white(rng, n), 400, 3000) * env_bell(n, 0.5, 1) * (0.5 + 0.5 * smooth_rand(rng, n, 30)) + grains(rng, n, 120, 1000, 5000, amp=(0.02, 0.2))
    return norm_peak(fade(y), -2)


@sfx("rin", n=1, db=-6)
def rin(rng, i):
    """Small Buddhist rin bowl (craft finished / lesson passed)."""
    n = N(3.0)
    f = 1180.0
    y = modal(n, [f, f * 1.0035, f * 2.71, f * 2.716, f * 5.1], [1.6, 1.5, 0.8, 0.8, 0.3], [0.5, 0.4, 0.3, 0.25, 0.1])
    y += click(n, rng, 1000, 6000) * 0.3
    return norm_peak(fade(y), -2)


@sfx("hyoshigi", n=1, db=-4)
def hyoshigi(rng, i):
    """Wooden clappers (Edo night watch / alert)."""
    n = N(1.2)
    y = np.zeros(n)
    for at in (0.0, 0.42):
        m = N(0.5)
        c = modal(m, [rng.uniform(1500, 1700), rng.uniform(3300, 3600)], [0.05, 0.03], [0.7, 0.3], rng) + click(m, rng, 1500, 9000) * 0.8
        place(y, c, N(at))
    return norm_peak(fade(outdoor_tail(rng, y, 1.2, 0.3)), -1)


@sfx("hansho", n=1, db=-3)
def hansho(rng, i):
    """Fire-watch alarm bell (hanshō) rapid strikes."""
    n = N(3.0)
    y = np.zeros(n)
    for k in range(8):
        m = N(1.2)
        f = 820.0
        place(y, modal(m, [f, f * 2.1, f * 3.3, f * 4.6], [0.6, 0.35, 0.2, 0.12], [0.5, 0.4, 0.25, 0.1], rng, 0.01) + click(m, rng, 1000, 7000) * 0.5, N(k * 0.3))
    return norm_peak(fade(outdoor_tail(rng, y, 1.5, 0.3)), -1)


@sfx("pickup_item", n=2, db=-6)
def pickup_item(rng, i):
    """Generic item picked up: cloth + soft knock."""
    n = N(0.4)
    y = bp(white(rng, n), 1500, 7000) * env_bell(n, 0.3, 1.5) * 0.4 + thump(rng, n, 260, 0.02, 0.6)
    return norm_peak(fade(y), -2)


# =================================================================== UI (Kenney interface)
def _ui(x, rng, i):
    return norm_peak(fade(x, 0.0005, 0.01), -1)


kenney("ui_hover", [K_UI2 + "rollover%d.ogg" % k for k in (1, 2, 3)], _ui, db=-18, bus="SFX", note="menu hover")
kenney("ui_click", [K_UI + "click_00%d.ogg" % k for k in (1, 2, 3)], _ui, db=-9)
kenney("ui_confirm", [K_UI + "confirmation_001.ogg", K_UI + "confirmation_002.ogg"], _ui, db=-8)
kenney("ui_back", [K_UI + "back_001.ogg", K_UI + "back_002.ogg"], _ui, db=-9)
kenney("ui_open", [K_UI + "maximize_006.ogg", K_UI + "open_002.ogg"], _ui, db=-10)
kenney("ui_close", [K_UI + "minimize_006.ogg", K_UI + "close_002.ogg"], _ui, db=-10)
kenney("ui_mark", [K_UI + "scratch_00%d.ogg" % k for k in (1, 2, 3, 4)], _ui, db=-8, note="pencil mark on the answer sheet")
kenney("ui_error", [K_UI + "error_004.ogg", K_UI + "error_006.ogg"], _ui, db=-9)
kenney("ui_tick", [K_UI + "tick_001.ogg", K_UI + "tick_002.ogg"], _ui, db=-12)
kenney("ui_toggle", [K_UI + "toggle_001.ogg", K_UI + "toggle_002.ogg"], _ui, db=-10)
kenney("ui_select", [K_UI + "select_00%d.ogg" % k for k in (1, 2, 3)], _ui, db=-10)
kenney("ui_toast", [K_UI + "pluck_001.ogg", K_UI + "pluck_002.ogg"], _ui, db=-14, note="HUD notification")
kenney("ui_switch", [K_UI2 + "switch%d.ogg" % k for k in (2, 3, 4)], _ui, db=-10, note="weapon / tool switch")


# =================================================================== stingers / time travel
def koto_note(rng, f, d, gain=1.0, bend=0.0):
    y = ks_pluck(f, d, rng, bright=0.55, decay=0.9975, pick=0.18)
    y = np.pad(y, (0, max(0, N(d) - len(y))))[:N(d)]
    return y * gain


YO = [62, 64, 67, 69, 71]     # D E G A B


@sfx("stinger_success", n=1, db=-4, bus="Music")
def stinger_success(rng, i):
    """Mission success: rising koto arpeggio in yo scale + rin bell + low taiko."""
    n = N(3.6)
    y = np.zeros(n)
    notes = [62, 64, 67, 69, 71, 74, 76, 79]
    for k, m in enumerate(notes):
        place(y, koto_note(rng, mtof(m), 2.5, 0.6 + 0.05 * k), N(k * 0.085))
    place(y, rin(rng, 0)[:N(3.0)] * 0.5, N(0.7))
    place(y, taiko(rng, 70, 0.6) * 0.9, 0)
    return norm_peak(fade(conv(y, ir_room(rng, 1.8, 0.4, 6000), 0.25), 0.001, 0.5), -1)


@sfx("stinger_fail", n=1, db=-4, bus="Music")
def stinger_fail(rng, i):
    """Mission failed: falling in-scale shamisen phrase + taiko."""
    n = N(3.0)
    y = np.zeros(n)
    for k, m in enumerate([69, 65, 64, 60, 57]):
        place(y, shamisen(rng, mtof(m), 1.4) * 0.7, N(k * 0.22))
    place(y, taiko(rng, 60, 0.9), N(1.05))
    return norm_peak(fade(conv(y, ir_room(rng, 1.5, 0.35, 5000), 0.25), 0.001, 0.5), -1)


@sfx("stinger_history", n=1, db=-4, bus="Music")
def stinger_history(rng, i):
    """History changed: deep gong + shimmering bell cascade."""
    n = N(4.5)
    t = tt(n)
    y = temple_bell_core(rng, 110, 4.5) * 0.7
    for k in range(14):
        f = mtof(rng.choice([74, 76, 79, 81, 83, 86, 88]))
        place(y, modal(N(2.0), [f, f * 2.76, f * 5.4], [0.9, 0.4, 0.15], [0.4, 0.2, 0.08], rng), N(0.15 + k * 0.11), 0.3)
    sw = tv_bp(white(rng, n), np.interp(t, [0, 1.5, 4.5], [400, 6000, 2000]), 3) * env_ad(n, 1.2, 3.0) * 0.12
    return norm_peak(fade(conv(y + sw, ir_room(rng, 2.5, 0.6, 7000), 0.3), 0.001, 0.6), -1)


@sfx("time_warp", n=1, db=-2)
def time_warp(rng, i):
    """Time-travel jump: long riser, swirling shimmer, final whoomp."""
    d = 4.0
    n = N(d)
    t = tt(n)
    x = t / d
    c = 150 + 7000 * x ** 2.2
    y = tv_bp(white(rng, n), c, 4) * (0.3 + x) * 0.7
    for k in range(5):
        f = 90 * 2 ** (k * 0.5) * (1 + 3 * x ** 2)
        y += np.sin(2 * np.pi * np.cumsum(f) / SR + k) * (x ** 1.5) * 0.12
    y *= (0.75 + 0.25 * np.sin(2 * np.pi * (2 + 12 * x) * t))
    w = np.zeros(n)
    m = N(1.2)
    place(w, (lp(brown(rng, m), 150) * 2 + np.sin(2 * np.pi * 45 * tt(m)) * 1.5) * env_exp(m, 0.35, 0.01), N(d - 0.6))
    y = y * env_ad(n, 0.3, 0.6) + w
    return norm_peak(fade(conv(y, ir_room(rng, 2.0, 0.5, 8000), 0.3), 0.01, 0.4), -1)


@sfx("time_arrive", n=1, db=-3)
def time_arrive(rng, i):
    """Arrival in the past: reversed swell into a soft impact and chime."""
    n = N(2.6)
    t = tt(n)
    sw = bp(white(rng, n), 1500, 9000) * np.clip(t / 0.9, 0, 1) ** 3 * (t < 0.9) * 0.5
    y = sw
    place(y, thump(rng, N(1.2), 70, 0.2, 2.0) + rin(rng, 0)[:N(1.2)] * 0.3, N(0.9))
    return norm_peak(fade(conv(y, ir_room(rng, 2.0, 0.5, 7000), 0.3), 0.01, 0.5), -1)


# instrument helpers shared with music (defined here to keep stingers self-contained)
def taiko(rng, f=65, d=0.9):
    n = N(d)
    t = tt(n)
    fr = f * (1 + 0.6 * np.exp(-t / 0.03))
    y = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t / (d * 0.35))
    y += lp(white(rng, n), 1500) * np.exp(-t / 0.015) * 0.6
    return y


def shamisen(rng, f, d):
    y = ks_pluck(f, d, rng, bright=0.9, decay=0.996, pick=0.08)
    y = np.pad(y, (0, max(0, N(d) - len(y))))[:N(d)]
    buzz = hp(np.clip(y * 3, -1, 1) - y * 3 * 0.33, 1500) * 0.25     # sawari buzz
    att = click(N(d), rng, 1000, 8000, 0.003) * 0.6
    return y + buzz + att


def temple_bell_core(rng, f, d):
    n = N(d)
    parts = [0.5, 1.0, 1.008, 1.19, 1.5, 1.506, 2.0, 2.52, 2.67, 3.0, 4.06]
    decs = [d * 0.9, d * 0.7, d * 0.7, d * 0.5, d * 0.4, d * 0.4, d * 0.3, d * 0.2, d * 0.18, d * 0.12, d * 0.08]
    amps = [0.5, 0.6, 0.5, 0.35, 0.3, 0.25, 0.22, 0.15, 0.12, 0.1, 0.06]
    y = modal(n, [f * p for p in parts], decs, amps, rng, 0.002)
    y += lp(white(rng, n), 400) * np.exp(-tt(n) / 0.05) * 0.4
    return y
