// End-to-end online combat: a REAL dedicated server (ENet/DTLS), TWO real client processes (OnlineChessClient +
// OnlineCombatView + CombatArena in its prediction/reconciliation mode), every client behind a UDP latency/loss proxy.
// Complete battles are played for several role pairs; both clients must converge to the server's result.
//
//   node scripts/test-online-combat.mjs                 quick profile (6 fights, ~3-4 min)
//   node scripts/test-online-combat.mjs --profile=full  every role pair x {0, 60, 120} ms RTT (+2% loss when impaired) + special scenarios
//   ONLINE_COMBAT_PARALLEL=3 (default)  concurrent fights;  MULTIPLAYER_REPORT_DIR=dir  also writes the measured numbers as JSON
//
// HONESTY: loopback sockets through a userspace proxy are not the internet; no real device, mobile network, NAT, or Windows/Android
// crossplay is involved. Timing numbers come from a shared, possibly loaded machine. Thresholds are deliberately loose
// (convergence, no snaps, bounded error) and the measured values are printed.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import { startProxy, freeUdpPort } from './lib/latency-proxy.mjs';

const godot = process.env.GODOT_BIN || 'godot';
const profile = (process.argv.find(a => a.startsWith('--profile=')) || '--profile=quick').split('=')[1];
const parallel = Number(process.env.ONLINE_COMBAT_PARALLEL || 3);
const directory = mkdtempSync(join(tmpdir(), 'peepeechess-online-combat-'));
const diagnostics = /SCRIPT ERROR|Parse Error|^ERROR:|^FAIL:/m;
const envFor = name => {
  const env = { ...process.env };
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) { env[key] = join(directory, name, key); mkdirSync(env[key], { recursive: true }); }
  return env;
};
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const children = new Set();
function start(name, args, timeoutMs) {
  const child = spawn(godot, ['--headless', '--path', 'godot', ...args], { env: envFor(name), stdio: ['ignore', 'pipe', 'pipe'] });
  children.add(child);
  const timeout = setTimeout(() => child.kill('SIGTERM'), timeoutMs);
  let log = '';
  child.stdout.on('data', d => { log += d; });
  child.stderr.on('data', d => { log += d; });
  const done = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', (code, signal) => { clearTimeout(timeout); children.delete(child); resolve({ code, signal, log }); });
  });
  return { child, done, log: () => log };
}
async function waitFor(test, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (!test()) { if (Date.now() >= deadline) throw Error('Timed out waiting for readiness'); await pause(30); }
}
const mean = a => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
const pct = (a, f) => { if (!a.length) return 0; const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(s.length * f))]; };
const r = (x, d = 4) => Number(Number(x).toFixed(d));

// ---- scenarios ----------------------------------------------------------------------------------------------------------
const LATENCIES = [
  { name: '0ms', rtt: 0, loss: 0, jitter: 0 },
  { name: '60ms+2%', rtt: 60, loss: 0.02, jitter: 8 },
  { name: '120ms+2%', rtt: 120, loss: 0.02, jitter: 16 },
];
const PAIRS = ['p-p', 'n-p', 'b-p', 'r-p', 'q-p', 'p-n', 'n-q', 'b-n', 'p-p-black'];
const fights = [];
if (profile === 'full') {
  for (const line of PAIRS) for (const net of LATENCIES) fights.push({ id: `${line}@${net.name}`, line, mode: 'fight', net });
  fights.push({ id: 'reconnect:n-p@60ms+2%', line: 'n-p', mode: 'reconnect', net: LATENCIES[1], cooldown: 3, blackout: true });
  fights.push({ id: 'parry:p-p@60ms+2%', line: 'p-p', mode: 'parry', net: LATENCIES[1] });
  fights.push({ id: 'parry:n-p@120ms+2%', line: 'n-p', mode: 'parry', net: LATENCIES[2] });
  fights.push({ id: 'invalid:b-n@60ms+2%', line: 'b-n', mode: 'invalid', net: LATENCIES[1], cooldown: 5 });
} else {
  fights.push({ id: 'p-p@0ms', line: 'p-p', mode: 'fight', net: LATENCIES[0] });
  fights.push({ id: 'n-p@60ms+2%', line: 'n-p', mode: 'fight', net: LATENCIES[1] });
  fights.push({ id: 'q-p@120ms+2%', line: 'q-p', mode: 'fight', net: LATENCIES[2] });
  fights.push({ id: 'reconnect:p-p@60ms+2%', line: 'p-p', mode: 'reconnect', net: LATENCIES[1], cooldown: 3, blackout: true });
  fights.push({ id: 'parry:p-p@60ms+2%', line: 'p-p', mode: 'parry', net: LATENCIES[1] });
  fights.push({ id: 'invalid:b-n@60ms+2%', line: 'b-n', mode: 'invalid', net: LATENCIES[1], cooldown: 5 });
}

