/** battle-royal-v1 wire types. godot/contracts/royal/v1/schema.json is authoritative; v1 types are reused, never changed. */
import type { Id, Color, Versioned, Combatant, BattleRequest, BattleResult, CombatSnapshot, FighterStats, MatchState, Role } from "../../v1/types";
export type RoyalRulesetId = "battle-royal-v1";
export interface RoyalHeader extends Versioned { rulesetId: RoyalRulesetId }
/** Like v1 Combatant but the king role is allowed. */
export interface RoyalCombatant extends Omit<Combatant, "role"> { role: Role }
/** v1 BattleRequest with king-capable combatants: the payload handed to CombatSimulation.start(request, options). */
export interface RoyalBattleRequest extends Omit<BattleRequest, "attacker" | "defender"> { attacker: RoyalCombatant; defender: RoyalCombatant }
/** The King's persistent resources. stamina is quantised to 0.01 as snapshots report it; hp 0 only in an end state. */
export interface RoyalKingState { hp: number; stamina: number; cooldownTicks: number }
export interface RoyalKingCombatant extends Omit<Combatant, "role"> { role: "k"; startHp: number; startStamina: number; startCooldown: number }
/** The frozen mating position: the checkers (ordered: ascending material value, then square a1..h8) vs the mated King. */
export interface RoyalSequenceRequest extends RoyalHeader {
  battleId: Id; matchId: Id; expectedRevision: number; beforeFen: string; mated: Color;
  king: RoyalKingCombatant; attackers: RoyalCombatant[]; arenaId: "stone-v1"; startTick: number;
}
/** One duel: a BattleRequest-compatible payload (King = attacker) plus the King's carried start state. */
export interface RoyalDuelRequest extends RoyalHeader { battleId: Id; duelIndex: number; duelCount: number; kingStart: RoyalKingState; battle: RoyalBattleRequest }
export interface RoyalDuelResult extends RoyalHeader { battleId: Id; duelIndex: number; duelCount: number; result: BattleResult; kingEnd: RoyalKingState; kingSurvived: boolean }
export interface RoyalSequenceProgress extends RoyalHeader {
  battleId: Id; matchId: Id; status: "active"; duelIndex: number; duelCount: number; currentBattleId: Id | null;
  king: RoyalKingState; defeated: Id[]; remaining: Id[];
}
export interface RoyalSequenceResult extends RoyalHeader {
  battleId: Id; matchId: Id; expectedRevision: number; outcome: "king_survived" | "king_fell" | "unplayable" | "abandoned";
  duels: RoyalDuelResult[]; defeated: Id[]; kingEnd: RoyalKingState; resolvedTick: number;
  matchResult: "1-0" | "0-1" | "1/2-1/2" | null; reason: string | null; fenAfter: string;
}
export interface RoyalMatchState extends Omit<MatchState, "mode" | "rulesetId" | "battle"> {
  mode: "battle"; rulesetId: RoyalRulesetId; battle: RoyalBattleRequest | null; royal: RoyalSequenceProgress | null;
}
export interface RoyalContracts {
  RoyalCombatant: RoyalCombatant; RoyalBattleRequest: RoyalBattleRequest; RoyalKingState: RoyalKingState;
  RoyalKingCombatant: RoyalKingCombatant; RoyalSequenceRequest: RoyalSequenceRequest; RoyalDuelRequest: RoyalDuelRequest;
  RoyalDuelResult: RoyalDuelResult; RoyalSequenceProgress: RoyalSequenceProgress; RoyalSequenceResult: RoyalSequenceResult;
  RoyalMatchState: RoyalMatchState; BattleResult: BattleResult; CombatSnapshot: CombatSnapshot; FighterStats: FighterStats;
}
