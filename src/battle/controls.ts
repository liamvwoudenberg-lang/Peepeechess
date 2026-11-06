import type { Color } from "chess.js";
import {
  ACTIONS,
  DEFAULT_BINDINGS,
  type Action,
  type Bindings,
} from "./config";
import { neutralInput, type CombatInput, type CombatState } from "./simulation";
import type { CameraControl } from "./ArenaRenderer";
export class CombatControls {
  keys = new Set<string>();
  touch: Record<Color, { x: number; z: number; block: boolean }> = {
    w: { x: 0, z: 0, block: false },
    b: { x: 0, z: 0, block: false },
  };
  counts: Record<Color, Record<Action, number>> = {
    w: { light: 0, heavy: 0, dodge: 0, parry: 0, ability: 0 },
    b: { light: 0, heavy: 0, dodge: 0, parry: 0, ability: 0 },
  };
  enabled = true;
  private pads = new Map<string, boolean>();
  constructor(
    public colors: Color[],
    public cameras: Record<Color, CameraControl>,
    public bindings: Record<Color, Bindings> = DEFAULT_BINDINGS,
    combat?: CombatState,
  ) {
    if (combat)
      for (const c of colors) this.counts[c] = { ...combat.fighters[c].seen };
    window.addEventListener("keydown", this.down);
    window.addEventListener("keyup", this.up);
    window.addEventListener("blur", this.clear);
  }
  press(color: Color, action: Action) {
    if (this.enabled && this.colors.includes(color))
      this.counts[color][action]++;
  }
  toggle(color: Color) {
    this.cameras[color].locked = !this.cameras[color].locked;
  }
  mouse(color: Color, button: number) {
    for (const action of ACTIONS)
      if (this.bindings[color][action] === `Mouse${button}`)
        this.press(color, action);
  }
  private down = (e: KeyboardEvent) => {
    if (
      !this.enabled ||
      (e.target as HTMLElement)?.matches("input,select,textarea")
    )
      return;
    const matched = this.colors.some((c) =>
      Object.values(this.bindings[c]).includes(e.code),
    );
    if (!matched) return;
    e.preventDefault();
    this.keys.add(e.code);
    if (e.repeat) return;
    for (const c of this.colors) {
      for (const action of ACTIONS)
        if (this.bindings[c][action] === e.code) this.press(c, action);
      if (this.bindings[c].lock === e.code) this.toggle(c);
    }
  };
  private up = (e: KeyboardEvent) => {
    this.keys.delete(e.code);
  };
  clear = () => {
    this.keys.clear();
    for (const c of this.colors) this.touch[c] = { x: 0, z: 0, block: false };
  };
  read(color: Color, dt: number): CombatInput {
    if (!this.enabled) return { ...neutralInput(), ...this.counts[color] };
    const b = this.bindings[color],
      held = (key: string) => (this.keys.has(key) ? 1 : 0),
      t = this.touch[color],
      cam = this.cameras[color];
    let x = held(b.right) - held(b.left) + t.x,
      z = held(b.up) - held(b.down) + t.z,
      sprint = Boolean(held(b.sprint) || Math.hypot(t.x, t.z) > 0.95),
      block = Boolean(held(b.block) || t.block);
    let connected: Gamepad[] = [];
    try {
      if (typeof navigator.getGamepads === "function")
        connected = Array.from(navigator.getGamepads()).filter(
          (pad): pad is Gamepad => Boolean(pad),
        );
    } catch {
      /* Touch and keyboard remain available when the browser blocks gamepads. */
    }
    const pad = connected[this.colors.indexOf(color)];
    if (pad) {
      const axis = (i: number) =>
        Math.abs(pad.axes[i] || 0) > 0.18 ? pad.axes[i] || 0 : 0;
      x += axis(0);
      z -= axis(1);
      cam.yaw += axis(2) * dt * 2.5;
      cam.pitch = Math.max(-0.08, Math.min(0.75, cam.pitch + axis(3) * dt));
      const buttons: Record<number, Action | "lock"> = {
        0: "dodge",
        1: "ability",
        2: "light",
        3: "heavy",
        5: "parry",
        10: "lock",
      };
      for (const [index, action] of Object.entries(buttons)) {
        const key = color + index,
          pressed = pad.buttons[Number(index)]?.pressed || false;
        if (pressed && !this.pads.get(key)) {
          if (action === "lock") this.toggle(color);
          else this.press(color, action);
        }
        this.pads.set(key, pressed);
      }
      block ||= pad.buttons[4]?.pressed || false;
      sprint ||= pad.buttons[6]?.pressed || false;
    }
    const length = Math.hypot(x, z);
    if (length > 1) {
      x /= length;
      z /= length;
    }
    return {
      ...this.counts[color],
      moveX: x * Math.cos(cam.yaw) + z * Math.sin(cam.yaw),
      moveZ: -x * Math.sin(cam.yaw) + z * Math.cos(cam.yaw),
      yaw: cam.yaw,
      lock: cam.locked,
      sprint,
      block,
    };
  }
  dispose() {
    this.clear();
    window.removeEventListener("keydown", this.down);
    window.removeEventListener("keyup", this.up);
    window.removeEventListener("blur", this.clear);
  }
}
