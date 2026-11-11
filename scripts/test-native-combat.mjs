// Integrate Claude's unchanged Godot suites with a reproducible presentation clock.
// test_assets samples an animated weapon after two physics frames. A variable
// render delta can advance that pose past its sampled strike (Bishop reach 0.85m
// instead of >=0.95m); --fixed-fps 60 makes both clocks use the documented 60 Hz.
// The owner touch fixture also injects logical rather than physical positions.
// A Codex wrapper gives that fixture a1:1 transform; a separate test exercises
// real physical input under the production canvas stretch. No assertions change.
// This flag is TEST ONLY: socket/clock tests and the dedicated server use real time.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const directory = mkdtempSync(join(tmpdir(), 'peepeechess-combat-clock-'));
const env = { ...process.env };
for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
  env[key] = join(directory, key); mkdirSync(env[key]);
}
try {
  for (const args of [
    ['--editor', '--import'],
    ['--script', 'res://tests/test_scaled_touch.gd'],
    ['--script', 'res://tests/run_combat_tests.gd'],
    ['res://combat/scenes/test_arena.tscn', '--', '--auto=demo', '--frames=900'],
  ]) {
    const r = spawnSync(process.env.GODOT_BIN || 'godot', ['--headless', '--fixed-fps', '60', '--path', 'godot', ...args], { env, encoding: 'utf8', timeout: 600000 });
    // Known headless-only engine message: with content scaling disabled the 64x64 fake display makes the pads suite's
    // centered AcceptDialog land at a negative position. Only this exact message (plus its location/backtrace lines)
    // is ignored; any other ERROR: line still fails the run.
    const output = ((r.stdout || '') + (r.stderr || '')).replace(/^ERROR: Window \d+ spawned at invalid position: \(-?\d+, -?\d+\)\.\n(?:[ \t]+(?:at:|GDScript backtrace|\[\d+\])[^\n]*\n?)*/gm, '');
    process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
    if (r.error || r.status !== 0 || /SCRIPT ERROR|Parse Error|^ERROR:|FAIL/m.test(output)) throw r.error || Error(`Native combat check failed: ${r.status}`);
  }
  console.log('PASS: unchanged combat suites and standalone arena on fixed 60 Hz test presentation clock');
} finally { rmSync(directory, { recursive: true, force: true }); }
