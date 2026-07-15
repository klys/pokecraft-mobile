/**
 * gamepad.ts — drop-in Web Gamepad helper for the PokeCraft web client.
 *
 * This file is meant to be copied into the client-poke.io React app (e.g.
 * src/input/gamepad.ts). It uses ONLY the standard Web Gamepad API, which is
 * available in the Android System WebView that Capacitor runs, as well as in
 * desktop Chromium/Firefox — so the same code powers web and Android builds.
 *
 * Usage:
 *
 *   import { GamepadManager, GamepadButton } from './input/gamepad';
 *
 *   const pads = new GamepadManager();
 *   pads.start();
 *
 *   // Poll once per animation frame from your game loop:
 *   function tick() {
 *     const s = pads.sample();
 *     if (s.connected) {
 *       player.move(s.axes.moveX, s.axes.moveY);           // left stick / d-pad
 *       if (s.pressed(GamepadButton.A)) player.interact(); // edge-triggered
 *     }
 *     requestAnimationFrame(tick);
 *   }
 *   requestAnimationFrame(tick);
 *
 *   // ...and pads.stop() on unmount.
 */

/** Standard-mapping button indices (https://w3c.github.io/gamepad/#remapping). */
export enum GamepadButton {
  A = 0,          // Xbox A / PlayStation Cross
  B = 1,          // Xbox B / PlayStation Circle
  X = 2,          // Xbox X / PlayStation Square
  Y = 3,          // Xbox Y / PlayStation Triangle
  LeftBumper = 4,
  RightBumper = 5,
  LeftTrigger = 6,
  RightTrigger = 7,
  Select = 8,     // View / Share
  Start = 9,      // Menu / Options
  LeftStick = 10,
  RightStick = 11,
  DpadUp = 12,
  DpadDown = 13,
  DpadLeft = 14,
  DpadRight = 15,
  Guide = 16,
}

export interface GamepadSample {
  connected: boolean;
  /** Normalised movement, dead-zoned, combining the left stick and the d-pad. */
  axes: { moveX: number; moveY: number; lookX: number; lookY: number };
  /** True while a button is held this frame. */
  down: (button: GamepadButton) => boolean;
  /** True only on the frame a button transitions from up -> down. */
  pressed: (button: GamepadButton) => boolean;
  /** True only on the frame a button transitions from down -> up. */
  released: (button: GamepadButton) => boolean;
}

const DEAD_ZONE = 0.25;

const applyDeadZone = (value: number) =>
  Math.abs(value) < DEAD_ZONE ? 0 : value;

export class GamepadManager {
  private prevButtons: boolean[] = [];
  private curButtons: boolean[] = [];
  private running = false;

  /** Optional: react to connect/disconnect (e.g. to swap on-screen hints). */
  onConnect?: (gamepad: Gamepad) => void;
  onDisconnect?: (gamepad: Gamepad) => void;

  start() {
    if (this.running) return;
    this.running = true;
    window.addEventListener('gamepadconnected', this.handleConnect);
    window.addEventListener('gamepaddisconnected', this.handleDisconnect);
  }

  stop() {
    this.running = false;
    window.removeEventListener('gamepadconnected', this.handleConnect);
    window.removeEventListener('gamepaddisconnected', this.handleDisconnect);
  }

  private handleConnect = (e: GamepadEvent) => this.onConnect?.(e.gamepad);
  private handleDisconnect = (e: GamepadEvent) => this.onDisconnect?.(e.gamepad);

  private firstGamepad(): Gamepad | null {
    // navigator.getGamepads() may contain nulls; return the first live pad.
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const pad of pads) {
      if (pad && pad.connected) return pad;
    }
    return null;
  }

  /**
   * Snapshot the controller state for this frame. Call exactly once per frame
   * so the pressed()/released() edge detection stays correct.
   */
  sample(): GamepadSample {
    const pad = this.firstGamepad();

    this.prevButtons = this.curButtons;
    this.curButtons = pad ? pad.buttons.map((b) => b.pressed) : [];

    const down = (button: GamepadButton) => !!this.curButtons[button];
    const pressed = (button: GamepadButton) =>
      !!this.curButtons[button] && !this.prevButtons[button];
    const released = (button: GamepadButton) =>
      !this.curButtons[button] && !!this.prevButtons[button];

    if (!pad) {
      return {
        connected: false,
        axes: { moveX: 0, moveY: 0, lookX: 0, lookY: 0 },
        down,
        pressed,
        released,
      };
    }

    // Left stick, falling back to / combined with the d-pad.
    let moveX = applyDeadZone(pad.axes[0] ?? 0);
    let moveY = applyDeadZone(pad.axes[1] ?? 0);
    if (down(GamepadButton.DpadLeft)) moveX = -1;
    if (down(GamepadButton.DpadRight)) moveX = 1;
    if (down(GamepadButton.DpadUp)) moveY = -1;
    if (down(GamepadButton.DpadDown)) moveY = 1;

    const lookX = applyDeadZone(pad.axes[2] ?? 0);
    const lookY = applyDeadZone(pad.axes[3] ?? 0);

    return {
      connected: true,
      axes: { moveX, moveY, lookX, lookY },
      down,
      pressed,
      released,
    };
  }
}
