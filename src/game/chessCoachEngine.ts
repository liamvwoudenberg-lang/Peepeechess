import { Chess, Move, Square } from 'chess.js';
import {
  BotDifficulty,
  MoveAnalysis,
  MoveVerdict,
  PieceColor,
  PieceSymbol,
  SquareId,
  TacticalVisionData,
} from './types';

export const PIECE_VALUES: Record<PieceSymbol, number> = {
  p: 100,
  n: 320,
  b: 330,
  r: 500,
  q: 900,
  k: 20000,
};

export const FANTASY_PIECE_NAMES: Record<PieceSymbol, string> = {
  p: 'Vanguard Squire (Pawn)',
  n: 'Crested Cavalier (Knight)',
  b: 'Runic Cleric (Bishop)',
  r: 'Bastion Warden (Rook)',
  q: 'High Sorceress (Queen)',
  k: 'Sovereign Monarch (King)',
};

const PAWN_PST = [
  [0, 0, 0, 0, 0, 0, 0, 0],
  [50, 50, 50, 50, 50, 50, 50, 50],
  [10, 10, 20, 30, 30, 20, 10, 10],
  [5, 5, 10, 27, 27, 10, 5, 5],
  [0, 0, 0, 24, 24, 0, 0, 0],
  [5, -5, -10, 0, 0, -10, -5, 5],
  [5, 10, 10, -22, -22, 10, 10, 5],
  [0, 0, 0, 0, 0, 0, 0, 0],
];

const KNIGHT_PST = [
  [-50, -40, -30, -30, -30, -30, -40, -50],
  [-40, -20, 0, 0, 0, 0, -20, -40],
  [-30, 0, 12, 16, 16, 12, 0, -30],
  [-30, 5, 16, 22, 22, 16, 5, -30],
  [-30, 0, 16, 22, 22, 16, 0, -30],
  [-30, 5, 12, 16, 16, 12, 5, -30],
  [-40, -20, 0, 5, 5, 0, -20, -40],
  [-50, -35, -30, -30, -30, -30, -35, -50],
];

const BISHOP_PST = [
  [-20, -10, -10, -10, -10, -10, -10, -20],
  [-10, 0, 0, 0, 0, 0, 0, -10],
  [-10, 0, 8, 12, 12, 8, 0, -10],
  [-10, 6, 8, 14, 14, 8, 6, -10],
  [-10, 0, 12, 14, 14, 12, 0, -10],
  [-10, 10, 10, 12, 12, 10, 10, -10],
  [-10, 8, 0, 0, 0, 0, 8, -10],
  [-20, -10, -12, -10, -10, -12, -10, -20],
];

const ROOK_PST = [
  [0, 0, 0, 0, 0, 0, 0, 0],
  [8, 12, 12, 12, 12, 12, 12, 8],
  [-5, 0, 0, 0, 0, 0, 0, -5],
  [-5, 0, 0, 0, 0, 0, 0, -5],
  [-5, 0, 0, 0, 0, 0, 0, -5],
  [-5, 0, 0, 0, 0, 0, 0, -5],
  [-5, 0, 0, 0, 0, 0, 0, -5],
  [0, 0, 4, 8, 8, 4, 0, 0],
];

const QUEEN_PST = [
  [-20, -10, -10, -5, -5, -10, -10, -20],
  [-10, 0, 0, 0, 0, 0, 0, -10],
  [-10, 0, 5, 5, 5, 5, 0, -10],
  [-5, 0, 5, 6, 6, 5, 0, -5],
  [0, 0, 5, 6, 6, 5, 0, -5],
  [-10, 5, 5, 5, 5, 5, 0, -10],
  [-10, 0, 5, 0, 0, 0, 0, -10],
  [-20, -10, -10, -5, -5, -10, -10, -20],
];

const KING_MID_PST = [
  [-30, -40, -40, -50, -50, -40, -40, -30],
  [-30, -40, -40, -50, -50, -40, -40, -30],
  [-30, -40, -40, -50, -50, -40, -40, -30],
  [-30, -40, -40, -50, -50, -40, -40, -30],
  [-20, -30, -30, -40, -40, -30, -30, -20],
  [-10, -20, -20, -20, -20, -20, -20, -10],
  [20, 20, 0, 0, 0, 0, 20, 20],
  [20, 32, 12, 0, 0, 10, 32, 20],
];

