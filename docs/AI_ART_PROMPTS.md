# AI art prompts — copy and paste

Companion to `UI_ART_BRIEF.md`. Every prompt below is written to be pasted whole.

**The palette, used throughout.** These are the real values from `ui_style.gd`, so
what comes back matches what is already on screen:

| | Hex |
|---|---|
| Herosauro green | `#57C25C` |
| Super Boxy red | `#EF5A52` |
| Adamastor amber / rage | `#D98A3A` / `#E0392F` |
| Gold, deep gold, ember | `#FFC64D`, `#EF8F2C`, `#FF7A3C` |
| Cream (text) | `#FBF1DF` |
| Ink (darkest) | `#100C18` |

**One rule that applies to every character prompt: ask for a flat `#FF00FF`
magenta background.** No generator cuts transparency reliably. Magenta appears
nowhere in these three characters, so I can key it out cleanly. Green would
destroy Herosauro; white would eat the cream highlights.

---

## A. Character art

Attach the existing sheet as a reference image with each prompt. Generate the
three **separately** — asking for all three in one image gives you three figures
you cannot move independently, which is exactly what the stage needs to do.

### A1 · Herosauro

> Full-body character sheet of a small cartoon dinosaur superhero boy, standing
> in a confident three-quarter view facing to the RIGHT of frame. He is a young
> anthropomorphic green dinosaur — visible snout, a row of soft back ridges, and
> a thick tapering tail that curves out behind him — wearing blue denim dungarees
> over a green long-sleeve shirt, a small red domino mask, and red sneakers.
> Friendly, brave, about eight years old in proportion: large head, small body.
> Skin and scales in warm green `#57C25C` with darker green shadow.
> Hand-drawn 2D cartoon illustration, thick confident black outlines of even
> weight, flat cel shading with two tones plus a warm rim light, no gradients, no
> texture, no crosshatching. Children's comic book style.
> Full body, head to feet, nothing cropped. Standing straight, weight on both
> feet, arms relaxed and clear of the torso silhouette.
> Flat solid magenta `#FF00FF` background, absolutely uniform, no shadow cast on
> it, no ground plane, no vignette, no border.

**The test to hold it to:** desaturate it and shrink it to 200 px. If it does not
instantly read as a *dinosaur* rather than a boy in costume, regenerate. The
snout and the tail are what carry that — insist on both.

### A2 · Super Boxy

> Full-body character sheet of a cartoon boxer superhero boy, standing in a
> dynamic three-quarter view facing to the RIGHT of frame, one oversized red
> boxing glove raised in a guard. Human boy, about eight years old in proportion,
> brown hair, red domino mask, a red hero cape flowing behind him, a white
> chest emblem, and enormous red boxing gloves that dominate his silhouette.
> Stocky and compact — visibly broader and shorter than a slim character.
> Reds in `#EF5A52`, cape a deeper red, cream `#FBF1DF` for the emblem.
> Hand-drawn 2D cartoon illustration, thick confident black outlines of even
> weight, flat cel shading with two tones plus a warm rim light, no gradients, no
> texture. Children's comic book style.
> Full body, head to feet, nothing cropped. The raised glove and the cape must
> read as distinct shapes against the body, not merge into it.
> Flat solid magenta `#FF00FF` background, absolutely uniform, no shadow cast on
> it, no ground plane, no vignette, no border.

**The test:** put A1 and A2 side by side, greyscale, 200 px tall. Different
height, different width, different silhouette — a tail on one, a cape and huge
gloves on the other. If they still merge, push A2 shorter and wider.

### A3 · Adamastor

> Full-body illustration of Adamastor, the colossal storm giant from Portuguese
> myth — the titan of Camões' Lusíadas, the spirit of the Cape of Storms.
> A vast, muscular, ancient giant with a long wild beard and streaming hair like
> sea-foam and storm cloud, bare-chested, wearing a ragged dark wrap at the waist
> and heavy weathered bronze cuffs. Furious, looming, monumental.
> His skin is weathered granite shot through with storm-blue and deep sea-green
> in the shadows, warm amber `#D98A3A` catching his edges where the low sun hits,
> and his eyes burn ember orange `#FF7A3C`. NOT neutral grey — he must read as a
> living creature of sea and stone, not a statue.
> Standing three-quarter view facing to the LEFT of frame, one arm reaching
> forward, shoulders hunched with menace.
> Hand-drawn 2D cartoon illustration matching a children's comic book, thick
> confident black outlines, flat cel shading with two tones plus a strong rim
> light, no gradients, no photographic texture.
> Full body, head to feet, nothing cropped, standing tall and filling the frame
> vertically.
> Flat solid magenta `#FF00FF` background, absolutely uniform, no shadow cast on
> it, no ground plane, no vignette, no border.

**Generate this one as tall as your tool allows** — 2:3 or 3:4 portrait, upscaled.
He gets cropped by the frame edge in the menu, so he needs resolution to spare.
`--ar 3:4` on Midjourney.

### What to send me

The raw generations, magenta background and all. I key the magenta, trim to the
alpha bounds, re-measure the head-crop rectangles in `ui_style.gd`, and re-tune
the stage composition. **Do not cut them out yourself** and do not add a drop
shadow — `hero_stage.gd` composites its own shadow, rim light and parallax, and a
baked-in one will double.

