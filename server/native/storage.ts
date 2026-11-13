import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import pg from "pg";

export interface Transaction {
  get<T = any>(sql: string, ...params: unknown[]): Promise<T | undefined>;
  all<T = any>(sql: string, ...params: unknown[]): Promise<T[]>;
  run(sql: string, ...params: unknown[]): Promise<void>;
}
const schema = [
  `CREATE TABLE IF NOT EXISTS native_accounts (player_id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, password_hash TEXT NOT NULL, created_at BIGINT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS native_sessions (token_hash TEXT PRIMARY KEY, player_id TEXT NOT NULL REFERENCES native_accounts(player_id), expires_at BIGINT NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS native_sessions_player ON native_sessions(player_id)`,
  `CREATE TABLE IF NOT EXISTS native_stats (player_id TEXT NOT NULL REFERENCES native_accounts(player_id), mode TEXT NOT NULL CHECK (mode IN ('classic','battle')), rating INTEGER NOT NULL DEFAULT 1200, wins INTEGER NOT NULL DEFAULT 0, losses INTEGER NOT NULL DEFAULT 0, draws INTEGER NOT NULL DEFAULT 0, games INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(player_id,mode))`,
  `CREATE TABLE IF NOT EXISTS native_matches (match_id TEXT PRIMARY KEY, white_player_id TEXT NOT NULL REFERENCES native_accounts(player_id), black_player_id TEXT NOT NULL REFERENCES native_accounts(player_id), allocation_json TEXT NOT NULL, report_json TEXT, record_json TEXT, status TEXT NOT NULL, created_at BIGINT NOT NULL, completed_at BIGINT, last_seen BIGINT NOT NULL DEFAULT 0)`,
  `CREATE INDEX IF NOT EXISTS native_matches_white ON native_matches(white_player_id,created_at)`,
  `CREATE INDEX IF NOT EXISTS native_matches_black ON native_matches(black_player_id,created_at)`,
  `CREATE TABLE IF NOT EXISTS native_queue (player_id TEXT PRIMARY KEY REFERENCES native_accounts(player_id), mode TEXT NOT NULL, ranked INTEGER NOT NULL, initial_ms INTEGER NOT NULL, increment_ms INTEGER NOT NULL, entered_at BIGINT NOT NULL, touched_at BIGINT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS native_invites (code TEXT PRIMARY KEY, player_id TEXT NOT NULL UNIQUE REFERENCES native_accounts(player_id), options_json TEXT NOT NULL, expires_at BIGINT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS native_tickets (token_hash TEXT PRIMARY KEY, player_id TEXT NOT NULL REFERENCES native_accounts(player_id), match_id TEXT NOT NULL REFERENCES native_matches(match_id), expires_at BIGINT NOT NULL)`,
  // Friends. One row per pair: the requester asked, the addressee accepts (status becomes 'accepted'). Pair uniqueness across
  // both directions is enforced by the service inside its transaction.
  `CREATE TABLE IF NOT EXISTS native_friendships (requester_id TEXT NOT NULL REFERENCES native_accounts(player_id), addressee_id TEXT NOT NULL REFERENCES native_accounts(player_id), status TEXT NOT NULL CHECK (status IN ('pending','accepted')), created_at BIGINT NOT NULL, PRIMARY KEY(requester_id,addressee_id))`,
  `CREATE INDEX IF NOT EXISTS native_friendships_addressee ON native_friendships(addressee_id,status)`,
  // A friend challenge is a private invite that only one player may join. Deleting the invite (cancel, expiry, matched,
  // sender queues elsewhere) removes the challenge with it, so no separate cleanup exists.
  `CREATE TABLE IF NOT EXISTS native_challenges (code TEXT PRIMARY KEY REFERENCES native_invites(code) ON DELETE CASCADE, target_player_id TEXT NOT NULL REFERENCES native_accounts(player_id), side TEXT NOT NULL CHECK (side IN ('white','black','random')))`,
  `CREATE INDEX IF NOT EXISTS native_challenges_target ON native_challenges(target_player_id)`,
  `CREATE TABLE IF NOT EXISTS native_presence (player_id TEXT PRIMARY KEY REFERENCES native_accounts(player_id), seen_at BIGINT NOT NULL)`,
];

/** SQL is parameterized. PostgreSQL transactions use a shared advisory lock to
 * serialize matchmaking/Elo across API replicas; SQLite is development-only. */
export class NativeStorage {
  private sqlite?: DatabaseSync;
  private pool?: pg.Pool;
  private gate: Promise<unknown> = Promise.resolve();
  readonly kind: "postgresql" | "sqlite";
  constructor(readonly options: { databaseUrl?: string; filename?: string }) {
    this.kind = options.databaseUrl ? "postgresql" : "sqlite";
    if (options.databaseUrl) this.pool = new pg.Pool({ connectionString: options.databaseUrl, max: 8, connectionTimeoutMillis: 5000, idleTimeoutMillis: 30000 });
    else {
      const filename = options.filename || ".data/native-application.sqlite";
      if (filename !== ":memory:") mkdirSync(dirname(filename), { recursive: true });
      this.sqlite = new DatabaseSync(filename);
      this.sqlite.exec("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL;");
    }
  }
  async initialize() {
    await this.transaction(async tx => { for (const sql of schema) await tx.run(sql); });
  }
  async transaction<T>(fn: (tx: Transaction) => Promise<T>): Promise<T> {
    if (this.pool) {
      const client = await this.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT pg_advisory_xact_lock(192837465)");
        const tx: Transaction = {
          get: async (sql, ...params) => (await client.query(sql, params)).rows[0],
          all: async (sql, ...params) => (await client.query(sql, params)).rows,
          run: async (sql, ...params) => { await client.query(sql, params); },
        };
        const result = await fn(tx); await client.query("COMMIT"); return result;
      } catch (error) { await client.query("ROLLBACK"); throw error; }
      finally { client.release(); }
    }
    const previous = this.gate;
    let release!: () => void;
    this.gate = new Promise<void>(resolve => { release = resolve; });
    await previous;
    try {
      this.sqlite!.exec("BEGIN IMMEDIATE");
      const sql = (statement: string) => statement.replace(/\$\d+/g, "?");
      const tx: Transaction = {
        get: async (statement, ...params) => this.sqlite!.prepare(sql(statement)).get(...params as any[]) as any,
        all: async (statement, ...params) => this.sqlite!.prepare(sql(statement)).all(...params as any[]) as any[],
        run: async (statement, ...params) => { this.sqlite!.prepare(sql(statement)).run(...params as any[]); },
      };
      try { const result = await fn(tx); this.sqlite!.exec("COMMIT"); return result; }
      catch (error) { this.sqlite!.exec("ROLLBACK"); throw error; }
    } finally { release(); }
  }
  async close() { if (this.pool) await this.pool.end(); this.sqlite?.close(); }
}
