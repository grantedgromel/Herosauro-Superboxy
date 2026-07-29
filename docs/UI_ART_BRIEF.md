# UI & Brand Brief — what to source, where, and what to hand back

_Scope: fonts, the logo lockup, menu UI, character art as it appears in menus, and
cover/key art. **Not** gameplay, not the 3D models, not the HUD's behaviour._

This is the division of labour. Everything in **§3** is something a person has to
go and get — a licence bought, a font chosen, a drawing commissioned, a reference
found. Everything in **§4** is something the repo does with it once it arrives.

---

## 1. What is already here — do not buy these twice

| Thing | Current state | Where |
|---|---|---|
| Design system | Real and complete. Nine-step type scale, elevation model, warm palette, widget factories. | `scripts/ui/ui_style.gd` |
| Display font | **Bangers**, SIL OFL, free | `assets/fonts/Bangers.woff2` |
| UI font | **Fredoka** + **Fredoka-Bold**, SIL OFL, free | `assets/fonts/Fredoka*.woff2` |
| Logo | Type-set in Bangers: two stacked lines, gold gradient shader, specular sweep, tracked strapline | `scripts/ui/menu/title_logo.gd` |
| Character art | 3 alpha-keyed sheets, 900 px tall, cropped from concept art | `assets/ui/portraits/` |
| Menu backdrop | Live 3D Porto on a 74-second camera loop — **not** an image | `scripts/ui/menu/menu_world.gd` |
| Game icon | **Missing.** `project.godot` sets only `boot_splash/bg_color` | — |
| Cover / key art | **Missing entirely** | — |
| Favicon | Godot's default | — |

The menu backdrop being *live 3D* matters for what you commission: **do not buy a
painted menu background.** The background is the game. What sits on top of it is
what needs art.

---

## 2. What is actually wrong right now

Rendered from the current build. This is the honest read, so the brief you give a
designer is specific instead of "make it look better".

1. **The two heroes read as one blob.** Same height, same pose, same palette
   family, standing edge-to-edge with Boxy's cape occluding Herosauro. A player
   who has never seen the game cannot tell there are two characters, let alone
   which one they play. This is the single biggest hit to perceived polish.
2. **Herosauro does not read as a dinosaur.** He is a boy in green overalls with a
   small dino badge. The name promises a dino; the art does not deliver one.
3. **Adamastor is grey.** He reads as a statue rather than a sea-giant, and he sits
   *inside* the frame with clearance on the right — a giant that fits on screen
   is not a giant. `hero_stage.gd` intends him cropped; the art is too small to crop.
4. **The logo is a font, not a logo.** Bangers with a gradient is competent and
   instantly recognisable as Bangers — it is *the* default comic face, so it reads
   as a placeholder to anyone who has seen a game jam page.
5. **The strapline is weak.** "LEGENDS OF PORTO" is thin, small and letterspaced
   under a very heavy lockup. The hierarchy jumps from 92 px to 20 px with nothing
   between.
6. **Menu rows sit directly on the brightest part of the frame.** The sun-lit water
   is the highest-luminance region and START/DIFFICULTY/CONTROLS land right on it.
   They survive on outline alone.
7. **The difficulty row is near-invisible.** Unselected EASY and HARD are dark grey
   on a dark scrim.

Items 5–7 I can fix in code with no new assets. Items 1–4 need art.

---

## 3. What I need from you

Ordered by how much each improves the game per unit of effort. **Item A alone
changes more than everything else combined.**

### A. Character art — the two heroes, redrawn as a pair

The problem is not rendering quality, it is *casting*. Two characters that
silhouette identically will never look professional side by side.

**Brief to give the artist:**
- Two heroes, **readable as different species and different silhouettes at 200 px
  tall in greyscale**. That is the test — if you squint and they merge, it failed.
- **Herosauro**: actually saurian. Snout, tail, or crest — something that breaks
  the human outline. Currently green/`#57c25c`.
- **Super Boxy**: the boxer. Red, gloves, cape. Currently `#ef5a52`.
- Both in **three-quarter view facing screen-right** (they must look toward
  Adamastor, who is staged on the right).
- **Adamastor**: taller and wider than the frame can hold. Deliver him at least
  **2400 px tall** so `hero_stage.gd` can crop him at the frame edge and still have
  resolution. Give him colour — weathered granite with sea-green or storm-blue in
  the shadows, not neutral grey.