const PST_MAP: Record<PieceSymbol, number[][]> = {
  p: PAWN_PST,
  n: KNIGHT_PST,
  b: BISHOP_PST,
  r: ROOK_PST,
  q: QUEEN_PST,
  k: KING_MID_PST,
};

const CENTER_SQUARES = new Set(['d4', 'e4', 'd5', 'e5']);
const EXTENDED_CENTER = new Set([
  'c3', 'd3', 'e3', 'f3',
  'c4', 'd4', 'e4', 'f4',
  'c5', 'd5', 'e5', 'f5',
  'c6', 'd6', 'e6', 'f6',
]);

const OPENING_BOOK: Record<string, { name: string; bookMoves: string[] }> = {
  'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w': {
    name: 'King or Queen Pawn Opening',
    bookMoves: ['e4', 'd4', 'Nf3', 'c4'],
  },
  'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b': {
    name: 'Open Game / Sicilian / French / Caro-Kann',
    bookMoves: ['e5', 'c5', 'e6', 'c6', 'd5'],
  },
  'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w': {
    name: "King's Knight Opening",
    bookMoves: ['Nf3', 'Bc4', 'Nc3', 'f4'],
  },
  'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b': {
    name: "Open Game — Queen's Knight Defense",
    bookMoves: ['Nc6', 'Nf6', 'd6'],
  },
  'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w': {
    name: 'Italian Game / Ruy Lopez',
    bookMoves: ['Bc4', 'Bb5', 'd4', 'Nc3'],
  },
  'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b': {
    name: 'Italian Game — Giuoco Piano / Two Knights',
    bookMoves: ['Bc5', 'Nf6', 'Be7'],
  },
  'r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b': {
    name: 'Ruy Lopez (Spanish Opening)',
    bookMoves: ['a6', 'Nf6', 'Bc5', 'd6'],
  },
  'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w': {
    name: 'Sicilian Defense',
    bookMoves: ['Nf3', 'Nc3', 'c3', 'd4'],
  },
  'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w': {
    name: 'French Defense',
    bookMoves: ['d4', 'Nc3', 'Nd2'],
  },
  'rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w': {
    name: 'Caro-Kann Defense',
    bookMoves: ['d4', 'Nc3', 'c4'],
  },
  'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b': {
    name: "Queen's Pawn Game / Indian Defense",
    bookMoves: ['d5', 'Nf6', 'e6'],
  },
  'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w': {
    name: "Queen's Gambit / London System",
    bookMoves: ['c4', 'Bf4', 'Nf3'],
  },
  'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b': {
    name: "Queen's Gambit",
    bookMoves: ['e6', 'c6', 'dxc4', 'Nf6'],
  },
};

function fenPrefix(fen: string): string {
  const parts = fen.split(' ');
  return `${parts[0]} ${parts[1]}`;
}

export function evaluatePositionCp(chess: Chess): number {
  if (chess.isCheckmate()) {
    return chess.turn() === 'w' ? -19000 : 19000;
  }
  if (chess.isDraw() || chess.isStalemate() || chess.isThreefoldRepetition() || chess.isInsufficientMaterial()) {
    return 0;
  }

  const board = chess.board();
  let score = 0;
  let whiteBishops = 0;
  let blackBishops = 0;

  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const cell = board[r][c];
      if (!cell) continue;

      const baseVal = PIECE_VALUES[cell.type];
      const pstRow = cell.color === 'w' ? r : 7 - r;
      const pstBonus = PST_MAP[cell.type][pstRow][c];

      if (cell.color === 'w') {
        score += baseVal + pstBonus;
        if (cell.type === 'b') whiteBishops++;
      } else {
        score -= baseVal + pstBonus;
        if (cell.type === 'b') blackBishops++;
      }
    }
  }

  if (whiteBishops >= 2) score += 30;
  if (blackBishops >= 2) score -= 30;

  if (chess.inCheck()) {
    score += chess.turn() === 'w' ? -25 : 25;
  }

  return score;
}

