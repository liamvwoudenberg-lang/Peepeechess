import { Chess, Move } from "chess.js";
import {
  MoveAnimationEvent,
  PieceInstance,
  PieceSymbol,
  SquareId,
} from "./types";

export function buildPiecesFromFen(fen: string): PieceInstance[] {
  const chess = new Chess(fen);
  const board = chess.board();
  const pieces: PieceInstance[] = [];

  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const cell = board[r][c];
      if (!cell) continue;
      pieces.push({
        id: `${cell.color}_${cell.type}_${cell.square}`,
        type: cell.type,
        color: cell.color,
        square: cell.square,
      });
    }
  }
  return pieces;
}

export function determineCombatRole(
  pieceType: PieceSymbol,
  isCapture: boolean,
): MoveAnimationEvent["combatRole"] {
  if (!isCapture) return undefined;
  if (pieceType === "n") return "knight_charge";
  if (pieceType === "r") return "rook_ballista";
  if (pieceType === "q") return "queen_sorcery";
  if (pieceType === "b") return "cleric_radiance";
  return "blade_slash";
}

export function applyMoveToPieceInstances(
  currentPieces: PieceInstance[],
  executedMove: Move,
  afterChess: Chess,
  eventSeq: number,
): { nextPieces: PieceInstance[]; animEvent: MoveAnimationEvent } {
  const nextPieces = currentPieces.map((p) => ({ ...p }));

  const moverIdx = nextPieces.findIndex(
    (p) => p.square === executedMove.from && p.color === executedMove.color,
  );

  if (moverIdx === -1) {
    const reconciled = buildPiecesFromFen(afterChess.fen());
    return {
      nextPieces: reconciled,
      animEvent: {
        id: `anim_${eventSeq}`,
        pieceId: `${executedMove.color}_${executedMove.piece}_${executedMove.to}`,
        pieceType: executedMove.piece,
        color: executedMove.color,
        from: executedMove.from,
        to: executedMove.to,
        isCheck: afterChess.inCheck(),
        isCheckmate: afterChess.isCheckmate(),
        san: executedMove.san,
        combatRole: determineCombatRole(
          executedMove.piece,
          Boolean(executedMove.captured),
        ),
      },
    };
  }

  const mover = nextPieces[moverIdx];
  let capturedPieceId: string | undefined;
  let capturedPieceType: PieceSymbol | undefined;
  let capturedSquare: SquareId | undefined;

  if (executedMove.captured) {
    if (executedMove.flags.includes("e")) {
      const epRank = executedMove.color === "w" ? "5" : "4";
      capturedSquare = `${executedMove.to[0]}${epRank}`;
    } else {
      capturedSquare = executedMove.to;
    }

    const victimIdx = nextPieces.findIndex(
      (p) => p.square === capturedSquare && p.color !== executedMove.color,
    );
    if (victimIdx !== -1) {
      capturedPieceId = nextPieces[victimIdx].id;
      capturedPieceType = nextPieces[victimIdx].type;
      nextPieces.splice(victimIdx, 1);
    }
  }

  mover.square = executedMove.to;
  if (executedMove.promotion) {
    mover.type = executedMove.promotion as PieceSymbol;
  }

  let rookCastleMove: MoveAnimationEvent["rookCastleMove"];
  if (executedMove.flags.includes("k") || executedMove.flags.includes("q")) {
    const rank = executedMove.color === "w" ? "1" : "8";
    const rookFrom = executedMove.flags.includes("k") ? `h${rank}` : `a${rank}`;
    const rookTo = executedMove.flags.includes("k") ? `f${rank}` : `d${rank}`;
    const rook = nextPieces.find(
      (p) =>
        p.square === rookFrom &&
        p.color === executedMove.color &&
        p.type === "r",
    );
    if (rook) {
      rook.square = rookTo;
      rookCastleMove = {
        pieceId: rook.id,
        from: rookFrom,
        to: rookTo,
      };
    }
  }

  const animEvent: MoveAnimationEvent = {
    id: `anim_${eventSeq}_${executedMove.san}`,
    pieceId: mover.id,
    pieceType: executedMove.piece,
    color: mover.color,
    from: executedMove.from,
    to: executedMove.to,
    capturedPieceId,
    capturedPieceType,
    capturedSquare,
    rookCastleMove,
    promotedTo: executedMove.promotion as PieceSymbol | undefined,
    isCheck: afterChess.inCheck(),
    isCheckmate: afterChess.isCheckmate(),
    san: executedMove.san,
    combatRole: determineCombatRole(
      executedMove.piece,
      Boolean(executedMove.captured),
    ),
  };

  return { nextPieces, animEvent };
}
