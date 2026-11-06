import test from "node:test";
import assert from "node:assert/strict";
import { OnlineService } from "../server/onlineService";
import { LocalKV } from "../server/onlineStorage";
function fixture() {
  let now = 1000000;
  const kv = new LocalKV(),
    s = new OnlineService(kv, () => now);
  return { s, kv, advance: (ms: number) => (now += ms) };
}
async function user(s: OnlineService, army = "royal") {
  const r = await s.handle(
    null,
    { type: "auth", army },
    "peer-" + Math.random(),
  );
  return {
    id: r.social.user.id,
    token: r.messages[0].token,
    code: r.social.user.code,
    army,
  };
}
const act = (s: OnlineService, u: any, d: any) =>
  s.handle(u.token, d, "peer-" + u.id);
async function friends(s: OnlineService, a: any, b: any) {
  await act(s, a, { type: "friend:add", code: b.code });
  const response = await act(s, b, { type: "poll" });
  await act(s, b, {
    type: "friend:respond",
    id: response.social.requests[0].id,
    accept: true,
  });
}
async function match(s: OnlineService, a: any, b: any) {
  await act(s, a, { type: "queue:join", timeControl: "3+2", army: a.army });
  const r = await act(s, b, {
    type: "queue:join",
    timeControl: "3+2",
    army: b.army,
  });
  return r.game;
}

