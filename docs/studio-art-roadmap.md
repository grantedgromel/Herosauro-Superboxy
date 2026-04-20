# Studio Art Roadmap

This prototype still runs in `Phaser`, so the best near-term path is not to replace the engine. The best path is to use higher-end 3D sources as an **art pipeline**, then render polished sprites, bosses, props, and backgrounds back into the browser game.

## Recommended Production Path

1. Keep gameplay in the current `Phaser + TypeScript + Vite` stack.
2. Build final art in `Blender` or `Unreal` using sourced kits, materials, and character tools.
3. Render approved camera angles into sprite sheets and layered background plates.
4. Export optimized textures and sprite atlases for the web build.
5. Preserve gameplay readability over full realism.

## Fab And External Asset Shortlist

### Environment kits

- [Modular Medieval Town, Docks](https://www.fab.com/listings/9bec871e-2d9b-4261-aa26-868d4300f81a)
  - Best use here: Ribeira blockout, dock modules, stepped facades, windows, balconies, riverside set dressing.
  - Why it fits: photoreal/modular dock-town coverage, strong for a Porto-like waterfront base.
- [Modular Medieval Docks / Harbor](https://www.fab.com/listings/454e9934-6193-445f-9e78-a3ed2015d987)
  - Best use here: boats, harbor details, rope posts, quay dressing, playable dock silhouettes.
  - Why it fits: modular dock scene with landscape materials and VFX-ready harbor pieces.
- [Side Scroller Template - 2D Movement/Camera Starter Kit](https://www.fab.com/listings/0c64fe7e-ac14-49a6-b507-39b133cdb25f)
  - Best use here: only if we prototype a future Unreal vertical slice for publisher/demo purposes.
  - Why it fits: free Unreal starter for side-scrolling movement and camera logic.
- [wRAiTHcg's 2.5D Side Scroller Game Creator Template with Motion Matching](https://www.fab.com/listings/fe717796-bd46-485f-850b-0a445f285f23)
  - Best use here: future Unreal migration exploration, not current runtime.
  - Why it fits: broader 2.5D action-adventure template with character systems and customization hooks.

### Character sources

- [MetaHuman Creator](https://www.metahuman.com/en-US/create)
  - Best use here: believable civilian forms, NPCs, and close-up reference for Rui/Kiko proportions, skin, hair, and clothing breakup.
  - Do not use as-is for final heroes without stylization passes.
- [Character Creator](https://www.reallusion.com/iclone/character-creator/top.html)
  - Best use here: stylized-real hero bodies, clothing iteration, export-friendly humanoid pipeline.
  - Stronger than MetaHuman for gameplay-directed customization.
- [Mixamo FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html)
  - Best use here: quick temp animation blocking and retarget experiments for Super Boxy and generic NPCs.
  - Limitation: Adobe says the auto-rigger and animation libraries are for biped humanoids only, so it is not a full Herosauro solution.
- [Cartoon Boy Black Rigged](https://www.fab.com/listings/78bbbfdc-a0a6-47ca-b670-c5238635d014)
  - Best use here: facial shape, youth silhouette, pose language reference.
- [Billy / Stylized Cartoon Boy Character](https://www.fab.com/listings/d679c086-7865-4184-ab1a-6207f162d1d8)
  - Best use here: fast stylized boy baseline for Rui/Kiko civilian or alternate Boxy proportions.
- [Stylized Male Character](https://www.fab.com/listings/630cecd2-d9a4-405b-ac00-4301bf6f0bbc)
  - Best use here: combat-ready pose language and martial-artist body reference for Super Boxy.

### Surface and material library

- [Plastered Wall](https://polyhaven.com/a/plastered_wall)
- [Painted Plaster Wall](https://polyhaven.com/a/painted_plaster_wall)
- [Roof Tiles 14](https://polyhaven.com/a/roof_tiles_14)
- [Cobblestone Pavement](https://polyhaven.com/a/cobblestone_pavement)
- [Cobblestone Color](https://polyhaven.com/a/cobblestone_color)

These are useful for Porto-specific wall wear, roof variation, and pavement grounding when building matte-painted or kitbashed background plates.

### Reality capture

- [RealityScan Mobile](https://www.realityscan.com/en-US/mobile)
  - Best use here: local props and secondary details.
  - Good scan targets: bollards, stone steps, mooring posts, old doors, lanterns, railings, wall plaques.

## Character Design Direction

### Herosauro

- Move from mascot dinosaur to **credible heroic hybrid**.
- Keep the broad silhouette, horn, tail, and green identity.
- Add layered anatomy: visible shoulder mass, hip mass, calf definition, clearer claw structure, heavier foot read.
- Replace flat color with:
  - scale breakup across shoulders and forearms
  - softer underbelly material
  - worn leather or canvas harness elements
  - metal buckles or straps that catch light
- Animation target:
  - heavier anticipation
  - stronger weight shift
  - slower recovery frames
  - more believable landing compression

### Super Boxy

- Move from toy-like boxer to **stylized-real athletic older brother**.
- Keep the gloves, speed, and color identity.
- Improve realism with:
  - more natural shoulder width and neck structure
  - real glove seams and wrap compression
  - layered fabric in shorts, belt, and shoes
  - asymmetry in hair, mask edges, and stance
- Animation target:
  - snappier torso twist
  - sharper planted feet
  - visible recoil in punch chains
  - cleaner center-of-gravity shifts

### Shared art rule

- Final art target should be `stylized realism`, not photorealism.
- Think believable materials and anatomy with storybook readability.
- Aim for "pre-rendered CG platformer hero" instead of "AAA live-action human".

## Porto Background Rules

Use real Porto references as the layout and material bible:

- [Ribeira](https://porto.travel/ribeira/)
- [Clérigos Tower](https://porto.travel/clerigos-tower/)
- [Casa da Música building notes](https://casadamusica.com/en/building/)
- [Feasts of São João](https://visitportugal.com/en/node/155969)

### Mandatory Porto motifs

- Colorful but weathered facades, not clean fantasy houses.
- Granite ground planes and retaining walls.
- Terracotta and stained ceramic roof variation.
- Azulejo panels as accents, not wallpaper over every surface.
- Iron balconies and railings.
- Laundry lines, shutters, wall plaques, café awnings, and mooring details.
- Rabelo boats and Douro reflections.
- Dom Luís I bridge structure that reads immediately from silhouette alone.

### Stage 1 lookdev priorities

1. Dom Luís I bridge silhouette and steel rhythm.
2. Ribeira slope of stacked facades along the water.
3. Warm sunset light with blue river bounce.
4. River haze and reflective water, not flat blue bands.
5. Granite, plaster, and roof material variation everywhere.

## Integration Plan

### Immediate next production steps

1. Build one polished Porto background plate for Stage 1 using dock kitbash pieces plus Poly Haven materials.
2. Sculpt or customize one approved 3D hero model for each brother.
3. Render:
   - idle
   - run
   - jump
   - attack
   - special
   - hurt
4. Normalize sprite strips into the current runtime.
5. Replace the procedural boss with a rendered Adamastor head, arm, and weak-point set.

### Do not do yet

- Full engine migration.
- Full photoreal character pipeline.
- Multi-stage environment art production.
- Final cinematic lighting for all stages before Stage 1 art proves out.

