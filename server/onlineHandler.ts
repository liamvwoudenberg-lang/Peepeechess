import { createHmac } from "node:crypto";
import { OnlineService } from "./onlineService.js";
import type { KV } from "./onlineStorage.js";
export function applyAppCors(req: any, res: any) {
  const headers = req.headers || {},
    origin = headers.origin;
  res.setHeader("Vary", "Origin");
  if (origin) {
    const native = ["https://localhost", "capacitor://localhost"].includes(
      origin,
    );
    let same = false;
    try {
      same = new URL(origin).host === headers.host;
    } catch {}
    if (!native && !same) {
      res
        .status(403)
        .json({ error: "Use the game website or Android app to connect." });
      return false;
    }
    if (native) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader(
        "Access-Control-Allow-Headers",
        "Authorization, Content-Type",
      );
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      res.setHeader("Access-Control-Max-Age", "3600");
    }
  }
  if (req.method === "OPTIONS") {
    res.status(204).end();
    return false;
  }
  return true;
}
export function onlineHandler(kv: KV, peer: any) {
  const service = new OnlineService(kv, Date.now, peer);
  return async (req: any, res: any) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    if (!applyAppCors(req, res)) return;
    if (req.method === "GET") {
      try {
        await kv.get("health");
        res
          .status(200)
          .json({ ok: true, transport: "peerjs", storage: "ready" });
      } catch {
        res.status(503).json({
          error:
            "Online storage is temporarily unavailable. Computer games remain available.",
          code: "ONLINE_STORAGE_UNAVAILABLE",
        });
      }
      return;
    }
    if (req.method !== "POST") {
      res.setHeader("Allow", "GET, POST");
      res.status(405).json({ error: "Method not allowed." });
      return;
    }
    try {
      let data = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
      if (!data) {
        let raw = "";
        for await (const chunk of req) {
          raw += String(chunk);
          if (raw.length > 10000) throw Error("Request too large.");
        }
        data = JSON.parse(raw);
      }
      if (JSON.stringify(data).length > 10000)
        throw Error("Request too large.");
      const token =
        String(req.headers.authorization || "").replace(/^Bearer /, "") ||
        undefined;
      if (data.action?.type === "auth" && !token) {
        const ip = String(
          req.headers["x-real-ip"] || req.socket?.remoteAddress || "unknown",
        ).slice(0, 100);
        await kv.run("auth-rate:" + ip, async (tx) => {
          const hits = (await tx.get<number>("auth-rate:" + ip)) || 0;
          if (hits > 30) throw Error("Too many new profiles. Try again later.");
          tx.set("auth-rate:" + ip, hits + 1, 600);
        });
      }
      res
        .status(200)
        .json(await service.handle(token, data.action, data.peerId));
    } catch (error) {
      res.status(400).json({
        error: error instanceof Error ? error.message : "The request failed.",
        serverTime: Date.now(),
      });
    }
  };
}
export function peerSettings(local = false) {
  return (userId = "player") => {
    let iceServers: RTCIceServer[] = [
      { urls: "stun:stun.l.google.com:19302" },
      { urls: "stun:global.stun.twilio.com:3478" },
    ];
    if (process.env.CHESS_ICE_SERVERS) {
      const value = JSON.parse(process.env.CHESS_ICE_SERVERS);
      if (!Array.isArray(value))
        throw Error("CHESS_ICE_SERVERS must be a JSON array.");
      iceServers = value;
    }
    if (process.env.TURN_URLS && process.env.TURN_SHARED_SECRET) {
      const username = `${Math.floor(Date.now() / 1000) + 3600}:${userId}`;
      iceServers.push({
        urls: process.env.TURN_URLS.split(",")
          .map((s) => s.trim())
          .filter(Boolean),
        username,
        credential: createHmac("sha1", process.env.TURN_SHARED_SECRET)
          .update(username)
          .digest("base64"),
      });
    }
    return {
      host:
        process.env.PEER_HOST || (local ? "__same_origin__" : "0.peerjs.com"),
      port: Number(process.env.PEER_PORT) || (local ? 0 : 443),
      path: process.env.PEER_PATH || (local ? "/peerjs" : "/"),
      secure: process.env.PEER_SECURE
        ? process.env.PEER_SECURE === "true"
        : !local,
      key: process.env.PEER_KEY || "peerjs",
      iceServers,
    };
  };
}
