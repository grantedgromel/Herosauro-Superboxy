# Adamastor's Henchmen — Lore & Encounter Design

_Chapter: the Dom Luís I bridge. Companion to `IMPLEMENTATION_PLAN.md` (Phase 1, "make the
boss fight great"). Design intent, not an implementation spec — it decides **what** fights
you and **why it is that thing**, so the encounter work has a fixed target._

**Audience: children.** The hero is a small boy in a red mask, a cape and velcro sneakers,
and `adamastor.gd` already says the giant towers "~5x over the human kids". Every choice
below is made for a player who is roughly the age of the character they are holding.

---

## 0. The good news

Camões's Adamastor is *already* a children's story. Strip Canto V to what a seven-year-old
can hold and you get: **a big lonely giant who got laughed at, turned to stone, and now
scares everybody away from his water.**

That is not a softening. It is what stanzas 52–60 literally say — he loved someone, he was
tricked, he was humiliated, he hardened, and now he frightens off anyone who comes near.
The terrifying-sea-demon reading is one interpretation; the sulking-giant reading is the
other, it is equally faithful, and it is the one that fits a kid in a dinosaur costume.

**And it solves the henchmen problem.** A lonely sulk does not have an army. He has:

| Family | Source | What it is |
|---|---|---|
| **Stone** | "Em penedos os ossos se fizeram" (st. 59) | What he is made of. Bits of him keep breaking off and getting up. |
| **Storm** | "Eu sou aquele oculto e grande Cabo / A quem chamais vós outros Tormentório" (st. 50) | **His moods.** He is the Cape of Storms, so the weather is his temper — and a kid can read his mood in the sky. |
| **The Lost-and-Found** | His shipwreck prophecies, st. 44–48 | Everything the river ever swallowed. He has kept all of it. |

Three families. Three silhouettes, three counters, one joke each.

---

## 1. What the first draft got wrong

An earlier version of this document built the third family out of the **drowned** — the
Ponte das Barcas disaster of 1809, when the pontoon bridge at this exact crossing gave way
under a fleeing crowd and thousands died, memorialised by the *Alminhas da Ponte* relief
still set into the Ribeira quay wall.

It is extraordinary lore and it is **cut**, entirely, with no softened version kept. Real
dead people, a real memorial a hundred metres from the arena, as enemies a child punches:
there is no framing that makes that land. Also cut for the same reason: the drowned ship
firing bombards, and any reading of the Tétis episode as a story about a spurned lover.

Nothing else is lost. Everything in this chapter that is made of **stone** or **weather**
gets *better* in cartoon, not worse.

---

## 2. STONE — bits of him

### 2.1 Penedos (chaff) — **build this one first**

Grumpy granite lumps the size of a football, with faces. They **hatch out of the rocks he
already throws.**

- **Lore:** his bones became *penedos*. Every rock he throws is a piece of him, so of course
  it gets up and grumbles.
- **Mechanics:** reuse `scenes/fx/rock_projectile.tscn`. On impact the rock uncurls instead
  of despawning. **One hit and it pops back into rubble** — `debris_piece.gd` already exists
  to make that satisfying.
- **Why first:** `ROCK_THROW` is currently the boss's most ignorable attack — sidestep it
  and it may as well not have happened. With penedos, ignoring rocks costs you the deck.
  One change, an existing FSM state gains a whole pressure curve, and it needs no new art
  beyond a rock with eyebrows.
- **Kid tuning:** they should be *funny*. Blink. Grumble. Bump into each other. Trip over
  the tram rail. Cap them at 8 live — this is chaff to pop, not an attrition puzzle.

### 2.2 Os Três Irmãos — the three brothers (elite)

Three big, slow, stone brothers who plant themselves and block the deck.

- **Lore:** Camões names Adamastor's actual siblings at st. 51 — **Encélado, Egeu** and
  **o Centimano**. Not invented; quoted.
- **Kid design:** heavy furniture, not menace. They cannot chase — they lumber into place,
  fold their arms and refuse to move. Beating one is beating a *bouncer*, not killing a
  monster. Three distinct colours and three distinct silhouettes so a child can tell them
  apart and pick favourites.
- **Mechanics:** zoning. Break the folded-arms guard with Dino Energy — which finally gives
  that ability a job besides boss chip damage.

### 2.3 The bridge's own stones (obstacle)

Kerbstones that rear up in your path. Balusters that lean in. A deck bay that stands on end.

- **Lore:** petrification is the thing that was done to him, so it is the thing he does.
- **Why it is cheap here:** `bridge_arena.gd` already builds kerbs, flags, balusters and
  deck bays procedurally on fixed pitches (`BAY_PITCH`, `BALUSTER_PITCH`, `POST_PITCH`).
  Those courses are already addressable — animating individual ones is far less work in
  this project than in a hand-modelled level.
- **The Grumpy Grey:** a slow crust of stone spreading out from wherever he lands. Standing
  in it **slows** you and drains colour from the world. It never roots you (see §5). Best
  pure obstacle in the chapter: it shrinks that flat 100 m corridor with no new geometry.

---

## 3. STORM — his moods

The key kid-facing move: **the weather is not an effect, it is how he feels**, and the sky
is the boss's health bar. Grey and blustery when he is grumpy; black and howling when he is
furious. A child who cannot read a HUD can read a sky.

- **Nortada** — Porto's real Atlantic northerly, blowing straight down the deck. Pushes you,
  never hurts you. One vector, and it re-tunes every other fight in the chapter.
- **Gaivotas** — Douro seagulls, and they **steal**. Real Porto behaviour, genuinely funny,
  and the best comedy loop available: a gull grabs your collectible and flaps off, you chase
  it, one bonk and it drops the thing and sulks off. Low stakes, high slapstick. They also
  fix the fact that nothing in the game currently makes the player look up — which is a
  waste of a nine-metre boss.
- **Tromba de água** — a wobbly waterspout that walks a telegraphed line down the deck and
  **launches** everything, barrels included. Being flung is fun; being damaged is not, so it
  should do the first and not the second. `Hitbox` already carries `lift` and `prop_impulse`.
- **Fogo de Santelmo** — blue sparkles crawling the iron railings. Canto V st. 18, the fire
  sailors "têm por santo". As a rule for a child: *don't touch the buzzy rail.* Colour-coded,
  no reading required, and it squeezes the arena inward without moving a single wall.

---

## 4. PERDIDOS E ACHADOS — the Lost-and-Found

The third family, replacing the drowned. Same job in the myth — Adamastor keeps what the
water takes — with none of the problem.

**Everything the Douro ever swallowed, and he has kept all of it.** Anchors, kettles,
bicycles, front-door keys, a piano, about nine hundred footballs. Crusted in barnacles and
river-weed, and all of it walking.

- **Lore:** his prophecies are a list of things the sea took off the Portuguese. Turning that
  from a body count into a *lost property office* keeps the idea exactly and loses nothing —
  he is still the thing that takes what you cannot get back.
- **Barcos rabelos** — the flat-bottomed port-wine boats, moored under this bridge in real
  life, clanking around on land like beetles. Retroactively explains why `wine_barrel.tscn`
  is scattered all over the deck.
- **A Âncora (elite)** — a big rusted anchor on a chain that he swings in a wide, slow,
  heavily telegraphed sweep. You jump it. Every child already knows how to play this.
- **The payoff, for free:** somewhere in the hoard is something that belongs to the heroes.
  Collectibles, a reason to explore the chapter, and the emotional beat all fall out of one
  design decision.

---

## 5. The lieutenant — Dona Tétis, who is a rock

A chapter wants a named rival before the boss. The text hands you a perfect one and it is
not a monster.

Stanzas 55–56: Adamastor chased a shape through the dark, seized it, and found he was
holding **"um duro monte"** — a bare boulder. In this version, **the boulder never corrected
him.** She has been his best friend for five hundred years. She is absolutely, sincerely
certain that she is a beautiful sea-nymph. She is a rock with seaweed hair, and she will
fight you because she loves him and you are upsetting him.

- **Why she works for kids:** funny and sad at once, needs no romance to explain, and is a
  direct quotation of the stanza. It is a lonely giant and his imaginary friend.
- **Verb: deception, not damage.** She conjures a false safe patch, a false path over a
  broken bay, a false voice calling you the wrong way. She is not lying — she believes all
  of it, because she believes she is a nymph.
- **The counter a six-year-old can hold:** *everything she makes is grey.* Look for the
  thing with no colour. One rule, no text, works the first time.

---

## 6. Rules this chapter is built on

Non-negotiables for this audience. Everything above already obeys them.

1. **Never take control away.** No grabs, no stuns, no roots, no "you cannot move for 1.2 s".
   Push, slow, launch, blow sideways — all fine, all still fun. This is the single biggest
   frustration source for young players and it is why the drowned-souls *grab* is gone twice
   over.
2. **One-hit chaff.** Popping things is the whole job. Penedos and gulls die instantly.
3. **Nothing dies — everything stops.** And this is free, because everything is stone or
   weather: penedos go back to being rocks, the brothers sit down and fold their arms, gulls
   flap off in a huff, the waterspout falls in the river. **Including the boss** — Adamastor
   settles back into being a cliff, which is not a workaround, it is the most lore-accurate
   ending available. He *is* the Cape. `adamastor_corpse.gd`'s topple already does it; only
   the reading changes.
4. **No enemy can defeat you alone.** Chaff chips, the boss closes. A child should only ever
   lose to Adamastor himself.
5. **Longer telegraphs.** `WINDUP` is 0.55 s (0.4 in phase two). That is tuned for an adult.
   For this audience, lengthen phase one and add a **colour** cue, not just a pose — the
   phase-2 red tint in `_on_phase_changed` shows the machinery is already there.
6. **No fall deaths.** The parapets already handle it. Falling to the lower deck (§7) is a
   scripted spectacle, never a fail state.

---

## 7. Chapter shape

`bridge_ironwork.gd` already models **the real lower road deck, 14 m below the playable
one**, as meshes with no colliders. There is a second arena sitting unused in this project
right now.

| Beat | Space | Content |
|---|---|---|
| 1 — The quay | Ribeira / lower deck | First penedos. Gulls steal something. Teaches pop-and-chase. |
| 2 — The climb | Arch lattice | Vertical traversal. Buzzy railings, wind, no ground fighting. |
| 3 — The friend | Upper deck | Dona Tétis. Os Três Irmãos hold the far end. |
| 4 — The giant | Upper deck | Adamastor as built today. |
| 5 — The drop | Deck gives way | His slam breaks a bay and the fight falls to the lower deck. |

Beat 5 is the argument for the whole structure. Phase two is currently a speed buff and a
red tint; it could be **the bridge breaking**, and the geometry to land on is already
modelled.

---

## 8. If only one thing gets built

**Penedos, gulls, Dona Tétis.** Three units, three verbs — *pop*, *chase*, *look* — one
joke each, and all three are quotations. Penedos alone would earn their cost.

---

## 9. Sources

- Luís de Camões, *Os Lusíadas*, Canto V: st. 18 (St Elmo's fire), st. 37–60 (the Adamastor
  episode — brothers st. 51, the boulder st. 55–56, petrification st. 59, the prophecies
  st. 44–48).
- Ponte de Dom Luís I (Téophile Seyrig, 1886) — double-deck wrought-iron crescent arch;
  upper deck metro and footways, lower deck road.
- Porto: the *nortada*, the Douro gulls, the *barcos rabelos* moored at Gaia.
- **Deliberately excluded:** the Ponte das Barcas disaster (1809) and the *Alminhas da Ponte*
  memorial. Recorded here so the decision is not quietly re-made later — see §1.
