import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const dir = mkdtempSync(join(tmpdir(), 'peepeechess-contracts-'));
const output = join(dir, 'godot-roundtrip.json');
const royalOutput = join(dir, 'godot-royal-roundtrip.json');
const runtimeEnv = { ...process.env };
for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
  runtimeEnv[key] = join(dir, key);
  mkdirSync(runtimeEnv[key], { recursive: true });
}
try {
  const run = (command, args) => {
    const result = spawnSync(command, args, { stdio: 'inherit', env: runtimeEnv });
    if (result.error) throw result.error;
    if (result.status !== 0) throw Error(`${command} failed: ${result.status}`);
  };
  run('node', ['--import', 'tsx', '--test', 'tests/contracts/wire.test.ts', 'tests/contracts/royal.test.ts', 'tests/contracts/royal-network.test.ts']);
  run(process.env.GODOT_BIN || 'godot', ['--headless', '--path', 'godot', '--script', 'res://tests/contracts_test.gd', '--', output]);
  const { validate } = await import('../contracts/v1/validate.ts');
  const examples = JSON.parse(readFileSync(output, 'utf8'));
  const source = JSON.parse(readFileSync('godot/contracts/v1/fixtures.json', 'utf8')).filter(c => c.valid);
  const { isDeepStrictEqual } = await import('node:util');
  if (examples.length !== source.length) throw Error('Missing Godot roundtrips');
  for (const [i, item] of examples.entries()) {
    if (!validate(item.type, item.payload) || !isDeepStrictEqual(item.payload, source[i].payload)) {
      throw Error(`Godot -> Node mismatch: ${item.type}`);
    }
  }
  console.log(`PASS: ${examples.length} Node -> Godot -> Node payloads preserved exactly`);
  // battle-royal-v1 (additive, separate schema): same round trip, valid fixtures byte-for-byte equal after Godot.
  run(process.env.GODOT_BIN || 'godot', ['--headless', '--path', 'godot', '--script', 'res://tests/royal_contracts_test.gd', '--', royalOutput]);
  const { validateRoyal } = await import('../contracts/royal/v1/validate.ts');
  const royal = JSON.parse(readFileSync(royalOutput, 'utf8'));
  const royalSource = JSON.parse(readFileSync('godot/contracts/royal/v1/fixtures.json', 'utf8')).filter(c => c.valid);
  if (royal.length !== royalSource.length) throw Error('Missing Godot royal roundtrips');
  for (const [i, item] of royal.entries()) {
    if (!validateRoyal(item.type, item.payload) || !isDeepStrictEqual(item.payload, royalSource[i].payload)) {
      throw Error(`Godot -> Node royal mismatch: ${item.type}`);
    }
  }
  console.log(`PASS: ${royal.length} royal Node -> Godot -> Node payloads preserved exactly`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
