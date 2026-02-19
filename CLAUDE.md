# CLAUDE.md

## Project Overview

**Herosauro & Super Boxy: Legends of Porto** is a browser-based 3D co-op action game. Two players control characters (Herosauro and Super Boxy) on the Dom Luís Bridge in Porto, Portugal, fighting the boss Adamastor. The entire game is a single self-contained HTML file with no build system.

## Repository Structure

```
/
├── index.html    # The entire game (HTML + CSS + JS, ~1430 lines)
└── CLAUDE.md     # This file
```

This is a **single-file application**. All markup, styles, and game logic live in `index.html`. There is no build step, no bundler, no package manager, and no separate source files.

## Technology Stack

- **Three.js r128** (CDN) — 3D rendering with WebGL
- **Cannon.js 0.6.2** (CDN) — Physics simulation
- **Vanilla JavaScript** — No frameworks, no modules, all script code in a single `<script>` block
- **CSS** — Inline `<style>` block, no preprocessor

## How to Run

Open `index.html` in any modern web browser. No server or build step required. A local file server (e.g., `python3 -m http.server`) also works but is not necessary.

## Architecture

### Game Loop

The game follows a standard real-time game loop pattern:

1. `init()` — Entry point, sets up Three.js scene, Cannon.js physics world, environment, players, boss, and event listeners
2. `animate()` — Called via `requestAnimationFrame`, runs every frame:
   - Physics step (`world.step`)
   - Player input handling (`handlePlayerMovement`)
   - Respawn/boundary checks (`checkRespawn`)
   - Boss AI update (`updateBossAI`)
   - Physics-to-graphics sync (`syncPhysicsToGraphics`)
   - Camera follow (`updateCamera`)
   - Render (`renderer.render`)

### Key Globals

| Variable | Purpose |
|---|---|
| `CONFIG` | Numeric constants (sizes, speeds, damage, cooldowns) |
| `gameState` | Mutable game state (health, cooldowns, game-over flags) |
| `scene, camera, renderer` | Three.js rendering objects |
| `world` | Cannon.js physics world |
| `player1Body, player2Body, bossBody` | Cannon.js physics bodies |
| `player1Mesh, player2Mesh, bossMesh` | Three.js visual meshes |
| `keys` | Keyboard input state map |

### Major Subsystems

- **Environment** (`createEnvironment`, `createBridgeArches`, `createCitySilhouette`, `createClouds`) — Bridge geometry, river, city backdrop, clouds
- **Players** (`createPlayers`) — Two character meshes with physics bodies (Herosauro = Player 1, Super Boxy = Player 2)
- **Boss** (`createBoss`, `updateBossAI`, `performBossSlam`, `checkBossPlayerCollision`) — Adamastor boss with patrol AI and slam attack
- **Abilities** (`activateDinoEnergy`, `activateBoxyDash`) — Cooldown-based special attacks with visual effects
- **Game Flow** (`damagePlayer`, `damageBoss`, `victory`, `defeat`, `restartGame`) — Health management, win/loss conditions, full state reset
- **UI** (`updateUI`) — DOM-based health bars, ability indicators, victory/defeat overlay

### Controls

| Player | Movement | Special Ability |
|---|---|---|
| Player 1 (Herosauro) | WASD | E — Dino Energy (50 dmg, 2s cooldown) |
| Player 2 (Super Boxy) | Arrow keys | Space — Boxy Dash (25 dmg, 1.5s cooldown) |

### Game Balance Constants (in `CONFIG`)

- Boss health: 500, Player health: 100
- Dino Energy damage: 50, Boxy Dash damage: 25
- Boss slam damage: 20, Boss contact damage: 5
- Boss slam interval: every 4 seconds
- Respawn penalty: 20 damage when falling off bridge

## Code Conventions

- **No modules or imports** — Everything is global scope within the `<script>` block
- **Function naming** — camelCase, descriptive verbs (`createPlayers`, `handlePlayerMovement`, `activateDinoEnergy`)
- **Constants** — `CONFIG` object with UPPER_SNAKE_CASE keys
- **Three.js pattern** — Meshes built in groups (`THREE.Group`), custom data stored in `mesh.userData`
- **Physics sync** — Cannon.js bodies are the source of truth for position; meshes copy from bodies each frame
- **Timed effects** — `setTimeout` for cooldowns, ability durations, and animation sequences
- **DOM UI** — Health bars and status indicators are HTML elements positioned absolutely over the canvas

## Guidelines for AI Assistants

- **Single-file constraint**: All changes go in `index.html`. Do not split into separate files unless explicitly asked.
- **No build tools**: There is no npm, no TypeScript, no bundler. Do not introduce them without explicit request.
- **CDN dependencies**: Three.js and Cannon.js are loaded from CDN. Do not change to local copies or different versions without reason.
- **Test by opening in browser**: There are no automated tests. Verify changes by opening `index.html` in a browser.
- **Preserve game balance**: When modifying gameplay, be aware of the tuning in `CONFIG` and how abilities, boss attacks, and health interact.
- **Global state awareness**: Many functions mutate shared globals (`gameState`, physics bodies, meshes). Side effects are pervasive — trace call chains carefully before modifying.
- **setTimeout chains**: Boss slam and ability effects use nested `setTimeout` calls. Be cautious about timing and cleanup when modifying these.
