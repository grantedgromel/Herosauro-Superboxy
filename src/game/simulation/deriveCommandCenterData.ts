import type {
  AlertItem,
  DashboardNavSection,
  DashboardSectionId,
  DashboardTone,
  EncounterDefinition,
  GameState,
  HeroKind,
  HeroProfile,
  RunSummary,
  UpcomingItem,
} from "../types";

const SECTION_LABELS: Record<DashboardSectionId, string> = {
  overview: "Overview",
  route: "Route",
  threats: "Threats",
  boss: "Boss",
};

const HERO_ROLE_TAGS: Record<
  HeroKind,
  HeroProfile["roleTags"]
> = {
  herosauro: [
    { label: "Power", value: "High" },
    { label: "Mobility", value: "Low" },
    { label: "Survivability", value: "High" },
  ],
  superBoxy: [
    { label: "Power", value: "Medium" },
    { label: "Mobility", value: "High" },
    { label: "Survivability", value: "Low" },
  ],
};

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function formatElapsed(seconds: number): string {
  const safeSeconds = Math.max(0, Math.floor(seconds));
  const minutes = Math.floor(safeSeconds / 60);
  const remainder = safeSeconds % 60;
  return `${minutes}:${remainder.toString().padStart(2, "0")}`;
}

function formatSeconds(seconds: number): string {
  return `${Math.max(0, seconds).toFixed(1)}s`;
}

function formatDistance(distance: number): string {
  return distance <= 0 ? "Live" : `${Math.round(distance)}m`;
}

function humanizeCheckpointId(id: string): string {
  if (id === "cp-start") {
    return "Start Anchor";
  }
  if (id === "cp-mid") {
    return "Mid Anchor";
  }
  if (id === "cp-boss") {
    return "Boss Anchor";
  }

  return id
    .replace(/^cp-/, "")
    .split("-")
    .map((token) => token.charAt(0).toUpperCase() + token.slice(1))
    .join(" ");
}

function liveSectionId(state: GameState): DashboardSectionId {
  switch (state.activeSection) {
    case "hazard":
      return "threats";
    case "warmup":
      return "route";
    case "boss":
      return "boss";
    case "tutorial":
    case "victory":
    default:
      return "overview";
  }
}

function bossStatusLabel(state: GameState, encounter: EncounterDefinition, heroX: number): string {
  if (state.status === "victory" || state.boss.phase === "defeated") {
    return "Objective secured";
  }

  if (!state.boss.active) {
    const approach = clamp(
      (heroX - encounter.startX) / Math.max(1, encounter.bossArena.start - encounter.startX),
      0,
      1,
    );
    if (approach >= 0.92) {
      return "Arena near";
    }
    return "Approach window";
  }

  if (state.boss.phase === "bridgeShake") {
    return "Rise sequence";
  }

  if (state.boss.phase === "finisher") {
    return "Finisher live";
  }

  if (state.boss.weakPointOpen) {
    return "Weak point open";
  }

  return "Telegraph live";
}

function bossReadinessPercent(state: GameState, encounter: EncounterDefinition, heroX: number): number {
  if (state.status === "victory" || state.boss.phase === "defeated") {
    return 100;
  }

  if (!state.boss.active) {
    return Math.round(
      clamp(
        (heroX - encounter.startX) / Math.max(1, encounter.bossArena.start - encounter.startX),
        0,
        1,
      ) * 100,
    );
  }

  if (state.boss.phase === "bridgeShake") {
    return 82;
  }

  if (state.boss.phase === "finisher") {
    return 96;
  }

  return Math.round(((state.boss.maxHealth - state.boss.health) / Math.max(1, state.boss.maxHealth)) * 100);
}

