import { randomBytes } from "node:crypto";
import type { Server, IncomingMessage } from "node:http";
import type { Color } from "chess.js";
import { WebSocket, WebSocketServer } from "ws";
import { BattleHost, type BattleCommand } from "../src/battle/session";
import { neutralInput, sanitizeInput } from "../src/battle/simulation";
import { resignBattleMatch } from "../src/battle/rules";
import type { Army } from "../src/game/battleProfiles";
const army = (value: unknown): Army =>
  value === "elves" || value === "skeletons" ? value : "royal";
interface Seat {
  token: string;
  ws: WebSocket | null;
  lastInput: number;
  goneAt: number;
  sequence: number;
}
interface Room {
  code: string;
  host: BattleHost;
  seats: Record<Color, Seat>;
  created: number;
  last: number;
  started: boolean;
}
export class BattleServer {
  wss = new WebSocketServer({ noServer: true, maxPayload: 2048 });
  rooms = new Map<string, Room>();
  private timer: ReturnType<typeof setInterval>;
  private lastTick: number;
  private frame = 0;
  private closing = false;
  private creations = new Map<string, number[]>();
  constructor(
    server: Server,
    private now = Date.now,
  ) {
    this.lastTick = now();
    server.on("upgrade", (req, socket, head) => {
      if (new URL(req.url || "/", "http://localhost").pathname !== "/battle-ws")
        return;
      const origin = req.headers.origin;
      let allowed = !origin;
      try {
        allowed ||=
          new URL(origin!).host === req.headers.host ||
          [
            "https://localhost",
            "capacitor://localhost",
            ...(process.env.BATTLE_ALLOWED_ORIGINS || "")
              .split(",")
              .map((s) => s.trim())
              .filter(Boolean),
          ].includes(origin!);
      } catch {}
      if (!allowed) {
        socket.destroy();
        return;
      }
      this.wss.handleUpgrade(req, socket, head, (ws) =>
        this.wss.emit("connection", ws, req),
      );
    });
    this.wss.on("connection", (ws: WebSocket, req: IncomingMessage) =>
      this.connect(ws, req),
    );
    this.timer = setInterval(() => this.tick(), 1000 / 30);
    this.timer.unref();
    server.once("close", () => this.close());
  }
  private send(ws: WebSocket, data: unknown) {
    if (ws.readyState === WebSocket.OPEN && ws.bufferedAmount < 200000)
      ws.send(JSON.stringify(data));
  }
  private snapshot(room: Room) {
    const peers = { w: Boolean(room.seats.w.ws), b: Boolean(room.seats.b.ws) };
    for (const seat of Object.values(room.seats))
      if (seat.ws)
        this.send(seat.ws, {
          type: "state",
          room: room.code,
          peers,
          started: room.started,
          snapshot: room.host.state,
        });
  }
  private connect(ws: WebSocket, req: IncomingMessage) {
    let room: Room | null = null,
      color: Color | null = null,
      events: number[] = [],
      alive = true;
    const timeout = setTimeout(() => {
      if (!room) ws.close(1008, "Join a room first.");
    }, 8000);
    timeout.unref();
    ws.on("pong", () => (alive = true));
    const heartbeat = setInterval(() => {
      if (!alive) {
        ws.terminate();
        return;
      }
      alive = false;
      ws.ping();
    }, 15000);
    heartbeat.unref();
    ws.on("message", (raw) => {
      try {
        const t = this.now();
        events = events.filter((at) => t - at < 1000);
        if (events.length >= 90) throw Error("Too many inputs.");
        events.push(t);
        const data = JSON.parse(String(raw));
        if (!data || typeof data.type !== "string")
          throw Error("Invalid command.");
        if (!room) {
          if (data.type === "create") {
            const ip = req.socket.remoteAddress || "unknown",
              times = (this.creations.get(ip) || []).filter(
                (at) => t - at < 60000,
              );
            if (times.length >= 5 || this.rooms.size >= 100)
              throw Error("The Battle server is busy. Try again shortly.");
            this.creations.set(ip, [...times, t]);
            const code = randomBytes(6).toString("hex"),
              empty = (): Seat => ({
                token: randomBytes(24).toString("hex"),
                ws: null,
                lastInput: t,
                goneAt: 0,
                sequence: -1,
              });
            room = {
              code,
              host: new BattleHost({ w: army(data.army), b: "skeletons" }),
              seats: { w: empty(), b: empty() },
              created: t,
              last: t,
              started: false,
            };
            this.rooms.set(code, room);
            color = "w";
          } else {
            const code = String(data.code || "").toLowerCase();
            room = this.rooms.get(code) || null;
            if (!room) throw Error("Room not found or expired.");
            if (data.type === "resume") {
              color =
                (["w", "b"] as Color[]).find(
                  (c) => room!.seats[c].token === data.token,
                ) || null;
              if (!color) throw Error("This room credential is not valid.");
            } else if (data.type === "join") {
              if (room.started || room.seats.b.ws)
                throw Error("This room already has two players.");
              color = "b";
              room.host.state.match.armies.b = army(data.army);
              room.started = true;
            } else throw Error("Create or join a Battle Chess room.");
          }
          const seat = room.seats[color!];
          seat.ws?.close(1000, "Reconnected from another tab.");
          seat.ws = ws;
          seat.goneAt = 0;
          seat.lastInput = t;
          seat.sequence = -1;
          clearTimeout(timeout);
          this.send(ws, {
            type: "welcome",
            room: room.code,
            seat: color,
            token: seat.token,
          });
          this.snapshot(room);
          return;
        }
        const seat = room.seats[color!];
        if (seat.ws !== ws) throw Error("This connection was replaced.");
        room.last = t;
        if (data.type === "input") {
          if (
            !room.started ||
            !Number.isSafeInteger(data.sequence) ||
            data.sequence <= seat.sequence
          )
            return;
          seat.sequence = data.sequence;
          seat.lastInput = t;
          room.host.inputs[color!] = sanitizeInput(data.input);
          return;
        }
        if (data.type === "command") {
          const command = data.command as BattleCommand;
          if (
            !command ||
            !["move", "continue", "resign", "draw"].includes(command.type)
          )
            throw Error("Unsupported command.");
          if (!room.started && command.type !== "resign")
            throw Error("Wait for the second player.");
          room.host.command(command, color!);
          this.snapshot(room);
          return;
        }
        throw Error("Unsupported message.");
      } catch (e) {
        if (room && color === null) room = null;
        this.send(ws, {
          type: "error",
          message: e instanceof Error ? e.message : "The request failed.",
        });
      }
    });
    ws.on("error", () => {});
    ws.on("close", () => {
      clearTimeout(timeout);
      clearInterval(heartbeat);
      if (room && color && room.seats[color].ws === ws) {
        room.seats[color].ws = null;
        room.seats[color].goneAt = this.now();
        room.host.inputs[color] = neutralInput();
        this.snapshot(room);
      }
    });
  }
  tick() {
    const now = this.now(),
      dt = (now - this.lastTick) / 1000;
    this.lastTick = now;
    this.frame++;
    for (const [code, room] of this.rooms) {
      if (
        (!room.started && now - room.created > 300000) ||
        (room.host.state.match.phase === "complete" && now - room.last > 600000)
      ) {
        for (const seat of Object.values(room.seats))
          seat.ws?.close(1000, "Room expired.");
        this.rooms.delete(code);
        continue;
      }
      if (!room.started) continue;
      for (const color of ["w", "b"] as Color[]) {
        const seat = room.seats[color];
        if (now - seat.lastInput > 250)
          room.host.inputs[color] = {
            ...neutralInput(),
            light: room.host.inputs[color].light,
            heavy: room.host.inputs[color].heavy,
            dodge: room.host.inputs[color].dodge,
            parry: room.host.inputs[color].parry,
            ability: room.host.inputs[color].ability,
          };
      }
      if (room.host.state.match.phase !== "complete") {
        const absent = (["w", "b"] as Color[]).filter(
          (c) =>
            !room.seats[c].ws &&
            room.seats[c].goneAt &&
            now - room.seats[c].goneAt > 10000,
        );
        if (absent.length && !room.seats.w.ws && !room.seats.b.ws) {
          room.host.state.match = {
            ...room.host.state.match,
            phase: "complete",
            pending: null,
            result: "1/2-1/2",
            reason: "Both players disconnected",
          };
          room.host.state.combat = null;
        } else if (absent.length === 1) {
          room.host.state.match = resignBattleMatch(
            room.host.state.match,
            absent[0],
            "Disconnection forfeit",
          );
          room.host.state.combat = null;
        } else room.host.advance(dt);
      }
      if (this.frame % 2 === 0) this.snapshot(room);
    }
  }
  close() {
    if (this.closing) return;
    this.closing = true;
    clearInterval(this.timer);
    for (const ws of this.wss.clients) ws.terminate();
    this.wss.close();
    this.rooms.clear();
  }
}
