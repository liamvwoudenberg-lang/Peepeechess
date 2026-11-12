import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validate } from "../../contracts/v1/validate";
import { validateRoyal } from "../../contracts/royal/v1/validate";
import { buildRoyalSchema, ROYAL_SCHEMA_PATH } from "../../scripts/build-royal-schema.mjs";
const cases = JSON.parse(readFileSync(new URL("../../godot/contracts/royal/v1/fixtures.json", import.meta.url), "utf8"));
const committed = JSON.parse(readFileSync(ROYAL_SCHEMA_PATH, "utf8"));
for (const c of cases) test(`royal v1: ${c.name}`, () => {
  assert.equal(validateRoyal(c.type, JSON.parse(JSON.stringify(c.payload))), c.valid);
});
test("royal schema is exactly the generated one (v1 definitions copied verbatim, nothing hand-edited)", () => {
  assert.deepEqual(buildRoyalSchema(), committed);
  const v1 = JSON.parse(readFileSync(new URL("../../godot/contracts/v1/schema.json", import.meta.url), "utf8"));
  for (const name of ["CharacterId", "FighterStats", "BattleResult", "FighterSnapshot", "CombatEvent", "CombatSnapshot", "Piece", "HistoryEntry", "ChessGameState"]) {
    assert.deepEqual(committed.$defs[name], v1.$defs[name], name);
  }
});
test("v1 stays strict: a king duel is not a v1 BattleRequest, a royal match state is not a v1 MatchState", () => {
  const request = cases.find((c: any) => c.type === "RoyalBattleRequest" && c.valid).payload;
  assert.equal(validate("BattleRequest", request), false);
  const state = cases.find((c: any) => c.type === "RoyalMatchState" && c.valid).payload;
  assert.equal(validate("MatchState", state), false);
  // ...while every v1 payload the royal flow reuses unchanged is still a plain v1 payload.
  const result = cases.find((c: any) => c.type === "BattleResult" && c.valid).payload;
  assert.equal(validate("BattleResult", result), true);
});
test("fixtures cover every royal type and the documented invariants", () => {
  const types = new Set(cases.filter((c: any) => c.valid).map((c: any) => c.type));
  for (const t of ["RoyalSequenceRequest", "RoyalBattleRequest", "RoyalDuelRequest", "RoyalDuelResult", "RoyalSequenceProgress", "RoyalSequenceResult", "RoyalMatchState"]) assert.ok(types.has(t), t);
  const request = cases.find((c: any) => c.name === "valid RoyalSequenceRequest (double check)").payload;
  assert.equal(request.attackers.length, 2);
  const order = request.attackers.map((a: any) => a.square);
  assert.deepEqual(order, ["e1", "a8"]); // equal material (rooks): ascending square a1..h8
  const carried = cases.find((c: any) => c.name === "valid RoyalDuelRequest (carried king state)").payload;
  assert.deepEqual(carried.kingStart, { hp: 112, stamina: 61.5, cooldownTicks: 340 });
  assert.equal(carried.battle.attacker.role, "k"); // the king is the attacker; ties go to the defending checker
  assert.equal(carried.duelIndex, 1);
  const stats = carried.battle.attacker.stats;
  assert.ok(carried.kingStart.hp <= stats.maxHp && carried.kingStart.cooldownTicks <= stats.cooldownTicks);
});
