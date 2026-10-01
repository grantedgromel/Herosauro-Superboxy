#!/usr/bin/env python3
"""Turn the book's page PNGs from the owner's Drive into the game's story art.

    python3 tools/import_story_art.py <folder-of-pngs> <chapter> [--dry-run]

    e.g. python3 tools/import_story_art.py ~/Downloads/"#2: Estadio do Dragao" dragao

Run it from herosauro-superboxy/. For each page in the MAPPING table below it
reads the Drive file (names like "#1.png", "#5h.png", "#0 Cover.png"), scales
it to 1600 px wide (never up), and writes a quality-85 WebP to the path the
page's `art` field names in scripts/story/story_data.gd, i.e.
assets/story/<chapter>/<page id>.webp. Then run `godot --headless --import .`
once so Godot picks the new files up. The page reader shows a painted page as
soon as its file exists; pages without one stay composed, so a partial import
is fine.

THE MAPPING TABLE IS YOURS TO EDIT. It was written from the file names in the
Drive folders as of December 2025 and from the page numbering in
docs/story/SOURCE.md; where a page has alternates (#5h / #5e / #5ee) the first
listed is used and the others are noted. The Panda pages are a best guess,
because that chapter's text is an adaptation. Change a right-hand side to pick
a different picture; delete a line to keep that page composed.

CONVERTERS, best first. Nothing has to be installed beyond what the project
already needs:
  1. Pillow  (pip install Pillow)
  2. cwebp   (libwebp's command-line tool)
  3. ImageMagick (`magick`, or `convert` on older installs)
  4. Godot itself: the same `godot` binary that builds the game, run headless
     on a throwaway script (Image.load_from_file + save_webp). Always there.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

WIDTH = 1600
QUALITY = 85

# chapter id -> {page id or "cover": Drive file name}
MAPPING = {
    # Page ids follow the final book: letter = story, number = page within the
    # story. Drive file numbers mostly match; the guesses are marked.
    "adamastor": {
        # Chapter 1's cover on the shelf is the game's key art, so #0.png is
        # not needed. a09-a12 are spoken beats during play, not pages, and
        # a13-a15 have no picture in Drive yet.
        "a01": "#1c.png",
        "a02": "#2c.png",
        "a03": "#3c.png",
        "a04": "#4a.png",
        "a05": "#5h.png",       # alternates: #5e.png, #5ee.png
        "a06": "#6c.png",
        "a07": "#7a.png",       # alternate: #7.1d.png
        "a08": "#8d.png",       # alternate: #8.1c.png
    },
    "dragao": {
        "cover": "#0 Cover.png",
        "d01": "#1.png",
        "d02": "#2.png",
        "d03": "#3.png",
        "d04": "#4.png",
        "d05": "#5.png",
        "d06": "#6.png",
        "d07": "#7.png",
        "d08": "#8.png",
        "d11": "#11.png",
        "d12": "#12.png",
        "d13": "#13a.png",
        "d14": "#14.png",
    },
    "pandas": {
        # 14 book pages, 14 Drive pictures; #8.1 and #12a/#12b are read as
        # the extra pages. p11 is a spoken beat, so #10 is unused.
        "cover": "#0 Cover (Panda).png",
        "p01": "#1.png",
        "p02": "#2.png",
        "p03": "#3.png",
        "p04": "#4.png",
        "p05": "#5.png",
        "p06": "#6.png",
        "p07": "#7.png",
        "p08": "#8.png",
        "p09": "#8.1.png",      # guess
        "p10": "#9.png",        # guess
        "p12": "#11.png",
        "p13": "#12a.png",
        "p14": "#12b.png",
    },
}

STORY_DATA = os.path.join("scripts", "story", "story_data.gd")


def story_paths(project: str, chapter: str) -> dict[str, str]:
    """Page id (and "cover") -> res:// path, read out of StoryData itself, so
    the destinations can never drift from what the reader looks for."""
    src = open(os.path.join(project, STORY_DATA), encoding="utf-8").read()
    start = src.find('"%s": {' % chapter)
    if start < 0:
        sys.exit("chapter '%s' is not in %s" % (chapter, STORY_DATA))
    nxt = len(src)
    for other in MAPPING:
        if other != chapter:
            k = src.find('"%s": {' % other, start + 1)
            if k > start:
                nxt = min(nxt, k)
    block = src[start:nxt]
    out = {m.group(1): m.group(2) for m in
           re.finditer(r'"id":\s*"(\w+)",\s*"art":\s*"(res://[^"]+)"', block)}
    cover = re.search(r'"cover":\s*"(res://[^"]+)"', block)
    if cover:
        out["cover"] = cover.group(1)
    return out


def to_disk(project: str, res_path: str) -> str:
    return os.path.join(project, res_path[len("res://"):])


# --- converters --------------------------------------------------------------
#
# Each takes a list of (src, dst) jobs and returns the ones it could not do, so
# a converter that is installed but cannot write WebP (an ImageMagick built
# without the webp delegate) hands its files on to the next one.

def _pillow(jobs):
    from PIL import Image  # optional dependency
    failed = []
    for src, dst in jobs:
        try:
            img = Image.open(src)
            img = img.convert("RGBA" if "A" in img.getbands() else "RGB")
            if img.width > WIDTH:
                img = img.resize((WIDTH, round(img.height * WIDTH / img.width)), Image.LANCZOS)
            img.save(dst, "WEBP", quality=QUALITY, method=6)
        except Exception as e:  # noqa: BLE001 - report and hand on
            print("  Pillow could not do %s: %s" % (os.path.basename(src), e))
            failed.append((src, dst))
    return failed


def _run_each(jobs, argv_for):
    failed = []
    for src, dst in jobs:
        r = subprocess.run(argv_for(src, dst), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode != 0 or not os.path.isfile(dst):
            failed.append((src, dst))
    return failed


def _cwebp(jobs):
    return _run_each(jobs, lambda src, dst: ["cwebp", "-quiet", "-q", str(QUALITY),
        "-resize", str(WIDTH), "0", src, "-o", dst])


def _magick(jobs, exe):
    return _run_each(jobs, lambda src, dst: [exe, src, "-resize", "%dx>" % WIDTH,
        "-quality", str(QUALITY), dst])


GODOT_SCRIPT = """extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	for i in range(0, a.size(), 2):
		var img := Image.load_from_file(a[i])
		if img == null or img.is_empty():
			continue
		if img.get_width() > %d:
			img.resize(%d, int(round(img.get_height() * %d.0 / img.get_width())), Image.INTERPOLATE_LANCZOS)
		img.save_webp(a[i + 1], true, %f)
	quit()
