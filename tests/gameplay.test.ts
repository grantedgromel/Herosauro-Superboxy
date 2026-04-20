import { stage1Encounter } from "../src/game/content/encounters/stage1";
import { assetManifest } from "../src/game/assets/manifest";
import { createEmptyInputFrame } from "../src/game/input/actions";
import { createGameState } from "../src/game/simulation/createGameState";
import { stepGameState } from "../src/game/simulation/updateGameState";
import { createSceneBridge } from "../src/phaser/adapters/sceneBridge";
import type { InputAction, InputFrame } from "../src/game/types";

function frame(pressed: InputAction[] = [], held: InputAction[] = pressed): InputFrame {
  const base = createEmptyInputFrame();
  for (const action of held) {
    base.held[action] = true;
  }
  for (const action of pressed) {
    base.pressed[action] = true;
    base.held[action] = true;
  }
  return base;
}

describe("gameplay simulation", () => {
  it("supports coyote-time jumping and clamps stage movement", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "superBoxy";
    state.heroes.superBoxy.x = 8;
    state.heroes.superBoxy.y = 620;
    state.heroes.superBoxy.onGround = false;
    state.heroes.superBoxy.coyoteTimer = 0.08;

    const next = stepGameState(state, frame(["jump"]), stage1Encounter, 1 / 60);

    expect(next.heroes.superBoxy.vy).toBeLessThan(0);
    expect(next.heroes.superBoxy.x).toBeGreaterThanOrEqual(32);
  });

  it("prevents rapid swap spam while cooldown is active", () => {
    const state = createGameState(stage1Encounter, "playing");
    const swapped = stepGameState(state, frame(["switchHero"]), stage1Encounter, 1 / 60);
    const secondAttempt = stepGameState(swapped, frame(["switchHero"]), stage1Encounter, 1 / 60);

    expect(swapped.activeHero).toBe("herosauro");
    expect(secondAttempt.activeHero).toBe("herosauro");
    expect(secondAttempt.swapCooldown).toBeGreaterThan(0);
  });

  it("applies invulnerability windows after hazard damage", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "superBoxy";
    state.heroes.superBoxy.x = 1180;
    state.heroes.superBoxy.y = 620;
    state.hazards[0].active = true;
    state.hazards[0].timer = 0.4;

    const damaged = stepGameState(state, createEmptyInputFrame(), stage1Encounter, 1 / 60);
    const damageTaken = damaged.heroes.superBoxy.maxHealth - damaged.heroes.superBoxy.health;
    const damagedAgain = stepGameState(damaged, createEmptyInputFrame(), stage1Encounter, 1 / 60);

    expect(damageTaken).toBeGreaterThan(0);
    expect(damagedAgain.heroes.superBoxy.health).toBe(damaged.heroes.superBoxy.health);
  });

  it("transitions Adamastor from rise to combat to finisher", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "herosauro";
    state.heroes.herosauro.x = stage1Encounter.bossArena.start + 32;
    state.heroes.herosauro.y = 620;
    state.heroes.superBoxy.x = stage1Encounter.bossArena.start + 32;
    state.heroes.superBoxy.y = 620;

    const risen = stepGameState(state, createEmptyInputFrame(), stage1Encounter, 1 / 60);
    expect(risen.boss.phase).toBe("bridgeShake");

    let current = risen;
    for (let index = 0; index < 150; index += 1) {
      current = stepGameState(current, createEmptyInputFrame(), stage1Encounter, 1 / 60);
    }
    expect(current.boss.phase).toBe("combat");

    current.boss.health = 4;
    const finisher = stepGameState(current, createEmptyInputFrame(), stage1Encounter, 1 / 60);
    expect(finisher.boss.phase).toBe("finisher");
  });

  it("resets to the latest checkpoint after falling out of bounds", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "superBoxy";
    state.checkpoint = {
      lastId: "cp-mid",
      x: 1640,
      y: 520,
      bossHealth: 12,
      bossPhase: "dormant",
    };
    state.heroes.superBoxy.y = stage1Encounter.worldHeight + 220;

    const reset = stepGameState(state, createEmptyInputFrame(), stage1Encounter, 1 / 60);
    expect(reset.heroes.superBoxy.x).toBe(1640);
    expect(reset.heroes.superBoxy.y).toBe(520);
  });
});

describe("integration surfaces", () => {
  it("keeps the generated asset manifest stable and unique", () => {
    const keys = Object.values(assetManifest)
      .flat()
      .map((asset) => asset.key);
    expect(new Set(keys).size).toBe(keys.length);
    expect(keys).toContain("hero.herosauro");
    expect(keys).toContain("boss.adamastor.face");
  });

  it("scene bridge supports start, pause, and restart flow", () => {
    const bridge = createSceneBridge(stage1Encounter);
    expect(bridge.getViewModel().status).toBe("menu");

    const started = bridge.start();
    expect(started.status).toBe("playing");

    const paused = bridge.setPaused(true);
    expect(paused.status).toBe("paused");

    const restarted = bridge.restart();
    expect(restarted.status).toBe("playing");
    expect(restarted.collectibles.tostoes).toBe(0);
  });
});