const only = (process.argv.find(a => a.startsWith('--only=')) || '').split('=')[1];
if (only) for (let i = fights.length - 1; i >= 0; i--) if (!fights[i].id.includes(only)) fights.splice(i, 1);

const cert = join(directory, 'localhost.crt');
const key = join(directory, 'localhost.key');

async function runFight(fight, index) {
  const name = `f${index}`;
  const port = await freeUdpPort();
  const server = start(`${name}-server`, ['--script', 'res://network/server/server_main.gd', '--', '--bind=127.0.0.1', `--port=${port}`, `--certificate=${cert}`, `--private-key=${key}`, '--run-seconds=170'], 175000);
  await waitFor(() => server.log().includes('SERVER_READY') || diagnostics.test(server.log()));
  const ready = server.log().match(/tuning=(balance-v1:[0-9a-f]+)/);
  assert.ok(ready, `${fight.id}: server announces its tuning stamp`);
  const { rtt, loss, jitter } = fight.net;
  const mk = seed => startProxy(port, { delayMs: Math.max(0, rtt / 2 - jitter / 2), jitterMs: jitter, loss, seed });
  const proxies = [await mk(173 + index), await mk(941 + index)];
  const invite = join(directory, `${name}-invite.txt`);
  const reportFile = seat => join(directory, `${name}-${seat}.json`);
  const bots = ['w', 'b'].map((seat, i) => start(`${name}-${seat}`, ['--script', 'res://tests/network/combat_bot.gd', '--', `--seat=${seat}`, `--port=${proxies[i].port}`, `--ca=${cert}`, `--invite=${invite}`, `--report=${reportFile(seat)}`, `--line=${fight.line}`, `--mode=${fight.mode}`, `--seed=${index + 1}`, `--cooldown_scale=${fight.cooldown || 1}`], 170000));
  let blackoutDone = null;
  if (fight.blackout) {
    // black loses its link for 4 s (longer than the 3 s liveness limit) ~10 s into the duel
    blackoutDone = (async () => {
      await waitFor(() => server.log().includes('COMBAT_BATTLE_START'), 120000);
      await pause(10000);
      await proxies[1].blackout(4000);
    })().catch(() => {});
  }
  const results = await Promise.all(bots.map(b => b.done));
  if (blackoutDone) await blackoutDone;
  await pause(300);
  proxies.forEach(p => p.close());
  server.child.kill('SIGTERM');
  const serverExit = await server.done;
  const serverLog = server.log();
  writeFileSync(join(directory, `${name}-server.log`), serverLog);
  results.forEach((x, i) => writeFileSync(join(directory, `${name}-bot${i}.log`), x.log));
  const row = { id: fight.id, line: fight.line, mode: fight.mode, rttMs: rtt, loss, tuning: ready[1] };
  for (const [i, result] of results.entries()) {
    assert.equal(result.code, 0, `${fight.id}: bot ${i} exit\n${result.log}`);
    assert.doesNotMatch(result.log, diagnostics, `${fight.id}: bot ${i} diagnostics\n${result.log}`);
  }
  assert.doesNotMatch(serverLog, diagnostics, `${fight.id}: server diagnostics\n${serverLog}`);
  const reports = ['w', 'b'].map(seat => JSON.parse(readFileSync(reportFile(seat), 'utf8')));
  const doneLines = [...serverLog.matchAll(/^COMBAT_BATTLE_DONE (.*)$/gm)].map(m => JSON.parse(m[1]));
  const abortLines = [...serverLog.matchAll(/^COMBAT_BATTLE_ABORT (.*)$/gm)].map(m => JSON.parse(m[1]));
  assert.equal(abortLines.length, 0, `${fight.id}: no battle aborted: ${JSON.stringify(abortLines)}`);
  assert.equal(doneLines.length, 1, `${fight.id}: exactly one battle finished on the server`);
  const server_ = doneLines[0];
  assert.equal(server_.tuning, ready[1], 'tuning stamp is stable within the process');
  for (const report of reports) {
    assert.equal(report.ok, true, `${fight.id}: ${report.message}`);
    if (!(fight.mode === 'invalid' && report.seat === 'b')) assert.deepEqual(report.errors, [], `${fight.id} ${report.seat}: ${JSON.stringify(report.errors)}`);
    assert.deepEqual(report.battles[server_.battleId], server_.result, `${fight.id} ${report.seat}: client converged to the server's BattleResult`);
    assert.equal(report.final.reason, 'Resignation', `${fight.id}: match ended by the scripted resignation after the duel`);
  }
  assert.deepEqual(reports[0].final.chess, reports[1].final.chess, `${fight.id}: identical final chess state`);
  // both clients saw the same server events (events are repeated in snapshots; compare what both saw)
  const byId = rep => new Map(rep.events.map(e => [e.id, e]));
  const [ew, eb] = reports.map(byId);
  let common = 0;
  for (const [id, e] of ew) if (eb.has(id)) { common++; assert.deepEqual(eb.get(id), e, `${fight.id}: event ${id} identical at both clients`); }
  const union = new Set([...ew.keys(), ...eb.keys()]).size;
  // A scenario that black-holes one client's link for 4 s (fight.blackout) legitimately costs that client the events of that window (a
  // reconnect gets a fresh snapshot, which only repeats the most recent events): measured 2026-11-13 on the unmodified tree, this ratio
  // failed 4 runs in 10 (6/10 .. 8/10 common). Every event both clients did see must still be identical (asserted above); the ratio
  // only means something when nobody was cut off.
  if (!fight.blackout) assert.ok(union === 0 || common / union >= 0.9, `${fight.id}: clients saw ${common}/${union} common events`);
  // measurements
  const stats = reports.map(rep => rep.battleStats[server_.battleId]);
  for (const s of stats) assert.ok(s, `${fight.id}: client battle stats present`);
  row.result = `${server_.result.outcome}/${server_.result.reason} atkHp=${server_.result.attackerHp} defHp=${server_.result.defenderHp} tick=${server_.result.resolvedTick}`;
  row.corrections = stats.map(s => s.corrections.n);
  row.errMean = stats.map(s => r(s.corrections.mean));
  row.errP95 = stats.map(s => r(s.corrections.p95));
  row.errMax = stats.map(s => r(s.corrections.max));
  row.hardSnaps = stats.map(s => s.stats.hard_snaps);
  row.catchups = stats.map(s => `${s.catchups.n}/${r(s.catchups.max, 3)}m`);
  row.clientSent = stats.map(s => s.stats.sent);
  row.rejectedSnapshots = stats.map(s => s.stats.rejected);
  row.visualMs = reports.map(rep => r(pct(rep.pressVisualMs, 0.5), 1));
  row.confirmMs = reports.map(rep => r(pct(rep.pressConfirmMs, 0.5), 1));
  row.pressesProbed = reports.map(rep => rep.pressVisualMs.length);
  const seats = Object.values(server_.net.seats);
  row.serverRttMs = seats.map(s => `${s.rtt_ms_mean}/${s.rtt_ms_max}`);
  row.starvedRatio = seats.map(s => s.starved_ratio);
  row.maxGapTicks = seats.map(s => s.max_gap_ticks);
  row.serverAccepted = seats.map(s => s.accepted);
  row.serverStale = seats.map(s => s.stale);
  row.hostCounters = server_.net.counters;
  row.proxy = proxies.map(p => ({ received: p.stats.received, dropped: p.stats.dropped, blackedOut: p.stats.blackedOut }));
  row.reconnected = reports.map(rep => rep.reconnected);
  row.events = [ew.size, eb.size, common];
  row.protocolCodes = reports.map(rep => rep.protocolCodes);
  // --- thresholds (loose; the numbers above are the evidence)
  // Real-time melee (strafing, contact, 1:1 input assumption broken by tick-phase jitter and loss) is looser than the lockstep suites;
  // the hard-snap threshold is 1.5 m, so 1.2 m worst correction still means "never teleported".
  const limit = 1.2;
  // A seat the server stopped hearing from for >= 15 ticks (INPUT_NEUTRAL_AFTER_TICKS: link blackout, or this shared machine stalling a
  // process) is neutralised by the server while the client keeps predicting, so a large correction / hard snap is then CORRECT behaviour.
  const stalled = seats.some(s => s.max_gap_ticks >= 15);
  row.stalledSeat = stalled;
  for (const s of stats) {
    assert.ok(s.stats.hard_snaps <= (stalled ? 4 : 0), `${fight.id}: hard snaps ${s.stats.hard_snaps} (stalled=${stalled})`);
    assert.equal(s.stats.rejected, 0, `${fight.id}: no snapshot rejected by the client`);
    assert.ok(s.corrections.mean < (stalled ? 0.4 : 0.15), `${fight.id}: mean prediction error ${s.corrections.mean}`);
    assert.ok(s.corrections.max < (stalled ? 7 : limit), `${fight.id}: worst correction ${s.corrections.max}`);
  }
  for (const [i, rep] of reports.entries()) {
    if (rep.pressVisualMs.length >= 3) assert.ok(pct(rep.pressVisualMs, 0.5) < 60, `${fight.id}: predicted press visible within ~3 frames (median ${pct(rep.pressVisualMs, 0.5)} ms)`);
  }
  if (fight.mode === 'fight' || fight.mode === 'parry') {
    // On an otherwise healthy link, loss costs only responsiveness: starved ticks are bounded.
    for (const s of seats) assert.ok(s.starved_ratio < 0.9, `${fight.id}: starved ratio ${s.starved_ratio}`);
  }
  if (rtt > 0 && fight.mode !== 'reconnect') for (const s of seats) assert.ok(s.rtt_ms_mean >= rtt * 0.5 && s.rtt_ms_mean < rtt * 3 + 150, `${fight.id}: server RTT feed ${s.rtt_ms_mean} ms vs configured ${rtt}`);
  if (fight.mode === 'reconnect') {
    assert.ok(reports[0].reconnected && reports[1].reconnected, `${fight.id}: both clients reconnected mid-fight`);
    assert.equal(server_.net.counters.invalid, 0, `${fight.id}: no counter regression after reconnect`);
    assert.equal(server_.net.counters.forbidden, 0, `${fight.id}: no forbidden input after resume`);
  }
  if (fight.mode === 'invalid') {
    const c = server_.net.counters;
    assert.ok(c.stale >= 1, `${fight.id}: replay rejected as stale (${c.stale})`);
    assert.ok(c.forbidden >= 1, `${fight.id}: other-battle packet forbidden by the combat host (${c.forbidden}); the seat spoof is refused earlier by the session`);
    assert.ok(c.invalid >= 1, `${fight.id}: counter regression refused (${c.invalid})`);
    const codes = reports[1].protocolCodes;
    assert.ok((codes.INVALID_PAYLOAD || 0) >= 3, `${fight.id}: schema/channel violations rejected (${JSON.stringify(codes)})`);
    assert.ok((codes.FORBIDDEN || 0) >= 1, `${fight.id}: forged result rejected (${JSON.stringify(codes)})`);
  }
  return row;
}

