/** Node tooling codec; transport integration is a later task. */
import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";
import type { Contracts } from "./types";
const schema = JSON.parse(readFileSync(new URL("../../godot/contracts/v1/schema.json", import.meta.url), "utf8"));
const ajv = new Ajv2020({ strict: true, allErrors: true });
ajv.addSchema(schema);
export function validate<K extends keyof Contracts>(type: K, payload: unknown): payload is Contracts[K] {
  return ajv.validate({ $ref: `${schema.$id}#/$defs/${type}` }, payload) === true;
}
