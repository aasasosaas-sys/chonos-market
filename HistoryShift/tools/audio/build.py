#!/usr/bin/env python3
"""Build every game sound into assets/audio/ (ogg) + manifest.json + ASSET_CREDITS.txt.

usage: python3 tools/audio/build.py --kenney <dir with extracted Kenney packs x_*> [--only key1,key2] [--jobs 4]

Kenney packs (CC0) are downloaded from https://kenney.nl/assets/<pack> and extracted to
<dir>/x_<pack>/ (impact-sounds, rpg-audio, interface-sounds, ui-audio, sci-fi-sounds).
All other sounds are synthesised here (numpy + scipy) and are CC0 as well.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from multiprocessing import Pool

import numpy as np
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dsp            # noqa: E402
import registry       # noqa: E402
import gen_sfx        # noqa: E402,F401
import gen_amb        # noqa: E402,F401
import gen_music      # noqa: E402,F401
import gen_weather    # noqa: E402,F401

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")


def subdir(key):
    if key.startswith("music_") or key.startswith("stinger_"):
        return "music"
    if key.startswith("amb_") or key.startswith("bird_") or key in ("temple_bell", "wind_chime", "dog_bark", "train_whistle", "lab_beep"):
        return "ambience"
    if key.startswith("step_") or key.startswith("land_") or key.startswith("hoof_"):
        return "footsteps"
    if key.startswith("ui_"):
        return "ui"
    return "sfx"


def encode(x, path, q, stereo):
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 2 and not stereo:
        x = x.mean(axis=0)
    x = np.clip(x, -1.0, 1.0)
    data = (x.T if x.ndim == 2 else x) * 32767.0
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp = tf.name
    try:
        wavfile.write(tmp, dsp.SR, data.astype(np.int16))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), path], check=True)
    finally:
        os.unlink(tmp)


def render(job):
    key, i = job
    e = registry.REG[key]
    seed = int(hashlib.md5(("%s:%d" % (key, i)).encode()).hexdigest()[:8], 16)
    rng = np.random.default_rng(seed)
    if e["src"] == "kenney":
        x = registry.kload(e["files"][i])
        if e.get("process"):
            x = e["process"](x, rng, i)
        else:
            x = dsp.norm_peak(x, -1)
    else:
        x = e["fn"](rng, i)
    d = os.path.join(OUT, subdir(key))
    os.makedirs(d, exist_ok=True)
    name = "%s_%02d.ogg" % (key, i) if e["n"] > 1 else "%s.ogg" % key
    p = os.path.join(d, name)
    encode(x, p, e["q"] if not e["stereo"] else min(e["q"], 3), e["stereo"])
    dur = (x.shape[-1]) / dsp.SR
    return key, i, os.path.relpath(p, ROOT).replace(os.sep, "/"), dur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kenney", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    registry.set_kenney_root(os.path.abspath(a.kenney))
    keys = sorted(registry.REG)
    if a.only:
        keys = [k for k in keys if k in a.only.split(",") or any(k.startswith(p.rstrip("*")) for p in a.only.split(",") if p.endswith("*"))]
    jobs = [(k, i) for k in keys for i in range(registry.REG[k]["n"])]
    print("rendering %d files for %d keys" % (len(jobs), len(keys)))
    with Pool(a.jobs, initializer=registry.set_kenney_root, initargs=(os.path.abspath(a.kenney),)) as pool:
        res = pool.map(render, jobs, chunksize=1)
    man_path = os.path.join(OUT, "manifest.json")
    man = {}
    if a.only and os.path.exists(man_path):
        man = json.load(open(man_path, encoding="utf-8")).get("sounds", {})
    by = {}
    for key, i, p, dur in res:
        by.setdefault(key, []).append((i, p, dur))
    for key, lst in by.items():
        e = registry.REG[key]
        lst.sort()
        man[key] = {"files": ["res://" + p for (_, p, _) in lst], "loop": e["loop"], "db": e["db"], "bus": e["bus"],
                    "src": e["src"], "len": round(max(d for (_, _, d) in lst), 3)}
    json.dump({"version": 1, "sounds": dict(sorted(man.items()))}, open(man_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    write_credits(man)
    write_gd_manifest(man)
    tot =sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(OUT) for f in fs if f.endswith(".ogg"))
    print("done: %d keys, %.2f MB of ogg" % (len(man), tot / 1e6))


def write_gd_manifest(man):
    """scripts/audio/sound_manifest.gd: the same table as a GDScript constant (export-safe, no JSON at runtime)."""
    out = ["class_name SoundManifest", "extends RefCounted",
           "## 自動生成（tools/audio/build.py）。手で編集しない。key -> {files, loop, db, bus, len}", "", "const SOUNDS := {"]
    for key in sorted(man):
        e = man[key]
        files = ", ".join('"%s"' % f for f in e["files"])
        out.append('\t"%s": {"files": [%s], "loop": %s, "db": %.1f, "bus": "%s", "len": %.3f},' % (
            key, files, "true" if e["loop"] else "false", float(e["db"]), e["bus"], float(e["len"])))
    out.append("}")
    p = os.path.join(ROOT, "scripts", "audio", "sound_manifest.gd")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")


def write_credits(man):
    lines = []
    lines.append("JIDAI SHIFT - audio asset credits and licences")
    lines.append("=" * 60)
    lines.append("")
    lines.append("Every file under assets/audio/ is either:")
    lines.append("  (a) derived from a Kenney audio pack - Creative Commons Zero (CC0 1.0)")
    lines.append("      https://creativecommons.org/publicdomain/zero/1.0/  (credit 'Kenney / www.kenney.nl' is optional),")
    lines.append("      decoded, trimmed, normalised, re-encoded and in some cases processed (e.g. running-footstep variants);")
    lines.append("  (b) synthesised procedurally by tools/audio/*.py (numpy/scipy, no recorded samples) for this project.")
    lines.append("      These synthesised sounds and the music are released under CC0 1.0 as well.")
    lines.append("")
    lines.append("Regenerate: python3 tools/audio/build.py --kenney <dir with the extracted Kenney packs>")
    lines.append("No freesound.org / OpenGameArt / Sonniss material is included.")
    lines.append("")
    lines.append("Kenney packs used:")
    for k, (name, url) in registry.KENNEY_PACKS.items():
        lines.append("  - %s  <%s>  licence: CC0 1.0" % (name, url))
    lines.append("")
    lines.append("Per-file list (key: file <- source | licence | note)")
    lines.append("-" * 60)
    for key in sorted(man):
        e = registry.REG.get(key)
        if e is None:
            continue
        for i, f in enumerate(man[key]["files"]):
            if e["src"] == "kenney":
                rel = e["files"][i]
                pack = rel.split("/")[0]
                src = "%s: %s" % (registry.KENNEY_PACKS.get(pack, (pack, ""))[0], rel.split("/")[-1])
                lic = "CC0 1.0 (Kenney)"
            else:
                mod = getattr(e.get("fn"), "__module__", "") or ""
                gen = ("gen_weather.py" if mod == "gen_weather" else
                       "gen_music.py" if key.startswith(("music_", "stinger_")) else
                       "gen_amb.py" if subdir(key) == "ambience" else "gen_sfx.py")
                src = "procedural synthesis (tools/audio/%s)" % gen
                lic = "CC0 1.0 (original work for this project)"
            note = e.get("note", "")
            lines.append("%s: %s <- %s | %s%s" % (key, f.replace("res://", ""), src, lic, (" | " + note) if note and i == 0 else ""))
    open(os.path.join(OUT, "ASSET_CREDITS.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
