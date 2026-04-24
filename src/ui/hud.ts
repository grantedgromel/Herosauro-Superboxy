import { gameBus } from "../game/events";
import type {
  DashboardSectionId,
  DashboardTone,
  HeroProfile,
  UpcomingItem,
  ViewModel,
} from "../game/types";

function bossPercent(view: ViewModel): number {
  return Math.max(0, Math.min(100, (view.boss.health / Math.max(1, view.boss.maxHealth)) * 100));
}

function statusLabel(status: ViewModel["status"]): string {
  switch (status) {
    case "menu":
      return "Briefing";
    case "playing":
      return "Live";
    case "paused":
      return "Paused";
    case "victory":
      return "Clear";
    case "gameOver":
      return "Reset";
  }
}

function toneClass(tone: DashboardTone): string {
  return `is-${tone}`;
}

function sectionLabel(view: ViewModel, sectionId: DashboardSectionId): string {
  return view.navSections.find((section) => section.id === sectionId)?.label ?? "Overview";
}

function renderRoleTags(profile: HeroProfile): string {
  return profile.roleTags
    .map(
      (tag) => `
        <div class="role-chip">
          <span class="role-chip__label">${tag.label}</span>
          <span class="role-chip__value">${tag.value}</span>
        </div>
      `,
    )
    .join("");
}

function renderHeroProfile(profile: HeroProfile): string {
  return `
    <article class="cc-card hero-card ${toneClass(profile.tone)} ${profile.active ? "is-active" : ""} ${
      profile.isDown ? "is-downed" : ""
    }">
      <div class="hero-card__top">
        <div>
          <div class="cc-card__eyebrow">${profile.active ? "Active Unit" : "Support Unit"}</div>
          <h3 class="hero-card__title">${profile.displayName}</h3>
        </div>
        <div class="status-tag ${toneClass(profile.tone)}">${profile.condition}</div>
      </div>
      <div class="meter">
        <div class="meter__fill ${toneClass(profile.tone)}" style="width:${profile.healthPercent}%"></div>
      </div>
      <div class="hero-card__meta">
        <span>Health ${profile.healthPercent}%</span>
        <span>${profile.readiness}</span>
      </div>
      <div class="hero-card__roles">
        ${renderRoleTags(profile)}
      </div>
    </article>
  `;
}

function renderAlert(alert: ViewModel["alerts"][number]): string {
  return `
    <div class="signal-pill ${toneClass(alert.tone)}">
      <span class="signal-pill__label">${alert.label}</span>
      <span class="signal-pill__detail">${alert.detail}</span>
    </div>
  `;
}

function renderUpcoming(item: UpcomingItem): string {
  return `
    <li class="detail-list__item">
      <div>
        <div class="detail-list__label">${item.label}</div>
        <div class="detail-list__body">${item.detail}</div>
      </div>
      <div class="detail-list__meta ${toneClass(item.tone)}">${item.distanceLabel}</div>
    </li>
  `;
}

function renderThreatRows(view: ViewModel): string {
  const hazards = view.hazards
    .map((hazard) => ({
      label: hazard.kind === "fallingRock" ? "Falling rock lane" : "Wave burst lane",
      detail: hazard.active ? "Active damage field" : `Next cycle ${hazard.timer.toFixed(1)}s`,
      tone: (hazard.active ? "warning" : "neutral") as DashboardTone,
      active: hazard.active,
    }))
    .map(
      (hazard) => `
        <li class="detail-list__item">
          <div>
            <div class="detail-list__label">${hazard.label}</div>
            <div class="detail-list__body">${hazard.detail}</div>
          </div>
          <div class="detail-list__meta ${toneClass(hazard.tone)}">${hazard.active ? "Live" : "Tracking"}</div>
        </li>
      `,
    )
    .join("");

  return hazards || '<li class="detail-list__item detail-list__item--empty">No active threat lanes.</li>';
}

function renderUpcomingRows(items: UpcomingItem[]): string {
  if (!items.length) {
    return '<li class="detail-list__item detail-list__item--empty">No immediate beats on deck.</li>';
  }
  return items.map(renderUpcoming).join("");
}

