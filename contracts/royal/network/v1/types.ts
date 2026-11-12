/** battle-royal-v1 wire messages, protocol `peepeechess-enet-royal-v1`. Additive: network/v1 and contracts/v1 are unchanged. */
import type { ClockState, InputResume } from '../../../network/v1/types';
import type { RoyalContracts } from '../../v1/types';
export const ROYAL_PROTOCOL = 'peepeechess-enet-royal-v1' as const;
export interface RoyalHello { schemaVersion: 1; protocol: typeof ROYAL_PROTOCOL; rulesetId: 'battle-royal-v1'; resumeToken: string | null }
export interface RoyalWelcome { schemaVersion: 1; protocol: typeof ROYAL_PROTOCOL; rulesetId: 'battle-royal-v1'; playerId: string; sessionToken: string; serverId: string; expiresInSeconds: number; combatRoles: string[] }
export interface RoyalCreateMatch { schemaVersion: 1; commandId: string; rulesetId: 'battle-royal-v1'; mode: 'battle'; initialMs: 0; incrementMs: 0 }
export interface RoyalMatchFrame { schemaVersion: 1; frameSequence: number; status: 'waiting' | 'active' | 'complete'; state: RoyalContracts['RoyalMatchState']; clocks: ClockState; connected: {w: boolean; b: boolean}; ready: {w: boolean; b: boolean}; drawOffer: string | null; inputResume: InputResume | null }
export interface RoyalSequenceNotice { schemaVersion: 1; kind: 'progress' | 'duel_result' | 'sequence_result'; matchId: string; progress: RoyalContracts['RoyalSequenceProgress'] | null; duel: RoyalContracts['RoyalDuelResult'] | null; sequence: RoyalContracts['RoyalSequenceResult'] | null }