function scoreMoveOrdering(move: Move): number {
  let score = 0;
  if (move.captured) {
    score += 10 * PIECE_VALUES[move.captured] - PIECE_VALUES[move.piece] * 0.1;
  }
  if (move.promotion) {
    score += PIECE_VALUES[move.promotion];
  }
  if (move.san.includes('+') || move.san.includes('#')) {
    score += 140;
  }
  if (CENTER_SQUARES.has(move.to)) {
    score += 35;
  }
  if (move.flags.includes('k') || move.flags.includes('q')) {
    score += 90;
  }
  return score;
}

function minimaxAlphaBeta(
  chess: Chess,
  depth: number,
  alpha: number,
  beta: number,
  maximizingWhite: boolean
): number {
  if (depth === 0 || chess.isGameOver()) {
    return evaluatePositionCp(chess);
  }

  const moves = chess
    .moves({ verbose: true })
    .sort((a, b) => scoreMoveOrdering(b) - scoreMoveOrdering(a))
    .slice(0, 14);

  if (maximizingWhite) {
    let maxEval = -99999;
    for (const m of moves) {
      chess.move(m);
      const val = minimaxAlphaBeta(chess, depth - 1, alpha, beta, false);
      chess.undo();
      if (val > maxEval) maxEval = val;
      if (val > alpha) alpha = val;
      if (beta <= alpha) break;
    }
    return maxEval;
  } else {
    let minEval = 99999;
    for (const m of moves) {
      chess.move(m);
      const val = minimaxAlphaBeta(chess, depth - 1, alpha, beta, true);
      chess.undo();
      if (val < minEval) minEval = val;
      if (val < beta) beta = val;
      if (beta <= alpha) break;
    }
    return minEval;
  }
}

export interface EngineMoveCandidate {
  move: Move;
  evalCp: number;
}

export function rankLegalMoves(fen: string, searchDepth = 2): EngineMoveCandidate[] {
  const chess = new Chess(fen);
  const turn = chess.turn();
  const legalMoves = chess.moves({ verbose: true });
  if (legalMoves.length === 0) return [];

  const bookEntry = OPENING_BOOK[fenPrefix(fen)];

  const scored: EngineMoveCandidate[] = [];
  for (const m of legalMoves) {
    chess.move(m);
    let evalCp = minimaxAlphaBeta(
      chess,
      Math.max(0, searchDepth - 1),
      -99999,
      99999,
      chess.turn() === 'w'
    );
    if (bookEntry && bookEntry.bookMoves.includes(m.san)) {
      evalCp += turn === 'w' ? 12 : -12;
    }
    chess.undo();
    scored.push({ move: m, evalCp });
  }

  scored.sort((a, b) => (turn === 'w' ? b.evalCp - a.evalCp : a.evalCp - b.evalCp));
  return scored;
}

export function selectBotMove(fen: string, difficulty: BotDifficulty): Move | null {
  const depth = difficulty === 'grandmaster' ? 3 : difficulty === 'knight' ? 2 : 1;
  const ranked = rankLegalMoves(fen, depth);
  if (ranked.length === 0) return null;

  if (difficulty === 'apprentice' && ranked.length > 2) {
    const poolSize = Math.min(3, ranked.length);
    const weights = [0.55, 0.3, 0.15];
    const roll = Math.random();
    let acc = 0;
    for (let i = 0; i < poolSize; i++) {
      acc += weights[i];
      if (roll <= acc) return ranked[i].move;
    }
  } else if (difficulty === 'knight' && ranked.length > 1) {
    const diff = Math.abs(ranked[0].evalCp - ranked[1].evalCp);
    if (diff < 35 && Math.random() < 0.22) {
      return ranked[1].move;
    }
  }

  return ranked[0].move;
}

export function computeMoveAccuracy(cpLoss: number): number {
  const clamped = Math.max(0, cpLoss);
  const raw = 103.1668 * Math.exp(-0.0115 * clamped) - 3.1669;
  return Math.max(5, Math.min(100, Math.round(raw)));
}