**Deliver:** PNG with **transparent background**, one file per character, **no
drop shadow baked in** (the stage adds its own shadow, rim light and parallax —
a baked shadow will double up). Minimum 900 px tall for the heroes, 2400 px for
Adamastor. Higher is better; I downsample with Lanczos.

**Where to get it made:**
| Route | Site | Note |
|---|---|---|
| Commission | [dribbble.com](https://dribbble.com), [behance.net](https://behance.net) | Search "game character sheet", DM directly. Best quality, slowest. |
| Commission, cheaper | [fiverr.com](https://fiverr.com), [upwork.com](https://upwork.com) | Filter for "2D game character". Ask for the *character sheet* deliverable. |
| Artist boards | [r/HungryArtists](https://reddit.com/r/HungryArtists), [artstation.com](https://artstation.com) | |
| AI-assisted | [midjourney.com](https://midjourney.com), [ideogram.ai](https://ideogram.ai) | Fast and cheap; consistency across three characters is the hard part. Check the commercial-use terms of whichever you use. |

### B. Fonts — one display face, one UI face

Bangers and Fredoka are both fine typefaces and both completely free. They are
also both *extremely* common. Replacing them is the cheapest professionalism win
available.

**What to look for:**
- **Display face** (logo, VICTORY/DEFEAT, combo splash): heavy, characterful,
  ideally with real ink or brush quality. It only ever sets short all-caps
  strings, so it can be as opinionated as you like.
- **UI face** (menu rows, score, timer, health, all prose): must have a **true
  bold** and, critically, **tabular figures** — the score and timer change every
  frame and proportional digits make them jitter. Neutral, not characterful.

**Licence requirement — this one is non-negotiable.** The font is embedded in the
game binary and in the web build. You need a licence that permits **application /
game embedding** *and* **webfont** use. Many desktop licences forbid both.
- **SIL OFL** — always safe, no cost, no limits. Every Google Fonts entry.
- **Adobe Fonts** — ⚠️ does *not* generally permit embedding in an application.
  Do not pick from there for this.
- Paid foundries — look for an explicit "app/game embedding" or "digital ambient"
  tier and expect it to cost more than the desktop licence.

| Site | Cost | Note |
|---|---|---|
| [fonts.google.com](https://fonts.google.com) | Free (OFL) | Where Bangers and Fredoka came from. Still has good less-used faces. |
| [fontshare.com](https://fontshare.com) | Free, commercial-OK | Indian Type Foundry. Genuinely professional quality — best free-to-paid ratio on this list. |
| [velvetyne.fr](https://velvetyne.fr) | Free (libre) | Experimental, distinctive, French. Great for a display face with personality. |
| [collletttttivo.it](https://collletttttivo.it) | Free (libre) | Italian libre foundry, similar spirit. |
| [theleagueofmoveabletype.com](https://theleagueofmoveabletype.com) | Free (OFL) | Small, solid, open-source. |
| [futurefonts.xyz](https://futurefonts.xyz) | Cheap (early access) | Buy fonts mid-development at a fraction of release price. Excellent for distinctive display faces. |
| [pangrampangram.com](https://pangrampangram.com) | Paid | Modern, very well made. |
| [fontspring.com](https://fontspring.com) / [myfonts.com](https://myfonts.com) | Paid | Huge catalogues; read the embedding terms carefully. |

**Deliver:** the **`.ttf` or `.otf`** files — not a webfont link, not a CSS
`@import`. I convert to `.woff2` and wire the type scale. Also send me **the
licence file or a link to the exact licence tier you bought**, so it can go in
`docs/` and the credits screen.

### C. The logo lockup

**Brief:** the words `HEROSAURO & SUPER BOXY` over `LEGENDS OF PORTO`. It has to
survive being laid over a **blown-out golden-hour sky** — so it needs weight, a
dark edge, and no fine detail that disappears at small sizes. It is currently
laid out left-aligned in two stacked lines; a designer may propose better, and
the layout code can follow.

Worth asking for: a **mark** as well as the wordmark — something small and
square that works as the game icon, the favicon, and the Steam small capsule.
A dino silhouette in a boxing glove, say.

**Deliver, in order of preference:**
1. **SVG** — infinitely scalable, and I can recolour it in engine.
2. PNG at **4096 px wide**, transparent, no baked shadow.
3. Both, plus a **one-colour version** (solid white on transparent) for the
   places it has to sit on a busy background.

**Where:** same commission routes as §A. For AI-assisted logo work specifically,
[ideogram.ai](https://ideogram.ai) is markedly better at legible lettering than
most, and [recraft.ai](https://recraft.ai) can output actual vector/SVG.

### D. Cover / key art

Even if you never ship on Steam, **use Steam's capsule sizes** — they are the de
facto standard and cover every other use (itch.io, press, social, the web build's
share card). Official spec:
[partner.steamgames.com/doc/store/assets/standard](https://partner.steamgames.com/doc/store/assets/standard)

| Asset | Size | Used for |
|---|---|---|
| Main capsule | 1232 × 706 | Store front page, itch.io cover |
| Header capsule | 920 × 430 | The one everyone sees |
| Small capsule | 462 × 174 | Search results — **logo must be legible this small** |
| Vertical capsule | 748 × 896 | Seasonal / featured |
| Library hero | 3840 × 1240 | Full-bleed banner |
| Page background | 1438 × 810 | |

**One composition, exported at each size** is fine to start — the small capsule
is the one that usually needs a separate crop.

**Deliver:** PNG or high-quality JPG. Put these in a **`press/` folder at the repo
root**, *not* inside `herosauro-superboxy/` — anything inside the Godot project
gets packed into the 16 MB web build whether the game uses it or not.

### E. Game icon

**Deliver:** one **1024 × 1024 PNG**, transparent or solid, that reads at 32 px.
I generate every other size and the favicon from it.

### F. Inspiration — the cheapest thing you can send me

Just links or screenshots, with a word on what you like about each. This is worth
more than a written description of a style.

| Site | Why |
|---|---|
| [gameuidatabase.com](https://gameuidatabase.com) | **Start here.** Thousands of real game screens, filterable by screen type — filter to "Main Menu" and browse. Purpose-built for exactly this. |
| [interfaceingame.com](https://interfaceingame.com) | Same idea, better curated, screenshots and video. |
| [dribbble.com](https://dribbble.com) / [behance.net](https://behance.net) | Logo and key-art direction. |
| [store.steampowered.com](https://store.steampowered.com) | Browse capsules in the wild — see what survives at thumbnail size. |
| [itch.io](https://itch.io) | Closer to this game's scale than Steam's front page. |

Games worth looking at for this specific problem — hand-drawn cartoon cast, warm
palette, strong logo: **Cuphead**, **Sea of Stars**, **Hades**, **Untitled Goose
Game**, **Pizza Tower**.

---

## 4. What I do once each arrives

| You send | I do |
|---|---|
| `.ttf`/`.otf` fonts | Convert to `.woff2`, swap `TITLE_FONT`/`UI_FONT`/`UI_BOLD` in `ui_style.gd`, re-tune the nine-step scale (a new face will not sit at the same sizes), re-verify contrast against `_ui_probe.gd`, screenshot before/after. |
| Character PNGs | Drop into `assets/ui/portraits/`, re-measure the alpha bounds, update `_HEAD_REGION` in `ui_style.gd` (the head crops are hardcoded pixel rects), re-tune the stage composition in `hero_stage.gd`, screenshot. |
| Logo SVG/PNG | Replace the type-set lockup in `title_logo.gd` with the real mark, keeping the drop shadow, the gradient and the specular sweep — or removing them if the art already carries that weight. |
| Icon PNG | Generate all sizes, set `config/icon` in `project.godot`, wire the web export's favicon and apple-touch-icon. |
| Cover art | `press/` folder, plus the web build's Open Graph tags so a shared link shows the cover. |
| Inspiration links | Translate them into the palette, spacing and motion changes I can make without any new assets. |

And regardless of any of the above, I can already fix items **5, 6 and 7** from
§2 — strapline hierarchy, menu-row contrast over the bright water, and the
difficulty row — in code today.

---

## 5. How to hand things over

Either works:

1. **Commit them.** Put files in the paths named above, push, tell me the branch.
2. **Attach them in chat.** I will place, convert and wire them.

For fonts, **send the licence too** — it goes in `docs/` and the credits screen.

One thing to decide early, because it changes what you commission: **is this
shipping commercially?** If yes, AI-generated character art and logos carry real
licensing ambiguity, and the font licence tier changes. If it is a personal or
portfolio project, that pressure mostly disappears.
