/** Wire v1. schema.json is authoritative; no Godot/Three objects on the wire. */
export type Id = string;
export type Color = "w" | "b";
export type Role = "p" | "n" | "b" | "r" | "q" | "k";
export type Promotion = "q" | "r" | "b" | "n" | null;
export interface Versioned { schemaVersion: 1 }
export interface Piece { pieceId: Id; square: string; color: Color; role: Role; characterId: string }
export interface HistoryEntry { from: string; to: string; promotion: Promotion; outcome: "quiet" | "attacker" | "defender"; fen: string }
export interface ChessGameState extends Versioned {
  matchId: Id; revision: number; ply: number; initialFen: string; fen: string;
  pieces: Piece[]; history: HistoryEntry[];
}
export interface ChessMoveRequest extends Versioned {
  matchId: Id; requestId: Id; playerId: Id; expectedRevision: number;
  from: string; to: string; promotion: Promotion;
}
export interface FighterStats extends Versioned {
  statsId: Id; role: Role; maxHp: number; maxStamina: number; baseDamage: number;
  moveSpeedMps: number; reachM: number; lightTicks: number; heavyTicks: number;
  parryTicks: number; abilityId: Id; cooldownTicks: number;
}
export interface Combatant extends Omit<Piece, "role"> { playerId: Id; role: Exclude<Role, "k">; stats: FighterStats }
export interface BattleRequest extends Versioned {
  matchId: Id; battleId: Id; expectedRevision: number; beforeFen: string;
  from: string; to: string; promotion: Promotion; attacker: Combatant; defender: Combatant;
  arenaId: "stone-v1"; startTick: number; countdownTicks: 180; durationTicks: 5400; seed: number;
}
export interface BattleResult extends Versioned {
  matchId: Id; battleId: Id; expectedRevision: number; resolvedTick: number;
  winnerPlayerId: Id; outcome: "attacker" | "defender";
  reason: "knockout" | "timeout_hp" | "timeout_tie" | "double_knockout";
  attackerHp: number; defenderHp: number;
}
export interface CombatInput extends Versioned {
  matchId: Id; battleId: Id; playerId: Id; sequence: number; clientTick: number;
  moveX: number; moveZ: number; yawRadians: number; lockTarget: boolean;
  sprint: boolean; block: boolean; light: number; heavy: number; dodge: number; parry: number; ability: number;
}
export interface Vec3 { x: number; y: number; z: number }
export interface FighterSnapshot {
  playerId: Id; pieceId: Id; position: Vec3; velocity: Vec3; yawRadians: number;
  hp: number; stamina: number; state: "Idle" | "Moving" | "Attacking" | "Blocking" | "Parrying" | "Dodging" | "Staggered" | "AbilityCasting" | "Defeated";
  stateTicks: number; cooldownTicks: number; lastInputSequence: number;
}
export interface CombatEvent {
  eventId: number; tick: number; type: "hit" | "block" | "parry" | "dodge" | "guardbreak" | "ability" | "whiff";
  actorPlayerId: Id; targetPlayerId: Id; damage: number;
}
export interface CombatSnapshot extends Versioned {
  matchId: Id; battleId: Id; serverTick: number; countdownTicksRemaining: number;
  durationTicksRemaining: number; fighters: FighterSnapshot[]; events: CombatEvent[]; result: BattleResult | null;
}
export interface MatchState extends Versioned {
  matchId: Id; serverTick: number; mode: "classic" | "battle";
  rulesetId: "classic-v1" | "battle-checkmate-v1"; phase: "board" | "combat" | "aftermath" | "complete";
  players: Record<Color, Id>; chess: ChessGameState; battle: BattleRequest | null;
  combat: CombatSnapshot | null; result: "1-0" | "0-1" | "1/2-1/2" | null; reason: string | null;
}
export interface ProtocolError extends Versioned {
  requestId: Id | null;
  code: "INVALID_PAYLOAD" | "UNSUPPORTED_VERSION" | "UNAUTHENTICATED" | "FORBIDDEN" | "STALE_REVISION" | "ILLEGAL_MOVE" | "UNSAFE_OUTCOME" | "WRONG_PHASE" | "STALE_INPUT" | "RATE_LIMITED" | "INTERNAL";
  message: string; retryable: boolean; currentRevision: number | null;
}
export interface Contracts {
  ChessGameState: ChessGameState; ChessMoveRequest: ChessMoveRequest;
  BattleRequest: BattleRequest; BattleResult: BattleResult; FighterStats: FighterStats;
  CombatInput: CombatInput; CombatSnapshot: CombatSnapshot; MatchState: MatchState; ProtocolError: ProtocolError;
}
