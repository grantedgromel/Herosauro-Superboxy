import { gameBus } from "../src/game/events";
import { createEmptyInputFrame } from "../src/game/input/actions";
import { createGameState } from "../src/game/simulation/createGameState";
import { createViewModel, stepGameState } from "../src/game/simulation/updateGameState";
import { stage1Encounter } from "../src/game/content/encounters/stage1";
import { createHudController } from "../src/ui/hud";

function renderState(state = createGameState(stage1Encounter, "playing")) {
  return createViewModel(state, stage1Encounter);
}

describe("command center view model", () => {
  it("includes command-center telemetry for a fresh run", () => {
    const view = renderState();

    expect(view.navSections.map((section) => section.label)).toEqual(["Overview", "Route", "Threats", "Boss"]);
    expect(view.runSummary.checkpointLabel).toBe("Start Anchor");
    expect(view.runSummary.collectiblesLabel).toBe("0/21 secured");
    expect(view.heroProfiles).toHaveLength(2);
    expect(view.heroProfiles[0].roleTags.map((tag) => tag.label)).toEqual(["Power", "Mobility", "Survivability"]);
    expect(view.alerts[0].label).toBe("Systems nominal");
    expect(view.upcoming.some((item) => item.kind === "checkpoint")).toBe(true);
  });

  it("surfaces hazard pressure with alerts and upcoming threat timing", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "superBoxy";
    state.heroes.superBoxy.x = 1180;
    state.heroes.superBoxy.y = 620;
    state.hazards[0].active = true;
    state.hazards[0].timer = 0.4;

    const next = stepGameState(state, createEmptyInputFrame(), stage1Encounter, 1 / 60);
    const view = createViewModel(next, stage1Encounter);

    expect(view.navSections.find((section) => section.id === "threats")?.live).toBe(true);
    expect(view.alerts.some((alert) => alert.label === "Risk rising")).toBe(true);
    expect(view.upcoming.some((item) => item.kind === "hazard" && item.distanceLabel === "Live")).toBe(true);
  });

  it("reports checkpoint capture in the run summary and alerts", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "superBoxy";
    state.heroes.superBoxy.x = 1660;
    state.heroes.superBoxy.y = 520;

    const next = stepGameState(state, createEmptyInputFrame(), stage1Encounter, 1 / 60);
    const view = createViewModel(next, stage1Encounter);

    expect(view.runSummary.checkpointLabel).toBe("Mid Anchor");
    expect(view.alerts.some((alert) => alert.label === "Checkpoint secured")).toBe(true);
  });

  it("tracks boss telegraphs as command-center alerts", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "herosauro";
    state.heroes.herosauro.x = stage1Encounter.bossArena.start + 32;
    state.heroes.herosauro.y = 620;
    state.heroes.superBoxy.x = stage1Encounter.bossArena.start + 32;
    state.heroes.superBoxy.y = 620;
    state.activeSection = "boss";
    state.boss.active = true;
    state.boss.phase = "combat";
    state.boss.pattern = "slam";
    state.boss.telegraphTimer = 1.1;

    const view = createViewModel(state, stage1Encounter);

    expect(view.alerts.some((alert) => alert.label === "Boss telegraph live")).toBe(true);
    expect(view.upcoming.find((item) => item.kind === "boss")?.label).toBe("Boss telegraph");
  });

  it("surfaces weak-point openings and downed hero states", () => {
    const state = createGameState(stage1Encounter, "playing");
    state.activeHero = "superBoxy";
    state.activeSection = "boss";
    state.boss.active = true;
    state.boss.phase = "combat";
    state.boss.weakPointOpen = true;
    state.boss.staggerTimer = 1.6;
    state.heroes.herosauro.isDown = true;
    state.heroes.herosauro.reviveTimer = 8.2;

    const view = createViewModel(state, stage1Encounter);

    expect(view.alerts.some((alert) => alert.label === "Weak point open")).toBe(true);
    expect(view.alerts.some((alert) => alert.label === "Teammate down")).toBe(true);
    expect(view.heroProfiles.find((profile) => profile.kind === "herosauro")?.condition).toBe("Downed");
  });

  it("reports victory as a secured objective", () => {
    const state = createGameState(stage1Encounter, "victory");
    state.activeSection = "victory";
    state.boss.phase = "defeated";

    const view = createViewModel(state, stage1Encounter);

    expect(view.runSummary.bossReadinessPercent).toBe(100);
    expect(view.runSummary.bossStatus).toBe("Objective secured");
    expect(view.alerts[0].label).toBe("Objective secured");
  });
});

describe("command center hud", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("renders nav pills and lets the user switch focus panels", () => {
    const root = document.createElement("div");
    document.body.appendChild(root);
    const hud = createHudController(root);
    const view = renderState();

    try {
      gameBus.emit("hud:update", view);
      expect(root.querySelectorAll("[data-nav-section]").length).toBe(4);

      const routeButton = root.querySelector<HTMLButtonElement>('[data-nav-section="route"]');
      routeButton?.click();
      gameBus.emit("hud:update", view);

      expect(root.querySelector<HTMLElement>("#detail-heading")?.textContent).toBe("Route");
    } finally {
      hud.destroy();
    }
  });

  it("renders hero condition and alert pills from the command-center state", () => {
    const root = document.createElement("div");
    document.body.appendChild(root);
    const hud = createHudController(root);
    const state = createGameState(stage1Encounter, "playing");
    state.heroes.superBoxy.isDown = true;
    state.heroes.superBoxy.reviveTimer = 9.4;
    state.boss.active = true;
    state.boss.phase = "combat";
    state.boss.weakPointOpen = true;
    state.boss.staggerTimer = 1.6;
    state.activeSection = "boss";

    try {
      gameBus.emit("hud:update", createViewModel(state, stage1Encounter));

      expect(root.querySelector(".hero-card.is-downed")).not.toBeNull();
      expect(root.textContent).toContain("Downed");
      expect(root.textContent).toContain("Weak point open");
    } finally {
      hud.destroy();
    }
  });

  it("switches overlay visibility and report copy across menu, pause, and victory", () => {
    const root = document.createElement("div");
    document.body.appendChild(root);
    const hud = createHudController(root);
    const menuView = createViewModel(createGameState(stage1Encounter, "menu"), stage1Encounter);
    const pausedView = createViewModel(createGameState(stage1Encounter, "paused"), stage1Encounter);
    const victoryState = createGameState(stage1Encounter, "victory");
    victoryState.activeSection = "victory";
    victoryState.boss.phase = "defeated";

    try {
      gameBus.emit("hud:update", menuView);
      expect(root.querySelector("#menu-overlay")?.classList.contains("is-visible")).toBe(true);
      expect(root.textContent).toContain("Run Briefing");

      gameBus.emit("hud:update", pausedView);
      expect(root.querySelector("#pause-overlay")?.classList.contains("is-visible")).toBe(true);
      expect(root.textContent).toContain("Simulation Paused");

      gameBus.emit("hud:update", createViewModel(victoryState, stage1Encounter));
      expect(root.querySelector("#result-overlay")?.classList.contains("is-visible")).toBe(true);
      expect(root.textContent).toContain("Objective secured.");
    } finally {
      hud.destroy();
    }
  });
});

