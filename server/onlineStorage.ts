import { randomUUID } from "node:crypto";

/** Keep each provider's URL and write token together; never mix credential pairs. */
export function redisConfig(env: NodeJS.ProcessEnv = process.env) {
  for (const [urlKey, tokenKey] of [
    ["UPSTASH_REDIS_REST_URL", "UPSTASH_REDIS_REST_TOKEN"],
    ["KV_REST_API_URL", "KV_REST_API_TOKEN"],
  ]) {
    const url = env[urlKey]?.trim(),
      token = env[tokenKey]?.trim();
    if (url && token) return { url, token };
  }
  return null;
}

export interface KV {
  get<T = any>(key: string): Promise<T | null>;
  many<T = any>(keys: string[]): Promise<(T | null)[]>;
  set(key: string, value: unknown, ttl?: number): Promise<void>;
  run<T>(scope: string, fn: (tx: Transaction) => Promise<T>): Promise<T>;
}
export interface Transaction {
  get<T = any>(key: string): Promise<T | null>;
  set(key: string, value: unknown, ttl?: number): void;
  del(key: string): void;
}
const PREFIX = "sg:v3:";
export class LocalKV implements KV {
  private values = new Map<string, { value: any; expires: number }>();
  private gates = new Map<string, Promise<void>>();
  constructor(private db?: any) {
    if (db)
      db.exec(
        "CREATE TABLE IF NOT EXISTS online_kv (key TEXT PRIMARY KEY,value TEXT NOT NULL,expires INTEGER NOT NULL)",
      );
  }
  async get<T>(key: string): Promise<T | null> {
    const entry = this.db
      ? this.db
          .prepare("SELECT value,expires FROM online_kv WHERE key=?")
          .get(key)
      : this.values.get(key);
    if (!entry || (entry.expires && entry.expires <= Date.now())) return null;
    return this.db ? JSON.parse(entry.value) : structuredClone(entry.value);
  }
  async many<T>(keys: string[]): Promise<(T | null)[]> {
    return Promise.all(keys.map((k) => this.get<T>(k)));
  }
  async set(key: string, value: any, ttl = 0) {
    this.write(key, value, ttl);
  }
  private write(key: string, value: any, ttl = 0) {
    const expires = ttl ? Date.now() + ttl * 1000 : 0;
    if (this.db)
      this.db
        .prepare(
          "INSERT INTO online_kv(key,value,expires) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,expires=excluded.expires",
        )
        .run(key, JSON.stringify(value), expires);
    else this.values.set(key, { value: structuredClone(value), expires });
  }
  async run<T>(scope: string, fn: (tx: Transaction) => Promise<T>) {
    const prior = this.gates.get(scope) || Promise.resolve();
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r)),
      next = prior.then(() => gate);
    this.gates.set(scope, next);
    await prior;
    const writes = new Map<string, { value: any; ttl: number } | null>();
    try {
      const result = await fn({
        get: async <T>(key: string) => {
          const pending = writes.get(key);
          return writes.has(key)
            ? pending
              ? structuredClone(pending.value)
              : null
            : this.get<T>(key);
        },
        set: (k, v, ttl = 0) => {
          writes.set(k, { value: v, ttl });
        },
        del: (k) => {
          writes.set(k, null);
        },
      });
      if (this.db) this.db.exec("BEGIN IMMEDIATE");
      try {
        for (const [k, v] of writes)
          if (v) this.write(k, v.value, v.ttl);
          else if (this.db)
            this.db.prepare("DELETE FROM online_kv WHERE key=?").run(k);
          else this.values.delete(k);
        if (this.db) this.db.exec("COMMIT");
      } catch (e) {
        if (this.db) this.db.exec("ROLLBACK");
        throw e;
      }
      return result;
    } finally {
      release();
      if (this.gates.get(scope) === next) this.gates.delete(scope);
    }
  }
}
export class RedisKV implements KV {
  constructor(
    private url: string,
    private token: string,
  ) {}
  private async cmd(...command: any[]) {
    const response = await fetch(this.url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(command),
      signal: AbortSignal.timeout(7000),
    });
    if (!response.ok)
      throw new Error("Online storage is temporarily unavailable.");
    const body = await response.json();
    if (body.error) throw new Error("Online storage command failed.");
    return body.result;
  }
  async get<T>(key: string): Promise<T | null> {
    const value = await this.cmd("GET", PREFIX + key);
    return value === null ? null : JSON.parse(value);
  }
  async many<T>(keys: string[]): Promise<(T | null)[]> {
    if (!keys.length) return [];
    return (await this.cmd("MGET", ...keys.map((k) => PREFIX + k))).map(
      (s: string | null) => (s === null ? null : JSON.parse(s)),
    );
  }
  async set(key: string, value: unknown, ttl = 0) {
    await this.cmd(
      "SET",
      PREFIX + key,
      JSON.stringify(value),
      ...(ttl ? ["EX", ttl] : []),
    );
  }
  async run<T>(scope: string, fn: (tx: Transaction) => Promise<T>) {
    const lock = PREFIX + "lock:" + scope,
      token = randomUUID();
    let acquired = false;
    for (let i = 0; i < 25; i++) {
      if (await this.cmd("SET", lock, token, "NX", "PX", 15000)) {
        acquired = true;
        break;
      }
      await new Promise((r) => setTimeout(r, 40 + Math.random() * 40));
    }
    if (!acquired)
      throw new Error("The server is busy. Try again in a moment.");
    const writes = new Map<string, { value: unknown; ttl: number } | null>();
    try {
      const result = await fn({
        get: async <T>(key: string) => {
          const v = writes.get(key);
          return writes.has(key)
            ? v
              ? (v.value as T)
              : null
            : this.get<T>(key);
        },
        set: (k, v, ttl = 0) => {
          writes.set(k, { value: v, ttl });
        },
        del: (k) => {
          writes.set(k, null);
        },
      });
      const changes = [...writes].map(([k, v]) =>
        v
          ? [
              "SET",
              PREFIX + k,
              JSON.stringify(v.value),
              ...(v.ttl ? ["EX", v.ttl] : []),
            ]
          : ["DEL", PREFIX + k],
      );
      const committed = await this.cmd(
        "EVAL",
        "if redis.call('GET',KEYS[1])~=ARGV[1] then return 0 end local changes=cjson.decode(ARGV[2]);for _,cmd in ipairs(changes) do redis.call(unpack(cmd)) end redis.call('DEL',KEYS[1]);return 1",
        1,
        lock,
        token,
        JSON.stringify(changes),
      );
      if (committed !== 1)
        throw new Error("The request expired. Refresh the position and retry.");
      return result;
    } finally {
      await this.cmd(
        "EVAL",
        "if redis.call('GET',KEYS[1])==ARGV[1] then return redis.call('DEL',KEYS[1]) end return 0",
        1,
        lock,
        token,
      ).catch(() => {});
    }
  }
}
