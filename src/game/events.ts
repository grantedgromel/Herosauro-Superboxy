import type { ViewModel } from "./types";

type EventPayloadMap = {
  "hud:update": ViewModel;
  "game:start": undefined;
  "game:restart": undefined;
  "game:resume": undefined;
};

class GameBus {
  private target = new EventTarget();

  on<K extends keyof EventPayloadMap>(type: K, listener: (detail: EventPayloadMap[K]) => void): () => void {
    const wrapped = (event: Event): void => {
      listener((event as CustomEvent<EventPayloadMap[K]>).detail);
    };
    this.target.addEventListener(type, wrapped);
    return () => this.target.removeEventListener(type, wrapped);
  }

  emit<K extends keyof EventPayloadMap>(type: K, detail: EventPayloadMap[K]): void {
    this.target.dispatchEvent(new CustomEvent(type, { detail }));
  }
}

export const gameBus = new GameBus();
