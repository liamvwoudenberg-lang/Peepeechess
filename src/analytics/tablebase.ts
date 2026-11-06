import { Chess } from 'chess.js';
import { SyzygyTablebaseResult, TablebaseCategory, TablebaseMove } from '../types/chess';

/**
 * Counts non-empty piece cells on the board from a FEN string.
 */
export function countPiecesFromFen(fen: string): number {
  const boardPart = fen.split(' ')[0];
  let count = 0;
  for (const char of boardPart) {
    if (/[pnbrqkPNBRQK]/.test(char)) {
      count++;
    }
  }
  return count;
}

/**
 * Client-side theoretical endgame heuristics when offline or network fails.
 */
export function evaluateLocalEndgameHeuristic(fen: string): SyzygyTablebaseResult {
  const chess = new Chess(fen);
  const board = chess.board();
  const pieces: Array<{ type: string; color: string; square: string }> = [];

  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const cell = board[r][c];
      if (cell) {
        pieces.push({ type: cell.type, color: cell.color, square: cell.square });
      }
    }
  }

  const pieceCount = pieces.length;
  const turn = chess.turn();
  const whitePieces = pieces.filter((p) => p.color === 'w');
  const blackPieces = pieces.filter((p) => p.color === 'b');

  // Kings only -> Draw
  if (pieceCount === 2) {
    return {
      fen,
      pieceCount: 2,
      category: 'draw',
      dtz: 0,
      dtm: 0,
      checkmate: false,
      stalemate: false,
      preciseEval: 'Theoretical Draw (0.00)',
      bestMoves: [],
      isTheoretical: true,
      explanation: 'Bare monarchs on the board — Insufficient material to checkmate.',
    };
  }

  // King + Queen vs King -> Forced Win
  const whiteHasQ = whitePieces.some((p) => p.type === 'q');
  const blackHasQ = blackPieces.some((p) => p.type === 'q');
  if (pieceCount === 3 && (whiteHasQ || blackHasQ)) {
    const winnerColor = whiteHasQ ? 'w' : 'b';
    const isWinForMover = turn === winnerColor;
    return {
      fen,
      pieceCount: 3,
      category: isWinForMover ? 'win' : 'loss',
      dtz: 1,
      dtm: 9,
      checkmate: false,
      stalemate: false,
      preciseEval: isWinForMover ? 'Forced Mate (+M9)' : 'Defeat (-M9)',
      bestMoves: [],
      isTheoretical: true,
      explanation: `${whiteHasQ ? 'White' : 'Black'} possesses decisive Queen advantage. Box the enemy King to the edge rank.`,
    };
  }

  // King + Rook vs King -> Forced Win
  const whiteHasR = whitePieces.some((p) => p.type === 'r');
  const blackHasR = blackPieces.some((p) => p.type === 'r');
  if (pieceCount === 3 && (whiteHasR || blackHasR)) {
    const winnerColor = whiteHasR ? 'w' : 'b';
    const isWinForMover = turn === winnerColor;
    return {
      fen,
      pieceCount: 3,
      category: isWinForMover ? 'win' : 'loss',
      dtz: 1,
      dtm: 16,
      checkmate: false,
      stalemate: false,
      preciseEval: isWinForMover ? 'Forced Mate (+M16)' : 'Defeat (-M16)',
      bestMoves: [],
      isTheoretical: true,
      explanation: `${whiteHasR ? 'White' : 'Black'} Bastion (Rook) cuts off rank and forces opponent king to the border file.`,
    };
  }

  // King + Minor vs King -> Theoretical Draw
  if (
    pieceCount === 3 &&
    (whitePieces.some((p) => p.type === 'b' || p.type === 'n') ||
      blackPieces.some((p) => p.type === 'b' || p.type === 'n'))
  ) {
    return {
      fen,
      pieceCount: 3,
      category: 'draw',
      dtz: 0,
      dtm: 0,
      checkmate: false,
      stalemate: false,
      preciseEval: 'Theoretical Draw (0.00)',
      bestMoves: [],
      isTheoretical: true,
      explanation: 'Insufficient mating material (King + lone minor piece cannot deliver forced checkmate).',
    };
  }

  return {
    fen,
    pieceCount,
    category: 'unknown',
    dtz: null,
    dtm: null,
    checkmate: chess.isCheckmate(),
    stalemate: chess.isStalemate(),
    preciseEval: 'Complex Endgame (Engine Evaluated)',
    bestMoves: [],
    isTheoretical: pieceCount <= 7,
    explanation: `Position contains ${pieceCount} pieces. Requires active piece coordination and king activity.`,
  };
}

