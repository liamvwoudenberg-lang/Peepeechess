import type { Color, PieceSymbol, Square } from "chess.js";

export type PieceSet = "royal" | "elves" | "skeletons";
export type Page =
  | "play"
  | "learn"
  | "puzzles"
  | "friends"
  | "armory"
  | "battle";
export interface Preferences {
  pieceSet: PieceSet;
  opponentSet: PieceSet | "matching";
  arena: "citadel" | "silverwood" | "ossuary";
  battleAnimations: "off" | "brief" | "cinematic";
  coordinates: boolean;
  reducedMotion: boolean;
  efficiency: "auto" | "on" | "off";
  sound: boolean;
  muteEmotes: boolean;
}
export const DEFAULT_PREFERENCES: Preferences = {
  pieceSet: "royal",
  opponentSet: "matching",
  arena: "citadel",
  battleAnimations: "cinematic",
  coordinates: true,
  reducedMotion: false,
  efficiency: "auto",
  sound: true,
  muteEmotes: false,
};
export const TIME_CONTROLS = [
  { id: "3+2", label: "3 + 2", detail: "Blitz", minutes: 3, increment: 2 },
  { id: "5+0", label: "5 min", detail: "Blitz", minutes: 5, increment: 0 },
  { id: "10+0", label: "10 min", detail: "Rapid", minutes: 10, increment: 0 },
  {
    id: "15+10",
    label: "15 + 10",
    detail: "Rapid",
    minutes: 15,
    increment: 10,
  },
  {
    id: "untimed",
    label: "Untimed",
    detail: "At your pace",
    minutes: 0,
    increment: 0,
  },
] as const;
export type TimeControl = (typeof TIME_CONTROLS)[number]["id"];
export interface Player {
  id: string;
  name: string;
  code?: string;
  rating: number;
  blitzRating?: number;
  rapidRating?: number;
  games?: number;
  allowSpectators?: boolean;
  army?: PieceSet;
}
export interface Friend extends Player {
  online: boolean;
  gameId: string | null;
  canWatch: boolean;
  unread: number;
}
export interface FriendRequest {
  id: string;
  fromId: string;
  toId: string;
  name: string;
  code: string;
}
export interface Challenge {
  id: string;
  fromId: string;
  toId: string;
  fromName: string;
  toName: string;
  timeControl: TimeControl;
  expiresAt: number;
}
export interface ChatMessage {
  id: string;
  fromId: string;
  toId: string;
  text: string;
  createdAt: number;
}
export interface Ply {
  from: Square;
  to: Square;
  san: string;
  promotion?: string;
  fen: string;
}
export interface Game {
  id: string;
  mode: "online" | "friend" | "computer" | "puzzle" | "lesson" | "analysis";
  phase?: "connecting" | "playing";
  armies?: { w: PieceSet; b: PieceSet };
  arena?: "citadel" | "silverwood" | "ossuary";
  initialFen: string;
  fen: string;
  history: Ply[];
  white: Player;
  black: Player;
  yourColor: Color | null;
  status: "active" | "completed";
  result?: "1-0" | "0-1" | "1/2-1/2";
  reason?: string;
  timeControl: TimeControl;
  clocks: {
    w: number;
    b: number;
    turn: Color;
    updatedAt: number;
    increment: number;
  };
  drawOffer?: string | null;
  rated: boolean;
  spectators: number;
  feedback?: boolean;
  elo?: number;
  pgn?: string;
  ratingDelta?: { w: number; b: number };
}
export const EMOTES = [
  { id: "salute", icon: "🛡️", label: "Good luck!", character: "The Knight" },
  { id: "crown", icon: "👑", label: "Well played!", character: "The Monarch" },
  { id: "fire", icon: "🐉", label: "Brilliant!", character: "The Dragon" },
  { id: "think", icon: "🧙", label: "Thinking…", character: "The Mage" },
  { id: "oops", icon: "💀", label: "Oops!", character: "The Skeleton" },
  { id: "gg", icon: "🤝", label: "Good game!", character: "The Alliance" },
] as const;
export interface EmoteEvent {
  id: string;
  userId: string;
  name: string;
  emote: (typeof EMOTES)[number];
  at: number;
}
export const PIECE_NAMES: Record<PieceSymbol, string> = {
  p: "pawn",
  n: "knight",
  b: "bishop",
  r: "rook",
  q: "queen",
  k: "king",
};
export function clockText(ms: number, showTenths = false) {
  const seconds = Math.max(0, ms) / 1000;
  if (showTenths && seconds < 10) return seconds.toFixed(1);
  return `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;
}

export interface InviteInfo {
  code: string;
  hostName: string;
  hostArmy: PieceSet;
  timeControl: TimeControl;
  hostColor: "w" | "b" | "random";
  expiresAt: number;
  status: "waiting" | "joined" | "cancelled" | "expired";
  hostOnline: boolean;
  isHost: boolean;
}
