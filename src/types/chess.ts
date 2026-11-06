import { PieceColor, PieceSymbol, SquareId } from '../game/types';

export type VariantType =
  | 'standard'
  | 'chess960'
  | 'king_of_the_hill'
  | 'three_check'
  | 'atomic'
  | 'crazyhouse'
  | 'fog_of_war';

// -------------------------------------------------------------
// Syzygy Tablebase & Endgame Analytics
// -------------------------------------------------------------
export type TablebaseCategory =
  | 'win'
  | 'loss'
  | 'draw'
  | 'cursed-win'
  | 'blessed-loss'
  | 'unknown';

export interface TablebaseMove {
  uci: string;
  san: string;
  category: TablebaseCategory;
  dtm?: number | null; // Distance to mate
  dtz?: number | null; // Distance to zeroing (pawn move or capture)
  checkmate?: boolean;
  stalemate?: boolean;
}

export interface SyzygyTablebaseResult {
  fen: string;
  pieceCount: number;
  category: TablebaseCategory;
  dtz: number | null;
  dtm: number | null;
  checkmate: boolean;
  stalemate: boolean;
  preciseEval: string;
  bestMoves: TablebaseMove[];
  isTheoretical: boolean;
  explanation: string;
}

// -------------------------------------------------------------
// Opening Explorer & ECO Database
// -------------------------------------------------------------
export interface ECOOpening {
  eco: string;
  name: string;
  movesSan: string[];
  fen: string;
}

export interface OpeningMoveStat {
  san: string;
  uci: string;
  masterGamesCount: number;
  whiteWinRate: number; // e.g. 38%
  drawRate: number;     // e.g. 34%
  blackWinRate: number; // e.g. 28%
  averageRating: number;
  userGamesCount: number;
  userWinRate: number;
}

export interface OpeningExplorerData {
  currentEco: string;
  openingName: string;
  fen: string;
  totalGames: number;
  moves: OpeningMoveStat[];
  notableGrandmasterGame?: {
    white: string;
    black: string;
    event: string;
    year: number;
    result: string;
  };
}

// -------------------------------------------------------------
// Post-Game Review & Accuracy Metrics
// -------------------------------------------------------------
export interface KeyMoment {
  moveIndex: number;
  moveNumber: number;
  color: PieceColor;
  fenBefore: string;
  playedMove: { from: SquareId; to: SquareId; san: string };
  bestMove: { from: SquareId; to: SquareId; san: string };
  verdict: 'Inaccuracy' | 'Mistake' | 'Blunder';
  cpLoss: number;
  explanation: string;
  solved: boolean;
}

export interface GameReviewReport {
  whiteAccuracy: number;
  blackAccuracy: number;
  whiteClassificationCounts: Record<string, number>;
  blackClassificationCounts: Record<string, number>;
  keyMoments: KeyMoment[];
  summaryNarrative: string;
  turningPointMoveNumber: number | null;
}

// -------------------------------------------------------------
// Rating Progression & Stat Dashboard
// -------------------------------------------------------------
export type TimeControlCategory = 'bullet' | 'blitz' | 'rapid' | 'daily';

export interface RatingPoint {
  timestamp: number;
  rating: number;
  opponentRating: number;
  result: 'win' | 'loss' | 'draw';
}

export interface CategoryStats {
  rating: number;
  peakRating: number;
  wins: number;
  losses: number;
  draws: number;
  history: RatingPoint[];
}

export interface LifetimeStats {
  bullet: CategoryStats;
  blitz: CategoryStats;
  rapid: CategoryStats;
  daily: CategoryStats;
  puzzleRating: number;
  puzzleRushHighscore: number;
  tacticalAccuracyAvg: number;
  tiltFactorScore: number; // 0 - 100%
  favoriteOpening: string;
}

// -------------------------------------------------------------
// Rated Puzzles, Puzzle Rush & Battle
// -------------------------------------------------------------
export type PuzzleMotif =
  | 'pin'
  | 'fork'
  | 'skewer'
  | 'deflection'
  | 'back_rank_mate'
  | 'discovered_attack'
  | 'smothered_mate'
  | 'lucena_endgame'
  | 'philidor_endgame'
  | 'opposition';

export interface RatedPuzzle {
  id: string;
  fen: string;
  solutionMoves: string[]; // SAN sequence
  rating: number;
  motif: PuzzleMotif;
  title: string;
  description: string;
  sideToMove: PieceColor;
}

export type PuzzleRushMode = '3min' | '5min' | 'survival';

export interface PuzzleRushState {
  mode: PuzzleRushMode;
  isActive: boolean;
  score: number;
  strikes: number;
  maxStrikes: number;
  timeRemainingMs: number;
  currentPuzzleIdx: number;
  isFinished: boolean;
}

export interface PuzzleBattleOpponent {
  id: string;
  name: string;
  rating: number;
  avatar: string;
  score: number;
  strikes: number;
}

export interface MasterClassLesson {
  id: string;
  title: string;
  category: 'openings' | 'middlegame' | 'endgame';
  difficulty: 'Squire' | 'Knight' | 'Paladin' | 'Grandmaster';
  summary: string;
  steps: Array<{
    fen: string;
    instruction: string;
    hint: string;
    targetMoveSan: string;
    explanationOnSuccess: string;
  }>;
}

// -------------------------------------------------------------
// Social, Tournaments, Clans & Emotes
// -------------------------------------------------------------
export type TournamentType = 'swiss' | 'arena' | 'knockout';

export interface TournamentPlayer {
  id: string;
  name: string;
  rating: number;
  title?: string;
  score: number;
  tiebreakScore: number;
  streak: number;
  status: 'active' | 'paused' | 'eliminated';
}

export interface TournamentMatch {
  id: string;
  round: number;
  white: TournamentPlayer;
  black: TournamentPlayer;
  status: 'pending' | 'in_progress' | 'completed';
  result?: '1-0' | '0-1' | '1/2-1/2';
}

export interface Tournament {
  id: string;
  name: string;
  type: TournamentType;
  durationMinutes: number;
  timeRemainingSec: number;
  round: number;
  maxRounds: number;
  players: TournamentPlayer[];
  matches: TournamentMatch[];
  status: 'registration' | 'live' | 'finished';
}

export type LeagueDivision =
  | 'Bronze'
  | 'Silver'
  | 'Gold'
  | 'Platinum'
  | 'Diamond'
  | 'Master'
  | 'Legend';

export interface ClanClub {
  id: string;
  name: string;
  bannerEmblem: string;
  tag: string;
  memberCount: number;
  totalXp: number;
  weeklyRank: number;
  motto: string;
}

export interface MatchEmote {
  id: string;
  name: string;
  icon: string;
  sfx: string;
  soundLabel: string;
}

// -------------------------------------------------------------
// Anti-Cheat & Telemetry
// -------------------------------------------------------------
export interface MoveTelemetry {
  moveNumber: number;
  san: string;
  latencyMs: number;
  evalDifferenceCp: number;
  isEngineFirstChoice: boolean;
  tabSwitchCount: number;
}

export interface AntiCheatReport {
  suspicionScore: number; // 0 - 100
  accuracyCorrelation: number; // %
  uniformLatencyScore: number; // %
  isFlaggedForAudit: boolean;
  recommendedPool: 'clean' | 'probation' | 'isolated';
}
