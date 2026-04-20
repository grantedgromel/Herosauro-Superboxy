import { createGameState } from "./createGameState";
import type {
  BossPattern,
  EncounterDefinition,
  GameState,
  HeroKind,
  HeroState,
  InputFrame,
  ObjectiveId,
  Rect,
  ViewModel,
} from "../types";

const WORLD_GRAVITY = 1450;
const HERO_SPECS = {
  herosauro: {
    width: 58,
    height: 92,
    moveSpeed: 220,
    jumpVelocity: 560,
    lightDamage: 2,
    lightRange: 108,
    maxHealth: 150,
  },
  superBoxy: {
    width: 48,
    height: 82,
    moveSpeed: 320,
    jumpVelocity: 540,
    lightDamage: 1,
    lightRange: 88,
    maxHealth: 110,
  },
} as const;

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function rectsOverlap(a: Rect, b: Rect): boolean {
  return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}

function heroRect(hero: HeroState): Rect {
  const spec = HERO_SPECS[hero.kind];
  return {
    x: hero.x - spec.width / 2,
    y: hero.y - spec.height,
    width: spec.width,
    height: spec.height,
  };
}

function getOtherHero(kind: HeroKind): HeroKind {
  return kind === "herosauro" ? "superBoxy" : "herosauro";
}

function solidRects(state: GameState, encounter: EncounterDefinition): Rect[] {
  const intactBreakables = state.breakables.filter((breakable) => !breakable.broken);
  return [...encounter.platforms, ...intactBreakables];
}

function tickHeroTimers(hero: HeroState, dt: number): void {
  hero.attackTimer = Math.max(0, hero.attackTimer - dt);
  hero.rollTimer = Math.max(0, hero.rollTimer - dt);
  hero.specialTimer = Math.max(0, hero.specialTimer - dt);
  hero.coyoteTimer = Math.max(0, hero.coyoteTimer - dt);
  hero.jumpBufferTimer = Math.max(0, hero.jumpBufferTimer - dt);
  hero.abilities.attackCooldown = Math.max(0, hero.abilities.attackCooldown - dt);
  hero.abilities.specialCooldown = Math.max(0, hero.abilities.specialCooldown - dt);
  hero.abilities.dodgeCooldown = Math.max(0, hero.abilities.dodgeCooldown - dt);
  hero.abilities.invulnerability = Math.max(0, hero.abilities.invulnerability - dt);
  hero.abilities.comboTimer = Math.max(0, hero.abilities.comboTimer - dt);
  hero.attackStyle = hero.attackTimer > 0 || hero.rollTimer > 0 || hero.specialTimer > 0 ? hero.attackStyle : "idle";
}

function syncInactiveHeroPosition(state: GameState): void {
  const active = state.heroes[state.activeHero];
  const inactive = state.heroes[getOtherHero(state.activeHero)];
  if (!inactive.isDown) {
    inactive.x = active.x;
    inactive.y = active.y;
    inactive.facing = active.facing;
    inactive.vx = 0;
    inactive.vy = active.vy;
    inactive.onGround = active.onGround;
  }
}

function applyDamageToHero(
  state: GameState,
  heroKind: HeroKind,
  amount: number,
  prompt?: string,
): void {
  const hero = state.heroes[heroKind];
  if (hero.isDown || hero.abilities.invulnerability > 0) {
    return;
  }

  hero.health = clamp(hero.health - amount, 0, hero.maxHealth);
  hero.abilities.invulnerability = 0.75;
  state.prompt = prompt ?? "Keep moving. Adamastor punishes hesitation.";

  if (hero.health > 0) {
    return;
  }

  hero.isDown = true;
  hero.reviveTimer = 10;
  hero.vx = 0;
  hero.vy = 0;
  hero.attackStyle = "idle";
  state.prompt = `${hero.displayName} is down. Hold on for the revive window.`;

  const otherKind = getOtherHero(heroKind);
  if (!state.heroes[otherKind].isDown) {
    state.activeHero = otherKind;
    state.swapCooldown = 0.8;
    syncInactiveHeroPosition(state);
    return;
  }

  state.status = "gameOver";
}

