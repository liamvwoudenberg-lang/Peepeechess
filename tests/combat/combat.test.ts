// Runs the Godot combat suite headlessly and fails on ANY script/parse/resource diagnostic,
// not just a non-zero exit code (Godot can exit 0 despite script errors; see TOOLCHAIN.md).
// Requires Godot 4.6.3 on PATH or in GODOT_BIN. Not part of `npm test` until Codex adds
// `tests/combat/*.test.ts` to the test script (root config is Codex-owned).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const godot = process.env.GODOT_BIN || 'godot';
const dir = mkdtempSync(join(tmpdir(), 'peepeechess-combat-'));
const env = { ...process.env };
for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
  env[key] = join(dir, key);
  mkdirSync(env[key], { recursive: true });
}

function run(args: string[]) {
  const r = spawnSync(godot, ['--headless', '--path', 'godot', ...args], { env, encoding: 'utf8', timeout: 600_000 });
  assert.equal(r.error, undefined, `could not start Godot: ${r.error}`);
  return { status: r.status, output: `${r.stdout}\n${r.stderr}` };
}
const diagnostics = /SCRIPT ERROR|Parse Error|^ERROR:|FAIL/m;

test('godot import registers the combat classes without errors', () => {
  const r = run(['--editor', '--import']);
  assert.equal(r.status, 0, r.output);
  assert.doesNotMatch(r.output, diagnostics, r.output);
});

test('combat suite passes with no engine diagnostics', () => {
  const r = run(['--script', 'res://combat/tests/test_runner.gd']);
  assert.equal(r.status, 0, r.output);
  assert.doesNotMatch(r.output, diagnostics, r.output);
  assert.match(r.output, /PASS: \d+ checks/);
});

test('standalone arena starts and plays an AI-vs-AI fight headless', () => {
  const r = run(['res://combat/scenes/test_arena.tscn', '--', '--auto=demo', '--frames=900']);
  assert.equal(r.status, 0, r.output);
  assert.doesNotMatch(r.output, diagnostics, r.output);
});

test.after(() => rmSync(dir, { recursive: true, force: true }));
