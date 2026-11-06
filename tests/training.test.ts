import test from "node:test";
import assert from "node:assert/strict";
import { Chess } from "chess.js";
import { LESSONS, PUZZLES } from "../src/next/training";

test("every lesson and puzzle has a complete legal line; mate exercises really end in mate", () => {
  for (const item of [...LESSONS, ...PUZZLES]) {
    const c = new Chess(item.fen);
    for (const san of item.line) assert.ok(c.move(san), `${item.id}: ${san}`);
    if (item.line[item.line.length - 1].includes("#"))
      assert.equal(c.isCheckmate(), true, item.id);
  }
});
test("the pin lesson actually immobilizes the knight and the fork has a forced king response", () => {
  const pin = new Chess(LESSONS.find((x) => x.id === "pin")!.fen);
  pin.move("Re1");
  assert.equal(pin.moves({ square: "e7" }).length, 0);
  const fork = new Chess(PUZZLES.find((x) => x.id === "fork")!.fen);
  fork.move("Nf7");
  assert.deepEqual(fork.moves(), ["Kg8"]);
});
