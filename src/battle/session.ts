import type { Color, Square } from "chess.js";
import type { Army } from "../game/battleProfiles";
import {
  createBattleMatch,
  attemptBattleMove,
  resolveBattleCapture,
  resignBattleMatch,
  type BattleMatch,
} from "./rules";
import {
  createCombat,
  neutralInput,
  stepCombat,
  type CombatState,
  type CombatInput,
} from "./simulation";
import { FIXED_DT } from "./config";
export interface BattleSnapshot {
  version: 1;
  match: BattleMatch;
  combat: CombatState | null;
  paused: boolean;
  revision: number;
  aftermath: number;
  drawOffers: Color[];
}
export type BattleCommand =
  | { type: "move"; from: Square; to: Square; promotion?: string }
  | { type: "resign" }
  | { type: "draw" }
  | { type: "continue" };
export interface BattleConnection {
  readonly kind: "local" | "server";
  send(command: BattleCommand, color: Color): void;
  input(color: Color, input: CombatInput): void;
  subscribe(fn: (s: BattleSnapshot) => void): () => void;
  close(): void;
}
/** Identical host logic is used by a shared device and the authoritative Node room. */
export class BattleHost {
  state: BattleSnapshot;
  inputs: Record<Color, CombatInput> = { w: neutralInput(), b: neutralInput() };
  private accumulator = 0;
  constructor(
    armies: Record<Color, Army> = { w: "royal", b: "skeletons" },
    fen?: string,
  ) {
    this.state = {
      version: 1,
      match: createBattleMatch(armies, fen),
      combat: null,
      paused: false,
      revision: 0,
      aftermath: 0,
      drawOffers: [],
    };
  }
  command(command: BattleCommand, color: Color) {
    const s = this.state;
    if (command.type === "resign") {
      s.match = resignBattleMatch(s.match, color);
      s.combat = null;
    } else if (command.type === "draw") {
      if (s.match.phase !== "board")
        throw Error("Draws can be agreed between duels.");
      s.drawOffers ||= [];
      if (!s.drawOffers.includes(color)) s.drawOffers.push(color);
      if (s.drawOffers.length === 2)
        s.match = {
          ...s.match,
          phase: "complete",
          result: "1/2-1/2",
          reason: "Agreed draw",
        };
    } else if (command.type === "move") {
      if (s.paused) throw Error("Resume the match first.");
      if (s.match.fen.split(" ")[1] !== color)
        throw Error("It is the other player’s turn.");
      s.match = attemptBattleMove(
        s.match,
        command.from,
        command.to,
        command.promotion,
      );
      s.drawOffers = [];
      if (s.match.pending) {
        s.combat = createCombat(s.match.pending);
        this.inputs = { w: neutralInput(), b: neutralInput() };
        s.aftermath = 0;
      }
    } else if (
      command.type === "continue" &&
      s.match.phase === "aftermath" &&
      s.aftermath >= 0.75
    )
      this.settle();
    s.revision++;
  }
  private settle() {
    const s = this.state;
    if (!s.combat?.winner || !s.match.pending) return;
    s.match = resolveBattleCapture(s.match, s.combat.id, s.combat.winner);
    s.combat = null;
    s.aftermath = 0;
    s.revision++;
  }
  advance(seconds: number) {
    const s = this.state;
    if (s.paused || !s.combat || s.match.phase === "complete") return;
    // Result presentation uses real elapsed time; slow rendering must not trap a finished duel.
    if (s.match.phase === "aftermath") {
      s.aftermath += Math.max(0, seconds);
      if (s.aftermath >= 3.5) this.settle();
      return;
    }
    this.accumulator += Math.max(0, Math.min(0.15, seconds));
    while (this.accumulator >= FIXED_DT) {
      this.accumulator -= FIXED_DT;
      if (s.match.phase === "combat") {
        stepCombat(s.combat, this.inputs, FIXED_DT);
        if (s.combat.winner) {
          s.match = { ...s.match, phase: "aftermath" };
          s.revision++;
        }
      } else if (s.match.phase === "aftermath") {
        s.aftermath += FIXED_DT;
        if (s.aftermath >= 3.5) {
          this.settle();
          break;
        }
      }
    }
  }
  pause(value: boolean) {
    this.state.paused = value;
    this.inputs = { w: neutralInput(), b: neutralInput() };
    if (this.state.combat)
      for (const f of Object.values(this.state.combat.fighters))
        f.seen = { light: 0, heavy: 0, dodge: 0, parry: 0, ability: 0 };
    this.state.revision++;
  }
}