function renderDetail(view: ViewModel, sectionId: DashboardSectionId): string {
  const routeItems = view.upcoming.filter((item) => item.kind === "checkpoint" || item.kind === "breakable" || item.kind === "boss");
  const threatItems = view.upcoming.filter((item) => item.kind === "hazard" || item.kind === "boss");
  const bossItems = view.upcoming.filter((item) => item.kind === "boss");

  switch (sectionId) {
    case "route":
      return `
        <div class="detail-grid">
          <section class="cc-card">
            <div class="cc-card__eyebrow">Route Board</div>
            <h3 class="detail-title">Anchor ${view.runSummary.checkpointLabel}</h3>
            <p class="detail-copy">${view.prompt}</p>
            <div class="stat-row">
              <div class="stat-pill">
                <span class="stat-pill__label">Progress</span>
                <span class="stat-pill__value">${view.runSummary.progressPercent}%</span>
              </div>
              <div class="stat-pill">
                <span class="stat-pill__label">Collectibles</span>
                <span class="stat-pill__value">${view.runSummary.collectiblesLabel}</span>
              </div>
            </div>
          </section>
          <section class="cc-card">
            <div class="cc-card__eyebrow">Upcoming</div>
            <ul class="detail-list">${renderUpcomingRows(routeItems)}</ul>
          </section>
        </div>
      `;
    case "threats":
      return `
        <div class="detail-grid">
          <section class="cc-card">
            <div class="cc-card__eyebrow">Threat Board</div>
            <h3 class="detail-title">Hazard timing is live</h3>
            <p class="detail-copy">Read the lane early and protect the active unit through the risk window.</p>
            <div class="signal-strip">
              ${view.alerts.map(renderAlert).join("")}
            </div>
          </section>
          <section class="cc-card">
            <div class="cc-card__eyebrow">Threat Queue</div>
            <ul class="detail-list">${renderThreatRows(view)}${renderUpcomingRows(threatItems)}</ul>
          </section>
        </div>
      `;
    case "boss":
      return `
        <div class="detail-grid">
          <section class="cc-card">
            <div class="cc-card__eyebrow">Boss Board</div>
            <h3 class="detail-title">${view.runSummary.bossStatus}</h3>
            <p class="detail-copy">
              ${view.boss.active ? "Arena lock is active. Read the telegraph, open the brow, and close with the finisher." : "The boss lane is dormant, but the final trigger is already being tracked."}
            </p>
            <div class="metric metric--stacked">
              <div class="metric__label-row">
                <span>Boss health</span>
                <span>${bossPercent(view)}%</span>
              </div>
              <div class="meter">
                <div class="meter__fill is-warning" style="width:${bossPercent(view)}%"></div>
              </div>
            </div>
            <div class="stat-row">
              <div class="stat-pill">
                <span class="stat-pill__label">Phase</span>
                <span class="stat-pill__value">${view.boss.phase}</span>
              </div>
              <div class="stat-pill">
                <span class="stat-pill__label">Pattern</span>
                <span class="stat-pill__value">${view.boss.pattern}</span>
              </div>
            </div>
          </section>
          <section class="cc-card">
            <div class="cc-card__eyebrow">Boss Timing</div>
            <ul class="detail-list">${renderUpcomingRows(bossItems)}</ul>
          </section>
        </div>
      `;
    case "overview":
    default:
      return `
        <div class="detail-grid">
          <section class="cc-card">
            <div class="cc-card__eyebrow">Mission Snapshot</div>
            <h3 class="detail-title">${view.objective}</h3>
            <p class="detail-copy">${view.prompt}</p>
            <div class="stat-row">
              <div class="stat-pill">
                <span class="stat-pill__label">Checkpoint</span>
                <span class="stat-pill__value">${view.runSummary.checkpointLabel}</span>
              </div>
              <div class="stat-pill">
                <span class="stat-pill__label">Elapsed</span>
                <span class="stat-pill__value">${view.runSummary.elapsedLabel}</span>
              </div>
            </div>
          </section>
          <section class="cc-card">
            <div class="cc-card__eyebrow">Signals</div>
            <div class="signal-strip">
              ${view.alerts.map(renderAlert).join("")}
            </div>
          </section>
        </div>
      `;
  }
}

