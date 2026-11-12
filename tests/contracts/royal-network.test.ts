import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";
import { buildSchema, buildFixtures, SCHEMA_PATH, FIXTURES_PATH } from "../../scripts/build-royal-network-schema.mjs";
const committed = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
const fixtures = JSON.parse(readFileSync(FIXTURES_PATH, "utf8"));
const ajv = new Ajv2020({ strict: true, allErrors: true });
ajv.addSchema(committed);
const valid = (type: string, payload: unknown) => ajv.validate({ $ref: `${committed.$id}#/$defs/${type}` }, payload) === true;
for (const c of fixtures) test(`royal wire v1: ${c.name}`, () => assert.equal(valid(c.type, JSON.parse(JSON.stringify(c.payload))), c.valid));
test("royal wire schema and fixtures are exactly the generated ones", () => {
  assert.deepEqual(buildSchema(), committed);
  assert.deepEqual(buildFixtures(), fixtures);
});
test("v1 stays untouched: shared definitions are verbatim copies, royal messages are not v1 messages", () => {
  const net = JSON.parse(readFileSync(new URL("../../godot/contracts/network/v1/schema.json", import.meta.url), "utf8"));
  for (const name of ["ClockState", "InputResume", "JoinMatch", "MatchCommand", "Ping", "Pong", "Ack", "ClockSync"]) assert.deepEqual(committed.$defs[name], net.$defs[name], name);
  const v1 = new Ajv2020({ strict: true, allErrors: true }); v1.addSchema(net);
  v1.addSchema(JSON.parse(readFileSync(new URL("../../godot/contracts/v1/schema.json", import.meta.url), "utf8")));
  const hello = fixtures.find((c: any) => c.type === "RoyalHello" && c.valid).payload;
  assert.equal(v1.validate({ $ref: `${net.$id}#/$defs/Hello` }, hello), false);
  assert.equal(v1.validate({ $ref: `${net.$id}#/$defs/MatchFrame` }, fixtures.find((c: any) => c.type === "RoyalMatchFrame" && c.valid).payload), false);
});