function findHangingPieces(chess: Chess, color: PieceColor): Array<{ square: SquareId; type: PieceSymbol }> {
  const enemy: PieceColor = color === 'w' ? 'b' : 'w';
  const board = chess.board();
  const hanging: Array<{ square: SquareId; type: PieceSymbol }> = [];

  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const cell = board[r][c];
      if (!cell || cell.color !== color || cell.type === 'k') continue;
      const sq = cell.square as Square;
      const isAttacked = chess.isAttacked(sq, enemy);
      if (!isAttacked) continue;
      const isDefended = chess.isAttacked(sq, color);
      if (!isDefended && PIECE_VALUES[cell.type] >= 100) {
        hanging.push({ square: sq, type: cell.type });
      }
    }
  }
  return hanging;
}

/**
 * Computes live tactical vision: color-coded square control heatmap, threat lines, and danger auras.
 */
export function computeTacticalVision(chess: Chess): TacticalVisionData {
  const controlMap: TacticalVisionData['controlMap'] = {};
  const activeThreatLines: TacticalVisionData['activeThreatLines'] = [];
  const dangerSquares = new Set<SquareId>();

  const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  const board = chess.board();

  // 1. Calculate square control counts
  for (let f = 0; f < 8; f++) {
    for (let r = 1; r <= 8; r++) {
      const sq = `${files[f]}${r}` as Square;
      const wAttacked = chess.isAttacked(sq, 'w');
      const bAttacked = chess.isAttacked(sq, 'b');

      let wCtrl = 0;
      let bCtrl = 0;
      if (wAttacked) wCtrl = 1;
      if (bAttacked) bCtrl = 1;

      const contested = wCtrl > 0 && bCtrl > 0;
      let netLeader: 'w' | 'b' | 'none' = 'none';
      if (wCtrl > bCtrl) netLeader = 'w';
      else if (bCtrl > wCtrl) netLeader = 'b';

      controlMap[sq] = {
        whiteControl: wCtrl,
        blackControl: bCtrl,
        contested,
        netLeader,
      };
    }
  }

  // 2. Detect immediate threats, pins, forks, and undefended danger squares
  const turn = chess.turn();
  const enemy: PieceColor = turn === 'w' ? 'b' : 'w';

  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const cell = board[r][c];
      if (!cell) continue;
      const sq = cell.square as Square;

      const isAttacked = chess.isAttacked(sq, cell.color === 'w' ? 'b' : 'w');
      const isDefended = chess.isAttacked(sq, cell.color);

      if (isAttacked && !isDefended && cell.type !== 'k') {
        dangerSquares.add(sq);
      }

      // If enemy piece attacks our piece, draw an active threat ray
      if (cell.color === enemy) {
        const moves = chess.moves({ square: sq, verbose: true });
        for (const m of moves) {
          if (m.captured) {
            activeThreatLines.push({
              from: m.from,
              to: m.to,
              type: m.san.includes('+') ? 'pin' : 'attack',
            });
          }
        }
      }
    }
  }

  return { controlMap, activeThreatLines, dangerSquares };
}

/**
 * Checks if a proposed move leads to a disastrous blunder (for Blunder Guard in Training Mode).
 */
export function checkBlunderGuard(
  fenBefore: string,
  moveInput: { from: string; to: string; promotion?: string }
): { isBlunder: boolean; warningText?: string; cpLoss: number } {
  const analysis = analyzePlayerMove(fenBefore, moveInput);
  if (analysis.verdict === 'Blunder' || analysis.cpLoss >= 230) {
    const mover = new Chess(fenBefore).turn();
    const lossPawns = (analysis.cpLoss / 100).toFixed(1);
    return {
      isBlunder: true,
      cpLoss: analysis.cpLoss,
      warningText: `Blunder Guard: ${analysis.san} loses approximately ${lossPawns} pawns of value! ${analysis.whyReasons[0] || ''} Consider ${analysis.bestMoveSan} instead.`,
    };
  }
  return { isBlunder: false, cpLoss: analysis.cpLoss };
}

