import Phaser from "phaser";

function generateTexture(
  scene: Phaser.Scene,
  key: string,
  width: number,
  height: number,
  draw: (graphics: Phaser.GameObjects.Graphics) => void,
): void {
  if (scene.textures.exists(key)) {
    return;
  }

  const graphics = scene.add.graphics();
  draw(graphics);
  graphics.generateTexture(key, width, height);
  graphics.destroy();
}

export function ensureProceduralTextures(scene: Phaser.Scene): void {
  generateTexture(scene, "hero.herosauro", 88, 112, (graphics) => {
    graphics.fillStyle(0x17342d);
    graphics.fillRoundedRect(18, 22, 40, 68, 14);
    graphics.fillStyle(0x63d287);
    graphics.fillRoundedRect(20, 12, 34, 52, 12);
    graphics.fillStyle(0xb5f07c);
    graphics.fillCircle(34, 28, 12);
    graphics.fillStyle(0x0d1c18);
    graphics.fillTriangle(10, 78, 2, 100, 24, 98);
    graphics.fillStyle(0xecf9d0);
    graphics.fillCircle(40, 28, 4);
    graphics.fillStyle(0xf0ad44);
    graphics.fillTriangle(56, 22, 76, 14, 64, 36);
  });

  generateTexture(scene, "hero.superboxy", 84, 104, (graphics) => {
    graphics.fillStyle(0x1b2036);
    graphics.fillRoundedRect(22, 16, 30, 62, 12);
    graphics.fillStyle(0xfed98f);
    graphics.fillCircle(38, 22, 12);
    graphics.fillStyle(0xd6483f);
    graphics.fillRoundedRect(12, 34, 18, 16, 8);
    graphics.fillRoundedRect(46, 34, 18, 16, 8);
    graphics.fillStyle(0xf4b400);
    graphics.fillRoundedRect(28, 38, 18, 26, 6);
    graphics.fillStyle(0x9ad7ff);
    graphics.fillRect(26, 20, 24, 10);
  });

  generateTexture(scene, "enemy.golem", 72, 92, (graphics) => {
    graphics.fillStyle(0x2d3446);
    graphics.fillRoundedRect(12, 10, 40, 64, 12);
    graphics.fillStyle(0x6e7d95);
    graphics.fillRoundedRect(16, 16, 34, 56, 10);
    graphics.fillStyle(0xc2d1e6);
    graphics.fillCircle(30, 30, 5);
    graphics.fillCircle(40, 30, 5);
  });

  generateTexture(scene, "boss.adamastor.face", 150, 150, (graphics) => {
    graphics.fillStyle(0x23314a);
    graphics.fillCircle(75, 75, 70);
    graphics.fillStyle(0x4e678b);
    graphics.fillCircle(75, 75, 56);
    graphics.fillStyle(0xffd58c);
    graphics.fillCircle(75, 70, 20);
    graphics.fillStyle(0x152033);
    graphics.fillCircle(60, 56, 7);
    graphics.fillCircle(90, 56, 7);
  });

  generateTexture(scene, "bg.water", 160, 64, (graphics) => {
    graphics.fillGradientStyle(0x0a2a47, 0x0a2a47, 0x2a6ca4, 0x2a6ca4, 1);
    graphics.fillRect(0, 0, 160, 64);
    graphics.lineStyle(4, 0x6bc4ff, 0.6);
    graphics.beginPath();
    graphics.moveTo(0, 20);
    graphics.lineTo(22, 12);
    graphics.lineTo(48, 18);
    graphics.lineTo(82, 30);
    graphics.lineTo(108, 16);
    graphics.lineTo(134, 10);
    graphics.lineTo(160, 20);
    graphics.strokePath();
  });

  generateTexture(scene, "bg.bridge", 96, 96, (graphics) => {
    graphics.fillStyle(0x34425c);
    graphics.fillRect(0, 0, 96, 96);
    graphics.lineStyle(6, 0x869ab8, 1);
    graphics.strokeRect(6, 6, 84, 84);
    graphics.strokeLineShape(new Phaser.Geom.Line(6, 6, 90, 90));
    graphics.strokeLineShape(new Phaser.Geom.Line(90, 6, 6, 90));
  });

  generateTexture(scene, "bg.stone", 72, 72, (graphics) => {
    graphics.fillStyle(0x556277);
    graphics.fillRoundedRect(0, 0, 72, 72, 10);
    graphics.fillStyle(0x7f90aa);
    graphics.fillRect(10, 16, 18, 12);
    graphics.fillRect(36, 12, 24, 14);
    graphics.fillRect(16, 40, 20, 16);
    graphics.fillRect(42, 38, 12, 20);
  });

  generateTexture(scene, "ui.panel", 256, 128, (graphics) => {
    graphics.fillStyle(0x142036, 0.9);
    graphics.fillRoundedRect(0, 0, 256, 128, 18);
    graphics.lineStyle(6, 0xddc38a, 1);
    graphics.strokeRoundedRect(4, 4, 248, 120, 18);
  });

  generateTexture(scene, "pickup.coin", 36, 36, (graphics) => {
    graphics.fillStyle(0xf2b90b);
    graphics.fillCircle(18, 18, 16);
    graphics.lineStyle(4, 0xfff2a6, 1);
    graphics.strokeCircle(18, 18, 12);
  });

  generateTexture(scene, "pickup.letter", 42, 42, (graphics) => {
    graphics.fillStyle(0x1f4d87);
    graphics.fillRoundedRect(2, 2, 38, 38, 10);
    graphics.lineStyle(3, 0xcde9ff, 1);
    graphics.strokeRoundedRect(2, 2, 38, 38, 10);
  });

  generateTexture(scene, "pickup.tile", 40, 40, (graphics) => {
    graphics.fillStyle(0x1e6e8c);
    graphics.fillRoundedRect(2, 2, 36, 36, 8);
    graphics.lineStyle(4, 0xf3f7ff, 1);
    graphics.strokeLineShape(new Phaser.Geom.Line(10, 10, 30, 30));
    graphics.strokeLineShape(new Phaser.Geom.Line(30, 10, 10, 30));
  });

  generateTexture(scene, "fx.roar", 120, 120, (graphics) => {
    graphics.lineStyle(6, 0x8bf8d2, 0.8);
    graphics.strokeCircle(60, 60, 32);
    graphics.strokeCircle(60, 60, 48);
  });

  generateTexture(scene, "fx.impact", 96, 96, (graphics) => {
    graphics.fillStyle(0xffc35e, 0.85);
    graphics.fillTriangle(48, 4, 66, 38, 92, 48);
    graphics.fillTriangle(48, 4, 30, 38, 4, 48);
    graphics.fillTriangle(4, 48, 30, 56, 48, 92);
    graphics.fillTriangle(92, 48, 66, 56, 48, 92);
  });

  generateTexture(scene, "fx.warning", 128, 48, (graphics) => {
    graphics.fillStyle(0x7f1d1d, 0.8);
    graphics.fillRoundedRect(0, 0, 128, 48, 14);
    graphics.lineStyle(4, 0xf59e0b, 1);
    graphics.strokeRoundedRect(4, 4, 120, 40, 14);
  });
}
