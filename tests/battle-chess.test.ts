import test from "node:test";
import assert from "node:assert/strict";
import { Chess, type Color, type PieceSymbol } from "chess.js";
import {
  createBattleMatch,
  attemptBattleMove,
  resolveBattleCapture,
  battleMoves,
  restrictedMoves,
  kingSafe,
  type CaptureIntent,
} from "../src/battle/rules";
import { FIGHTERS, FIXED_DT, ARENA_LIMIT } from "../src/battle/config";
import {
  createCombat,
  neutralInput,
  stepCombat,
  sanitizeInput,
  type CombatState,
  type CombatInput,
} from "../src/battle/simulation";
import { BattleHost } from "../src/battle/session";
const fen = "7k/8/8/4q3/3P4/8/8/7K w - - 0 1";
function intent(a: PieceSymbol = "p", d: PieceSymbol = "q"): CaptureIntent {
  return {
    id: "test:0",
    before: fen,
    from: "d4",
    to: "e5",
    san: "dxe5",
    attacker: { color: "w", role: a },
    defender: { color: "b", role: d, square: "e5" },
  };
}
function fight(a: PieceSymbol = "p", d: PieceSymbol = "q") {
  const s = createCombat(intent(a, d));
  s.countdown = 0;
  s.fighters.w.z = 0;
  s.fighters.b.z = 1.2;
  return s;
}
const input = () => ({ w: neutralInput(), b: neutralInput() });
function advance(
  s: CombatState,
  i: Record<Color, CombatInput>,
  seconds: number,
) {
  for (let t = 0; t < seconds - 1e-8; t += FIXED_DT) stepCombat(s, i, FIXED_DT);
}