---

## C. Logo

Use **[ideogram.ai](https://ideogram.ai)** for this. It is markedly better at
legible lettering than Midjourney, which will confidently misspell a wordmark.
[recraft.ai](https://recraft.ai) can output real SVG if you want it vector.

> A video game logo wordmark reading exactly "HEROSAURO & SUPER BOXY" on two
> stacked lines, with a smaller subtitle beneath reading exactly "LEGENDS OF
> PORTO". Bold hand-drawn comic book lettering, chunky rounded capitals with
> slightly irregular hand-inked edges, heavy black outline and a subtle drop
> shadow so it stays legible over a bright sky. Warm gold `#FFC64D` letterforms
> shading to deep amber `#EF8F2C` at the baseline. Playful, adventurous, made for
> a children's action game.
> Integrated into the lettering: a small dinosaur silhouette and a red boxing
> glove, worked into the letterforms as part of the mark rather than placed
> beside them. A thin gold rule separates the title from the subtitle.
> Centred, flat solid black background, no other elements, no characters, no
> scenery, no border, high resolution.

Then a **second, separate** generation for the square mark — this is the one that
becomes the icon and the small capsule:

> A simple bold app icon: a cartoon dinosaur head in profile wearing a red boxing
> glove, or a dinosaur silhouette inside a red boxing glove. Thick black outlines,
> flat colour, warm green `#57C25C` and red `#EF5A52` on a warm gold `#FFC64D`
> background. Extremely simple and readable at very small sizes — no fine detail,
> no gradients, no text. Centred, square composition, vector sticker style.

**Watch for:** the ampersand and the double-word title are where generators break.
Generate a batch, pick the one where every letter is right, and expect to pay a
human to redraw it if you want it truly clean. `--ar 16:9` for the wordmark,
`--ar 1:1` for the mark.

---

## D. Cover / key art

One composition; I derive every capsule size from it. Generate at **16:9** and
leave headroom — the vertical capsule needs a taller crop out of the same scene.

> Video game key art. A small green cartoon dinosaur superhero boy in denim
> dungarees and a red mask, and a stocky cartoon boy boxer in a red cape with
> enormous red boxing gloves, stand together in the foreground on the iron deck
> of the Dom Luís I bridge in Porto, Portugal — small, brave, backs to us,
> looking up. Towering over them and filling the upper right of the frame, a
> colossal ancient storm giant with a wild sea-foam beard and burning ember eyes
> rises out of the Douro river, one huge fist drawn back.
> Behind them the Ribeira: stacked pastel houses in terracotta, ochre and faded
> blue climbing the gorge, the river blazing with the reflection of a low golden
> sun, port wine boats on the water.
> Dramatic golden-hour backlight, warm gold `#FFC64D` and ember `#FF7A3C` rim
> light on every figure, deep plum `#100C18` shadows.
> Hand-drawn 2D cartoon illustration, thick confident outlines, rich cel shading,
> children's adventure comic book cover style. Epic scale contrast between the
> tiny heroes and the giant. Cinematic composition.
> No text, no logo, no watermark, no UI, no border.

**"No text"** is deliberate — the logo gets composited on top afterwards, at the
right size for each capsule. Art with baked-in text cannot be re-cropped.

Keep the lower-left third relatively quiet: that is where the logo lands on the
Steam header and the itch.io cover.

---

## E. Icon

Use the square mark from **§C**. Send it at **1024 × 1024** and I generate every
other size, the favicon, and the apple-touch-icon.

---

## F. What to take from Absolum — and what not to

Absolum's title screen is a very good reference and it is *already* the same
skeleton as yours: logo top-left, menu down the left margin, cast filling the
right. The differences are all in discipline, and five of the six are free.

| | Absolum does | You do | Worth taking |
|---|---|---|---|
| 1 | Menu sits on **near-black** | Menu sits on the **brightest part of the frame** (sunlit water) | **Yes — biggest win** |
| 2 | Selected item is **white, larger, with a red diamond** | Selected item is same size, gold left bar | **Yes** |
| 3 | ~100 px between menu items | ~58 px | **Yes** |
| 4 | Cast **overlaps, cropped by two edges**, staggered in depth | Cast in a row, all fully visible, clearance on the right | **Yes** — needs the new art |
| 5 | Button prompt bottom-right, version bottom-left | Key hints bottom-left only | **Yes** |
| 6 | Palette: black, crimson, cream — three colours | Warm golden-hour Porto | **No** |

**Row 1 is the whole thing.** Absolum's menu is legible because it sits on black.
Yours sits on a blown-out sun reflection and survives on outline alone. The fix
is not to darken the game — it is to put a much stronger, wider gradient scrim
under the left column so the text has its own dark field, while the right two
thirds of Porto stay bright and warm. That keeps golden hour *and* buys the
contrast.

**Row 6 is the trap.** Copying the black-and-crimson palette would give you a
readable menu and throw away the game's identity. Absolum is dark fantasy; this
is a warm children's comic set at sunset. Take the *structure* and the *contrast
discipline*, keep the colour.

Rows 1, 2, 3 and 5 need no new assets. I can do them now.
