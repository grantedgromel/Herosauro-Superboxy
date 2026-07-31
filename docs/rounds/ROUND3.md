# Round 3 — the score moves, and a third wrong cause is caught

| shot | round 1 | round 2 | round 3 |
|---|---|---|---|
| `03_rail_macro` | 3.0 | 2.8 | **4.0** |
| `01_deck_mid` | 2.3 | 2.6 | **3.5** |

Still AMATEUR. But this is the first round where fixing causes showed up as a
number, and it moved +1.2 and +0.9 on the two frames a materials-and-lighting
critic scores.

Measured across all three rounds, same regions, same cameras:

| region | r1 | r2 | r3 |
|---|---|---|---|
| `02_deck_eye` deck (playable) | L81 s0.138 | L92 s0.132 | **L97 s0.148** |
| `02_deck_eye` facades (background) | L161 s0.354 | L116 s0.358 | **L126 s0.309** |
| `07_ribeira` deck (playable) | L73 s0.159 | L92 s0.144 | **L95 s0.162** |

Deck-to-background luminance ratio **0.50 → 0.79 → 0.77**, with deck saturation
recovering rather than being spent to fake the separation. Round 1's most
damaging finding — an inverted focal hierarchy — is no longer inverted on those
regions, and it was fixed with fog depth and grade shaping rather than the
distance blur the critics warned against.

## The third wrong cause in three rounds

Every round so far, the leading systemic finding has been a correct observation
attached to a wrong cause, and every time the proposed fix would have changed
nothing:

| round | the claim | what was actually true |
|---|---|---|
| 1 | "not one cast shadow exists" | they existed; the sun was at 51° so every shadow fell under its own object |
| 2 | "there is no directional light in this scene at all" | there was; the critic averaged *row means* along the axis the shadows run |
| 3 | "shadows respect a material boundary, so they are not cast by a light" | they taper with distance, exactly as a throw that runs out |

Round 3's version, verified before anything was briefed. The critic reported six
shadow bands on the cobble apron and none on the coplanar slab walkway beyond
it, and concluded the shadows must be painted into the cobble material. Sampling
the dark fraction across rows, top of deck to bottom:

```
y=700  44%      y=590  30%
y=660  51%      y=575  12%
y=620  31%      y=565   8%
```

A **taper**, not a hard stop. A 1.2 m parapet at 34° elevation throws 1.63 m;
the bands fade out where the throw ends, which is ordinary physics and happens
to land near the cobble/slab seam. The critic had already measured everything
needed to rule its own theory out — the bands preserve texture CoV through them
(0.314 vs 0.312), carry sky fill (B/R +0.116 in shadow), and share a vanishing
point with an independent pole shadow to within 7 px. Painted shadows do none of
those three.

**Worth stating plainly: the critics' measurements keep being reproducible and
their inferences keep being wrong.** That is not a reason to stop using them —
their observations have driven every real fix this project has made. It is a
reason never to brief work off a single frame's inferred cause without a second
measurement.

## Confirmed, and outstanding

**The tram rail head renders as a pure sky mirror.** Verified at y=603–604:
RGB (22, 60, 115) and (17, 54, 115), saturation 0.64–0.79, against immediate
neighbours at 0.19–0.33 and warm grey. Round 1 named the flat blue rails as the
single tell that gave the frame away in a blind test; the geometry was rebuilt
in Round 2 as real Ri60 grooved track and a ReflectionProbe was added in the
same round, and the crown is brighter but *still* pure blue.

The cause is understood and was predicted by the stream that built it: the crown
is `metallic = 1`, a metal has no diffuse term, so every photon it returns is a
reflection — and at a grazing view down the deck the only thing in that
reflection is sky. A burnished rail head is not a mirror. It wants enough
roughness spread and enough non-metal in the crown that it picks up the warm
deck bounce and its own iron colour rather than reporting the sky verbatim.

**Contact darkening is still absent**, and this capture already includes
`ssao_light_affect` 0.15 → 0.50. Three standing objects measured — both lamp
standards and the deck bollard — show no dip in the paving beneath them, and in
places the ground directly under an object reads *brighter* than the ground away
from it. Raising the SSAO term was necessary and was not sufficient; the next
pass on this should measure whether SSAO is generating any occlusion at that
radius at all before tuning it further.

**Still open, carried from the critics and unverified by the lead:**

- The stone wall band in `01_deck_mid` tiles at a 214 px period with r=0.864 —
  visible to the naked eye, six repeats across the frame — and has no normal
  doing work: a 7% non-monotonic vertical swing across a 115 px plane.
- The `DOURO CORVO` sign is now the highest-contrast object in `01_deck_mid`
  (local contrast 49.6 against the play space's 11.6) and is cropped mid-word by
  the frame edge. Fixing its geometry made it loud; it now needs to sit behind
  the same aerial perspective as the roofs around it, which measure B/R 0.795
  where the sign does not.
- Ironwork still has no specular return: the top rail's 99th-percentile
  luminance is 92/255 in direct sun.
- Roughly a third to a half of each frame is low-detail, and neither frame has a
  prop on the deck or a character in it.
