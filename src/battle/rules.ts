import {
  Chess,
  type Color,
  type PieceSymbol,
  type Square,
  type Move,
} from "chess.js";
import type { Army } from "../game/battleProfiles";
export type BattlePhase = "board" | "combat" | "aftermath" | "complete";
export interface CaptureIntent {
  id: string;
  before: string;
  from: Square;
  to: Square;
  promotion?: string;
  san: string;
  attacker: { color: Color; role: PieceSymbol };
  defender: { color: Color; role: PieceSymbol; square: Square };
}
export interface BattlePly {
  from: Square;
  to: Square;
  promotion?: string;
  san: string;
  fen: string;
  outcome?: "attacker" | "defender";
}
export interface BattleMatch {
  version: 1;
  id: string;
  fen: string;
  initialFen: string;
  armies: Record<Color, Army>;
  phase: BattlePhase;
  pending: CaptureIntent | null;
  history: BattlePly[];
  repetitions: Record<string, number>;
  result?: "1-0" | "0-1" | "1/2-1/2";
  reason?: string;
}
export const other = (color: Color): Color => (color === "w" ? "b" : "w");
const positionKey = (fen: string) => {
  const fields = fen.split(" ").slice(0, 4);
  if (fields[3] !== "-" && !battleMoves(fen).some((move) => move.isEnPassant()))
    fields[3] = "-";
  return fields.join(" ");
};
const kingSquare = (c: Chess, color: Color) =>
  c
    .board()
    .flat()
    .find((p) => p?.type === "k" && p.color === color)?.square;
