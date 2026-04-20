export interface AssetDefinition {
  key: string;
  category: "characters" | "environment" | "ui" | "fx" | "audio";
  generated: boolean;
}

export const assetManifest = {
  characters: [
    { key: "hero.herosauro", category: "characters", generated: true },
    { key: "hero.superboxy", category: "characters", generated: true },
    { key: "enemy.golem", category: "characters", generated: true },
    { key: "boss.adamastor.face", category: "characters", generated: true },
  ],
  environment: [
    { key: "bg.water", category: "environment", generated: true },
    { key: "bg.bridge", category: "environment", generated: true },
    { key: "bg.stone", category: "environment", generated: true },
  ],
  ui: [
    { key: "ui.panel", category: "ui", generated: true },
    { key: "pickup.coin", category: "ui", generated: true },
    { key: "pickup.letter", category: "ui", generated: true },
    { key: "pickup.tile", category: "ui", generated: true },
  ],
  fx: [
    { key: "fx.roar", category: "fx", generated: true },
    { key: "fx.impact", category: "fx", generated: true },
    { key: "fx.warning", category: "fx", generated: true },
  ],
  audio: [] satisfies AssetDefinition[],
} as const;

export const allAssetDefinitions: AssetDefinition[] = Object.values(assetManifest).flat();

