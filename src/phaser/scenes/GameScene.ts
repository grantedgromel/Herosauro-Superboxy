import Phaser from "phaser";

import { gameBus } from "../../game/events";
import { createInputCollector } from "../../game/input/bindings";
import type { BreakableState, InputFrame, PickupState, ViewModel } from "../../game/types";
import { createSceneBridge, type SceneBridge } from "../adapters/sceneBridge";

const VIEW_WIDTH = 1280;
const VIEW_HEIGHT = 720;

export class GameScene extends Phaser.Scene {
  private bridge!: SceneBridge;
  private collectInput!: () => InputFrame;
  private heroSprites = new Map<string, Phaser.GameObjects.Image>();
  private golemSprites = new Map<string, Phaser.GameObjects.Image>();
  private pickupSprites = new Map<string, Phaser.GameObjects.Container>();
  private breakableSprites = new Map<string, Phaser.GameObjects.Image>();
  private hazardSprites = new Map<string, Phaser.GameObjects.Rectangle>();
  private waterLayer!: Phaser.GameObjects.TileSprite;
  private platformGraphics!: Phaser.GameObjects.Graphics;
  private bossBody!: Phaser.GameObjects.Ellipse;
  private bossFace!: Phaser.GameObjects.Image;
  private telegraphGraphics!: Phaser.GameObjects.Graphics;
  private unsubscribers: Array<() => void> = [];

  constructor() {
    super("game");
  }

  create(): void {
    this.bridge = createSceneBridge();
    const encounter = this.bridge.encounter;
    this.collectInput = createInputCollector(this);
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, this.cleanup, this);
    this.events.once(Phaser.Scenes.Events.DESTROY, this.cleanup, this);

    this.cameras.main.setBounds(0, 0, encounter.worldWidth, encounter.worldHeight);
    this.cameras.main.setRoundPixels(true);

    this.createBackdrop();
    this.createLevelGeometry();
    this.createPickups();
    this.createActors();
    this.createBoss();

    this.unsubscribers.push(
      gameBus.on("game:start", () => this.pushView(this.bridge.start())),
      gameBus.on("game:restart", () => this.pushView(this.bridge.restart())),
      gameBus.on("game:resume", () => this.pushView(this.bridge.setPaused(false))),
    );

