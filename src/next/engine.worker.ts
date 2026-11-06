import { Chess, type Move } from "chess.js";
import { evaluatePositionCp } from "../game/chessCoachEngine";

let deadline = 0;
function order(moves: Move[]) {
  return moves.sort(
    (a, b) =>
      (b.captured ? 10 : 0) +
      (b.promotion ? 20 : 0) -
      (a.captured ? 10 : 0) -
      (a.promotion ? 20 : 0),
  );
}
function search(
  chess: Chess,
  depth: number,
  alpha: number,
  beta: number,
): number {
  if (performance.now() > deadline) throw new Error("budget");
  if (depth <= 0 || chess.isGameOver())
    return evaluatePositionCp(chess) * (chess.turn() === "w" ? 1 : -1);
  let best = -Infinity;
  for (const move of order(chess.moves({ verbose: true }))) {
    chess.move(move);
    let score: number;
    try {
      score = -search(chess, depth - 1, -beta, -alpha);
    } finally {
      chess.undo();
    }
    best = Math.max(best, score);
    alpha = Math.max(alpha, score);
    if (alpha >= beta) break;
  }
  return best;
}
function rank(fen: string, budget: number, maxDepth: number) {
  const chess = new Chess(fen),
    moves = order(chess.moves({ verbose: true }));
  let result = moves
    .map((move) => {
      chess.move(move);
      const score = evaluatePositionCp(chess) * (move.color === "w" ? 1 : -1);
      chess.undo();
      return { move, score };
    })
    .sort((a, b) => b.score - a.score);
  deadline = performance.now() + budget;
  for (let depth = 2; depth <= maxDepth; depth++) {
    const next: typeof result = [];
    try {
      for (const item of result) {
        chess.move(item.move);
        let score: number;
        try {
          score = -search(chess, depth - 1, -Infinity, Infinity);
        } finally {
          chess.undo();
        }
        next.push({ move: item.move, score });
      }
    } catch {
      break;
    }
    result = next.sort((a, b) => b.score - a.score);
  }
  return result;
}
self.onmessage = ({ data }) => {
  try {
    const { id, fen, action, elo = 1200, move } = data;
    const ranked = rank(
      fen,
      action === "feedback"
        ? 220
        : Math.max(80, Math.min(700, (elo - 300) * 0.35)),
      elo >= 1600 ? 4 : elo >= 1000 ? 3 : 2,
    );
    if (!ranked.length) {
      self.postMessage({ id, move: null });
      return;
    }
    if (action === "feedback") {
      const played = ranked.find(
        (r) =>
          r.move.from === move.from &&
          r.move.to === move.to &&
          (r.move.promotion || "") === (move.promotion || ""),
      );
      const loss = Math.max(
        0,
        ranked[0].score - (played?.score ?? ranked[0].score),
      );
      const after = new Chess(fen);
      const executed = after.move(move);
      const verdict = after.isCheckmate()
        ? "Checkmate"
        : loss <= 15
          ? "Best"
          : loss <= 45
            ? "Great"
            : loss <= 90
              ? "Good"
              : loss <= 180
                ? "Inaccuracy"
                : loss <= 300
                  ? "Mistake"
                  : "Blunder";
      self.postMessage({
        id,
        verdict,
        loss,
        san: executed.san,
        best: ranked[0].move.san,
        from: ranked[0].move.from,
        to: ranked[0].move.to,
      });
    } else {
      const errorChance = Math.max(0.02, (2100 - elo) / 2300);
      const index =
        action === "hint" || Math.random() > errorChance
          ? 0
          : Math.min(
              ranked.length - 1,
              Math.floor(Math.random() * Math.max(2, (2200 - elo) / 140)),
            );
      const chosen = ranked[index].move;
      self.postMessage({
        id,
        move: { from: chosen.from, to: chosen.to, promotion: chosen.promotion },
        san: chosen.san,
      });
    }
  } catch (error) {
    self.postMessage({ id: data.id, error: String(error) });
  }
};
