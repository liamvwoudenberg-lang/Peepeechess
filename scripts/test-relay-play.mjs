// Hosted play THROUGH THE RELAY between three REAL processes: the relay (tools/relay/relay.mjs, in this process), a host Godot process and a
// guest Godot process. No port forwarding and no direct path: the host's game port listens on its loopback only and every datagram crosses
// the relay's WebSocket (ENet + DTLS run end to end; the relay sees ciphertext). Scenarios: Classic, Classic with 60 ms + 2% loss on the relay
// path, Battle up to the capture duel, and the direct fallback when the guest ignores the relay (connection "both").
// Real NAT, a real PaaS and the real internet are NOT covered.
//   node scripts/test-relay-play.mjs
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import { createRelay } from '../tools/relay/relay.mjs';
import { freeUdpPort } from './lib/latency-proxy.mjs';

const godot = process.env.GODOT_BIN || 'godot';
const root = mkdtempSync(join(tmpdir(), 'peepeechess-relay-proc-'));
const diagnostics = /SCRIPT ERROR|Parse Error|PROC FAIL/m;
// Godot 4.6.3 logs these engine errors when a DTLS ENet host is destroyed / a handshake is refused on purpose.
const engineNoise = /^ERROR: (?:Parameter "p_mutex->mutex" is null\.|TLS handshake error: -\d+)\n(?:(?:[ \t]+.*|mbedtls error.*|)\n?)*/gm;

function envFor(name) {
  const env = { ...process.env };
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
    env[key] = join(root, name, key);
    mkdirSync(env[key], { recursive: true });
  }
  return env;
}

function launch(name, args) {
  const child = spawn(godot, ['--headless', '--path', 'godot', '--script', 'res://tests/network/host_proc.gd', '--', ...args], { env: envFor(name), stdio: ['ignore', 'pipe', 'pipe'] });
  let log = '';
  child.stdout.on('data', chunk => { log += chunk; });
  child.stderr.on('data', chunk => { log += chunk; });
  const done = new Promise(resolve => child.on('exit', code => resolve({ code, log: log.replace(engineNoise, '') })));
  return { child, done };
}

async function scenario(label, { impair = null, mode = 'classic', connection = 'relay', guestFlags = [] } = {}) {
  const dir = join(root, label.replace(/\W+/g, '-'));
  mkdirSync(dir, { recursive: true });
  const relay = createRelay({ host: '127.0.0.1', port: 0, testImpair: impair });
  const relayPort = await relay.listen();
  const port = await freeUdpPort();
  const host = launch(`${label}-host`, ['--role=host', `--dir=${dir}`, `--port=${port}`, `--mode=${mode}`, `--relay=ws://127.0.0.1:${relayPort}`, `--connection=${connection}`]);
  const guest = launch(`${label}-guest`, ['--role=guest', `--dir=${dir}`, `--mode=${mode}`, ...guestFlags]);
  const timer = setTimeout(() => { host.child.kill(); guest.child.kill(); }, 170000);
  const [h, g] = await Promise.all([host.done, guest.done]);
  clearTimeout(timer);
  const stats = relay.stats();
  await relay.close();
  for (const [who, r] of [['host', h], ['guest', g]]) {
    assert.equal(r.code, 0, `${label}: ${who} process exited ${r.code}\n${r.log}`);
    assert.ok(!diagnostics.test(r.log), `${label}: ${who} logged errors\n${r.log}`);
    assert.ok(r.log.includes(`PROC ${who}: ok`), `${label}: ${who} did not finish ok\n${r.log}`);
  }
  if (!guestFlags.includes('--no-relay=1')) assert.ok(stats.forwarded > 20, `${label}: only ${stats.forwarded} datagrams crossed the relay`);
  else assert.ok(stats.forwarded < 10, `${label}: the guest used the relay although it was told not to (${stats.forwarded})`);
  const invite = existsSync(join(dir, 'invite.txt')) ? readFileSync(join(dir, 'invite.txt'), 'utf8') : '';
  console.log(`PASS ${label}: ${stats.forwarded} datagrams relayed (${stats.dropped} dropped), invite ${invite.length} characters`);
}

try {
  await scenario('relay classic');
  await scenario('relay classic 60ms+2%', { impair: { delayMs: 30, jitterMs: 6, loss: 0.02 } });
  await scenario('relay battle capture', { mode: 'battle' });
  await scenario('direct fallback', { connection: 'both', guestFlags: ['--no-relay=1'] });
  console.log('PASS: hosted play through a relay between real processes (real NAT / PaaS / internet NOT tested)');
} finally {
  rmSync(root, { recursive: true, force: true });
}