function reviveHeroes(state: GameState, dt: number): void {
  const active = state.heroes[state.activeHero];
  for (const hero of Object.values(state.heroes)) {
    if (!hero.isDown) {
      continue;
    }
    hero.reviveTimer = Math.max(0, hero.reviveTimer - dt);
    if (hero.reviveTimer > 0) {
      continue;
    }
    hero.isDown = false;
    hero.health = Math.round(hero.maxHealth * 0.45);
    hero.abilities.invulnerability = 1.25;
    hero.x = active.x;
    hero.y = active.y;
    hero.facing = active.facing;
  }
}

function activeSectionForX(state: GameState, encounter: EncounterDefinition): ObjectiveId {
  const x = state.heroes[state.activeHero].x;
  if (state.boss.phase === "defeated") {
    return "victory";
  }
  if (x >= encounter.bossArena.start - 120 || state.boss.active) {
    return "boss";
  }
  if (x >= 2300) {
    return "warmup";
  }
  if (x >= 820) {
    return "hazard";
  }
  return "tutorial";
}

function updateObjectiveText(state: GameState, encounter: EncounterDefinition): void {
  state.activeSection = activeSectionForX(state, encounter);
  state.objective = encounter.objectiveText[state.activeSection];

  switch (state.activeSection) {
    case "tutorial":
      state.prompt = state.swapCooldown > 0 ? "Swap cooling down..." : "Swap freely to feel the brothers' rhythm.";
      break;
    case "hazard":
      state.prompt = "Jump the broken girders and watch the falling stone.";
      break;
    case "warmup":
      state.prompt = "Herosauro crushes crates. Boxy threads tight routes.";
      break;
    case "boss":
      if (state.boss.phase === "bridgeShake") {
        state.prompt = "Adamastor is rising. Hold steady on the bridge.";
      } else if (state.boss.phase === "combat" && state.boss.weakPointOpen) {
        state.prompt = "Weak point open. Strike his brow before he resets.";
      } else if (state.boss.phase === "finisher") {
        state.prompt =
          state.boss.finisherStep === 0
            ? "Lead with Herosauro, then tag Super Boxy for the finisher."
            : "Switch to Super Boxy and uppercut the weak point.";
      }
      break;
    case "victory":
      state.prompt = "Adamastor falls back into the Douro.";
      break;
  }
}

function maybeCaptureCheckpoint(state: GameState, encounter: EncounterDefinition): void {
  const hero = state.heroes[state.activeHero];
  for (const checkpoint of encounter.checkpoints) {
    if (hero.x < checkpoint.x || state.checkpoint.lastId === checkpoint.id) {
      continue;
    }
    state.checkpoint = {
      lastId: checkpoint.id,
      x: checkpoint.x,
      y: checkpoint.y,
      bossHealth: state.boss.health,
      bossPhase: state.boss.phase,
    };
    state.message = `Checkpoint reached at ${checkpoint.id}.`;
  }
}

function resetToCheckpoint(state: GameState, encounter: EncounterDefinition): GameState {
  const fresh = createGameState(encounter, "playing");
  const collectedIds = new Set(state.pickups.filter((pickup) => pickup.collected).map((pickup) => pickup.id));

  fresh.pickups = fresh.pickups.map((pickup) => ({
    ...pickup,
    collected: collectedIds.has(pickup.id),
  }));
  fresh.collectibles = structuredClone(state.collectibles);
  fresh.checkpoint = structuredClone(state.checkpoint);
  fresh.boss.health = state.checkpoint.bossHealth;
  fresh.boss.phase = state.checkpoint.bossPhase;
  fresh.boss.active = state.checkpoint.bossPhase !== "dormant";
  fresh.boss.locked = state.checkpoint.bossPhase !== "dormant";
  fresh.boss.weakPointOpen = false;
  fresh.boss.telegraphTimer = state.checkpoint.bossPhase === "combat" ? 1.2 : 0;
  fresh.activeHero = state.activeHero;
  fresh.heroes.herosauro.health = Math.round(fresh.heroes.herosauro.maxHealth * 0.7);
  fresh.heroes.superBoxy.health = Math.round(fresh.heroes.superBoxy.maxHealth * 0.7);
  fresh.heroes.herosauro.x = state.checkpoint.x;
  fresh.heroes.herosauro.y = state.checkpoint.y;
  fresh.heroes.superBoxy.x = state.checkpoint.x;
  fresh.heroes.superBoxy.y = state.checkpoint.y;
  fresh.message = "Back on your feet. Porto still needs you.";
  updateObjectiveText(fresh, encounter);
  return fresh;
}

