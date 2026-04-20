import Phaser from "phaser";

import { createActionRecord } from "./actions";
import type { InputAction, InputFrame } from "../types";

interface GameKeys {
  leftA: Phaser.Input.Keyboard.Key;
  leftArrow: Phaser.Input.Keyboard.Key;
  rightD: Phaser.Input.Keyboard.Key;
  rightArrow: Phaser.Input.Keyboard.Key;
  jumpSpace: Phaser.Input.Keyboard.Key;
  jumpUp: Phaser.Input.Keyboard.Key;
  attackJ: Phaser.Input.Keyboard.Key;
  specialK: Phaser.Input.Keyboard.Key;
  dodgeL: Phaser.Input.Keyboard.Key;
  switchQ: Phaser.Input.Keyboard.Key;
  switchShift: Phaser.Input.Keyboard.Key;
  interactEnter: Phaser.Input.Keyboard.Key;
  pauseEsc: Phaser.Input.Keyboard.Key;
  pauseP: Phaser.Input.Keyboard.Key;
}

interface BindingState {
  current: Record<InputAction, boolean>;
}

function isGamepadPressed(gamepad: Phaser.Input.Gamepad.Gamepad | undefined, button: number): boolean {
  return Boolean(gamepad?.buttons[button]?.pressed);
}

export function createInputCollector(scene: Phaser.Scene): () => InputFrame {
  const keys = scene.input.keyboard?.addKeys({
    leftA: Phaser.Input.Keyboard.KeyCodes.A,
    leftArrow: Phaser.Input.Keyboard.KeyCodes.LEFT,
    rightD: Phaser.Input.Keyboard.KeyCodes.D,
    rightArrow: Phaser.Input.Keyboard.KeyCodes.RIGHT,
    jumpSpace: Phaser.Input.Keyboard.KeyCodes.SPACE,
    jumpUp: Phaser.Input.Keyboard.KeyCodes.UP,
    attackJ: Phaser.Input.Keyboard.KeyCodes.J,
    specialK: Phaser.Input.Keyboard.KeyCodes.K,
    dodgeL: Phaser.Input.Keyboard.KeyCodes.L,
    switchQ: Phaser.Input.Keyboard.KeyCodes.Q,
    switchShift: Phaser.Input.Keyboard.KeyCodes.SHIFT,
    interactEnter: Phaser.Input.Keyboard.KeyCodes.ENTER,
    pauseEsc: Phaser.Input.Keyboard.KeyCodes.ESC,
    pauseP: Phaser.Input.Keyboard.KeyCodes.P,
  }) as GameKeys | undefined;

  const previous: BindingState = {
    current: createActionRecord(),
  };

  return (): InputFrame => {
    const pad = scene.input.gamepad?.getPad(0);
    const axisX = pad?.axes.length ? pad.axes[0].getValue() : 0;

    const held = createActionRecord();
    held.moveLeft = Boolean(keys?.leftA.isDown || keys?.leftArrow.isDown || axisX < -0.2 || isGamepadPressed(pad, 14));
    held.moveRight = Boolean(keys?.rightD.isDown || keys?.rightArrow.isDown || axisX > 0.2 || isGamepadPressed(pad, 15));
    held.jump = Boolean(keys?.jumpSpace.isDown || keys?.jumpUp.isDown || isGamepadPressed(pad, 0));
    held.lightAttack = Boolean(keys?.attackJ.isDown || isGamepadPressed(pad, 2));
    held.special = Boolean(keys?.specialK.isDown || isGamepadPressed(pad, 3));
    held.dodge = Boolean(keys?.dodgeL.isDown || isGamepadPressed(pad, 1));
    held.switchHero = Boolean(keys?.switchQ.isDown || keys?.switchShift.isDown || isGamepadPressed(pad, 4) || isGamepadPressed(pad, 5));
    held.interact = Boolean(keys?.interactEnter.isDown || isGamepadPressed(pad, 9));
    held.pause = Boolean(keys?.pauseEsc.isDown || keys?.pauseP.isDown || isGamepadPressed(pad, 8));

    const pressed = createActionRecord();
    for (const action of Object.keys(held) as InputAction[]) {
      pressed[action] = held[action] && !previous.current[action];
    }

    previous.current = held;

    return {
      held,
      pressed,
      usingGamepad: Boolean(pad),
    };
  };
}
