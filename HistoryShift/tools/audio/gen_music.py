"""Light, era-flavoured background music, composed and rendered procedurally (CC0).

Each track is ~64 s, mono, seamless loop. Instruments are simple physical /
additive models (koto, biwa, shamisen, shakuhachi, shinobue, sho, hichiriki,
taiko, tsuzumi, piano, music box, reed organ, electric piano).
"""
import numpy as np
from dsp import *          # noqa: F401,F403
from registry import sfx
from gen_sfx import taiko, shamisen, temple_bell_core

LEN = 64.0


# ------------------------------------------------------------------ instruments
def _fit(y, d):
    n = N(d)
    return np.pad(y, (0, max(0, n - len(y))))[:n]


def koto(rng, f, d, bright=0.55):
    y = _fit(ks_pluck(f, d, rng, bright=bright, decay=0.9978, pick=0.2), d)
    return y + reson(y, 900, 2) * 0.15


def biwa(rng, f, d):
    y = _fit(ks_pluck(f, d, rng, bright=0.85, decay=0.995, pick=0.07), d)
    buzz = hp(np.tanh(y * 4) - y, 1200) * 0.3
    return y + buzz + click(N(d), rng, 600, 5000, 0.004) * 0.5


def flute(rng, f, d, breath=0.25, vib=5.0, bright=0.3, attack=0.08):
    n = N(d)
    t = tt(n)
    v = 1 + 0.006 * np.sin(2 * np.pi * vib * t) * np.clip((t - 0.25) / 0.4, 0, 1)
    ff = f * v * (1 - 0.02 * np.exp(-t / 0.06))
    ph = 2 * np.pi * np.cumsum(ff) / SR
    y = np.sin(ph) + bright * np.sin(2 * ph) * 0.5 + bright * 0.2 * np.sin(3 * ph)
    y += bp(white(rng, n), f * 0.8, min(f * 4, 12000)) * breath
    env = env_ad(n, attack, min(0.3, d * 0.4), 1.3) * (0.85 + 0.15 * smooth_rand(rng, n, 2))
    return y * env


def shakuhachi(rng, f, d):
    y = flute(rng, f, d, breath=0.45, vib=4.5, bright=0.25, attack=0.12)
    n = N(d)
    y[:N(0.06)] += bp(white(rng, N(0.06)), 1500, 6000) * 0.6       # muraiki breath burst
    return y


def shinobue(rng, f, d):
    return flute(rng, f, d, breath=0.2, vib=6.0, bright=0.45, attack=0.04)


def hichiriki(rng, f, d):
    n = N(d)
    t = tt(n)
    ff = f * (1 + 0.03 * np.exp(-t / 0.15) * -1 + 0.004 * np.sin(2 * np.pi * 5 * t))     # enbai slide up
    ph = 2 * np.pi * np.cumsum(ff) / SR
    saw = sum(np.sin(k * ph) / k for k in range(1, 16))
    y = reson(saw, 1200, 3) + reson(saw, 2600, 5) * 0.5 + saw * 0.1
    return y * env_ad(n, 0.12, min(0.4, d * 0.4), 1.2)


def sho(rng, notes, d):
    n = N(d)
    t = tt(n)
    y = np.zeros(n)
    for m in notes:
        f = mtof(m) * (1 + rng.uniform(-0.002, 0.002))
        ph = 2 * np.pi * f * t
        y += (np.sin(ph) + 0.3 * np.sin(3 * ph) + 0.15 * np.sin(5 * ph))
    y = lp(y, 3500) * env_ad(n, d * 0.35, d * 0.3, 1.0) * (0.9 + 0.1 * np.sin(2 * np.pi * 0.3 * t))
    return y / max(1, len(notes))


def tsuzumi(rng, d=0.6):
    n = N(d)
    t = tt(n)
    f = 300 * (1 + 0.5 * np.exp(-t / 0.02))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.08) + click(n, rng, 800, 6000, 0.003) * 0.5


def kakko(rng):
    n = N(0.15)
    return modal(n, [rng.uniform(900, 1100), 2300], [0.02, 0.01], [0.6, 0.3], rng) + click(n, rng, 1500, 8000) * 0.6


def kane(rng, d=1.5):
    n = N(d)
    f = 1600.0
    return modal(n, [f, f * 1.42, f * 2.31, f * 3.07], [0.4, 0.3, 0.2, 0.1], [0.4, 0.3, 0.2, 0.1], rng, 0.01) + click(n, rng) * 0.3


