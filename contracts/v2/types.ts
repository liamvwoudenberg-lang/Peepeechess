/** Persistent-board public contracts. Engines/components remain behind a deliberate v1 adapter. */
import type * as Legacy from '../v1/types';
export type BoardVersion<T> = T extends readonly (infer U)[] ? BoardVersion<U>[] : T extends object ? { [K in keyof T]: K extends 'schemaVersion' ? 2 : K extends 'arenaId' ? 'board-v1' : BoardVersion<T[K]> } : T;
export type ChessGameState = BoardVersion<Legacy.ChessGameState>;
export type ChessMoveRequest = BoardVersion<Legacy.ChessMoveRequest>;
export type BattleRequest = BoardVersion<Legacy.BattleRequest>;
export type BattleResult = BoardVersion<Legacy.BattleResult>;
export type FighterStats = BoardVersion<Legacy.FighterStats>;
export type CombatInput = BoardVersion<Legacy.CombatInput>;
export type CombatSnapshot = BoardVersion<Legacy.CombatSnapshot>;
export type MatchState = BoardVersion<Legacy.MatchState>;
export type ProtocolError = BoardVersion<Legacy.ProtocolError>;
export type Contracts = BoardVersion<Legacy.Contracts>;
