# Character art — regeneration prompts

The three menu portraits in `assets/ui/portraits/` were cut out of 4-view
character turnaround sheets, and the crops went wrong. This is the diagnosis and
the prompts to regenerate them as clean single-figure cut-outs.

## What is actually wrong

Measured from the alpha channel of each sheet:

| File | Size | Aspect | Fault |
|---|---|---|---|
| `superboxy.png` | 209×900 | 0.232 | **Two figures in one file.** Front view rows 3–428, back view rows 454–896, empty band between. Right edge sliced: 479 of 900 rows opaque at the last column. |
| `herosauro.png` | 282×900 | 0.311 | Right edge sliced through cape and arm: 443 of 900 rows opaque at the last column. Left margin 6 px. |
| `adamastor.png` | 631×900 | 0.701 | Cleanest of the three. Mane sits 1 px off the left edge — no bleed for the rim pass. |

## Why it shows up the way it does

`scripts/ui/menu/hero_stage.gd` scales the **whole file** to the figure height and
anchors the texture's **bottom edge** to the ground line:

```gdscript
var tex := UIStyle.portrait_scaled(int(fig["actor"]), want)   # whole file, not a region
var top := size.y + float(fig["feet"]) * _unit - h
```

So for Super Boxy the back view lands on the ground and the front view floats
above it, each at roughly half the intended height — `SUPERBOXY_SIZE` is 0.545 of
the stage unit, but figure 1 only occupies 47% of the file, so he draws ~185 px
tall where ~392 px was intended.

Each figure is also drawn three times — `shadow`, `rim`, `body` — and the `rim`
copy is the same texture scaled up around the centre. Art that touches the file
edge gets its backlight halo cut off flat against a straight vertical line.

The same three files feed the results card (`game_over.gd` → `portrait_scaled`,
whole file, so Super Boxy doubles there too) and the HUD avatars
(`portrait_head`, a hardcoded square region per sheet).

## What the replacements have to satisfy

1. **One figure, one view per file.** Not a turnaround, not a model sheet.
2. **Transparent background, clean alpha**, no matte fringe — a halo gets drawn
   three times over.
3. **Whole silhouette inside the frame with margin.** Nothing touching or
   crossing an edge, including hair, cape and gloves.
4. **Full body, head to feet, standing**, feet flat and level.
5. Consistent house style across all three — they share a frame.

## House style block

Prepend this to every character prompt so the cast matches:

> Children's picture-book cartoon character illustration, bold clean black ink
> outline of even weight, flat cel shading with soft gradient within each colour
> block, warm saturated palette, friendly modern mobile-game concept art. Full
> body, head to toe, standing upright and facing the viewer, feet flat and level
> on an invisible ground line, arms clear of the torso. Single character, one
> view only. Entire figure well inside the frame with clear empty margin on all
> four sides — nothing cropped, nothing touching the edge. Flat solid magenta
> background, no shadow cast on the background, no ground plane, no scenery.

**Use magenta (`#FF00FF`), not white or grey.** Super Boxy and Herosauro both
have white sneakers and white trim, and Adamastor is grey-skinned with white
hair — a white or grey backdrop destroys the alpha extraction on exactly the
parts that are already fragile. Magenta appears nowhere in any of the three.

## Prompt — Herosauro

> [house style block]
>
> A cheerful boy of about nine, slim, standing straight with a small confident
> smile. Short tousled dark brown hair. Red fabric domino eye mask across his
> eyes. Long-sleeved grass-green knit sweater with ribbed cuffs. Blue denim
> dungarees over the sweater, with a square chest pocket carrying a round
> embroidered patch: a friendly green cartoon dinosaur head on a yellow disc
> inside a red ring. A red hooded cape hanging down his back and spreading a
> little to either side of him. Cuffed jeans, white velcro sneakers. Arms
> relaxed at his sides, hands open, elbows slightly out from the body so the
> cape and both arms read as separate shapes.

**Target aspect after trimming:** ~0.33–0.38 wide-to-tall.

## Prompt — Super Boxy

> [house style block]
>
> A small boy of about five in chibi proportions — large round head, short body,
> stubby limbs. Brown bowl-cut hair with a single cowlick sticking up. Red
> fabric domino eye mask, large dark round eyes, wide happy grin. Red superhero
> cape with a tall stand-up collar, hanging behind him and flaring out to both
> sides. Green hoodie under blue denim dungarees. A round white-and-red enamel
> chest badge on the dungarees reading "SUPER BOXY" in red capitals on two
> lines. **Oversized red boxing gloves on both hands, each with a white band at
> the cuff**, held down and out at his sides, well away from his body. Red and
> white sneakers.