export function deriveRunSummary(state: GameState, encounter: EncounterDefinition): RunSummary {
  const hero = state.heroes[state.activeHero];
  const collectiblesFound = state.pickups.filter((pickup) => pickup.collected).length;
  const collectiblesTotal = state.pickups.length;
  const liveSection = liveSectionId(state);

  return {
    progressPercent: Math.round(
      clamp((hero.x - encounter.startX) / Math.max(1, encounter.worldWidth - encounter.startX), 0, 1) * 100,
    ),
    elapsedLabel: formatElapsed(state.time),
    checkpointLabel: humanizeCheckpointId(state.checkpoint.lastId),
    collectiblesFound,
    collectiblesTotal,
    collectiblesLabel: `${collectiblesFound}/${collectiblesTotal} secured`,
    bossReadinessPercent: bossReadinessPercent(state, encounter, hero.x),
    bossStatus: bossStatusLabel(state, encounter, hero.x),
    activeSectionLabel: SECTION_LABELS[liveSection],
  };
}

export function deriveNavSections(state: GameState, encounter: EncounterDefinition): DashboardNavSection[] {
  const hero = state.heroes[state.activeHero];
  const liveId = liveSectionId(state);
  const nextCheckpoint = encounter.checkpoints.find((checkpoint) => checkpoint.id !== state.checkpoint.lastId && checkpoint.x > hero.x);
  const activeHazard = state.hazards.find((hazard) => hazard.active);

  return [
    {
      id: "overview",
      label: SECTION_LABELS.overview,
      live: liveId === "overview",
      available: true,
      note:
        state.status === "menu"
          ? "Briefing"
          : state.status === "paused"
            ? "Paused"
            : state.status === "victory"
              ? "Clear"
              : "Live",
    },
    {
      id: "route",
      label: SECTION_LABELS.route,
      live: liveId === "route",
      available: true,
      note: nextCheckpoint ? formatDistance(nextCheckpoint.x - hero.x) : state.status === "victory" ? "Complete" : "Clear",
    },
    {
      id: "threats",
      label: SECTION_LABELS.threats,
      live: liveId === "threats",
      available: true,
      note: activeHazard ? "Hot" : hero.x >= 820 ? "Ahead" : "Quiet",
    },
    {
      id: "boss",
      label: SECTION_LABELS.boss,
      live: liveId === "boss",
      available: true,
      note: state.boss.active ? bossStatusLabel(state, encounter, hero.x) : hero.x >= encounter.bossArena.start - 520 ? "Near" : "Dormant",
    },
  ];
}

function heroTone(state: GameState, kind: HeroKind): DashboardTone {
  const hero = state.heroes[kind];
  const healthPercent = (hero.health / Math.max(1, hero.maxHealth)) * 100;
  if (hero.isDown || healthPercent <= 28) {
    return "critical";
  }
  if (healthPercent <= 55 || (kind === state.activeHero && (state.activeSection === "hazard" || state.boss.active))) {
    return "warning";
  }
  return healthPercent >= 80 ? "positive" : "neutral";
}

function heroCondition(state: GameState, kind: HeroKind): string {
  const hero = state.heroes[kind];
  const healthPercent = (hero.health / Math.max(1, hero.maxHealth)) * 100;
  if (hero.isDown) {
    return "Downed";
  }
  if (healthPercent <= 28) {
    return "Critical";
  }
  if (healthPercent <= 55 || (kind === state.activeHero && state.boss.active)) {
    return "Pressured";
  }
  return "Healthy";
}

function heroReadiness(state: GameState, kind: HeroKind): string {
  const hero = state.heroes[kind];
  if (hero.isDown) {
    return `Revive ${formatSeconds(hero.reviveTimer)}`;
  }
  if (kind === state.activeHero && state.swapCooldown > 0) {
    return `Swap ${formatSeconds(state.swapCooldown)}`;
  }
  if (hero.abilities.specialCooldown > 0 || hero.abilities.dodgeCooldown > 0) {
    return "Cooldown pressure";
  }
  if (hero.abilities.specialCooldown <= 0) {
    return "Special ready";
  }
  return "System ready";
}

