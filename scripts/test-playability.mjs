import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const temporary = mkdtempSync(join(tmpdir(), 'peepeechess-playability-'));
let runNumber = 0;
function freshEnv() {
  const env = { ...process.env };
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
    env[key] = join(temporary, String(runNumber), key);
    mkdirSync(env[key], { recursive: true });
  }
  runNumber++;
  return env;
}
try {
  const python = spawnSync(process.env.PYTHON || 'python3', ['-m', 'unittest', 'discover', '-s', 'tests', '-p', 'android_verifier_test.py'], { encoding: 'utf8' });
  process.stdout.write(python.stdout || ''); process.stderr.write(python.stderr || '');
  assert.equal(python.status, 0, 'Android verifier must reject incomplete, desktop or blank-frame evidence');
  const godot = process.env.GODOT_BIN || 'godot';
  for (const args of [
    ['--editor', '--import'],
    ['--script', 'res://tests/battle/mobile_controls_test.gd'],
    ['--script', 'res://tests/ai/computer_capture_test.gd'],
    ['--', '--playability-smoke'],
  ]) {
    // The full app owns real-time loading/countdowns; keep its normal clock.
    const clock = args.includes('--playability-smoke') ? [] : ['--fixed-fps', '60'];
    const result = spawnSync(godot, ['--headless', ...clock, '--path', 'godot', ...args], { env: freshEnv(), encoding: 'utf8', timeout: 240000 });
    const log = (result.stdout || '') + (result.stderr || '');
    process.stdout.write(log);
    assert.equal(result.status, 0, `Playability check failed: ${args.join(' ')}`);
    assert.doesNotMatch(log, /SCRIPT ERROR|Parse Error|^ERROR:|FAIL:/m);
    if (args.includes('--playability-smoke')) {
      const results = log.split('\n').filter(line => line.startsWith('PEEPEECHESS_SMOKE ')).map(line => JSON.parse(line.slice('PEEPEECHESS_SMOKE '.length))).filter(row => row.event === 'result');
      assert.equal(results.length, 1, 'complete run must emit exactly one result');
      assert.equal(results[0].passed, true);
      assert.ok(results[0].checks >= 20);
      assert.equal(results[0].rendered, false, 'headless harness check must not claim Android/rendered validation');
    }
  }
  console.log('PASS: full local playability loop and Android verifier logic; installed APK validation is a separate device/emulator check');
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
