import Phaser from "phaser";

import { BootScene } from "./phaser/boot/BootScene";
import { GameScene } from "./phaser/scenes/GameScene";
import { createHudController } from "./ui/hud";
import "./styles.css";

const app = document.querySelector<HTMLDivElement>("#app");

if (!app) {
  throw new Error("Missing #app root.");
}

app.innerHTML = `
  <div class="shell">
    <div class="shell__ornament shell__ornament--left"></div>
    <div class="shell__ornament shell__ornament--right"></div>
    <div class="shell__frame">
      <div id="game-root" class="shell__game"></div>
      <div id="hud-root" class="shell__hud"></div>
    </div>
  </div>
`;

createHudController(document.querySelector<HTMLElement>("#hud-root")!);

new Phaser.Game({
  type: Phaser.AUTO,
  width: 1280,
  height: 720,
  parent: "game-root",
  backgroundColor: "#081529",
  render: {
    pixelArt: false,
    antialias: true,
  },
  fps: {
    target: 60,
    forceSetTimeOut: true,
  },
  scene: [BootScene, GameScene],
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
  },
});

