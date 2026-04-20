import { gameBus } from "../game/events";
import type { ViewModel } from "../game/types";

function heroPercent(view: ViewModel, hero: "herosauro" | "superBoxy"): number {
  const data = view.heroes[hero];
  return Math.max(0, Math.min(100, (data.health / data.maxHealth) * 100));
}

export function createHudController(root: HTMLElement): { destroy(): void } {
  root.innerHTML = `
    <div class="hud">
      <div class="hud__bar hud__bar--left">
        <div class="chip chip--hero" data-hero="herosauro">
          <div class="chip__title">Herosauro</div>
          <div class="bar"><div class="bar__fill" data-fill="herosauro"></div></div>
        </div>
        <div class="chip chip--hero" data-hero="superBoxy">
          <div class="chip__title">Super Boxy</div>
          <div class="bar"><div class="bar__fill" data-fill="superBoxy"></div></div>
        </div>
      </div>

      <div class="hud__bar hud__bar--right">
        <div class="chip chip--objective">
          <div class="chip__eyebrow" id="encounter-name">Stage 1</div>
          <div class="chip__body" id="objective-text">Master the brothers</div>
        </div>
        <div class="chip chip--boss" id="boss-chip">
          <div class="chip__eyebrow">Adamastor</div>
          <div class="bar"><div class="bar__fill bar__fill--boss" id="boss-health"></div></div>
        </div>
      </div>

      <div class="hud__footer">
        <div class="chip chip--prompt">
          <div class="chip__eyebrow">Prompt</div>
          <div class="chip__body" id="prompt-text"></div>
          <div class="chip__hint" id="message-text"></div>
        </div>
        <div class="chip chip--collectibles">
          <div class="chip__eyebrow">Collectibles</div>
          <div class="collectibles" id="collectible-text"></div>
        </div>
      </div>

      <div class="overlay is-visible" id="menu-overlay">
        <div class="overlay__card">
          <div class="overlay__eyebrow">Porto Storybook Prototype</div>
          <h1>Herosauro &amp; Super Boxy</h1>
          <p>
            A retro 2.5D-inspired browser prototype set on the Douro.
            Swap between the brothers, cross a collapsing bridge, and bring down Adamastor.
          </p>
          <div class="overlay__controls">
            <span>Move: A/D or arrows</span>
            <span>Jump: Space</span>
            <span>Attack: J</span>
            <span>Special: K</span>
            <span>Dodge: L</span>
            <span>Swap: Q or Shift</span>
          </div>
          <button class="overlay__button" id="start-button">Begin Stage 1</button>
        </div>
      </div>

      <div class="overlay" id="pause-overlay">
        <div class="overlay__card overlay__card--small">
          <div class="overlay__eyebrow">Paused</div>
          <h2>Hold the line over Porto.</h2>
          <div class="overlay__actions">
            <button class="overlay__button" id="resume-button">Resume</button>
            <button class="overlay__button overlay__button--ghost" id="restart-button">Restart Run</button>
          </div>
        </div>
      </div>

      <div class="overlay" id="result-overlay">
        <div class="overlay__card overlay__card--small">
          <div class="overlay__eyebrow" id="result-label">Victory</div>
          <h2 id="result-title">Porto shines again.</h2>
          <p id="result-body"></p>
          <button class="overlay__button" id="result-button">Run Again</button>
        </div>
      </div>
    </div>
  `;

  const menuOverlay = root.querySelector<HTMLElement>("#menu-overlay");
  const pauseOverlay = root.querySelector<HTMLElement>("#pause-overlay");
  const resultOverlay = root.querySelector<HTMLElement>("#result-overlay");
  const encounterName = root.querySelector<HTMLElement>("#encounter-name");
  const objectiveText = root.querySelector<HTMLElement>("#objective-text");
  const promptText = root.querySelector<HTMLElement>("#prompt-text");
  const messageText = root.querySelector<HTMLElement>("#message-text");
  const collectibleText = root.querySelector<HTMLElement>("#collectible-text");
  const bossChip = root.querySelector<HTMLElement>("#boss-chip");
  const bossHealth = root.querySelector<HTMLElement>("#boss-health");
  const herosauroFill = root.querySelector<HTMLElement>("[data-fill='herosauro']");
  const superBoxyFill = root.querySelector<HTMLElement>("[data-fill='superBoxy']");
  const herosauroChip = root.querySelector<HTMLElement>("[data-hero='herosauro']");
  const superBoxyChip = root.querySelector<HTMLElement>("[data-hero='superBoxy']");
  const resultLabel = root.querySelector<HTMLElement>("#result-label");
  const resultTitle = root.querySelector<HTMLElement>("#result-title");
  const resultBody = root.querySelector<HTMLElement>("#result-body");

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

  const unsubscribe = gameBus.on("hud:update", (view) => {
    encounterName!.textContent = view.encounterName;
    objectiveText!.textContent = view.objective;
    promptText!.textContent = view.prompt;
    messageText!.textContent = view.message;
    collectibleText!.textContent = `Tostoes ${view.collectibles.tostoes} · PORTO ${view.collectibles.letters.join("") || "-----"} · Tiles ${view.collectibles.tileFragments}/6`;

    herosauroFill!.style.width = `${heroPercent(view, "herosauro")}%`;
    superBoxyFill!.style.width = `${heroPercent(view, "superBoxy")}%`;
    bossHealth!.style.width = `${(view.boss.health / Math.max(1, view.boss.maxHealth)) * 100}%`;

    herosauroChip?.classList.toggle("is-active", view.activeHero === "herosauro");
    herosauroChip?.classList.toggle("is-downed", view.heroes.herosauro.isDown);
    superBoxyChip?.classList.toggle("is-active", view.activeHero === "superBoxy");
    superBoxyChip?.classList.toggle("is-downed", view.heroes.superBoxy.isDown);
    bossChip?.classList.toggle("is-hidden", !view.boss.active);

    menuOverlay?.classList.toggle("is-visible", view.status === "menu");
    pauseOverlay?.classList.toggle("is-visible", view.status === "paused");

    const resultVisible = view.status === "victory" || view.status === "gameOver";
    resultOverlay?.classList.toggle("is-visible", resultVisible);
    if (view.status === "victory") {
      resultLabel!.textContent = "Victory";
      resultTitle!.textContent = "Porto shines again.";
      resultBody!.textContent = "The prototype ends with Adamastor driven back into the Douro and Primal Roar foreshadowed for the next episode.";
    } else if (view.status === "gameOver") {
      resultLabel!.textContent = "Storybook fall";
      resultTitle!.textContent = "Both brothers were downed.";
      resultBody!.textContent = "Restart from the top and keep the tag rhythm tighter through the bridge hazards and boss telegraphs.";
    }
  });

  return {
    destroy() {
      unsubscribe();
      root.innerHTML = "";
    },
  };
}

