import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createNativeBackend } from "../server/native/http.js";
import { FRIEND_LIMIT, ONLINE_MS, PENDING_REQUEST_LIMIT, PENDING_REQUEST_MS } from "../server/native/service.js";
const secret = "test-dedicated-secret-32-characters-minimum";
const endpoint = { host: "127.0.0.1", port: 2456, serverName: "localhost", caCertificate: "", insecureLocal: true };
const baseOptions = { serverId: "local-1", serverSecret: secret, endpoint };
const control = { mode: "classic", ranked: true, initialMs: 600000, incrementMs: 0 };
const admin = { authorization: "Bearer " + secret, "x-server-id": "local-1" };
const fen = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3";
async function harness(filename = ":memory:", now = Date.now, reset = true) {
  const backend = await createNativeBackend({ ...baseOptions, filename, databaseUrl: process.env.NATIVE_TEST_DATABASE_URL, now });
  if (process.env.NATIVE_TEST_DATABASE_URL && reset) await backend.storage.transaction(async tx => { for (const table of ["native_challenges", "native_friendships", "native_presence", "native_tickets", "native_invites", "native_queue", "native_matches", "native_sessions", "native_stats", "native_accounts"]) await tx.run(`DELETE FROM ${table}`); });
  await new Promise<void>(resolve => backend.server.listen(0, "127.0.0.1", resolve));
  const address = backend.server.address() as any, url = `http://127.0.0.1:${address.port}`;
  async function request(method: string, path: string, body?: unknown, token?: string, headers = {}) {
    const response = await fetch(url + path, { method, headers: { ...(body === undefined ? {} : { "content-type": "application/json" }), ...(token ? { authorization: "Bearer " + token } : {}), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
    const data = await response.json() as any; assert.equal(data.schemaVersion, 1); return { status: response.status, data };
  }
  async function register(name: string) { const result = await request("POST", "/v1/auth/register", { username: name, displayName: "Player " + name, password: "correct-horse-battery" }); assert.equal(result.status, 200); return result.data; }
  return { ...backend, request, register, url };
}

test("native accounts: server IDs, salted hashes, sessions, logout and strict admission", async () => {
  const h = await harness(); try {
    const a = await h.register("alice"); assert.match(a.profile.playerId, /^[0-9a-f-]{36}$/); assert.equal(a.profile.classic.rating, 1200); assert.equal(a.profile.battle.games, 0);
    assert.equal((await h.request("GET", "/v1/me")).status, 401);
    assert.equal((await h.request("GET", "/v1/me", undefined, undefined, { authorization: a.token })).status, 401);
    assert.equal((await h.request("POST", "/v1/auth/register", { username: "alice", displayName: "Hacker", password: "correct-horse-battery" })).status, 409);
    assert.equal((await h.request("POST", "/v1/auth/login", { username: "alice", password: "wrong-password" })).status, 401);
    const login = await h.request("POST", "/v1/auth/login", { username: "ALICE", password: "correct-horse-battery" }); assert.equal(login.data.profile.playerId, a.profile.playerId);
    assert.equal((await h.request("POST", "/v1/auth/register", { username: "hacker", password: "correct-horse-battery", displayName: "Hacker", rating: 9999 })).status, 400);
    assert.equal((await h.request("POST", "/v1/me", { rating: 9999 }, a.token)).status, 404);
    const rows = await h.storage.transaction(async tx => ({ account: await tx.get("SELECT * FROM native_accounts WHERE player_id=$1", a.profile.playerId), sessions: await tx.all("SELECT * FROM native_sessions") }));
    assert.ok(!JSON.stringify(rows).includes("correct-horse")); assert.ok(!JSON.stringify(rows).includes(a.token)); assert.match(rows.account.password_hash, /^[a-f0-9]{32}:[a-f0-9]{128}$/);
    assert.equal((await h.request("POST", "/v1/auth/logout", {}, a.token)).status, 200); assert.equal((await h.request("GET", "/v1/me", undefined, a.token)).status, 401);
    assert.equal((await h.request("GET", "/v1/me", undefined, login.data.token)).status, 200);
  } finally { await h.close(); }
});

test("native matchmaking: buckets, FIFO, one room per player, tickets and result authority", async () => {
  const h = await harness(); try {
    const a = await h.register("alice"), b = await h.register("bravo"), c = await h.register("charlie");
    await h.request("POST", "/v1/queue", control, a.token);
    const rankedBattle = await h.request("POST", "/v1/queue", { mode: "battle", ranked: true, initialMs: 0, incrementMs: 0 }, c.token); assert.equal(rankedBattle.data.status.allocation, null);
    const paired = await h.request("POST", "/v1/queue", control, b.token); const allocation = paired.data.status.allocation; assert.ok(allocation);
    assert.equal((await h.request("GET", "/v1/status", undefined, a.token)).data.status.allocation.matchId, allocation.matchId);
    assert.equal((await h.request("POST", "/v1/queue", control, a.token)).status, 409);
    assert.equal((await h.request("POST", "/v1/tickets", { matchId: allocation.matchId }, c.token)).status, 403);
    const ticket = await h.request("POST", "/v1/tickets", { matchId: allocation.matchId }, a.token); assert.equal(ticket.status, 200);
    assert.equal((await h.request("POST", "/internal/tickets/redeem", { ticket: ticket.data.ticket }, a.token)).status, 401);
    const redeemed = await h.request("POST", "/internal/tickets/redeem", { ticket: ticket.data.ticket }, undefined, admin); assert.equal(redeemed.data.playerId, a.profile.playerId);
    assert.equal((await h.request("POST", "/internal/tickets/redeem", { ticket: ticket.data.ticket }, undefined, admin)).status, 401);
    const report = { matchId: allocation.matchId, result: "black", reason: "checkmate", finalFen: fen, history: [{ from: "f2", to: "f3" }] };
    assert.equal((await h.request("POST", "/internal/results", report, a.token)).status, 401);
    assert.equal((await h.request("POST", "/internal/results", report, undefined, { ...admin, "x-server-id": "other" })).status, 401);
    const reports = await Promise.all([h.request("POST", "/internal/results", report, undefined, admin), h.request("POST", "/internal/results", report, undefined, admin)]);
    assert.deepEqual(reports.map(r => r.status), [200, 200]); assert.deepEqual(reports.map(r => r.data.duplicate).sort(), [false, true]);
    assert.equal((await h.request("POST", "/internal/results", { ...report, result: "white" }, undefined, admin)).status, 409);
    const winnerToken = allocation.blackPlayerId === a.profile.playerId ? a.token : b.token;
    const loserToken = winnerToken === a.token ? b.token : a.token;
    const winner = (await h.request("GET", "/v1/me", undefined, winnerToken)).data.profile; const loser = (await h.request("GET", "/v1/me", undefined, loserToken)).data.profile;
    assert.equal(winner.classic.rating, 1216); assert.equal(loser.classic.rating, 1184); assert.equal(winner.classic.wins, 1); assert.equal(loser.classic.losses, 1); assert.equal(winner.battle.games, 0);
    const history = await h.request("GET", "/v1/history", undefined, a.token); assert.equal(history.data.matches.length, 1); assert.deepEqual(history.data.matches[0].history, report.history);
    const leaders = await h.request("GET", "/v1/leaderboard?mode=classic", undefined, a.token); assert.equal(leaders.data.players[0].playerId, allocation.blackPlayerId);
    assert.equal((await h.request("GET", "/v1/status", undefined, a.token)).data.status.allocation, null);
  } finally { await h.close(); }
});

test("native private invites: unranked Battle stats, draw, expiry and cancellation", async () => {
  let now = 1800000000000; const h = await harness(":memory:", () => now); try {
    const a = await h.register("alice"), b = await h.register("bravo");
    const created = await h.request("POST", "/v1/private", { mode: "battle", initialMs: 0, incrementMs: 0 }, a.token); const code = created.data.status.invite.code; assert.match(code, /^[A-HJ-NP-Z2-9]{6}$/);
    assert.equal((await h.request("POST", "/v1/private/join", { code }, a.token)).status, 404);
    const joined = await h.request("POST", "/v1/private/join", { code }, b.token); const allocation = joined.data.status.allocation; assert.equal(allocation.ranked, false); assert.equal(allocation.whitePlayerId, a.profile.playerId);
    const ticket = (await h.request("POST", "/v1/tickets", { matchId: allocation.matchId }, a.token)).data.ticket;
    await h.request("POST", "/internal/tickets/redeem", { ticket }, undefined, admin);
    await h.request("POST", "/internal/results", { matchId: allocation.matchId, result: "draw", reason: "agreement", finalFen: fen, history: [] }, undefined, admin);
    const p = (await h.request("GET", "/v1/me", undefined, a.token)).data.profile; assert.equal(p.battle.draws, 1); assert.equal(p.battle.rating, 1200); assert.equal(p.classic.games, 0);
    const stale = (await h.request("POST", "/v1/private", { mode: "classic", initialMs: 600000, incrementMs: 0 }, a.token)).data.status.invite.code; now += 600001;
    assert.equal((await h.request("POST", "/v1/private/join", { code: stale }, b.token)).status, 404);
    await h.request("POST", "/v1/queue", control, a.token); await h.request("DELETE", "/v1/queue", undefined, a.token); assert.equal((await h.request("GET", "/v1/status", undefined, a.token)).data.status.queue, null);
    now += 31 * 86400000; assert.equal((await h.request("GET", "/v1/me", undefined, a.token)).status, 401);
  } finally { await h.close(); }
});

test("native queue ranked window expands; allocation timeout stays unrated", async () => {
  let now = 1800000000000; const h = await harness(":memory:", () => now); try {
    const a = await h.register("alice"), b = await h.register("bravo");
    await h.storage.transaction(tx => tx.run("UPDATE native_stats SET rating=$1 WHERE player_id=$2 AND mode=$3", 1500, b.profile.playerId, "classic"));
    await h.request("POST", "/v1/queue", control, a.token); assert.equal((await h.request("POST", "/v1/queue", control, b.token)).data.status.allocation, null);
    now += 40000; const allocation = (await h.request("GET", "/v1/status", undefined, a.token)).data.status.allocation; assert.ok(allocation);
    const ticket = (await h.request("POST", "/v1/tickets", { matchId: allocation.matchId }, a.token)).data.ticket; now += 61000;
    assert.equal((await h.request("POST", "/internal/tickets/redeem", { ticket }, undefined, admin)).status, 401);
    now += 300001; assert.equal((await h.request("GET", "/v1/status", undefined, a.token)).data.status.allocation, null);
    const profile = (await h.request("GET", "/v1/me", undefined, a.token)).data.profile; assert.equal(profile.classic.games, 0); assert.equal(profile.classic.rating, 1200);
    const record = (await h.request("GET", "/v1/history", undefined, a.token)).data.matches[0]; assert.equal(record.result, "aborted"); assert.equal(record.ratingChange.white, 0);
  } finally { await h.close(); }
});

test("native persistence survives service reopen and session bearer remains valid", async () => {
  const dir = await mkdtemp(join(tmpdir(), "peepeechess-backend-")), filename = join(dir, "accounts.sqlite"); let h = await harness(filename);
  try {
    const a = await h.register("alice"); await h.close(); h = await harness(filename, Date.now, false);
    const p = await h.request("GET", "/v1/me", undefined, a.token); assert.equal(p.status, 200); assert.equal(p.data.profile.playerId, a.profile.playerId);
    const login = await h.request("POST", "/v1/auth/login", { username: "alice", password: "correct-horse-battery" }); assert.equal(login.data.profile.playerId, a.profile.playerId);
  } finally { await h.close(); await rm(dir, { recursive: true }); }
});

test("native HTTP invalid JSON, unknown fields, limits and body size fail closed", async () => {
  const h = await harness(); try {
    const a = await h.register("alice");
    assert.equal((await h.request("POST", "/v1/queue", { ...control, playerId: "spoof" }, a.token)).status, 400);
    assert.equal((await h.request("POST", "/v1/queue", { ...control, initialMs: 0 }, a.token)).status, 400);
    assert.equal((await h.request("GET", "/v1/history?limit=101", undefined, a.token)).status, 400);
    assert.equal((await h.request("GET", "/v1/leaderboard?mode=invalid", undefined, a.token)).status, 400);
    assert.equal((await fetch(h.url + "/v1/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: "{broken" })).status, 400);
    assert.equal((await h.request("POST", "/v1/auth/login", { username: "alice", password: "x".repeat(1024 * 1024) })).status, 413);
    let rateLimited = false;
    for (let i = 0; i < 32; i++) { const result = await h.request("POST", "/v1/auth/login", { username: "alice", password: "wrong-password" }); if (result.status === 429) { rateLimited = true; break; } }
    assert.equal(rateLimited, true);
  } finally { await h.close(); }
});

test("native heartbeat renews only assigned active leases, expiry aborts once without ratings", async () => {
  let now = 1800000000000; const h = await harness(":memory:", () => now); try {
    const a = await h.register("alice"), b = await h.register("bravo");
    await h.request("POST", "/v1/queue", control, a.token); const allocation = (await h.request("POST", "/v1/queue", control, b.token)).data.status.allocation;
    const ticket = (await h.request("POST", "/v1/tickets", { matchId: allocation.matchId }, a.token)).data.ticket;
    await h.request("POST", "/internal/tickets/redeem", { ticket }, undefined, admin);
    now += 100000; assert.equal((await h.request("POST", "/internal/heartbeat", { matchIds: [allocation.matchId] }, undefined, admin)).status, 200);
    assert.equal((await h.request("POST", "/internal/heartbeat", { matchIds: [allocation.matchId] }, a.token)).status, 401);
    assert.equal((await h.request("POST", "/internal/heartbeat", { matchIds: ["not-owned"] }, undefined, admin)).status, 403);
    assert.equal((await h.request("POST", "/internal/heartbeat", { matchIds: [allocation.matchId, allocation.matchId] }, undefined, admin)).status, 400);
    now += 100000; assert.ok((await h.request("GET", "/v1/status", undefined, a.token)).data.status.allocation);
    now += 21000; assert.equal((await h.request("GET", "/v1/status", undefined, a.token)).data.status.allocation, null);
    const report = { matchId: allocation.matchId, result: "white", reason: "checkmate", finalFen: fen, history: [] };
    assert.equal((await h.request("POST", "/internal/results", report, undefined, admin)).status, 409);
    const history = (await h.request("GET", "/v1/history", undefined, a.token)).data.matches;
    assert.equal(history.length, 1); assert.equal(history[0].result, "aborted"); assert.equal(history[0].reason, "server_lease_expired");
    assert.equal((await h.request("GET", "/v1/me", undefined, a.token)).data.profile.classic.games, 0);
  } finally { await h.close(); }
});

test("native concurrent queue admissions never allocate an account twice", async () => {
  const h = await harness(); try {
    const players = []; for (const name of ["alpha", "bravo", "charlie", "delta"]) players.push(await h.register(name));
    await Promise.all(players.flatMap(p => [h.request("POST", "/v1/queue", control, p.token), h.request("POST", "/v1/queue", control, p.token)]));
    const statuses = await Promise.all(players.map(p => h.request("GET", "/v1/status", undefined, p.token)));
    const rooms = new Map(statuses.map(s => [s.data.status.allocation.matchId, s.data.status.allocation])); assert.equal(rooms.size, 2);
    const seats = [...rooms.values()].flatMap(a => [a.whitePlayerId, a.blackPlayerId]); assert.equal(new Set(seats).size, 4);
  } finally { await h.close(); }
});

test("PostgreSQL transactions serialize matchmaking and result writes across API replicas", { skip: !process.env.NATIVE_TEST_DATABASE_URL }, async () => {
  const first = await harness(), second = await harness(":memory:", Date.now, false);
  try {
    const a = await first.register("alice"), b = await first.register("bravo");
    await Promise.all([first.request("POST", "/v1/queue", control, a.token), second.request("POST", "/v1/queue", control, b.token)]);
    const allocation = (await first.request("GET", "/v1/status", undefined, a.token)).data.status.allocation;
    assert.ok(allocation); assert.equal((await second.request("GET", "/v1/status", undefined, b.token)).data.status.allocation.matchId, allocation.matchId);
    const ticket = (await first.request("POST", "/v1/tickets", { matchId: allocation.matchId }, a.token)).data.ticket;
    const redeems = await Promise.all([first.request("POST", "/internal/tickets/redeem", { ticket }, undefined, admin), second.request("POST", "/internal/tickets/redeem", { ticket }, undefined, admin)]);
    assert.deepEqual(redeems.map(r => r.status).sort(), [200, 401]);
    const report = { matchId: allocation.matchId, result: "draw", reason: "agreement", finalFen: fen, history: [] };
    const results = await Promise.all([first.request("POST", "/internal/results", report, undefined, admin), second.request("POST", "/internal/results", report, undefined, admin)]);
    assert.deepEqual(results.map(r => r.data.duplicate).sort(), [false, true]);
    assert.equal((await second.request("GET", "/v1/me", undefined, a.token)).data.profile.classic.games, 1);
  } finally { await first.close(); await second.close(); }
});

test("native history summary pagination is bounded, stable, private and compatible with full records", async () => {
  let now = 1800000000000; const h = await harness(":memory:", () => now); try {
    const a = await h.register("alice"), b = await h.register("bravo"), c = await h.register("charlie");
    const history = Array.from({ length: 4096 }, (_, ply) => ({ ply, from: "a2", to: "a3", note: "x".repeat(160) }));
    const ids: string[] = [];
    for (let i = 0; i < 3; i++) {
      await h.request("POST", "/v1/queue", control, a.token);
      const allocation = (await h.request("POST", "/v1/queue", control, b.token)).data.status.allocation;
      ids.push(allocation.matchId);
      const ticket = (await h.request("POST", "/v1/tickets", { matchId: allocation.matchId }, a.token)).data.ticket;
      await h.request("POST", "/internal/tickets/redeem", { ticket }, undefined, admin);
      const reported = await h.request("POST", "/internal/results", { matchId: allocation.matchId, result: "draw", reason: "agreement", finalFen: fen, history }, undefined, admin);
      assert.equal(reported.status, 200);
    }
    ids.sort();
    const first = await h.request("GET", "/v1/history/summary?limit=2", undefined, a.token);
    assert.equal(first.status, 200); assert.deepEqual(first.data.matches.map((m: any) => m.matchId), ids.slice(0, 2)); assert.equal(first.data.nextOffset, 2);
    assert.equal(first.data.matches[0].plies, 4096); assert.ok(!Object.hasOwn(first.data.matches[0], "history"));
    assert.ok(!JSON.stringify(first.data).includes('"note"')); assert.ok(Buffer.byteLength(JSON.stringify(first.data)) < 8192);
    const second = await h.request("GET", "/v1/history/summary?limit=2&offset=2", undefined, a.token);
    assert.deepEqual(second.data.matches.map((m: any) => m.matchId), ids.slice(2)); assert.equal(second.data.nextOffset, null);
    const outOfRange = await h.request("GET", "/v1/history/summary?limit=2&offset=1000000", undefined, a.token); assert.deepEqual(outOfRange.data.matches, []); assert.equal(outOfRange.data.nextOffset, null);
    const defaultPage = await h.request("GET", "/v1/history/summary", undefined, a.token); assert.equal(defaultPage.data.matches.length, 3);
    const foreign = await h.request("GET", "/v1/history/summary?playerId=" + a.profile.playerId, undefined, c.token); assert.deepEqual(foreign.data.matches, []);
    assert.equal((await h.request("GET", "/v1/history/summary")).status, 401);
    for (const query of ["limit=0", "limit=101", "offset=-1", "offset=1000001", "offset=1.5", "offset=abc", "offset=0&offset=1"]) assert.equal((await h.request("GET", "/v1/history/summary?" + query, undefined, a.token)).status, 400);
    const full = await h.request("GET", "/v1/history?limit=3", undefined, a.token);
    assert.equal(full.data.matches.length, 3); assert.equal(full.data.matches[0].history.length, 4096); assert.ok(Buffer.byteLength(JSON.stringify(full.data)) > 1024 * 1024);
    // A new completion sorts ahead; clients deliberately refresh offset0 after new results.
    now += 1;
    await h.request("POST", "/v1/queue", control, a.token);
    const later = (await h.request("POST", "/v1/queue", control, b.token)).data.status.allocation;
    const ticket = (await h.request("POST", "/v1/tickets", { matchId: later.matchId }, a.token)).data.ticket;
    await h.request("POST", "/internal/tickets/redeem", { ticket }, undefined, admin);
    await h.request("POST", "/internal/results", { matchId: later.matchId, result: "draw", reason: "agreement", finalFen: fen, history: [] }, undefined, admin);
    const refreshed = await h.request("GET", "/v1/history/summary?limit=1&offset=0", undefined, a.token);
    assert.equal(refreshed.data.matches[0].matchId, later.matchId); assert.equal(refreshed.data.nextOffset, 1);
  } finally { await h.close(); }
});

// ---- friends and friend challenges -------------------------------------------------------------------------------------
const ref = (account: any) => ({ playerId: account.profile.playerId, username: account.profile.username, displayName: account.profile.displayName });
async function befriend(h: any, asker: any, other: any) {
  assert.equal((await h.request("POST", "/v1/friends/request", { username: other.profile.username }, asker.token)).status, 200);
  const accepted = await h.request("POST", "/v1/friends/accept", { playerId: asker.profile.playerId }, other.token); assert.equal(accepted.status, 200); return accepted.data;
}
/** Accounts that exist only as rows (registering costs a scrypt each, and sign-ups are rate limited), for exercising the caps. */
async function fakePlayers(h: any, count: number): Promise<string[]> {
  const ids = Array.from({ length: count }, (_, i) => `fake-player-${i}`);
  await h.storage.transaction(async (tx: any) => { for (const [i, id] of ids.entries()) await tx.run("INSERT INTO native_accounts(player_id,username,display_name,password_hash,created_at) VALUES($1,$2,$3,$4,$5)", id, `fake_${i}`, `Fake ${i}`, "0:0", 1); });
  return ids;
}

test("native friends: requests, acceptance, mutual requests, presence and removal", async () => {
  let now = 1800000000000; const h = await harness(":memory:", () => now); try {
    const a = await h.register("alice"), b = await h.register("bravo"), c = await h.register("charlie");
    const A = a.profile.playerId, B = b.profile.playerId, C = c.profile.playerId;
    assert.equal((await h.request("GET", "/v1/friends")).status, 401);
    const empty = (await h.request("GET", "/v1/friends", undefined, a.token)).data;
    assert.deepEqual([empty.friends, empty.incoming, empty.outgoing, empty.challenges], [[], [], [], { incoming: [], outgoing: null }]);
    // Admission is strict: exact fields, a valid username, a real player, not yourself.
    assert.equal((await h.request("POST", "/v1/friends/request", { username: "bravo", extra: 1 }, a.token)).status, 400);
    assert.equal((await h.request("POST", "/v1/friends/request", { username: "no spaces!" }, a.token)).status, 400);
    assert.equal((await h.request("POST", "/v1/friends/request", { username: "nobody_here" }, a.token)).status, 404);
    assert.equal((await h.request("POST", "/v1/friends/request", { username: "ALICE" }, a.token)).status, 400);
    assert.equal((await h.request("POST", "/v1/friends/request", { username: "bravo" })).status, 401);
    // A request: usernames are case-insensitive; the addressee sees it; you cannot accept your own request or someone else's.
    const sent = await h.request("POST", "/v1/friends/request", { username: "BRAVO" }, a.token);
    assert.equal(sent.status, 200); assert.equal(sent.data.result, "requested"); assert.deepEqual(sent.data.outgoing, [ref(b)]);
    assert.deepEqual((await h.request("GET", "/v1/friends", undefined, b.token)).data.incoming, [ref(a)]);
    const again = await h.request("POST", "/v1/friends/request", { username: "bravo" }, a.token); assert.equal(again.status, 409); assert.equal(again.data.error.code, "REQUEST_PENDING");
    assert.equal((await h.request("POST", "/v1/friends/accept", { playerId: B }, a.token)).status, 404);
    assert.equal((await h.request("POST", "/v1/friends/accept", { playerId: A }, c.token)).status, 404);
    assert.equal((await h.request("POST", "/v1/friends/challenge", { playerId: B, mode: "classic", initialMs: 600000, incrementMs: 0 }, a.token)).status, 403);  // a pending request is not a friendship
    const accepted = await h.request("POST", "/v1/friends/accept", { playerId: A }, b.token); assert.equal(accepted.status, 200); assert.deepEqual(accepted.data.incoming, []);
    // Both sides list each other with ratings. Presence is "seen in the last 45 seconds"; both have polled just now.
    const live = { online: true, inMatch: false, classicRating: 1200, battleRating: 1200 };
    assert.deepEqual((await h.request("GET", "/v1/friends", undefined, b.token)).data.friends, [{ ...ref(a), ...live }]);
    assert.deepEqual((await h.request("GET", "/v1/friends", undefined, a.token)).data.friends, [{ ...ref(b), ...live }]);
    now += ONLINE_MS + 1000;
    assert.equal((await h.request("GET", "/v1/friends", undefined, a.token)).data.friends[0].online, false);  // bravo last polled 46 s ago
    assert.equal((await h.request("GET", "/v1/friends", undefined, b.token)).data.friends[0].online, true);   // alice polled a moment ago
    for (const [x, y] of [[a, "bravo"], [b, "alice"]] as const) { const dup = await h.request("POST", "/v1/friends/request", { username: y }, x.token); assert.equal(dup.status, 409); assert.equal(dup.data.error.code, "ALREADY_FRIENDS"); }
    // Mutual requests: asking someone who already asked you accepts.
    await h.request("POST", "/v1/friends/request", { username: "alice" }, c.token);
    const mutual = await h.request("POST", "/v1/friends/request", { username: "charlie" }, a.token); assert.equal(mutual.data.result, "accepted");
    assert.deepEqual(mutual.data.friends.map((f: any) => f.playerId).sort(), [B, C].sort()); assert.deepEqual(mutual.data.incoming, []);
    // Removing: unfriend is visible to both, is idempotent, and the same call declines or cancels a pending request.
    const removed = await h.request("POST", "/v1/friends/remove", { playerId: B }, a.token); assert.deepEqual(removed.data.friends.map((f: any) => f.playerId), [C]);
    assert.deepEqual((await h.request("GET", "/v1/friends", undefined, b.token)).data.friends, []);
    assert.equal((await h.request("POST", "/v1/friends/remove", { playerId: B }, a.token)).status, 200);
    await h.request("POST", "/v1/friends/request", { username: "alice" }, b.token);
    assert.deepEqual((await h.request("POST", "/v1/friends/remove", { playerId: B }, a.token)).data.incoming, []);   // alice declines
    assert.deepEqual((await h.request("GET", "/v1/friends", undefined, b.token)).data.outgoing, []);
    await h.request("POST", "/v1/friends/request", { username: "alice" }, b.token);
    assert.deepEqual((await h.request("POST", "/v1/friends/remove", { playerId: A }, b.token)).data.outgoing, []);     // bravo cancels
    assert.equal((await h.request("POST", "/v1/friends/remove", { playerId: A, extra: true }, b.token)).status, 400);
  } finally { await h.close(); }
});

test("native friends: list and request caps, expiry and per-account rate limit fail closed", async () => {
  let now = 1800000000000; const h = await harness(":memory:", () => now); try {
    const a = await h.register("alice"), b = await h.register("bravo"), c = await h.register("charlie");
    const A = a.profile.playerId, fakes = await fakePlayers(h, FRIEND_LIMIT);
    // Too many unanswered requests.
    await h.storage.transaction(async (tx: any) => { for (const id of fakes.slice(0, PENDING_REQUEST_LIMIT)) await tx.run("INSERT INTO native_friendships(requester_id,addressee_id,status,created_at) VALUES($1,$2,'pending',$3)", A, id, now); });
    const over = await h.request("POST", "/v1/friends/request", { username: "bravo" }, a.token); assert.equal(over.status, 409); assert.equal(over.data.error.code, "REQUEST_LIMIT");
    // Unanswered requests expire after 30 days, which frees the slots. (Sessions last 30 days too, so everyone signs in again.)
    now += PENDING_REQUEST_MS + 1;
    for (const [account, name] of [[a, "alice"], [b, "bravo"], [c, "charlie"]] as const) account.token = (await h.request("POST", "/v1/auth/login", { username: name, password: "correct-horse-battery" })).data.token;
    assert.equal((await h.request("POST", "/v1/friends/request", { username: "bravo" }, a.token)).data.result, "requested");
    assert.equal((await h.request("GET", "/v1/friends", undefined, a.token)).data.outgoing.length, 1);
    // A full friends list can neither send nor accept another.
    await h.storage.transaction(async (tx: any) => { for (const id of fakes) await tx.run("INSERT INTO native_friendships(requester_id,addressee_id,status,created_at) VALUES($1,$2,'accepted',$3)", id, A, now); });
    const full = await h.request("POST", "/v1/friends/request", { username: "charlie" }, a.token); assert.equal(full.status, 409); assert.equal(full.data.error.code, "FRIEND_LIMIT");
    const blocked = await h.request("POST", "/v1/friends/accept", { playerId: A }, b.token); assert.equal(blocked.status, 409); assert.equal(blocked.data.error.code, "FRIEND_LIMIT");
    assert.equal((await h.request("GET", "/v1/friends", undefined, a.token)).data.friends.length, FRIEND_LIMIT);
    // Per-account limit on sending requests (counted even when they fail), independent of the per-IP limit.
    let limited = 0; for (let i = 0; i < 31; i++) if ((await h.request("POST", "/v1/friends/request", { username: "nobody_here" }, c.token)).status === 429) limited++;
    assert.equal(limited, 1);
  } finally { await h.close(); }
});

test("native friend challenges: friends only, only the target joins, colours, decline, expiry, unfriend and cancel", async () => {
  let now = 1800000000000; const h = await harness(":memory:", () => now); try {
    const a = await h.register("alice"), b = await h.register("bravo"), c = await h.register("charlie"), d = await h.register("delta");
    const A = a.profile.playerId, B = b.profile.playerId;
    await befriend(h, a, b); await befriend(h, a, c);
    const challenge = (from: any, to: any, extra: object = {}) => h.request("POST", "/v1/friends/challenge", { playerId: to.profile.playerId, mode: "classic", initialMs: 600000, incrementMs: 0, ...extra }, from.token);
    const friendsOf = async (who: any) => (await h.request("GET", "/v1/friends", undefined, who.token)).data;
    const abort = (matchId: string) => h.request("POST", "/internal/results", { matchId, result: "aborted", reason: "test", finalFen: fen, history: [] }, undefined, admin);
    // Friends only, strict, validated, and never ranked.
    assert.equal((await challenge(a, d)).status, 403);
    await h.request("POST", "/v1/friends/request", { username: "delta" }, a.token); assert.equal((await challenge(a, d)).status, 403);
    assert.equal((await challenge(a, b, { ranked: true })).status, 400);
    assert.equal((await challenge(a, b, { side: "purple" })).status, 400);
    assert.equal((await challenge(a, b, { mode: "battle" })).status, 400);   // Battle is untimed
    assert.equal((await challenge(a, b, { initialMs: 1000 })).status, 400);
    assert.equal((await h.request("POST", "/v1/friends/challenge", { playerId: B, mode: "classic", initialMs: 600000 }, a.token)).status, 400);
    // Sending: the invite code is in the sender's status (so the client keeps polling), the recipient sees the opposite colour.
    const sent = await challenge(a, b, { side: "black" }); assert.equal(sent.status, 200);
    const code = sent.data.status.invite.code; assert.match(code, /^[A-HJ-NP-Z2-9]{6}$/);
    const base = { code, mode: "classic", initialMs: 600000, incrementMs: 0, expiresAt: now + 600000 };
    assert.deepEqual(sent.data.challenges.outgoing, { ...base, player: ref(b), side: "black" });
    assert.deepEqual((await friendsOf(b)).challenges.incoming, [{ ...base, player: ref(a), side: "white" }]);
    // Only the target can see or join it: not another friend of the sender, not the sender.
    assert.deepEqual((await friendsOf(c)).challenges.incoming, []);
    assert.equal((await h.request("POST", "/v1/private/join", { code }, c.token)).status, 404);
    assert.equal((await h.request("POST", "/v1/private/join", { code }, a.token)).status, 404);
    assert.equal((await h.request("POST", "/v1/friends/challenge/decline", { code }, c.token)).status, 404);
    // The target declines: gone for both, and the code is dead.
    const declined = await h.request("POST", "/v1/friends/challenge/decline", { code }, b.token); assert.equal(declined.status, 200); assert.deepEqual(declined.data.challenges.incoming, []);
    assert.equal((await friendsOf(a)).challenges.outgoing, null); assert.equal((await h.request("GET", "/v1/status", undefined, a.token)).data.status.invite, null);
    assert.equal((await h.request("POST", "/v1/private/join", { code }, b.token)).status, 404);
    // Accepting is the ordinary private join. The sender chose Black, so the friend is White. Friend games are never ranked.
    const second = (await challenge(a, b, { side: "black" })).data.status.invite.code;
    const allocation = (await h.request("POST", "/v1/private/join", { code: second }, b.token)).data.status.allocation;
    assert.equal(allocation.whitePlayerId, B); assert.equal(allocation.blackPlayerId, A); assert.equal(allocation.ranked, false); assert.equal(allocation.mode, "classic"); assert.equal(allocation.initialMs, 600000);
    assert.deepEqual((await friendsOf(b)).challenges, { incoming: [], outgoing: null });
    assert.equal((await friendsOf(a)).friends.find((f: any) => f.playerId === B).inMatch, true);
    assert.equal((await friendsOf(b)).friends.find((f: any) => f.playerId === A).inMatch, true);
    assert.equal((await challenge(a, c)).status, 409);   // ACTIVE_MATCH until the game ends
    await abort(allocation.matchId);
    assert.equal((await friendsOf(a)).friends.find((f: any) => f.playerId === B).inMatch, false);
    // The sender may choose White; "random" is decided by the server but always seats both players.
    const asWhite = (await h.request("POST", "/v1/private/join", { code: (await challenge(a, b, { side: "white" })).data.status.invite.code }, b.token)).data.status.allocation;
    assert.equal(asWhite.whitePlayerId, A); assert.equal(asWhite.blackPlayerId, B); await abort(asWhite.matchId);
    const random = (await h.request("POST", "/v1/private/join", { code: (await challenge(a, b)).data.status.invite.code }, b.token)).data.status.allocation;
    assert.deepEqual([random.whitePlayerId, random.blackPlayerId].sort(), [A, B].sort()); assert.equal(random.ranked, false); await abort(random.matchId);
    // A challenge expires with the invite.
    const stale = (await challenge(a, b)).data.status.invite.code; now += 600001;
    assert.deepEqual((await friendsOf(b)).challenges.incoming, []); assert.equal((await friendsOf(a)).challenges.outgoing, null);
    assert.equal((await h.request("POST", "/v1/private/join", { code: stale }, b.token)).status, 404);
    // Unfriending withdraws it.
    const pending = (await challenge(a, b)).data.status.invite.code;
    await h.request("POST", "/v1/friends/remove", { playerId: B }, a.token);
    assert.deepEqual((await friendsOf(b)).challenges.incoming, []); assert.equal((await h.request("POST", "/v1/private/join", { code: pending }, b.token)).status, 404);
    assert.equal((await challenge(a, b)).status, 403);
    // Searching for a quick match elsewhere, or cancelling, withdraws it too.
    await befriend(h, b, a);
    const queued = (await challenge(a, b)).data.status.invite.code;
    await h.request("POST", "/v1/queue", control, a.token);
    assert.deepEqual((await friendsOf(b)).challenges.incoming, []); assert.equal((await h.request("POST", "/v1/private/join", { code: queued }, b.token)).status, 404);
    await h.request("DELETE", "/v1/queue", undefined, a.token);
    await challenge(a, b); await h.request("DELETE", "/v1/queue", undefined, a.token);
    assert.deepEqual((await friendsOf(b)).challenges.incoming, []);
    // A newer challenge replaces the sender's previous one (one outstanding invite per player).
    await challenge(a, b); const newest = (await challenge(a, c)).data.status.invite.code;
    assert.deepEqual((await friendsOf(b)).challenges.incoming, []); assert.deepEqual((await friendsOf(c)).challenges.incoming.map((x: any) => x.code), [newest]);
  } finally { await h.close(); }
});
