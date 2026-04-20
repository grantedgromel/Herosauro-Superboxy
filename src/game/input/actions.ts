import type { InputAction, InputFrame } from "../types";

export const inputActions: InputAction[] = [
  "moveLeft",
  "moveRight",
  "jump",
  "lightAttack",
  "special",
  "dodge",
  "switchHero",
  "interact",
  "pause",
];

export function createActionRecord(defaultValue = false): Record<InputAction, boolean> {
  return Object.fromEntries(inputActions.map((action) => [action, defaultValue])) as Record<
    InputAction,
    boolean
  >;
}

export function createEmptyInputFrame(): InputFrame {
  return {
    held: createActionRecord(),
    pressed: createActionRecord(),
    usingGamepad: false,
  };
}

