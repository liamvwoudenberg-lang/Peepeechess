import { gameWebsite, isNativeApp, inviteSessionKey } from "./mobile";
import type { Peer, DataConnection } from "peerjs";
type Status = "connecting" | "online" | "offline";
export class PeerTransport {
  private origin = gameWebsite();
  private sessionKey = inviteSessionKey();
  private inviteCode = "";
  private peer: Peer | null = null;
  private channel: DataConnection | null = null;
  private descriptor: any = null;
  private config: any = null;
  private peerId = "";
  private token = "";
  private stopped = false;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private readyTimer: ReturnType<typeof setTimeout> | null = null;
  private polling = false;
  private pending = false;
  private peerLoading = false;
  private currentGame: any = null;
  private queued = false;
  private chatWith = "";
  private cache = new Map<string, string>();
  private seenEmotes = new Set<string>();
  private readyRooms = new Set<string>();
  private chain = Promise.resolve();
  private peerAttempts = 0;
  private nextPeerTry = 0;
  private lastHint = 0;
  constructor(
    private message: (d: any) => void,
    private state: (s: Status, error?: string) => void,
    private route: (s: "connecting" | "direct" | "server") => void,
    private offset: (n: number) => void,
  ) {}
  start() {
    if (isNativeApp() && !this.origin) {
      this.state("offline");
      return;
    }
    try {
      this.token = localStorage.getItem(this.sessionKey) || "";
    } catch {}
    void this.authenticate();
    window.addEventListener("online", this.onOnline);
  }
  private onOnline = () => {
    if (!this.stopped) void this.authenticate();
  };
  private async call(action: any) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch(this.origin + "/api/chess", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(this.token ? { Authorization: "Bearer " + this.token } : {}),
        },
        body: JSON.stringify({ action, peerId: this.peerId }),
        signal: controller.signal,
      });
      const data = await response.json();
      if (!response.ok)
        throw new Error(data.error || "The game server is unavailable.");
      if (this.stopped) return null;
      if (typeof data.serverTime === "number")
        this.offset(data.serverTime - Date.now());
      return data;
    } catch (error) {
      if (controller.signal.aborted)
        throw new Error("The connection took too long. Reconnecting…");
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }
  private async authenticate() {
    try {
      let faction = "royal";
      try {
        faction =
          JSON.parse(localStorage.getItem("sg-preferences-v2") || "{}")
            .pieceSet || "royal";
      } catch {}
      const data = await this.call({ type: "auth", army: faction });
      if (!data) return;
      if (data.messages?.some((d: any) => d.type === "auth:error")) {
        data.messages.forEach(this.message);
        this.state("offline", "This browser profile could not be restored.");
        return;
      }
      const ready = data.messages?.find((d: any) => d.type === "ready");
      if (ready?.token) {
        this.token = ready.token;
        try {
          localStorage.setItem(this.sessionKey, this.token);
        } catch {}
      }
      this.config = data.peerConfig;
      this.state("online");
      this.consume(data);
      this.schedule();
    } catch (e) {
      if (this.stopped) return;
      this.state(
        "offline",
        e instanceof Error ? e.message : "Could not connect.",
      );
      this.schedule(6000);
    }
  }
  private emit(key: string, data: any) {
    if (!data) return;
    const value = JSON.stringify(data);
    if (this.cache.get(key) === value) return;
    this.cache.set(key, value);
    this.message(data);
  }
  private consume(data: any) {
    if (!data || this.stopped) return;
    if (data.peerConfig) this.config = data.peerConfig;
    for (const message of data.messages || []) this.message(message);
    this.emit("invite", { type: "invite:state", invite: data.invite || null });
    if (data.invitePreview)
      this.emit("preview", {
        type: "invite:preview",
        invite: data.invitePreview,
      });
    this.emit("social", data.social);
    this.emit("queue", data.queue);
    this.queued = Boolean(data.queue?.queued);
    this.emit("archive", data.archive);
    if (data.chat) this.emit("chat:" + data.chat.friendId, data.chat);
    if (data.spectateEnded)
      this.message({
        type: "spectate:ended",
        message: "This game is no longer available to watch.",
      });
    if (data.game) {
      const g = data.game,
        old = this.currentGame;
      if (
        !old ||
        old.id !== g.id ||
        (data.roomVersion || 0) >= (old.version || 0)
      ) {
        this.currentGame = { ...g, version: data.roomVersion };
        this.emit("game", { type: "game:state", game: g });
        if (g.status === "completed" && g.yourColor)
          this.send({ type: "game:seen", id: g.id });
      }
    }
    for (const event of data.emotes || []) {
      const key = event.id + ":" + event.userId + ":" + event.at;
      if (!this.seenEmotes.has(key)) {
        this.seenEmotes.add(key);
        if (Date.now() - event.at < 12000)
          this.message({ type: "game:emote", event });
      }
    }
    if (this.seenEmotes.size > 100)
      this.seenEmotes = new Set([...this.seenEmotes].slice(-50));
    if (data.peer && data.game?.status === "active") this.matchPeer(data.peer);
    else if (data.game?.status === "completed" || (!data.peer && !data.game))
      this.disconnectRoom();
  }
  send(action: any) {
    if (this.stopped || !this.token) return false;
    if (action.type === "invite:inspect") this.inviteCode = action.code;
    if (action.type === "invite:clear") {
      this.inviteCode = "";
      return true;
    }
    if (action.type === "chat:history") this.chatWith = action.friendId;
    if (
      action.type === "queue:join" ||
      action.type === "challenge:send" ||
      action.type === "invite:create" ||
      action.type === "invite:join"
    )
      void this.ensurePeer();
    const requestId =
      typeof crypto.randomUUID === "function"
        ? crypto.randomUUID()
        : Date.now().toString(36) + Math.random().toString(36).slice(2);
    this.chain = this.chain.then(async () => {
      if (this.stopped) return;
      try {
        const data = await this.call({
          ...action,
          chatWith: this.chatWith,
          inviteCode: this.inviteCode,
          requestId,
        });
        this.state("online");
        this.consume(data);
        if (this.channel?.open && action.type !== "game:seen")
          this.channel.send({ type: "sync", roomId: this.descriptor?.roomId });
      } catch (error) {
        this.message({
          type: "error",
          action: action.type,
          message:
            error instanceof Error
              ? error.message
              : "The action failed. Try again.",
        });
        if (action.type === "game:ready") this.readyRooms.delete(action.id);
        void this.poll();
      }
    });
    return true;
  }
  private schedule(ms?: number) {
    if (this.stopped) return;
    if (this.timer) clearTimeout(this.timer);
    const active = this.currentGame?.status === "active";
    this.timer = setTimeout(
      () => {
        if (this.token) void this.poll();
        else void this.authenticate();
      },
      ms ??
        (document.hidden
          ? 10000
          : active
            ? this.channel?.open
              ? 5000
              : 1100
            : this.queued
              ? 1200
              : this.chatWith
                ? 1600
                : 3000),
    );
  }
  private async poll() {
    if (this.stopped) return;
    if (this.polling) {
      this.pending = true;
      return;
    }
    this.polling = true;
    try {
      const data = await this.call({
        type: "poll",
        chatWith: this.chatWith,
        inviteCode: this.inviteCode,
      });
      if (data) {
        this.state("online");
        this.consume(data);
      }
    } catch (e) {
      if (!this.stopped)
        this.state(
          "offline",
          e instanceof Error ? e.message : "Connection lost. Reconnecting…",
        );
    } finally {
      this.polling = false;
      if (this.pending) {
        this.pending = false;
        this.schedule(50);
      } else this.schedule();
    }
  }
  private async ensurePeer() {
    if (this.peer || this.peerLoading || !this.config || this.stopped) return;
    this.peerLoading = true;
    try {
      const { Peer } = await import("peerjs");
      if (this.stopped) return;
      const c = this.config,
        local = c.host === "__same_origin__",
        target = new URL(this.origin);
      this.peer = new Peer({
        host: local ? target.hostname : c.host,
        port: local
          ? Number(target.port) || (target.protocol === "https:" ? 443 : 80)
          : c.port,
        path: c.path,
        secure: local ? target.protocol === "https:" : c.secure,
        key: c.key,
        debug: 0,
        config: { iceServers: c.iceServers },
      });
      this.peer.on("open", (id) => {
        this.peerId = id;
        void this.poll();
      });
      this.peer.on("connection", (channel) => this.accept(channel));
      this.peer.on("error", () => {
        this.route("server");
      });
      this.peer.on("disconnected", () => {
        this.route("server");
        try {
          this.peer?.reconnect();
        } catch {}
      });
    } catch {
      this.route("server");
    } finally {
      this.peerLoading = false;
    }
  }
  private matchPeer(d: any) {
    const changed =
      this.descriptor?.roomId !== d.roomId ||
      this.descriptor?.peerId !== d.peerId;
    this.descriptor = d;
    if (changed) {
      this.peerAttempts = 0;
      this.nextPeerTry = 0;
    }
    void this.ensurePeer();
    if (!this.readyRooms.has(d.roomId) && !this.readyTimer)
      this.readyTimer = setTimeout(() => {
        this.readyTimer = null;
        this.ready(d.roomId);
      }, 2200);
    if (changed) {
      this.channel?.close();
      this.channel = null;
      this.route("connecting");
    }
    if (
      this.peer?.open &&
      d.peerId &&
      d.initiator &&
      !this.channel &&
      this.peerAttempts < 3 &&
      Date.now() >= this.nextPeerTry
    ) {
      this.peerAttempts++;
      this.nextPeerTry = Date.now() + 30000;
      if (this.peer.options.config)
        this.peer.options.config.iceServers = this.config.iceServers;
      const c = this.peer.connect(d.peerId, {
        reliable: true,
        serialization: "json",
        metadata: { roomId: d.roomId, secret: d.secret },
      });
      this.accept(c);
    }
  }
  private accept(c: DataConnection) {
    const d = this.descriptor;
    if (
      !d ||
      c.peer !== d.peerId ||
      c.metadata?.roomId !== d.roomId ||
      c.metadata?.secret !== d.secret
    ) {
      c.close();
      return;
    }
    if (this.channel && this.channel !== c) this.channel.close();
    this.channel = c;
    const opening = setTimeout(() => {
      if (this.channel === c && !c.open) c.close();
    }, 10000);
    c.on("open", () => {
      clearTimeout(opening);
      if (this.channel !== c) return;
      this.route("direct");
      this.ready(d.roomId);
      c.send({ type: "sync", roomId: d.roomId });
    });
    c.on("data", (raw: any) => {
      if (
        this.channel === c &&
        raw &&
        raw.type === "sync" &&
        raw.roomId === d.roomId &&
        Date.now() - this.lastHint > 500
      ) {
        this.lastHint = Date.now();
        void this.poll();
      }
    });
    c.on("close", () => {
      clearTimeout(opening);
      if (this.channel === c) {
        this.channel = null;
        this.route("server");
      }
    });
    c.on("error", () => {
      clearTimeout(opening);
      if (this.channel === c) {
        this.channel = null;
        this.route("server");
      }
    });
  }
  private ready(id: string) {
    if (
      this.stopped ||
      this.descriptor?.roomId !== id ||
      this.readyRooms.has(id)
    )
      return;
    this.readyRooms.add(id);
    if (!this.channel?.open) this.route("server");
    this.send({ type: "game:ready", id });
  }
  private disconnectRoom() {
    if (!this.descriptor) return;
    this.descriptor = null;
    this.channel?.close();
    this.channel = null;
    if (this.readyTimer) clearTimeout(this.readyTimer);
    this.readyTimer = null;
    this.route("server");
  }
  stop() {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
    if (this.readyTimer) clearTimeout(this.readyTimer);
    this.channel?.close();
    this.peer?.destroy();
    window.removeEventListener("online", this.onOnline);
  }
}
