import { createHash, randomBytes, randomUUID, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import type { Allocation, Endpoint, HistoryPage, MatchOptions, MatchRecord, Mode, Profile, Stats, Status } from "../../contracts/application/v1/types.js";
import { NativeStorage, type Transaction } from "./storage.js";
const scrypt = (password: string, salt: string) => new Promise<Buffer>((resolve, reject) => scryptCallback(password, salt, 64, { N: 32768, r: 8, p: 3, maxmem: 64 * 1024 * 1024 }, (error, key) => error ? reject(error) : resolve(key)));
const hash = (value: string) => createHash("sha256").update(value).digest("hex");
const token = () => randomBytes(32).toString("hex");
const SESSION_MS = 30 * 24 * 60 * 60 * 1000;
export class ApiError extends Error { constructor(readonly status: number, readonly code: string, message: string) { super(message); } }
function need(condition: unknown, status: number, code: string, message: string): asserts condition { if (!condition) throw new ApiError(status, code, message); }
export function object(value: unknown, keys: string[], optional: string[] = []): asserts value is Record<string, any> {
  need(value && typeof value === "object" && !Array.isArray(value), 400, "INVALID_PAYLOAD", "Expected a JSON object.");
  need(Object.keys(value).every(key => keys.includes(key) || optional.includes(key)) && keys.every(key => Object.hasOwn(value, key)), 400, "INVALID_PAYLOAD", "Missing or unknown fields.");
}
function options(value: any, privateMatch = false): MatchOptions {
  object(value, privateMatch ? ["mode", "initialMs", "incrementMs"] : ["mode", "ranked", "initialMs", "incrementMs"]);
  need(value.mode === "classic" || value.mode === "battle", 400, "INVALID_PAYLOAD", "Choose Classic or Battle.");
  need(privateMatch || typeof value.ranked === "boolean", 400, "INVALID_PAYLOAD", "Choose ranked or unranked.");
  need(Number.isInteger(value.initialMs) && Number.isInteger(value.incrementMs) && (value.mode === "battle" ? value.initialMs === 0 && value.incrementMs === 0 : value.initialMs >= 60000 && value.initialMs <= 10800000 && value.incrementMs >= 0 && value.incrementMs <= 60000), 400, "INVALID_PAYLOAD", "Unsupported time control.");
  return { mode: value.mode, ranked: privateMatch ? false : value.ranked, initialMs: value.initialMs, incrementMs: value.incrementMs };
}
function mode(value: unknown): Mode { need(value === "classic" || value === "battle", 400, "INVALID_PAYLOAD", "Choose Classic or Battle."); return value; }
const initialStats = (): Stats => ({ rating: 1200, wins: 0, losses: 0, draws: 0, games: 0 });
function safeName(value: unknown) {
  need(typeof value === "string" && value.trim().length > 0 && value.trim().length <= 32 && !/[\u0000-\u001f\u007f]/.test(value), 400, "INVALID_PAYLOAD", "Display name must contain 1–32 visible characters.");
  return value.trim();
}
function credentials(value: unknown): { username: string; password: string } {
  const v = value as any;
  need(typeof v.username === "string" && /^[a-zA-Z0-9_]{3,24}$/.test(v.username), 400, "INVALID_PAYLOAD", "Username must contain 3–24 letters, numbers or underscores.");
  need(typeof v.password === "string" && v.password.length >= 10 && v.password.length <= 128, 400, "INVALID_PAYLOAD", "Password must contain 10–128 characters.");
  return { username: v.username.toLowerCase(), password: v.password };
}
function statsRow(row: any): Stats { return { rating: Number(row.rating), wins: Number(row.wins), losses: Number(row.losses), draws: Number(row.draws), games: Number(row.games) }; }
function canonical(value: any): string { return JSON.stringify(value && typeof value === "object" ? Array.isArray(value) ? value.map(v => JSON.parse(canonical(v))) : Object.fromEntries(Object.keys(value).sort().map(k => [k, JSON.parse(canonical(value[k]))])) : value); }
export class NativeService {
  constructor(readonly storage: NativeStorage, readonly config: { serverId: string; endpoint: Endpoint }, readonly now = Date.now) {}
  async register(body: unknown) {
    object(body, ["username", "password", "displayName"]); const { username, password } = credentials(body); const displayName = safeName(body.displayName);
    const salt = randomBytes(16).toString("hex"), derived = await scrypt(password, salt);
    return this.storage.transaction(async tx => {
      need(!await tx.get("SELECT player_id FROM native_accounts WHERE username=$1", username), 409, "USERNAME_TAKEN", "That username is unavailable.");
      const playerId = randomUUID();
      await tx.run("INSERT INTO native_accounts(player_id,username,display_name,password_hash,created_at) VALUES($1,$2,$3,$4,$5)", playerId, username, displayName, salt + ":" + derived.toString("hex"), this.now());
      for (const m of ["classic", "battle"]) await tx.run("INSERT INTO native_stats(player_id,mode) VALUES($1,$2)", playerId, m);
      return this.newSession(tx, playerId);
    });
  }
  async login(body: unknown) {
    object(body, ["username", "password"]); const { username, password } = credentials(body);
    const account = await this.storage.transaction(tx => tx.get("SELECT * FROM native_accounts WHERE username=$1", username));
    const [salt, stored] = (account?.password_hash || "0".repeat(32) + ":" + "0".repeat(128)).split(":");
    const derived = await scrypt(password, salt);
    need(account && timingSafeEqual(derived, Buffer.from(stored, "hex")), 401, "INVALID_CREDENTIALS", "Username or password is incorrect.");
    return this.storage.transaction(tx => this.newSession(tx, account.player_id));
  }
  private async newSession(tx: Transaction, playerId: string) {
    const secret = token(), expiresAt = this.now() + SESSION_MS;
    await tx.run("DELETE FROM native_sessions WHERE expires_at<=$1", this.now());
    // Bound active sessions per account; oldest sessions are removed, not prolonged.
    const sessions = await tx.all("SELECT token_hash FROM native_sessions WHERE player_id=$1 ORDER BY expires_at DESC", playerId);
    for (const old of sessions.slice(7)) await tx.run("DELETE FROM native_sessions WHERE token_hash=$1", old.token_hash);
    await tx.run("INSERT INTO native_sessions(token_hash,player_id,expires_at) VALUES($1,$2,$3)", hash(secret), playerId, expiresAt);
    return { token: secret, expiresAt, profile: await this.profile(tx, playerId) };
  }
  async authenticate(secret: unknown) {
    need(typeof secret === "string" && /^[a-f0-9]{64}$/.test(secret), 401, "UNAUTHENTICATED", "Sign in to continue.");
    return this.storage.transaction(async tx => {
      const session = await tx.get("SELECT player_id,expires_at FROM native_sessions WHERE token_hash=$1", hash(secret));
      need(session && Number(session.expires_at) > this.now(), 401, "UNAUTHENTICATED", "Your session expired. Sign in again.");
      return session.player_id as string;
    });
  }
  async logout(secret: string) { await this.storage.transaction(tx => tx.run("DELETE FROM native_sessions WHERE token_hash=$1", hash(secret))); return { ok: true }; }
  private async profile(tx: Transaction, playerId: string): Promise<Profile> {
    const account = await tx.get("SELECT player_id,username,display_name,created_at FROM native_accounts WHERE player_id=$1", playerId);
    need(account, 404, "NOT_FOUND", "Player not found.");
    const rows = await tx.all("SELECT * FROM native_stats WHERE player_id=$1", playerId);
    return { playerId: account.player_id, username: account.username, displayName: account.display_name, createdAt: Number(account.created_at), classic: statsRow(rows.find(r => r.mode === "classic")), battle: statsRow(rows.find(r => r.mode === "battle")) };
  }
  getProfile(playerId: string) { return this.storage.transaction(async tx => ({ profile: await this.profile(tx, playerId) })); }
  history(playerId: string, limit: number) { return this.storage.transaction(async tx => ({ matches: (await tx.all("SELECT record_json FROM native_matches WHERE (white_player_id=$1 OR black_player_id=$2) AND record_json IS NOT NULL ORDER BY completed_at DESC LIMIT $3", playerId, playerId, limit)).map(r => JSON.parse(r.record_json)) })); }
  historySummary(playerId: string, limit: number, offset: number): Promise<HistoryPage> {
    return this.storage.transaction(async tx => {
      // Strip move arrays inside the database so large records never become
      // multi-megabyte API buffers or PostgreSQL-to-API result transfers.
      const projection = this.storage.kind === "postgresql"
        ? "((record_json::jsonb - 'history') || jsonb_build_object('plies',jsonb_array_length(record_json::jsonb->'history')))::text"
        : "json_set(json_remove(record_json,'$.history'),'$.plies',json_array_length(record_json,'$.history'))";
      const rows = await tx.all(`SELECT ${projection} AS summary_json FROM native_matches WHERE (white_player_id=$1 OR black_player_id=$2) AND record_json IS NOT NULL ORDER BY completed_at DESC,match_id ASC LIMIT $3 OFFSET $4`, playerId, playerId, limit + 1, offset);
      return {
        matches: rows.slice(0, limit).map(row => JSON.parse(row.summary_json)),
        nextOffset: rows.length > limit && offset + limit <= 1000000 ? offset + limit : null,
      };
    });
  }
  leaderboard(selectedMode: unknown, limit: number) { const m = mode(selectedMode); return this.storage.transaction(async tx => {
    const rows = await tx.all("SELECT player_id FROM native_stats WHERE mode=$1 AND games>0 ORDER BY rating DESC,wins DESC,player_id ASC LIMIT $2", m, limit);
    return { players: await Promise.all(rows.map(r => this.profile(tx, r.player_id))) };
  }); }
  private async cleanup(tx: Transaction) {
    const now = this.now();
    await tx.run("DELETE FROM native_queue WHERE touched_at<$1", now - 600000);
    await tx.run("DELETE FROM native_invites WHERE expires_at<=$1", now);
    await tx.run("DELETE FROM native_tickets WHERE expires_at<=$1", now);
    const stale = await tx.all("SELECT match_id FROM native_matches WHERE status='allocated' AND created_at<$1", now - 300000);
    for (const match of stale) await this.complete(tx, match.match_id, "aborted", "allocation_timeout", "", []);
    const expired = await tx.all("SELECT match_id FROM native_matches WHERE status='active' AND last_seen<$1", now - 120000);
    for (const match of expired) await this.complete(tx, match.match_id, "aborted", "server_lease_expired", "", []);
  }
  private async active(tx: Transaction, playerId: string): Promise<Allocation | null> {
    const row = await tx.get("SELECT allocation_json FROM native_matches WHERE (white_player_id=$1 OR black_player_id=$2) AND status IN ('allocated','active') ORDER BY created_at DESC LIMIT 1", playerId, playerId);
    return row ? JSON.parse(row.allocation_json) : null;
  }
  private async status(tx: Transaction, playerId: string): Promise<Status> {
    const q = await tx.get("SELECT * FROM native_queue WHERE player_id=$1", playerId);
    const invite = await tx.get("SELECT code,expires_at FROM native_invites WHERE player_id=$1", playerId);
    return { queue: q ? { mode: q.mode, ranked: !!q.ranked, initialMs: q.initial_ms, incrementMs: q.increment_ms, enteredAt: Number(q.entered_at) } : null, allocation: await this.active(tx, playerId), invite: invite ? { code: invite.code, expiresAt: Number(invite.expires_at) } : null };
  }
  private async removeWaiting(tx: Transaction, playerId: string) {
    await tx.run("DELETE FROM native_queue WHERE player_id=$1", playerId); await tx.run("DELETE FROM native_invites WHERE player_id=$1", playerId);
  }
  private async allocate(tx: Transaction, white: string, black: string, opts: MatchOptions) {
    const allocation: Allocation = { matchId: randomUUID(), mode: opts.mode, ranked: opts.ranked, whitePlayerId: white, blackPlayerId: black, initialMs: opts.initialMs, incrementMs: opts.incrementMs, serverId: this.config.serverId, endpoint: this.config.endpoint, createdAt: this.now() };
    await this.removeWaiting(tx, white); await this.removeWaiting(tx, black);
    await tx.run("INSERT INTO native_matches(match_id,white_player_id,black_player_id,allocation_json,status,created_at) VALUES($1,$2,$3,$4,$5,$6)", allocation.matchId, white, black, JSON.stringify(allocation), "allocated", allocation.createdAt);
    return allocation;
  }
  private async pair(tx: Transaction, playerId: string) {
    const own = await tx.get("SELECT * FROM native_queue WHERE player_id=$1", playerId); if (!own) return;
    const ownStats = await tx.get("SELECT rating FROM native_stats WHERE player_id=$1 AND mode=$2", playerId, own.mode);
    const candidates = await tx.all("SELECT q.*,s.rating FROM native_queue q JOIN native_stats s ON s.player_id=q.player_id AND s.mode=q.mode WHERE q.player_id<>$1 AND q.mode=$2 AND q.ranked=$3 AND q.initial_ms=$4 AND q.increment_ms=$5 ORDER BY q.entered_at ASC,q.player_id ASC", playerId, own.mode, own.ranked, own.initial_ms, own.increment_ms);
    for (const candidate of candidates) {
      const wait = Math.max(this.now() - Number(own.entered_at), this.now() - Number(candidate.entered_at));
      const window = Math.min(600, 100 + Math.floor(wait / 10000) * 50);
      if (own.ranked && Math.abs(ownStats!.rating - candidate.rating) > window) continue;
      const flip = randomBytes(1)[0] % 2 === 0;
      await this.allocate(tx, flip ? playerId : candidate.player_id, flip ? candidate.player_id : playerId, { mode: own.mode, ranked: !!own.ranked, initialMs: own.initial_ms, incrementMs: own.increment_ms });
      return;
    }
  }
  queue(playerId: string, body: unknown) { const opts = options(body); return this.storage.transaction(async tx => {
    await this.cleanup(tx); need(!await this.active(tx, playerId), 409, "ACTIVE_MATCH", "Finish your active match first.");
    const existing = await tx.get("SELECT * FROM native_queue WHERE player_id=$1", playerId);
    if (!existing || existing.mode !== opts.mode || !!existing.ranked !== opts.ranked || existing.initial_ms !== opts.initialMs || existing.increment_ms !== opts.incrementMs) {
      await this.removeWaiting(tx, playerId);
      await tx.run("INSERT INTO native_queue(player_id,mode,ranked,initial_ms,increment_ms,entered_at,touched_at) VALUES($1,$2,$3,$4,$5,$6,$7)", playerId, opts.mode, opts.ranked ? 1 : 0, opts.initialMs, opts.incrementMs, this.now(), this.now());
    } else await tx.run("UPDATE native_queue SET touched_at=$1 WHERE player_id=$2", this.now(), playerId);
    await this.pair(tx, playerId); return { status: await this.status(tx, playerId) };
  }); }
  getStatus(playerId: string) { return this.storage.transaction(async tx => { await this.cleanup(tx); await tx.run("UPDATE native_queue SET touched_at=$1 WHERE player_id=$2", this.now(), playerId); await this.pair(tx, playerId); return { status: await this.status(tx, playerId) }; }); }
  cancel(playerId: string) { return this.storage.transaction(async tx => { await this.removeWaiting(tx, playerId); return { status: await this.status(tx, playerId) }; }); }
  createPrivate(playerId: string, body: unknown) { const opts = options(body, true); return this.storage.transaction(async tx => {
    await this.cleanup(tx); need(!await this.active(tx, playerId), 409, "ACTIVE_MATCH", "Finish your active match first."); await this.removeWaiting(tx, playerId);
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let code = ""; do { code = [...randomBytes(6)].map(v => alphabet[v % alphabet.length]).join(""); } while (await tx.get("SELECT code FROM native_invites WHERE code=$1", code));
    await tx.run("INSERT INTO native_invites(code,player_id,options_json,expires_at) VALUES($1,$2,$3,$4)", code, playerId, JSON.stringify(opts), this.now() + 600000);
    return { status: await this.status(tx, playerId) };
  }); }
  joinPrivate(playerId: string, body: unknown) { object(body, ["code"]); need(typeof body.code === "string" && /^[A-HJ-NP-Z2-9]{6}$/.test(body.code), 400, "INVALID_PAYLOAD", "Enter a six-character invite code."); return this.storage.transaction(async tx => {
    await this.cleanup(tx); need(!await this.active(tx, playerId), 409, "ACTIVE_MATCH", "Finish your active match first.");
    const invite = await tx.get("SELECT * FROM native_invites WHERE code=$1", body.code);
    need(invite && invite.player_id !== playerId, 404, "INVITE_NOT_FOUND", "That invite is unavailable.");
    need(!await this.active(tx, invite.player_id), 409, "ACTIVE_MATCH", "That invite is unavailable.");
    await this.allocate(tx, invite.player_id, playerId, JSON.parse(invite.options_json)); return { status: await this.status(tx, playerId) };
  }); }
  issueTicket(playerId: string, body: unknown) { object(body, ["matchId"]); need(typeof body.matchId === "string", 400, "INVALID_PAYLOAD", "Invalid match ID."); return this.storage.transaction(async tx => {
    await this.cleanup(tx); const allocation = await this.active(tx, playerId);
    need(allocation !== null && allocation.matchId === body.matchId, 403, "FORBIDDEN", "That match is not assigned to you.");
    const secret = token(), expiresAt = this.now() + 60000;
    await tx.run("DELETE FROM native_tickets WHERE player_id=$1", playerId);
    await tx.run("INSERT INTO native_tickets(token_hash,player_id,match_id,expires_at) VALUES($1,$2,$3,$4)", hash(secret), playerId, allocation.matchId, expiresAt);
    return { ticket: secret, expiresAt, allocation };
  }); }
  redeemTicket(serverId: string, body: unknown) { object(body, ["ticket"]); need(typeof body.ticket === "string" && /^[a-f0-9]{64}$/.test(body.ticket), 401, "INVALID_TICKET", "Invalid match ticket."); return this.storage.transaction(async tx => {
    await this.cleanup(tx); const ticket = await tx.get("SELECT * FROM native_tickets WHERE token_hash=$1", hash(body.ticket));
    need(ticket && Number(ticket.expires_at) > this.now(), 401, "INVALID_TICKET", "Match ticket expired or already used.");
    const row = await tx.get("SELECT * FROM native_matches WHERE match_id=$1", ticket.match_id);
    const allocation: Allocation = JSON.parse(row.allocation_json);
    need(allocation.serverId === serverId && (row.status === "allocated" || row.status === "active"), 403, "FORBIDDEN", "Match ticket is not assigned to this server.");
    await tx.run("DELETE FROM native_tickets WHERE token_hash=$1", hash(body.ticket));
    await tx.run("UPDATE native_matches SET status='active',last_seen=$1 WHERE match_id=$2", this.now(), ticket.match_id);
    return { playerId: ticket.player_id, allocation };
  }); }
  heartbeat(serverId: string, body: unknown) {
    object(body, ["matchIds"]);
    need(Array.isArray(body.matchIds) && body.matchIds.length <= 256 && body.matchIds.every(id => typeof id === "string" && id.length <= 96) && new Set(body.matchIds).size === body.matchIds.length, 400, "INVALID_PAYLOAD", "Invalid heartbeat match list.");
    return this.storage.transaction(async tx => {
      for (const matchId of body.matchIds) {
        const row = await tx.get("SELECT allocation_json,status FROM native_matches WHERE match_id=$1", matchId);
        need(row && JSON.parse(row.allocation_json).serverId === serverId, 403, "FORBIDDEN", "Heartbeat match is not assigned to this server.");
        if (row.status === "active") await tx.run("UPDATE native_matches SET last_seen=$1 WHERE match_id=$2", this.now(), matchId);
      }
      return { ok: true };
    });
  }
  report(serverId: string, body: unknown) {
    object(body, ["matchId", "result", "reason", "finalFen", "history"]);
    need(typeof body.matchId === "string" && ["white", "black", "draw", "aborted"].includes(body.result) && typeof body.reason === "string" && body.reason.length >= 1 && body.reason.length <= 96 && typeof body.finalFen === "string" && body.finalFen.length <= 256 && Array.isArray(body.history) && body.history.length <= 4096, 400, "INVALID_PAYLOAD", "Invalid match report.");
    return this.storage.transaction(async tx => {
      const row = await tx.get("SELECT * FROM native_matches WHERE match_id=$1", body.matchId); need(row, 404, "NOT_FOUND", "Match not found.");
      need(JSON.parse(row.allocation_json).serverId === serverId, 403, "FORBIDDEN", "Only the assigned server may finalize this match.");
      const report = canonical(body);
      if (row.report_json) { need(row.report_json === report, 409, "CONFLICTING_RESULT", "Match already finalized with another result."); return { record: JSON.parse(row.record_json), duplicate: true }; }
      need(row.status === "active" || body.result === "aborted", 409, "MATCH_NOT_STARTED", "Match has not started.");
      const record = await this.complete(tx, body.matchId, body.result, body.reason, body.finalFen, body.history, report);
      return { record, duplicate: false };
    });
  }
  private async complete(tx: Transaction, matchId: string, result: string, reason: string, finalFen: string, history: any[], report?: string) {
    const row = await tx.get("SELECT * FROM native_matches WHERE match_id=$1", matchId), a: Allocation = JSON.parse(row.allocation_json);
    const white = await this.profile(tx, a.whitePlayerId), black = await this.profile(tx, a.blackPlayerId);
    const ws = white[a.mode], bs = black[a.mode]; let delta = 0;
    if (result !== "aborted") {
      const score = result === "white" ? 1 : result === "black" ? 0 : .5;
      if (a.ranked) delta = Math.round(32 * (score - 1 / (1 + 10 ** ((bs.rating - ws.rating) / 400))));
      for (const [id, s, won, d] of [[a.whitePlayerId, ws, score, delta], [a.blackPlayerId, bs, 1 - score, -delta]] as const)
        await tx.run("UPDATE native_stats SET rating=$1,wins=$2,losses=$3,draws=$4,games=$5 WHERE player_id=$6 AND mode=$7", s.rating + d, s.wins + (won === 1 ? 1 : 0), s.losses + (won === 0 ? 1 : 0), s.draws + (won === .5 ? 1 : 0), s.games + 1, id, a.mode);
    }
    const record = { matchId, mode: a.mode, ranked: a.ranked, whitePlayerId: a.whitePlayerId, blackPlayerId: a.blackPlayerId, whiteName: white.displayName, blackName: black.displayName, result, reason, finalFen, history, startedAt: a.createdAt, completedAt: this.now(), ratingChange: { white: delta, black: -delta } };
    const body = { matchId, result, reason, finalFen, history };
    await tx.run("UPDATE native_matches SET report_json=$1,record_json=$2,status=$3,completed_at=$4 WHERE match_id=$5", report || canonical(body), JSON.stringify(record), result === "aborted" ? "aborted" : "complete", this.now(), matchId);
    await tx.run("DELETE FROM native_tickets WHERE match_id=$1", matchId);
    return record;
  }
}
