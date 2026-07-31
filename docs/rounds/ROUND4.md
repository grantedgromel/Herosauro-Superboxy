# Round 4 — performance, and the measurements that were measuring nothing

Round 4 was not scored by a critic. It started from four criticisms the user
made directly, which is a better signal than a rubric and is worth saying out
loud: **the rubric never once flagged that the game was unplayable in a
browser.** It scores frames. A frame at 8 fps and a frame at 60 fps are the
same PNG.

The four:

1. the menu screen is weird — make it static
2. the lighting is so bright it is white
3. it runs really slowly in the browser
4. the rule under the title "screams AI slop"

(1) and (4) landed in `bb1ac7f`, (2) in `56dec3b`, (3) across `32adce7`,
`19b521d`, `4b20430`, `9799d2d` and `2c2e155`.

This document is about what measuring (3) turned up. Most of it is corrections
to my own work, and they fall into two kinds. Three published numbers were
simply wrong. Worse, and the reason this round is worth reading: **three of this
project's measurement tools were not measuring anything**, and one of those was
the tool written this round to catch the other two.

## Corrections

### The artwork was 9.9 MiB resident, not 45

`19b521d`'s commit message says the eight installed PNGs were "roughly 45 MiB"
of uncompressed RGBA8 in VRAM. Measured from the IHDR of each file:

| file | pixels | RGBA8 | referenced by |
|---|---|---|---|
| `ui/key_art.png` | 1672×941 | 6.00 MiB | `menu_backdrop.gd` |
| `ui/portraits/adamastor.png` | 631×900 | 2.17 MiB | `ui_style.gd` |
| `ui/portraits/herosauro.png` | 282×900 | 0.97 MiB | `ui_style.gd` |
| `ui/portraits/superboxy.png` | 209×900 | 0.72 MiB | `ui_style.gd` |
| `ui/art/banner_adamastor.png` | 1672×941 | 6.00 MiB | **nothing** |
| `ui/art/banner_superboxy.png` | 1672×941 | 6.00 MiB | **nothing** |
| `ui/art/figure_adamastor.png` | 1024×1536 | 6.00 MiB | **nothing** |
| `ui/art/figure_superboxy.png` | 1024×1536 | 6.00 MiB | **nothing** |

Total across all eight is 33.9 MiB, not 45. And only the top four are loaded by
anything, so the resident figure is **9.9 MiB**. The other 24 MiB was never in
VRAM at all — it was pck weight, which is a different problem with a different
fix, and I gave it the wrong one's number.

The compression change in `19b521d` bought about a fifth of what I claimed, and
`2c2e155` later reverted the largest of the eight for reasons that had nothing
to do with size — see below. `4b20430` handles the real problem with the four
unreferenced plates: they are excluded from the web pck.

### I had the texture-compression argument backwards

`19b521d` moved all eight UI plates to VRAM Compressed and justified it: *"these
are painterly plates viewed at or near native size, where the block artifacts
have nothing crisp to chew on."* That is the reasoning inverted. Block
compression is *good* at busy detail, which hides its 4-colour-per-block
quantisation, and *bad* at exactly the two things this art has — smooth
painterly gradients and crisp high-contrast edges.

So it went through the gate it should have gone through in the first place.
`13_menu` rendered against a lossless baseline:

| | RMSE | PSNR | >4 levels | >16 levels | max |
|---|---|---|---|---|---|
| BC1/BC3 | 11.83 | 26.67 dB | 44.8% | 13.2% | 209 |
| BC7/ASTC (`high_quality`) | 11.17 | 27.17 dB | 35.4% | 11.7% | 218 |

`harness.py verify` on the same shot returns IDENTICAL, so that is signal and
not capture noise. A 16× region map put the damage in the right-lower quadrant
at mean |Δ| 18–24 while the left side sat at 0.5–2, and a 3× crop shows why: the
error is **edge ringing** — the eye outlines, the mask rim, the glove seams, the
"SUPER BOXY" lettering — not gradient banding. The conclusion happened to
survive, but not for the reason given.

BC7 is not the answer: 0.5 dB for double the bytes. The split that is:

* **`key_art.png` back to Lossless.** It is the full-bleed menu backdrop, so it
  *is* the frame that took the damage, and it is `load()`ed at runtime by
  `menu_backdrop.gd` rather than preloaded — resident only while the title
  screen is up, never during the fight, which is when frame rate matters. Six
  MiB is not worth degrading the title screen, and the user has art-directed
  that screen twice. `13_menu` now renders IDENTICAL to the lossless baseline.
