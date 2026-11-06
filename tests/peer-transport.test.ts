import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PeerTransport } from "../src/next/PeerTransport";
import { peerSettings } from "../server/onlineHandler";
import api from "../api/chess";
import { LocalKV } from "../server/onlineStorage";
class Channel extends EventEmitter {
  peer = "opponent-peer";
  metadata = { roomId: "room", secret: "test-only-room-secret" };
  open = false;
  closed = false;
  sent: any[] = [];
  close() {
    this.closed = true;
    this.emit("close");
  }
  send(data: any) {
    this.sent.push(data);
  }
}

test("PeerJS accepts only the matched peer and room secret; direct messages trigger authoritative refresh, never replace the board", () => {
  const messages: any[] = [],
    routes: string[] = [],
    t = new PeerTransport(
      (d) => messages.push(d),
      () => {},
      (r) => routes.push(r),
      () => {},
    ) as any;
  t.descriptor = {
    roomId: "room",
    peerId: "opponent-peer",
    secret: "test-only-room-secret",
  };
  let refreshes = 0;
  t.poll = async () => {
    refreshes++;
  };
  const outsider = new Channel();
  outsider.peer = "stranger";
  t.accept(outsider);
  assert.equal(outsider.closed, true);
  const badSecret = new Channel();
  badSecret.metadata.secret = "wrong";
  t.accept(badSecret);
  assert.equal(badSecret.closed, true);
  const c = new Channel();
  t.accept(c);
  c.open = true;
  c.emit("open");
  assert.equal(routes.at(-1), "direct");
  assert.deepEqual(c.sent, [{ type: "sync", roomId: "room" }]);
  c.emit("data", { type: "game:state", game: { fen: "untrusted" } });
  assert.equal(messages.length, 0);
  assert.equal(refreshes, 0);
  c.emit("data", { type: "sync", roomId: "other" });
  assert.equal(refreshes, 0);
  c.emit("data", { type: "sync", roomId: "room" });
  assert.equal(refreshes, 1);
  c.emit("data", { type: "sync", roomId: "room" });
  assert.equal(refreshes, 1);
  c.close();
  assert.equal(routes.at(-1), "server");
  assert.equal(t.channel, null);
});
test("TURN REST credentials are short-lived per player; the shared secret never enters ICE configuration", () => {
  const urls = process.env.TURN_URLS,
    secret = process.env.TURN_SHARED_SECRET,
    ice = process.env.CHESS_ICE_SERVERS;
  try {
    process.env.TURN_URLS = "turns:turn.example.test:443?transport=tcp";
    process.env.TURN_SHARED_SECRET = "test-only-shared-secret";
    delete process.env.CHESS_ICE_SERVERS;
    const config = peerSettings(false)("player-123"),
      turn = config.iceServers.at(-1)!;
    assert.ok(turn.username?.endsWith(":player-123"));
    const expiry = Number(turn.username?.split(":")[0]);
    assert.ok(
      expiry > Date.now() / 1000 + 3500 && expiry < Date.now() / 1000 + 3700,
    );
    assert.equal(turn.credential!.length, 28);
    assert.ok(!JSON.stringify(config).includes("test-only-shared-secret"));
  } finally {
    for (const [key, value] of [
      ["TURN_URLS", urls],
      ["TURN_SHARED_SECRET", secret],
      ["CHESS_ICE_SERVERS", ice],
    ])
      if (value === undefined) delete process.env[key!];
      else process.env[key!] = value;
  }
});
test("Vercel without configured Redis returns an explicit unavailable state instead of ephemeral matchmaking", async () => {
  const url = process.env.UPSTASH_REDIS_REST_URL,
    token = process.env.UPSTASH_REDIS_REST_TOKEN;
  try {
    delete process.env.UPSTASH_REDIS_REST_URL;
    delete process.env.UPSTASH_REDIS_REST_TOKEN;
    let status = 0,
      payload: any;
    const res = {
      setHeader() {},
      status(n: number) {
        status = n;
        return this;
      },
      json(value: any) {
        payload = value;
      },
    };
    await api({ method: "GET" }, res);
    assert.equal(status, 503);
    assert.equal(payload.code, "ONLINE_NOT_CONFIGURED");
    assert.match(payload.error, /play the computer/);
  } finally {
    if (url !== undefined) process.env.UPSTASH_REDIS_REST_URL = url;
    if (token !== undefined) process.env.UPSTASH_REDIS_REST_TOKEN = token;
  }
});
test("storage transactions serialize concurrent updates and roll back failed work", async () => {
  const kv = new LocalKV();
  await kv.set("count", 0);
  await Promise.all(
    Array.from({ length: 30 }, () =>
      kv.run("counter", async (tx) => {
        const n = await tx.get<number>("count");
        tx.set("count", n! + 1);
      }),
    ),
  );
  assert.equal(await kv.get("count"), 30);
  await assert.rejects(
    kv.run("counter", async (tx) => {
      tx.set("count", 99);
      throw Error("rollback");
    }),
  );
  assert.equal(await kv.get("count"), 30);
});
