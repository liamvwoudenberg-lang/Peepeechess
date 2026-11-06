export type PieceColor = "w" | "b";
export type PieceSymbol = "p" | "n" | "b" | "r" | "q" | "k";
export type SquareId = string; // 'a1' .. 'h8'

export type GameShellState = "title" | "playing" | "paused" | "gameover";
export type GameMode =
  | "solo_coach"
  | "online_ranked"
  | "siege_campaign"
  | "formation_academy"
  | "sandbox_handicap";

export type BotDifficulty = "apprentice" | "knight" | "grandmaster";

export type MoveVerdict =
  | "Brilliant"
  | "Great"
  | "Best"
  | "Book"
  | "Optimal"
  | "Inaccuracy"
  | "Mistake"
  | "Blunder";

export type CameraPreset =
  "white" | "black" | "overhead" | "cinematic" | "action" | "first_person_pov";

export type ArenaTheme =
  | "courtyard"
  | "dungeon_vault"
  | "besieged_ruins"
  | "throne_room"
  | "citadel"
  | "silverwood"
  | "ossuary";
export type WeatherEffect = "clear" | "rain" | "snow" | "night_torches";
export type FactionSkin =
  | "high_crusaders"
  | "shadow_cultists"
  | "golems_gargoyles"
  | "norse_raiders"
  | "elves"
  | "skeletons";

export interface PieceInstance {
  id: string; // Stable identity across moves so 3D character walks/attacks smoothly
  type: PieceSymbol;
  color: PieceColor;
  square: SquareId;
}

export interface MoveAnimationEvent {
  id: string;
  pieceId: string;
  pieceType: PieceSymbol;
  color: PieceColor;
  from: SquareId;
  to: SquareId;
  capturedPieceId?: string;
  capturedPieceType?: PieceSymbol;
  capturedSquare?: SquareId;
  rookCastleMove?: {
    pieceId: string;
    from: SquareId;
    to: SquareId;
  };
  promotedTo?: PieceSymbol;
  isCheck: boolean;
  isCheckmate: boolean;
  san: string;
  combatRole?:
    | "knight_charge"
    | "rook_ballista"
    | "queen_sorcery"
    | "blade_slash"
    | "cleric_radiance";
}

export interface TacticalVisionData {
  controlMap: Record<
    SquareId,
    {
      whiteControl: number;
      blackControl: number;
      contested: boolean;
      netLeader: "w" | "b" | "none";
    }
  >;
  activeThreatLines: Array<{
    from: SquareId;
    to: SquareId;
    type: "pin" | "skewer" | "fork" | "defend" | "attack";
  }>;
  dangerSquares: Set<SquareId>; // pieces under immediate unprotected threat
}

export interface MoveAnalysis {
  moveNumber: number;
  color: PieceColor;
  san: string;
  from: SquareId;
  to: SquareId;
  fenBefore: string;
  fenAfter: string;
  verdict: MoveVerdict;
  evalBeforeCp: number;
  evalAfterCp: number;
  cpLoss: number;
  accuracy: number;
  bestMoveSan: string;
  bestMoveFrom: SquareId;
  bestMoveTo: SquareId;
  openingName?: string;
  headline: string;
  whyReasons: string[];
  optimalComparison: string;
  tacticalThemes: string[];
  deepCoachNote?: string;
  isBlunderWarningTriggered?: boolean;
}

export interface SiegeScenario {
  id: string;
  title: string;
  category: "siege_campaign" | "formation_academy";
  difficulty: "Squire" | "Knight" | "Paladin";
  description: string;
  fen: string;
  targetMoves: string[]; // Solution SAN moves e.g. ["Qxf7#"] or multiple turns
  goalText: string;
  openingName?: string;
  conceptTaught: string;
}

export interface LeaderboardEntry {
  id: string;
  name: string;
  title: string;
  rating: number;
  wins: number;
  losses: number;
  draws: number;
  region: string;
  isOnline: boolean;
}

export interface OnlineMatchState {
  matchId: string;
  roomCode?: string;
  white: { id: string; name: string; rating: number; isBot?: boolean };
  black: { id: string; name: string; rating: number; isBot?: boolean };
  yourColor: PieceColor;
  fen: string;
  pgn: string;
  whiteTimeMs: number;
  blackTimeMs: number;
  status: "active" | "completed";
  winner?: PieceColor | "draw";
  reason?: string;
  ratingDelta?: { white: number; black: number };
  isSiegeIncrement?: boolean; // +5s per capture
}

export interface EndgameSummary {
  outcome: "victory" | "defeat" | "draw";
  title: string;
  subtitle: string;
  movesPlayed: number;
  playerAccuracy: number;
  brilliantMoveCount: number;
  optimalMoveCount: number;
  blunderCount: number;
  ratingBefore?: number;
  ratingAfter?: number;
  ratingDelta?: number;
}
