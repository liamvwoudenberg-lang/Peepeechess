import { Chess, Square } from 'chess.js';
import { PieceColor, PieceSymbol, SquareId } from '../game/types';
import { VariantType } from '../types/chess';

export interface CrazyhousePocket {
  white: PieceSymbol[];
  black: PieceSymbol[];
}

export interface VariantState {
  type: VariantType;
  threeCheckCount: { white: number; black: number };
  pocket: CrazyhousePocket;
  explodedSquares: SquareId[];
}

export function createInitialVariantState(type: VariantType = 'standard'): VariantState {
  return {
    type,
    threeCheckCount: { white: 0, black: 0 },
    pocket: { white: [], black: [] },
    explodedSquares: [],
  };
}

/**
 * Checks if a King of the Hill instant win occurred (Monarch on d4, d5, e4, e5).
 */
export function checkKingOfTheHillWin(chess: Chess): { winner: PieceColor; reason: string } | null {
  const hillSquares: Square[] = ['d4', 'd5', 'e4', 'e5'];
  for (const sq of hillSquares) {
    const piece = chess.get(sq);
    if (piece && piece.type === 'k') {
      return {
        winner: piece.color,
        reason: `${piece.color === 'w' ? 'White' : 'Black'} Monarch has seized the Citadel Hill (${sq})!`,
      };
    }
  }
  return null;
}

/**
 * Updates 3-Check count after a move.
 */
export function updateThreeCheckState(
  currentState: VariantState,
  chess: Chess,
  moverColor: PieceColor
): { state: VariantState; winner: PieceColor | null; reason?: string } {
  if (currentState.type !== 'three_check') {
    return { state: currentState, winner: null };
  }

  const isCheck = chess.inCheck();
  if (!isCheck) {
    return { state: currentState, winner: null };
  }

  const countKey = moverColor === 'w' ? 'white' : 'black';
  const nextCounts = {
    ...currentState.threeCheckCount,
    [countKey]: currentState.threeCheckCount[countKey] + 1,
  };

  const nextState: VariantState = {
    ...currentState,
    threeCheckCount: nextCounts,
  };

  if (nextCounts[countKey] >= 3) {
    return {
      state: nextState,
      winner: moverColor,
      reason: `${moverColor === 'w' ? 'White' : 'Black'} delivered 3 Checks against the opposing Sovereign!`,
    };
  }

  return { state: nextState, winner: null };
}

/**
 * Computes Atomic explosion squares when a capture occurs.
 * Rule: Both capturing and captured piece explode.
 * In addition, all non-pawn pieces in the 8 adjacent squares are vaporized!
 */
export function computeAtomicExplosion(
  chess: Chess,
  targetSquare: SquareId
): { explodedSquares: SquareId[]; kingDiedWinner: PieceColor | null } {
  const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  const targetFileIdx = files.indexOf(targetSquare[0]);
  const targetRank = parseInt(targetSquare[1], 10);

  const exploded: SquareId[] = [targetSquare];
  let kingDiedWinner: PieceColor | null = null;

  // Check 8 adjacent squares
  for (let df = -1; df <= 1; df++) {
    for (let dr = -1; dr <= 1; dr++) {
      if (df === 0 && dr === 0) continue;
      const nf = targetFileIdx + df;
      const nr = targetRank + dr;
      if (nf >= 0 && nf < 8 && nr >= 1 && nr <= 8) {
        const adjSq = `${files[nf]}${nr}` as Square;
        const p = chess.get(adjSq);
        if (p) {
          // In Atomic chess, pawns are immune to collateral explosion
          if (p.type !== 'p') {
            exploded.push(adjSq);
            if (p.type === 'k') {
              // Opponent wins if a king explodes
              kingDiedWinner = p.color === 'w' ? 'b' : 'w';
            }
          }
        }
      }
    }
  }

  return { explodedSquares: exploded, kingDiedWinner };
}

/**
 * Fog of War vision filter:
 * Returns the set of squares visible to the current player.
 */
export function computeFogOfWarVision(chess: Chess, playerColor: PieceColor): Set<SquareId> {
  const visible = new Set<SquareId>();
  const board = chess.board();

  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const cell = board[r][c];
      if (cell && cell.color === playerColor) {
        visible.add(cell.square);
        // Add all legal and attacked moves for this piece
        const moves = chess.moves({ square: cell.square as Square, verbose: true });
        for (const m of moves) {
          visible.add(m.to);
        }
      }
    }
  }

  return visible;
}
