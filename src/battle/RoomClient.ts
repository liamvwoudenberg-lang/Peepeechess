import type { Color } from "chess.js";
import type { Army } from "../game/battleProfiles";
import type { BattleSnapshot, BattleCommand } from "./session";
import type { CombatInput } from "./simulation";
export interface RoomInfo {
  code: string;
  seat: Color;
  token: string;
}
export class RoomClient {
  private ws: WebSocket | null = null;
  private stopped = false;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private sequence = 0;
  private lastInput = 0;
  private info: RoomInfo | null = null;
  constructor(
    private origin: string,
    private request: { type: "create" | "join"; army: Army; code?: string },
    private onState: (
      s: BattleSnapshot,
      peers: Record<Color, boolean>,
      started: boolean,
    ) => void,
    private onWelcome: (info: RoomInfo) => void,
    private onStatus: (message: string) => void,
  ) {
    if (request.code)
      try {
        const value = JSON.parse(
          sessionStorage.getItem(this.key(request.code)) || "null",
        );
        if (value?.token) this.info = value;
      } catch {}
    this.connect();
  }
  private key(code: string) {
    return `sg-battle-room@${this.origin}@${code}`;
  }
  private connect() {
    if (this.stopped) return;
    this.onStatus("Connecting to the Battle server…");
    const url = new URL("/battle-ws", this.origin);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    const ws = new WebSocket(url);
    let welcomed = false;
    this.ws = ws;
    ws.onopen = () => {
      if (this.stopped) return;
      this.sequence = 0;
      ws.send(
        JSON.stringify(
          this.info
            ? { type: "resume", code: this.info.code, token: this.info.token }
            : this.request,
        ),
      );
    };
    ws.onmessage = (e) => {
      if (this.stopped || this.ws !== ws) return;
      try {
        const d = JSON.parse(e.data);
        if (d.type === "welcome") {
          welcomed = true;
          this.info = { code: d.room, seat: d.seat, token: d.token };
          sessionStorage.setItem(this.key(d.room), JSON.stringify(this.info));
          this.onWelcome(this.info);
          this.onStatus("");
        } else if (d.type === "state" && d.snapshot?.version === 1)
          this.onState(d.snapshot, d.peers, d.started);
        else if (d.type === "error") {
          this.onStatus(d.message);
          if (!welcomed) {
            this.stopped = true;
            ws.close();
          }
        }
      } catch {
        this.onStatus("The Battle server sent an unreadable update.");
      }
    };
    ws.onerror = () => {
      if (!this.stopped && this.ws === ws)
        this.onStatus("The Battle server could not be reached.");
    };
    ws.onclose = () => {
      if (this.stopped || this.ws !== ws) return;
      this.onStatus(
        "Disconnected. Reconnecting; a missing player forfeits after 10 seconds.",
      );
      this.timer = setTimeout(() => this.connect(), 1500);
    };
  }
  command(command: BattleCommand) {
    if (this.ws?.readyState !== WebSocket.OPEN)
      throw Error("Wait for the Battle server to reconnect.");
    this.ws.send(JSON.stringify({ type: "command", command }));
  }
  input(color: Color, input: CombatInput) {
    if (color !== this.info?.seat || this.ws?.readyState !== WebSocket.OPEN)
      return;
    const time = performance.now();
    if (time - this.lastInput < 30) return;
    this.lastInput = time;
    this.ws.send(
      JSON.stringify({ type: "input", sequence: ++this.sequence, input }),
    );
  }
  close() {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
    this.ws?.close();
  }
}
