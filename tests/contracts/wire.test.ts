import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validate } from "../../contracts/v1/validate";
import type { Contracts } from "../../contracts/v1/types";
import { Chess } from "chess.js";
import { attemptBattleMove, createBattleMatch, resolveBattleCapture, kingSafe } from "../../src/battle/rules";
const cases = JSON.parse(readFileSync(new URL("../../godot/contracts/v1/fixtures.json", import.meta.url), "utf8"));
for (const c of cases) test(`wire v1: ${c.name}`, () => {
  assert.equal(validate(c.type, JSON.parse(JSON.stringify(c.payload))), c.valid);
});
const sample = <K extends keyof Contracts>(type: K): Contracts[K] => cases.find((c: any) => c.type === type && c.valid).payload;

test("BattleRequest example maps onto the existing engine and both outcomes retain king safety", () => {
  const b = sample("BattleRequest");
  const original = createBattleMatch(undefined, b.beforeFen, b.matchId);
  const pending = attemptBattleMove(original, b.from as any, b.to as any, b.promotion ?? "q");
  assert.equal(pending.fen, b.beforeFen);
  assert.equal(pending.pending?.defender.square, b.defender.square);
  for (const outcome of ["attacker", "defender"] as const) {
    const winner = b[outcome].color;
    const final = resolveBattleCapture(pending, pending.pending!.id, winner);
    const c = new Chess(final.fen);
    assert.equal(c.turn(), b.defender.color);
    assert.ok(kingSafe(c, b.attacker.color));
    assert.equal(c.get(b.to as any)?.color, winner);
    assert.throws(() => resolveBattleCapture(final, pending.pending!.id, winner));
  }
  const r = sample("BattleResult");
  assert.equal(r.winnerPlayerId, b[r.outcome].playerId);
  assert.equal(r.expectedRevision, b.expectedRevision);
});

test("MatchState example has consistent FEN, stable piece IDs, references and history", () => {
  const m = sample("MatchState");
  const c = new Chess(m.chess.fen);
  assert.equal(m.mode, "battle");
  assert.equal(m.rulesetId, "battle-checkmate-v1");
  assert.equal(m.chess.matchId, m.matchId);
  assert.equal(m.battle!.beforeFen, m.chess.fen);
  assert.equal(m.battle!.battleId, m.combat!.battleId);
  assert.equal(m.chess.ply, m.chess.history.length);
  assert.equal(new Set(m.chess.pieces.map(p => p.pieceId)).size, m.chess.pieces.length);
  assert.equal(c.board().flat().filter(Boolean).length, m.chess.pieces.length);
  for (const p of m.chess.pieces) assert.deepEqual(c.get(p.square as any), { color: p.color, type: p.role });
  for (const f of m.combat!.fighters) {
    assert.ok(m.chess.pieces.some(p => p.pieceId === f.pieceId));
    assert.ok(Object.values(m.players).includes(f.playerId));
  }
});
