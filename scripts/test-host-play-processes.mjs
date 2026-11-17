// Hosted-friend play between TWO REAL Godot processes over localhost UDP (not one process talking to itself):
//   host process: HostedGame (DTLS listen server, fake router) + its own client as Black
//   guest process: reads the invite file, joins through InviteJoin, both Ready, e2-e4 / e7-e5
// Scenarios: direct, and through the UDP latency/loss proxy (60 ms RTT, 2% loss). Real routers, NAT and the internet are NOT covered.
//   node scripts/test-host-play-processes.mjs
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import { startProxy, freeUdpPort } from './lib/latency-proxy.mjs';

const godot = process.env.GODOT_BIN || 'godot';
const root = mkdtempSync(join(tmpdir(), 'peepeechess-host-proc-'));
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

async function scenario(label, { impair = null } = {}) {
  const dir = join(root, label.replace(/\W+/g, '-'));
  mkdirSync(dir, { recursive: true });
  const port = await freeUdpPort();
  const host = launch(`${label}-host`, ['--role=host', `--dir=${dir}`, `--port=${port}`]);
  let proxy = null;
  const guestArgs = ['--role=guest', `--dir=${dir}`];
  if (impair) {
    proxy = await startProxy(port, impair);
    guestArgs.push(`--via-port=${proxy.port}`);
  }
  const guest = launch(`${label}-guest`, guestArgs);
  const timer = setTimeout(() => { host.child.kill(); guest.child.kill(); }, 150000);
  const [h, g] = await Promise.all([host.done, guest.done]);
  clearTimeout(timer);
  if (proxy) proxy.close?.();
  for (const [who, r] of [['host', h], ['guest', g]]) {
    assert.equal(r.code, 0, `${label}: ${who} process exited ${r.code}\n${r.log}`);
    assert.ok(!diagnostics.test(r.log), `${label}: ${who} logged errors\n${r.log}`);
    assert.ok(r.log.includes(`PROC ${who}: ok`), `${label}: ${who} did not finish ok\n${r.log}`);
  }
  const invite = existsSync(join(dir, 'invite.txt')) ? readFileSync(join(dir, 'invite.txt'), 'utf8') : '';
  console.log(`PASS ${label}: invite ${invite.length} characters, game played to two plies between two processes`);
}

try {
  await scenario('direct');
  await scenario('proxy 60ms+2%', { impair: { delayMs: 30, jitterMs: 6, loss: 0.02, seed: 77 } });
  console.log('PASS: hosted friend play between real processes over localhost UDP (real router/NAT/internet NOT tested)');
} finally {
  rmSync(root, { recursive: true, force: true });
}
