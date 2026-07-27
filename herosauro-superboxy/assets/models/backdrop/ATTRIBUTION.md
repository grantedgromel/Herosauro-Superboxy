# Third-party asset attribution

## `porto_backdrop.glb` — Ponte de D. Luís (Porto/Portugal)

- **Author:** EDUARDO SOETHE — https://sketchfab.com/dusoethe
- **Source:** https://sketchfab.com/3d-models/ponte-de-d-luis-portoportugal-2551868c712942729abe8e5bd6cc318c
- **License:** [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/)

This attribution is **required** by the licence. It must remain with the asset,
appear in the game's credits, and stay in the project README. If the asset is
removed from the project, this file goes with it.

### Modifications made

The original is an aerial photogrammetry capture of the district around the
bridge. It was redistributed here in modified form (CC BY 4.0 permits this and
requires that the changes be stated):

1. `gltf-transform metalrough` — converted the material off the archived
   `KHR_materials_pbrSpecularGlossiness` extension to metallic-roughness.
   Required: the source listed that extension in `extensionsRequired`, which
   makes Godot abort the import outright.
2. `gltf-transform dedup` + `weld` + `join` — merged 239 separate mesh
   primitives into 1, reducing the model from 239 draw calls to 1.
3. `gltf-transform webp` — recompressed the 1024x1024 baked albedo atlas.

Geometry is otherwise unaltered: 426,571 triangles, 1,060,156 vertices.
(Decimation was attempted and abandoned — the mesh is ~239 originally
disconnected photogrammetry chunks whose UV-atlas seams lock the topology, so
even an aggressive simplify only reached ~377k triangles.)

### How it is used

Distant backdrop only, with no collision. Everything the player walks on is
hand-built geometry. The scan carries lighting baked into its albedo, so it
does not cast real-time shadows — see `scenes/world/city_backdrop.tscn`.
