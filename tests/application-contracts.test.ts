import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import Ajv from 'ajv/dist/2020.js';

test('account handshake admits only an opaque single-use ticket', () => {
  const schema=JSON.parse(readFileSync('godot/contracts/application/v1/schema.json','utf8'));
  const fixtures=JSON.parse(readFileSync('godot/contracts/application/v1/fixtures.json','utf8'));
  const ajv=new Ajv({strict:true}); ajv.addSchema(schema);
  for(const item of fixtures.valid) assert.equal(ajv.validate(`${schema.$id}#/$defs/${item.type}`,item.payload),true);
  for(const item of fixtures.invalid) assert.equal(ajv.validate(`${schema.$id}#/$defs/${item.type}`,item.payload),false);
});