function resolveHorizontalCollisions(hero: HeroState, solids: Rect[]): void {
  const rect = heroRect(hero);
  for (const solid of solids) {
    if (!rectsOverlap(rect, solid)) {
      continue;
    }
    if (hero.vx > 0) {
      hero.x = solid.x - rect.width / 2;
    } else if (hero.vx < 0) {
      hero.x = solid.x + solid.width + rect.width / 2;
    }
    hero.vx = 0;
  }
}

function resolveVerticalCollisions(hero: HeroState, solids: Rect[]): void {
  hero.onGround = false;
  const rect = heroRect(hero);
  for (const solid of solids) {
    if (!rectsOverlap(rect, solid)) {
      continue;
    }
    if (hero.vy >= 0 && rect.y + rect.height - hero.vy * (1 / 60) <= solid.y + 8) {
      hero.y = solid.y;
      hero.vy = 0;
      hero.onGround = true;
      hero.coyoteTimer = 0.12;
      hero.airDashes = 1;
    } else if (hero.vy < 0) {
      hero.y = solid.y + solid.height + rect.height;
      hero.vy = 0;
    }
  }
}

function nearClimbZone(hero: HeroState, encounter: EncounterDefinition): boolean {
  const rect = heroRect(hero);
  return encounter.climbZones.some((zone) => {
    if (zone.hero !== "both" && zone.hero !== hero.kind) {
      return false;
    }
    return rectsOverlap(rect, zone);
  });
}

function nearWallBounce(hero: HeroState, solids: Rect[]): boolean {
  const rect = heroRect(hero);
  return solids.some((solid) => {
    const touching =
      rect.y + rect.height > solid.y + 8 &&
      rect.y < solid.y + solid.height - 8 &&
      Math.abs(rect.x + rect.width - solid.x) < 12;
    const touchingRight =
      rect.y + rect.height > solid.y + 8 &&
      rect.y < solid.y + solid.height - 8 &&
      Math.abs(rect.x - (solid.x + solid.width)) < 12;
    return touching || touchingRight;
  });
}

function updateHeroMovement(
  state: GameState,
  input: InputFrame,
  encounter: EncounterDefinition,
  dt: number,
): void {
  const hero = state.heroes[state.activeHero];
  if (hero.isDown) {
    return;
  }

  const spec = HERO_SPECS[hero.kind];
  const solids = solidRects(state, encounter);
  const moveDirection = Number(input.held.moveRight) - Number(input.held.moveLeft);

  if (moveDirection !== 0) {
    hero.facing = moveDirection > 0 ? 1 : -1;
  }

  if (input.pressed.jump) {
    hero.jumpBufferTimer = 0.16;
  }

  const climb = hero.kind === "herosauro" && nearClimbZone(hero, encounter) && input.held.jump;
  if (climb) {
    hero.vy = -220;
    hero.onGround = false;
  } else if (hero.rollTimer <= 0) {
    hero.vx = moveDirection * spec.moveSpeed;
  }

  if (input.pressed.dodge && hero.kind === "superBoxy" && hero.abilities.dodgeCooldown <= 0) {
    hero.rollTimer = 0.28;
    hero.attackStyle = "roll";
    hero.abilities.dodgeCooldown = 1.05;
    hero.abilities.invulnerability = 0.42;
    hero.vx = hero.facing * 480;
  }

  const canJump = hero.onGround || hero.coyoteTimer > 0;
  if (hero.jumpBufferTimer > 0 && canJump) {
    hero.vy = -spec.jumpVelocity;
    hero.jumpBufferTimer = 0;
    hero.coyoteTimer = 0;
    hero.onGround = false;
  } else if (
    hero.kind === "superBoxy" &&
    input.pressed.jump &&
    !hero.onGround &&
    hero.airDashes > 0 &&
    nearWallBounce(hero, solids)
  ) {
    hero.vy = -520;
    hero.vx = hero.facing * -290;
    hero.airDashes = 0;
  }

  if (!climb) {
    hero.vy += WORLD_GRAVITY * dt;
  }

  hero.x += hero.vx * dt;
  resolveHorizontalCollisions(hero, solids);

  hero.y += hero.vy * dt;
  resolveVerticalCollisions(hero, solids);

  hero.x = clamp(hero.x, 32, encounter.worldWidth - 32);
}

