class_name PhysicsLayers
extends RefCounted
## Single source of truth for the project's 3D physics layer bits.
##
## project.godot's [layer_names] block is 1-indexed; these are the matching
## masks. Layer 6 ("props") arrives with the interactive prop library and still
## wants its display name adding to project.godot — it works unnamed, it is just
## harder to read in the inspector.
##
## Two masking rules that are easy to get wrong and expensive to debug:
##
##  * Godot collides two bodies when EITHER side's mask names the other's layer.
##    So a prop that masks PLAYERS is blocked and shoved by the player without
##    the player's own mask changing at all — one less cross-stream dependency.
##  * The boss deliberately masks WORLD only, and no prop or projectile masks
##    BOSS. A nine-metre stone giant that a 1.7 m kid or a 45 kg barrel can
##    body-block reads as broken. It blocks THEM (its layer is in their masks)
##    and shoves them with explicit hitboxes.

const WORLD := 1 << 0
const PLAYERS := 1 << 1
const BOSS := 1 << 2
const PLAYER_PROJECTILES := 1 << 3
const HAZARDS := 1 << 4
const PROPS := 1 << 5
