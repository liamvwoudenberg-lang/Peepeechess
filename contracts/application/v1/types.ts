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

/** Friends (additive; no existing type or endpoint changed). A challenge is a private invite only the chosen friend may join:
 *  the friend accepts with the existing POST /v1/private/join, after which the normal allocation/ticket flow applies. */
export type PlayerRef = { playerId: string; username: string; displayName: string };
export type Friend = PlayerRef & { online: boolean; inMatch: boolean; classicRating: number; battleRating: number };
/** The viewer's own colour in a challenged game. */
export type Side = "white" | "black" | "random";
export type Challenge = { code: string; player: PlayerRef; mode: Mode; initialMs: number; incrementMs: number; side: Side; expiresAt: number };
/** challenges.incoming: sent to you (player = the challenger). challenges.outgoing: your own pending challenge (player = the friend). */
export type FriendsSnapshot = { friends: Friend[]; incoming: PlayerRef[]; outgoing: PlayerRef[]; challenges: { incoming: Challenge[]; outgoing: Challenge | null } };

/** Bounded history pages omit move arrays; /v1/history retains full record compatibility. */
export type MatchSummary = Omit<MatchRecord, "history"> & { plies: number };
export type HistoryPage = { matches: MatchSummary[]; nextOffset: number | null };
