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
    const encounter = this.bridge.encounter;
    const sky = this.add.graphics();
    sky.fillGradientStyle(0x091524, 0x091524, 0x345d8f, 0xf2a35e, 1);
    sky.fillRect(0, 0, 4600, VIEW_HEIGHT);
    sky.setScrollFactor(0);

    this.add.circle(980, 122, 86, 0xffd89a, 0.92).setScrollFactor(0.08);
    this.add.ellipse(980, 122, 260, 120, 0xffc27a, 0.22).setScrollFactor(0.08);

    const haze = this.add.graphics();
    haze.fillGradientStyle(0xffcb8a, 0xffcb8a, 0xffffff, 0xffffff, 0.12);
    haze.fillRect(0, 230, 4600, 220);
    haze.setScrollFactor(0.1);

    this.createDomLuisBridge(0.18, 300, 0.26);
    this.createSkylineSilhouette(0.16, 330, 0x1a2740, 0.4);
    this.createClerigosTower(910, 302, 0.16, 0.7);

    this.createRibeiraLayer(0.24, 0.84, 430, 20, ["bg.facadeGranite", "bg.facadeBlue", "bg.facadeOchre"]);
    this.createDomLuisBridge(0.28, 360, 0.44);
    this.createRibeiraLayer(0.36, 0.94, 498, 70, ["bg.facadeBlue", "bg.facadeRose", "bg.facadeOchre", "bg.facadeGranite"]);

    this.add.tileSprite(encounter.worldWidth / 2, 566, encounter.worldWidth + 500, 126, "bg.quay")
      .setScrollFactor(0.62)
      .setAlpha(0.86);
    this.add.rectangle(encounter.worldWidth / 2, 536, encounter.worldWidth + 500, 8, 0x9ea9b5, 0.42).setScrollFactor(0.62);

    this.createRiverTraffic();

    this.waterLayer = this.add.tileSprite(encounter.worldWidth / 2, 656, encounter.worldWidth + 500, 150, "bg.water")
      .setScrollFactor(0.8)
      .setAlpha(0.9);
    this.add.rectangle(encounter.worldWidth / 2, 682, encounter.worldWidth + 500, 96, 0x07101e, 0.46).setScrollFactor(1);
    this.add.rectangle(encounter.worldWidth / 2, 610, encounter.worldWidth + 500, 16, 0xe7c07f, 0.12).setScrollFactor(0.85);
  }

  private createSkylineSilhouette(
    scrollFactor: number,
    baseY: number,
    color: number,
    alpha: number,
  ): void {
    const skyline = this.add.graphics();
    skyline.fillStyle(color, alpha);
    for (let index = 0; index < 24; index += 1) {
      const x = index * 190;
      const width = 94 + ((index * 17) % 42);
      const height = 90 + ((index * 31) % 120);
      skyline.fillRect(x, baseY - height, width, height);
      skyline.fillTriangle(x + 8, baseY - height, x + width / 2, baseY - height - 26, x + width - 8, baseY - height);
    }
    skyline.setScrollFactor(scrollFactor);
  }

  private createRibeiraLayer(
    scrollFactor: number,
    alpha: number,
    baseY: number,
    startX: number,
    facadeKeys: string[],
  ): void {
    let x = startX;
    let index = 0;
    while (x < this.bridge.encounter.worldWidth + 320) {
      const width = 104 + ((index * 19) % 34);
      const height = 170 + ((index * 23) % 66);
      const key = facadeKeys[index % facadeKeys.length];
      const house = this.add.image(x + width / 2, baseY, key);
      house.setOrigin(0.5, 1);
      house.setDisplaySize(width, height);
      house.setAlpha(alpha);
      house.setScrollFactor(scrollFactor);
      x += width - 12;
      index += 1;
    }
  }

  private createDomLuisBridge(scrollFactor: number, y: number, alpha: number): void {
    const bridge = this.add.graphics();
    bridge.setScrollFactor(scrollFactor);
    bridge.lineStyle(8, 0x66778d, alpha);
    bridge.strokeLineShape(new Phaser.Geom.Line(260, y, 3930, y));
    bridge.lineStyle(6, 0x90a4be, alpha * 0.85);
    bridge.strokeLineShape(new Phaser.Geom.Line(260, y - 18, 3930, y - 18));

    for (let x = 300; x <= 3880; x += 180) {
      bridge.lineStyle(4, 0x6c7c94, alpha * 0.78);
      bridge.strokeLineShape(new Phaser.Geom.Line(x, y - 18, x + 90, y));
      bridge.strokeLineShape(new Phaser.Geom.Line(x + 90, y - 18, x, y));
      bridge.strokeLineShape(new Phaser.Geom.Line(x + 45, y - 18, x + 45, y));
    }

    bridge.lineStyle(7, 0x536170, alpha * 0.72);
    for (let arch = 0; arch < 6; arch += 1) {
      const start = 420 + arch * 540;
      bridge.beginPath();
      bridge.moveTo(start, y);
      bridge.lineTo(start + 110, y + 38);
      bridge.lineTo(start + 250, y + 52);
      bridge.lineTo(start + 420, y);
      bridge.strokePath();
    }

    bridge.lineStyle(6, 0x4d5965, alpha * 0.68);
    for (let support = 420; support <= 3700; support += 420) {
      bridge.strokeLineShape(new Phaser.Geom.Line(support, y, support, y + 132));
    }
  }

  private createClerigosTower(x: number, baseY: number, scrollFactor: number, alpha: number): void {
    const tower = this.add.graphics();
    tower.setScrollFactor(scrollFactor);
    tower.fillStyle(0x25334d, alpha);
    tower.fillRect(x, baseY - 168, 34, 168);
    tower.fillRoundedRect(x - 16, baseY - 216, 66, 48, 12);
    tower.fillTriangle(x - 10, baseY - 216, x + 17, baseY - 254, x + 44, baseY - 216);
    tower.fillRect(x + 10, baseY - 244, 12, 26);
    tower.fillStyle(0xa9b8ca, alpha * 0.12);
    tower.fillRect(x + 6, baseY - 170, 6, 150);
  }

  private createRiverTraffic(): void {
    const boats = [
      { x: 620, y: 610, scale: 0.72, scroll: 0.73, alpha: 0.8 },
      { x: 1760, y: 626, scale: 0.94, scroll: 0.79, alpha: 0.86 },
      { x: 3090, y: 616, scale: 0.78, scroll: 0.75, alpha: 0.76 },
    ];
    for (const boat of boats) {
      this.add.image(boat.x, boat.y, "bg.rabelo")
        .setScale(boat.scale)
        .setAlpha(boat.alpha)
        .setScrollFactor(boat.scroll);
      this.add.ellipse(boat.x, boat.y + 24, 180 * boat.scale, 18 * boat.scale, 0xe9c07b, 0.08)
        .setScrollFactor(boat.scroll);
    }
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

      if (platform.kind === "ground") {
        this.add.rectangle(platform.x + platform.width / 2, platform.y + 8, platform.width, 10, 0xe1c78e, 0.14);
      }
    }

    this.createSceneryProps();

    this.add.text(180, 448, "Ribeira dock", {
      fontFamily: "Georgia, Times New Roman, serif",
      fontSize: "24px",
      color: "#f3e7c2",
      stroke: "#17263a",
      strokeThickness: 5,
    });
    this.add.text(998, 430, "Broken girders", {
      fontFamily: "Georgia, Times New Roman, serif",
      fontSize: "22px",
      color: "#fff5d6",
      stroke: "#17263a",
      strokeThickness: 5,
    });
    this.add.text(2432, 256, "Granite climb line", {
      fontFamily: "Georgia, Times New Roman, serif",
      fontSize: "22px",
      color: "#dcf3ff",
      stroke: "#17263a",
      strokeThickness: 5,
    });
  }

  private createSceneryProps(): void {
    const lamps = [
      { x: 120, y: 618 },
      { x: 560, y: 618 },
      { x: 1710, y: 618 },
      { x: 2860, y: 618 },
      { x: 3320, y: 618 },
    ];
    for (const lamp of lamps) {
      this.add.image(lamp.x, lamp.y, "bg.lamp").setOrigin(0.5, 1).setAlpha(0.82);
    }

    const azulejos = [
      { x: 420, y: 576, scale: 0.78 },
      { x: 1610, y: 576, scale: 0.72 },
      { x: 2800, y: 576, scale: 0.72 },
    ];
    for (const tile of azulejos) {
      this.add.image(tile.x, tile.y, "bg.azulejo").setScale(tile.scale).setAlpha(0.72);
    }

    const posts = this.add.graphics();
    posts.fillStyle(0x382619, 0.92);
    for (const x of [140, 220, 300, 1700, 1780, 1860, 3270, 3350]) {
      posts.fillRect(x, 562, 12, 58);
      posts.fillRect(x - 2, 556, 16, 8);
    }
    posts.lineStyle(3, 0xaa8354, 0.55);
    posts.strokeLineShape(new Phaser.Geom.Line(146, 572, 226, 572));
    posts.strokeLineShape(new Phaser.Geom.Line(226, 572, 306, 572));
    posts.strokeLineShape(new Phaser.Geom.Line(1706, 572, 1786, 572));
    posts.strokeLineShape(new Phaser.Geom.Line(1786, 572, 1866, 572));
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
    this.add.ellipse(encounter.bossArena.end + 10, 572, 620, 76, 0xdcb36e, 0.1);
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
    this.bossBody.setAlpha(view.boss.phase === "bridgeShake" ? 0.82 : 0.94);

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