export function deriveHeroProfiles(state: GameState): HeroProfile[] {
  return (Object.keys(state.heroes) as HeroKind[]).map((kind) => {
    const hero = state.heroes[kind];
    return {
      kind,
      displayName: hero.displayName,
      active: state.activeHero === kind,
      isDown: hero.isDown,
      healthPercent: Math.round((hero.health / Math.max(1, hero.maxHealth)) * 100),
      condition: heroCondition(state, kind),
      readiness: heroReadiness(state, kind),
      tone: heroTone(state, kind),
      roleTags: HERO_ROLE_TAGS[kind],
    };
  });
}

function pushAlert(alerts: AlertItem[], alert: AlertItem): void {
  if (alerts.some((existing) => existing.id === alert.id)) {
    return;
  }
  alerts.push(alert);
}

function hazardRiskLive(state: GameState, encounter: EncounterDefinition): boolean {
  const hero = state.heroes[state.activeHero];
  return state.hazards.some((hazard) => hazard.active && hazard.x + hazard.width >= hero.x - 80 && hazard.x <= hero.x + 200) ||
    (state.activeSection === "hazard" && hero.x < encounter.bossArena.start);
}

export function deriveAlerts(state: GameState, encounter: EncounterDefinition): AlertItem[] {
  const alerts: AlertItem[] = [];

  if (state.status === "victory") {
    pushAlert(alerts, {
      id: "objective-secured",
      label: "Objective secured",
      detail: "Run cleared and Adamastor neutralized.",
      tone: "positive",
    });
  } else if (state.status === "gameOver") {
    pushAlert(alerts, {
      id: "run-lost",
      label: "Run lost",
      detail: "Both heroes are down. Reset the route.",
      tone: "critical",
    });
  } else if (state.status === "paused") {
    pushAlert(alerts, {
      id: "paused",
      label: "Run paused",
      detail: "Simulation clock is halted.",
      tone: "neutral",
    });
  } else if (state.status === "menu") {
    pushAlert(alerts, {
      id: "briefing-ready",
      label: "Briefing ready",
      detail: "Systems are standing by for launch.",
      tone: "neutral",
    });
  }

  if (Object.values(state.heroes).some((hero) => hero.isDown)) {
    pushAlert(alerts, {
      id: "teammate-down",
      label: "Teammate down",
      detail: "Protect the lane until the revive window closes.",
      tone: "critical",
    });
  }

  if (state.message.toLowerCase().includes("checkpoint")) {
    pushAlert(alerts, {
      id: "checkpoint",
      label: "Checkpoint secured",
      detail: state.message,
      tone: "positive",
    });
  }

  if (state.boss.phase === "finisher") {
    pushAlert(alerts, {
      id: "finisher-live",
      label: "Finisher live",
      detail: "Tag the brothers in sequence to close the fight.",
      tone: "warning",
    });
  } else if (state.boss.weakPointOpen) {
    pushAlert(alerts, {
      id: "weak-point-open",
      label: "Weak point open",
      detail: "Strike before the window shuts.",
      tone: "positive",
    });
  } else if (state.boss.active && state.boss.telegraphTimer > 0) {
    pushAlert(alerts, {
      id: "boss-telegraph",
      label: "Boss telegraph live",
      detail: `Impact forecast in ${formatSeconds(state.boss.telegraphTimer)}.`,
      tone: "warning",
    });
  }

  if (hazardRiskLive(state, encounter)) {
    pushAlert(alerts, {
      id: "risk-rising",
      label: "Risk rising",
      detail: "Hazard timing is the main failure point here.",
      tone: "warning",
    });
  }

  if (!alerts.length) {
    pushAlert(alerts, {
      id: "systems-nominal",
      label: "Systems nominal",
      detail: "Route is stable and both heroes are mission-ready.",
      tone: "positive",
    });
  }

  return alerts.slice(0, 3);
}

interface UpcomingCandidate extends UpcomingItem {
  distance: number;
}