    this.pushView(this.bridge.getViewModel());
  }

  private cleanup(): void {
    for (const unsubscribe of this.unsubscribers) {
      unsubscribe();
    }
    this.unsubscribers = [];
  }

  private createBackdrop(): void {
    const sky = this.add.graphics();
    sky.fillGradientStyle(0x081529, 0x081529, 0x27518f, 0xf6ab54, 1);
    sky.fillRect(0, 0, 4600, VIEW_HEIGHT);
    sky.setScrollFactor(0);

    this.add.circle(930, 118, 70, 0xffd98b, 0.88).setScrollFactor(0.08);

    const farCity = this.add.graphics();
    farCity.fillStyle(0x22314a, 0.85);
    for (let index = 0; index < 26; index += 1) {
      const x = index * 190;
      const height = 120 + ((index * 37) % 140);
      farCity.fillRect(x, 320 - height, 110, height);
      farCity.fillTriangle(x + 8, 320 - height, x + 55, 290 - height, x + 105, 320 - height);
    }
    farCity.setScrollFactor(0.22);

    const midCity = this.add.graphics();
    midCity.fillStyle(0x314563, 0.95);
    for (let index = 0; index < 24; index += 1) {
      const x = index * 200 + 60;
      const height = 120 + ((index * 29) % 170);
      midCity.fillRect(x, 405 - height, 134, height);
      midCity.fillRect(x + 18, 385 - height, 18, height * 0.25);
    }
    midCity.setScrollFactor(0.36);

    this.add.tileSprite(2100, 554, 4600, 180, "bg.bridge").setScrollFactor(0.48).setAlpha(0.35);
    this.waterLayer = this.add.tileSprite(2100, 658, 4600, 124, "bg.water").setScrollFactor(0.8);
    this.add.rectangle(2100, 680, 4600, 84, 0x081529, 0.5).setScrollFactor(1);
  }

  private createLevelGeometry(): void {
    const encounter = this.bridge.encounter;
    this.platformGraphics = this.add.graphics();
    this.platformGraphics.fillStyle(0x6d7f9c);
    for (const platform of encounter.platforms) {
      const texture = platform.kind === "ground" ? "bg.stone" : "bg.bridge";
      this.add.tileSprite(
        platform.x + platform.width / 2,
        platform.y + platform.height / 2,
        platform.width,
        platform.height,
        texture,
      );
      this.platformGraphics.lineStyle(2, 0xd6e6ff, 0.3);
      this.platformGraphics.strokeRect(platform.x, platform.y, platform.width, platform.height);
    }

    this.add.text(180, 448, "Ribeira training dock", {
      fontFamily: "Trebuchet MS, Verdana, sans-serif",
      fontSize: "24px",
      color: "#f3e7c2",
    });
    this.add.text(998, 430, "Broken girders", {
      fontFamily: "Trebuchet MS, Verdana, sans-serif",
      fontSize: "22px",
      color: "#fff5d6",
    });
    this.add.text(2428, 256, "Rough stone / wall-bounce lane", {
      fontFamily: "Trebuchet MS, Verdana, sans-serif",
      fontSize: "22px",
      color: "#dcf3ff",
    });
  }

  private createPickups(): void {
    const encounter = this.bridge.encounter;
    for (const pickup of encounter.pickups) {
      const container = this.add.container(pickup.x, pickup.y);
      const baseKey = pickup.kind === "tostao" ? "pickup.coin" : pickup.kind === "tile" ? "pickup.tile" : "pickup.letter";
      const icon = this.add.image(0, 0, baseKey);
      container.add(icon);

      if (pickup.kind === "letter" && pickup.letter) {
        const label = this.add.text(0, 0, pickup.letter, {
          fontFamily: "Trebuchet MS, Verdana, sans-serif",
          fontSize: "20px",
          color: "#f5f8ff",
          fontStyle: "bold",
        });
        label.setOrigin(0.5);
        container.add(label);
      }

      this.pickupSprites.set(pickup.id, container);
    }
  }

  private createActors(): void {
    const herosauro = this.add.image(0, 0, "hero.herosauro");
    herosauro.setOrigin(0.5, 1);
    this.heroSprites.set("herosauro", herosauro);

    const superBoxy = this.add.image(0, 0, "hero.superboxy");
    superBoxy.setOrigin(0.5, 1);
    this.heroSprites.set("superBoxy", superBoxy);

    for (const golem of this.bridge.encounter.golemSpawns) {
      const sprite = this.add.image(golem.x, golem.y, "enemy.golem");
      sprite.setOrigin(0.5, 1);
      this.golemSprites.set(golem.id, sprite);
    }

    for (const breakable of this.bridge.encounter.breakables) {
      const sprite = this.add.image(breakable.x + breakable.width / 2, breakable.y + breakable.height / 2, "bg.stone");
      sprite.setDisplaySize(breakable.width, breakable.height);
      this.breakableSprites.set(breakable.id, sprite);
    }

    for (const hazard of this.bridge.encounter.hazards) {
      const rect = this.add.rectangle(
        hazard.x + hazard.width / 2,
        hazard.y + hazard.height / 2,
        hazard.width,
        hazard.height,
        hazard.kind === "fallingRock" ? 0xf59e0b : 0x38bdf8,
        0.2,
      );
      rect.setVisible(false);
      this.hazardSprites.set(hazard.id, rect);
    }
  }

  private createBoss(): void {
    const encounter = this.bridge.encounter;
    this.bossBody = this.add.ellipse(encounter.bossArena.end + 30, 450, 620, 520, 0x1a2940, 0.92);
    this.bossBody.setVisible(false);
    this.bossFace = this.add.image(encounter.bossArena.weakPointX, encounter.bossArena.weakPointY, "boss.adamastor.face");
    this.bossFace.setScale(1.05);
    this.bossFace.setVisible(false);
    this.telegraphGraphics = this.add.graphics();
  }

  override update(_time: number, delta: number): void {
    const input = this.collectInput();
    const view = this.bridge.update(input, delta / 1000);
    this.pushView(view);
    this.waterLayer.tilePositionX += delta * 0.02;
  }

  private pushView(view: ViewModel): void {
    this.renderHeroes(view);
    this.renderGolems(view);
    this.renderPickups(view.pickups);
    this.renderBreakables(view.breakables);
    this.renderHazards(view);
    this.renderBoss(view);
    this.cameras.main.scrollX = Phaser.Math.Linear(
      this.cameras.main.scrollX,
      view.cameraTargetX - VIEW_WIDTH / 2,
      0.1,
    );
    gameBus.emit("hud:update", view);
  }

  private renderHeroes(view: ViewModel): void {
    for (const hero of Object.values(view.heroes)) {
      const sprite = this.heroSprites.get(hero.kind);
      if (!sprite) {
        continue;
      }
      sprite.setPosition(hero.x, hero.y);
      sprite.setVisible(!hero.isDown);
      sprite.setAlpha(hero.active ? 1 : 0.24);
      sprite.setFlipX(hero.facing < 0);
      const pulse =
        hero.attackStyle === "roar" || hero.attackStyle === "uppercut"
          ? 1.14
          : hero.attackStyle === "roll"
            ? 0.96
            : hero.attackStyle === "finisher"
              ? 1.1
              : 1;
      sprite.setScale(pulse);
      sprite.setTint(hero.invulnerability > 0 ? 0xf8f2be : 0xffffff);
    }
  }

  private renderGolems(view: ViewModel): void {
    for (const golem of view.golems) {
      const sprite = this.golemSprites.get(golem.id);
      if (!sprite) {
        continue;
      }
      sprite.setVisible(golem.alive);
      sprite.setPosition(golem.x, golem.y);
      sprite.setFlipX(golem.facing > 0);
      sprite.setTint(golem.hitFlash > 0 ? 0xffdca7 : 0xffffff);
    }
  }

  private renderPickups(pickups: PickupState[]): void {
    for (const pickup of pickups) {
      const sprite = this.pickupSprites.get(pickup.id);
      if (!sprite) {
        continue;
      }
      sprite.setVisible(!pickup.collected);
      sprite.y = pickup.y + Math.sin((this.time.now + pickup.x) / 240) * 4;
    }
  }

  private renderBreakables(breakables: BreakableState[]): void {
    for (const breakable of breakables) {
      const sprite = this.breakableSprites.get(breakable.id);
      if (!sprite) {
        continue;
      }
      sprite.setVisible(!breakable.broken);
      sprite.setAlpha(breakable.broken ? 0 : 0.92);
    }
  }

  private renderHazards(view: ViewModel): void {
    for (const hazard of view.hazards) {
      const sprite = this.hazardSprites.get(hazard.id);
      if (!sprite) {
        continue;
      }
      sprite.setVisible(hazard.active);
      sprite.setAlpha(hazard.active ? 0.38 : 0);
    }
  }

  private renderBoss(view: ViewModel): void {
    this.bossBody.setVisible(view.boss.active);
    this.bossFace.setVisible(view.boss.active);
    this.bossFace.setTint(view.boss.weakPointOpen ? 0xfff1a6 : 0xffffff);
    this.bossFace.setScale(view.boss.weakPointOpen ? 1.18 : 1.05);

    this.telegraphGraphics.clear();
    if (!view.boss.active || view.status === "menu") {
      return;
    }

    if (view.boss.phase === "bridgeShake") {
      this.cameras.main.shake(180, 0.0028);
      return;
    }

    if (view.boss.phase === "combat" && !view.boss.weakPointOpen) {
      this.telegraphGraphics.fillStyle(0xef4444, 0.24);
      if (view.boss.pattern === "slam") {
        const zoneX =
          this.bridge.encounter.bossArena.slamZones[
            this.bridge.getState().boss.patternIndex % this.bridge.encounter.bossArena.slamZones.length
          ];
        this.telegraphGraphics.fillRect(zoneX - 84, 440, 168, 180);
      } else {
        this.telegraphGraphics.fillRect(
          this.bridge.encounter.bossArena.start + 40,
          this.bridge.encounter.bossArena.sweepY - 56,
          this.bridge.encounter.bossArena.end - this.bridge.encounter.bossArena.start - 80,
          56,
        );
      }
    }
  }
}
