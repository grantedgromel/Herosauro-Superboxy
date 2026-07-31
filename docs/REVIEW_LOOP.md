# The review loop

How quality work is actually driven on this project. The method is adapted from
[Claude of Duty](https://github.com/mshumer/Claude-of-Duty), which built a
browser FPS with a fleet of agents under orchestration; the parts worth keeping
were the harness and the process discipline, not the game.

The short version: **agents cannot see.** A change that "should look better"
routinely looks worse, and nobody finds out for three more rounds. So every
visual claim goes through a render, and every render goes past an adversarial
critic whose job is to find the frame amateur.

## The pieces

| tool | purpose |
|---|---|
| `tools/harness.py capture` | Render the shot set. One Godot process per shot, `--fixed-fps`, seeded. |
| `tools/harness.py diff` | Per-pixel gate between two capture directories. Non-zero exit if any pixel moved. |
| `tools/harness.py sheet` | Contact sheet — the whole set as one image a critic can read in one look. |
| `tools/harness.py verify` | Captures twice and diffs the two runs. Proves the gate is real. |
| `tools/harness.py check` | Fast pre-commit smoke: import clean, boot, render one frame. |
| `tools/parsecheck.tscn` | Every `.gd` in the project compiles. Three seconds. Run it. |
| `tools/budget.tscn` | Static-world cost at every canonical vantage, per tier. |
| `tools/profile.tscn` | Frame-cost **distribution** over a live fight, plus the budget gate. |
| `tools/playtest.tscn` | Scripted playthrough; asserts the fight actually functions. |
| `tools/critic/RUBRIC.md` | What the critic scores against, and the rules it must follow. |
| `tools/shots.json` | The shot manifest. Vantage points are fixed forever so rounds compare. |

`ARCHITECTURE.md` at the repo root is the contract every agent reads first:
directory ownership, the signal vocabulary, and the quality bar.

## Running a round

```bash
cd herosauro-superboxy

# 1. Where are we?
python3 tools/harness.py capture --out /tmp/shots/r1 --jobs 2
python3 tools/harness.py sheet   /tmp/shots/r1

# 2. Critics score /tmp/shots/r1/sheet.png against tools/critic/RUBRIC.md.
#    Defects become the next round's work, one owner per directory.

# 3. After the work lands:
python3 tools/harness.py check                        # did anyone break the boot?
python3 tools/harness.py capture --out /tmp/shots/r2 --jobs 2
python3 tools/harness.py diff /tmp/shots/r1 /tmp/shots/r2 --heatmaps /tmp/shots/heat
```

`diff` is used two opposite ways, and both matter:

- On a **visual** pass, it should report change — and the heatmaps show *where*,
  which catches the agent that fixed the deck and silently moved the sky.
- On an **optimisation** or **refactor** pass, it must report `IDENTICAL`. That
  is the whole value: a performance change that is provably pixel-neutral needs
  no visual re-review, so the expensive part of the loop is skipped entirely.

## Running a stream's probe

Each stream ships a `_*probe.gd` self-test. There are two kinds and they launch
differently — running one the other's way does not error, it reports nonsense:

```bash
godot --headless --path . --script scripts/world/_atmosphere_probe.gd   # extends SceneTree
godot --headless --path . scripts/ui/_ui_probe.tscn                     # needs a scene tree
```

A probe that needs a scene tree **must** be launched as a scene. On the
`--script` path Godot instantiates no autoloads, so every reference to
`GameManager`, `AudioManager` or `InputManager` fails to resolve and the probe
dies before it asserts anything. The same trap makes
`godot --check-only --script <file>` useless for validating a single file here:
untouched, correct scripts fail it identically.

For "does everything still compile", use `tools/parsecheck.tscn` — three seconds
for the whole project, and it exists because `--import` is *not* the check it
looks like. Godot compiles the scripts reachable from the resources it imports,
so a script referenced only by a `.tscn` that no import step loads is never
compiled and the import log stays clean. `tools/profile.gd` sat unparseable that
way for its entire life.

## Gates

A gate does not exist until you have watched it fail. Write the check, put the
fault back, confirm it goes red, then keep it.

This is not a formality. Four tools in this project have reported a clean result
while measuring nothing:

| tool | reported | actually |
|---|---|---|
| `_menu_probe` | 0.1 ms, 9 nodes | measured a scene it had failed to add to the tree — really 3062 ms, 268 nodes |
| `tools/budget.gd` | 0 objects, 0 draw calls, 0 primitives | its scene had no `Camera3D`, so nothing rendered 3D |
| `tools/profile.gd` | nothing, and the budget "kept passing" | did not parse; had never run; and `quit(0)` was unconditional so it could not have failed |
| `tools/parsecheck.gd` | PASS | tested `load() == null`; Godot returns a Script object for a file that did not compile |

Three of those four were written by this loop, to check this loop. The failure
mode is structural, not careless: **a tool that does not run looks exactly like a
tool that runs and finds nothing wrong.** Only a demonstrated failure tells them
apart.

The same applies to a *number* as to a gate. Plausible reasoning is routinely
backwards — the case for compressing the UI art ("painterly plates, nothing
crisp for block artifacts to chew on") had the failure mode of block compression
precisely inverted, and only a render showed it. If a change alters what reaches
the screen, it goes through `diff` against a baseline before it is defended.

## This container has no GPU

Rendering runs on Mesa's lavapipe (software Vulkan) under Xvfb. Two consequences,
both important:

- **It is the real Forward+ pipeline**, not a fallback tier. SDFGI, SSR, SSIL,
  volumetric fog and AgX all execute. What the critic sees is what a desktop
  player sees.
- **Frame times here are meaningless.** A number from lavapipe says nothing
  about a real card. `tools/profile.tscn` therefore reports no framerate: it
  reports CPU-side script and physics cost (which is real everywhere) and
  hardware-independent counts — draw calls, primitives, nodes, bytes.

Budget on roughly **3 minutes per shot**, and note that the cost is dominated by
building the world in GDScript rather than by pixels: dropping from 1280x720 to
640x360 saves only about 10%. That is why there is no cheap iteration tier worth
using for anything but a smoke test.

Concurrency is set with `--jobs`. lavapipe is itself threaded, so more workers
than about half the core count makes the whole set slower, not faster.

## Rules the loop only works under

All three are enforced in `ARCHITECTURE.md` and all three were found the hard way.

1. **Nothing animates off the wall clock.** `sky_background.gd` and
   `river_life.gd` both drove their gulls and boats off `Time.get_ticks_msec()`.
   Two runs boot milliseconds apart, so every capture containing sky differed on
   every run and the gate could only ever report failure. A gate that always
   fails is a gate nobody reads.
2. **Nothing is randomly seeded.** Same reason, at build time rather than frame
   time.
3. **One process per shot.** Sharing a process leaks auto-exposure, particle age
   and tween phase forward, so shot 7 depends on shot 6 and the set stops being
   reproducible even with 1 and 2 fixed.

## The rubric is a proxy. Do not optimise the proxy.

The critics score **frames**, because frames are the only thing an agent can be
shown. A frame-scoring loop will therefore always ask for more *in the frame* —
and past a certain point that stops being the same thing as a better game.

This project walked into it. Three rounds of review kept reporting that the wide
establishing shots were empty: *"across 2.76 million pixels of one of Europe's
busiest riverfronts, at most two or three ambiguous specks that might be
people"*. All true. It became a brief to populate Porto — crowds, market stalls,
café patrons — and that brief was wrong, and the project owner was right to kill
it.

The game is a two-player fight on a bridge deck. The player spends effectively
all of it looking at a nine-metre giant from about ten metres. The far banks are
backdrop nobody studies. A crowd at 60–200 m resolves to 6–10 px specks and
costs real geometry, real draw calls and real review time.

So every critic finding gets a second question before it becomes work:

> **Does a player ever look at this, and for how long?**

Set dressing on a far bank fails that test. A wall tiling visibly fifteen metres
from the camera passes it. The paving the hero runs across for the entire game
passes it emphatically — which is why "the playable ground is half as bright as
sunlit stone" was worth a stream and "nobody lives in Porto" was not.

This is the same trap as briefing off an unverified critic diagnosis, one level
up. There, the fix is to measure the cause before acting. Here, the fix is to
weigh the finding against what the game actually is before acting. The rubric
cannot do that for you: it does not know the deck is where the game happens, and
writing that into the rubric would only teach the critics to under-report the
background, which is not the same as knowing it matters less.

## Process findings worth keeping

**Sequential single-owner beats parallel fan-out on coupled systems.** Claude of
Duty measured this directly: three rounds of six agents each owning a directory
moved their score +0.46 and left frame-ruining defects *higher* than they
started, because tonemapping, sky and indirect light are one system and isolated
agents kept invalidating each other's assumptions. One sequential pass with a
single owner over the whole coupled concern moved it +1.00 and cut defects by
60%.

The same coupling exists here: the sky shader, the Environment resource, the
lighting rig and `ToonFactory`'s material response are one system. They get one
owner and one pass. Genuinely independent streams — UI, audio, props, boss
behaviour — fan out safely.

**Trust the measurement over the brief.** Claude of Duty's single most valuable
result came from an agent contradicting its instructions: every critic for three
rounds called the weapon "untextured", and it was not — it was
specular-dominated, and the previous rounds had been crushing albedo to fight
the complaint, which killed the diffuse term and made it worse. The fix was the
opposite of what was asked for. If a defect survives three rounds of being
"fixed", the correction is probably backwards. The rubric tells critics to say
so explicitly.
