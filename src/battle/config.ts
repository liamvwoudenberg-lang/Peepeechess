import type { PieceSymbol } from "chess.js";
export const FIXED_DT = 1 / 60;
export const ARENA_LIMIT = 6.65;
export const COMBAT_SECONDS = 90;
export const COUNTDOWN_SECONDS = 3;
export const FIGHTERS = {
  p: {
    name: "Agile Spearman",
    hp: 80,
    stamina: 120,
    damage: 12,
    speed: 9,
    reach: 1.95,
    light: 0.4,
    heavy: 0.88,
    parry: 0.17,
    ability: "Last Stand",
    cooldown: 15,
    description:
      "Below 35% health: five seconds of faster movement and attacks.",
  },
  n: {
    name: "Armored Duelist",
    hp: 125,
    stamina: 110,
    damage: 22,
    speed: 7,
    reach: 1.65,
    light: 0.53,
    heavy: 1.04,
    parry: 0.21,
    ability: "Lunging Strike",
    cooldown: 9,
    description: "Commit to a forward charge. Dodge aside or parry the strike.",
  },
  b: {
    name: "Arcane Spellblade",
    hp: 90,
    stamina: 115,
    damage: 18,
    speed: 8,
    reach: 1.75,
    light: 0.48,
    heavy: 0.98,
    parry: 0.17,
    ability: "Blink",
    cooldown: 8,
    description:
      "Teleport in your movement direction, or forward when standing still.",
  },
  r: {
    name: "Fortress Guardian",
    hp: 190,
    stamina: 90,
    damage: 25,
    speed: 4,
    reach: 2.0,
    light: 0.69,
    heavy: 1.23,
    parry: 0.16,
    ability: "Fortress Guard",
    cooldown: 12,
    description: "Four seconds of stronger guard and stagger resistance.",
  },
  q: {
    name: "Royal Assassin",
    hp: 135,
    stamina: 115,
    damage: 24,
    speed: 9,
    reach: 1.65,
    light: 0.47,
    heavy: 0.96,
    parry: 0.17,
    ability: "Royal Fury",
    cooldown: 14,
    description: "Six seconds of quicker attacks and longer combo chains.",
  },
  k: {
    name: "Royal Champion",
    hp: 160,
    stamina: 100,
    damage: 18,
    speed: 6,
    reach: 1.8,
    light: 0.54,
    heavy: 1.05,
    parry: 0.21,
    ability: "Royal Counter",
    cooldown: 10,
    description:
      "A committed counter stance. A precisely timed incoming hit triggers a riposte.",
  },
} as const satisfies Record<PieceSymbol, unknown>;
export const ROLE_NAMES: Record<PieceSymbol, string> = {
  p: "Pawn",
  n: "Knight",
  b: "Bishop",
  r: "Rook",
  q: "Queen",
  k: "King",
};
export type Action = "light" | "heavy" | "dodge" | "parry" | "ability";
export const ACTIONS: Action[] = [
  "light",
  "heavy",
  "dodge",
  "parry",
  "ability",
];
export type BindingAction =
  | Action
  | "up"
  | "down"
  | "left"
  | "right"
  | "sprint"
  | "block"
  | "lock";
export type Bindings = Record<BindingAction, string>;
export const DEFAULT_BINDINGS: Record<"w" | "b", Bindings> = {
  w: {
    up: "KeyW",
    down: "KeyS",
    left: "KeyA",
    right: "KeyD",
    sprint: "ShiftLeft",
    light: "Mouse0",
    heavy: "Mouse2",
    dodge: "Space",
    block: "KeyQ",
    parry: "KeyE",
    ability: "KeyR",
    lock: "Tab",
  },
  b: {
    up: "ArrowUp",
    down: "ArrowDown",
    left: "ArrowLeft",
    right: "ArrowRight",
    sprint: "Enter",
    light: "KeyJ",
    heavy: "KeyK",
    dodge: "KeyL",
    block: "KeyU",
    parry: "KeyI",
    ability: "KeyO",
    lock: "KeyP",
  },
};