function bossUpcoming(state: GameState, encounter: EncounterDefinition, heroX: number): UpcomingCandidate | null {
  if (state.boss.active) {
    if (state.boss.phase === "bridgeShake") {
      return {
        id: "boss-rise",
        kind: "boss",
        label: "Rise sequence",
        detail: "Arena lock is active while Adamastor surfaces.",
        distanceLabel: formatSeconds(state.boss.shakeTimer),
        tone: "warning",
        distance: 0,
      };
    }

    if (state.boss.phase === "finisher") {
      return {
        id: "boss-finisher",
        kind: "boss",
        label: "Finisher chain",
        detail: "Herosauro leads, Super Boxy closes.",
        distanceLabel: formatSeconds(state.boss.finisherTimer),
        tone: "warning",
        distance: 0,
      };
    }

    if (state.boss.weakPointOpen) {
      return {
        id: "boss-window",
        kind: "boss",
        label: "Weak point window",
        detail: "Damage is live on the brow.",
        distanceLabel: formatSeconds(state.boss.staggerTimer),
        tone: "positive",
        distance: 0,
      };
    }

    return {
      id: "boss-telegraph",
      kind: "boss",
      label: "Boss telegraph",
      detail: state.boss.pattern === "slam" ? "Slam lane is charging." : "Sweep lane is charging.",
      distanceLabel: formatSeconds(state.boss.telegraphTimer),
      tone: "warning",
      distance: 0,
    };
  }

  const distance = encounter.bossArena.start - heroX;
  if (distance <= 700) {
    return {
      id: "boss-gate",
      kind: "boss",
      label: "Arena trigger",
      detail: "Boss engagement begins at the final dock span.",
      distanceLabel: formatDistance(distance),
      tone: "neutral",
      distance,
    };
  }

  return null;
}

export function deriveUpcoming(state: GameState, encounter: EncounterDefinition): UpcomingItem[] {
  const hero = state.heroes[state.activeHero];
  const candidates: UpcomingCandidate[] = [];

  for (const checkpoint of encounter.checkpoints) {
    if (checkpoint.id === state.checkpoint.lastId || checkpoint.x <= hero.x) {
      continue;
    }
    candidates.push({
      id: checkpoint.id,
      kind: "checkpoint",
      label: humanizeCheckpointId(checkpoint.id),
      detail: "Respawn anchor and route save.",
      distanceLabel: formatDistance(checkpoint.x - hero.x),
      tone: "positive",
      distance: checkpoint.x - hero.x,
    });
    break;
  }

  for (const hazard of state.hazards) {
    if (hazard.x + hazard.width < hero.x - 40) {
      continue;
    }
    const distance = Math.max(0, hazard.x - hero.x);
    candidates.push({
      id: hazard.id,
      kind: "hazard",
      label: hazard.kind === "fallingRock" ? "Falling rock lane" : "Wave burst lane",
      detail: hazard.active ? "Damage field is active." : `Cycles every ${formatSeconds(hazard.interval)}.`,
      distanceLabel: hazard.active ? "Live" : formatDistance(distance),
      tone: hazard.active ? "warning" : "neutral",
      distance,
    });
    break;
  }

  for (const breakable of state.breakables) {
    if (breakable.broken || breakable.x + breakable.width < hero.x - 20) {
      continue;
    }
    const distance = Math.max(0, breakable.x - hero.x);
    candidates.push({
      id: breakable.id,
      kind: "breakable",
      label: "Breakable cache",
      detail: "Herosauro can break this lane open.",
      distanceLabel: formatDistance(distance),
      tone: "neutral",
      distance,
    });
    break;
  }

  const bossCandidate = bossUpcoming(state, encounter, hero.x);
  if (bossCandidate) {
    candidates.push(bossCandidate);
  }

  return candidates
    .sort((left, right) => left.distance - right.distance)
    .slice(0, 3)
    .map(({ distance: _distance, ...item }) => item);
}