test("Peer/Vercel matchmaking pairs humans atomically and fixes both factions and White’s home castle", async () => {
  const { s } = fixture(),
    users = await Promise.all(
      Array.from({ length: 12 }, (_, i) =>
        user(s, ["royal", "elves", "skeletons"][i % 3]),
      ),
    );
  await Promise.all(
    users.map((u) =>
      act(s, u, { type: "queue:join", timeControl: "3+2", army: u.army }),
    ),
  );
  const snapshots = await Promise.all(
      users.map((u) => act(s, u, { type: "poll" })),
    ),
    ids = new Set(snapshots.map((r) => r.game?.id));
  assert.equal(ids.size, 6);
  for (const [i, r] of snapshots.entries()) {
    assert.equal(r.game.phase, "connecting");
    assert.equal(r.game.armies.w, r.game.white.army);
    assert.equal(
      r.game.arena,
      ({ royal: "citadel", elves: "silverwood", skeletons: "ossuary" } as any)[
        r.game.armies.w
      ],
    );
    assert.equal(r.game.history.length, 0);
    assert.equal(
      r.peer.otherId,
      r.game.yourColor === "w" ? r.game.black.id : r.game.white.id,
    );
    assert.ok(r.peer.secret.length >= 40);
    assert.notEqual(r.peer.otherId, users[i].id);
  }
});
test("server validates moves and sequence, starts clocks after both ready, rejects outsiders, and applies increments", async () => {
  const f = fixture(),
    { s } = f,
    a = await user(s),
    b = await user(s, "elves"),
    outsider = await user(s),
    g = await match(s, a, b),
    white = g.white.id === a.id ? a : b,
    black = white === a ? b : a;
  f.advance(20000);
  assert.equal((await act(s, white, { type: "poll" })).game.clocks.w, 180000);
  await assert.rejects(
    act(s, white, {
      type: "game:move",
      id: g.id,
      from: "e2",
      to: "e4",
      ply: 0,
    }),
    /Waiting/,
  );
  await act(s, white, { type: "game:ready", id: g.id });
  await act(s, black, { type: "game:ready", id: g.id });
  f.advance(1000);
  const move = {
    type: "game:move",
    id: g.id,
    from: "e2",
    to: "e4",
    ply: 0,
    requestId: "exactly-once",
  };
  const r = await act(s, white, move);
  assert.equal(r.game.history.length, 1);
  assert.equal(r.game.clocks.w, 181000);
  assert.equal((await act(s, white, move)).game.history.length, 1);
  await assert.rejects(
    act(s, white, { ...move, requestId: "different" }),
    /board changed/,
  );
  await assert.rejects(
    act(s, white, {
      type: "game:move",
      id: g.id,
      from: "d2",
      to: "d4",
      ply: 1,
    }),
    /not your turn/,
  );
  await assert.rejects(
    act(s, outsider, { type: "game:resign", id: g.id }),
    /Only players/,
  );
  await assert.rejects(
    act(s, black, {
      type: "game:move",
      id: g.id,
      from: "a7",
      to: "a4",
      ply: 1,
    }),
    /Invalid move/,
  );
  f.advance(190000);
  const end = await act(s, black, { type: "poll" });
  assert.equal(end.game.status, "completed");
  assert.equal(end.game.result, "1-0");
  assert.equal(end.game.ratingDelta.w, 12);
  await act(s, white, { type: "game:seen", id: g.id });
  assert.equal((await act(s, white, { type: "poll" })).game, null);
});
test("persistent friends, private chat, challenges, spectating, privacy, and emotes work without WebSocket server state", async () => {
  const { s, kv, advance } = fixture(),
    a = await user(s, "elves"),
    b = await user(s, "skeletons"),
    watcher = await user(s),
    stranger = await user(s);
  await friends(s, a, b);
  await friends(s, a, watcher);
  await assert.rejects(
    act(s, stranger, { type: "chat:history", friendId: a.id }),
    /between friends/,
  );
  await act(s, a, {
    type: "chat:send",
    friendId: b.id,
    text: "Meet in the great hall. <script>text</script>",
  });
  const restart = new OnlineService(kv, s.now);
  assert.equal(
    (await act(restart, b, { type: "chat:history", friendId: a.id }))
      .messages[0].messages[0].text,
    "Meet in the great hall. <script>text</script>",
  );
  await act(s, a, {
    type: "challenge:send",
    friendId: b.id,
    timeControl: "5+0",
    army: a.army,
  });
  const invitation = (await act(s, b, { type: "poll" })).social.challenges[0];
  let r = await act(s, b, {
    type: "challenge:respond",
    id: invitation.id,
    accept: true,
  });
  const gid = r.game.id;
  r = await act(s, watcher, { type: "game:spectate", friendId: a.id });
  assert.equal(r.game.yourColor, null);
  assert.equal(r.peer, null);
  assert.ok(r.game.spectators >= 1);
  await assert.rejects(
    act(s, stranger, { type: "game:spectate", friendId: a.id }),
    /private/,
  );
  await assert.rejects(
    act(s, watcher, { type: "game:ready", id: gid }),
    /Only players/,
  );
  await act(s, a, { type: "game:ready", id: gid });
  await act(s, b, { type: "game:ready", id: gid });
  advance(4000);
  await act(s, a, { type: "game:emote", id: gid, emote: "salute" });
  assert.equal(
    (await act(s, watcher, { type: "poll" })).emotes.at(-1).emote.id,
    "salute",
  );
  await assert.rejects(
    act(s, a, { type: "game:emote", id: gid, emote: "salute" }),
    /three seconds/,
  );
  await act(s, a, {
    type: "profile:update",
    name: "Private player",
    allowSpectators: false,
  });
  assert.equal((await act(s, watcher, { type: "poll" })).spectateEnded, true);
});
test("queue cancellation, expired presence, connection timeout, and missing browser credentials never invent an opponent", async () => {
  const { s, advance } = fixture(),
    a = await user(s),
    b = await user(s);
  await act(s, a, { type: "queue:join", timeControl: "5+0" });
  await act(s, a, { type: "queue:leave" });
  assert.equal(
    (await act(s, b, { type: "queue:join", timeControl: "5+0" })).game,
    null,
  );
  await act(s, b, { type: "queue:leave" });
  await act(s, a, { type: "queue:join", timeControl: "5+0" });
  advance(30000);
  assert.equal(
    (await act(s, b, { type: "queue:join", timeControl: "5+0" })).game,
    null,
  );
  await act(s, b, { type: "queue:leave" });
  const g = await match(s, a, b);
  advance(46000);
  const r = await act(s, a, { type: "poll" });
  assert.equal(r.game.status, "completed");
  assert.equal(r.game.ratingDelta, undefined);
  assert.match(r.game.reason, /Connection cancelled/);
  assert.equal(
    (await s.handle("invalid", { type: "auth" }, "")).messages[0].type,
    "auth:error",
  );
});