export function createHudController(root: HTMLElement): { destroy(): void } {
  root.innerHTML = `
    <div class="hud">
      <div class="hud__top">
        <section class="cc-card cc-card--brand">
          <div class="cc-card__eyebrow">PE Simulator</div>
          <div class="brand-row">
            <h1>Run Command</h1>
            <span class="status-tag" id="status-pill">Briefing</span>
          </div>
          <div class="brand-copy" id="encounter-name">Stage 1</div>
        </section>

        <section class="cc-card cc-card--metrics">
          <div class="metric-grid">
            <div class="metric">
              <div class="metric__label-row">
                <span>Route</span>
                <span id="progress-value">0%</span>
              </div>
              <div class="meter"><div class="meter__fill is-positive" id="progress-fill"></div></div>
            </div>
            <div class="metric">
              <div class="metric__label-row">
                <span>Checkpoint</span>
                <span id="checkpoint-value">Start Anchor</span>
              </div>
              <div class="metric__sub" id="active-section-value">Overview</div>
            </div>
            <div class="metric">
              <div class="metric__label-row">
                <span>Collectibles</span>
                <span id="collectibles-value">0/0</span>
              </div>
              <div class="metric__sub" id="collectibles-sub">0 secured</div>
            </div>
            <div class="metric">
              <div class="metric__label-row">
                <span>Boss</span>
                <span id="boss-readiness-value">0%</span>
              </div>
              <div class="meter"><div class="meter__fill is-warning" id="boss-readiness-fill"></div></div>
              <div class="metric__sub" id="boss-status">Dormant</div>
            </div>
          </div>
        </section>

        <section class="cc-card cc-card--nav">
          <div class="cc-card__eyebrow">Sections</div>
          <div class="nav-pills" id="nav-sections"></div>
        </section>
      </div>

      <div class="hud__body">
        <aside class="hud__left">
          <section class="cc-card">
            <div class="cc-card__eyebrow">Mission Line</div>
            <h2 class="detail-title" id="objective-text">Master the brothers</h2>
            <p class="detail-copy" id="prompt-text"></p>
          </section>
          <div class="hero-rail" id="hero-profiles"></div>
        </aside>

        <section class="hud__right">
          <section class="cc-card cc-card--detail">
            <div class="detail-head">
              <div>
                <div class="cc-card__eyebrow">Focus Panel</div>
                <h2 class="detail-title" id="detail-heading">Overview</h2>
              </div>
              <div class="detail-head__meta" id="detail-status">Live</div>
            </div>
            <div id="detail-body"></div>
          </section>
        </section>
      </div>

      <section class="cc-card cc-card--ticker">
        <div class="ticker-row">
          <div>
            <div class="cc-card__eyebrow">Event Ticker</div>
            <div class="ticker-copy" id="message-text"></div>
          </div>
          <div class="signal-strip signal-strip--ticker" id="alert-strip"></div>
        </div>
      </section>

      <div class="overlay is-visible" id="menu-overlay">
        <div class="overlay__card">
          <div class="overlay__eyebrow">PE Simulator</div>
          <h1>Run Briefing</h1>
          <p id="briefing-body">
            Route through the dock, stabilize both units, and enter the boss lane with momentum.
          </p>
          <div class="overlay__stats">
            <div class="overlay__stat">
              <span class="overlay__stat-label">Route</span>
              <span class="overlay__stat-value" id="brief-route">0%</span>
            </div>
            <div class="overlay__stat">
              <span class="overlay__stat-label">Collectibles</span>
              <span class="overlay__stat-value" id="brief-collectibles">0/0</span>
            </div>
            <div class="overlay__stat">
              <span class="overlay__stat-label">Boss</span>
              <span class="overlay__stat-value" id="brief-boss">Dormant</span>
            </div>
          </div>
          <div class="overlay__controls">
            <span>Move A/D or arrows</span>
            <span>Jump Space</span>
            <span>Attack J</span>
            <span>Special K</span>
            <span>Dodge L</span>
            <span>Swap Q or Shift</span>
          </div>
          <button class="overlay__button" id="start-button">Launch Run</button>
        </div>
      </div>

      <div class="overlay" id="pause-overlay">
        <div class="overlay__card overlay__card--small">
          <div class="overlay__eyebrow">Simulation Paused</div>
          <h2>Run clock halted.</h2>
          <p id="pause-summary">Progress and boss readiness are frozen until you resume.</p>
          <div class="overlay__actions">
            <button class="overlay__button" id="resume-button">Resume Run</button>
            <button class="overlay__button overlay__button--ghost" id="restart-button">Reset Route</button>
          </div>
        </div>
      </div>

      <div class="overlay" id="result-overlay">
        <div class="overlay__card overlay__card--small">
          <div class="overlay__eyebrow" id="result-label">Run Report</div>
          <h2 id="result-title">Objective secured.</h2>
          <p id="result-body"></p>
          <button class="overlay__button" id="result-button">Run Again</button>
        </div>
      </div>
    </div>
  `;

  const menuOverlay = root.querySelector<HTMLElement>("#menu-overlay");
  const pauseOverlay = root.querySelector<HTMLElement>("#pause-overlay");
  const resultOverlay = root.querySelector<HTMLElement>("#result-overlay");
  const statusPill = root.querySelector<HTMLElement>("#status-pill");
  const encounterName = root.querySelector<HTMLElement>("#encounter-name");
  const progressValue = root.querySelector<HTMLElement>("#progress-value");
  const progressFill = root.querySelector<HTMLElement>("#progress-fill");
  const checkpointValue = root.querySelector<HTMLElement>("#checkpoint-value");
  const activeSectionValue = root.querySelector<HTMLElement>("#active-section-value");
  const collectiblesValue = root.querySelector<HTMLElement>("#collectibles-value");
  const collectiblesSub = root.querySelector<HTMLElement>("#collectibles-sub");
  const bossReadinessValue = root.querySelector<HTMLElement>("#boss-readiness-value");
  const bossReadinessFill = root.querySelector<HTMLElement>("#boss-readiness-fill");
  const bossStatus = root.querySelector<HTMLElement>("#boss-status");
  const navSections = root.querySelector<HTMLElement>("#nav-sections");
  const objectiveText = root.querySelector<HTMLElement>("#objective-text");
  const promptText = root.querySelector<HTMLElement>("#prompt-text");
  const heroProfiles = root.querySelector<HTMLElement>("#hero-profiles");
  const detailHeading = root.querySelector<HTMLElement>("#detail-heading");
  const detailStatus = root.querySelector<HTMLElement>("#detail-status");
  const detailBody = root.querySelector<HTMLElement>("#detail-body");
  const messageText = root.querySelector<HTMLElement>("#message-text");
  const alertStrip = root.querySelector<HTMLElement>("#alert-strip");
  const briefingBody = root.querySelector<HTMLElement>("#briefing-body");
  const briefRoute = root.querySelector<HTMLElement>("#brief-route");
  const briefCollectibles = root.querySelector<HTMLElement>("#brief-collectibles");
  const briefBoss = root.querySelector<HTMLElement>("#brief-boss");
  const pauseSummary = root.querySelector<HTMLElement>("#pause-summary");
  const resultLabel = root.querySelector<HTMLElement>("#result-label");
  const resultTitle = root.querySelector<HTMLElement>("#result-title");
  const resultBody = root.querySelector<HTMLElement>("#result-body");

  let selectedSection: DashboardSectionId | null = null;
  let manualSection = false;
  let lastView: ViewModel | null = null;

  root.querySelector<HTMLButtonElement>("#start-button")?.addEventListener("click", () => {
    gameBus.emit("game:start", undefined);
  });
  root.querySelector<HTMLButtonElement>("#resume-button")?.addEventListener("click", () => {
    gameBus.emit("game:resume", undefined);
  });
  root.querySelector<HTMLButtonElement>("#restart-button")?.addEventListener("click", () => {
    gameBus.emit("game:restart", undefined);
  });
  root.querySelector<HTMLButtonElement>("#result-button")?.addEventListener("click", () => {
    gameBus.emit("game:restart", undefined);
  });

  root.addEventListener("click", (event) => {
    const target = event.target as HTMLElement | null;
    const button = target?.closest<HTMLButtonElement>("[data-nav-section]");
    if (!button) {
      return;
    }
    selectedSection = button.dataset.navSection as DashboardSectionId;
    manualSection = true;
    if (lastView) {
      render(lastView);
    }
  });

  function syncSelectedSection(view: ViewModel): void {
    const liveSection = view.navSections.find((section) => section.live)?.id ?? "overview";
    const hasSelectedSection = selectedSection && view.navSections.some((section) => section.id === selectedSection);
    if (!hasSelectedSection || !manualSection || view.status !== "playing") {
      selectedSection = liveSection;
      manualSection = false;
    }
  }

  function render(view: ViewModel): void {
    lastView = view;
    syncSelectedSection(view);

    const activeSection = selectedSection ?? "overview";
    const sectionMeta = view.navSections.find((section) => section.id === activeSection);

    encounterName!.textContent = view.encounterName;
    statusPill!.textContent = statusLabel(view.status);
    statusPill!.className = `status-tag ${view.status === "gameOver" ? "is-critical" : view.status === "victory" ? "is-positive" : "is-neutral"}`;

    progressValue!.textContent = `${view.runSummary.progressPercent}%`;
    progressFill!.style.width = `${view.runSummary.progressPercent}%`;
    checkpointValue!.textContent = view.runSummary.checkpointLabel;
    activeSectionValue!.textContent = view.runSummary.activeSectionLabel;
    collectiblesValue!.textContent = `${view.runSummary.collectiblesFound}/${view.runSummary.collectiblesTotal}`;
    collectiblesSub!.textContent = view.runSummary.collectiblesLabel;
    bossReadinessValue!.textContent = `${view.runSummary.bossReadinessPercent}%`;
    bossReadinessFill!.style.width = `${view.runSummary.bossReadinessPercent}%`;
    bossStatus!.textContent = view.runSummary.bossStatus;

    objectiveText!.textContent = view.objective;
    promptText!.textContent = view.prompt;
    heroProfiles!.innerHTML = view.heroProfiles.map(renderHeroProfile).join("");
    navSections!.innerHTML = view.navSections
      .map(
        (section) => `
          <button
            type="button"
            class="nav-pill ${section.live ? "is-live" : ""} ${section.id === activeSection ? "is-selected" : ""}"
            data-nav-section="${section.id}"
          >
            <span class="nav-pill__label">${section.label}</span>
            <span class="nav-pill__note">${section.note}</span>
          </button>
        `,
      )
      .join("");

    detailHeading!.textContent = sectionLabel(view, activeSection);
    detailStatus!.textContent = sectionMeta?.note ?? "Live";
    detailBody!.innerHTML = renderDetail(view, activeSection);

    messageText!.textContent = view.message || view.prompt;
    alertStrip!.innerHTML = view.alerts.map(renderAlert).join("");

    briefingBody!.textContent = `Route ${view.runSummary.activeSectionLabel.toLowerCase()} is ready. Keep both units stable and enter the boss lane with a clean resource line.`;
    briefRoute!.textContent = `${view.runSummary.progressPercent}%`;
    briefCollectibles!.textContent = `${view.runSummary.collectiblesFound}/${view.runSummary.collectiblesTotal}`;
    briefBoss!.textContent = view.runSummary.bossStatus;

    pauseSummary!.textContent = `${view.runSummary.progressPercent}% route cleared from ${view.runSummary.checkpointLabel}. Boss board: ${view.runSummary.bossStatus}.`;

    menuOverlay?.classList.toggle("is-visible", view.status === "menu");
    pauseOverlay?.classList.toggle("is-visible", view.status === "paused");

    const resultVisible = view.status === "victory" || view.status === "gameOver";
    resultOverlay?.classList.toggle("is-visible", resultVisible);
    if (view.status === "victory") {
      resultLabel!.textContent = "Run Report";
      resultTitle!.textContent = "Objective secured.";
      resultBody!.textContent = `Finished in ${view.runSummary.elapsedLabel} with ${view.runSummary.collectiblesLabel}. Adamastor was cleared from the board and both units remained recoverable.`;
    } else if (view.status === "gameOver") {
      resultLabel!.textContent = "Run Report";
      resultTitle!.textContent = "Route lost.";
      resultBody!.textContent = `The run collapsed at ${view.runSummary.progressPercent}% route progress from ${view.runSummary.checkpointLabel}. Tighten hazard timing and re-enter the boss lane cleaner.`;
    }
  }

  const unsubscribe = gameBus.on("hud:update", render);

  return {
    destroy() {
      unsubscribe();
      root.innerHTML = "";
    },
  };
}