function attackBox(hero: HeroState, range: number, height = 90): Rect {
  const body = heroRect(hero);
  return {
    x: hero.facing === 1 ? body.x + body.width - 4 : body.x - range + 4,
    y: body.y + 8,
    width: range,
    height,
  };
}

function damageGolemsInBox(state: GameState, box: Rect, damage: number): void {
  for (const golem of state.golems) {
    if (!golem.alive) {
      continue;
    }
    const golemRect: Rect = { x: golem.x - 28, y: golem.y - 72, width: 56, height: 72 };
    if (!rectsOverlap(box, golemRect)) {
      continue;
    }
    golem.health = Math.max(0, golem.health - damage);
    golem.hitFlash = 0.18;
    if (golem.health === 0) {
      golem.alive = false;
      state.message = "Stone golem shattered.";
    }
  }
}

function hitBossWeakPoint(state: GameState, hero: HeroState, damage: number, encounter: EncounterDefinition): void {
  if (!state.boss.active) {
    return;
  }

  const weakPoint: Rect = {
    x: encounter.bossArena.weakPointX - 64,
    y: encounter.bossArena.weakPointY - 64,
    width: 128,
    height: 128,
  };
  const box = attackBox(hero, 110, 120);
  if (!rectsOverlap(box, weakPoint)) {
    return;
  }

  if (state.boss.phase === "finisher") {
    if (hero.kind === "herosauro" && state.boss.finisherStep === 0) {
      state.boss.finisherStep = 1;
      state.boss.finisherTimer = 5;
      state.prompt = "Switch! Super Boxy can finish the opening.";
    } else if (hero.kind === "superBoxy" && state.boss.finisherStep === 1) {
      state.boss.finisherStep = 2;
      state.boss.phase = "defeated";
      state.boss.active = true;
      state.boss.locked = false;
      state.prompt = "The titan falls back into the Douro.";
    }
    return;
  }

  if (!state.boss.weakPointOpen) {
    return;
  }

  state.boss.health = Math.max(0, state.boss.health - damage);
  state.boss.weakPointOpen = false;
  state.boss.staggerTimer = 0;
  state.boss.telegraphTimer = 1.15;
  state.message = "Direct hit on Adamastor's brow.";
}

function breakCrates(state: GameState, box: Rect): void {
  for (const breakable of state.breakables) {
    if (breakable.broken || !rectsOverlap(box, breakable)) {
      continue;
    }
    breakable.broken = true;
  }
}

