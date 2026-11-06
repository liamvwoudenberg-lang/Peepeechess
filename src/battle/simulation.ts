import type { Color, PieceSymbol } from "chess.js";
import {
  FIGHTERS,
  ACTIONS,
  ARENA_LIMIT,
  COUNTDOWN_SECONDS,
  COMBAT_SECONDS,
  type Action,
} from "./config";
import { other, type CaptureIntent } from "./rules";
export type FighterState =
  | "Idle"
  | "Moving"
  | "Attacking"
  | "Blocking"
  | "Parrying"
  | "Dodging"
  | "Staggered"
  | "AbilityCasting"
  | "Defeated";
export interface CombatInput {
  moveX: number;
  moveZ: number;
  yaw: number;
  lock: boolean;
  sprint: boolean;
  block: boolean;
  light: number;
  heavy: number;
  dodge: number;
  parry: number;
  ability: number;
}
export const neutralInput = (): CombatInput => ({
  moveX: 0,
  moveZ: 0,
  yaw: 0,
  lock: true,
  sprint: false,
  block: false,
  light: 0,
  heavy: 0,
  dodge: 0,
  parry: 0,
  ability: 0,
});
export interface Attack {
  kind: "light" | "heavy" | "lunge";
  time: number;
  duration: number;
  startup: number;
  activeEnd: number;
  damage: number;
  range: number;
  hit: boolean;
  queue: "light" | "heavy" | null;
  combo: number;
}
export interface Fighter {
  color: Color;
  role: PieceSymbol;
  hp: number;
  stamina: number;
  x: number;
  z: number;
  vx: number;
  vz: number;
  yaw: number;
  state: FighterState;
  stateTime: number;
  attack: Attack | null;
  seen: Record<Action, number>;
  cooldown: number;
  buff: number;
  counter: number;
  combo: number;
  comboUntil: number;
  regenAt: number;
  staggerImmune: number;
  dodgeX: number;
  dodgeZ: number;
}
export interface CombatEvent {
  id: number;
  at: number;
  type:
    | "hit"
    | "block"
    | "parry"
    | "dodge"
    | "guardbreak"
    | "ability"
    | "whiff";
  actor: Color;
  target: Color;
  damage: number;
}
export interface CombatState {
  version: 1;
  id: string;
  time: number;
  countdown: number;
  remaining: number;
  attacker: Color;
  fighters: Record<Color, Fighter>;
  events: CombatEvent[];
  eventId: number;
  winner: Color | null;
  reason: string;
}
const clamp = (v: number, min: number, max: number) =>
  Math.max(min, Math.min(max, v));
