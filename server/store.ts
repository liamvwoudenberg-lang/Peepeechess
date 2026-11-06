import { DatabaseSync } from "node:sqlite";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { mkdirSync } from "node:fs";
import path from "node:path";
import type { Player, ChatMessage } from "../src/next/contracts";

export class Store {
  db: DatabaseSync;
  constructor(
    file = process.env.CHESS_DATABASE || path.resolve(".data/chess.sqlite"),
  ) {
    if (file !== ":memory:") mkdirSync(path.dirname(file), { recursive: true });
    this.db = new DatabaseSync(file);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS players(id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL, name TEXT NOT NULL, code TEXT UNIQUE NOT NULL, blitz INTEGER DEFAULT 1200, rapid INTEGER DEFAULT 1200, games INTEGER DEFAULT 0, spectators INTEGER DEFAULT 1);
      CREATE TABLE IF NOT EXISTS friendships(a TEXT NOT NULL,b TEXT NOT NULL,PRIMARY KEY(a,b));
      CREATE TABLE IF NOT EXISTS requests(id TEXT PRIMARY KEY,from_id TEXT NOT NULL,to_id TEXT NOT NULL,UNIQUE(from_id,to_id));
      CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,from_id TEXT NOT NULL,to_id TEXT NOT NULL,text TEXT NOT NULL,created_at INTEGER NOT NULL,seen INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS games(id TEXT PRIMARY KEY,white_id TEXT NOT NULL,black_id TEXT NOT NULL,status TEXT NOT NULL,snapshot TEXT NOT NULL);
    `);
  }
  player(row: any): Player | null {
    return row
      ? {
          id: row.id,
          name: row.name,
          code: row.code,
          rating: row.rapid,
          blitzRating: row.blitz,
          rapidRating: row.rapid,
          games: row.games,
          allowSpectators: Boolean(row.spectators),
        }
      : null;
  }
  get(id: string) {
    return this.player(
      this.db.prepare("SELECT * FROM players WHERE id=?").get(id),
    );
  }
  byCode(code: string) {
    return this.player(
      this.db
        .prepare("SELECT * FROM players WHERE code=?")
        .get(code.toUpperCase()),
    );
  }
  auth(token: string) {
    return this.player(
      this.db
        .prepare("SELECT * FROM players WHERE token_hash=?")
        .get(createHash("sha256").update(token).digest("hex")),
    );
  }
  create() {
    const token = randomBytes(32).toString("hex");
    const id = randomUUID(),
      code = randomBytes(5).toString("hex").toUpperCase();
    this.db
      .prepare("INSERT INTO players(id,token_hash,name,code) VALUES(?,?,?,?)")
      .run(
        id,
        createHash("sha256").update(token).digest("hex"),
        `Knight ${code.slice(0, 4)}`,
        code,
      );
    return { token, user: this.get(id)! };
  }
  update(id: string, name: string, allowSpectators: boolean) {
    this.db
      .prepare("UPDATE players SET name=?,spectators=? WHERE id=?")
      .run(name, Number(allowSpectators), id);
    return this.get(id)!;
  }
  friends(id: string): Player[] {
    return this.db
      .prepare(
        "SELECT p.* FROM players p JOIN friendships f ON p.id=CASE WHEN f.a=? THEN f.b ELSE f.a END WHERE f.a=? OR f.b=?",
      )
      .all(id, id, id)
      .map((row) => this.player(row)!);
  }
  areFriends(a: string, b: string) {
    return Boolean(
      this.db
        .prepare("SELECT 1 FROM friendships WHERE a=? AND b=?")
        .get(...[a, b].sort()),
    );
  }
  addFriend(a: string, b: string) {
    this.db
      .prepare("INSERT OR IGNORE INTO friendships(a,b) VALUES(?,?)")
      .run(...[a, b].sort());
  }
  requests(id: string) {
    return this.db
      .prepare(
        "SELECT r.*,p.name,p.code FROM requests r JOIN players p ON p.id=CASE WHEN r.from_id=? THEN r.to_id ELSE r.from_id END WHERE from_id=? OR to_id=?",
      )
      .all(id, id, id)
      .map((r: any) => ({
        id: r.id,
        fromId: r.from_id,
        toId: r.to_id,
        name: r.name,
        code: r.code,
      }));
  }
  addRequest(from: string, to: string) {
    this.db
      .prepare("INSERT OR IGNORE INTO requests(id,from_id,to_id) VALUES(?,?,?)")
      .run(randomUUID(), from, to);
  }
  request(id: string) {
    return this.db.prepare("SELECT * FROM requests WHERE id=?").get(id) as
      { id: string; from_id: string; to_id: string } | undefined;
  }
  deleteRequest(id: string) {
    this.db.prepare("DELETE FROM requests WHERE id=?").run(id);
  }
  removeFriend(a: string, b: string) {
    this.db
      .prepare("DELETE FROM friendships WHERE a=? AND b=?")
      .run(...[a, b].sort());
  }
  history(a: string, b: string): ChatMessage[] {
    this.db
      .prepare("UPDATE messages SET seen=1 WHERE from_id=? AND to_id=?")
      .run(b, a);
    return this.db
      .prepare(
        "SELECT * FROM (SELECT * FROM messages WHERE (from_id=? AND to_id=?) OR (from_id=? AND to_id=?) ORDER BY created_at DESC LIMIT 100) ORDER BY created_at ASC",
      )
      .all(a, b, b, a)
      .map((r: any) => ({
        id: r.id,
        fromId: r.from_id,
        toId: r.to_id,
        text: r.text,
        createdAt: r.created_at,
      }));
  }
  unread(a: string, b: string) {
    return Number(
      (
        this.db
          .prepare(
            "SELECT COUNT(*) AS n FROM messages WHERE from_id=? AND to_id=? AND seen=0",
          )
          .get(b, a) as any
      ).n,
    );
  }
  message(fromId: string, toId: string, text: string): ChatMessage {
    const message = {
      id: randomUUID(),
      fromId,
      toId,
      text,
      createdAt: Date.now(),
    };
    this.db
      .prepare(
        "INSERT INTO messages(id,from_id,to_id,text,created_at) VALUES(?,?,?,?,?)",
      )
      .run(message.id, fromId, toId, text, message.createdAt);
    return message;
  }
  save(game: any) {
    this.db
      .prepare(
        "INSERT INTO games(id,white_id,black_id,status,snapshot) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,snapshot=excluded.snapshot",
      )
      .run(
        game.id,
        game.white.id,
        game.black.id,
        game.status,
        JSON.stringify(game),
      );
  }
  active() {
    return this.db
      .prepare("SELECT snapshot FROM games WHERE status='active'")
      .all()
      .map((row: any) => JSON.parse(row.snapshot));
  }
  game(id: string) {
    const row = this.db
      .prepare("SELECT snapshot FROM games WHERE id=?")
      .get(id) as any;
    return row ? JSON.parse(row.snapshot) : null;
  }
  archive(id: string) {
    return this.db
      .prepare(
        "SELECT snapshot FROM games WHERE status='completed' AND (white_id=? OR black_id=?) ORDER BY rowid DESC LIMIT 20",
      )
      .all(id, id)
      .map((row: any) => JSON.parse(row.snapshot));
  }
  finish(game: any) {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const saved = this.game(game.id);
      if (saved?.status === "completed") {
        this.db.exec("ROLLBACK");
        return false;
      }
      if (game.rated) {
        const category =
          game.timeControl.startsWith("3") || game.timeControl.startsWith("5")
            ? "blitz"
            : "rapid";
        const w = this.get(game.white.id)!,
          b = this.get(game.black.id)!;
        const wr = w[`${category}Rating`]!,
          br = b[`${category}Rating`]!;
        const score =
          game.result === "1-0" ? 1 : game.result === "0-1" ? 0 : 0.5;
        const delta = Math.round(
          24 * (score - 1 / (1 + Math.pow(10, (br - wr) / 400))),
        );
        const nextW = Math.max(100, wr + delta),
          nextB = Math.max(100, br - delta);
        this.db
          .prepare(`UPDATE players SET ${category}=?,games=games+1 WHERE id=?`)
          .run(nextW, w.id);
        this.db
          .prepare(`UPDATE players SET ${category}=?,games=games+1 WHERE id=?`)
          .run(nextB, b.id);
        game.ratingDelta = { w: nextW - wr, b: nextB - br };
        game.white = this.get(w.id);
        game.black = this.get(b.id);
      }
      this.save(game);
      this.db.exec("COMMIT");
      return true;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }
}