function resolveHeroAttacks(state: GameState, input: InputFrame, encounter: EncounterDefinition): void {
  const hero = state.heroes[state.activeHero];
  const spec = HERO_SPECS[hero.kind];
  if (hero.isDown) {
    return;
  }

  if (input.pressed.lightAttack && hero.abilities.attackCooldown <= 0) {
    const comboReset = hero.abilities.comboTimer <= 0;
    if (hero.kind === "superBoxy") {
      hero.comboStep = comboReset ? 0 : (hero.comboStep + 1) % 3;
      hero.attackStyle = hero.comboStep === 2 ? "finisher" : "combo";
      hero.abilities.comboTimer = 0.6;
      hero.abilities.attackCooldown = hero.comboStep === 2 ? 0.38 : 0.22;
      hero.attackTimer = 0.22;
    } else {
      hero.attackStyle = "attack";
      hero.abilities.attackCooldown = 0.48;
      hero.attackTimer = 0.28;
    }

    const damage = hero.kind === "superBoxy" ? (hero.comboStep === 2 ? 2 : spec.lightDamage) : spec.lightDamage;
    const box = attackBox(hero, spec.lightRange, hero.kind === "herosauro" ? 100 : 84);
    damageGolemsInBox(state, box, damage);
    hitBossWeakPoint(state, hero, damage, encounter);
    if (hero.kind === "herosauro") {
      breakCrates(state, box);
    }
  }

  if (input.pressed.special && hero.abilities.specialCooldown <= 0) {
    hero.abilities.specialCooldown = hero.kind === "herosauro" ? 6.2 : 5.2;
    hero.specialTimer = 0.4;
    if (hero.kind === "herosauro") {
      hero.attackStyle = "roar";
      const box = {
        x: hero.x - 150,
        y: hero.y - 120,
        width: 300,
        height: 180,
      };
      damageGolemsInBox(state, box, 2);
      breakCrates(state, box);
      if (state.boss.phase === "combat") {
        state.boss.weakPointOpen = true;
        state.boss.staggerTimer = Math.max(state.boss.staggerTimer, 1.8);
      }
    } else {
      hero.attackStyle = "uppercut";
      hero.vy = -420;
      const box = {
        x: hero.x - 46,
        y: hero.y - 150,
        width: 92,
        height: 150,
      };
      damageGolemsInBox(state, box, 2);
      hitBossWeakPoint(state, hero, 2, encounter);
    }
  }
}

function updateGolems(state: GameState, dt: number): void {
  const hero = state.heroes[state.activeHero];
  const heroBody = heroRect(hero);

  for (const golem of state.golems) {
    if (!golem.alive) {
      continue;
    }
    golem.hitFlash = Math.max(0, golem.hitFlash - dt);
    golem.attackCooldown = Math.max(0, golem.attackCooldown - dt);
    const direction = hero.x >= golem.x ? 1 : -1;
    golem.facing = direction;
    golem.vx = direction * 65;
    golem.x = clamp(golem.x + golem.vx * dt, golem.patrolMin, golem.patrolMax);

    const golemRect: Rect = { x: golem.x - 28, y: golem.y - 72, width: 56, height: 72 };
    if (golem.attackCooldown <= 0 && rectsOverlap(heroBody, golemRect)) {
      golem.attackCooldown = 1.2;
      applyDamageToHero(state, state.activeHero, 10, "The golems punish reckless rushing.");
    }
  }
}

function updateHazards(state: GameState, dt: number): void {
  const hero = state.heroes[state.activeHero];
  const body = heroRect(hero);
  for (const hazard of state.hazards) {
    hazard.timer -= dt;
    if (hazard.timer <= 0) {
      hazard.active = !hazard.active;
      hazard.timer = hazard.active ? hazard.activeDuration : hazard.interval;
    }
    if (hazard.active && rectsOverlap(body, hazard)) {
      applyDamageToHero(state, state.activeHero, hazard.damage, "Bridge hazards are telegraphed. Read them early.");
    }
  }
}

function nextBossPattern(patternIndex: number): BossPattern {
  return patternIndex % 2 === 0 ? "slam" : "sweep";
}

function applyBossAttack(state: GameState, encounter: EncounterDefinition): void {
  const hero = state.heroes[state.activeHero];
  const rect = heroRect(hero);
  if (state.boss.pattern === "slam") {
    const zoneX = encounter.bossArena.slamZones[state.boss.patternIndex % encounter.bossArena.slamZones.length];
    const danger: Rect = { x: zoneX - 80, y: 440, width: 160, height: 180 };
    if (rectsOverlap(rect, danger)) {
      applyDamageToHero(state, state.activeHero, 18, "Roll through the fist impact.");
    }
  } else {
    const sweep: Rect = {
      x: encounter.bossArena.start + 40,
      y: encounter.bossArena.sweepY - 56,
      width: encounter.bossArena.end - encounter.bossArena.start - 80,
      height: 56,
    };
    const jumpingClear = hero.vy < -100 || rect.y + rect.height < sweep.y + 6;
    if (rectsOverlap(rect, sweep) && !jumpingClear) {
      applyDamageToHero(state, state.activeHero, 14, "Jump the sweeping arm or dodge clean through it.");
    }
  }
}

