import { stage1Encounter } from "../../game/content/encounters/stage1";
import { createEmptyInputFrame } from "../../game/input/actions";
import { createGameState } from "../../game/simulation/createGameState";
import { createViewModel, stepGameState } from "../../game/simulation/updateGameState";
import type { EncounterDefinition, GameState, InputFrame, ViewModel } from "../../game/types";

export interface SceneBridge {
  readonly encounter: EncounterDefinition;
  getState(): GameState;
  getViewModel(): ViewModel;
  start(): ViewModel;
  restart(): ViewModel;
  setPaused(paused: boolean): ViewModel;
  update(input: InputFrame, dt: number): ViewModel;
}

export function createSceneBridge(encounter: EncounterDefinition = stage1Encounter): SceneBridge {
  let state = createGameState(encounter, "menu");

  const toViewModel = (): ViewModel => createViewModel(state, encounter);

  return {
    encounter,
    getState: () => state,
    getViewModel: toViewModel,
    start() {
      state = createGameState(encounter, "playing");
      return toViewModel();
    },
    restart() {
      state = createGameState(encounter, "playing");
      return toViewModel();
    },
    setPaused(paused: boolean) {
      if (state.status === "playing" || state.status === "paused") {
        state.status = paused ? "paused" : "playing";
      }
      return toViewModel();
    },
    update(input: InputFrame, dt: number) {
      state = stepGameState(state, input, encounter, dt);
      return toViewModel();
    },
  };
}

export function createIdleFrame(): InputFrame {
  return createEmptyInputFrame();
}