test("Battle captures preserve the original board until combat; both outcomes pass one turn without corrupting FEN", () => {
  const original = createBattleMatch(
    { w: "elves", b: "skeletons" },
    fen,
    "test",
  );
  const pending = attemptBattleMove(original, "d4", "e5");
  assert.equal(original.phase, "board");
  assert.equal(pending.fen, fen);
  assert.equal(pending.phase, "combat");
  assert.equal(pending.history.length, 0);
  for (const winner of ["w", "b"] as Color[]) {
    const settled = resolveBattleCapture(pending, pending.pending!.id, winner),
      c = new Chess(settled.fen);
    assert.equal(c.turn(), "b");
    assert.equal(c.get("d4"), undefined);
    assert.equal(c.get("e5")?.color, winner);
    assert.equal(c.get("e5")?.type, winner === "w" ? "p" : "q");
    assert.ok(kingSafe(c, "w"));
    assert.equal(
      settled.history[0].outcome,
      winner === "w" ? "attacker" : "defender",
    );
    assert.throws(
      () => resolveBattleCapture(settled, pending.pending!.id, winner),
      /no longer pending/,
    );
  }
  assert.throws(() => attemptBattleMove(original, "d4", "d7"), /not legal/);
  assert.throws(() => attemptBattleMove(pending, "d4", "d5"), /current battle/);
});
test("captures that expose the moving king on a defender victory are explicitly forbidden, including captures that would escape check", () => {
  for (const f of [
    "4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1",
    "7k/8/8/8/8/8/3Rr3/4K3 w - - 0 1",
  ]) {
    const restriction = restrictedMoves(f).find(
      (m) => m.to === (f.startsWith("4r") ? "e8" : "e2"),
    );
    assert.ok(restriction);
    assert.match(restriction.reason, /king in check/);
    assert.ok(
      !battleMoves(f).some(
        (m) => m.from === restriction.from && m.to === restriction.to,
      ),
    );
    assert.throws(
      () =>
        attemptBattleMove(
          createBattleMatch(undefined, f),
          restriction.from,
          restriction.to,
        ),
      /king in check/,
    );
  }
  const king = "7k/8/8/8/8/8/p7/K7 w - - 0 1";
  assert.ok(!battleMoves(king).some((m) => m.to === "a2"));
  assert.match(restrictedMoves(king)[0].reason, /Kings/);
});
test("en passant, promotion, castling rights and Black move counters resolve explicitly for both duel outcomes", () => {
  const ep = attemptBattleMove(
    createBattleMatch(undefined, "7k/8/8/3pP3/8/8/8/7K w - d6 0 1"),
    "e5",
    "d6",
  );
  assert.equal(ep.pending?.defender.square, "d5");
  for (const color of ["w", "b"] as Color[]) {
    const c = new Chess(resolveBattleCapture(ep, ep.pending!.id, color).fen);
    assert.equal(c.get("e5"), undefined);
    assert.equal(c.get("d5")?.color, color === "b" ? "b" : undefined);
    assert.equal(c.get("d6")?.color, color === "w" ? "w" : undefined);
    assert.equal(c.fen().split(" ")[3], "-");
  }
  for (const promotion of ["q", "r", "b", "n"]) {
    const p = attemptBattleMove(
      createBattleMatch(undefined, "1r5k/P7/8/8/8/8/8/K7 w - - 0 1"),
      "a7",
      "b8",
      promotion,
    );
    assert.equal(
      new Chess(resolveBattleCapture(p, p.pending!.id, "w").fen).get("b8")
        ?.type,
      promotion,
    );
    assert.equal(
      new Chess(resolveBattleCapture(p, p.pending!.id, "b").fen).get("b8")
        ?.type,
      "r",
    );
  }
  const r = attemptBattleMove(
    createBattleMatch(undefined, "k7/7r/8/8/8/8/8/4K2R w K - 0 1"),
    "h1",
    "h7",
  );
  for (const color of ["w", "b"] as Color[])
    assert.equal(
      resolveBattleCapture(r, r.pending!.id, color).fen.split(" ")[2],
      "-",
    );
  const b = attemptBattleMove(
    createBattleMatch(undefined, "k7/8/8/3p4/4N3/8/8/7K b - - 12 24"),
    "d5",
    "e4",
  );
  assert.deepEqual(
    resolveBattleCapture(b, b.pending!.id, "w").fen.split(" ").slice(1),
    ["w", "-", "-", "0", "25"],
  );
  let castle = createBattleMatch(undefined, "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1");
  castle = attemptBattleMove(castle, "e1", "g1");
  const c = new Chess(castle.fen);
  assert.equal(c.get("g1")?.type, "k");
  assert.equal(c.get("f1")?.type, "r");
  assert.equal(castle.phase, "board");
});
test("Battle legal moves define checkmate/stalemate and retain explicit repetition, fifty-move and material draws", () => {
  let m = createBattleMatch();
  for (const [a, b] of [
    ["f2", "f3"],
    ["e7", "e5"],
    ["g2", "g4"],
    ["d8", "h4"],
  ] as const)
    m = attemptBattleMove(m, a, b);
  assert.equal(m.result, "0-1");
  assert.equal(m.reason, "Checkmate");
  assert.equal(new Chess(m.fen).get("e1")?.type, "k");
  assert.equal(
    createBattleMatch(undefined, "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").reason,
    "Stalemate",
  );
  assert.equal(
    createBattleMatch(undefined, "7k/8/8/8/8/8/8/KR6 w - - 100 1").reason,
    "Fifty-move rule",
  );
  assert.equal(
    createBattleMatch(undefined, "7k/8/8/8/8/8/8/K7 w - - 0 1").reason,
    "Insufficient material",
  );
  m = createBattleMatch();
  for (let j = 0; j < 2; j++)
    for (const [a, b] of [
      ["g1", "f3"],
      ["g8", "f6"],
      ["f3", "g1"],
      ["f6", "g8"],
    ] as const)
      m = attemptBattleMove(m, a, b);
  assert.equal(m.reason, "Threefold repetition");
});
test("all six fighters start with the configured equal-access health/stamina and fresh abilities", () => {
  const expected = {
    p: [80, 120, 12, 9],
    n: [125, 110, 22, 7],
    b: [90, 115, 18, 8],
    r: [190, 90, 25, 4],
    q: [135, 115, 24, 9],
    k: [160, 100, 18, 6],
  };
  for (const role of Object.keys(expected) as PieceSymbol[]) {
    const cfg = FIGHTERS[role];
    assert.deepEqual(
      [cfg.hp, cfg.stamina, cfg.damage, cfg.speed],
      expected[role],
    );
    const f = createCombat(intent(role, role)).fighters;
    assert.equal(f.w.hp, f.b.hp);
    assert.equal(f.w.stamina, f.b.stamina);
    assert.equal(f.w.cooldown, 0);
  }
});
test("attacks use active frames, range/facing and a single hit; holding a button never auto-attacks", () => {
  const s = fight(),
    i = input(),
    hp = s.fighters.b.hp;
  i.w.light++;
  stepCombat(s, i);
  assert.equal(s.fighters.b.hp, hp);
  advance(s, i, 0.1);
  assert.equal(s.fighters.b.hp, hp);
  advance(s, i, 0.45);
  assert.equal(s.fighters.b.hp, hp - FIGHTERS.p.damage);
  advance(s, i, 2);
  assert.equal(s.fighters.b.hp, hp - FIGHTERS.p.damage);
  const far = fight();
  far.fighters.b.z = 5;
  const j = input();
  j.w.heavy++;
  advance(far, j, 1);
  assert.equal(far.fighters.b.hp, FIGHTERS.q.hp);
  const facing = fight();
  const k = input();
  k.w.lock = false;
  k.w.yaw = Math.PI;
  facing.fighters.w.yaw = Math.PI;
  k.w.light++;
  advance(facing, k, 0.7);
  assert.equal(facing.fighters.b.hp, FIGHTERS.q.hp);
});
test("timed parries stagger an attacker and empower a counter; early/spammed parries do not extend their active window", () => {
  const s = fight("q", "p"),
    i = input();
  i.w.heavy++;
  advance(s, i, 0.39);
  i.b.parry++;
  advance(s, i, 0.18);
  assert.ok(s.events.some((e) => e.type === "parry"));
  assert.equal(s.fighters.b.hp, FIGHTERS.p.hp);
  assert.equal(s.fighters.w.state, "Staggered");
  assert.ok(s.fighters.b.counter > 0);
  const early = fight("q", "p"),
    j = input();
  j.w.heavy++;
  j.b.parry++;
  advance(early, j, 0.7);
  assert.ok(!early.events.some((e) => e.type === "parry"));
  assert.ok(early.fighters.b.hp < FIGHTERS.p.hp);
});
test("block consumes stamina, sustained heavy pressure breaks guard, and a directional dodge has bounded invulnerability and recovery", () => {
  const s = fight("r", "p"),
    i = input();
  i.b.block = true;
  i.w.heavy++;
  const stamina = s.fighters.b.stamina;
  advance(s, i, 1.3);
  assert.ok(s.events.some((e) => e.type === "block"));
  assert.ok(s.fighters.b.stamina < stamina);
  assert.ok(s.fighters.b.hp > 70);
  s.fighters.b.stamina = 6;
  i.w.heavy++;
  advance(s, i, 1.4);
  assert.ok(s.events.some((e) => e.type === "guardbreak"));
  const d = fight("p", "q"),
    j = input();
  j.w.light++;
  j.b.dodge++;
  advance(d, j, 0.25);
  assert.equal(d.fighters.b.hp, FIGHTERS.q.hp);
  assert.ok(d.fighters.b.stamina < FIGHTERS.q.stamina);
  const stateTime = d.fighters.b.stateTime;
  j.b.dodge++;
  advance(d, j, 0.1);
  assert.ok(d.fighters.b.stateTime > stateTime);
  assert.equal(d.fighters.b.state, "Dodging");
  advance(d, j, 0.6);
  assert.notEqual(d.fighters.b.state, "Dodging");
});
test("stamina gates attacks and sprinting; malicious inputs cannot teleport, inject damage or escape the arena", () => {
  const s = fight(),
    i = input();
  s.fighters.w.stamina = 0;
  i.w.heavy++;
  advance(s, i, 0.3);
  assert.equal(s.fighters.w.attack, null);
  assert.equal(s.fighters.b.hp, FIGHTERS.q.hp);
  const clean = sanitizeInput({
    moveX: Infinity,
    moveZ: 1e9,
    yaw: NaN,
    heavy: NaN,
  } as any);
  assert.deepEqual(
    [clean.moveX, clean.moveZ, clean.yaw, clean.heavy],
    [0, 1, 0, 0],
  );
  const m = fight();
  m.fighters.b.z = -6;
  const j = input();
  j.w.moveX = 1e8;
  j.w.moveZ = 1e8;
  j.w.sprint = true;
  (j.w as any).damage = 1e9;
  advance(m, j, 12);
  assert.ok(Math.abs(m.fighters.w.x) <= ARENA_LIMIT);
  assert.ok(Math.abs(m.fighters.w.z) <= ARENA_LIMIT);
  assert.equal(m.fighters.b.hp, FIGHTERS.q.hp);
  assert.ok(m.fighters.w.stamina < FIGHTERS.p.stamina);
});
test("all six abilities have real mechanics and cooldowns, with Last Stand limited to low health", () => {
  for (const role of ["p", "n", "b", "r", "q", "k"] as PieceSymbol[]) {
    const s = fight(role, "p"),
      i = input();
    if (role === "p") {
      i.w.ability++;
      advance(s, i, 0.05);
      assert.equal(s.fighters.w.cooldown, 0);
      s.fighters.w.hp = 20;
    }
    const x = s.fighters.w.x,
      z = s.fighters.w.z;
    i.w.moveX = 1;
    i.w.ability++;
    advance(s, i, 0.1);
    assert.ok(s.fighters.w.cooldown > 0, role);
    assert.ok(s.fighters.w.stamina < FIGHTERS[role].stamina);
    if (role === "b")
      assert.ok(Math.hypot(s.fighters.w.x - x, s.fighters.w.z - z) > 2);
    if (role === "n") assert.equal(s.fighters.w.attack?.kind, "lunge");
    if (["p", "r", "q"].includes(role)) assert.ok(s.fighters.w.buff > 0);
    if (role === "k") assert.equal(s.fighters.w.state, "Parrying");
    const cooldown = s.fighters.w.cooldown;
    i.w.ability++;
    advance(s, i, 0.1);
    assert.ok(s.fighters.w.cooldown < cooldown);
  }
});
test("a skilled pawn can defeat a queen by parrying and countering; timeout ties favor the defender without random outcomes", () => {
  const s = fight("p", "q"),
    i = input();
  let nextQueen = 0,
    parriedAttack: object | null = null,
    nextPawn = 0;
  for (let n = 0; n < 60 * 60 && !s.winner; n++) {
    const a = s.fighters.w,
      b = s.fighters.b;
    if (
      !b.attack &&
      s.time >= nextQueen &&
      ["Idle", "Moving"].includes(b.state)
    ) {
      i.b.heavy++;
      nextQueen = s.time + 1.8;
    }
    if (
      b.attack &&
      b.attack !== parriedAttack &&
      b.attack.startup - b.attack.time < 0.09 &&
      a.state === "Idle"
    ) {
      i.w.parry++;
      parriedAttack = b.attack;
    }
    if (a.counter > 0 && a.state === "Idle" && s.time >= nextPawn) {
      i.w.heavy++;
      nextPawn = s.time + 1.3;
    }
    stepCombat(s, i);
  }
  assert.equal(s.winner, "w", JSON.stringify(s));
  assert.ok(s.events.some((e) => e.type === "parry") || s.fighters.w.hp > 0);
  const tie = fight();
  tie.remaining = 0.01;
  stepCombat(tie, input());
  assert.equal(tie.winner, "b");
  assert.match(tie.reason, /defender/);
});
test("the match host only resolves a simulated winner once, pauses safely and returns to a valid continuing chess position", () => {
  const h = new BattleHost(undefined, fen);
  h.command({ type: "move", from: "d4", to: "e5" }, "w");
  assert.equal(h.state.match.phase, "combat");
  assert.equal(h.state.match.fen, fen);
  assert.throws(
    () => h.command({ type: "move", from: "a1", to: "a2" }, "w"),
    /battle/,
  );
  h.pause(true);
  const time = h.state.combat!.time;
  h.advance(1);
  assert.equal(h.state.combat!.time, time);
  h.pause(false);
  h.state.combat!.countdown = 0;
  h.state.combat!.remaining = 0.01;
  h.advance(0.1);
  assert.equal(h.state.match.phase, "aftermath");
  assert.equal(h.state.combat!.winner, "b");
  h.command({ type: "continue" }, "w");
  assert.equal(h.state.match.phase, "aftermath");
  for (let i = 0; i < 40; i++) h.advance(0.1);
  assert.equal(h.state.combat, null);
  assert.equal(h.state.match.history.length, 1);
  assert.equal(new Chess(h.state.match.fen).get("e5")?.type, "q");
  assert.equal(new Chess(h.state.match.fen).turn(), "b");
});

