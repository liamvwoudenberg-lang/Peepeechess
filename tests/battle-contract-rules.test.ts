import test from "node:test";
import assert from "node:assert/strict";
import { Chess } from "chess.js";
import { createBattleMatch, battleMoves, attemptBattleMove, resolveBattleCapture, kingSafe } from "../src/battle/rules";

test("documented Battle mate excludes an Orthodox king-capture escape, without removing a king", () => {
  const fen = "1r5k/8/8/8/8/8/r7/K7 w - - 0 1";
  const classic = new Chess(fen);
  assert.equal(classic.isCheckmate(), false);
  assert.deepEqual(classic.moves(), ["Kxa2"]);
  const battle = createBattleMatch(undefined, fen);
  assert.equal(battle.reason, "Checkmate");
  assert.equal(battle.result, "0-1");
  assert.equal(new Chess(battle.fen).get("a1")?.type, "k");
});

test("every admitted capture in representative pin/check/EP/promotion positions has two safe outcomes", () => {
  const positions = [
    "7k/8/8/4q3/3P4/8/8/7K w - - 0 1",
    "4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1",
    "7k/8/8/8/8/8/3Rr3/4K3 w - - 0 1",
    "7k/8/8/3pP3/8/8/8/7K w - d6 0 1",
    "7k/8/8/3pP3/4K3/8/8/8 w - d6 0 1",
    "1r5k/P7/8/8/8/8/8/K7 w - - 0 1",
  ];
  let checked = 0;
  for (const fen of positions) for (const move of battleMoves(fen).filter(m => m.captured)) {
    const pending = attemptBattleMove(createBattleMatch(undefined, fen), move.from, move.to, move.promotion ?? "q");
    for (const winner of [move.color, move.color === "w" ? "b" : "w"] as const) {
      const resolved = resolveBattleCapture(pending, pending.pending!.id, winner);
      const c = new Chess(resolved.fen);
      assert.ok(kingSafe(c, move.color), `${fen}: ${move.san}: ${winner}`);
      for (const color of ["w", "b"] as const)
        assert.equal(c.board().flat().filter(p => p?.color === color && p.type === "k").length, 1);
      assert.equal(resolved.history.length, 1);
      assert.notEqual(c.turn(), move.color);
      checked++;
    }
  }
  assert.ok(checked >= 12);
});