* **The three portraits stay compressed**, and that half was measured too
  rather than argued. They are `preload` constants in `ui_style.gd`, so they are
  resident for the whole process including the fight. `14_hud` against a
  lossless-portrait baseline: **0.751% of the frame changes, and within those
  6,925 pixels RMSE is 4.37, only 5.3% exceed 8 levels, 0.5% exceed 16, and the
  worst is 35.** Against the backdrop's 11.83 / 13.2% / 209, that is three times
  cleaner on RMSE and twenty-six times smaller in the tail — the portraits are
  drawn at roughly 200 px from 900 px sources, and minification averages the
  block error away.
* **The four `art/` plates stay compressed** and are excluded from the web pck
  entirely, so the setting only affects a desktop download.

### The figure plates DO have alpha

I recorded that the two 1024×1536 cutouts "have baked gradient backgrounds, not
alpha", and therefore could not be used as portraits. Decoded and measured:

```
figure_superboxy.png  a=0: 60.19%   a=255: 21.96%   partial: 17.85%
figure_adamastor.png  a=0: 60.42%   a=255: 22.87%   partial: 16.70%
```

All four corners are a=0. The alpha bounding box is 89%×88% and 77%×89% of the
frame. A mid-row profile runs `0 0 0 0 0 255 255 255 … 255 0 0 0` — a hard
silhouette with soft edges, which is exactly what a cutout is. They are usable
as-is; `UIStyle.portrait_scaled()` already crops from alpha bounds.

### `tools/budget.gd` printed zero for the three numbers it exists to report

Not a wrong claim so much as a tool that could not have produced a right one.
"objects in frame", "draw calls in frame" and "primitives in frame" came back
`0` on every run this tool has ever done. The counters were fine —
`budget.tscn` had no `Camera3D`, so nothing rendered 3D, and zero was honest.

### `tools/profile.gd` had never run at all

Worse, and found while setting its ceilings. The profiler did not parse:

```gdscript
var p50 := proc["p50"]      # Parse Error: cannot infer the type of "p50"
```

`:=` off a Dictionary subscript is a hard parse error in GDScript. The line had
been there since the file was written, so the tool that owns the frame-cost
distribution, the hitch attribution and the budget gate has been dead code for
its whole life. `--import` could not catch it — Godot compiles what the imported
resources reference, and a script reached only through a `.tscn` that no import
loads is never compiled — so CI's "Import must be error-free" was grepping a log
that could not contain the error.

And underneath that, the gate could not have failed even if it had run:
`_report()` printed `BUDGET EXCEEDED` and `_process` then called
`get_tree().quit(0)` unconditionally.

### The parse check I wrote to catch it passed the bug on its first try

`tools/parsecheck.tscn` now loads every `.gd` in one process. Its first version
tested `ResourceLoader.load(path, "Script") == null` — and with the real bug put
back into `profile.gd` on purpose, it printed **PASS**. Godot returns a `Script`
object for a file that did not compile; measured, `load()` non-null and
`reload()` → `43` (`ERR_PARSE_ERROR`). It checks `reload()` now, and was run in
all three states before being wired to CI: clean → PASS, bug → FAIL exit 1,
restored → PASS.

**Four instances of one failure shape.** The `_menu_probe` measuring a scene it
had failed to add to the tree; `budget.gd`'s zeros; a profiler that never
parsed; a parse check that passed its own motivating bug. Every one of them
reported a clean result rather than an error, and three of the four were written
*by this loop, to check this loop*. A tool that does not run looks exactly like a
tool that runs and finds nothing wrong — so a new gate does not count until it
has been watched failing on the fault it was built for.

## What the fixed tool measured

`tools/budget.tscn`, Forward+, llvmpipe, 1280×720, `bridge_arena.tscn` with no
actors and no FX:

```
census   178 mesh surfaces, 130 of them casting shadow
         7 multimeshes / 604 instances
         1,106,039 triangles
         48.0 MiB texture, 76.9 MiB buffer, 141.9 MiB video

sweep    worst 01_deck_mid  575 obj  575 draws  3,261,457 prims
         range 3,131,571 .. 3,261,457 across all ten vantages
```

The same sweep on GL Compatibility, which is what the browser builds:

```
census   209 mesh surfaces, 100 of them casting shadow
         416,883 triangles
         15.1 MiB texture, 37.3 MiB buffer, 52.3 MiB video

sweep    worst 02_deck_eye  226 obj  226 draws    574,730 prims
         range   491,409 ..   574,730
```

**The web tier costs 17.6% of the desktop tier's worst-case primitives and 39%
of its draw calls.** That is the geometry tier from `32adce7` measured end to
end rather than inferred from its levers. The full ten-vantage table for both
tiers is in `docs/PERFORMANCE_BUDGET.md`.

### And the fight itself is 1.5% of the frame