""" % (WIDTH, WIDTH, WIDTH, QUALITY / 100.0)


def _godot(jobs, project):
    exe = shutil.which("godot") or shutil.which("godot4")
    if exe is None:
        return jobs
    with tempfile.TemporaryDirectory() as tmp:
        script = os.path.join(tmp, "webp.gd")
        open(script, "w").write(GODOT_SCRIPT)
        args = [exe, "--headless", "--path", project, "--script", script, "--"]
        for src, dst in jobs:
            args += [os.path.abspath(src), os.path.abspath(dst)]
        subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return [(src, dst) for src, dst in jobs if not os.path.isfile(dst)]


def convert(jobs, project):
    chain = []
    try:
        import PIL  # noqa: F401
        chain.append(("Pillow", _pillow))
    except ImportError:
        pass
    if shutil.which("cwebp"):
        chain.append(("cwebp", _cwebp))
    for exe in ("magick", "convert"):
        if shutil.which(exe):
            chain.append(("ImageMagick (%s)" % exe, lambda j, e=exe: _magick(j, e)))
            break
    chain.append(("Godot", lambda j: _godot(j, project)))
    left = list(jobs)
    for name, fn in chain:
        if not left:
            break
        print("converter: %s (%d file(s))" % (name, len(left)))
        left = fn(left)
    for src, _dst in left:
        print("FAILED: %s (not a readable PNG?)" % os.path.basename(src))
    return left


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("folder", help="folder holding the Drive PNGs for one chapter")
    ap.add_argument("chapter", choices=sorted(MAPPING), help="StoryData chapter id")
    ap.add_argument("--project", default=".", help="the Godot project (default: .)")
    ap.add_argument("--out", default="", help="write here instead of the project (testing)")
    ap.add_argument("--dry-run", action="store_true", help="show what would be written")
    opt = ap.parse_args()

    project = os.path.abspath(opt.project)
    targets = story_paths(project, opt.chapter)
    jobs = []
    for page, name in MAPPING[opt.chapter].items():
        if page not in targets:
            print("skip %-6s %s: no such page in StoryData" % (page, name))
            continue
        src = os.path.join(opt.folder, name)
        if not os.path.isfile(src):
            print("skip %-6s %s: not in the folder" % (page, name))
            continue
        dst = to_disk(project, targets[page])
        if opt.out:
            dst = os.path.join(opt.out, os.path.basename(dst))
        if not dst.endswith(".webp"):
            # e.g. a cover that StoryData points at a .png: leave it alone.
            print("skip %-6s %s: StoryData wants %s" % (page, name, targets[page]))
            continue
        print("%-6s %s -> %s" % (page, name, os.path.relpath(dst, project)))
        jobs.append((src, dst))
    missing = sorted(set(targets) - set(MAPPING[opt.chapter]))
    if missing:
        print("composed (no picture mapped): %s" % ", ".join(missing))
    if opt.dry_run or not jobs:
        return
    for _src, dst in jobs:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
    failed = convert(jobs, project)
    print("wrote %d page(s). Now run: godot --headless --import ." % (len(jobs) - len(failed)))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
