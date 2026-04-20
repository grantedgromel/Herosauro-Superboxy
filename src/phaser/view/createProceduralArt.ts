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

function drawWindow(
  graphics: Phaser.GameObjects.Graphics,
  x: number,
  y: number,
  width: number,
  height: number,
  glow = false,
): void {
  graphics.fillStyle(glow ? 0xf7d89d : 0x203049);
  graphics.fillRoundedRect(x, y, width, height, 4);
  graphics.lineStyle(2, glow ? 0xfff2d2 : 0x7aa6d1, 0.65);
  graphics.strokeRoundedRect(x, y, width, height, 4);
  graphics.lineStyle(1, glow ? 0xd59a5e : 0x1a2438, 0.65);
  graphics.strokeLineShape(new Phaser.Geom.Line(x + width / 2, y + 2, x + width / 2, y + height - 2));
  graphics.strokeLineShape(new Phaser.Geom.Line(x + 2, y + height / 2, x + width - 2, y + height / 2));
}

function drawBalcony(
  graphics: Phaser.GameObjects.Graphics,
  x: number,
  y: number,
  width: number,
  depth: number,
): void {
  graphics.fillStyle(0x1a2232, 0.85);
  graphics.fillRect(x, y, width, depth);
  graphics.lineStyle(2, 0x121923, 1);
  for (let rail = 0; rail <= width; rail += 10) {
    graphics.strokeLineShape(new Phaser.Geom.Line(x + rail, y - 12, x + rail, y + depth));
  }
  graphics.strokeLineShape(new Phaser.Geom.Line(x, y - 12, x + width, y - 12));
}

function drawAzulejoBand(
  graphics: Phaser.GameObjects.Graphics,
  x: number,
  y: number,
  width: number,
  tileSize: number,
): void {
  for (let offset = 0; offset < width; offset += tileSize) {
    graphics.fillStyle(0xeef6ff);
    graphics.fillRect(x + offset, y, tileSize - 1, tileSize - 1);
    graphics.lineStyle(1, 0x7cb4d8, 0.9);
    graphics.strokeRect(x + offset, y, tileSize - 1, tileSize - 1);
    graphics.lineStyle(2, 0x2c72a8, 0.9);
    graphics.strokeLineShape(
      new Phaser.Geom.Line(x + offset + 4, y + tileSize / 2, x + offset + tileSize / 2, y + 4),
    );
    graphics.strokeLineShape(
      new Phaser.Geom.Line(x + offset + tileSize / 2, y + tileSize - 4, x + offset + tileSize - 4, y + tileSize / 2),
    );
  }
}

