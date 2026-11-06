import { Chess } from "chess.js";
import { applyMoveToPieceInstances, buildPiecesFromFen } from "./pieceTracker";
import type { MoveAnimationEvent, PieceInstance } from "./types";
import type { Ply } from "../next/contracts";

export interface ScenePosition {
  fen: string;
  pieces: PieceInstance[];
}
export function sceneTransition(
  previous: ScenePosition | null,
  fen: string,
  lastMove: Ply | undefined,
  sequence: number,
): { position: ScenePosition; event: MoveAnimationEvent | null } {
  if (previous && previous.fen === fen)
    return { position: previous, event: null };
  if (previous && lastMove) {
    try {
      const chess = new Chess(previous.fen),
        move = chess.move({
          from: lastMove.from,
          to: lastMove.to,
          promotion: lastMove.promotion,
        });
      if (chess.fen() === fen) {
        const result = applyMoveToPieceInstances(
          previous.pieces,
          move,
          chess,
          sequence,
        );
        return {
          position: { fen, pieces: result.nextPieces },
          event: result.animEvent,
        };
      }
    } catch {
      /* Historical navigation and reconnects restore a position without inventing a move. */
    }
  }
  return { position: { fen, pieces: buildPiecesFromFen(fen) }, event: null };
}
