import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { createChessServer } from "../server";
import type { Game } from "../src/next/contracts";

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
async function harness() {
  let now = Date.now();
  const runtime = await createChessServer({
    database: ":memory:",
    production: true,
    now: () => now,
  });
  await new Promise<void>((resolve) =>
    runtime.server.listen(0, "127.0.0.1", resolve),
  );
  const port = (runtime.server.address() as any).port;
  async function connect(token?: string) {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`),
      messages: any[] = [];
    ws.on("message", (raw) => messages.push(JSON.parse(String(raw))));
    await new Promise<void>((resolve) => ws.once("open", () => resolve()));
    const next = async (
      type: string,
      after = 0,
      predicate = (m: any) => true,
    ) => {
      for (let i = 0; i < 400; i++) {
        const result = messages
          .slice(after)
          .find((m) => m.type === type && predicate(m));
        if (result) return result;
        await delay(5);
      }
      throw new Error(
        `Missing ${type}: ${JSON.stringify(messages.slice(after))}`,
      );
    };
    const send = (data: any) => ws.send(JSON.stringify(data));
    send({ type: "auth", token });
    const ready = await next("ready");
    const client = {
      ws,
      messages,
      next,
      send,
      user: ready.user,
      token: ready.token || token,
    };
    return client;
  }
  async function friends(a: any, b: any) {
    a.send({ type: "friend:add", code: b.user.code });
    const state = await b.next("social:state", 0, (m: any) =>
      m.requests.some((r: any) => r.fromId === a.user.id),
    );
    const request = state.requests.find((r: any) => r.fromId === a.user.id);
    b.send({ type: "friend:respond", id: request.id, accept: true });
    await a.next("social:state", 0, (m: any) =>
      m.friends.some((f: any) => f.id === b.user.id),
    );
  }
  async function game(
    a: any,
    b: any,
    tc = "10+0",
    rated = false,
  ): Promise<Game> {
    const cursor = a.messages.length;
    if (rated) {
      a.send({ type: "queue:join", timeControl: tc });
      await a.next("queue:state", cursor);
      b.send({ type: "queue:join", timeControl: tc });
    } else {
      a.send({ type: "challenge:send", friendId: b.user.id, timeControl: tc });
      const s = await b.next(
        "social:state",
        0,
        (m: any) => m.challenges.length > 0,
      );
      b.send({
        type: "challenge:respond",
        id: s.challenges[0].id,
        accept: true,
      });
    }
    return (await a.next("game:state", cursor)).game;
  }
  async function close() {
    runtime.service.close();
    await new Promise<void>((resolve) => runtime.server.close(() => resolve()));
  }
  return {
    runtime,
    connect,
    friends,
    game,
    close,
    advance: (ms: number) => {
      now += ms;
    },
  };
}

test("friend requests require acceptance; messages persist and outsiders cannot read or send them", async () => {
  const h = await harness();
  try {
    const a = await h.connect(),
      b = await h.connect(),
      stranger = await h.connect();
    let cursor = stranger.messages.length;
    stranger.send({ type: "chat:history", friendId: a.user.id });
    assert.match((await stranger.next("error", cursor)).message, /friends/);
    await h.friends(a, b);
    const sent = b.messages.length;
    a.send({
      type: "chat:send",
      friendId: b.user.id,
      text: "<b>Good luck</b> & have fun!",
    });
    const m = (await b.next("chat:message", sent)).message;
    assert.equal(m.text, "<b>Good luck</b> & have fun!");
    b.send({ type: "chat:history", friendId: a.user.id });
    const history = await b.next("chat:history");
    assert.equal(history.messages[0].id, m.id);
    a.ws.close();
    await delay(30);
    const restored = await h.connect(a.token);
    assert.equal(restored.user.id, a.user.id);
    assert.equal(restored.user.code, a.user.code);
    restored.send({ type: "chat:history", friendId: b.user.id });
    assert.equal(
      (await restored.next("chat:history")).messages[0].text,
      m.text,
    );
    cursor = b.messages.length;
    b.send({ type: "friend:remove", friendId: a.user.id });
    await b.next("social:state", cursor, (s: any) => s.friends.length === 0);
    cursor = restored.messages.length;
    restored.send({
      type: "chat:send",
      friendId: b.user.id,
      text: "not allowed",
    });
    assert.match((await restored.next("error", cursor)).message, /friends/);
  } finally {
    await h.close();
  }
});

test("friends can challenge and spectate; spectators cannot move or resign; results serialize and persist", async () => {
  const h = await harness();
  try {
    const a = await h.connect(),
      b = await h.connect(),
      watcher = await h.connect();
    await h.friends(a, b);
    await h.friends(a, watcher);
    const game = await h.game(a, b, "untimed");
    assert.equal(game.rated, false);
    watcher.send({ type: "game:spectate", friendId: a.user.id });
    const watched = (await watcher.next("game:state")).game;
    assert.equal(watched.yourColor, null);
    assert.equal(watched.spectators, 1);
    let cursor = watcher.messages.length;
    watcher.send({ type: "game:resign", id: game.id });
    assert.match((await watcher.next("error", cursor)).message, /Only players/);
    assert.equal(h.runtime.service.rooms.get(game.id)!.state.status, "active");
    cursor = watcher.messages.length;
    watcher.send({
      type: "game:move",
      id: game.id,
      from: "e2",
      to: "e4",
      ply: 0,
    });
    assert.match((await watcher.next("error", cursor)).message, /Only players/);
    const white = game.white.id === a.user.id ? a : b,
      black = white === a ? b : a;
    cursor = black.messages.length;
    black.send({
      type: "game:move",
      id: game.id,
      from: "e7",
      to: "e5",
      ply: 0,
    });
    assert.match((await black.next("error", cursor)).message, /not your turn/);
    cursor = watcher.messages.length;
    white.send({
      type: "game:move",
      id: game.id,
      from: "e2",
      to: "e4",
      ply: 0,
    });
    const state = (await watcher.next("game:state", cursor)).game;
    assert.equal(state.history[0].san, "e4");
    assert.equal(state.history.length, 1);
    cursor = watcher.messages.length;
    white.send({ type: "game:emote", id: game.id, emote: "salute" });
    assert.equal(
      (await watcher.next("game:emote", cursor)).event.emote.label,
      "Good luck!",
    );
    cursor = white.messages.length;
    white.send({ type: "game:emote", id: game.id, emote: "oops" });
    assert.match((await white.next("error", cursor)).message, /three seconds/);
    cursor = watcher.messages.length;
    white.send({ type: "game:resign", id: game.id });
    const finished = (await watcher.next("game:state", cursor)).game;
    assert.equal(finished.status, "completed");
    assert.equal(finished.result, "0-1");
    assert.match(finished.pgn, /e4/);
    assert.equal(h.runtime.service.store.game(game.id).status, "completed");
    const rating = white.user.rating;
    assert.equal(h.runtime.service.store.get(white.user.id)!.rating, rating);
  } finally {
    await h.close();
  }
});

test("rated queue uses humans only, applies increments, rejects late moves, and updates ratings once", async () => {
  const h = await harness();
  try {
    const a = await h.connect(),
      b = await h.connect();
    const game = await h.game(a, b, "3+2", true);
    assert.equal(game.rated, true);
    assert.notEqual(game.black.id, "bot_ai");
    const white = game.white.id === a.user.id ? a : b,
      black = white === a ? b : a;
    h.advance(600);
    let cursor = white.messages.length;
    white.send({
      type: "game:move",
      id: game.id,
      from: "e2",
      to: "e4",
      ply: 0,
    });
    const first = (await white.next("game:state", cursor)).game;
    assert.equal(first.clocks.w, 181400);
    assert.equal(first.clocks.b, 180000);
    h.advance(180001);
    cursor = black.messages.length;
    black.send({
      type: "game:move",
      id: game.id,
      from: "e7",
      to: "e5",
      ply: 1,
    });
    const finish = (await black.next("game:state", cursor)).game;
    assert.equal(finish.status, "completed");
    assert.equal(finish.result, "1-0");
    assert.equal(finish.history.length, 1);
    assert.equal(finish.clocks.b, 0);
    assert.equal(finish.ratingDelta.w, 12);
    assert.equal(finish.ratingDelta.b, -12);
    assert.equal(h.runtime.service.store.get(white.user.id)!.blitzRating, 1212);
    assert.equal(h.runtime.service.store.get(black.user.id)!.blitzRating, 1188);
    cursor = white.messages.length;
    white.send({ type: "game:resign", id: game.id });
    await white.next("error", cursor);
    assert.equal(h.runtime.service.store.get(white.user.id)!.blitzRating, 1212);
  } finally {
    await h.close();
  }
});

test("idle flag fall and draw agreements finish correctly; reconnect returns the same live game", async () => {
  const h = await harness();
  try {
    const a = await h.connect(),
      b = await h.connect();
    await h.friends(a, b);
    let game = await h.game(a, b, "5+0");
    const token = a.token;
    a.ws.close();
    await delay(30);
    const resumed = await h.connect(token);
    const state = (await resumed.next("game:state")).game;
    assert.equal(state.id, game.id);
    assert.equal(state.status, "active");
    const before = b.messages.length;
    resumed.send({ type: "game:draw", id: game.id });
    await b.next("game:state", before, (m: any) => Boolean(m.game.drawOffer));
    b.send({ type: "game:draw", id: game.id, accept: true });
    await resumed.next(
      "game:state",
      0,
      (m: any) => m.game.status === "completed",
    );
    assert.equal(h.runtime.service.store.game(game.id).result, "1/2-1/2");
    const cursor = resumed.messages.length;
    resumed.send({ type: "queue:join", timeControl: "3+2" });
    await resumed.next("queue:state", cursor);
    await delay(50);
    assert.equal(h.runtime.service.active(resumed.user.id), undefined);
    b.send({ type: "queue:join", timeControl: "3+2" });
    game = (await resumed.next("game:state", cursor)).game;
    h.advance(180010);
    h.runtime.service.tick();
    assert.equal(h.runtime.service.store.game(game.id).status, "completed");
    assert.equal(h.runtime.service.store.game(game.id).history.length, 0);
  } finally {
    await h.close();
  }
});

test("spectating respects friendship and the friend’s privacy setting", async () => {
  const h = await harness();
  try {
    const a = await h.connect(),
      b = await h.connect(),
      watcher = await h.connect(),
      outsider = await h.connect();
    await h.friends(a, b);
    await h.friends(a, watcher);
    await h.game(a, b);
    let cursor = outsider.messages.length;
    outsider.send({ type: "game:spectate", friendId: a.user.id });
    assert.match(
      (await outsider.next("error", cursor)).message,
      /unavailable or private/,
    );
    watcher.send({ type: "game:spectate", friendId: a.user.id });
    await watcher.next("game:state");
    cursor = watcher.messages.length;
    a.send({ type: "profile:update", name: "Aldric", allowSpectators: false });
    assert.match(
      (await watcher.next("spectate:ended", cursor)).message,
      /no longer available/,
    );
    cursor = watcher.messages.length;
    watcher.send({ type: "game:spectate", friendId: a.user.id });
    await watcher.next("error", cursor);
  } finally {
    await h.close();
  }
});