export function analyzePlayerMove(
  fenBefore: string,
  playedMoveInput: { from: string; to: string; promotion?: string },
  moveNumber = 1
): MoveAnalysis {
  const beforeChess = new Chess(fenBefore);
  const moverColor = beforeChess.turn();
  const enemyColor: PieceColor = moverColor === 'w' ? 'b' : 'w';

  const ranked = rankLegalMoves(fenBefore, 2);
  const bestCandidate = ranked[0];

  const afterChess = new Chess(fenBefore);
  const executed = afterChess.move(playedMoveInput);
  if (!executed) {
    throw new Error(`Illegal move passed to analyzePlayerMove: ${JSON.stringify(playedMoveInput)}`);
  }

  const playedRankedEntry = ranked.find(
    (c) =>
      c.move.from === executed.from &&
      c.move.to === executed.to &&
      (c.move.promotion || '') === (executed.promotion || '')
  );

  const evalBeforeCp = bestCandidate ? bestCandidate.evalCp : evaluatePositionCp(beforeChess);
  const evalAfterCp = playedRankedEntry ? playedRankedEntry.evalCp : evaluatePositionCp(afterChess);

  const rawLoss =
    moverColor === 'w' ? evalBeforeCp - evalAfterCp : evalAfterCp - evalBeforeCp;
  const cpLoss = Math.max(0, Math.round(rawLoss));
  const accuracy = computeMoveAccuracy(cpLoss);

  const bookEntry = OPENING_BOOK[fenPrefix(fenBefore)];
  const isBookMove = Boolean(bookEntry && bookEntry.bookMoves.includes(executed.san));
  const isBestMove = Boolean(
    bestCandidate &&
      bestCandidate.move.from === executed.from &&
      bestCandidate.move.to === executed.to &&
      (bestCandidate.move.promotion || '') === (executed.promotion || '')
  );

  // Check for sacrifice / Brilliant classification
  let isSacrifice = false;
  if (executed.captured) {
    const moverVal = PIECE_VALUES[executed.piece];
    const capVal = PIECE_VALUES[executed.captured];
    if (moverVal > capVal && cpLoss <= 10) isSacrifice = true;
  }

  let verdict: MoveVerdict;
  if (afterChess.isCheckmate()) {
    verdict = isSacrifice ? 'Brilliant' : 'Optimal';
  } else if (isSacrifice && cpLoss <= 10) {
    verdict = 'Brilliant';
  } else if (isBookMove && cpLoss <= 25) {
    verdict = 'Book';
  } else if (isBestMove || cpLoss <= 12) {
    verdict = 'Best';
  } else if (cpLoss <= 32) {
    verdict = 'Great';
  } else if (cpLoss <= 55) {
    verdict = 'Optimal';
  } else if (cpLoss <= 115) {
    verdict = 'Inaccuracy';
  } else if (cpLoss <= 220) {
    verdict = 'Mistake';
  } else {
    verdict = 'Blunder';
  }

  const bestMove = bestCandidate ? bestCandidate.move : executed;
  const whyReasons: string[] = [];
  const tacticalThemes: string[] = [];

  const pieceLabel = FANTASY_PIECE_NAMES[executed.piece];
  const bestPieceLabel = FANTASY_PIECE_NAMES[bestMove.piece];

  if (afterChess.isCheckmate()) {
    whyReasons.push(`Delivers decisive Checkmate on ${executed.to}, ending all royal escape routes.`);
    tacticalThemes.push('Checkmate');
  } else if (afterChess.inCheck()) {
    whyReasons.push(`Forces the enemy Monarch into Check with ${executed.san}, seizing immediate initiative.`);
    tacticalThemes.push('Direct Check');
  }

  if (isBookMove && bookEntry) {
    whyReasons.push(
      `Follows established Grandmaster opening theory (${bookEntry.name}), developing harmoniously for central tempo.`
    );
    tacticalThemes.push('Opening Theory');
  }

  if (executed.flags.includes('k') || executed.flags.includes('q')) {
    const side = executed.flags.includes('k') ? 'kingside' : 'queenside';
    whyReasons.push(
      `Castles ${side} to shelter your Sovereign Monarch behind a loyal shield while mobilizing your Bastion Rook.`
    );
    tacticalThemes.push('King Safety');
  }

  if (executed.captured) {
    const capVal = PIECE_VALUES[executed.captured];
    const moverVal = PIECE_VALUES[executed.piece];
    const capLabel = FANTASY_PIECE_NAMES[executed.captured];
    if (capVal > moverVal || !afterChess.isAttacked(executed.to as Square, enemyColor)) {
      whyReasons.push(
        `Wins material or trades favorably by capturing the enemy ${capLabel} on ${executed.to}.`
      );
      tacticalThemes.push('Material Gain');
    } else if (cpLoss > 60) {
      whyReasons.push(
        `Capturing on ${executed.to} walks a higher-value ${pieceLabel} into a defended square, losing the material exchange.`
      );
      tacticalThemes.push('Unfavorable Trade');
    }
  }

  const hangingBefore = new Set(findHangingPieces(beforeChess, moverColor).map((h) => h.square));
  const hangingAfter = findHangingPieces(afterChess, moverColor);
  const newlyHanging = hangingAfter.filter((h) => !hangingBefore.has(h.square) || h.square === executed.to);

  if (newlyHanging.length > 0 && cpLoss >= 70) {
    const victim = newlyHanging[0];
    whyReasons.push(
      `Leaves your ${FANTASY_PIECE_NAMES[victim.type]} on ${victim.square} undefended against immediate enemy strike.`
    );
    tacticalThemes.push('Hanging Piece');
  } else if (afterChess.isAttacked(executed.to as Square, enemyColor) && cpLoss >= 90) {
    whyReasons.push(
      `Steps onto ${executed.to} where enemy forces command the line, surrendering ${(cpLoss / 100).toFixed(1)} pawns of value.`
    );
    tacticalThemes.push('Square Control');
  }

  if (CENTER_SQUARES.has(executed.to) && cpLoss <= 45) {
    whyReasons.push(
      `Directly contests vital central citadel square ${executed.to}, restricting enemy mobility.`
    );
    tacticalThemes.push('Center Control');
  } else if (
    (executed.piece === 'n' || executed.piece === 'b') &&
    (executed.from.endsWith('1') || executed.from.endsWith('8')) &&
    EXTENDED_CENTER.has(executed.to) &&
    cpLoss <= 45
  ) {
    whyReasons.push(
      `Develops your ${pieceLabel} from its starting rank onto an active outpost at ${executed.to}.`
    );
    tacticalThemes.push('Piece Development');
  }

  if (cpLoss > 35) {
    if (moveNumber <= 8 && executed.piece === 'q' && !executed.captured) {
      whyReasons.push(
        `Deploys the High Sorceress (Queen) prematurely on move ${moveNumber}, allowing enemy minor pieces to develop with tempo by chasing her.`
      );
      tacticalThemes.push('Premature Queen');
    }
    if (
      moveNumber <= 8 &&
      executed.piece === 'p' &&
      (executed.to.startsWith('a') || executed.to.startsWith('h')) &&
      !executed.captured
    ) {
      whyReasons.push(
        `Flank pawn push ${executed.san} spends a precious opening tempo on the rim while central squares d4/e4/d5/e5 remain contested.`
      );
      tacticalThemes.push('Lost Tempo');
    }
    if (
      moveNumber <= 10 &&
      executed.piece === 'p' &&
      ((moverColor === 'w' && executed.from === 'f2') || (moverColor === 'b' && executed.from === 'f7')) &&
      cpLoss >= 50
    ) {
      whyReasons.push(
        `Advancing the f-pawn weakens the critical diagonal guarding your Sovereign Monarch.`
      );
      tacticalThemes.push('King Exposure');
    }
    if (bestMove.captured && !executed.captured) {
      whyReasons.push(
        `Missed a tactical opportunity: ${bestMove.san} captured on ${bestMove.to} for immediate advantage.`
      );
      tacticalThemes.push('Missed Tactic');
    }
    if (bestMove.san.includes('#') && !executed.san.includes('#')) {
      whyReasons.push(`Overlooked a forced Checkmate sequence starting with ${bestMove.san}!`);
      tacticalThemes.push('Missed Mate');
    }
  }

  if (whyReasons.length === 0) {
    if (verdict === 'Brilliant' || verdict === 'Best' || verdict === 'Great' || verdict === 'Optimal' || verdict === 'Book') {
      whyReasons.push(
        `Maintains solid piece coordination and keeps evaluation favorable (${formatEvalScore(evalAfterCp)}) without conceding weaknesses.`
      );
      whyReasons.push(
        `Improves position harmony and prepares future pressure across key files and diagonals.`
      );
      tacticalThemes.push('Positional Harmony');
    } else {
      whyReasons.push(
        `Cedes ${(cpLoss / 100).toFixed(2)} pawns of positional evaluation compared to the strongest engine continuation.`
      );
      whyReasons.push(
        `Allows the opponent easier piece coordination and initiative on the next turn.`
      );
      tacticalThemes.push('Positional Drift');
    }
  }

  let headline = '';
  let optimalComparison = '';

  if (verdict === 'Brilliant') {
    headline = `${executed.san} is Brilliant! A daring sacrifice that breaks open enemy lines.`;
    optimalComparison = `You found the deepest tactical breakthrough (${executed.san}).`;
  } else if (verdict === 'Book') {
    headline = `${executed.san} is a classical Book Move (${bookEntry?.name ?? 'Citadel Opening'}).`;
    optimalComparison = `Matches Grandmaster opening repertoire. Engine top choice: ${bestMove.san}.`;
  } else if (verdict === 'Best' || verdict === 'Optimal') {
    headline = `${executed.san} is the Optimal move in this position!`;
    optimalComparison = `You found the #1 tactical & positional continuation (${executed.san}).`;
  } else if (verdict === 'Great') {
    headline = `${executed.san} is a Great, principled move.`;
    optimalComparison = `Nearly equal to the engine's razor-thin #1 preference ${bestMove.san} (${bestPieceLabel} to ${bestMove.to}).`;
  } else if (verdict === 'Inaccuracy') {
    headline = `${executed.san} is a slight Inaccuracy (-${(cpLoss / 100).toFixed(2)} pawns).`;
    optimalComparison = `Optimal was ${bestMove.san} (moving ${bestPieceLabel} from ${bestMove.from} to ${bestMove.to}), which better fought for central control and initiative.`;
  } else if (verdict === 'Mistake') {
    headline = `${executed.san} is a tactical Mistake (-${(cpLoss / 100).toFixed(2)} pawns).`;
    optimalComparison = `Optimal was ${bestMove.san} (${bestMove.from} -> ${bestMove.to}), preserving material safety and active pressure.`;
  } else {
    headline = `${executed.san} is a costly Blunder (-${(cpLoss / 100).toFixed(2)} pawns)!`;
    optimalComparison = `Instead, ${bestMove.san} (${bestMove.from} -> ${bestMove.to}) kept your forces defended and held a ${(Math.abs(evalBeforeCp) / 100).toFixed(1)}-pawn balance.`;
  }

  return {
    moveNumber,
    color: moverColor,
    san: executed.san,
    from: executed.from,
    to: executed.to,
    fenBefore,
    fenAfter: afterChess.fen(),
    verdict,
    evalBeforeCp,
    evalAfterCp,
    cpLoss,
    accuracy,
    bestMoveSan: bestMove.san,
    bestMoveFrom: bestMove.from,
    bestMoveTo: bestMove.to,
    openingName: bookEntry?.name,
    headline,
    whyReasons,
    optimalComparison,
    tacticalThemes,
  };
}

export function formatEvalScore(evalCp: number): string {
  if (Math.abs(evalCp) >= 18000) {
    return evalCp > 0 ? '+M' : '-M';
  }
  const pawns = evalCp / 100;
  return `${pawns >= 0 ? '+' : ''}${pawns.toFixed(2)}`;
}

export function calculateEloDelta(
  playerRating: number,
  opponentRating: number,
  score: 0 | 0.5 | 1,
  kFactor = 32
): number {
  const expected = 1 / (1 + Math.pow(10, (opponentRating - playerRating) / 400));
  return Math.round(kFactor * (score - expected));
}

export function getRankTitle(rating: number): string {
  if (rating >= 1800) return 'Arch-Grandmaster';
  if (rating >= 1550) return 'High Paladin';
  if (rating >= 1350) return 'Royal Knight';
  if (rating >= 1150) return 'Castle Warden';
  return 'Citadel Squire';
}
