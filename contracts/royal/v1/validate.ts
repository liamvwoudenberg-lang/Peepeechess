/** Node tooling codec for the battle-royal-v1 sequence contract (the v1 codec stays untouched). */
import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";
import type { RoyalContracts } from "./types";
const schema = JSON.parse(readFileSync(new URL("../../../godot/contracts/royal/v1/schema.json", import.meta.url), "utf8"));
const ajv = new Ajv2020({ strict: true, allErrors: true });
ajv.addSchema(schema);
export function validateRoyal<K extends keyof RoyalContracts>(type: K, payload: unknown): payload is RoyalContracts[K] {
  return ajv.validate({ $ref: `${schema.$id}#/$defs/${type}` }, payload) === true;
}
