import type {
  BossPhase,
  EncounterDefinition,
  GameState,
  GameStatus,
  HeroKind,
  HeroState,
} from "../types";

function createHero(kind: HeroKind, x: number, y: number): HeroState {
  const isHerosauro = kind === "herosauro";

  return {
    kind,
    displayName: isHerosauro ? "Herosauro" : "Super Boxy",
    health: isHerosauro ? 150 : 110,
    maxHealth: isHerosauro ? 150 : 110,
    x,
    y,
    vx: 0,
    vy: 0,
    facing: 1,
    onGround: false,
    coyoteTimer: 0,
    jumpBufferTimer: 0,
    airDashes: 1,
    attackTimer: 0,
    rollTimer: 0,
    specialTimer: 0,
    attackStyle: "idle",
    comboStep: 0,
    isDown: false,
    reviveTimer: 0,
    abilities: {
      attackCooldown: 0,
      specialCooldown: 0,
      dodgeCooldown: 0,
      invulnerability: 0,
      comboTimer: 0,
    },
  };
}

function checkpointBossPhase(status: GameStatus): BossPhase {
  return status === "victory" ? "defeated" : "dormant";
}

export function createGameState(
  encounter: EncounterDefinition,
  status: GameStatus = "playing",
): GameState {
  const herosauro = createHero("herosauro", encounter.startX, encounter.startY);
  const superBoxy = createHero("superBoxy", encounter.startX, encounter.startY);
  const checkpoint = encounter.checkpoints[0];

  return {
    encounterId: encounter.id,
    time: 0,
    status,
    activeHero: "superBoxy",
    swapCooldown: 0,
    heroes: {
      herosauro,
      superBoxy,
    },
    boss: {
      phase: checkpointBossPhase(status),
      pattern: "slam",
      patternIndex: 0,
      active: false,
      locked: false,
      weakPointOpen: false,
      telegraphTimer: 0,
      staggerTimer: 0,
      health: 12,
      maxHealth: 12,
      shakeTimer: 0,
      finisherStep: 0,
      finisherTimer: 0,
    },
    checkpoint: {
      lastId: checkpoint.id,
      x: checkpoint.x,
      y: checkpoint.y,
      bossHealth: 12,
      bossPhase: checkpointBossPhase(status),
    },
    collectibles: {
      tostoes: 0,
      letters: [],
      tileFragments: 0,
    },
    pickups: encounter.pickups.map((pickup) => ({ ...pickup, collected: false })),
    golems: encounter.golemSpawns.map((spawn) => ({
      id: spawn.id,
      x: spawn.x,
      y: spawn.y,
      vx: 0,
      facing: -1,
      health: 7,
      maxHealth: 7,
      alive: true,
      patrolMin: spawn.patrolMin,
      patrolMax: spawn.patrolMax,
      attackCooldown: 0,
      hitFlash: 0,
    })),
    hazards: encounter.hazards.map((hazard) => ({
      ...hazard,
      timer: hazard.interval,
      active: false,
    })),
    breakables: encounter.breakables.map((breakable) => ({ ...breakable, broken: false })),
    objective: encounter.objectiveText.tutorial,
    activeSection: "tutorial",
    cameraTargetX: encounter.startX + 120,
    prompt: "J attack, K special, L dodge, Q or Shift swap",
    message: "A retro action-platformer prototype on the Douro.",
  };
}

