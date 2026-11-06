import { randomBytes, randomUUID, createHash } from "node:crypto";
import { Chess } from "chess.js";
import {
  EMOTES,
  TIME_CONTROLS,
  type Game,
  type Player,
  type PieceSet,
  type TimeControl,
  type ChatMessage,
  type Challenge,
} from "../src/next/contracts.js";
import type { KV, Transaction } from "./onlineStorage.js";

type User = Player & {
  army: PieceSet;
  blitzRating: number;
  rapidRating: number;
  games: number;
};
type Presence = { peerId: string; at: number };
type PrivateInvite = {
  code: string;
  hostId: string;
  timeControl: TimeControl;
  hostColor: "w" | "b" | "random";
  createdAt: number;
  expiresAt: number;
  status: "waiting" | "joined" | "cancelled";
  guestId?: string;
  gameId?: string;
};
type Room = {
  game: Game;
  secret: string;
  ready: string[];
  created: number;
  version: number;
  emotes: any[];
};
function need(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
const clean = (s: unknown, n: number) =>
  typeof s === "string"
    ? s
        .replace(/[\u0000-\u001f\u007f]/g, "")
        .trim()
        .slice(0, n)
    : "";
const hash = (s: string) => createHash("sha256").update(s).digest("hex");
const pair = (a: string, b: string) => [a, b].sort().join(":");
const army = (s: unknown): PieceSet =>
  s === "elves" || s === "skeletons" ? s : "royal";
const home = (s: PieceSet) =>
  s === "elves" ? "silverwood" : s === "skeletons" ? "ossuary" : "citadel";
const replay = (g: Game) => {
  const c = new Chess(g.initialFen);
  for (const m of g.history)
    c.move({ from: m.from, to: m.to, promotion: m.promotion });
  return c;
};
export class OnlineService {
  constructor(
    public kv: KV,
    public now = Date.now,
    public peerConfig: any = {
      host: "0.peerjs.com",
      port: 443,
      path: "/",
      secure: true,
      key: "peerjs",
      iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
    },
  ) {}
  async handle(token: unknown, action: any, peerId = ""): Promise<any> {
    need(
      action && typeof action === "object" && typeof action.type === "string",
      "Invalid action.",
    );
    if (action.type === "auth") return this.auth(token, peerId, action.army);
    need(
      typeof token === "string" && token.length === 64,
      "Sign in again to connect.",
    );
    const id = await this.kv.get<string>("auth:" + hash(token));
    need(
      id,
      "This profile could not be found. Create a new profile in preferences.",
    );
    await this.kv.set(
      "presence:" + id,
      { peerId: clean(peerId, 100), at: this.now() },
      45,
    );
    const rate = await this.kv.run("rate:" + id, async (tx) => {
      const times = ((await tx.get<number[]>("rate:" + id)) || []).filter(
        (t) => this.now() - t < 10000,
      );
      need(times.length < 65, "Please slow down for a moment.");
      times.push(this.now());
      tx.set("rate:" + id, times, 15);
      return true;
    });
    const messages: any[] = [];
    if (action.type !== "poll") {
      const scope =
        action.type.startsWith("invite:") ||
        action.type === "game:seen" ||
        action.type.startsWith("queue:") ||
        action.type.startsWith("challenge:")
          ? "matchmaking"
          : action.type.startsWith("game:") && action.id
            ? "game:" + clean(action.id, 50)
            : "social";
      await this.kv.run(scope, async (tx) => {
        const request =
          typeof action.requestId === "string"
            ? `request:${id}:${clean(action.requestId, 70)}`
            : null;
        if (request && (await tx.get(request))) return;
        const user = await tx.get<User>("user:" + id);
        need(user, "Profile unavailable.");
        await this.action(tx, user, action, messages);
        if (request) tx.set(request, true, 300);
      });
    }
    return {
      ...(await this.snapshot(
        id,
        clean(action.chatWith, 50),
        clean(action.inviteCode, 64),
      )),
      messages: [...messages],
      serverTime: this.now(),
      peerConfig:
        typeof this.peerConfig === "function"
          ? this.peerConfig(id)
          : this.peerConfig,
    };
  }
  async auth(token: unknown, peerId: string, faction: unknown) {
    let id =
        typeof token === "string"
          ? await this.kv.get<string>("auth:" + hash(token))
          : null,
      newToken: string | undefined;
    if (token && !id)
      return {
        messages: [
          {
            type: "auth:error",
            message:
              "This saved profile is unavailable. Create a new profile in preferences.",
          },
        ],
        serverTime: this.now(),
      };
    if (!id) {
      id = randomUUID();
      newToken = randomBytes(32).toString("hex");
      const code = randomBytes(5).toString("hex").toUpperCase(),
        user: User = {
          id,
          name: "Knight " + code.slice(0, 4),
          code,
          rating: 1200,
          blitzRating: 1200,
          rapidRating: 1200,
          games: 0,
          allowSpectators: true,
          army: army(faction),
        };
      await this.kv.run("identity", async (tx) => {
        tx.set("user:" + id, user);
        tx.set("code:" + code, id);
        tx.set("auth:" + hash(newToken!), id);
      });
    }
    await this.kv.set(
      "presence:" + id,
      { peerId: clean(peerId, 100), at: this.now() },
      45,
    );
    return {
      ...(await this.snapshot(id, "")),
      messages: [
        {
          type: "ready",
          token: newToken,
          user: await this.kv.get("user:" + id),
        },
      ],
      peerConfig:
        typeof this.peerConfig === "function"
          ? this.peerConfig(id)
          : this.peerConfig,
      serverTime: this.now(),
    };
  }
  async active(tx: Transaction, id: string) {
    const gid = await tx.get<string>("active:" + id);
    const r = gid ? await tx.get<Room>("room:" + gid) : null;
    return r?.game.status === "active" ? r : null;
  }
  async start(
    tx: Transaction,
    a: User,
    b: User,
    tc: TimeControl,
    rated: boolean,
    hostColor: "w" | "b" | "random" = "random",
  ) {
    need(
      !(await this.active(tx, a.id)) && !(await this.active(tx, b.id)),
      "A player is already playing.",
    );
    Object.assign(a, (await tx.get("rating:" + a.id)) || {});
    Object.assign(b, (await tx.get("rating:" + b.id)) || {});
    a.army = army((await tx.get("army:" + a.id)) || a.army);
    b.army = army((await tx.get("army:" + b.id)) || b.army);
    const white =
        hostColor === "w"
          ? a
          : hostColor === "b"
            ? b
            : Math.random() < 0.5
              ? a
              : b,
      black = white === a ? b : a,
      c = new Chess(),
      control = TIME_CONTROLS.find((x) => x.id === tc)!;
    const game: Game = {
      id: randomUUID(),
      mode: rated ? "online" : "friend",
      initialFen: c.fen(),
      fen: c.fen(),
      history: [],
      white,
      black,
      yourColor: null,
      status: "active",
      phase: "connecting",
      timeControl: tc,
      clocks: {
        w: control.minutes * 60000,
        b: control.minutes * 60000,
        increment: control.increment * 1000,
        turn: "w",
        updatedAt: this.now(),
      },
      rated,
      spectators: 0,
      armies: { w: white.army, b: black.army },
      arena: home(white.army),
    };
    const room: Room = {
      game,
      secret: randomBytes(24).toString("hex"),
      ready: [],
      created: this.now(),
      version: 1,
      emotes: [],
    };
    tx.set("room:" + game.id, room);
    for (const id of [a.id, b.id]) {
      tx.set("active:" + id, game.id);
      tx.del("queued:" + id);
      tx.del("watch:" + id);
      await this.cancelInvite(tx, id);
    }
  }
  async finish(
    tx: Transaction,
    r: Room,
    result: Game["result"],
    reason: string,
  ) {
    const g = r.game;
    if (g.status !== "active") return;
    const c = replay(g);
    if (g.phase !== "connecting" && g.timeControl !== "untimed")
      g.clocks[c.turn()] = Math.max(
        0,
        g.clocks[c.turn()] - (this.now() - g.clocks.updatedAt),
      );
    g.clocks.updatedAt = this.now();
    g.status = "completed";
    g.result = result;
    g.reason = reason;
    g.drawOffer = null;
    r.version++;
    c.header(
      "White",
      g.white.name,
      "Black",
      g.black.name,
      "Result",
      result!,
      "TimeControl",
      g.timeControl,
    );
    g.pgn = c.pgn();
    if (g.rated && g.phase !== "connecting") {
      const [w, b] = await Promise.all([
        tx.get<User>("user:" + g.white.id),
        tx.get<User>("user:" + g.black.id),
      ]);
      if (w && b) {
        Object.assign(w, (await tx.get("rating:" + w.id)) || {});
        Object.assign(b, (await tx.get("rating:" + b.id)) || {});
        const field =
            g.timeControl === "3+2" || g.timeControl === "5+0"
              ? "blitzRating"
              : "rapidRating",
          expected = 1 / (1 + 10 ** ((b[field] - w[field]) / 400)),
          score = result === "1-0" ? 1 : result === "0-1" ? 0 : 0.5,
          delta = Math.round(24 * (score - expected));
        w[field] += delta;
        b[field] -= delta;
        w.rating = w.rapidRating;
        b.rating = b.rapidRating;
        w.games++;
        b.games++;
        g.ratingDelta = { w: delta, b: -delta };
        for (const p of [w, b])
          tx.set("rating:" + p.id, {
            blitzRating: p.blitzRating,
            rapidRating: p.rapidRating,
            rating: p.rating,
            games: p.games,
          });
      }
    }
    for (const id of [g.white.id, g.black.id]) {
      const archive = (await tx.get<string[]>("archive:" + id)) || [];
      tx.set(
        "archive:" + id,
        [g.id, ...archive.filter((x) => x !== g.id)].slice(0, 50),
      );
    }
    tx.set("room:" + g.id, r);
  }
  async expire(tx: Transaction, r: Room) {
    const g = r.game;
    if (g.status !== "active") return false;
    if (g.phase === "connecting") {
      if (this.now() - r.created > 45000) {
        await this.finish(
          tx,
          r,
          "1/2-1/2",
          "Connection cancelled · no rating change",
        );
        return true;
      }
      return false;
    }
    if (
      g.timeControl === "untimed" ||
      g.clocks[g.clocks.turn] - (this.now() - g.clocks.updatedAt) > 0
    )
      return false;
    const c = replay(g),
      winner = c.turn() === "w" ? "b" : "w",
      draw =
        c.isInsufficientMaterial() ||
        c
          .board()
          .flat()
          .filter((p) => p && p.color === winner && p.type !== "k").length ===
          0;
    await this.finish(
      tx,
      r,
      draw ? "1/2-1/2" : winner === "w" ? "1-0" : "0-1",
      draw ? "Time expired · insufficient mating material" : "Time expired",
    );
    return true;
  }
  tc(value: unknown, online = false): TimeControl {
    need(
      TIME_CONTROLS.some((t) => t.id === value) &&
        (!online || value !== "untimed"),
      "Choose a valid time control.",
    );
    return value as TimeControl;
  }
  async cancelInvite(tx: Transaction, id: string) {
    const code = await tx.get<string>("host-invite:" + id);
    if (code) {
      const invite = await tx.get<PrivateInvite>("invite:" + code);
      if (invite?.status === "waiting") {
        invite.status = "cancelled";
        tx.set("invite:" + code, invite, 3600);
      }
      tx.del("host-invite:" + id);
    }
  }
  async publicInvite(
    tx: Pick<Transaction, "get">,
    invite: PrivateInvite,
    id: string,
  ) {
    const host = await tx.get<User>("user:" + invite.hostId),
      presence = await tx.get<Presence>("presence:" + invite.hostId);
    return {
      code: invite.code,
      hostName: host?.name || "Your friend",
      hostArmy: army((await tx.get("army:" + invite.hostId)) || host?.army),
      timeControl: invite.timeControl,
      hostColor: invite.hostColor,
      expiresAt: invite.expiresAt,
      status: invite.status,
      hostOnline: Boolean(presence && this.now() - presence.at < 30000),
      isHost: invite.hostId === id,
    };
  }
  async action(tx: Transaction, user: User, d: any, out: any[]) {
    const id = user.id;
    switch (d.type) {
      case "invite:create": {
        need(!(await this.active(tx, id)), "Finish your current game first.");
        need(
          !(await tx.get("queued:" + id)),
          "Cancel your search before creating a friend link.",
        );
        await this.cancelInvite(tx, id);
        const code = randomBytes(16).toString("hex"),
          invite: PrivateInvite = {
            code,
            hostId: id,
            timeControl: this.tc(d.timeControl),
            hostColor: d.color === "w" || d.color === "b" ? d.color : "random",
            createdAt: this.now(),
            expiresAt: this.now() + 3600000,
            status: "waiting",
          };
        tx.set("army:" + id, army(d.army || user.army));
        tx.set("invite:" + code, invite, 3600);
        tx.set("host-invite:" + id, code, 3600);
        out.push({
          type: "invite:created",
          invite: await this.publicInvite(tx, invite, id),
        });
        break;
      }
      case "invite:cancel": {
        const code = clean(d.code, 64),
          invite = await tx.get<PrivateInvite>("invite:" + code);
        need(
          invite && invite.hostId === id,
          "Only the host can cancel this invite.",
        );
        need(invite.status === "waiting", "This invite has already been used.");
        await this.cancelInvite(tx, id);
        break;
      }
      case "invite:inspect": {
        const invite = await tx.get<PrivateInvite>(
          "invite:" + clean(d.code, 64),
        );
        need(
          invite && invite.expiresAt > this.now(),
          "This invite has expired or is no longer available.",
        );
        out.push({
          type: "invite:preview",
          invite: await this.publicInvite(tx, invite, id),
        });
        break;
      }
      case "invite:join": {
        const code = clean(d.code, 64),
          invite = await tx.get<PrivateInvite>("invite:" + code);
        need(
          invite && invite.expiresAt > this.now(),
          "This invite has expired or is no longer available.",
        );
        need(
          invite.status === "waiting",
          "This invite has already been used or cancelled.",
        );
        need(
          invite.hostId !== id,
          "This is your invite. Share it with a friend in another browser.",
        );
        need(
          !(await this.active(tx, id)) &&
            !(await this.active(tx, invite.hostId)),
          "A player is already in a game.",
        );
        need(
          !(await tx.get("queued:" + id)) &&
            !(await tx.get("queued:" + invite.hostId)),
          "Cancel matchmaking before joining this private game.",
        );
        const presence = await tx.get<Presence>("presence:" + invite.hostId);
        need(
          presence && this.now() - presence.at < 30000,
          "The host is offline. Ask them to reopen the game, then try again.",
        );
        const host = await tx.get<User>("user:" + invite.hostId);
        need(host, "The host is unavailable.");
        tx.set("army:" + id, army(d.army || user.army));
        await this.start(
          tx,
          host,
          user,
          invite.timeControl,
          false,
          invite.hostColor,
        );
        invite.status = "joined";
        invite.guestId = id;
        invite.gameId = (await tx.get<string>("active:" + id))!;
        tx.set("invite:" + code, invite, 3600);
        break;
      }
      case "profile:update": {
        const name = clean(d.name, 24);
        need(name.length >= 2, "Use 2–24 characters for your name.");
        user.name = name;
        user.allowSpectators = d.allowSpectators !== false;
        tx.set("user:" + id, user);
        break;
      }
      case "profile:army":
        tx.set("army:" + id, army(d.army));
        break;
      case "friend:add": {
        const other = await tx.get<string>(
          "code:" + clean(d.code, 10).toUpperCase(),
        );
        need(
          other && other !== id,
          "Enter another player’s valid friend code.",
        );
        const friends = (await tx.get<string[]>("friends:" + id)) || [];
        need(!friends.includes(other), "You are already friends.");
        const requests = (await tx.get<any[]>("requests")) || [];
        const reverse = requests.find(
          (r) => r.fromId === other && r.toId === id,
        );
        if (reverse) {
          tx.set("friends:" + id, [...friends, other]);
          tx.set("friends:" + other, [
            ...new Set([
              ...((await tx.get<string[]>("friends:" + other)) || []),
              id,
            ]),
          ]);
          tx.set(
            "requests",
            requests.filter((r) => r !== reverse),
          );
        } else {
          need(
            requests.filter((r) => r.fromId === id).length < 20,
            "Wait for your friend requests to be answered.",
          );
          const target = await tx.get<User>("user:" + other);
          if (!requests.some((r) => r.fromId === id && r.toId === other))
            requests.push({
              id: randomUUID(),
              fromId: id,
              toId: other,
              name: user.name,
              code: user.code,
              toName: target!.name,
              toCode: target!.code,
            });
          tx.set("requests", requests);
        }
        out.push({
          type: "notice",
          message: reverse ? "Friend added." : "Friend request sent.",
        });
        break;
      }
      case "friend:respond": {
        const requests = (await tx.get<any[]>("requests")) || [],
          request = requests.find((r) => r.id === d.id);
        need(request && request.toId === id, "This request is not yours.");
        if (d.accept === true)
          for (const [a, b] of [
            [id, request.fromId],
            [request.fromId, id],
          ])
            tx.set("friends:" + a, [
              ...new Set([
                ...((await tx.get<string[]>("friends:" + a)) || []),
                b,
              ]),
            ]);
        tx.set(
          "requests",
          requests.filter((r) => r.id !== d.id),
        );
        break;
      }
      case "friend:remove": {
        for (const [a, b] of [
          [id, d.friendId],
          [d.friendId, id],
        ])
          tx.set(
            "friends:" + a,
            ((await tx.get<string[]>("friends:" + a)) || []).filter(
              (x) => x !== b,
            ),
          );
        break;
      }
      case "chat:history":
      case "chat:send": {
        need(
          ((await tx.get<string[]>("friends:" + id)) || []).includes(
            d.friendId,
          ),
          "Chat is available between friends.",
        );
        const key = "chat:" + pair(id, d.friendId),
          list = (await tx.get<ChatMessage[]>(key)) || [];
        if (d.type === "chat:send") {
          const text = clean(d.text, 500);
          need(text, "Write a message first.");
          need(
            this.now() - ((await tx.get<number>("chat-rate:" + id)) || 0) >=
              400,
            "Wait a moment before sending another message.",
          );
          tx.set("chat-rate:" + id, this.now(), 5);
          list.push({
            id: randomUUID(),
            fromId: id,
            toId: d.friendId,
            text,
            createdAt: this.now(),
          });
          tx.set(key, list.slice(-100));
        }
        tx.set("seen:" + id + ":" + d.friendId, this.now());
        out.push({
          type: "chat:history",
          friendId: d.friendId,
          messages: list.slice(-100),
        });
        break;
      }
      case "queue:leave":
        tx.del("queued:" + id);
        break;
      case "queue:join": {
        need(!(await this.active(tx, id)), "Finish your current game first.");
        const tc = this.tc(d.timeControl, true);
        user.army = army(d.army || user.army);
        tx.set("army:" + id, user.army);
        const key = "queue:" + tc,
          queue = (
            (await tx.get<{ id: string; at: number }[]>(key)) || []
          ).filter((q) => q.id !== id && this.now() - q.at < 45000);
        let opponent: User | null = null;
        for (const candidate of queue) {
          const [p, q] = await Promise.all([
            tx.get<Presence>("presence:" + candidate.id),
            tx.get<any>("queued:" + candidate.id),
          ]);
          if (
            !p ||
            this.now() - p.at > 25000 ||
            q?.tc !== tc ||
            (await this.active(tx, candidate.id))
          )
            continue;
          opponent = await tx.get<User>("user:" + candidate.id);
          if (opponent) break;
        }
        if (opponent) {
          tx.set(
            key,
            queue.filter((q) => q.id !== opponent!.id),
          );
          await this.start(tx, user, opponent, tc, true);
        } else {
          queue.push({ id, at: this.now() });
          tx.set(key, queue, 60);
          tx.set("queued:" + id, { tc, at: this.now() }, 45);
        }
        break;
      }
      case "challenge:send": {
        need(
          ((await tx.get<string[]>("friends:" + id)) || []).includes(
            d.friendId,
          ),
          "Add this player as a friend first.",
        );
        need(
          !(await this.active(tx, id)) && !(await this.active(tx, d.friendId)),
          "Finish the current game first.",
        );
        const presence = await tx.get<Presence>("presence:" + d.friendId);
        need(
          presence && this.now() - presence.at < 25000,
          "Your friend is offline.",
        );
        const list = ((await tx.get<Challenge[]>("challenges")) || []).filter(
          (c) => c.expiresAt > this.now(),
        );
        need(
          !list.some((c) => c.fromId === id && c.toId === d.friendId),
          "You already sent a challenge.",
        );
        need(
          list.filter((c) => c.fromId === id).length < 5,
          "Wait for your challenges to be answered.",
        );
        user.army = army(d.army || user.army);
        tx.set("army:" + id, user.army);
        const friend = await tx.get<User>("user:" + d.friendId);
        list.push({
          id: randomUUID(),
          fromId: id,
          toId: d.friendId,
          fromName: user.name,
          toName: friend!.name,
          timeControl: this.tc(d.timeControl),
          expiresAt: this.now() + 60000,
        });
        tx.set("challenges", list);
        break;
      }
      case "challenge:respond":
      case "challenge:cancel": {
        const list = (await tx.get<Challenge[]>("challenges")) || [],
          c = list.find((x) => x.id === d.id);
        need(
          c &&
            c.expiresAt > this.now() &&
            (d.type === "challenge:cancel" ? c.fromId === id : c.toId === id),
          "This challenge is unavailable.",
        );
        tx.set(
          "challenges",
          list.filter((x) => x.id !== d.id),
        );
        if (d.accept === true && d.type === "challenge:respond") {
          need(
            ((await tx.get<string[]>("friends:" + id)) || []).includes(
              c.fromId,
            ),
            "You are no longer friends.",
          );
          await this.start(
            tx,
            (await tx.get<User>("user:" + c.fromId))!,
            user,
            c.timeControl,
            false,
          );
        }
        break;
      }
      case "game:spectate": {
        need(
          !(await this.active(tx, id)) && !(await tx.get("queued:" + id)),
          "Finish your game or leave the queue before watching.",
        );
        const gid = await tx.get<string>("active:" + d.friendId),
          r = gid ? await tx.get<Room>("room:" + gid) : null;
        need(
          r && (await this.canWatch(tx, id, r)),
          "Your friend’s game is unavailable or private.",
        );
        tx.set("watch:" + id, gid);
        tx.set("watchers:" + gid, [
          ...new Set([
            ...((await tx.get<string[]>("watchers:" + gid)) || []),
            id,
          ]),
        ]);
        break;
      }
      case "game:unwatch":
        tx.del("watch:" + id);
        break;
      case "game:seen": {
        const gid = await tx.get<string>("active:" + id),
          r = gid ? await tx.get<Room>("room:" + gid) : null;
        if (gid === d.id && r?.game.status === "completed")
          tx.del("active:" + id);
        break;
      }
      case "game:sync":
        break;
      default: {
        need(typeof d.id === "string", "Missing game.");
        const r = await tx.get<Room>("room:" + d.id);
        need(r && r.game.status === "active", "This game has ended.");
        const g = r.game;
        need(
          g.white.id === id || g.black.id === id,
          "Only players in this game can do that.",
        );
        if (await this.expire(tx, r)) return;
        if (d.type === "game:ready") {
          if (!r.ready.includes(id)) r.ready.push(id);
          if (r.ready.length === 2 && g.phase === "connecting") {
            g.phase = "playing";
            g.clocks.updatedAt = this.now();
          }
          r.version++;
          tx.set("room:" + g.id, r);
          break;
        }
        if (d.type === "game:resign") {
          await this.finish(
            tx,
            r,
            g.phase === "connecting"
              ? "1/2-1/2"
              : g.white.id === id
                ? "0-1"
                : "1-0",
            g.phase === "connecting"
              ? "Connection cancelled · no rating change"
              : "Resignation",
          );
          break;
        }
        need(g.phase !== "connecting", "Waiting for both players to connect.");
        if (d.type === "game:move") {
          need(
            d.ply === g.history.length,
            "The board changed. Refresh your position.",
          );
          const c = replay(g);
          need(
            (c.turn() === "w" ? g.white.id : g.black.id) === id,
            "It is not your turn.",
          );
          need(
            /^[a-h][1-8]$/.test(d.from) && /^[a-h][1-8]$/.test(d.to),
            "Invalid square.",
          );
          const m = c.move({
            from: d.from,
            to: d.to,
            promotion: ["q", "r", "b", "n"].includes(d.promotion)
              ? d.promotion
              : "q",
          });
          if (g.timeControl !== "untimed")
            g.clocks[m.color] =
              Math.max(
                0,
                g.clocks[m.color] - (this.now() - g.clocks.updatedAt),
              ) + g.clocks.increment;
          g.clocks.turn = c.turn();
          g.clocks.updatedAt = this.now();
          g.fen = c.fen();
          g.history.push({
            from: m.from,
            to: m.to,
            promotion: m.promotion,
            san: m.san,
            fen: c.fen(),
          });
          if (g.drawOffer !== id) g.drawOffer = null;
          r.version++;
          if (c.isGameOver())
            await this.finish(
              tx,
              r,
              c.isCheckmate() ? (c.turn() === "w" ? "0-1" : "1-0") : "1/2-1/2",
              c.isCheckmate()
                ? "Checkmate"
                : c.isStalemate()
                  ? "Stalemate"
                  : c.isThreefoldRepetition()
                    ? "Threefold repetition"
                    : c.isInsufficientMaterial()
                      ? "Insufficient material"
                      : "Fifty-move rule",
            );
          else tx.set("room:" + g.id, r);
        } else if (d.type === "game:draw") {
          if (g.drawOffer && g.drawOffer !== id && d.accept === true)
            await this.finish(tx, r, "1/2-1/2", "Draw by agreement");
          else {
            g.drawOffer = d.decline ? null : id;
            r.version++;
            tx.set("room:" + g.id, r);
          }
        } else if (d.type === "game:emote") {
          const e = EMOTES.find((e) => e.id === d.emote);
          need(
            e &&
              this.now() - ((await tx.get<number>("emote-rate:" + id)) || 0) >=
                3000,
            "Wait three seconds between emotes.",
          );
          tx.set("emote-rate:" + id, this.now(), 5);
          r.emotes = [
            ...r.emotes,
            { id: g.id, userId: id, name: user.name, emote: e, at: this.now() },
          ].slice(-8);
          tx.set("room:" + g.id, r);
        } else throw new Error("Unknown action.");
      }
    }
  }
  async canWatch(tx: Pick<Transaction, "get">, id: string, r: Room) {
    const friends = (await tx.get<string[]>("friends:" + id)) || [];
    for (const p of [r.game.white, r.game.black])
      if (
        friends.includes(p.id) &&
        (await tx.get<User>("user:" + p.id))?.allowSpectators
      )
        return true;
    return false;
  }
  async snapshot(id: string, chatWith: string, previewCode = "") {
    const [user, friendIds, requests, challenges, gid, watch, queued, archive] =
      await this.kv.many<any>([
        "user:" + id,
        "friends:" + id,
        "requests",
        "challenges",
        "active:" + id,
        "watch:" + id,
        "queued:" + id,
        "archive:" + id,
      ]);
    const ids: string[] = friendIds || [],
      friends = await this.kv.many<User>(ids.map((x) => "user:" + x)),
      presence = await this.kv.many<Presence>(ids.map((x) => "presence:" + x)),
      active = await this.kv.many<string>(ids.map((x) => "active:" + x)),
      rooms = await this.kv.many<Room>(active.map((x) => "room:" + (x || ""))),
      seen = await this.kv.many<number>(ids.map((x) => "seen:" + id + ":" + x)),
      chats = await this.kv.many<ChatMessage[]>(
        ids.map((x) => "chat:" + pair(id, x)),
      );
    const factions = await this.kv.many<any>(
      [id, ...ids].map((x) => "army:" + x),
    );
    user.army = army(factions[0] || user.army);
    friends.forEach((f, i) => {
      if (f) f.army = army(factions[i + 1] || f.army);
    });
    const ratings = await this.kv.many<any>(
      [id, ...ids].map((x) => "rating:" + x),
    );
    Object.assign(user, ratings[0] || {});
    friends.forEach((f, i) => {
      if (f) Object.assign(f, ratings[i + 1] || {});
    });
    const social = {
      type: "social:state",
      user,
      friends: friends.flatMap((f, i) =>
        f
          ? [
              {
                ...f,
                online: Boolean(
                  presence[i] && this.now() - presence[i]!.at < 25000,
                ),
                gameId: rooms[i]?.game.status === "active" ? active[i] : null,
                canWatch: Boolean(
                  rooms[i]?.game.status === "active" && f.allowSpectators,
                ),
                unread: (chats[i] || []).filter(
                  (m) => m.fromId === f.id && m.createdAt > (seen[i] || 0),
                ).length,
              },
            ]
          : [],
      ),
      requests: (requests || [])
        .filter((r: any) => r.fromId === id || r.toId === id)
        .map((r: any) => ({
          ...r,
          name: r.fromId === id ? r.toName : r.name,
          code: r.fromId === id ? r.toCode : r.code,
        })),
      challenges: (challenges || []).filter(
        (c: any) =>
          c.expiresAt > this.now() && (c.fromId === id || c.toId === id),
      ),
      onlineCount:
        1 + presence.filter((p) => p && this.now() - p.at < 25000).length,
    };
    let room: Room | null =
        gid || watch ? await this.kv.get<Room>("room:" + (gid || watch)) : null,
      ended = false;
    if (room && watch && !gid && !(await this.canWatch(this.kv, id, room))) {
      await this.kv.set("watch:" + id, null);
      room = null;
      ended = true;
    }
    if (room && room.game.status === "active") {
      const g = room.game;
      if (
        (g.phase === "connecting" && this.now() - room.created > 45000) ||
        (g.phase !== "connecting" &&
          g.timeControl !== "untimed" &&
          g.clocks[g.clocks.turn] - (this.now() - g.clocks.updatedAt) <= 0)
      )
        await this.kv.run("game:" + g.id, async (tx) => {
          const fresh = await tx.get<Room>("room:" + g.id);
          if (fresh) await this.expire(tx, fresh);
        });
      room = await this.kv.get<Room>("room:" + room.game.id);
    }
    const archives = (
      await this.kv.many<Room>(
        (archive || []).slice(0, 30).map((x: any) => "room:" + x),
      )
    )
      .filter(Boolean)
      .map((r) => r!.game);
    let peer: any = null,
      game: Game | null = null;
    if (room) {
      const watchers =
          (await this.kv.get<string[]>("watchers:" + room.game.id)) || [],
        wp = await this.kv.many<Presence>(watchers.map((x) => "presence:" + x)),
        wg = await this.kv.many<string>(watchers.map((x) => "watch:" + x));
      game = {
        ...room.game,
        spectators: watchers.filter(
          (_, i) =>
            wp[i] && this.now() - wp[i]!.at < 25000 && wg[i] === room!.game.id,
        ).length,
        yourColor:
          room.game.white.id === id
            ? "w"
            : room.game.black.id === id
              ? "b"
              : null,
      };
      if (game.yourColor && game.status === "active") {
        const other = game.yourColor === "w" ? game.black.id : game.white.id,
          p = await this.kv.get<Presence>("presence:" + other);
        peer = {
          roomId: game.id,
          otherId: other,
          peerId: p?.peerId || "",
          secret: room.secret,
          initiator: game.yourColor === "w",
        };
      }
    }
    if (queued && !game) {
      await this.kv.set("queued:" + id, { ...queued, at: this.now() }, 45);
      await this.kv.run("matchmaking", async (tx) => {
        const list = (await tx.get<any[]>("queue:" + queued.tc)) || [];
        if (list.some((x) => x.id === id))
          tx.set(
            "queue:" + queued.tc,
            list.map((x) => (x.id === id ? { ...x, at: this.now() } : x)),
            60,
          );
      });
    }
    const chat = ids.includes(chatWith)
      ? {
          type: "chat:history",
          friendId: chatWith,
          messages: chats[ids.indexOf(chatWith)] || [],
        }
      : null;
    const ownCode = await this.kv.get<string>("host-invite:" + id),
      ownInvite = ownCode
        ? await this.kv.get<PrivateInvite>("invite:" + ownCode)
        : null,
      preview = previewCode
        ? await this.kv.get<PrivateInvite>("invite:" + previewCode)
        : null;
    return {
      invite:
        ownInvite && ownInvite.expiresAt > this.now()
          ? await this.publicInvite(this.kv, ownInvite, id)
          : null,
      invitePreview: previewCode
        ? preview && preview.expiresAt > this.now()
          ? await this.publicInvite(this.kv, preview, id)
          : { code: previewCode, status: "expired" }
        : null,
      social,
      game,
      peer,
      roomVersion: room?.version,
      emotes: room?.emotes || [],
      queue: {
        type: "queue:state",
        queued: Boolean(queued && !game),
        timeControl: queued?.tc,
      },
      archive: { type: "archive", games: archives },
      chat,
      spectateEnded: ended,
      serverTime: this.now(),
    };
  }
}