async function pool(items, size, worker) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: size }, async () => {
    while (next < items.length) { const i = next++; results[i] = await worker(items[i], i); console.log(`PASS ${items[i].id} :: ${results[i].result}`); }
  }));
  return results;
}

let failed = false;
try {
  const imported = spawnSync(godot, ['--headless', '--path', 'godot', '--editor', '--import'], { env: envFor('import'), encoding: 'utf8', timeout: 180000 });
  assert.equal(imported.status, 0, 'godot import');
  const openssl = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1', '-keyout', key, '-out', cert], { encoding: 'utf8' });
  assert.equal(openssl.status, 0, 'test certificate generation');
  const rows = await pool(fights, parallel, runFight);
  console.log('\nONLINE_COMBAT_REPORT ' + JSON.stringify(rows));
  for (const row of rows) console.log(`  ${row.id.padEnd(26)} err(mean/p95/max m) w=${row.errMean[0]}/${row.errP95[0]}/${row.errMax[0]} b=${row.errMean[1]}/${row.errP95[1]}/${row.errMax[1]} corr=${row.corrections} snaps=${row.hardSnaps} visual=${row.visualMs}ms confirm=${row.confirmMs}ms serverRTT=${row.serverRttMs} starved=${row.starvedRatio} accepted=${row.serverAccepted} stale=${row.serverStale}`);
  if (process.env.MULTIPLAYER_REPORT_DIR) { mkdirSync(process.env.MULTIPLAYER_REPORT_DIR, { recursive: true }); writeFileSync(join(process.env.MULTIPLAYER_REPORT_DIR, `online-combat-${profile}.json`), JSON.stringify(rows, null, 2)); }
  console.log(`PASS: online combat (${profile}) ${rows.length} fights through a loopback latency/loss proxy; real devices, real networks and Windows/Android crossplay NOT tested`);
} catch (error) {
  failed = true;
  console.error(`Online combat failed. Diagnostic logs retained at ${directory}`);
  console.error(error);
  process.exitCode = 1;
} finally {
  for (const child of children) child.kill('SIGTERM');
  if (!failed) rmSync(directory, { recursive: true, force: true });
}
