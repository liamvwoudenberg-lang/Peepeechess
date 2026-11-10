import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import dgram from 'node:dgram';
import assert from 'node:assert/strict';
import Ajv2020 from 'ajv/dist/2020.js';
const godot = process.env.GODOT_BIN || 'godot';
const directory = mkdtempSync(join(tmpdir(), 'peepeechess-enet-'));
const diagnostics = /SCRIPT ERROR|Parse Error|^ERROR:|^FAIL:/m;
const envFor = name => {
  const env = { ...process.env };
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
    env[key] = join(directory, name, key); mkdirSync(env[key], { recursive: true });
  }
  return env;
};
const run = (name, args) => {
  const r = spawnSync(godot, ['--headless', '--path', 'godot', ...args], { env: envFor(name), encoding: 'utf8', timeout: 180000 });
  process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
  if (r.error || r.status !== 0 || diagnostics.test((r.stdout || '') + (r.stderr || ''))) throw r.error || Error(`${name} failed: ${r.status}`);
};
const children = [];
function start(name, args) {
  const child = spawn(godot, ['--headless', '--path', 'godot', ...args], { env: envFor(name), stdio: ['ignore', 'pipe', 'pipe'] });
  const timeout = setTimeout(() => child.kill('SIGTERM'), 175000);
  children.push(child);
  let log = '';
  child.stdout.on('data', data => { log += data; });
  child.stderr.on('data', data => { log += data; });
  const done = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', (code, signal) => {
      clearTimeout(timeout);
      if (existsSync(directory)) writeFileSync(join(directory, `${name}.log`), log);
      resolve({ code, signal, log });
    });
  });
  return { child, done, log: () => log };
}
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(test, timeout = 10000) {
  const deadline = Date.now() + timeout;
  while (!test()) {
    if (Date.now() >= deadline) throw Error('Timed out waiting for server/client readiness');
    await pause(30);
  }
}
async function freePort() {
  const socket = dgram.createSocket('udp4');
  await new Promise(resolve => socket.bind(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  socket.close();
  return port;
}
async function proxy(serverPort, initialSeed, enabled) {
  const socket = dgram.createSocket('udp4');
  // Preserve each client UDP endpoint across NAT. Reusing one upstream port
  // for a NEW client socket conflates separate DTLS sessions while ENet still
  // has queued packets for the old one (a Godot 4.6.3 handshake-state error).
  const upstreams = new Map();
  let seed = initialSeed;
  const stats = { received: 0, dropped: 0, forwarded: 0, delayMs: enabled ? 40 : 0, loss: enabled ? 0.10 : 0 };
  const timers = new Set();
  const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 2 ** 32; };
  function forward(data, sender, destination) {
    stats.received++;
    if (random() < stats.loss) { stats.dropped++; return; }
    const timer = setTimeout(() => {
      timers.delete(timer);
      sender.send(data, destination.port, destination.address);
      stats.forwarded++;
    }, stats.delayMs + (enabled ? Math.floor(random() * 20) : 0));
    timers.add(timer);
  }
  socket.on('message', (data, info) => {
    const key = `${info.address}:${info.port}`;
    if (!upstreams.has(key)) {
      const upstream = dgram.createSocket('udp4');
      upstream.on('message', reply => forward(reply, socket, { port: info.port, address: info.address }));
      upstreams.set(key, upstream);
    }
    forward(data, upstreams.get(key), { port: serverPort, address: '127.0.0.1' });
  });
  await new Promise(resolve => socket.bind(0, '127.0.0.1', resolve));
  return { port: socket.address().port, stats, close() { for (const timer of timers) clearTimeout(timer); for (const upstream of upstreams.values()) upstream.close(); socket.close(); } };
}
try {
  const gameSchema = JSON.parse(readFileSync('godot/contracts/v1/schema.json', 'utf8'));
  const networkSchema = JSON.parse(readFileSync('godot/contracts/network/v1/schema.json', 'utf8'));
  const ajv = new Ajv2020({ strict: true, allErrors: true });
  ajv.addSchema(gameSchema); ajv.addSchema(networkSchema);
  for (const fixture of JSON.parse(readFileSync('godot/contracts/network/v1/fixtures.json', 'utf8'))) {
    assert.equal(ajv.validate({ $ref: `${networkSchema.$id}#/$defs/${fixture.type}` }, fixture.payload), fixture.valid, fixture.name);
  }
  run('import', ['--editor', '--import']);
  run('authority', ['--script', 'res://tests/network/network_test.gd']);
  run('roster', ['--script', 'res://tests/network/roster_test.gd']);
  run('online-ui', ['--script', 'res://tests/network/online_ui_test.gd']);
  run('client-scene', ['res://network/client/online_lobby.tscn', '--quit-after', '3']);
  const cert = join(directory, 'localhost.crt');
  const key = join(directory, 'localhost.key');
  const openssl = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1', '-keyout', key, '-out', cert], { encoding: 'utf8' });
  assert.equal(openssl.status, 0, 'test certificate generation');
  const serverPort = await freePort();
  const server = start('server', ['--script', 'res://network/server/server_main.gd', '--', '--bind=127.0.0.1', `--port=${serverPort}`, `--certificate=${cert}`, `--private-key=${key}`, '--run-seconds=180']);
  await waitFor(() => server.log().includes('SERVER_READY') || diagnostics.test(server.log()));
  assert.doesNotMatch(server.log(), diagnostics);
  for (const scenario of ['classic', 'clock', 'battle']) {
    const impaired = scenario === 'battle';
    const proxies = await Promise.all([proxy(serverPort, 173, impaired), proxy(serverPort, 941, impaired)]);
    try {
      const invite = join(directory, `${scenario}-invite.txt`);
      const bots = ['w', 'b'].map((seat, i) => start(`${scenario}-${seat}`, ['--script', 'res://tests/network/bot_client.gd', '--', `--seat=${seat}`, `--scenario=${scenario}`, `--port=${proxies[i].port}`, `--ca=${cert}`, `--invite=${invite}`, `--report=${join(directory, `${scenario}-${seat}.json`)}`]));
      const results = await Promise.all(bots.map(bot => bot.done));
      for (const result of results) {
        assert.equal(result.code, 0, result.log);
        assert.doesNotMatch(result.log, diagnostics, result.log);
      }
      const reports = ['w', 'b'].map(seat => JSON.parse(readFileSync(join(directory, `${scenario}-${seat}.json`), 'utf8')));
      for (const report of reports) {
        assert.equal(report.ok, true);
        assert.deepEqual(report.errors, [], JSON.stringify(report.errors));
        assert.equal(ajv.validate({ $ref: `${gameSchema.$id}#/$defs/MatchState` }, report.final), true, JSON.stringify(ajv.errors));
      }
      assert.deepEqual(reports[0].final.chess, reports[1].final.chess, `${scenario}: synchronized authoritative final chess state`);
      assert.equal(reports[0].final.result, reports[1].final.result);
      for (const [i, report] of reports.entries()) {
        for (const [revision, board] of Object.entries(report.boards)) {
          const other = reports[1 - i].boards[revision];
          if (other) assert.deepEqual(other, board, `${scenario}: clients agree at observed revision ${revision}`);
          else assert.ok(reports[1 - i].reconnected, `${scenario}: only reconnect may skip a reliable intermediate revision`);
          assert.deepEqual(board.history, report.final.chess.history.slice(0, board.ply), `${scenario}: exact committed history prefix at revision ${revision}`);
          assert.equal(board.fen, board.ply ? reports[1 - i].final.chess.history[board.ply - 1].fen : report.final.chess.initialFen, `${scenario}: both clients recover every committed board through complete history`);
        }
      }
      if (scenario === 'classic') {
        assert.equal(reports[0].final.result, '0-1');
        assert.equal(reports[0].final.chess.ply, 4);
        assert.match(reports[0].final.reason, /Checkmate/);
      } else if (scenario === 'clock') {
        assert.equal(reports[0].final.result, '0-1');
        assert.equal(reports[0].final.reason, 'Time expired');
      } else {
        assert.equal(Object.keys(reports[0].battles).length, 4);
        assert.deepEqual(reports[0].battles, reports[1].battles);
        assert.equal(reports[0].reconnected, true);
        assert.equal(reports[1].forgeryRejected, true);
        assert.equal(reports[1].damageRejected, true);
        assert.equal(reports[0].final.chess.ply, 12);
        assert.equal(reports[0].final.reason, 'Resignation');
        assert.ok(Object.values(reports[0].battles).every(result => result.reason === 'knockout'));
        assert.ok(Object.values(reports[0].battles).some(result => result.outcome === 'defender'));
        assert.ok(proxies.every(p => p.stats.dropped > 0));
      }
      console.log(`PASS ENet/DTLS ${scenario}: two independent clients; ${Object.keys(reports[0].boards).length} synchronized revisions; proxies=${JSON.stringify(proxies.map(p => p.stats))}`);
      if (process.env.MULTIPLAYER_REPORT_DIR) {
        mkdirSync(process.env.MULTIPLAYER_REPORT_DIR, { recursive: true });
        for (const [i, seat] of ['w', 'b'].entries()) writeFileSync(join(process.env.MULTIPLAYER_REPORT_DIR, `${scenario}-${seat}.json`), JSON.stringify(reports[i], null, 2));
        writeFileSync(join(process.env.MULTIPLAYER_REPORT_DIR, `${scenario}-network.json`), JSON.stringify(proxies.map(p => p.stats), null, 2));
      }
    } finally { proxies.forEach(p => p.close()); }
  }
  assert.doesNotMatch(server.log(), diagnostics);
  const wrongCert = join(directory, 'wrong.crt');
  const wrongKey = join(directory, 'wrong.key');
  const wrong = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=unrelated', '-keyout', wrongKey, '-out', wrongCert], { encoding: 'utf8' });
  assert.equal(wrong.status, 0);
  const rejected = spawnSync(godot, ['--headless', '--path', 'godot', '--script', 'res://tests/network/tls_probe.gd', '--', `--port=${serverPort}`, `--ca=${wrongCert}`], { env: envFor('untrusted-client'), encoding: 'utf8', timeout: 10000 });
  assert.equal(rejected.status, 0, rejected.stdout + rejected.stderr);
  assert.match(rejected.stdout, /PASS: incorrect CA never authenticated/);
  assert.doesNotMatch(rejected.stdout + rejected.stderr, /SCRIPT ERROR|Parse Error|FAIL:/);
  const errorLines = (rejected.stdout + rejected.stderr).split('\n').filter(line => line.startsWith('ERROR:'));
  assert.ok(errorLines.every(line => line.startsWith('ERROR: TLS handshake error:')), rejected.stdout + rejected.stderr);
  run('trusted-client', ['--script', 'res://tests/network/tls_probe.gd', '--', `--port=${serverPort}`, `--ca=${cert}`, '--expect-valid=true']);
  await pause(100);
  assert.doesNotMatch(server.log(), /SCRIPT ERROR|Parse Error|FAIL:/);
  assert.ok(server.log().split('\n').filter(line => line.startsWith('ERROR:')).every(line => line.startsWith('ERROR: TLS handshake error:')), server.log());
  console.log('PASS ENet/DTLS trust: incorrect CA refused (expected TLS-handshake diagnostic)');
  console.log('PASS: authoritative ENet/DTLS multiplayer; physical Windows/Android crossplay NOT tested');
} catch (error) {
  console.error(`Multiplayer failed. Diagnostic logs retained at ${directory}`);
  for (const child of children) if (child.exitCode === null) child.kill('SIGTERM');
  process.exitCode = 1;
  console.error(error);
} finally {
  for (const child of children) if (child.exitCode === null) child.kill('SIGTERM');
  if (!process.exitCode) rmSync(directory, { recursive: true, force: true });
}
