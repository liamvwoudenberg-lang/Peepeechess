/** Application HTTP v1. Independent from the ENet/game v1 schema. */
export type Mode = "classic" | "battle";
export type MatchResult = "white" | "black" | "draw" | "aborted";
export type Stats = { rating: number; wins: number; losses: number; draws: number; games: number };
export type Profile = { playerId: string; username: string; displayName: string; createdAt: number; classic: Stats; battle: Stats };
export type Endpoint = { host: string; port: number; serverName: string; caCertificate: string; insecureLocal: boolean };
export type Allocation = { matchId: string; mode: Mode; ranked: boolean; whitePlayerId: string; blackPlayerId: string; initialMs: number; incrementMs: number; serverId: string; endpoint: Endpoint; createdAt: number };
export type Queue = { mode: Mode; ranked: boolean; initialMs: number; incrementMs: number; enteredAt: number };
export type Status = { queue: Queue | null; allocation: Allocation | null; invite: { code: string; expiresAt: number } | null };
export type AuthResponse = { token: string; expiresAt: number; profile: Profile };
export type MatchRecord = { matchId: string; mode: Mode; ranked: boolean; whitePlayerId: string; blackPlayerId: string; whiteName: string; blackName: string; result: MatchResult; reason: string; finalFen: string; history: unknown[]; startedAt: number; completedAt: number; ratingChange: { white: number; black: number } };
export type MatchOptions = { mode: Mode; ranked: boolean; initialMs: number; incrementMs: number };
export type ResultReport = { matchId: string; result: MatchResult; reason: string; finalFen: string; history: unknown[] };

/** Additive ENet account handshake, reliable channel 0; distinct from anonymous Hello. */
export type AccountHello = { schemaVersion: 1; protocol: "peepeechess-enet-v1"; ticket: string };
