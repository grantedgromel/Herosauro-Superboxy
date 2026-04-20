import Phaser from "phaser";

import { ensureProceduralTextures } from "../view/createProceduralArt";

export class BootScene extends Phaser.Scene {
  constructor() {
    super("boot");
  }

  create(): void {
    ensureProceduralTextures(this);
    this.scene.start("game");
  }
}