**Target aspect after trimming:** ~0.48. This is roughly **twice the current
0.232** — see the layout note below.

## Prompt — Adamastor

> [house style block]
>
> A colossal stone giant, a mythic Portuguese sea titan, standing in a heavy
> wide-legged stance and glowering straight ahead. Massive carved musculature,
> granite-grey skin with subtle stone fracture lines. Wild flowing pale
> silver-white hair streaming outward and a long thick silver-white beard down
> his chest. Glowing molten-orange eyes with small licks of orange flame curling
> from his brows. Pointed ears, heavy brow, stern closed mouth. Bare chest, a
> ragged dark olive-brown cloth loincloth at his waist. Wide battered gold-bronze
> bracers on both forearms. Barefoot. Arms hanging out and away from his body,
> hands open and slightly clawed. Leave generous empty margin around the streaming
> hair especially — the full spread of the mane must sit inside the frame.

**Target aspect after trimming:** ~0.70, matching the current sheet.

## Negative prompt

For any model that takes one (Stable Diffusion, Flux with a negative, Midjourney
via `--no`):

```
character turnaround, model sheet, reference sheet, multiple views, front and
back view, side view, two characters, duplicate figure, grid layout, multiple
panels, cropped, cut off, out of frame, touching frame edge, text, labels,
watermark, signature, logo, drop shadow on background, ground shadow, floor,
scenery, background detail, photorealistic, 3D render
```

## Parameters by model

| Model | Settings |
|---|---|
| **Midjourney** | `--ar 2:3 --style raw --s 150 --no character turnaround, model sheet, multiple views, cropped, text, watermark` |
| **GPT-Image / DALL·E** | Portrait 1024×1536. Prose works as written. Add the sentence: "Generate exactly one character in exactly one view — do not produce a turnaround or reference sheet." |
| **Flux** | Natural language as written, portrait 832×1216, guidance 3.5–4.0 |
| **Stable Diffusion XL** | Comma-separate the descriptors, 832×1216, CFG 6–7, plus the negative prompt above |
| **Ideogram** | Portrait 2:3, style preset "Design" — best of the group at the "SUPER BOXY" badge lettering |

Generate at **2:3 portrait**, not at the target aspect. Extreme aspect ratios
push these models toward mangled anatomy; the final narrow aspect should come
from trimming, not from the generation frame.

## After generating

1. **Key the background out** and check the alpha at 400% on the hair, cape
   edges and glove rims. A leftover magenta fringe is drawn three times.
2. **Trim to the alpha bounding box**, then resize so the file is **900 px
   tall**. `hero_stage.gd` quantises requested heights to 32 px steps and
   Lanczos-resamples from the source, so 900 is the working figure.
   ```
   magick in.png -trim +repage -resize x900 out.png
   ```
3. **Re-measure `_HEAD_REGION` in `scripts/ui/ui_style.gd`.** These are hardcoded
   square crops per sheet and they will be wrong for new art:
   ```gdscript
   const _HEAD_REGION := [
       Rect2i(43, 0, 230, 230),     # Herosauro  (282 x 900)
       Rect2i(19, 4, 190, 190),     # Super Boxy (209 x 900)
       Rect2i(136, 0, 360, 360),    # Adamastor  (631 x 900)
   ]
   ```
   Update the dimensions in the trailing comments too.
4. **Re-check Super Boxy's staging constants.** His aspect roughly doubles once
   he is a single figure, and width is derived from it:
   ```gdscript
   var w := h * aspect
   ```
   At `SUPERBOXY_SIZE = 0.545` and unit 720 he goes from ~91 px wide to ~188 px,
   so his silhouette reaches ~49 px further left toward the menu column. The
   column ends at x≈507 on a 1280-wide frame and his left edge lands near 570 —
   it still clears, but the margin drops from ~112 px to ~63 px. Run
   `scripts/ui/menu/_flow_probe.gd` across the aspect sweep afterwards and
   retune `SUPERBOXY_X` if it reads tight.
5. Run `scripts/ui/_ui_probe.gd`, which checks the portrait pipeline and asserts
   the results card swaps art correctly.