def piano(rng, f, d, vel=1.0):
    n = N(d)
    t = tt(n)
    B = 0.0004
    y = np.zeros(n)
    for k in range(1, 12):
        fk = f * k * np.sqrt(1 + B * k * k)
        if fk > 15000:
            break
        y += np.sin(2 * np.pi * fk * t + rng.uniform(0, 6)) * np.exp(-t / (1.6 / k ** 0.7)) / k ** (1.4 - 0.3 * vel)
    y += lp(white(rng, n), 3000) * np.exp(-t / 0.01) * 0.1
    return y * vel * env_ad(n, 0.002, 0.08)


def musicbox(rng, f, d):
    n = N(d)
    return modal(n, [f, f * 3.9, f * 8.1], [0.9, 0.3, 0.1], [0.6, 0.15, 0.05], rng) + click(n, rng, 3000, 10000) * 0.05


def reed(rng, f, d):
    n = N(d)
    t = tt(n)
    y = np.zeros(n)
    for det in (-0.003, 0.003):
        ph = 2 * np.pi * f * (1 + det) * t
        y += sum(np.sin(k * ph) / k for k in range(1, 10))
    return lp(y, 2200) * env_ad(n, 0.08, 0.2, 1.0) * 0.3


def epiano(rng, f, d, vel=0.8):
    n = N(d)
    t = tt(n)
    mod = np.sin(2 * np.pi * f * 14 * t) * 1.5 * np.exp(-t / 0.05)
    y = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 1.2) + 0.2 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.4)
    return y * vel * env_ad(n, 0.003, 0.1)


def pad(rng, notes, d):
    n = N(d)
    t = tt(n)
    y = np.zeros(n)
    for m in notes:
        for det in (-0.004, 0.0, 0.004):
            ph = 2 * np.pi * mtof(m) * (1 + det) * t + rng.uniform(0, 6)
            y += sum(np.sin(k * ph) / k for k in range(1, 7))
    return lp(y, 1500) * env_ad(n, d * 0.3, d * 0.3, 1.0) / (len(notes) * 3)


def kick(rng):
    n = N(0.4)
    t = tt(n)
    return np.sin(2 * np.pi * np.cumsum(55 * (1 + 2 * np.exp(-t / 0.02))) / SR) * np.exp(-t / 0.12)


def snare(rng):
    n = N(0.25)
    return bp(white(rng, n), 1500, 7000) * env_exp(n, 0.05) * 0.5 + np.sin(2 * np.pi * 190 * tt(n)) * env_exp(n, 0.03) * 0.3


def hat(rng):
    n = N(0.06)
    return hp(white(rng, n), 7000) * env_exp(n, 0.015) * 0.3


