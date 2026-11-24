"""Registry of every sound key the game uses.

A key maps to 1..n variations. Each variation is either synthesised here
(source "synth", CC0, original work) or derived from a Kenney CC0 sample.
"""
import subprocess
import numpy as np

import dsp

REG = {}        # key -> dict(kind, n, fn, loop, stereo, db, bus, src, note)


def sfx(key, n=1, loop=False, stereo=False, db=0.0, bus="SFX", q=4, note=""):
    def deco(fn):
        REG[key] = {"key": key, "n": n, "fn": fn, "loop": loop, "stereo": stereo, "db": db,
                    "bus": bus, "src": "synth", "q": q, "note": note or (fn.__doc__ or "").strip()}
        return fn
    return deco


def kenney(key, files, process=None, db=0.0, bus="SFX", loop=False, note=""):
    """files: list of 'pack/Audio/name.ogg' relative to the Kenney download root."""
    REG[key] = {"key": key, "n": len(files), "files": files, "process": process, "loop": loop,
                "stereo": False, "db": db, "bus": bus, "src": "kenney", "q": 4, "note": note}


_KROOT = [None]


def set_kenney_root(p):
    _KROOT[0] = p


def load_audio(path, mono=True):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-f", "f32le", "-ac", "1" if mono else "2",
                          "-ar", str(dsp.SR), "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).astype(np.float64)
    if not mono:
        x = x.reshape(-1, 2).T
    return x


def kload(rel):
    if _KROOT[0] is None:
        raise RuntimeError("Kenney root not set (pass --kenney DIR)")
    import os
    return load_audio(os.path.join(_KROOT[0], rel))


# pack name (directory prefix) -> human name and page
KENNEY_PACKS = {
    "x_impact-sounds": ("Kenney - Impact Sounds 1.0", "https://kenney.nl/assets/impact-sounds"),
    "x_rpg-audio": ("Kenney - RPG Audio 1.0", "https://kenney.nl/assets/rpg-audio"),
    "x_interface-sounds": ("Kenney - Interface Sounds 1.0", "https://kenney.nl/assets/interface-sounds"),
    "x_ui-audio": ("Kenney - UI Audio 1.0", "https://kenney.nl/assets/ui-audio"),
    "x_sci-fi-sounds": ("Kenney - Sci-fi Sounds 1.0", "https://kenney.nl/assets/sci-fi-sounds"),
    "x_music-jingles": ("Kenney - Music Jingles 1.0", "https://kenney.nl/assets/music-jingles"),
}