test("agreed draws require both seats, expire on a move, and finished duels settle even after a slow presentation frame", () => {
  const h = new BattleHost();
  h.command({ type: "draw" }, "w");
  assert.equal(h.state.match.phase, "board");
  h.command({ type: "move", from: "e2", to: "e4" }, "w");
  assert.deepEqual(h.state.drawOffers, []);
  h.command({ type: "draw" }, "w");
  h.command({ type: "draw" }, "b");
  assert.equal(h.state.match.result, "1/2-1/2");
  assert.equal(h.state.match.reason, "Agreed draw");
  const s = new BattleHost(undefined, fen);
  s.command({ type: "move", from: "d4", to: "e5" }, "w");
  s.state.combat!.countdown = 0;
  s.state.combat!.remaining = 0.01;
  s.advance(0.1);
  assert.equal(s.state.match.phase, "aftermath");
  s.advance(5);
  assert.equal(s.state.combat, null);
  assert.equal(s.state.match.history.length, 1);
});
test("repetition keys ignore en passant when the variant safety restriction makes it unavailable", () => {
  const m = createBattleMatch(undefined, "7k/8/8/3pP3/4K3/8/8/8 w - d6 0 1");
  assert.ok(!battleMoves(m.fen).some((move) => move.isEnPassant()));
  assert.equal(Object.keys(m.repetitions)[0].split(" ")[3], "-");
});

test("fighter facing remains correct and bounded after repeated full orbits", () => {
  for (const turns of [-100, -5, 5, 100]) {
    const s = fight("p", "q"),
      i = input();
    s.fighters.w.yaw = turns * Math.PI * 2 + 0.05;
    stepCombat(s, i);
    assert.ok(Math.abs(s.fighters.w.yaw) < 1e-8);
    i.w.light++;
    advance(s, i, 0.55);
    assert.equal(s.fighters.b.hp, FIGHTERS.q.hp - FIGHTERS.p.damage);
  }
});
