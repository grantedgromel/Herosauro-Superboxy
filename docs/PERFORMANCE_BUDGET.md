# Render budget — measured

Produced by `tools/budget.tscn` against `scenes/world/bridge_arena.tscn` on
Godot 4.7.1, Forward+:

```
godot --path . tools/budget.tscn --rendering-driver vulkan
```

## What was measured

| Metric | Value |
|---|---|
| MeshInstance3D | 188 |
| Surfaces (≈ draw calls, geometry) | 188 |
| …of which cast shadows | 171 |
| MultiMeshInstance3D | 7 (604 instances) |
| Lights | 11 (1 directional + 8 lamp omnis + 2) |
| Collision bodies | 9 |
| Triangles | 441,842 |
| Texture memory | 43.3 MiB |
| Buffer memory | 34.2 MiB |
| Video memory | 86.6 MiB |

## Reading these

**Geometry is comfortable.** 188 draw calls is far inside what any mid-range GPU
handles (low thousands); 442k triangles is likewise unremarkable — mid-range
cards push millions per frame. That headroom is bought by baking: `MeshBaker`
welds each building, the whole bridge ironwork and each terrain reach into single
surfaces, so detail costs triangles instead of draw calls. The same scene built
one-primitive-per-node would be several thousand draw calls, which is the number
that actually kills a frame.

**Memory is a non-issue** at 87 MiB total.

**The real cost is per-pixel, not geometry.** The expensive things here are the
post-processing stack — SDFGI, SSR, SSIL, SSAO and volumetric fog — plus the
shadow pass, where 171 casters are re-rendered per directional cascade. If the
frame budget is missed on real hardware, those are the levers, in order:

1. `sdfgi_enabled = false` — highest cost, and the most doubtful at this world
   scale. The scene spans ~900 units of river; SDFGI cascades sized for that are
   coarse, and the play space is an open sky-lit deck where GI contributes least.
   Compensate with `ambient_light_energy` and SSIL.
2. `directional_shadow_max_distance` — currently the default 100. Cutting it
   drops casters out of the cascades wholesale.
3. `ssr_enabled` — the Douro reflection is the single most Porto-looking thing in
   the frame, so trade it away last.
4. Volumetric fog `volume_size`/`volume_depth`, raised to 96 for shaft crispness
   through the lattice; back to 64 costs little visually.

## What is NOT measured, and why

**Framerate.** This was produced in a container with **no GPU** — rendering runs
on llvmpipe (software Vulkan), so a frame time here says nothing about a real
card. Every number above is deliberately hardware-independent: counts and bytes,
not milliseconds.

So the 60fps target is pursued through budgets, not asserted. Confirming it needs
one run of the desktop build on real mid-range hardware. If it misses, the lever
order above is the place to start.

The web build is a separate, lighter tier: GL Compatibility, LDR framebuffer, no
SDFGI/SSR/SSIL/volumetric fog, and the photogrammetry backdrop excluded at export
(pck stays at 7.4 MB rather than ~45 MB).
