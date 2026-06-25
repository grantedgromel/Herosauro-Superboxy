# Suno Soundtrack Prompts — *Herosauro & Super Boxy: Legends of Porto*

A ready-to-paste set of **short Suno prompts** for the game's music. The project
currently ships **no music** — every sound is procedural SFX synthesised at
startup by `autoloads/audio_manager.gd`. These prompts generate the missing
*soundtrack* layer (looping music beds + a couple of stingers) that sits on top
of that SFX.

Each cue is driven by an actual game state / signal, so the score follows the
fight: title → battle → enrage at 50% HP → win/lose.

---

## The world, in one breath (shared style DNA)

> Toon, cel-shaded co-op adventure. **Golden-hour over Porto**, on the Dom Luís
> bridge across the Douro. Two pint-sized heroes — **Herosauro** (a little dino,
> green energy) and **Super Boxy** (a boxer, dashing combos) — face **Adamastor,
> the giant stone golem of the Douro**, a mythic Titan out of Portuguese epic
> poetry who turns red and rages when wounded.

To make the five tracks feel like **one composed score** rather than five random
songs, reuse this palette and keep a common tonal centre of **D**:

- **Heroes' colour:** Fado-style **Portuguese guitarra** (bright 12-string
  tremolo), warm **nylon classical guitar**, pizzicato strings, playful
  woodwinds, punchy Saturday-morning **cartoon brass**.
- **Adamastor's colour:** deep **taiko + timpani**, gritty **low brass**,
  **wordless epic choir**, granite weight.
- **Mood:** heroic, warm, a little comedic — but the giant is genuinely epic.

---

## How to use these in Suno

1. **Turn `Instrumental` ON** for every cue (no vocals — choirs stay wordless).
2. Paste the **Style prompt** line into Suno's *Style of Music* box. It's kept
   short on purpose; tempo + key are baked in.
3. Set **Exclude styles** (all cues): `vocals, lyrics, spoken word, fade-out, lo-fi hiss`.
4. **Looping:** Suno likes to add intros/outros. Generate ~2 min, then trim a
   clean bar-aligned loop (or use *Extend* / the loop tools). The title, battle
   and pause cues must loop seamlessly; victory and defeat may keep a clean end.
5. **Export** each as `.ogg` (Godot's preferred streaming/looping format) into
   `assets/audio/music/` using the filename below, then enable **Loop** on the
   import for the looping cues.

---

## The cues

### 1 · Title — "Legends of Porto"  → `music/title_legends_of_porto.ogg`
- **Plays:** `State.MENU` (main menu / title screen). Loop.
- **Feel:** warm golden-hour fanfare that invites *press start*; states the
  heroes' theme.
- **~95 BPM · D major · 60–90 s loop**

> **Style prompt:** `Heroic golden-hour cartoon-adventure title theme, warm Portuguese guitarra tremolo and nylon guitar over soaring cinematic brass and strings, gentle taiko build, triumphant yet playful, instrumental, seamless loop, ~95 BPM, D major`

### 2 · Battle Phase 1 — "Defend the Bridge"  → `music/battle_phase1.ogg`
- **Plays:** `State.PLAYING`, boss phase 1. Loop. The core combat groove.
- **Feel:** driving, adventurous co-op fun; busy but not yet menacing.
- **~140 BPM · D dorian · seamless loop, no fade**

> **Style prompt:** `Fast heroic boss-battle music, driving taiko and live rock drums, staccato brass stabs, frantic Portuguese guitarra and pizzicato strings, adventurous cartoon energy, instrumental, looping no fade, ~140 BPM, D dorian`

### 3 · Battle Phase 2 — "Adamastor Unbound"  → `music/battle_phase2.ogg`
- **Plays:** on `boss_phase_changed(2)` — the giant hits 50% HP, turns red and
  attacks faster (double rock throws). Loop, replaces cue 2.
- **Feel:** same DNA as Phase 1 but darker, faster, relentless — the storm
  breaks.
- **~168 BPM · D minor · choir + distorted low brass**

> **Style prompt:** `Intense phase-two boss enrage, faster and darker than before, pounding double-time taiko, distorted low brass, wordless epic choir, shredding Portuguese guitarra, relentless and stormy, instrumental, looping, ~168 BPM, D minor`

### 4 · Victory — "Porto is Safe"  → `music/victory.ogg`
- **Plays:** `State.VICTORY` (under the in-game *"Porto is safe — the brothers
  triumph!"*). One-shot; clean ending.
- **Feel:** triumphant fanfare melting into a warm Portuguese-folk celebration.
- **~110 BPM · D major · clean ending**

> **Style prompt:** `Triumphant victory fanfare resolving into a warm celebratory Portuguese folk dance, bright brass, jubilant guitarra and hand percussion, sunset joy, instrumental, ~110 BPM, D major, clean ending`

### 5 · Defeat — "Adamastor Stands Unbroken"  → `music/defeat.ogg`
- **Plays:** `State.DEFEAT` (under *"Adamastor stands unbroken…"*). One-shot.
- **Feel:** somber Fado lament; the heroes have fallen, the giant looms.
- **~68 BPM · D minor · slow, gentle fade**

> **Style prompt:** `Somber defeat theme, lone mournful Fado-style Portuguese guitarra and nylon guitar, low strings and a distant wordless choir, heavy and tragic, slow, instrumental, ~68 BPM, D minor, gentle fade`

---

## Optional / supporting assets

### 6 · Pause — "Held Breath"  → `music/pause.ogg`  *(optional)*
- **Plays:** `State.PAUSED`. A soft suspended bed (or just low-pass/duck the
  battle track instead — your call).
- **~slow / rubato · sparse**

> **Style prompt:** `Soft suspended ambient pause music, sparse warm pads, distant nylon guitar harmonics, weightless and calm, instrumental, slow, looping, very quiet`

### 7 · Stinger — "He Turns Red"  → `music/sting_phase2.ogg`  *(optional, ~3 s, no loop)*
- **Plays:** as a one-shot the instant `boss_phase_changed(2)` fires, bridging
  cue 2 → cue 3 (pairs with the existing red flash + screen shake).

> **Style prompt:** `Short 3-second boss transformation stinger, sudden low brass and wordless choir swell crashing into a single taiko slam, ominous, instrumental, no loop`

---

## How these map to the code

The wiring lives in `autoloads/game_manager.gd` and would be played by
`autoloads/audio_manager.gd` (add an `AudioStreamPlayer` music channel + a
`play_music(track, loop)` helper):

| Signal / state | Cue |
|---|---|
| `state_changed(State.MENU)` | 1 · Title |
| `game_started` / `state_changed(State.PLAYING)` | 2 · Battle Phase 1 |
| `boss_phase_changed(2)` | 7 · Stinger → 3 · Battle Phase 2 |
| `state_changed(State.PAUSED)` | 6 · Pause (or duck cue 2/3) |
| `game_over(true)` → `State.VICTORY` | 4 · Victory |
| `game_over(false)` → `State.DEFEAT` | 5 · Defeat |

> Note: generating the audio and adding the music channel is a follow-up step —
> this file only delivers the prompts. Drop the rendered `.ogg`s into
> `assets/audio/music/` and they'll be ready to wire in.
