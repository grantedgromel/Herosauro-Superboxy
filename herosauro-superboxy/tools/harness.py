#!/usr/bin/env python3
"""The review harness. Capture, gate, profile and contact-sheet the game.

This is the loop the whole quality pass runs inside:

    tools/harness.py capture --out shots/round3      # render the shot set
    tools/harness.py sheet   shots/round3            # one image a critic can read
    tools/harness.py diff    shots/base shots/round3 # per-pixel regression gate
    tools/harness.py verify                          # prove captures reproduce
    tools/harness.py check                           # fast pre-commit smoke

Every shot is rendered in its OWN Godot process (see tools/baseline.gd for why),
under --fixed-fps so the simulation advances by an exact amount per frame. The
container has no GPU, so this drives Mesa's lavapipe software Vulkan under Xvfb;
that is slow — budget ~3 min per shot at 1280x720 — but it is the real Forward+
pipeline, not a fallback, so what the critic sees is what ships.

Because it is slow, shots run concurrently, each on its own Xvfb display. Concurrency
defaults to cores-1: lavapipe is itself threaded, so oversubscribing makes the
whole set slower rather than faster.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png  # noqa: E402  (local module, path set above)

ROOT = Path(__file__).resolve().parent.parent          # the Godot project dir
MANIFEST = ROOT / "tools" / "shots.json"
LAVAPIPE = "/usr/share/vulkan/icd.d/lvp_icd.json"

TIERS = {
    # name:      (width, height, settle multiplier)
    "review": (1280, 720, 1.0),   # what critics score. Slow and correct.
    "fast": (640, 360, 0.6),      # iteration. Same framing, ~5x cheaper.
}


def shots(names: list[str] | None = None, kinds: list[str] | None = None) -> list[dict]:
    data = json.loads(MANIFEST.read_text())["shots"]
    if kinds:
        data = [s for s in data if s.get("kind") in kinds]
    if names:
        want = set(names)
        data = [s for s in data if s["name"] in want]
        missing = want - {s["name"] for s in data}
        if missing:
            raise SystemExit(f"no such shot(s): {', '.join(sorted(missing))}")
    return data


def godot_bin() -> str:
    for cand in ("godot", "godot4"):
        found = shutil.which(cand)
        if found:
            return found
    raise SystemExit("godot not found on PATH")


# --- capture -----------------------------------------------------------------

def _render(shot: dict, out: Path, tier: str, timeout: int) -> dict:
    w, h, _ = TIERS[tier]
    env = dict(os.environ)
    if Path(LAVAPIPE).exists():
        env["VK_ICD_FILENAMES"] = LAVAPIPE

    # `-a` (auto-pick a free display), NOT `-n <fixed number>`. Fixed numbers
    # were chosen for reproducibility, which was a mistake twice over: the X
    # display number cannot reach a pixel, and hard-coding it means two harness
    # invocations running at once — a capture sweep and an agent's own spot
    # check, say — both grab :90 and the second dies with "Xvfb failed to start".
    cmd = [
        "xvfb-run", "-a", "-s", f"-screen 0 {w}x{h}x24",
        godot_bin(), "--path", str(ROOT), "tools/baseline.tscn",
        "--rendering-driver", "vulkan",
        "--fixed-fps", "60",
        "--resolution", f"{w}x{h}",
        "--", f"--shot={shot['name']}", f"--out={out}",
    ]

    t0 = time.time()
    try:
        proc = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)
        rc = proc.returncode
        tail = proc.stdout.strip().splitlines()[-3:] + proc.stderr.strip().splitlines()[-3:]
    except subprocess.TimeoutExpired:
        rc, tail = -1, [f"TIMEOUT after {timeout}s"]

    made = (out / f"{shot['name']}.png").exists()
    return {
        "shot": shot["name"],
        "ok": rc == 0 and made,
        "rc": rc,
        "seconds": round(time.time() - t0, 1),
        "log": [ln for ln in tail if ln and "ALSA" not in ln and "pulse" not in ln],
    }


def cmd_capture(args) -> int:
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    todo = shots(args.shots.split(",") if args.shots else None,
                 args.kinds.split(",") if args.kinds else None)

    workers = args.jobs or max(1, (os.cpu_count() or 2) - 1)
    print(f"capture: {len(todo)} shots, tier={args.tier}, {workers} workers -> {out}")

    results: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(_render, s, out, args.tier, args.timeout): s
            for s in todo
        }
        for fut in concurrent.futures.as_completed(futures):
            r = fut.result()
            results.append(r)
            mark = "ok " if r["ok"] else "FAIL"
            print(f"  [{mark}] {r['shot']:<18} {r['seconds']:>6.1f}s")
            if not r["ok"]:
                for ln in r["log"]:
                    print(f"         {ln}")

    results.sort(key=lambda r: r["shot"])
    report = {"tier": args.tier, "out": str(out), "shots": results,
              "ok": all(r["ok"] for r in results)}
    (out / "report.json").write_text(json.dumps(report, indent=2))
    print(f"capture: {'OK' if report['ok'] else 'FAILED'} "
          f"({sum(r['ok'] for r in results)}/{len(results)})")
    return 0 if report["ok"] else 1


# --- diff --------------------------------------------------------------------

def _compare(a_path: Path, b_path: Path, heat: Path | None) -> dict:
    a, b = png.read(str(a_path)), png.read(str(b_path))
    if (a.w, a.h) != (b.w, b.h):
        return {"shot": a_path.stem, "identical": False,
                "note": f"size {a.w}x{a.h} vs {b.w}x{b.h}"}

    n = a.w * a.h
    moved = 0
    total = 0
    worst = 0
    hm = bytearray(n * 3) if heat else None
    ar, br = a.rgb, b.rgb
    for i in range(n):
        j = i * 3
        d = (abs(ar[j] - br[j]) + abs(ar[j + 1] - br[j + 1]) + abs(ar[j + 2] - br[j + 2]))
        if d:
            moved += 1
            total += d
            if d > worst:
                worst = d
            if hm is not None:
                v = 255 if d > 24 else 96 + d * 6
                hm[j] = v
        elif hm is not None:
            g = ar[j] // 4
            hm[j] = hm[j + 1] = hm[j + 2] = g

    if hm is not None and heat is not None:
        png.write(str(heat), png.Image(a.w, a.h, hm))

    return {
        "shot": a_path.stem,
        "identical": moved == 0,
        "pixels_moved": moved,
        "pixels_moved_pct": round(100.0 * moved / n, 4),
        "mean_channel_delta": round(total / max(1, moved) / 3.0, 2),
        "worst_channel_delta": worst,
    }


def cmd_diff(args) -> int:
    a_dir, b_dir = Path(args.a).resolve(), Path(args.b).resolve()
    heat_dir = Path(args.heatmaps).resolve() if args.heatmaps else None
    if heat_dir:
        heat_dir.mkdir(parents=True, exist_ok=True)

    names = sorted(p.stem for p in a_dir.glob("*.png"))
    rows = []
    for name in names:
        b = b_dir / f"{name}.png"
        if not b.exists():
            rows.append({"shot": name, "identical": False, "note": "missing in B"})
            continue
        rows.append(_compare(a_dir / f"{name}.png", b, heat_dir / f"{name}.png" if heat_dir else None))

    clean = all(r.get("identical") for r in rows)
    for r in rows:
        if r.get("identical"):
            print(f"  [same] {r['shot']}")
        elif "note" in r:
            print(f"  [DIFF] {r['shot']:<18} {r['note']}")
        else:
            print(f"  [DIFF] {r['shot']:<18} {r['pixels_moved_pct']:>7.3f}% of pixels, "
                  f"worst channel delta {r['worst_channel_delta']}")
    print(f"diff: {'IDENTICAL' if clean else 'CHANGED'}")
    if args.json:
        Path(args.json).write_text(json.dumps(rows, indent=2))
    return 0 if clean else 1


# --- contact sheet -----------------------------------------------------------

def cmd_sheet(args) -> int:
    src = Path(args.dir).resolve()
    files = sorted(p for p in src.glob("*.png") if p.stem != "sheet")
    if not files:
        raise SystemExit(f"no PNGs in {src}")

    cols = args.cols
    cell_w = args.cell
    tiles = []
    for f in files:
        im = png.read(str(f))
        cell_h = max(1, round(cell_w * im.h / im.w))
        tiles.append((f.stem, png.scaled(im, cell_w, cell_h)))

    cell_h = max(t[1].h for t in tiles)
    rows = (len(tiles) + cols - 1) // cols
    pad = 6
    sheet = png.blank(cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad, (18, 18, 22))
    for i, (_, im) in enumerate(tiles):
        x = pad + (i % cols) * (cell_w + pad)
        y = pad + (i // cols) * (cell_h + pad)
        png.blit(sheet, im, x, y)

    out = Path(args.out) if args.out else src / "sheet.png"
    png.write(str(out), sheet)
    print(f"sheet: {out}  ({len(tiles)} shots, {cols} across)")
    print("order: " + ", ".join(t[0] for t in tiles))
    return 0


# --- reproducibility proof ---------------------------------------------------

def cmd_verify(args) -> int:
    """Capture the same shots twice into different directories and diff them.

    This is the claim the whole gate depends on, so it is checked rather than
    asserted. If this fails, something in the game is reading the wall clock or
    an unseeded RNG, and the per-pixel gate is worthless until it is fixed.
    """
    base = Path(args.workdir).resolve()
    a, b = base / "verify_a", base / "verify_b"
    for d in (a, b):
        shutil.rmtree(d, ignore_errors=True)

    ns = argparse.Namespace(out=str(a), tier=args.tier, shots=args.shots,
                            kinds=args.kinds, jobs=args.jobs, timeout=args.timeout)
    if cmd_capture(ns) != 0:
        return 1
    ns.out = str(b)
    if cmd_capture(ns) != 0:
        return 1

    print("\nverify: comparing the two runs")
    return cmd_diff(argparse.Namespace(a=str(a), b=str(b), heatmaps=None,
                                       json=str(base / "verify.json")))


# --- fast smoke --------------------------------------------------------------

def cmd_check(args) -> int:
    """Pre-commit gate: does it import, boot and render at all?"""
    env = dict(os.environ)
    if Path(LAVAPIPE).exists():
        env["VK_ICD_FILENAMES"] = LAVAPIPE

    print("check: importing resources")
    r = subprocess.run([godot_bin(), "--headless", "--path", str(ROOT), "--import"],
                       env=env, capture_output=True, text=True, timeout=1200)
    errors = [ln for ln in (r.stdout + r.stderr).splitlines()
              if "ERROR" in ln or "SCRIPT ERROR" in ln]
    if errors:
        print("check: import reported errors")
        for ln in errors[:20]:
            print("   " + ln)
        return 1

    print("check: rendering one shot")
    out = Path(args.workdir).resolve() / "check"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True, exist_ok=True)
    res = _render(shots(["01_deck_mid"])[0], out, "fast", args.timeout)
    if not res["ok"]:
        print("check: render FAILED")
        for ln in res["log"]:
            print("   " + ln)
        return 1
    print(f"check: OK ({res['seconds']}s)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="harness.py", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    work = "/tmp/hs-harness"

    c = sub.add_parser("capture", help="render the shot set")
    c.add_argument("--out", required=True)
    c.add_argument("--tier", choices=TIERS, default="review")
    c.add_argument("--shots", help="comma-separated shot names")
    c.add_argument("--kinds", help="comma-separated: world,game,menu")
    c.add_argument("--jobs", type=int, default=0)
    c.add_argument("--timeout", type=int, default=1800)
    c.set_defaults(func=cmd_capture)

    d = sub.add_parser("diff", help="per-pixel gate between two capture dirs")
    d.add_argument("a")
    d.add_argument("b")
    d.add_argument("--heatmaps")
    d.add_argument("--json")
    d.set_defaults(func=cmd_diff)

    s = sub.add_parser("sheet", help="contact sheet for a capture dir")
    s.add_argument("dir")
    s.add_argument("--out")
    s.add_argument("--cols", type=int, default=3)
    s.add_argument("--cell", type=int, default=520)
    s.set_defaults(func=cmd_sheet)

    v = sub.add_parser("verify", help="prove captures are reproducible")
    v.add_argument("--tier", choices=TIERS, default="fast")
    v.add_argument("--shots")
    v.add_argument("--kinds")
    v.add_argument("--jobs", type=int, default=0)
    v.add_argument("--timeout", type=int, default=1800)
    v.add_argument("--workdir", default=work)
    v.set_defaults(func=cmd_verify)

    k = sub.add_parser("check", help="fast pre-commit smoke")
    k.add_argument("--workdir", default=work)
    k.add_argument("--timeout", type=int, default=900)
    k.set_defaults(func=cmd_check)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