/**
 * Query Syzygy Tablebase for positions with <= 7 pieces.
 */
export async function querySyzygyTablebase(fen: string): Promise<SyzygyTablebaseResult> {
  const pieceCount = countPiecesFromFen(fen);

  if (pieceCount > 7) {
    return {
      fen,
      pieceCount,
      category: 'unknown',
      dtz: null,
      dtm: null,
      checkmate: false,
      stalemate: false,
      preciseEval: 'Middlegame / Heavy Endgame (> 7 pieces)',
      bestMoves: [],
      isTheoretical: false,
      explanation: 'Tablebase theoretical databases index endgames with up to 7 pieces. Position currently exceeds 7 pieces.',
    };
  }

  try {
    const encodedFen = encodeURIComponent(fen);
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 2600);

    const res = await fetch(`https://tablebase.lichess.ovh/standard?fen=${encodedFen}`, {
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (!res.ok) {
      return evaluateLocalEndgameHeuristic(fen);
    }

    const data = await res.json();
    const rawCategory = data.category as TablebaseCategory;
    const dtz = typeof data.dtz === 'number' ? data.dtz : null;
    const dtm = typeof data.dtm === 'number' ? data.dtm : null;
    const checkmate = Boolean(data.checkmate);
    const stalemate = Boolean(data.stalemate);

    const moves: TablebaseMove[] = Array.isArray(data.moves)
      ? data.moves.slice(0, 5).map((m: any) => ({
          uci: m.uci,
          san: m.san,
          category: m.category,
          dtz: m.dtz,
          dtm: m.dtm,
          checkmate: m.checkmate,
          stalemate: m.stalemate,
        }))
      : [];

    let preciseEval = 'Theoretical Draw (0.00)';
    let explanation = 'Theoretical tablebase equilibrium.';

    if (rawCategory === 'win') {
      preciseEval = dtm !== null ? `Theoretical Win in ${Math.abs(dtm)} moves (+M${Math.abs(dtm)})` : 'Theoretical Win (+M)';
      explanation = 'Position is mathematically solved as a forced win under perfect play.';
    } else if (rawCategory === 'loss') {
      preciseEval = dtm !== null ? `Forced Loss in ${Math.abs(dtm)} moves (-M${Math.abs(dtm)})` : 'Forced Loss (-M)';
      explanation = 'Defending side faces an insurmountable theoretical forced defeat.';
    } else if (rawCategory === 'cursed-win') {
      preciseEval = '50-Move Rule Theoretical Draw (Cursed Win)';
      explanation = 'Winning position blocked by the 50-move rule without zeroing.';
    } else if (rawCategory === 'blessed-loss') {
      preciseEval = '50-Move Rule Theoretical Escape (Blessed Loss)';
      explanation = 'Defending side escapes via the 50-move rule.';
    }

    return {
      fen,
      pieceCount,
      category: rawCategory,
      dtz,
      dtm,
      checkmate,
      stalemate,
      preciseEval,
      bestMoves: moves,
      isTheoretical: true,
      explanation,
    };
  } catch {
    // Network or timeout fallback to fast local heuristic
    return evaluateLocalEndgameHeuristic(fen);
  }
}