# ------------------------------------------------------------------ composition helpers
class Score:
    def __init__(self, bpm, beats_per_bar=4, target=LEN, tail=6.0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = max(4, int(round(target / (self.beat * beats_per_bar) / 4.0)) * 4)
        self.length = self.bars * beats_per_bar * self.beat
        self.n = N(self.length + tail)
        self.bus = {}

    def add(self, bus, y, at_beat=None, at_sec=None, gain=1.0):
        b = self.bus.setdefault(bus, np.zeros(self.n))
        at = at_sec if at_sec is not None else at_beat * self.beat
        place(b, y, N(at), gain)

    def mix(self, rng, gains, verb=0.3, verb_len=2.5):
        y = np.zeros(self.n)
        for k, b in self.bus.items():
            y += b * gains.get(k, 1.0)
        ir = ir_room(rng, verb_len, verb_len / 4, 5000)
        y = conv(y, ir, verb)
        L = N(self.length)
        out = y[:L].copy()
        tail = y[L:]
        out[:len(tail)] += tail          # wrap the ringing tail into the start: seamless loop
        return norm_rms(out, -21, -2)


def melody(rng, scale, bars, beats_per_bar, rhythm_pool, start=None, home=None):
    """Random-walk melody on a scale (list of midi), phrase endings resolve home."""
    out = []
    idx = start if start is not None else len(scale) // 2
    home = home if home is not None else idx
    for b in range(bars):
        rhy = rhythm_pool[rng.integers(len(rhythm_pool))]
        pos = 0.0
        for k, dur in enumerate(rhy):
            last = (b == bars - 1 and k == len(rhy) - 1)
            if last:
                idx = home
            else:
                step = rng.choice([-2, -1, -1, 0, 1, 1, 2], p=[0.1, 0.25, 0.1, 0.05, 0.25, 0.15, 0.1])
                idx = int(np.clip(idx + step, 0, len(scale) - 1))
            out.append((b * beats_per_bar + pos, dur, scale[idx]))
            pos += dur
    return out


def scale_from(root, steps, octaves=2):
    s = []
    for o in range(octaves):
        for st in steps:
            s.append(root + 12 * o + st)
    s.append(root + 12 * octaves)
    return s


YO = [0, 2, 5, 7, 9]           # D E G A B style (ryo/yo)
IN = [0, 1, 5, 7, 8]           # miyako-bushi
MINYO = [0, 3, 5, 7, 10]
YONANUKI_MAJ = [0, 2, 4, 7, 9]
YONANUKI_MIN = [0, 2, 3, 7, 8]


def render_melody(sc, rng, bus, notes, inst, gain=1.0, offset_beats=0.0, legato=1.0):
    for (b, d, m) in notes:
        dur = max(0.15, d * sc.beat * legato + 0.25)
        sc.add(bus, inst(rng, mtof(m), dur), at_beat=b + offset_beats, gain=gain * rng.uniform(0.85, 1.0))


# ------------------------------------------------------------------ tracks
@sfx("music_jomon", n=1, loop=True, db=-11, bus="Music", q=3)
def music_jomon(rng, i):
    """Jomon/Kofun: frame drum, clay-flute phrases, wind drone."""
    sc = Score(68)
    bars = sc.bars
    for b in range(bars):
        for k, (bt, g) in enumerate([(0, 1.0), (1.5, 0.5), (2, 0.8), (3.5, 0.4)]):
            sc.add("drum", lp(taiko(rng, 55, 0.9), 900), at_beat=b * 4 + bt, gain=g * 0.8)
        if b % 2 == 1:
            sc.add("rattle", grains(rng, N(0.4), 60, 2000, 8000, amp=(0.05, 0.3)), at_beat=b * 4 + 3)
    scale = scale_from(57, MINYO, 2)
    for ph in range(0, bars, 4):
        mel = melody(rng, scale, 2, 4, [[2, 2], [1.5, 0.5, 2], [3, 1], [4]], start=5, home=5)
        render_melody(sc, rng, "flute", mel, lambda r, f, d: flute(r, f, d, 0.35, 4.0, 0.1, 0.1), 0.9, ph * 4 + 4)
    drone = lp(brown(rng, sc.n), 200) * 0.3 + np.sin(2 * np.pi * mtof(45) * tt(sc.n)) * 0.15
    sc.add("drone", drone, at_sec=0)
    return sc.mix(rng, {"drum": 0.8, "flute": 0.55, "drone": 0.6, "rattle": 0.4}, 0.35, 3.0)


@sfx("music_nara", n=1, loop=True, db=-11, bus="Music", q=3)
def music_nara(rng, i):
    """Asuka/Nara: gagaku-like sho clusters, hichiriki line, kakko and taiko."""
    sc = Score(52)
    bars = sc.bars
    chords = [[62, 64, 69, 71, 76], [64, 69, 71, 74, 76], [62, 67, 69, 74, 76], [61, 64, 66, 69, 71]]
    for b in range(0, bars, 2):
        sc.add("sho", sho(rng, chords[(b // 2) % 4], sc.beat * 8 + 1.5), at_beat=b * 4)
    scale = scale_from(62, YO, 2)
    mel = melody(rng, scale, bars, 4, [[4], [2, 2], [3, 1], [2, 1, 1]], start=4, home=0)
    render_melody(sc, rng, "hichi", mel, hichiriki, 0.6)
    for b in range(bars):
        if b % 2 == 0:
            for k in range(6):
                sc.add("perc", kakko(rng), at_beat=b * 4 + 2 + k * (0.5 - k * 0.05), gain=0.4 + k * 0.08)
        sc.add("perc", lp(taiko(rng, 50, 1.2), 700), at_beat=b * 4 + 3.5, gain=0.9)
    return sc.mix(rng, {"sho": 0.7, "hichi": 0.35, "perc": 0.6}, 0.4, 3.5)


@sfx("music_heian", n=1, loop=True, db=-11, bus="Music", q=3)
def music_heian(rng, i):
    """Heian: courtly koto arpeggios, biwa phrases and a soft sho pad (spring)."""
    sc = Score(76)
    bars = sc.bars
    scale = scale_from(62, YO, 2)
    pattern = [0, 2, 4, 5, 4, 2]
    roots = [0, 3, 1, 4]
    for b in range(bars):
        r = roots[(b // 2) % 4]
        for k, p in enumerate(pattern):
            sc.add("koto", koto(rng, mtof(scale[min(len(scale) - 1, r + p)]), 2.0), at_beat=b * 4 + k * (4 / 6), gain=0.6 if k else 0.8)
    for ph in range(2, bars, 4):
        mel = melody(rng, scale_from(50, YO, 1), 2, 4, [[1, 1, 2], [2, 2], [1.5, 0.5, 2]], start=2, home=0)
        render_melody(sc, rng, "biwa", mel, lambda r, f, d: biwa(r, f, d + 0.8), 0.7, ph * 4)
    for b in range(0, bars, 4):
        sc.add("pad", sho(rng, [62, 69, 71, 76], sc.beat * 16 + 1.0), at_beat=b * 4)
    return sc.mix(rng, {"koto": 0.5, "biwa": 0.5, "pad": 0.35}, 0.35, 2.8)


@sfx("music_kamakura", n=1, loop=True, db=-11, bus="Music", q=3)
def music_kamakura(rng, i):
    """Kamakura/Muromachi: zen shakuhachi over a sparse koto ostinato."""
    sc = Score(60)
    bars = sc.bars
    scale = scale_from(62, IN, 2)
    for b in range(bars):
        for k, p in enumerate([0, 2, 3]):
            sc.add("koto", koto(rng, mtof(scale[p] - 12), 2.5, 0.4), at_beat=b * 4 + k * 1.33, gain=0.5)
    for ph in range(0, bars, 3):
        mel = melody(rng, scale, 2, 4, [[4], [3, 1], [6, 2], [2, 2]], start=5, home=5)
        render_melody(sc, rng, "shaku", mel, shakuhachi, 0.9, ph * 4 + 1)
    for b in range(0, bars, 8):
        sc.add("bell", temple_bell_core(rng, 196, 8.0) * 0.3, at_beat=b * 4)
    return sc.mix(rng, {"koto": 0.4, "shaku": 0.6, "bell": 0.3}, 0.45, 3.5)


@sfx("music_sengoku", n=1, loop=True, db=-11, bus="Music", q=3)
def music_sengoku(rng, i):
    """Sengoku: taiko ensemble groove, shime-daiko, shinobue melody."""
    sc = Score(104)
    bars = sc.bars
    ji = [0, 1, 1.5, 2, 3, 3.5]
    for b in range(bars):
        for bt in ji:
            sc.add("taiko", taiko(rng, 62 if bt in (0, 2) else 75, 0.8), at_beat=b * 4 + bt, gain=1.0 if bt in (0, 2) else 0.55)
        for k in range(8):
            sc.add("shime", lp(tsuzumi(rng, 0.2), 4000), at_beat=b * 4 + k * 0.5, gain=0.25 if k % 2 else 0.4)
        if b % 4 == 3:
            sc.add("kane", kane(rng), at_beat=b * 4 + 3.5, gain=0.4)
    scale = scale_from(69, YO, 2)
    for ph in range(2, bars, 4):
        mel = melody(rng, scale, 2, 4, [[1, 1, 2], [0.5, 0.5, 1, 2], [2, 1, 1], [1.5, 0.5, 1, 1]], start=3, home=0)
        render_melody(sc, rng, "fue", mel, shinobue, 0.7, ph * 4)
    return sc.mix(rng, {"taiko": 0.7, "shime": 0.5, "fue": 0.45, "kane": 0.4}, 0.3, 2.2)


@sfx("music_edo", n=1, loop=True, db=-11, bus="Music", q=3)
def music_edo(rng, i):
    """Edo: lively shamisen tune with tsuzumi and hyoshigi accents."""
    sc = Score(96)
    bars = sc.bars
    scale = scale_from(64, IN, 2)
    for ph in range(0, bars, 4):
        mel = melody(rng, scale, 4, 4, [[1, 1, 1, 1], [0.5, 0.5, 1, 2], [1, 0.5, 0.5, 2], [2, 1, 1]], start=4, home=0 if ph % 8 else 5)
        render_melody(sc, rng, "sham", mel, lambda r, f, d: shamisen(r, f, min(d, 1.2)), 0.8, ph * 4, 0.8)
    for b in range(bars):
        sc.add("tsuzumi", tsuzumi(rng), at_beat=b * 4 + 1.0, gain=0.5)
        sc.add("tsuzumi", tsuzumi(rng), at_beat=b * 4 + 2.5, gain=0.35)
        if b % 8 == 7:
            sc.add("tsuzumi", kakko(rng), at_beat=b * 4 + 3.5, gain=0.6)
    for b in range(bars):
        sc.add("bass", koto(rng, mtof(scale[0] - 12), 1.5, 0.3), at_beat=b * 4, gain=0.4)
    return sc.mix(rng, {"sham": 0.55, "tsuzumi": 0.5, "bass": 0.5}, 0.28, 2.0)


@sfx("music_meiji", n=1, loop=True, db=-11, bus="Music", q=3)
def music_meiji(rng, i):
    """Meiji/Taisho: gentle piano waltz with music-box melody (yonanuki major)."""
    sc = Score(108, 3)
    bars = sc.bars
    chords = [[48, 55, 64], [53, 57, 65], [55, 59, 62], [48, 52, 60]]
    for b in range(bars):
        c = chords[(b // 2) % 4]
        sc.add("lh", piano(rng, mtof(c[0]), 1.4, 0.7), at_beat=b * 3)
        for k in (1, 2):
            for m in c[1:]:
                sc.add("lh", piano(rng, mtof(m), 0.6, 0.35), at_beat=b * 3 + k)
    scale = scale_from(72, YONANUKI_MAJ, 1) + [86, 88]
    mel = melody(rng, scale, bars, 3, [[2, 1], [1, 1, 1], [3], [1.5, 0.5, 1]], start=2, home=0)
    render_melody(sc, rng, "mel", mel, musicbox, 0.5)
    render_melody(sc, rng, "mel", [(b, d, m - 12) for (b, d, m) in mel], lambda r, f, d: piano(r, f, d, 0.6), 0.5)
    return sc.mix(rng, {"lh": 0.5, "mel": 0.55}, 0.3, 2.2)


@sfx("music_showa", n=1, loop=True, db=-11, bus="Music", q=3)
def music_showa(rng, i):
    """Showa: nostalgic reed organ and piano, yonanuki minor (ryukoka feel)."""
    sc = Score(80)
    bars = sc.bars
    chords = [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]
    for b in range(bars):
        c = chords[b % 4]
        for m in c:
            sc.add("organ", reed(rng, mtof(m), sc.beat * 4 + 0.3), at_beat=b * 4, gain=0.5)
        sc.add("bass", piano(rng, mtof(c[0] - 12), 1.5, 0.6), at_beat=b * 4)
        sc.add("bass", piano(rng, mtof(c[0] - 5), 1.0, 0.4), at_beat=b * 4 + 2)
    scale = scale_from(69, YONANUKI_MIN, 2)
    for ph in range(0, bars, 4):
        mel = melody(rng, scale, 4, 4, [[1.5, 0.5, 2], [1, 1, 2], [3, 1], [2, 1, 1]], start=5, home=5 if ph % 8 else 0)
        render_melody(sc, rng, "mel", mel, lambda r, f, d: piano(r, f, d + 0.6, 0.8), 0.6, ph * 4)
    return sc.mix(rng, {"organ": 0.35, "bass": 0.5, "mel": 0.55}, 0.32, 2.4)


@sfx("music_hub", n=1, loop=True, db=-11, bus="Music", q=3)
def music_hub(rng, i):
    """2026 time lab: lo-fi electric piano chords, soft beat and a koto motif."""
    sc = Score(80)
    bars = sc.bars
    chords = [[50, 57, 60, 64, 69], [55, 59, 62, 66, 69], [52, 55, 59, 62, 67], [57, 61, 64, 67, 71]]
    for b in range(bars):
        c = chords[b % 4]
        for k, m in enumerate(c):
            sc.add("ep", epiano(rng, mtof(m), sc.beat * 3.5, 0.5), at_beat=b * 4 + k * 0.03)
        sc.add("pad", pad(rng, c[1:4], sc.beat * 4 + 0.5), at_beat=b * 4)
        for bt in (0, 2.5):
            sc.add("drums", kick(rng), at_beat=b * 4 + bt, gain=0.8)
        sc.add("drums", snare(rng), at_beat=b * 4 + 1, gain=0.5)
        sc.add("drums", snare(rng), at_beat=b * 4 + 3, gain=0.5)
        for k in range(8):
            sc.add("drums", hat(rng), at_beat=b * 4 + k * 0.5 + (0.06 if k % 2 else 0), gain=0.5 if k % 2 else 0.8)
    scale = scale_from(74, YO, 1)
    for ph in range(4, bars, 8):
        mel = melody(rng, scale, 2, 4, [[1, 1, 2], [0.5, 0.5, 1, 2], [2, 2]], start=2, home=0)
        render_melody(sc, rng, "koto", mel, koto, 0.6, ph * 4)
    y = sc.mix(rng, {"ep": 0.4, "pad": 0.4, "drums": 0.35, "koto": 0.45}, 0.25, 1.8)
    return norm_rms(lp(y, 9000) + white(rng, len(y)) * 0.0015, -21, -2)