function updateBoss(state: GameState, encounter: EncounterDefinition, dt: number): void {
  const hero = state.heroes[state.activeHero];

  if (!state.boss.active && hero.x >= encounter.bossArena.start - 120) {
    state.boss.active = true;
    state.boss.locked = true;
    state.boss.phase = "bridgeShake";
    state.boss.shakeTimer = 2.2;
    state.message = "Adamastor rises from the Douro.";
  }

  if (!state.boss.active) {
    return;
  }

  hero.x = clamp(hero.x, encounter.bossArena.start + 32, encounter.bossArena.end - 32);

  if (state.boss.phase === "bridgeShake") {
    state.boss.shakeTimer = Math.max(0, state.boss.shakeTimer - dt);
    if (state.boss.shakeTimer <= 0) {
      state.boss.phase = "combat";
      state.boss.pattern = nextBossPattern(state.boss.patternIndex);
      state.boss.telegraphTimer = 1.1;
    }
    return;
  }

  if (state.boss.phase === "combat") {
    if (state.boss.health <= 4) {
      state.boss.phase = "finisher";
      state.boss.finisherTimer = 5;
      state.boss.weakPointOpen = false;
      state.boss.telegraphTimer = 0;
      state.boss.staggerTimer = 0;
      return;
    }

    if (state.boss.weakPointOpen) {
      state.boss.staggerTimer = Math.max(0, state.boss.staggerTimer - dt);
      if (state.boss.staggerTimer <= 0) {
        state.boss.weakPointOpen = false;
        state.boss.patternIndex += 1;
        state.boss.pattern = nextBossPattern(state.boss.patternIndex);
        state.boss.telegraphTimer = 1.15;
      }
      return;
    }

    state.boss.telegraphTimer = Math.max(0, state.boss.telegraphTimer - dt);
    if (state.boss.telegraphTimer <= 0) {
      applyBossAttack(state, encounter);
      state.boss.weakPointOpen = true;
      state.boss.staggerTimer = 1.6;
    }
    return;
  }

  if (state.boss.phase === "finisher") {
    state.boss.finisherTimer = Math.max(0, state.boss.finisherTimer - dt);
    if (state.boss.finisherTimer <= 0) {
      state.boss.finisherStep = 0;
      state.boss.finisherTimer = 5;
    }
    return;
  }

  if (state.boss.phase === "defeated" && Object.values(state.heroes).every((heroState) => !heroState.isDown)) {
    state.status = "victory";
    state.activeSection = "victory";
    state.objective = encounter.objectiveText.victory;
    state.message = "Primal Roar unlocked for the next chapter.";
  }
}

function updatePickups(state: GameState): void {
  const hero = state.heroes[state.activeHero];
  const body = heroRect(hero);
  for (const pickup of state.pickups) {
    if (pickup.collected) {
      continue;
    }
    const pickupRect: Rect = {
      x: pickup.x - 18,
      y: pickup.y - 18,
      width: 36,
      height: 36,
    };
    if (!rectsOverlap(body, pickupRect)) {
      continue;
    }
    pickup.collected = true;
    if (pickup.kind === "tostao") {
      state.collectibles.tostoes += 1;
    } else if (pickup.kind === "tile") {
      state.collectibles.tileFragments += 1;
    } else if (pickup.letter) {
      state.collectibles.letters.push(pickup.letter);
    }
  }
}

function maybeSwapHero(state: GameState, input: InputFrame): void {
  if (!input.pressed.switchHero || state.swapCooldown > 0) {
    return;
  }

  const nextHeroKind = getOtherHero(state.activeHero);
  if (state.heroes[nextHeroKind].isDown) {
    return;
  }

  const currentHero = state.heroes[state.activeHero];
  const nextHero = state.heroes[nextHeroKind];
  nextHero.x = currentHero.x;
  nextHero.y = currentHero.y;
  nextHero.vx = currentHero.vx;
  nextHero.vy = currentHero.vy;
  nextHero.facing = currentHero.facing;
  nextHero.onGround = currentHero.onGround;
  state.activeHero = nextHeroKind;
  state.swapCooldown = 0.55;
}