export function sanitizeInput(
  value: Partial<CombatInput> | null | undefined,
): CombatInput {
  const v = value || {},
    finite = (n: unknown) =>
      typeof n === "number" && Number.isFinite(n) ? n : 0;
  const result = {
    ...neutralInput(),
    moveX: clamp(finite(v.moveX), -1, 1),
    moveZ: clamp(finite(v.moveZ), -1, 1),
    yaw: finite(v.yaw) % (Math.PI * 2),
    lock: v.lock !== false,
    sprint: v.sprint === true,
    block: v.block === true,
  };
  const length = Math.hypot(result.moveX, result.moveZ);
  if (length > 1) {
    result.moveX /= length;
    result.moveZ /= length;
  }
  for (const key of ACTIONS)
    result[key] = clamp(Math.floor(finite(v[key])), 0, 1e9);
  return result;
}
export function createCombat(intent: CaptureIntent): CombatState {
  const make = (color: Color): Fighter => {
    const role =
        intent.attacker.color === color
          ? intent.attacker.role
          : intent.defender.role,
      c = FIGHTERS[role];
    return {
      color,
      role,
      hp: c.hp,
      stamina: c.stamina,
      x: 0,
      z: color === "w" ? -2.6 : 2.6,
      vx: 0,
      vz: 0,
      yaw: color === "w" ? 0 : Math.PI,
      state: "Idle",
      stateTime: 0,
      attack: null,
      seen: { light: 0, heavy: 0, dodge: 0, parry: 0, ability: 0 },
      cooldown: 0,
      buff: 0,
      counter: 0,
      combo: 0,
      comboUntil: 0,
      regenAt: 0,
      staggerImmune: 0,
      dodgeX: 0,
      dodgeZ: 0,
    };
  };
  return {
    version: 1,
    id: intent.id,
    time: 0,
    countdown: COUNTDOWN_SECONDS,
    remaining: COMBAT_SECONDS,
    attacker: intent.attacker.color,
    fighters: { w: make("w"), b: make("b") },
    events: [],
    eventId: 0,
    winner: null,
    reason: "",
  };
}
function emit(
  s: CombatState,
  type: CombatEvent["type"],
  actor: Color,
  damage = 0,
) {
  s.events.push({
    id: ++s.eventId,
    at: s.time,
    type,
    actor,
    target: other(actor),
    damage,
  });
  s.events = s.events.slice(-12);
}
function spend(s: CombatState, f: Fighter, amount: number) {
  if (f.stamina + 1e-6 < amount) return false;
  f.stamina = Math.max(0, f.stamina - amount);
  f.regenAt = s.time + 0.7;
  return true;
}
function enter(f: Fighter, state: FighterState) {
  f.state = state;
  f.stateTime = 0;
  f.vx *= 0.25;
  f.vz *= 0.25;
}
function buffed(f: Fighter) {
  return f.buff > 0 && (f.role === "p" || f.role === "q");
}
function startAttack(s: CombatState, f: Fighter, kind: Attack["kind"]) {
  const cfg = FIGHTERS[f.role],
    combo =
      s.time < f.comboUntil
        ? Math.min(f.combo + 1, f.role === "q" && f.buff > 0 ? 5 : 3)
        : 1;
  if (
    s.time < f.comboUntil &&
    f.combo >= (f.role === "q" && f.buff > 0 ? 5 : 3)
  )
    return false;
  const cost =
    (kind === "light" ? 14 : kind === "heavy" ? 29 : 32) +
    Math.max(0, combo - 1) * 3;
  if (!spend(s, f, cost)) return false;
  const duration =
      (kind === "light" ? cfg.light : kind === "heavy" ? cfg.heavy : 1.12) /
      (buffed(f) ? 1.2 : 1),
    startup = duration * (kind === "light" ? 0.38 : 0.52),
    counter = f.counter > 0 ? 1.6 : 1;
  f.attack = {
    kind,
    time: 0,
    duration,
    startup,
    activeEnd: startup + 0.13,
    range:
      kind === "lunge"
        ? 2.35
        : kind === "heavy" && f.role === "b"
          ? 4.6
          : cfg.reach + (kind === "heavy" ? 0.35 : 0),
    damage:
      cfg.damage *
      (kind === "light" ? 1 : kind === "heavy" ? 1.65 : 1.5) *
      counter *
      (1 + 0.07 * (combo - 1)),
    hit: false,
    queue: null,
    combo,
  };
  f.counter = 0;
  f.combo = combo;
  enter(f, "Attacking");
  return true;
}
function ability(s: CombatState, f: Fighter, input: CombatInput) {
  if (f.cooldown > 0) return;
  if (f.role === "p" && f.hp > FIGHTERS.p.hp * 0.35) return;
  if (f.role === "n") {
    if (!startAttack(s, f, "lunge")) return;
  } else {
    if (!spend(s, f, f.role === "b" ? 32 : 20)) return;
    enter(f, f.role === "k" ? "Parrying" : "AbilityCasting");
    if (f.role === "b") {
      const length = Math.hypot(input.moveX, input.moveZ),
        x = length ? input.moveX / length : Math.sin(f.yaw),
        z = length ? input.moveZ / length : Math.cos(f.yaw);
      f.x = clamp(f.x + x * 2.6, -ARENA_LIMIT, ARENA_LIMIT);
      f.z = clamp(f.z + z * 2.6, -ARENA_LIMIT, ARENA_LIMIT);
    }
    if (f.role === "p") f.buff = 5;
    if (f.role === "r") f.buff = 4;
    if (f.role === "q") f.buff = 6;
    if (f.role === "k") f.buff = 0.44;
  }
  f.cooldown = FIGHTERS[f.role].cooldown;
  emit(s, "ability", f.color);
}
function facing(a: Fighter, b: Fighter, arc = 0.3) {
  const dx = b.x - a.x,
    dz = b.z - a.z,
    d = Math.hypot(dx, dz) || 1;
  return (Math.sin(a.yaw) * dx + Math.cos(a.yaw) * dz) / d > arc;
}
function stagger(s: CombatState, f: Fighter, duration: number) {
  if (f.buff > 0 && f.role === "r") return;
  if (s.time < f.staggerImmune) return;
  f.attack = null;
  enter(f, "Staggered");
  f.staggerImmune = s.time + duration + 0.8;
  f.stateTime = -Math.max(0, duration - 0.43);
}
function hit(s: CombatState, a: Fighter, d: Fighter, attack: Attack) {
  if (d.state === "Dodging" && d.stateTime >= 0.065 && d.stateTime <= 0.31) {
    emit(s, "dodge", d.color);
    return;
  }
  if (d.state === "AbilityCasting" && d.role === "b" && d.stateTime < 0.2) {
    emit(s, "dodge", d.color);
    return;
  }
  const front = facing(d, a, 0.18),
    perfect =
      front &&
      d.state === "Parrying" &&
      d.stateTime >= 0.045 &&
      d.stateTime <
        0.045 +
          FIGHTERS[d.role].parry +
          (d.role === "k" && d.buff > 0 ? 0.14 : 0);
  if (perfect) {
    stagger(s, a, 0.9);
    d.counter = 1.6;
    d.stamina = Math.min(FIGHTERS[d.role].stamina, d.stamina + 12);
    if (d.role === "k" && d.buff > 0) a.hp = Math.max(0, a.hp - 14);
    emit(s, "parry", d.color);
    return;
  }
  let damage = attack.damage;
  if (front && d.state === "Blocking") {
    const cost =
      (attack.kind === "light" ? 19 : 36) *
      (d.role === "r" && d.buff > 0 ? 0.45 : 1);
    if (spend(s, d, cost)) {
      damage *= d.role === "r" && d.buff > 0 ? 0 : 0.08;
      emit(s, "block", d.color, Math.round(damage));
      d.hp = Math.max(0, d.hp - damage);
      return;
    }
    d.stamina = 0;
    d.regenAt = s.time + 1.2;
    stagger(s, d, 1.0);
    damage *= 0.7;
    emit(s, "guardbreak", a.color, Math.round(damage));
  } else {
    if (d.role === "r" && d.buff > 0) damage *= 0.65;
    stagger(s, d, attack.kind === "light" ? 0.3 : 0.52);
    emit(s, "hit", a.color, Math.round(damage));
  }
  d.hp = Math.max(0, d.hp - damage);
}
function turn(f: Fighter, target: number, dt: number, rate = 10) {
  const delta = Math.atan2(Math.sin(target - f.yaw), Math.cos(target - f.yaw));
  const next = f.yaw + clamp(delta, -rate * dt, rate * dt);
  f.yaw = Math.atan2(Math.sin(next), Math.cos(next));
}
/** The host alone advances fixed steps. Inputs contain intent, never damage or outcomes. */
export function stepCombat(
  s: CombatState,
  raw: Record<Color, Partial<CombatInput>>,
  dt = 1 / 60,
): CombatState {
  if (s.winner) return s;
  dt = clamp(dt, 0, 1 / 30);
  s.time += dt;
  const inputs = { w: sanitizeInput(raw.w), b: sanitizeInput(raw.b) },
    pressed = {} as Record<Color, Record<Action, boolean>>;
  for (const color of ["w", "b"] as Color[]) {
    const f = s.fighters[color];
    pressed[color] = {} as Record<Action, boolean>;
    for (const k of ACTIONS) {
      pressed[color][k] = inputs[color][k] > f.seen[k];
      f.seen[k] = Math.max(f.seen[k], inputs[color][k]);
    }
  }
  if (s.countdown > 0) {
    s.countdown = Math.max(0, s.countdown - dt);
    return s;
  }
  s.remaining = Math.max(0, s.remaining - dt);
  for (const color of ["w", "b"] as Color[]) {
    const f = s.fighters[color],
      enemy = s.fighters[other(color)],
      i = inputs[color],
      p = pressed[color],
      cfg = FIGHTERS[f.role];
    f.stateTime += dt;
    f.cooldown = Math.max(0, f.cooldown - dt);
    f.buff = Math.max(0, f.buff - dt);
    f.counter = Math.max(0, f.counter - dt);
    if (
      s.time >= f.regenAt &&
      f.state !== "Blocking" &&
      f.state !== "Attacking" &&
      f.state !== "Dodging"
    )
      f.stamina = Math.min(cfg.stamina, f.stamina + 24 * dt);
    if (f.state === "Staggered" && f.stateTime >= 0.43) enter(f, "Idle");
    if (f.state === "Parrying" && f.stateTime >= 0.6) enter(f, "Idle");
    if (f.state === "AbilityCasting" && f.stateTime >= 0.42) enter(f, "Idle");
    if (f.state === "Dodging") {
      if (f.stateTime < 0.39) {
        f.x += f.dodgeX * 7.6 * dt;
        f.z += f.dodgeZ * 7.6 * dt;
      }
      if (f.stateTime >= 0.64) enter(f, "Idle");
    }
    if (f.state === "Attacking" && f.attack) {
      const a = f.attack;
      a.time += dt;
      if (a.kind === "lunge" && a.time < a.activeEnd) {
        f.x += Math.sin(f.yaw) * 4.5 * dt;
        f.z += Math.cos(f.yaw) * 4.5 * dt;
      }
      if (a.time > a.duration - 0.18 && (p.light || p.heavy) && !a.queue)
        a.queue = p.heavy ? "heavy" : "light";
      if (a.time >= a.duration) {
        const queue = a.queue;
        f.attack = null;
        f.comboUntil = s.time + 0.28;
        enter(f, "Idle");
        if (queue) startAttack(s, f, queue);
      }
    }
    const free = ["Idle", "Moving", "Blocking"].includes(f.state);
    if (free) {
      if (p.dodge && spend(s, f, f.role === "p" ? 21 : 27)) {
        const length = Math.hypot(i.moveX, i.moveZ);
        f.dodgeX = length ? i.moveX / length : -Math.sin(f.yaw);
        f.dodgeZ = length ? i.moveZ / length : -Math.cos(f.yaw);
        enter(f, "Dodging");
      } else if (p.parry && spend(s, f, 15)) {
        enter(f, "Parrying");
      } else if (p.ability) ability(s, f, i);
      else if (p.heavy || p.light)
        startAttack(s, f, p.heavy ? "heavy" : "light");
      if (["Idle", "Moving", "Blocking"].includes(f.state)) {
        if (i.block && f.stamina > 1) {
          if (f.state !== "Blocking") enter(f, "Blocking");
          f.stamina = Math.max(0, f.stamina - 5 * dt);
          f.regenAt = s.time + 0.7;
        } else {
          f.state = Math.hypot(i.moveX, i.moveZ) > 0.05 ? "Moving" : "Idle";
        }
        const sprint = i.sprint && f.state !== "Blocking" && f.stamina > 1;
        if (sprint) spend(s, f, 17 * dt);
        const speed =
            (1.05 + cfg.speed * 0.29) *
            (sprint ? 1.5 : 1) *
            (f.state === "Blocking" ? 0.4 : 1) *
            (f.role === "p" && f.buff > 0 ? 1.3 : 1),
          smooth = 1 - Math.exp(-18 * dt);
        f.vx += (i.moveX * speed - f.vx) * smooth;
        f.vz += (i.moveZ * speed - f.vz) * smooth;
        f.x += f.vx * dt;
        f.z += f.vz * dt;
      }
    }
    if (f.state !== "Dodging" && f.state !== "Staggered")
      turn(
        f,
        i.lock ? Math.atan2(enemy.x - f.x, enemy.z - f.z) : i.yaw,
        dt,
        f.state === "Attacking" ? 2.2 : 10,
      );
    f.x = clamp(f.x, -ARENA_LIMIT, ARENA_LIMIT);
    f.z = clamp(f.z, -ARENA_LIMIT, ARENA_LIMIT);
  }
  const w = s.fighters.w,
    b = s.fighters.b,
    dx = b.x - w.x,
    dz = b.z - w.z,
    distance = Math.hypot(dx, dz);
  if (distance < 1.15) {
    const nx = distance ? dx / distance : 1,
      nz = distance ? dz / distance : 0,
      push = (1.15 - distance) / 2;
    w.x = clamp(w.x - nx * push, -ARENA_LIMIT, ARENA_LIMIT);
    w.z = clamp(w.z - nz * push, -ARENA_LIMIT, ARENA_LIMIT);
    b.x = clamp(b.x + nx * push, -ARENA_LIMIT, ARENA_LIMIT);
    b.z = clamp(b.z + nz * push, -ARENA_LIMIT, ARENA_LIMIT);
  }
  const strikes: { a: Fighter; d: Fighter; attack: Attack }[] = [];
  for (const color of ["w", "b"] as Color[]) {
    const a = s.fighters[color],
      d = s.fighters[other(color)],
      attack = a.attack;
    if (
      attack &&
      !attack.hit &&
      attack.time >= attack.startup &&
      attack.time <= attack.activeEnd &&
      Math.hypot(a.x - d.x, a.z - d.z) <= attack.range &&
      facing(a, d, 0.4)
    ) {
      attack.hit = true;
      strikes.push({ a, d, attack });
    }
  }
  for (const strike of strikes) hit(s, strike.a, strike.d, strike.attack);
  if (w.hp <= 0 || b.hp <= 0) {
    s.winner =
      w.hp <= 0 && b.hp <= 0 ? other(s.attacker) : w.hp <= 0 ? "b" : "w";
    s.reason =
      w.hp <= 0 && b.hp <= 0
        ? "Simultaneous knockout: defender holds"
        : "Knockout";
  } else if (s.remaining <= 0) {
    const delta = w.hp / FIGHTERS[w.role].hp - b.hp / FIGHTERS[b.role].hp;
    s.winner =
      Math.abs(delta) < 1e-8 ? other(s.attacker) : delta > 0 ? "w" : "b";
    s.reason =
      Math.abs(delta) < 1e-8
        ? "Time expired: defender holds the tie"
        : "Time expired: higher health percentage wins";
  }
  for (const f of [w, b])
    if (f.hp <= 0) {
      f.state = "Defeated";
      f.attack = null;
      f.vx = f.vz = 0;
    }
  return s;
}