export function kingSafe(c: Chess, color: Color) {
  const square = kingSquare(c, color);
  return Boolean(square && !c.isAttacked(square, other(color)));
}
export function createBattleMatch(
  armies: Record<Color, Army> = { w: "royal", b: "skeletons" },
  fen = new Chess().fen(),
  id: string = typeof globalThis.crypto.randomUUID === "function"
    ? globalThis.crypto.randomUUID()
    : Array.from(globalThis.crypto.getRandomValues(new Uint8Array(16)), (b) =>
        b.toString(16).padStart(2, "0"),
      ).join(""),
): BattleMatch {
  const c = new Chess(fen);
  if (!kingSafe(c, other(c.turn())))
    throw Error("The side that just moved cannot be in check.");
  return adjudicate({
    version: 1,
    id,
    fen: c.fen(),
    initialFen: c.fen(),
    armies,
    phase: "board",
    pending: null,
    history: [],
    repetitions: { [positionKey(c.fen())]: 1 },
  });
}
function defenderFen(fen: string, m: Move): string {
  if (m.piece === "k") throw Error("A king never fights a capture duel.");
  const c = new Chess(fen);
  c.remove(m.from);
  const fields = c.fen().split(" "),
    old = fen.split(" ");
  let rights = fields[2];
  // Removing an attacking original rook also removes its castling right.
  const right = (
    { a1: "Q", h1: "K", a8: "q", h8: "k" } as Record<string, string>
  )[m.from];
  if (right) rights = rights.replace(right, "");
  fields[1] = other(m.color);
  fields[2] = rights || "-";
  fields[3] = "-";
  fields[4] = "0";
  fields[5] = String(Number(old[5]) + (m.color === "b" ? 1 : 0));
  return new Chess(fields.join(" ")).fen();
}
export function captureRestriction(fen: string, move: Move): string | null {
  if (!move.captured) return null;
  if (move.captured === "k" || move.piece === "k")
    return "Kings use checkmate and cannot enter a capture duel. Move your king to an empty safe square or defend with another piece.";
  try {
    if (!kingSafe(new Chess(defenderFen(fen, move)), move.color))
      return "This capture is unavailable: losing the duel would leave your king in check.";
  } catch {
    return "This capture cannot resolve safely.";
  }
  return null;
}
export function battleMoves(fen: string): Move[] {
  return new Chess(fen)
    .moves({ verbose: true })
    .filter((m) => !captureRestriction(fen, m));
}
export function restrictedMoves(
  fen: string,
): { from: Square; to: Square; reason: string }[] {
  return new Chess(fen).moves({ verbose: true }).flatMap((m) => {
    const reason = captureRestriction(fen, m);
    return reason ? [{ from: m.from, to: m.to, reason }] : [];
  });
}
function adjudicate(match: BattleMatch): BattleMatch {
  const c = new Chess(match.fen),
    moves = battleMoves(match.fen);
  let reason: string | undefined, result: BattleMatch["result"];
  if (!moves.length) {
    reason = c.inCheck() ? "Checkmate" : "Stalemate";
    result = c.inCheck() ? (c.turn() === "w" ? "0-1" : "1-0") : "1/2-1/2";
  } else if (c.isInsufficientMaterial()) {
    reason = "Insufficient material";
    result = "1/2-1/2";
  } else if (Number(match.fen.split(" ")[4]) >= 100) {
    reason = "Fifty-move rule";
    result = "1/2-1/2";
  } else if ((match.repetitions[positionKey(match.fen)] || 0) >= 3) {
    reason = "Threefold repetition";
    result = "1/2-1/2";
  }
  return result ? { ...match, phase: "complete", result, reason } : match;
}
function commit(
  match: BattleMatch,
  fen: string,
  ply: Omit<BattlePly, "fen">,
): BattleMatch {
  const key = positionKey(fen);
  return adjudicate({
    ...match,
    fen,
    pending: null,
    phase: "board",
    history: [...match.history, { ...ply, fen }],
    repetitions: {
      ...match.repetitions,
      [key]: (match.repetitions[key] || 0) + 1,
    },
  });
}
export function attemptBattleMove(
  match: BattleMatch,
  from: Square,
  to: Square,
  promotion = "q",
): BattleMatch {
  if (match.phase !== "board")
    throw Error("Wait for the current battle to finish.");
  const c = new Chess(match.fen),
    m = c
      .moves({ verbose: true })
      .find(
        (m) =>
          m.from === from &&
          m.to === to &&
          (!m.promotion || m.promotion === promotion),
      );
  if (!m) throw Error("That move is not legal.");
  const reason = captureRestriction(match.fen, m);
  if (reason) throw Error(reason);
  if (!m.captured) {
    c.move({ from, to, promotion });
    return commit(match, c.fen(), {
      from,
      to,
      promotion: m.promotion,
      san: m.san,
    });
  }
  const square = (
    m.isEnPassant() ? `${to[0]}${m.color === "w" ? "5" : "4"}` : to
  ) as Square;
  const pending: CaptureIntent = {
    id: `${match.id}:${match.history.length}`,
    before: match.fen,
    from,
    to,
    promotion: m.promotion,
    san: m.san,
    attacker: { color: m.color, role: m.piece },
    defender: { color: other(m.color), role: m.captured, square },
  };
  return { ...match, phase: "combat", pending };
}
export function resolveBattleCapture(
  match: BattleMatch,
  id: string,
  winner: Color,
): BattleMatch {
  const p = match.pending;
  if (
    !p ||
    p.id !== id ||
    p.before !== match.fen ||
    !["combat", "aftermath"].includes(match.phase)
  )
    throw Error("This battle is no longer pending.");
  if (winner !== p.attacker.color && winner !== p.defender.color)
    throw Error("Invalid battle winner.");
  const c = new Chess(p.before),
    m = c
      .moves({ verbose: true })
      .find(
        (m) =>
          m.from === p.from && m.to === p.to && m.promotion === p.promotion,
      );
  if (!m || !m.captured || captureRestriction(p.before, m))
    throw Error("The saved capture is not valid.");
  const attacking = winner === p.attacker.color;
  let fen: string;
  if (attacking) {
    c.move({ from: p.from, to: p.to, promotion: p.promotion });
    fen = c.fen();
  } else fen = defenderFen(p.before, m);
  if (!kingSafe(new Chess(fen), p.attacker.color))
    throw Error("Combat cannot expose the moving king.");
  return commit(match, fen, {
    from: p.from,
    to: p.to,
    promotion: p.promotion,
    san: attacking ? m.san : `${m.san} [defended]`,
    outcome: attacking ? "attacker" : "defender",
  });
}
export function resignBattleMatch(
  match: BattleMatch,
  color: Color,
  reason = "Resignation",
): BattleMatch {
  if (match.phase === "complete") return match;
  return {
    ...match,
    phase: "complete",
    pending: null,
    result: color === "w" ? "0-1" : "1-0",
    reason,
  };
}
