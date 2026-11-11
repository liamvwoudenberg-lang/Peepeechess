// battle-royal-v1 gate: rules, flow, server session, real-simulation `royal` combat suite. Fails on SCRIPT ERROR / ERROR: lines.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const temporary = mkdtempSync(join(tmpdir(), 'peepeechess-royal-'));
const env = { ...process.env };
for (const name of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
  env[name] = join(temporary, name); mkdirSync(env[name]);
}
const run = args => {
  const r = spawnSync(process.env.GODOT_BIN || 'godot', ['--headless', '--path', 'godot', ...args], { env, encoding: 'utf8', timeout: 600000 });
  process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
  if (r.error || r.status !== 0 || /SCRIPT ERROR|Parse Error|^ERROR:|FAIL/m.test((r.stdout || '') + (r.stderr || ''))) throw r.error || Error(`Godot failed with exit ${r.status}: ${args.join(' ')}`);
};
try {
  run(['--editor', '--import']);
  for (const script of ['rules_test', 'flow_test', 'session_test']) run(['--script', `res://tests/royal/${script}.gd`]);
  run(['--script', 'res://combat/tests/test_runner.gd', '--', 'royal']);
  console.log('PASS: battle-royal-v1 rules, flow, server session and real-simulation suites');
} finally { rmSync(temporary, { recursive: true, force: true }); }
