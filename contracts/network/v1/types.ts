/** ENet session protocol v1; existing game payloads retain contracts/v1. */
import type { CombatInput, MatchState, ProtocolError } from '../../v1/types';
export const PROTOCOL = 'peepeechess-enet-v1' as const;
export interface Hello { schemaVersion: 1; protocol: typeof PROTOCOL; resumeToken: string | null }
export interface Welcome { schemaVersion: 1; protocol: typeof PROTOCOL; playerId: string; sessionToken: string; serverId: string; expiresInSeconds: number; combatRoles: string[] }
export interface CreateMatch { schemaVersion: 1; commandId: string; mode: 'classic' | 'battle'; initialMs: number; incrementMs: number }
export interface JoinMatch { schemaVersion: 1; commandId: string; matchId: string }
export interface MatchCommand { schemaVersion: 1; commandId: string; matchId: string; action: 'ready' | 'resign' | 'offer_draw' | 'accept_draw' | 'claim_draw'; drawKind: string | null; intended: {from: string; to: string; promotion: 'q' | 'r' | 'b' | 'n' | null} | null }
export interface ClockState { whiteMs: number; blackMs: number; initialMs: number; incrementMs: number; running: boolean; timed: boolean; turn: 'w' | 'b' }
export interface InputResume extends Omit<CombatInput, 'schemaVersion' | 'matchId' | 'playerId' | 'moveX' | 'moveZ' | 'yawRadians' | 'lockTarget' | 'sprint' | 'block'> {}
export interface MatchFrame { schemaVersion: 1; frameSequence: number; status: 'waiting' | 'active' | 'complete'; state: MatchState; clocks: ClockState; connected: {w: boolean; b: boolean}; ready: {w: boolean; b: boolean}; drawOffer: string | null; inputResume: InputResume | null }
export interface ClockSync { schemaVersion: 1; matchId: string; serverTick: number; clocks: ClockState; connected: {w: boolean; b: boolean} }
export interface Ack { schemaVersion: 1; requestId: string; matchId: string; revision: number }
export interface Heartbeat { schemaVersion: 1; nonce: number }
export type ServerError = ProtocolError;