export function ensureProceduralTextures(scene: Phaser.Scene): void {
  generateTexture(scene, "hero.herosauro", 112, 152, (graphics) => {
    graphics.fillStyle(0x10261d);
    graphics.fillRoundedRect(26, 26, 48, 84, 16);
    graphics.fillStyle(0x4eb578);
    graphics.fillRoundedRect(28, 20, 44, 74, 16);
    graphics.fillStyle(0x8fe39f);
    graphics.fillEllipse(50, 40, 34, 28);
    graphics.fillStyle(0xc8f7b3);
    graphics.fillRoundedRect(42, 54, 22, 42, 10);
    graphics.fillStyle(0x1d2c2a);
    graphics.fillRoundedRect(22, 72, 14, 28, 8);
    graphics.fillRoundedRect(70, 74, 14, 26, 8);
    graphics.fillStyle(0x162136);
    graphics.fillRoundedRect(30, 82, 42, 12, 6);
    graphics.fillStyle(0xe7b257);
    graphics.fillTriangle(72, 26, 90, 18, 80, 38);
    graphics.fillTriangle(28, 22, 18, 8, 38, 18);
    graphics.fillStyle(0x0f1725);
    graphics.fillTriangle(16, 102, 4, 138, 30, 130);
    graphics.fillStyle(0x274234);
    graphics.fillTriangle(20, 100, 8, 132, 26, 126);
    graphics.fillStyle(0xefffdc);
    graphics.fillCircle(56, 38, 5);
    graphics.fillStyle(0x183027);
    for (let row = 0; row < 3; row += 1) {
      for (let column = 0; column < 4; column += 1) {
        graphics.fillCircle(38 + column * 8, 62 + row * 10, 2);
      }
    }
    graphics.fillStyle(0x3f6f54);
    graphics.fillRoundedRect(38, 110, 14, 24, 6);
    graphics.fillRoundedRect(56, 110, 14, 24, 6);
    graphics.fillStyle(0x151d29);
    graphics.fillRoundedRect(36, 128, 18, 12, 5);
    graphics.fillRoundedRect(54, 128, 18, 12, 5);
  });

  generateTexture(scene, "hero.superboxy", 110, 150, (graphics) => {
    graphics.fillStyle(0x0e1630);
    graphics.fillRoundedRect(32, 28, 42, 84, 16);
    graphics.fillStyle(0x203762);
    graphics.fillRoundedRect(34, 24, 38, 74, 16);
    graphics.fillStyle(0xf1cb9b);
    graphics.fillCircle(54, 40, 16);
    graphics.fillStyle(0x111827);
    graphics.fillRoundedRect(38, 28, 32, 16, 8);
    graphics.fillStyle(0x8fc4ff);
    graphics.fillRoundedRect(40, 34, 28, 10, 5);
    graphics.fillStyle(0xc33d32);
    graphics.fillRoundedRect(18, 56, 20, 18, 8);
    graphics.fillRoundedRect(70, 56, 20, 18, 8);
    graphics.fillStyle(0xe25a47);
    graphics.fillRoundedRect(16, 54, 22, 20, 8);
    graphics.fillRoundedRect(72, 54, 22, 20, 8);
    graphics.fillStyle(0xf0cb4e);
    graphics.fillRoundedRect(42, 68, 24, 24, 7);
    graphics.fillStyle(0x842c28);
    graphics.fillRoundedRect(42, 92, 24, 12, 6);
    graphics.fillStyle(0x1a2442);
    graphics.fillRoundedRect(38, 108, 14, 24, 5);
    graphics.fillRoundedRect(58, 108, 14, 24, 5);
    graphics.fillStyle(0xe7e7f3);
    graphics.fillRect(36, 112, 5, 16);
    graphics.fillRect(69, 112, 5, 16);
    graphics.fillStyle(0x151a28);
    graphics.fillRoundedRect(34, 130, 18, 11, 5);
    graphics.fillRoundedRect(58, 130, 18, 11, 5);
  });

  generateTexture(scene, "enemy.golem", 86, 112, (graphics) => {
    graphics.fillStyle(0x1d2432);
    graphics.fillRoundedRect(16, 18, 48, 70, 12);
    graphics.fillStyle(0x66758f);
    graphics.fillRoundedRect(20, 22, 42, 66, 10);
    graphics.fillStyle(0x8397b6);
    graphics.fillRect(24, 30, 14, 12);
    graphics.fillRect(44, 28, 14, 18);
    graphics.fillRect(28, 50, 28, 20);
    graphics.fillStyle(0xd1ddf0);
    graphics.fillCircle(34, 42, 5);
    graphics.fillCircle(48, 42, 5);
    graphics.fillStyle(0x3b475d);
    graphics.fillRoundedRect(24, 86, 16, 18, 4);
    graphics.fillRoundedRect(44, 86, 16, 18, 4);
  });

  generateTexture(scene, "boss.adamastor.face", 180, 180, (graphics) => {
    graphics.fillStyle(0x1d2a43);
    graphics.fillCircle(90, 92, 82);
    graphics.fillStyle(0x3f597f);
    graphics.fillCircle(90, 90, 66);
    graphics.fillStyle(0x5f7ea6);
    graphics.fillEllipse(90, 96, 108, 96);
    graphics.fillStyle(0xe7cf99);
    graphics.fillEllipse(90, 96, 44, 28);
    graphics.fillStyle(0x0d1728);
    graphics.fillCircle(68, 72, 8);
    graphics.fillCircle(112, 72, 8);
    graphics.lineStyle(4, 0xb7d9ff, 0.75);
    graphics.strokeLineShape(new Phaser.Geom.Line(54, 48, 72, 34));
    graphics.strokeLineShape(new Phaser.Geom.Line(126, 48, 108, 34));
    graphics.lineStyle(3, 0xf3f6fe, 0.55);
    graphics.beginPath();
    graphics.arc(90, 108, 26, Phaser.Math.DegToRad(18), Phaser.Math.DegToRad(162), false, 0.02);
    graphics.strokePath();
    graphics.fillStyle(0x8bbde5, 0.25);
    graphics.fillEllipse(90, 128, 100, 18);
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

  generateTexture(scene, "bg.facadeBlue", 128, 220, (graphics) => {
    graphics.fillGradientStyle(0xaed4eb, 0xaed4eb, 0x4f84b7, 0x4f84b7, 1);
    graphics.fillRect(0, 30, 128, 190);
    graphics.fillStyle(0x7b4c34);
    graphics.fillTriangle(0, 30, 64, 0, 128, 30);
    graphics.fillStyle(0xc26d3f);
    graphics.fillTriangle(8, 30, 64, 8, 120, 30);
    drawAzulejoBand(graphics, 10, 140, 108, 16);
    drawWindow(graphics, 18, 56, 28, 42);
    drawWindow(graphics, 82, 56, 28, 42, true);
    drawWindow(graphics, 18, 108, 28, 42);
    drawWindow(graphics, 82, 108, 28, 42);
    drawWindow(graphics, 48, 162, 32, 46);
    drawBalcony(graphics, 44, 152, 40, 8);
  });

  generateTexture(scene, "bg.facadeOchre", 128, 216, (graphics) => {
    graphics.fillGradientStyle(0xf2d39c, 0xf2d39c, 0xb5733d, 0xb5733d, 1);
    graphics.fillRect(0, 24, 128, 192);
    graphics.fillStyle(0x5f3030);
    graphics.fillTriangle(0, 24, 64, 4, 128, 24);
    graphics.fillStyle(0xa94e3b);
    graphics.fillTriangle(10, 24, 64, 10, 118, 24);
    graphics.fillStyle(0xe7e5d8);
    graphics.fillRect(10, 134, 108, 18);
    drawWindow(graphics, 14, 54, 28, 38, true);
    drawWindow(graphics, 48, 54, 28, 38);
    drawWindow(graphics, 82, 54, 28, 38);
    drawWindow(graphics, 18, 100, 28, 34);
    drawWindow(graphics, 82, 100, 28, 34, true);
    drawWindow(graphics, 48, 162, 32, 40);
    drawBalcony(graphics, 44, 152, 40, 8);
  });

  generateTexture(scene, "bg.facadeRose", 128, 224, (graphics) => {
    graphics.fillGradientStyle(0xf2c1bc, 0xf2c1bc, 0xad645f, 0xad645f, 1);
    graphics.fillRect(0, 34, 128, 190);
    graphics.fillStyle(0x6e4031);
    graphics.fillTriangle(0, 34, 64, 6, 128, 34);
    graphics.fillStyle(0xcf7e52);
    graphics.fillTriangle(8, 34, 64, 12, 120, 34);
    drawWindow(graphics, 16, 60, 24, 38);
    drawWindow(graphics, 52, 60, 24, 38, true);
    drawWindow(graphics, 88, 60, 24, 38);
    drawWindow(graphics, 16, 110, 24, 34);
    drawWindow(graphics, 52, 110, 24, 34);
    drawWindow(graphics, 88, 110, 24, 34, true);
    drawAzulejoBand(graphics, 18, 150, 92, 12);
    drawWindow(graphics, 48, 170, 32, 42);
    drawBalcony(graphics, 44, 160, 40, 8);
  });

  generateTexture(scene, "bg.facadeGranite", 128, 214, (graphics) => {
    graphics.fillGradientStyle(0xd5d2cb, 0xd5d2cb, 0x6a7078, 0x6a7078, 1);
    graphics.fillRect(0, 26, 128, 188);
    graphics.fillStyle(0x4c4b50);
    graphics.fillTriangle(0, 26, 64, 2, 128, 26);
    drawWindow(graphics, 14, 56, 28, 44, true);
    drawWindow(graphics, 48, 56, 32, 44);
    drawWindow(graphics, 86, 56, 24, 44);
    drawWindow(graphics, 18, 110, 24, 32);
    drawWindow(graphics, 48, 110, 32, 32);
    drawWindow(graphics, 88, 110, 22, 32, true);
    graphics.fillStyle(0xdee9f7);
    graphics.fillRoundedRect(40, 150, 48, 52, 6);
    drawAzulejoBand(graphics, 44, 156, 40, 10);
    drawBalcony(graphics, 40, 194, 48, 8);
  });

  generateTexture(scene, "bg.azulejo", 96, 96, (graphics) => {
    graphics.fillStyle(0xf5fbff);
    graphics.fillRoundedRect(0, 0, 96, 96, 10);
    drawAzulejoBand(graphics, 8, 8, 80, 16);
    drawAzulejoBand(graphics, 8, 32, 80, 16);
    drawAzulejoBand(graphics, 8, 56, 80, 16);
    drawAzulejoBand(graphics, 8, 80, 80, 16);
  });

  generateTexture(scene, "bg.quay", 160, 96, (graphics) => {
    graphics.fillGradientStyle(0x7b7f82, 0x7b7f82, 0x474b52, 0x474b52, 1);
    graphics.fillRect(0, 0, 160, 96);
    graphics.lineStyle(2, 0xadb5bf, 0.5);
    for (let column = 0; column <= 160; column += 24) {
      graphics.strokeLineShape(new Phaser.Geom.Line(column, 0, column, 96));
    }
    for (let row = 0; row <= 96; row += 18) {
      graphics.strokeLineShape(new Phaser.Geom.Line(0, row, 160, row));
    }
  });

  generateTexture(scene, "bg.rabelo", 240, 120, (graphics) => {
    graphics.fillStyle(0x5a321f);
    graphics.fillTriangle(20, 76, 218, 76, 118, 106);
    graphics.fillStyle(0x7b4931);
    graphics.fillRect(46, 56, 126, 20);
    graphics.fillStyle(0x2f1f18);
    graphics.fillRect(112, 24, 6, 52);
    graphics.fillStyle(0xe9d7af);
    graphics.fillTriangle(118, 26, 118, 74, 178, 56);
    graphics.lineStyle(3, 0x3d261a, 1);
    graphics.strokeLineShape(new Phaser.Geom.Line(28, 76, 212, 76));
  });

  generateTexture(scene, "bg.lamp", 48, 132, (graphics) => {
    graphics.fillStyle(0x1f2530);
    graphics.fillRect(22, 22, 4, 96);
    graphics.fillRect(16, 114, 16, 6);
    graphics.fillStyle(0x283445);
    graphics.fillRoundedRect(12, 0, 24, 28, 6);
    graphics.fillStyle(0xffe4a6, 0.82);
    graphics.fillRoundedRect(16, 6, 16, 18, 4);
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
