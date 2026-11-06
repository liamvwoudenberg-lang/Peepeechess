import test from "node:test";
import assert from "node:assert/strict";
import { OnlineService } from "../server/onlineService";
import { LocalKV } from "../server/onlineStorage";
import { applyAppCors } from "../server/onlineHandler";
import { inviteCodeFrom, normalizeWebsite } from "../src/next/mobile";
function fixture() {
  let now = 1000000;
  const s = new OnlineService(new LocalKV(), () => now);
  return { s, advance: (ms: number) => (now += ms) };
}
async function user(s: OnlineService, army = "royal") {
  const r = await s.handle(
    null,
    { type: "auth", army },
    "test-peer-" + Math.random(),
  );
  return { token: r.messages[0].token, id: r.social.user.id, army };
}
const act = (s: OnlineService, u: any, action: any) =>
  s.handle(u.token, action, "test-peer-" + u.id);
async function invite(s: OnlineService, u: any, color = "w") {
  const r = await act(s, u, {
    type: "invite:create",
    timeControl: "3+2",
    color,
    army: u.army,
  });
  return r.messages.find((m: any) => m.type === "invite:created").invite;
}
test("a private link fixes sides and White’s castle, starts only after both ready, and reconnects without friend codes", async () => {
  const { s } = fixture(),
    host = await user(s, "elves"),
    guest = await user(s, "skeletons"),
    link = await invite(s, host, "b");
  assert.match(link.code, /^[a-f0-9]{32}$/);
  assert.equal(link.status, "waiting");
  const preview = await act(s, guest, {
    type: "invite:inspect",
    code: link.code,
  });
  assert.equal(preview.messages[0].invite.hostColor, "b");
  assert.equal(preview.messages[0].invite.hostOnline, true);
  const joined = await act(s, guest, {
      type: "invite:join",
      code: link.code,
      army: guest.army,
    }),
    g = joined.game;
  assert.equal(g.mode, "friend");
  assert.equal(g.rated, false);
  assert.equal(g.yourColor, "w");
  assert.equal(g.arena, "ossuary");
  assert.deepEqual(g.armies, { w: "skeletons", b: "elves" });
  assert.equal(g.phase, "connecting");
  assert.equal((await act(s, host, { type: "poll" })).game.id, g.id);
  await act(s, host, { type: "game:ready", id: g.id });
  await act(s, guest, { type: "game:ready", id: g.id });
  await act(s, guest, {
    type: "game:move",
    id: g.id,
    from: "e2",
    to: "e4",
    ply: 0,
  });
  assert.equal(
    (await act(s, host, { type: "poll" })).game.history[0].san,
    "e4",
  );
  assert.equal((await act(s, guest, { type: "poll" })).game.id, g.id);
  const outsider = await user(s);
  await assert.rejects(
    act(s, outsider, { type: "invite:join", code: link.code }),
    /already been used/,
  );
  assert.equal((await act(s, host, { type: "poll" })).invite, null);
});
test("one private link admits exactly one guest when two join concurrently", async () => {
  const { s } = fixture(),
    host = await user(s),
    a = await user(s),
    b = await user(s),
    link = await invite(s, host);
  const results = await Promise.allSettled(
    [a, b].map((u) => act(s, u, { type: "invite:join", code: link.code })),
  );
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(results.filter((r) => r.status === "rejected").length, 1);
  const games = await Promise.all(
    [a, b].map((u) => act(s, u, { type: "poll" })),
  );
  assert.equal(games.filter((r) => r.game).length, 1);
});
test("private links enforce host ownership, self-join, cancellation, presence, queue state and expiry", async () => {
  const { s, advance } = fixture(),
    host = await user(s),
    guest = await user(s),
    link = await invite(s, host);
  await assert.rejects(
    act(s, host, { type: "invite:join", code: link.code }),
    /your invite/,
  );
  await assert.rejects(
    act(s, guest, { type: "invite:cancel", code: link.code }),
    /Only the host/,
  );
  advance(31000);
  await assert.rejects(
    act(s, guest, { type: "invite:join", code: link.code }),
    /host is offline/,
  );
  await act(s, host, { type: "poll" });
  await act(s, host, { type: "queue:join", timeControl: "3+2" });
  await assert.rejects(
    act(s, guest, { type: "invite:join", code: link.code }),
    /Cancel matchmaking/,
  );
  await act(s, host, { type: "queue:leave" });
  await act(s, host, { type: "invite:cancel", code: link.code });
  await assert.rejects(
    act(s, guest, { type: "invite:join", code: link.code }),
    /cancelled/,
  );
  const next = await invite(s, host);
  assert.notEqual(link.code, next.code);
  advance(3600001);
  await assert.rejects(
    act(s, guest, { type: "invite:join", code: next.code }),
    /expired/,
  );
  assert.equal(
    (await act(s, guest, { type: "poll", inviteCode: next.code })).invitePreview
      .status,
    "expired",
  );
});
test("creating a replacement link cancels the earlier link", async () => {
  const { s } = fixture(),
    host = await user(s),
    guest = await user(s),
    first = await invite(s, host),
    second = await invite(s, host);
  await assert.rejects(
    act(s, guest, { type: "invite:join", code: first.code }),
    /cancelled/,
  );
  assert.equal((await act(s, host, { type: "poll" })).invite.code, second.code);
});
test("Android WebView CORS permits authenticated app requests and preflight, blocks unrelated websites", () => {
  for (const origin of ["https://localhost", "capacitor://localhost"]) {
    const headers: Record<string, string> = {};
    let status = 0;
    const res = {
      setHeader: (k: string, v: string) => (headers[k] = v),
      status(n: number) {
        status = n;
        return this;
      },
      end() {},
      json() {},
    };
    assert.equal(
      applyAppCors(
        { headers: { origin, host: "chess.example" }, method: "OPTIONS" },
        res,
      ),
      false,
    );
    assert.equal(status, 204);
    assert.equal(headers["Access-Control-Allow-Origin"], origin);
    assert.match(headers["Access-Control-Allow-Headers"], /Authorization/);
    assert.equal(
      applyAppCors(
        { headers: { origin, host: "chess.example" }, method: "POST" },
        res,
      ),
      true,
    );
    assert.equal(
      applyAppCors(
        {
          headers: {
            origin: "https://unrelated.example",
            host: "chess.example",
          },
          method: "POST",
        },
        res,
      ),
      false,
    );
    assert.equal(status, 403);
  }
});
test("mobile friend links parse safely and game websites require HTTPS", () => {
  const code = "a".repeat(32);
  assert.equal(inviteCodeFrom("https://chess.example/?play=" + code), code);
  assert.equal(inviteCodeFrom(code), code);
  assert.equal(inviteCodeFrom("https://chess.example/?play=<script>"), null);
  assert.equal(inviteCodeFrom("not a link"), null);
  assert.equal(
    normalizeWebsite("https://chess.example/?play=" + code),
    "https://chess.example",
  );
  assert.throws(() => normalizeWebsite("http://chess.example"));
  assert.throws(() => normalizeWebsite("https://user:password@chess.example"));
});
