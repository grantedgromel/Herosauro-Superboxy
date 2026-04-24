export type HeroKind = "herosauro" | "superBoxy";
export type DashboardSectionId = "overview" | "route" | "threats" | "boss";
export type DashboardTone = "neutral" | "positive" | "warning" | "critical";
export type BossPhase =
  | "dormant"
  | "bridgeShake"
  | "combat"
  | "finisher"
  | "defeated";
export type BossPattern = "slam" | "sweep";
export type GameStatus = "menu" | "playing" | "paused" | "victory" | "gameOver";
export type ObjectiveId = "tutorial" | "hazard" | "warmup" | "boss" | "victory";
export type InputAction =
  | "moveLeft"
  | "moveRight"
  | "jump"
  | "lightAttack"
  | "special"
  | "dodge"
  | "switchHero"
  | "interact"
  | "pause";

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PlatformDefinition extends Rect {
  id: string;
  kind: "ground" | "bridge" | "ledge";
}

export interface BreakableDefinition extends Rect {
  id: string;
}

export interface ClimbZoneDefinition extends Rect {
  id: string;
  hero: HeroKind | "both";
}

export interface PickupDefinition {
  id: string;
  kind: "tostao" | "letter" | "tile";
  x: number;
  y: number;
  letter?: string;
}

export interface GolemSpawn {
  id: string;
  x: number;
  y: number;
  patrolMin: number;
  patrolMax: number;
}

export interface HazardDefinition extends Rect {
  id: string;
  kind: "fallingRock" | "waveBurst";
  interval: number;
  activeDuration: number;
  damage: number;
}

export interface CheckpointDefinition {
  id: string;
  x: number;
  y: number;
}

export interface BossArenaDefinition {
  start: number;
  end: number;
  weakPointX: number;
  weakPointY: number;
  slamZones: number[];
  sweepY: number;
}

export interface EncounterDefinition {
  id: string;
  name: string;
  worldWidth: number;
  worldHeight: number;
  startX: number;
  startY: number;
  objectiveText: Record<ObjectiveId, string>;
  platforms: PlatformDefinition[];
  breakables: BreakableDefinition[];
  climbZones: ClimbZoneDefinition[];
  pickups: PickupDefinition[];
  golemSpawns: GolemSpawn[];
  hazards: HazardDefinition[];
  checkpoints: CheckpointDefinition[];
  bossArena: BossArenaDefinition;
}

export interface AbilityState {
  attackCooldown: number;
  specialCooldown: number;
  dodgeCooldown: number;
  invulnerability: number;
  comboTimer: number;
}

export interface HeroState {
  kind: HeroKind;
  displayName: string;
  health: number;
  maxHealth: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  facing: -1 | 1;
  onGround: boolean;
  coyoteTimer: number;
  jumpBufferTimer: number;
  airDashes: number;
  attackTimer: number;
  rollTimer: number;
  specialTimer: number;
  attackStyle: "idle" | "attack" | "combo" | "finisher" | "roar" | "uppercut" | "roll";
  comboStep: number;
  isDown: boolean;
  reviveTimer: number;
  abilities: AbilityState;
}

export interface BossState {
  phase: BossPhase;
  pattern: BossPattern;
  patternIndex: number;
  active: boolean;
  locked: boolean;
  weakPointOpen: boolean;
  telegraphTimer: number;
  staggerTimer: number;
  health: number;
  maxHealth: number;
  shakeTimer: number;
  finisherStep: 0 | 1 | 2;
  finisherTimer: number;
}

export interface CheckpointState {
  lastId: string;
  x: number;
  y: number;
  bossHealth: number;
  bossPhase: BossPhase;
}

export interface CollectibleState {
  tostoes: number;
  letters: string[];
  tileFragments: number;
}

export interface PickupState extends PickupDefinition {
  collected: boolean;
}

export interface HazardState extends HazardDefinition {
  timer: number;
  active: boolean;
}

export interface GolemState {
  id: string;
  x: number;
  y: number;
  vx: number;
  facing: -1 | 1;
  health: number;
  maxHealth: number;
  alive: boolean;
  patrolMin: number;
  patrolMax: number;
  attackCooldown: number;
  hitFlash: number;
}

export interface BreakableState extends BreakableDefinition {
  broken: boolean;
}

export interface GameState {
  encounterId: string;
  time: number;
  status: GameStatus;
  activeHero: HeroKind;
  swapCooldown: number;
  heroes: Record<HeroKind, HeroState>;
  boss: BossState;
  checkpoint: CheckpointState;
  collectibles: CollectibleState;
  pickups: PickupState[];
  golems: GolemState[];
  hazards: HazardState[];
  breakables: BreakableState[];
  objective: string;
  activeSection: ObjectiveId;
  cameraTargetX: number;
  prompt: string;
  message: string;
}

export interface InputFrame {
  held: Record<InputAction, boolean>;
  pressed: Record<InputAction, boolean>;
  usingGamepad: boolean;
}

export interface HeroViewData {
  kind: HeroKind;
  x: number;
  y: number;
  health: number;
  maxHealth: number;
  active: boolean;
  isDown: boolean;
  facing: -1 | 1;
  attackStyle: HeroState["attackStyle"];
  invulnerability: number;
}

export interface DashboardNavSection {
  id: DashboardSectionId;
  label: string;
  live: boolean;
  available: boolean;
  note: string;
}

export interface RunSummary {
  progressPercent: number;
  elapsedLabel: string;
  checkpointLabel: string;
  collectiblesFound: number;
  collectiblesTotal: number;
  collectiblesLabel: string;
  bossReadinessPercent: number;
  bossStatus: string;
  activeSectionLabel: string;
}

export interface HeroRoleTag {
  label: "Power" | "Mobility" | "Survivability";
  value: "High" | "Medium" | "Low";
}

export interface HeroProfile {
  kind: HeroKind;
  displayName: string;
  active: boolean;
  isDown: boolean;
  healthPercent: number;
  condition: string;
  readiness: string;
  tone: DashboardTone;
  roleTags: HeroRoleTag[];
}

export interface AlertItem {
  id: string;
  label: string;
  detail: string;
  tone: DashboardTone;
}

export interface UpcomingItem {
  id: string;
  kind: "checkpoint" | "hazard" | "breakable" | "boss";
  label: string;
  detail: string;
  distanceLabel: string;
  tone: DashboardTone;
}

export interface BossViewData {
  active: boolean;
  phase: BossPhase;
  health: number;
  maxHealth: number;
  weakPointOpen: boolean;
  pattern: BossPattern;
  telegraphTimer: number;
  staggerTimer: number;
  finisherStep: 0 | 1 | 2;
}

export interface ViewModel {
  status: GameStatus;
  encounterName: string;
  activeHero: HeroKind;
  swapCooldown: number;
  objective: string;
  prompt: string;
  message: string;
  cameraTargetX: number;
  collectibles: CollectibleState;
  navSections: DashboardNavSection[];
  runSummary: RunSummary;
  heroProfiles: HeroProfile[];
  alerts: AlertItem[];
  upcoming: UpcomingItem[];
  heroes: Record<HeroKind, HeroViewData>;
  boss: BossViewData;
  golems: GolemState[];
  hazards: HazardState[];
  pickups: PickupState[];
  breakables: BreakableState[];
}