function regenInactiveHero(state: GameState, dt: number): void {
  const inactive = state.heroes[getOtherHero(state.activeHero)];
  if (inactive.isDown) {
    return;
  }
  inactive.health = clamp(inactive.health + 10 * dt, 0, inactive.maxHealth);
}

function handleOutOfBounds(state: GameState, encounter: EncounterDefinition): GameState | null {
  const hero = state.heroes[state.activeHero];
  if (hero.y <= encounter.worldHeight + 140) {
    return null;
  }
  return resetToCheckpoint(state, encounter);
}

function updateCameraTarget(state: GameState, encounter: EncounterDefinition): void {
  const hero = state.heroes[state.activeHero];
  state.cameraTargetX = clamp(hero.x + hero.facing * 180, 240, encounter.worldWidth - 240);
}

export function stepGameState(
  state: GameState,
  input: InputFrame,
  encounter: EncounterDefinition,
  dt: number,
): GameState {
  const next = structuredClone(state) as GameState;

  if (next.status === "menu" && input.pressed.interact) {
    next.status = "playing";
  }

  if ((next.status === "playing" || next.status === "paused") && input.pressed.pause) {
    next.status = next.status === "playing" ? "paused" : "playing";
  }

  if (next.status !== "playing") {
    updateCameraTarget(next, encounter);
    return next;
  }

  next.time += dt;
  next.swapCooldown = Math.max(0, next.swapCooldown - dt);

  for (const hero of Object.values(next.heroes)) {
    tickHeroTimers(hero, dt);
  }

  maybeSwapHero(next, input);
  updateHeroMovement(next, input, encounter, dt);
  const checkpointReset = handleOutOfBounds(next, encounter);
  if (checkpointReset) {
    return checkpointReset;
  }

  resolveHeroAttacks(next, input, encounter);
  regenInactiveHero(next, dt);
  updateGolems(next, dt);
  updateHazards(next, dt);
  updateBoss(next, encounter, dt);
  reviveHeroes(next, dt);
  syncInactiveHeroPosition(next);
  updatePickups(next);
  maybeCaptureCheckpoint(next, encounter);
  updateObjectiveText(next, encounter);
  updateCameraTarget(next, encounter);

  return next;
}

export function createViewModel(state: GameState, encounter: EncounterDefinition): ViewModel {
  return {
    status: state.status,
    encounterName: encounter.name,
    activeHero: state.activeHero,
    swapCooldown: state.swapCooldown,
    objective: state.objective,
    prompt: state.prompt,
    message: state.message,
    cameraTargetX: state.cameraTargetX,
    collectibles: state.collectibles,
    heroes: {
      herosauro: {
        kind: "herosauro",
        x: state.heroes.herosauro.x,
        y: state.heroes.herosauro.y,
        health: state.heroes.herosauro.health,
        maxHealth: state.heroes.herosauro.maxHealth,
        active: state.activeHero === "herosauro",
        isDown: state.heroes.herosauro.isDown,
        facing: state.heroes.herosauro.facing,
        attackStyle: state.heroes.herosauro.attackStyle,
        invulnerability: state.heroes.herosauro.abilities.invulnerability,
      },
      superBoxy: {
        kind: "superBoxy",
        x: state.heroes.superBoxy.x,
        y: state.heroes.superBoxy.y,
        health: state.heroes.superBoxy.health,
        maxHealth: state.heroes.superBoxy.maxHealth,
        active: state.activeHero === "superBoxy",
        isDown: state.heroes.superBoxy.isDown,
        facing: state.heroes.superBoxy.facing,
        attackStyle: state.heroes.superBoxy.attackStyle,
        invulnerability: state.heroes.superBoxy.abilities.invulnerability,
      },
    },
    boss: {
      active: state.boss.active,
      phase: state.boss.phase,
      health: state.boss.health,
      maxHealth: state.boss.maxHealth,
      weakPointOpen: state.boss.weakPointOpen,
      pattern: state.boss.pattern,
      telegraphTimer: state.boss.telegraphTimer,
      staggerTimer: state.boss.staggerTimer,
      finisherStep: state.boss.finisherStep,
    },
    golems: state.golems,
    hazards: state.hazards,
    pickups: state.pickups,
    breakables: state.breakables,
  };
}
