import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { createChessServer } from "../server";
import { neutralInput } from "../src/battle/simulation";
import type { Color } from "chess.js";
const delay = (ms = 2) => new Promise((r) => setTimeout(r, ms));
async function harness() {
  let now = 1000000;
  const runtime = await createChessServer({
    database: ":memory:",
    production: true,
    now: () => now,
  });
  await new Promise<void>((r) => runtime.server.listen(0, "127.0.0.1", r));
  const port = (runtime.server.address() as any).port;
  const connect = async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/battle-ws`),
      messages: any[] = [];
    ws.on("message", (raw) => messages.push(JSON.parse(String(raw))));
    await new Promise<void>((r) => ws.once("open", r));
    return {
      ws,
      messages,
      send: (d: any) => ws.send(JSON.stringify(d)),
      next: async (type: string, after = 0, predicate = (d: any) => true) => {
        for (let i = 0; i < 500; i++) {
          const d = messages
            .slice(after)
            .find((d) => d.type === type && predicate(d));
          if (d) return d;
          await delay();
        }
        throw Error(
          `No ${type}: ${JSON.stringify(messages.slice(after)).slice(-800)}`,
        );
      },
    };
  };
  const tick = async (seconds: number) => {
    for (let n = 0; n < seconds * 30; n++) {
      now += 1000 / 30;
      runtime.battle.tick();
      if (n % 3 === 0) await delay(0);
    }
    await delay();
  };
  return {
    runtime,
    port,
    connect,
    tick,
    close: async () => {
      runtime.battle.close();
      runtime.service.close();
      await new Promise<void>((r) => runtime.server.close(() => r()));
    },
  };
}
test("Battle room authority rejects fabricated results and opponent moves; real input-driven combat settles both boards", async () => {
  const h = await harness();
  try {
    assert.equal(
      (
        await (
          await fetch(`http://127.0.0.1:${h.port}/api/battle-capabilities`)
        ).json()
      ).authority,
      "server",
    );
    const a = await h.connect(),
      b = await h.connect();
    a.send({ type: "create", army: "elves" });
    const aw = await a.next("welcome");
    b.send({ type: "join", code: aw.room, army: "skeletons" });
    const bw = await b.next("welcome");
    assert.equal(aw.seat, "w");
    assert.equal(bw.seat, "b");
    assert.notEqual(aw.token, bw.token);
    await a.next("state", 0, (d) => d.started);
    let room = h.runtime.battle.rooms.get(aw.room)!;
    assert.deepEqual(room.host.state.match.armies, {
      w: "elves",
      b: "skeletons",
    });
    b.send({
      type: "command",
      command: { type: "move", from: "e2", to: "e4" },
    });
    await b.next("error");
    assert.equal(room.host.state.match.history.length, 0);
    for (const [who, from, to] of [
      [a, "e2", "e4"],
      [b, "d7", "d5"],
      [a, "e4", "d5"],
    ] as const) {
      const cursor = who.messages.length;
      who.send({ type: "command", command: { type: "move", from, to } });
      await who.next("state", cursor);
    }
    assert.equal(room.host.state.match.phase, "combat");
    assert.equal(room.host.state.match.history.length, 2);
    assert.equal(room.host.state.match.fen.split(" ")[1], "w");
    const before = structuredClone(room.host.state.combat);
    a.send({ type: "victory", winner: "w", damage: 99999 });
    await a.next("error", a.messages.length - 1);
    assert.equal(room.host.state.combat?.fighters.b.hp, before!.fighters.b.hp);
    let seq = 0;
    const attack = neutralInput(),
      defend = neutralInput();
    attack.moveZ = 1;
    attack.sprint = true;
    a.send({
      type: "input",
      sequence: ++seq,
      input: { ...attack, damage: 99999, winner: "w", hp: 99999 },
    });
    await delay();
    await h.tick(0.2);
    assert.equal(room.host.state.combat?.fighters.b.hp, 80);
    // Countdown cannot be skipped by client input. Then both authenticated fighters move toward each other.
    await h.tick(3);
    attack.moveZ = 1;
    attack.sprint = false;
    defend.moveZ = -1;
    let sequenceB = 0;
    for (let i = 0; i < 35; i++) {
      a.send({ type: "input", sequence: ++seq, input: attack });
      b.send({ type: "input", sequence: ++sequenceB, input: defend });
      await delay();
      await h.tick(0.03334);
    }
    attack.moveZ = 0;
    defend.moveZ = 0;
    for (let i = 0; i < 450 && room.host.state.match.phase === "combat"; i++) {
      if (i % 28 === 0) attack.light++;
      a.send({ type: "input", sequence: ++seq, input: attack });
      b.send({ type: "input", sequence: ++sequenceB, input: defend });
      await delay();
      await h.tick(0.03334);
    }
    assert.equal(room.host.state.combat?.winner, "w");
    assert.equal(room.host.state.match.phase, "aftermath");
    await h.tick(3.7);
    assert.equal(room.host.state.match.phase, "board");
    assert.equal(room.host.state.match.history.length, 3);
    assert.equal(room.host.state.match.history[2].outcome, "attacker");
    await a.next("state", 0, (d) => d.snapshot.match.history.length === 3);
    const stateB = await b.next(
      "state",
      0,
      (d) => d.snapshot.match.history.length === 3,
    );
    assert.equal(stateB.snapshot.match.fen, room.host.state.match.fen);
    assert.ok(!JSON.stringify(stateB).includes(aw.token));
    assert.ok(!JSON.stringify(stateB).includes(bw.token));
  } finally {
    await h.close();
  }
});
test("room credentials restore the same seat and combat; disconnected players forfeit after the grace period", async () => {
  const h = await harness();
  try {
    const a = await h.connect(),
      b = await h.connect();
    a.send({ type: "create" });
    const w = await a.next("welcome");
    b.send({ type: "join", code: w.room });
    const k = await b.next("welcome");
    await a.next("state", 0, (d) => d.started);
    const outsider = await h.connect();
    outsider.send({ type: "resume", code: w.room, token: "invented" });
    await outsider.next("error");
    const full = await h.connect();
    full.send({ type: "join", code: w.room });
    await full.next("error");
    b.ws.close();
    await delay(8);
    await h.tick(3);
    const restored = await h.connect();
    restored.send({ type: "resume", code: w.room, token: k.token });
    const ready = await restored.next("welcome");
    assert.equal(ready.seat, "b");
    assert.equal(ready.token, k.token);
    const room = h.runtime.battle.rooms.get(w.room)!;
    assert.equal(room.host.state.match.phase, "board");
    restored.ws.close();
    await delay(8);
    await h.tick(10.2);
    assert.equal(room.host.state.match.result, "1-0");
    assert.equal(room.host.state.match.reason, "Disconnection forfeit");
  } finally {
    await h.close();
  }
});
