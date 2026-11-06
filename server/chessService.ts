import { randomUUID } from "node:crypto";
import { WebSocket, WebSocketServer } from "ws";
import { Chess } from "chess.js";
import type { Server } from "node:http";
import { Store } from "./store";
import {
  EMOTES,
  TIME_CONTROLS,
  type Game,
  type TimeControl,
  type Challenge,
  type Player,
} from "../src/next/contracts";

type Client = {
  ws: WebSocket;
  userId: string | null;
  watching: string | null;
  events: number[];
  lastChat: number;
  lastEmote: number;
};
type Room = { state: Game; chess: Chess };
function requireThat(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
const clean = (value: unknown, max: number) =>
  typeof value === "string"
    ? value
        .replace(/[\u0000-\u001f\u007f]/g, "")
        .trim()
        .slice(0, max)
    : "";

export class ChessService {
  wss: WebSocketServer;
  clients = new Set<Client>();
  rooms = new Map<string, Room>();
  queue = new Map<string, TimeControl>();
  challenges = new Map<string, Challenge>();
  timer: ReturnType<typeof setInterval>;
  closing = false;
  constructor(
    public store: Store,
    server: Server,
    public now: () => number = Date.now,
  ) {
    for (const state of store.active()) {
      const chess = new Chess(state.initialFen);
      for (const move of state.history)
        chess.move({ from: move.from, to: move.to, promotion: move.promotion });
      this.rooms.set(state.id, { state, chess });
    }
    this.wss = new WebSocketServer({ noServer: true, maxPayload: 4096 });
    server.on("upgrade", (req, socket, head) => {
      if (
        req.url?.startsWith("/peerjs/") ||
        req.url?.split("?")[0] === "/battle-ws"
      )
        return;
      // Vite owns its development hot-reload socket; the game owns /ws.
      if (
        process.env.NODE_ENV !== "production" &&
        req.headers["sec-websocket-protocol"] === "vite-hmr"
      )
        return;
      try {
        if (
          req.url !== "/ws" ||
          (req.headers.origin &&
            new URL(req.headers.origin).host !== req.headers.host)
        ) {
          socket.destroy();
          return;
        }
        this.wss.handleUpgrade(req, socket, head, (ws) =>
          this.wss.emit("connection", ws),
        );
      } catch {
        socket.destroy();
      }
    });
    this.wss.on("connection", (ws) => {
      const client: Client = {
        ws,
        userId: null,
        watching: null,
        events: [],
        lastChat: 0,
        lastEmote: 0,
      };
      this.clients.add(client);
      const authTimeout = setTimeout(() => {
        if (!client.userId) ws.close(1008, "Sign in required");
      }, 8000);
      ws.on("message", (raw) => {
        try {
          const data = JSON.parse(String(raw));
          requireThat(
            data && typeof data === "object" && typeof data.type === "string",
            "Invalid message.",
          );
          const timestamp = this.now();
          client.events = client.events.filter((t) => timestamp - t < 10000);
          requireThat(
            client.events.length < 60,
            "Too many requests. Please slow down.",
          );
          client.events.push(timestamp);
          this.handle(client, data);
        } catch (error) {
          this.send(client, {
            type: "error",
            message: error instanceof Error ? error.message : "Request failed.",
          });
        }
      });
      ws.on("error", () => {});
      ws.on("close", () => {
        clearTimeout(authTimeout);
        this.clients.delete(client);
        if (client.userId && !this.online(client.userId))
          this.queue.delete(client.userId);
        if (client.watching) this.broadcastGame(client.watching);
        this.socialAll();
      });
    });
    this.timer = setInterval(() => this.tick(), 200);
    this.timer.unref();
  }
  send(client: Client, data: unknown) {
    if (client.ws.readyState === WebSocket.OPEN)
      client.ws.send(
        JSON.stringify({ ...(data as object), serverTime: this.now() }),
      );
  }
  sendTo(id: string, data: unknown) {
    for (const c of this.clients) if (c.userId === id) this.send(c, data);
  }
  online(id: string) {
    return [...this.clients].some(
      (c) => c.userId === id && c.ws.readyState === WebSocket.OPEN,
    );
  }
  active(id: string) {
    return [...this.rooms.values()].find(
      (r) =>
        r.state.status === "active" &&
        (r.state.white.id === id || r.state.black.id === id),
    );
  }
  publicGame(room: Room, id: string): Game {
    return {
      ...room.state,
      yourColor:
        room.state.white.id === id
          ? "w"
          : room.state.black.id === id
            ? "b"
            : null,
      spectators: [...this.clients].filter((c) => c.watching === room.state.id)
        .length,
    };
  }
  snapshot(client: Client) {
    const id = client.userId!;
    const friends = this.store.friends(id).map((friend) => ({
      ...friend,
      online: this.online(friend.id),
      gameId: this.active(friend.id)?.state.id || null,
      canWatch: Boolean(this.active(friend.id) && friend.allowSpectators),
      unread: this.store.unread(id, friend.id),
    }));
    this.send(client, {
      type: "social:state",
      user: this.store.get(id),
      friends,
      requests: this.store.requests(id),
      challenges: [...this.challenges.values()].filter(
        (x) => x.fromId === id || x.toId === id,
      ),
      onlineCount: new Set(
        [...this.clients].filter((c) => c.userId).map((c) => c.userId),
      ).size,
    });
  }
  socialAll() {
    if (this.closing) return;
    for (const c of this.clients) if (c.userId) this.snapshot(c);
  }
  member(client: Client, gameId: unknown): Room {
    requireThat(typeof gameId === "string", "Missing game.");
    const room = this.rooms.get(gameId);
    requireThat(room && room.state.status === "active", "This game has ended.");
    requireThat(
      room.state.white.id === client.userId ||
        room.state.black.id === client.userId,
      "Only players in this game can do that.",
    );
    return room;
  }
  tc(value: unknown, online = false): TimeControl {
    requireThat(
      TIME_CONTROLS.some((t) => t.id === value) &&
        (!online || value !== "untimed"),
      "Choose a valid time control.",
    );
    return value as TimeControl;
  }
  clock(room: Room) {
    if (room.state.status !== "active" || room.state.timeControl === "untimed")
      return false;
    const clocks = room.state.clocks;
    if (
      clocks[room.chess.turn()] - Math.max(0, this.now() - clocks.updatedAt) >
      0
    )
      return false;
    clocks[room.chess.turn()] = 0;
    clocks.updatedAt = this.now();
    const winner = room.chess.turn() === "w" ? "b" : "w";
    const opponent = room.chess
      .board()
      .flat()
      .filter((p) => p && p.color === winner && p.type !== "k");
    const draw = opponent.length === 0 || room.chess.isInsufficientMaterial();
    this.finish(
      room,
      draw ? "1/2-1/2" : winner === "w" ? "1-0" : "0-1",
      draw ? "Time expired · insufficient mating material" : "Time expired",
    );
    return true;
  }
  finish(room: Room, result: Game["result"], reason: string) {
    if (room.state.status !== "active") return;
    const clocks = room.state.clocks;
    if (room.state.timeControl !== "untimed")
      clocks[room.chess.turn()] = Math.max(
        0,
        clocks[room.chess.turn()] - Math.max(0, this.now() - clocks.updatedAt),
      );
    clocks.updatedAt = this.now();
    room.state.status = "completed";
    room.state.result = result;
    room.state.reason = reason;
    room.state.drawOffer = null;
    room.chess.header(
      "White",
      room.state.white.name,
      "Black",
      room.state.black.name,
      "Result",
      result!,
      "TimeControl",
      room.state.timeControl,
    );
    room.state.pgn = room.chess.pgn();
    this.store.finish(room.state);
    this.broadcastGame(room.state.id);
    for (const player of [room.state.white, room.state.black])
      this.sendTo(player.id, {
        type: "archive",
        games: this.store.archive(player.id),
      });
    this.socialAll();
  }
  broadcastGame(id: string) {
    const room = this.rooms.get(id);
    if (!room) return;
    for (const c of this.clients)
      if (
        c.userId &&
        (c.userId === room.state.white.id ||
          c.userId === room.state.black.id ||
          c.watching === id)
      )
        this.send(c, {
          type: "game:state",
          game: this.publicGame(room, c.userId),
        });
  }
  start(a: Player, b: Player, timeControl: TimeControl, rated: boolean) {
    requireThat(
      !this.active(a.id) && !this.active(b.id),
      "A player is already in a game.",
    );
    const white = Math.random() < 0.5 ? a : b,
      black = white === a ? b : a;
    const tc = TIME_CONTROLS.find((t) => t.id === timeControl)!;
    const chess = new Chess();
    const state: Game = {
      id: randomUUID(),
      mode: rated ? "online" : "friend",
      initialFen: chess.fen(),
      fen: chess.fen(),
      history: [],
      white,
      black,
      yourColor: null,
      status: "active",
      timeControl,
      clocks: {
        w: tc.minutes * 60000,
        b: tc.minutes * 60000,
        increment: tc.increment * 1000,
        updatedAt: this.now(),
        turn: "w",
      },
      rated,
      spectators: 0,
    };
    this.queue.delete(a.id);
    this.queue.delete(b.id);
    for (const id of [a.id, b.id])
      this.sendTo(id, { type: "queue:state", queued: false });
    for (const [id, c] of this.challenges)
      if ([a.id, b.id].includes(c.fromId) || [a.id, b.id].includes(c.toId))
        this.challenges.delete(id);
    for (const c of this.clients)
      if (c.userId === a.id || c.userId === b.id) c.watching = null;
    const room = { state, chess };
    this.rooms.set(state.id, room);
    this.store.save(state);
    this.broadcastGame(state.id);
    this.socialAll();
  }
  tick() {
    for (const room of this.rooms.values()) this.clock(room);
    let changed = false;
    for (const [id, challenge] of this.challenges)
      if (challenge.expiresAt <= this.now()) {
        this.challenges.delete(id);
        changed = true;
      }
    if (changed) this.socialAll();
  }
  handle(client: Client, data: any) {
    if (data.type === "auth") {
      requireThat(!client.userId, "Already signed in.");
      const fresh = data.token ? null : this.store.create();
      const user =
        fresh?.user ||
        (typeof data.token === "string" ? this.store.auth(data.token) : null);
      if (!user) {
        this.send(client, {
          type: "auth:error",
          message:
            "This saved profile could not be found. Create a new profile to continue.",
        });
        return;
      }
      client.userId = user.id;
      this.send(client, { type: "ready", token: fresh?.token, user });
      const active = this.active(user.id);
      if (active) {
        this.clock(active);
        this.send(client, {
          type: "game:state",
          game: this.publicGame(active, user.id),
        });
      }
      this.send(client, {
        type: "archive",
        games: this.store.archive(user.id),
      });
      this.socialAll();
      return;
    }
    requireThat(client.userId, "Sign in first.");
    const id = client.userId;
    switch (data.type) {
      case "profile:update": {
        const name = clean(data.name, 24);
        requireThat(name.length >= 2, "Use a name with 2–24 characters.");
        this.store.update(id, name, data.allowSpectators !== false);
        this.checkSpectators();
        this.socialAll();
        break;
      }
      case "friend:add": {
        const friend = this.store.byCode(clean(data.code, 10));
        requireThat(
          friend && friend.id !== id,
          "Enter another player’s valid friend code.",
        );
        requireThat(
          !this.store.areFriends(id, friend.id),
          "You are already friends.",
        );
        const reverse = this.store
          .requests(id)
          .find((r) => r.fromId === friend.id && r.toId === id);
        if (reverse) {
          this.store.addFriend(id, friend.id);
          this.store.deleteRequest(reverse.id);
        } else this.store.addRequest(id, friend.id);
        this.socialAll();
        this.send(client, {
          type: "notice",
          message: reverse ? "Friend added." : "Friend request sent.",
        });
        break;
      }
      case "friend:respond": {
        const request = this.store.request(clean(data.id, 40));
        requireThat(
          request && request.to_id === id,
          "This friend request is not yours.",
        );
        if (data.accept === true) this.store.addFriend(id, request.from_id);
        this.store.deleteRequest(request.id);
        this.socialAll();
        break;
      }
      case "friend:remove": {
        const friendId = clean(data.friendId, 40);
        this.store.removeFriend(id, friendId);
        for (const [cid, c] of this.challenges)
          if (
            (c.fromId === id && c.toId === friendId) ||
            (c.fromId === friendId && c.toId === id)
          )
            this.challenges.delete(cid);
        this.checkSpectators();
        this.socialAll();
        break;
      }
      case "chat:history": {
        requireThat(
          this.store.areFriends(id, data.friendId),
          "Chat is available between friends.",
        );
        this.send(client, {
          type: "chat:history",
          friendId: data.friendId,
          messages: this.store.history(id, data.friendId),
        });
        this.snapshot(client);
        break;
      }
      case "chat:send": {
        requireThat(
          this.store.areFriends(id, data.friendId),
          "Chat is available between friends.",
        );
        const text = clean(data.text, 500);
        requireThat(
          text && this.now() - client.lastChat >= 400,
          "Please wait a moment before sending another message.",
        );
        client.lastChat = this.now();
        const message = this.store.message(id, data.friendId, text);
        this.sendTo(id, { type: "chat:message", message });
        this.sendTo(data.friendId, { type: "chat:message", message });
        this.socialAll();
        break;
      }
      case "challenge:send": {
        requireThat(
          this.store.areFriends(id, data.friendId),
          "Add this player as a friend first.",
        );
        requireThat(
          !this.active(id) && !this.active(data.friendId),
          "Finish the current game first.",
        );
        requireThat(
          this.online(data.friendId),
          "Your friend is offline. Send them a message first.",
        );
        requireThat(
          ![...this.challenges.values()].some(
            (c) => c.fromId === id && c.toId === data.friendId,
          ),
          "You already sent this friend a challenge.",
        );
        requireThat(
          [...this.challenges.values()].filter((c) => c.fromId === id).length <
            5,
          "Wait for your challenges to be answered.",
        );
        const challenge: Challenge = {
          id: randomUUID(),
          fromId: id,
          toId: data.friendId,
          fromName: this.store.get(id)!.name,
          toName: this.store.get(data.friendId)!.name,
          timeControl: this.tc(data.timeControl),
          expiresAt: this.now() + 60000,
        };
        this.challenges.set(challenge.id, challenge);
        this.socialAll();
        break;
      }
      case "challenge:respond": {
        const c = this.challenges.get(data.id);
        requireThat(
          c && c.toId === id && c.expiresAt > this.now(),
          "This challenge has expired.",
        );
        this.challenges.delete(c.id);
        if (data.accept === true)
          this.start(
            this.store.get(c.fromId)!,
            this.store.get(id)!,
            c.timeControl,
            false,
          );
        else this.socialAll();
        break;
      }
      case "challenge:cancel": {
        const c = this.challenges.get(data.id);
        requireThat(c && c.fromId === id, "This challenge is not yours.");
        this.challenges.delete(c.id);
        this.socialAll();
        break;
      }
      case "queue:join": {
        requireThat(!this.active(id), "Finish your current game first.");
        const tc = this.tc(data.timeControl, true);
        this.queue.set(id, tc);
        const opponent = [...this.queue]
          .filter(
            ([uid, t]) =>
              uid !== id && t === tc && this.online(uid) && !this.active(uid),
          )
          .sort(
            ([a], [b]) =>
              Math.abs(this.store.get(a)!.rating - this.store.get(id)!.rating) -
              Math.abs(this.store.get(b)!.rating - this.store.get(id)!.rating),
          )[0];
        if (opponent)
          this.start(
            this.store.get(id)!,
            this.store.get(opponent[0])!,
            tc,
            true,
          );
        else
          this.send(client, {
            type: "queue:state",
            queued: true,
            timeControl: tc,
          });
        break;
      }
      case "queue:leave":
        this.queue.delete(id);
        this.send(client, { type: "queue:state", queued: false });
        break;
      case "game:move": {
        const room = this.member(client, data.id);
        if (this.clock(room)) return;
        requireThat(
          (room.chess.turn() === "w"
            ? room.state.white.id
            : room.state.black.id) === id,
          "It is not your turn.",
        );
        requireThat(
          typeof data.from === "string" &&
            /^[a-h][1-8]$/.test(data.from) &&
            typeof data.to === "string" &&
            /^[a-h][1-8]$/.test(data.to),
          "Invalid square.",
        );
        requireThat(
          data.ply === room.state.history.length,
          "The board changed. Try your move again.",
        );
        const move = room.chess.move({
          from: data.from,
          to: data.to,
          promotion: ["q", "r", "b", "n"].includes(data.promotion)
            ? data.promotion
            : "q",
        });
        const clocks = room.state.clocks;
        if (room.state.timeControl !== "untimed")
          clocks[move.color] =
            Math.max(
              0,
              clocks[move.color] - Math.max(0, this.now() - clocks.updatedAt),
            ) + clocks.increment;
        clocks.updatedAt = this.now();
        clocks.turn = room.chess.turn();
        room.state.fen = room.chess.fen();
        room.state.drawOffer = room.state.drawOffer === id ? id : null;
        room.state.history.push({
          from: move.from,
          to: move.to,
          promotion: move.promotion,
          san: move.san,
          fen: room.state.fen,
        });
        if (room.chess.isCheckmate())
          this.finish(
            room,
            room.chess.turn() === "w" ? "0-1" : "1-0",
            "Checkmate",
          );
        else if (room.chess.isGameOver())
          this.finish(
            room,
            "1/2-1/2",
            room.chess.isStalemate()
              ? "Stalemate"
              : room.chess.isThreefoldRepetition()
                ? "Threefold repetition"
                : room.chess.isInsufficientMaterial()
                  ? "Insufficient material"
                  : "Fifty-move rule",
          );
        else {
          this.store.save(room.state);
          this.broadcastGame(room.state.id);
        }
        break;
      }
      case "game:resign": {
        const room = this.member(client, data.id);
        if (!this.clock(room))
          this.finish(
            room,
            room.state.white.id === id ? "0-1" : "1-0",
            "Resignation",
          );
        break;
      }
      case "game:draw": {
        const room = this.member(client, data.id);
        if (this.clock(room)) return;
        if (
          room.state.drawOffer &&
          room.state.drawOffer !== id &&
          data.accept === true
        )
          this.finish(room, "1/2-1/2", "Draw by agreement");
        else if (data.decline === true) {
          room.state.drawOffer = null;
          this.broadcastGame(room.state.id);
        } else {
          requireThat(room.state.drawOffer !== id, "Draw already offered.");
          room.state.drawOffer = id;
          this.broadcastGame(room.state.id);
        }
        break;
      }
      case "game:spectate": {
        requireThat(
          !this.active(id) && !this.queue.has(id),
          "Finish your game or leave the queue before watching.",
        );
        const room = this.active(data.friendId);
        requireThat(
          room && this.canWatch(id, room),
          "Your friend’s game is unavailable or private.",
        );
        client.watching = room.state.id;
        this.broadcastGame(room.state.id);
        break;
      }
      case "game:unwatch": {
        const watched = client.watching;
        client.watching = null;
        if (watched) this.broadcastGame(watched);
        break;
      }
      case "game:emote": {
        const room = this.member(client, data.id);
        const emote = EMOTES.find((e) => e.id === data.emote);
        requireThat(
          emote && this.now() - client.lastEmote >= 3000,
          "Wait three seconds between emotes.",
        );
        client.lastEmote = this.now();
        const event = {
          type: "game:emote",
          event: {
            id: room.state.id,
            userId: id,
            name: this.store.get(id)!.name,
            emote,
            at: this.now(),
          },
        };
        for (const c of this.clients)
          if (
            c.userId === room.state.white.id ||
            c.userId === room.state.black.id ||
            c.watching === room.state.id
          )
            this.send(c, event);
        break;
      }
      case "game:sync": {
        const room =
          this.active(id) ||
          (client.watching ? this.rooms.get(client.watching) : null);
        if (room)
          this.send(client, {
            type: "game:state",
            game: this.publicGame(room, id),
          });
        break;
      }
      default:
        throw new Error("Unknown action.");
    }
  }
  canWatch(id: string, room: Room) {
    return [room.state.white, room.state.black].some(
      (p) =>
        this.store.areFriends(id, p.id) &&
        this.store.get(p.id)?.allowSpectators,
    );
  }
  checkSpectators() {
    for (const c of this.clients)
      if (c.watching) {
        const room = this.rooms.get(c.watching);
        if (room && !this.canWatch(c.userId!, room)) {
          const watched = c.watching;
          c.watching = null;
          this.send(c, {
            type: "spectate:ended",
            message: "This game is no longer available to watch.",
          });
          this.broadcastGame(watched);
        }
      }
  }
  close() {
    this.closing = true;
    clearInterval(this.timer);
    for (const c of this.clients) c.ws.terminate();
    this.wss.close();
    this.store.db.close();
  }
}