`tools/profile.tscn`, once it could run at all, over 600 frames of the scripted
route, one run per tier:

```
Forward+          p50         p95         p99         max
  draw calls      693         721         726         730
  primitives  3,305,102   3,311,709   3,312,473   3,342,749
  nodes           667         727         735         739
  peak static memory 146.6 MiB

GL Compatibility  p50         p95         p99         max
  draw calls      441         474         479         480
  primitives    611,638     619,806     621,172     628,498
  nodes           696         756         764         768
  peak static memory 114.7 MiB
```

**Two heroes, a nine-metre giant and every combat effect add 51,016 primitives
to a 3,261,457-primitive static world.** Draw calls say it from the other side:
575 static, 726 live — the actors cost 151 draw calls and essentially no
geometry.

Whatever makes a frame expensive here, it is not the fight. That is the number
the last four rounds should have been working from.

### The finding: primitives do not respond to the camera

Across the ten Forward+ vantages, **objects range 380–575 — a 51% spread — and
primitives range 3,131,571–3,261,457, a spread of 4.1%.** `03_rail_macro` is a
camera half a metre from a railing at 45° FOV and it still submits 3.2M
primitives — 2.9× the entire world's triangle count.

The reason is that the shadow cascades are anchored to the camera's frustum
slices, not to what the camera is looking at, and the bridge is inside all four
of them from every vantage in the arena. Four cascades plus the colour pass is
five potential submissions per caster; `directional_shadow_blend_splits = true`
adds a sixth for anything near a split boundary. 2.9× is the average that comes
out of that.

This is the same root cause as the web-tier finding in `32adce7` — bakes whose
AABBs are too large to cull — showing up on the tier that fix did not touch. On
Compatibility the spread is 17%, four times better, which is the chunking
letting culling bite.

**Not acted on**, deliberately. It is desktop geometry and every available lever
(fewer cascades, `blend_splits` off, `cast_shadow` off on the far bakes,
visibility ranges) trades a measurable win for a visual cost that has to be
scored, not assumed. The user's complaint was the browser, and the browser is
addressed. This is written down so the next round starts from a number instead
of a hunch.

## Two web-tier "fixes" that are staying unfixed

Both were handed to me as perf items. Both are wrong, and `export_presets.cfg`
now says so in-file so nobody spends another round deriving it.

**`variant/thread_support=false`.** Multithreaded WASM needs SharedArrayBuffer,
which needs cross-origin isolation (COOP `same-origin` + COEP `require-corp`).
`.github/workflows/web-export.yml` publishes to GitHub Pages, which sends
neither header and provides no way to set them. Flipping the flag on its own
does not make the build slow; it makes it not boot. There is a route — enable
the PWA and let its service worker inject the headers — and it is worth doing,
but it costs a second page load before the worker is live and offline-caching a
16 MB pck, and it cannot be verified from a container with no browser and no
Pages origin.

**`vram_texture_compression/for_mobile=false`.** Shipping ETC2/ASTC next to
S3TC roughly doubles the compressed texture payload. No mobile browser can play
this: there is no touch scheme anywhere in the input map, every action is a key,
and it is two players sharing one keyboard.

## Still missing, and it needs the user

There is **no Herosauro banner and no Herosauro figure.** Adamastor and Super
Boxy each have both. Herosauro has only the 282×900 portrait, which is the
smallest of the three.

This is why the four plates are wired to nothing rather than into a versus card
or a boss intro: any screen built from what exists shows two of the three
characters. The user's note on the logo was that Herosauro and Super Boxy must
be the same size "otherwise it implies that Herosauro is somehow the more
important character" — a screen where Super Boxy has a full-body cutout and
Herosauro has a head is that same asymmetry, pointing the other way, and larger.

Two plates matching the existing set unblock it:

* `banner_herosauro.png` at 1672×941
* `figure_herosauro.png` at 1024×1536, transparent background

## The rubric's blind spot, again

`REVIEW_LOOP.md` already carries "the rubric is a proxy, do not optimise the
proxy", written after the round that tried to populate Porto with pedestrians.
Round 4 is the same lesson from the opposite side: **the proxy is also blind.**

Four rounds of adversarial critique scored the frames and never noticed the game
did not run. Frame rate is not in a PNG. Neither is load time, input latency,
audio, or whether the fight is winnable.

`tools/profile.tscn` exists to cover exactly that gap, and this round found it
had never executed — so the gap was not merely uncovered, it was covered by
something that reported nothing and was read as covering it. `tools/parsecheck`
and the profiler's exit code close that specific hole. The larger one stays
open: the profiler is still not run by CI, because 600 frames of a live fight
under software Vulkan is hours on a runner. Naming that is the honest state of
the loop, not a plan to close it.
