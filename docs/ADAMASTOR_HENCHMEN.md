# Adamastor's Henchmen — Lore & Encounter Design

_Chapter: the Dom Luís I bridge. Companion to `IMPLEMENTATION_PLAN.md` (Phase 1, "make the
boss fight great"). This document is design intent, not an implementation spec — it decides
**what** fights you and **why it is that thing**, so the encounter work has a fixed target._

---

## 0. The constraint that shapes everything

**Adamastor has no army.** In Camões he is a solitary Titan — one of "os filhos aspérrimos
da Terra", the Earth-born who warred on the gods — who took the sea as his province, was
humiliated by a trick, and was petrified into the Cape of Storms. He commands no soldiers.
He was not even given a monster's death; he was given a geography.

So a roster of "Adamastor's guys" is lore-false on its face. What is lore-true is that he
has exactly three things, and all three are named in Canto V:

| Family | Source | What it is |
|---|---|---|
| **Stone** | "Converte-se-me a carne em terra dura; / Em penedos os ossos se fizeram" (st. 59) | His own body. He is made of rock and everything he touches becomes rock. |
| **Storm** | "Eu sou aquele oculto e grande Cabo / A quem chamais vós outros Tormentório" (st. 50) | He *is* the Cape of Storms. Weather is his weapon, and it is the one that actually sinks fleets. |
| **The Drowned** | His prophecies over Bartolomeu Dias, D. Francisco de Almeida, Sepúlveda and D. Leonor (st. 44–48) | Everyone he has taken. He recites them by name — they are his trophies, and he keeps them. |

**Stone / Storm / Drowned.** That triad is the whole roster. Nothing in the chapter should
be a creature that merely happens to work for a giant; every enemy must be a piece of him,
a piece of his weather, or a piece of his body count. That is also a strong *readability*
rule for the player: three silhouettes, three counters, learnable in one playthrough.

---

## 1. STONE — the body

He is granite. Porto is granite. The bridge is granite and iron. This family is the one
that connects the myth to the arena without a single line of exposition.

### 1.1 Penedos (chaff) — **highest-value unit in the document**

Knee-high granite lumps that **hatch out of the rocks he already throws.**

- **Lore:** his bones became *penedos*. Any fragment of Adamastor is a fragment of a living
  Titan; a rock that lands and does not die is the most economical statement of what he is.
- **Mechanics:** reuse `scenes/fx/rock_projectile.tscn` wholesale. On impact, instead of
  despawning, the rock uncurls. Low HP, dies to one basic attack, dies in bunches to
  Dino Energy.
- **Why it is the best unit here:** it makes `ROCK_THROW` — currently the boss's *weakest*
  and most ignorable attack — into a generative threat. Right now the correct answer to a
  rock is to sidestep and forget it. With penedos, ignoring rocks costs you the arena. One
  change, and an existing FSM state gains a whole new pressure curve for free.
- **Tuning note:** cap live penedos hard (8–10). This is a chaff unit, not an attrition
  puzzle, and every one is a live body under Jolt.

### 1.2 Filhos da Terra (elite)

Half-formed giants — a torso and arms dragging itself over the parapet from the riverbed,
no legs, three metres of it.

- **Lore:** Camões names Adamastor's brothers directly — **Encélado, Egeu, o Centimano**
  (st. 51). These are not his minions, they are his *siblings*, and the right reading is
  that he is calling up unfinished ones: things the Earth started and never completed.
- **Mechanics:** slow, cannot chase, armoured front. It is a **zoning** enemy — it owns a
  piece of deck and you have to fight around it. Break the armour with the special
  (`dino_energy`), which finally gives that ability a job other than boss chip damage.
- **Naming:** if you want one named elite for the chapter, **Briareu** (the Hundred-handed)
  is the pick — an arm-wall that closes off half the carriageway.

### 1.3 The bridge itself (obstacle, not enemy)

Kerb blocks that rear up. Balusters that pull out of the parapet and swing. A bay of
deck plate that stands vertical to block the lane.

- **Lore:** petrification is his signature trauma and his signature power — what was done
  to him, he does to everything.
- **Mechanics:** `bridge_arena.gd` already builds the parapet, kerbs and deck bays
  procedurally from constants on a fixed pitch (`BAY_PITCH`, `BALUSTER_PITCH`,
  `POST_PITCH`). Those courses are *already addressable*. Animating individual bays is
  much cheaper here than in a hand-modelled level.
- **Creeping petrification:** a stone crust spreading outward from where he lands. Standing
  in it slows you, then roots you. Best pure-obstacle idea in the chapter — it converts the
  flat, featureless corridor into a shrinking one without any new geometry.

---

## 2. STORM — the weather

He is the Cape of Storms; the storm is what actually kills sailors. This family supplies
**pressure and movement**, not bodies. Every unit here changes where you can stand.

### 2.1 Nortada (environmental)

A hard directional wind down the deck.

- **Lore:** the *nortada* is Porto's real prevailing summer northerly off the Atlantic.
  Free authenticity, zero fantasy budget.
- **Mechanics:** no damage, no HP — a lateral force added to player velocity, telegraphed
  by the lamppost glow and spray direction. It re-tunes every other fight in the chapter
  for the cost of one vector.

### 2.2 Tromba de água — waterspout (elite hazard)

A walking column of river water that tracks a telegraphed line down the carriageway and
launches everything it touches.

- **Lore:** Camões describes a waterspout at length **in the same canto** (st. 19–22),
  drawing the sea up "em cano subtil". It is not borrowed from elsewhere — it is Gama's
  own voyage.
- **Mechanics:** moving area denial. `Hitbox` already carries `lift` and `prop_impulse`,
  so a spout that hurls the deck's barrels and crates is nearly free.

### 2.3 Fogo de Santelmo — St Elmo's fire (area denial)

A blue-white glow that crawls the iron lattice and electrifies the railings.

- **Lore:** Canto V st. 18 — the living fire "que a marítima gente / Tem por santo". Sailors
  revered it; here he perverts it.
- **Mechanics:** the parapet becomes a no-touch surface for a window. On a 14 m-wide deck
  bounded by iron on both sides, that squeezes the corridor to the tram bed — the arena
  narrows without a single wall moving.
- **Bonus:** the bridge is an Eiffel-school wrought-iron structure. This is the one enemy
  the *architecture* asked for.

### 2.4 Gaivotas (air chaff)

Storm-driven gulls off the estuary, diving in flocks.

- **Why:** the entire fight is currently on one ground plane. Nothing makes the player look
  up, which is a waste of a nine-metre boss. Gulls are the cheapest possible vertical threat
  and they are already flying over the real Ribeira.

---

## 3. THE DROWNED — the body count

The most site-specific family, and the one that needs the most care.

### 3.1 Alminhas da Ponte (signature unit)

Waterlogged figures that climb over the parapet from the Douro and **grab** — slowing, not
killing.

- **Lore, and this is the find:** on 29 March 1809, fleeing Soult's troops, the crowd of
  Porto packed onto the **Ponte das Barcas** — the pontoon bridge of boats that stood *at
  this exact crossing* — and it gave way. Estimates of the dead vary and are commonly cited
  in the thousands. The **Alminhas da Ponte**, a bronze relief of souls in the water with
  their hands raised, is set into the Ribeira quay wall at the foot of the bridge to this
  day. Adamastor's canonical trophy is drowned people; this crossing already has its own.
- **Mechanics:** a tether/grab, not a damage source. Distinct verb from everything else in
  the game — you break out or you get caught by the next slam.
- **Tone — read this before building it:** these are real dead people, memorialised a
  hundred metres from the arena. Using them as trash mobs to farm will read as tasteless,
  and rightly so. **The recommended framing is that they are not enemies but hostages:**
  Adamastor has dragged them up and is driving them at you. They grab because they are
  reaching for help. Freeing one is a heal or a score bonus, not a kill. That is better
  drama than another mob, it makes the giant genuinely monstrous rather than merely large,
  and it keeps a real memorial on the right side of the line. If that framing is not going
  to be built, cut the unit rather than ship the flat version.

### 3.2 Barcos rabelos (arena hazard)

The flat-bottomed port-wine boats, raised from their moorings at Gaia, ramming the piers
and shuddering the deck.

- **Lore:** the rabelos carried the pipes down the Douro and are moored directly under this
  bridge right now. As pure iconography per pixel, nothing beats them.
- **Mechanics:** a scheduled arena shake that destabilises footing, plus a delivery system
  for flaming wine pipes — which retroactively explains why `wine_barrel.tscn` is scattered
  all over the deck.

### 3.3 A nau afogada — the drowned ship (chapter mini-boss, alternative)

A barnacled prow breaching *through* the deck, firing rotted bombards.

- **Lore:** the wrecks Adamastor names are the *História Trágico-Marítima* disasters. The
  **São João** — Sepúlveda's ship, the wreck Camões dwells on longest — is the obvious pick,
  and the name lands twice in Porto, where São João is the city's patron and its festival.

---

## 4. The lieutenant — and it should not be a monster

A chapter wants a named rival before the boss. Camões supplies the perfect one, and the
whole point of it is that it is not a fight you win by hitting harder.

**Adamastor was not beaten in combat. He was tricked.** Doris promised him Tétis; he chased
a shape through the dark, seized it, and found he was holding "um duro monte" — a bare rock
(st. 55–56). Every ship he has sunk since is that humiliation, re-enacted.

So the lieutenant is **the false Tétis**: the illusion itself, still walking. Sea-foam over
granite, beautiful at distance, stone up close.

- **Verb:** deception, not damage. She creates a false safe zone, a false path across a
  broken bay, a false ally voice calling you to the wrong side of the deck. The counter is
  to read what is real — a different skill from everything else in the game, which is
  exactly what a mid-chapter fight should demand.
- **Payoff:** Adamastor still cannot tell she is not real. Fighting her in front of him is
  the chapter's emotional beat, and it costs one enemy rather than a cutscene.
- **Counterpart:** in Canto VI the Nereids side *with* the Portuguese — Venus sends them to
  calm the sea for Gama. If the chapter wants a friendly NPC, the real nymphs are canonically
  available, and their presence sharpens what the false one is.

---

## 5. Chapter shape

Three families, one lieutenant, one boss — and the bridge already has the geometry for all
of it. `bridge_ironwork.gd` builds **the real lower road deck, 14 m below the playable one**,
as meshes with no colliders. That is a second arena sitting unused in the project right now.

| Beat | Space | Content |
|---|---|---|
| 1 — Approach | Ribeira quay / lower deck | Alminhas rise from the water. Teaches the grab. Penedos as first combat. |
| 2 — The climb | Arch lattice, spandrel columns | Vertical traversal. Fogo de Santelmo on the ironwork, gulls, nortada. No ground fighting. |
| 3 — The lie | Upper deck | The false Tétis. Filhos da Terra hold the far end. |
| 4 — The giant | Upper deck | Adamastor as built today. |
| 5 — Phase two | Deck collapses | His slam breaks a bay and drops the fight to the lower road deck for the finish. |

Beat 5 is the argument for the whole structure: the existing phase-two transition is a
speed buff and a red tint, and it could instead be **the arena breaking**. The geometry to
fall onto is already modelled.

---

## 6. If only one thing gets built

**Penedos** (§1.1). It is a reskin of an existing projectile, it repairs the weakest attack
in the current FSM, it needs no new art beyond a rock with a face, and it is a direct quote
from stanza 59. Everything else in this document is a bigger bet.

---

## 7. Sources

- Luís de Camões, *Os Lusíadas*, Canto V, st. 18–22 (St Elmo's fire, the waterspout) and
  st. 37–60 (the Adamastor episode: lineage st. 51, Tétis and the deception st. 52–56,
  petrification st. 59, the prophecies st. 44–48); Canto VI (the Nereids aiding the fleet).
- *História Trágico-Marítima* — the shipwreck accounts Adamastor's prophecies draw on,
  including the loss of the São João and the death of Sepúlveda and D. Leonor.
- The Ponte das Barcas disaster, 29 March 1809, and the *Alminhas da Ponte* memorial relief
  on the Ribeira quay.
- Ponte de Dom Luís I (Téophile Seyrig, 1886) — double-deck wrought-iron crescent arch;
  upper deck metro and footways, lower deck road.
