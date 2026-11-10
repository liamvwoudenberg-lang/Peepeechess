/** Real HTTP account service + dedicated authority + two independent Godot clients.
 * Run from repository root. No client directly writes records, ratings or outcomes.
 */
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import net from 'node:net';
import dgram from 'node:dgram';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';

const godot = process.env.GODOT_BIN || 'godot';
const directory = mkdtempSync(join(tmpdir(), 'peepeechess-application-'));
const diagnostics = /SCRIPT ERROR|Parse Error|^ERROR:|^FAIL:/m;
const children = [];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const envFor = name => {
  const env = { ...process.env };
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
    env[key] = join(directory, name, key); mkdirSync(env[key], { recursive: true });
  }
  return env;
};
function start(name, command, args, extraEnv = {}, timeout = 180000) {
  const child = spawn(command, args, { env: { ...envFor(name), ...extraEnv }, stdio: ['ignore', 'pipe', 'pipe'] });
  children.push(child);
  let log = '';
  child.stdout.on('data', data => { log += data; });
  child.stderr.on('data', data => { log += data; });
  const timer = setTimeout(() => child.kill('SIGTERM'), timeout);
  const done = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', (code, signal) => {
      clearTimeout(timer);
      writeFileSync(join(directory, `${name}.log`), log);
      resolve({ code, signal, log });
    });
  });
  return { child, done, log: () => log };
}
async function stop(process) {
  if (process.child.exitCode === null && process.child.signalCode === null) process.child.kill('SIGTERM');
  return process.done;
}
async function waitFor(test, message, timeout = 10000) {
  const deadline = Date.now() + timeout;
  while (!(await test())) {
    if (Date.now() >= deadline) throw Error(`Timed out: ${message}`);
    await pause(40);
  }
}
async function freePort(protocol) {
  const socket = protocol === 'udp' ? dgram.createSocket('udp4') : net.createServer();
  await new Promise(resolve => protocol === 'udp' ? socket.bind(0, '127.0.0.1', resolve) : socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  return port;
}
let base;
async function api(path, { token, method = 'GET', body, headers = {} } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...headers },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(10000),
  });
  const text = await response.text();
  let decoded;
  try { decoded = JSON.parse(text); } catch { decoded = text; }
  return { status: response.status, body: decoded };
}
async function success(path, options) {
  const response = await api(path, options);
  assert.ok(response.status >= 200 && response.status < 300, `${path}: ${response.status} ${JSON.stringify(response.body)}`);
  assert.equal(response.body.schemaVersion, 1, path);
  return response.body;
}
async function statusFor(account) { return (await success('/v1/status', { token: account.token })).status; }
async function ticketsFor(accounts, allocation) {
  return Promise.all(accounts.map(async account => {
    const response = await success('/v1/tickets', { token: account.token, method: 'POST', body: { matchId: allocation.matchId } });
    assert.equal(response.allocation.matchId, allocation.matchId);
    assert.match(response.ticket, /^[a-f0-9]{64}$/);
    return response;
  }));
}
async function play(accounts, allocation, scenario, label, hooks = {}) {
  const tickets = await ticketsFor(accounts, allocation);
  const reports = [];
  const bots = accounts.map((account, index) => {
    const seat = account.profile.playerId === allocation.whitePlayerId ? 'w' : 'b';
    assert.equal(account.profile.playerId, seat === 'w' ? allocation.whitePlayerId : allocation.blackPlayerId);
    const ticketFile = join(directory, `${label}-${seat}.ticket`);
    writeFileSync(ticketFile, tickets[index].ticket, { mode: 0o600 });
    const report = join(directory, `${label}-${seat}.json`);
    const bot = start(`${label}-${seat}`, godot, ['--headless', '--path', 'godot', '--script', 'res://tests/application_bot.gd', '--',
      `--seat=${seat}`, `--scenario=${scenario}`, `--port=${allocation.endpoint.port}`, '--insecure_local=true',
      `--ticket_file=${ticketFile}`, `--expected_player=${account.profile.playerId}`, `--begin_after=${hooks.afterAuth ? 3000 : 0}`, `--invite=${join(directory, `${label}-unused-invite`)}`, `--report=${report}`]);
    return { ...bot, report };
  });
  if (hooks.afterAuth) {
    await waitFor(() => bots.every(bot => bot.log().includes('ACCOUNT_AUTHENTICATED')), `${label}: both account handshakes`, 15000);
    await hooks.afterAuth();
  }
  const botResults = await Promise.all(bots.map(bot => bot.done));
  if (hooks.afterBots) await hooks.afterBots();
  for (const [index, result] of botResults.entries()) {
    assert.equal(result.code, 0, result.log);
    assert.doesNotMatch(result.log, diagnostics);
    const report = JSON.parse(readFileSync(bots[index].report, 'utf8'));
    assert.equal(report.ok, true, JSON.stringify(report));
    assert.deepEqual(report.errors, []);
    reports.push(report);
  }
  assert.deepEqual(reports[0].final.chess, reports[1].final.chess, 'independent clients receive identical authoritative final chess state');
  for (const key of ['result', 'reason', 'players', 'matchId', 'mode']) assert.deepEqual(reports[0].final[key], reports[1].final[key], `identical final ${key}`);
  assert.equal(reports[0].final.matchId, allocation.matchId);
  assert.equal(reports[0].final.chess.ply, scenario === 'battle' ? 12 : 4);
  if (scenario === 'battle') {
    assert.equal(reports[0].reconnected || reports[1].reconnected, true);
    assert.deepEqual(reports[0].battles, reports[1].battles);
    assert.equal(Object.keys(reports[0].battles).length, 4);
    assert.ok(Object.values(reports[0].battles).some(result => result.outcome === 'attacker'));
    assert.ok(Object.values(reports[0].battles).some(result => result.outcome === 'defender'));
    assert.ok(reports.some(report => report.forgeryRejected));
    assert.ok(reports.some(report => report.damageRejected));
  }
  let record;
  await waitFor(async () => {
    const history = await success('/v1/history?limit=100', { token: accounts[0].token });
    record = history.matches.find(match => match.matchId === allocation.matchId);
    return !!record;
  }, `${label}: dedicated result persisted`, 15000);
  assert.equal(record.result, 'black');
  assert.equal(record.ranked, allocation.ranked);
  assert.equal(record.finalFen, reports[0].final.chess.fen);
  assert.deepEqual(record.history, reports[0].final.chess.history);
  const otherHistory = await success('/v1/history?limit=100', { token: accounts[1].token });
  assert.deepEqual(record, otherHistory.matches.find(match => match.matchId === allocation.matchId));
  console.log(`PASS application ${label}: ${scenario}, ${reports[0].final.chess.ply} plies, ${Object.keys(reports[0].battles).length} real battles, synchronized final board, persisted result`);
  if (process.env.APPLICATION_REPORT_DIR) {
    mkdirSync(process.env.APPLICATION_REPORT_DIR, { recursive: true });
    writeFileSync(join(process.env.APPLICATION_REPORT_DIR, `${label}.json`), JSON.stringify({ allocation, reports, record }, null, 2));
  }
  return record;
}
async function holdMatch(accounts, allocation) {
  const tickets = await ticketsFor(accounts, allocation);
  const bots = accounts.map((account, index) => {
    const seat = account.profile.playerId === allocation.whitePlayerId ? 'w' : 'b';
    const ticketFile = join(directory, `interrupted-${seat}.ticket`);
    writeFileSync(ticketFile, tickets[index].ticket, { mode: 0o600 });
    return start(`interrupted-${seat}`, godot, ['--headless', '--path', 'godot', '--script', 'res://tests/application_bot.gd', '--',
      `--seat=${seat}`, '--scenario=clock', `--port=${allocation.endpoint.port}`, '--insecure_local=true',
      `--ticket_file=${ticketFile}`, `--expected_player=${account.profile.playerId}`, `--invite=${join(directory, 'interrupted-invite')}`, `--report=${join(directory, `interrupted-${seat}.json`)}`]);
  });
  await waitFor(() => bots.every(bot => bot.log().includes('ACCOUNT_AUTHENTICATED')), 'interrupted match authenticated', 15000);
  return bots;
}
async function quick(accounts, mode, ranked) {
  const body = { mode, ranked, initialMs: mode === 'battle' ? 0 : 60000, incrementMs: 0 };
  await success('/v1/queue', { token: accounts[0].token, method: 'POST', body });
  await success('/v1/queue', { token: accounts[1].token, method: 'POST', body });
  const statuses = await Promise.all(accounts.map(statusFor));
  assert.ok(statuses[0].allocation && statuses[1].allocation);
  assert.deepEqual(statuses[0].allocation, statuses[1].allocation);
  assert.equal(statuses[0].allocation.mode, mode);
  assert.equal(statuses[0].allocation.ranked, ranked);
  return statuses[0].allocation;
}
try {
  const imported = await start('import', godot, ['--headless', '--path', 'godot', '--editor', '--import']).done;
  assert.equal(imported.code, 0, imported.log);
  assert.doesNotMatch(imported.log, diagnostics);
  const apiPort = await freePort('tcp');
  const gamePort = await freePort('udp');
  base = `http://127.0.0.1:${apiPort}`;
  const secret = randomBytes(32).toString('hex');
  const backendEnv = { NATIVE_API_BIND: '127.0.0.1', NATIVE_API_PORT: String(apiPort), NATIVE_DATABASE_PATH: join(directory, 'application.sqlite'), NATIVE_SERVER_ID: 'local-1', NATIVE_SERVER_SECRET: secret, NATIVE_GAME_HOST: '127.0.0.1', NATIVE_GAME_PORT: String(gamePort), NATIVE_GAME_INSECURE_LOCAL: '1' };
  delete backendEnv.DATABASE_URL;
  const startBackend = name => start(name, process.execPath, ['--import', 'tsx', 'server/native/main.ts'], { ...backendEnv, DATABASE_URL: '' }, 360000);
  const ready = async () => waitFor(async () => { try { return (await api('/health')).body.ok === true; } catch { return false; } }, 'backend health', 20000);
  let backend = startBackend('backend');
  await ready();
  const startDedicated = name => start(name, godot, ['--headless', '--path', 'godot', '--script', 'res://network/server/server_main.gd', '--', '--bind=127.0.0.1', `--port=${gamePort}`, '--insecure-local', `--backend-url=${base}`, '--backend-insecure-local', '--server-id=local-1', `--outbox-dir=${join(directory, 'outbox')}`, '--run-seconds=360'], { PEEPEECHESS_BACKEND_SECRET: secret }, 360000);
  let server = startDedicated('dedicated');
  const serverReady = async () => {
    await waitFor(() => server.log().includes('SERVER_READY') || diagnostics.test(server.log()), 'dedicated ready');
    assert.doesNotMatch(server.log(), diagnostics);
  };
  await serverReady();
  const outbox = () => readdirSync(join(directory, 'outbox')).filter(name => name.endsWith('.json')).map(name => JSON.parse(readFileSync(join(directory, 'outbox', name), 'utf8')));
  assert.equal((await api('/v1/me')).status, 401);
  const credentials = ['alice', 'bob'].map(username => ({ username, password: `Test-only-${randomBytes(16).toString('hex')}`, displayName: username === 'alice' ? 'Alice Native' : 'Bob Native' }));
  const accounts = await Promise.all(credentials.map(body => success('/v1/auth/register', { method: 'POST', body })));
  const login = await success('/v1/auth/login', { method: 'POST', body: { username: credentials[0].username, password: credentials[0].password } });
  assert.equal(login.profile.playerId, accounts[0].profile.playerId, 'account identity survives independent login');
  assert.equal((await api('/v1/auth/login', { method: 'POST', body: { username: credentials[0].username, password: 'Wrong-password-123' } })).status, 401);
  assert.notEqual(accounts[0].profile.playerId, accounts[1].profile.playerId);
  assert.ok([401, 403].includes((await api('/internal/results', { token: accounts[0].token, method: 'POST', body: {} })).status), 'client cannot report results');
  const ratingWrite = await api('/v1/me', { token: accounts[0].token, method: 'PATCH', body: { classic: { rating: 99999 } } });
  assert.ok(ratingWrite.status >= 400, 'client has no rating mutation endpoint');
  const records = [];
  records.push(await play(accounts, await quick(accounts, 'classic', true), 'classic', 'ranked-classic'));
  const privateInvite = await success('/v1/private', { token: accounts[0].token, method: 'POST', body: { mode: 'classic', initialMs: 60000, incrementMs: 0 } });
  assert.match(privateInvite.status.invite.code, /^[A-Z2-9]{6}$/);
  const joined = await success('/v1/private/join', { token: accounts[1].token, method: 'POST', body: { code: privateInvite.status.invite.code } });
  assert.equal(joined.status.allocation.whitePlayerId, accounts[0].profile.playerId);
  assert.equal(joined.status.allocation.ranked, false);
  records.push(await play(accounts, joined.status.allocation, 'classic', 'private-classic', {
    afterAuth: async () => { await stop(backend); },
    afterBots: async () => {
      await waitFor(() => outbox().some(job => job.report.matchId === joined.status.allocation.matchId && !job.active && job.report.result === 'black'), 'terminal result durably written while backend offline');
      assert.doesNotMatch(server.log(), diagnostics);
      await stop(server);
      backend = startBackend('backend-outbox-reopened');
      await ready();
      server = startDedicated('dedicated-outbox-reopened');
      await serverReady();
    },
  }));
  console.log('PASS application outage: completed offline result survives dedicated restart and delivers once');
  records.push(await play(accounts, await quick(accounts, 'battle', true), 'battle', 'ranked-battle'));
  assert.doesNotMatch(server.log(), diagnostics);
  const profiles = await Promise.all(accounts.map(account => success('/v1/me', { token: account.token })));
  for (const [index, response] of profiles.entries()) {
    const profile = response.profile;
    assert.equal(profile.classic.games, 2);
    assert.equal(profile.battle.games, 1);
    const classicRanked = records[0];
    const classicWinner = classicRanked.blackPlayerId === profile.playerId;
    assert.equal(profile.classic.rating, classicWinner ? 1216 : 1184, 'private result never changes competitive rating');
    assert.equal(profile.battle.rating, records[2].blackPlayerId === profile.playerId ? 1216 : 1184);
    const history = await success('/v1/history?limit=100', { token: accounts[index].token });
    assert.equal(history.matches.length, 3);
  }
  const interrupted = await quick(accounts, 'classic', false);
  const interruptedBots = await holdMatch(accounts, interrupted);
  await waitFor(() => outbox().some(job => job.report.matchId === interrupted.matchId && job.active), 'active allocation durably journaled');
  assert.doesNotMatch(server.log(), diagnostics);
  await Promise.all([stop(server), ...interruptedBots.map(stop)]);
  server = startDedicated('dedicated-active-reopened');
  await serverReady();
  let aborted;
  await waitFor(async () => {
    aborted = (await success('/v1/history?limit=100', { token: accounts[0].token })).matches.find(match => match.matchId === interrupted.matchId);
    return !!aborted;
  }, 'active match restart recorded as aborted', 15000);
  assert.equal(aborted.result, 'aborted');
  assert.deepEqual(aborted.ratingChange, { white: 0, black: 0 });
  for (const [index, account] of accounts.entries()) assert.deepEqual((await success('/v1/me', { token: account.token })).profile, profiles[index].profile, 'infrastructure abort changes neither statistics nor ratings');
  console.log('PASS application active restart: interrupted match aborts explicitly without rating or statistics');
  await stop(backend);
  backend = startBackend('backend-reopened');
  await ready();
  for (const [index, account] of accounts.entries()) {
    assert.deepEqual((await success('/v1/me', { token: account.token })).profile, profiles[index].profile, 'SQLite reopen preserves account session and mode-specific stats');
    assert.equal((await success('/v1/history?limit=100', { token: account.token })).matches.length, 4);
  }
  const leaders = await success('/v1/leaderboard?mode=classic&limit=20', { token: accounts[0].token });
  assert.ok(leaders.players[0].classic.rating >= leaders.players[1].classic.rating);
  console.log('PASS application persistence: ratings, accounts, bearer sessions, history and leaderboard survive backend restart');
  console.log('PASS application integration: no physical Windows or Android device testing implied');
} catch (error) {
  console.error(`Application integration failed. Logs retained at ${directory}`);
  console.error(error);
  process.exitCode = 1;
} finally {
  for (const child of children) if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
  await Promise.allSettled(children.map(child => new Promise(resolve => child.exitCode !== null || child.signalCode !== null ? resolve() : child.once('exit', resolve))));
  if (!process.exitCode) rmSync(directory, { recursive: true, force: true });
}
