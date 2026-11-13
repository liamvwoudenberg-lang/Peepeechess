import express from "express";
import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { ApiError, NativeService, object } from "./service.js";
import { NativeStorage } from "./storage.js";
import type { Endpoint } from "../../contracts/application/v1/types.js";

export interface BackendOptions {
  databaseUrl?: string; filename?: string; serverId: string; serverSecret: string; endpoint: Endpoint; now?: () => number;
}
class Limiter {
  private entries = new Map<string, { started: number; count: number }>();
  allow(key: string, limit: number, duration: number, now: number) {
    let entry = this.entries.get(key);
    if (!entry && this.entries.size >= 10000) {
      for (const [k, v] of this.entries) if (now - v.started >= 600000) this.entries.delete(k);
      if (this.entries.size >= 10000) return false;
    }
    if (!entry || now - entry.started >= duration) { entry = { started: now, count: 0 }; this.entries.set(key, entry); }
    return ++entry.count <= limit;
  }
}
export async function createNativeBackend(options: BackendOptions) {
  if (!options.serverId || options.serverSecret.length < 32) throw new Error("A dedicated server ID and secret of at least 32 characters are required.");
  const storage = new NativeStorage({ databaseUrl: options.databaseUrl, filename: options.filename });
  await storage.initialize();
  const service = new NativeService(storage, { serverId: options.serverId, endpoint: options.endpoint }, options.now);
  const now = options.now || Date.now, limit = new Limiter(), app = express();
  let activeAuth = 0;
  app.disable("x-powered-by");
  app.use((_req, res, next) => { res.setHeader("Cache-Control", "no-store"); res.setHeader("X-Content-Type-Options", "nosniff"); next(); });
  app.use((req, _res, next) => {
    const ip = req.socket.remoteAddress || "unknown";
    const internal = req.path.startsWith("/internal/");
    if (!limit.allow((internal ? "internal:" : "http:") + ip, internal ? 1200 : 240, 60000, now())) return next(new ApiError(429, "RATE_LIMITED", "Too many requests. Try again shortly."));
    next();
  });
  app.use(express.json({ limit: "1mb", strict: true, type: "application/json" }));
  const wrap = (fn: (req: express.Request, res: express.Response) => Promise<unknown>) => (req: express.Request, res: express.Response, next: express.NextFunction) => {
    Promise.resolve(fn(req, res)).then(value => { if (!res.headersSent) res.json({ schemaVersion: 1, ...value as object }); }).catch(next);
  };
  const account = (req: express.Request) => service.authenticate(/^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization || "")?.[1]);
  const limitNumber = (value: unknown) => {
    if (value === undefined) return 20;
    if (typeof value !== "string" || !/^\d{1,3}$/.test(value) || +value < 1 || +value > 100) throw new ApiError(400, "INVALID_PAYLOAD", "Limit must be 1–100.");
    return +value;
  };
  const offsetNumber = (value: unknown) => {
    if (value === undefined) return 0;
    if (typeof value !== "string" || !/^\d{1,7}$/.test(value) || +value > 1000000) throw new ApiError(400, "INVALID_PAYLOAD", "Offset must be 0–1000000.");
    return +value;
  };
  const serverAuth = (req: express.Request) => {
    const authorization = req.headers.authorization || "";
    const secret = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (req.headers["x-server-id"] !== options.serverId || Buffer.byteLength(secret) !== Buffer.byteLength(options.serverSecret) || !timingSafeEqual(Buffer.from(secret), Buffer.from(options.serverSecret))) throw new ApiError(401, "UNAUTHENTICATED", "Dedicated server authentication required.");
    return options.serverId;
  };
  const auth = (register: boolean) => wrap(async req => {
    const ip = req.socket.remoteAddress || "unknown";
    if (!limit.allow("auth:" + ip, 30, 600000, now()) || activeAuth >= 8) throw new ApiError(429, "RATE_LIMITED", "Too many sign-in attempts. Try again later.");
    activeAuth++;
    try { return await (register ? service.register(req.body) : service.login(req.body)); }
    finally { activeAuth--; }
  });
  app.get("/health", (_req, res) => res.json({ schemaVersion: 1, ok: true }));
  app.post("/v1/auth/register", auth(true));
  app.post("/v1/auth/login", auth(false));
  app.post("/v1/auth/logout", wrap(async req => { await account(req); object(req.body, []); return service.logout(req.headers.authorization!.slice(7)); }));
  app.get("/v1/me", wrap(async req => service.getProfile(await account(req))));
  app.get("/v1/profile", wrap(async req => { const own = await account(req); const id = req.query.playerId; if (id !== undefined && (typeof id !== "string" || id.length > 96)) throw new ApiError(400, "INVALID_PAYLOAD", "Invalid player ID."); return service.getProfile(id as string || own); }));
  app.get("/v1/history/summary", wrap(async req => service.historySummary(await account(req), limitNumber(req.query.limit), offsetNumber(req.query.offset))));
  app.get("/v1/history", wrap(async req => service.history(await account(req), limitNumber(req.query.limit))));
  app.get("/v1/leaderboard", wrap(async req => { await account(req); return service.leaderboard(req.query.mode || "classic", limitNumber(req.query.limit)); }));
  app.post("/v1/queue", wrap(async req => service.queue(await account(req), req.body)));
  app.delete("/v1/queue", wrap(async req => service.cancel(await account(req))));
  app.get("/v1/status", wrap(async req => service.getStatus(await account(req))));
  app.post("/v1/private", wrap(async req => service.createPrivate(await account(req), req.body)));
  app.post("/v1/private/join", wrap(async req => service.joinPrivate(await account(req), req.body)));
  // Friends. Mutations return the full snapshot so a client can redraw from one response. Accepting a challenge is POST /v1/private/join.
  app.get("/v1/friends", wrap(async req => service.getFriends(await account(req))));
  app.post("/v1/friends/request", wrap(async req => {
    const player = await account(req);
    if (!limit.allow("friend-request:" + player, 30, 3600000, now())) throw new ApiError(429, "RATE_LIMITED", "Too many friend requests. Try again later.");
    return service.friendRequest(player, req.body);
  }));
  app.post("/v1/friends/accept", wrap(async req => service.friendAccept(await account(req), req.body)));
  app.post("/v1/friends/remove", wrap(async req => service.friendRemove(await account(req), req.body)));
  app.post("/v1/friends/challenge", wrap(async req => service.challenge(await account(req), req.body)));
  app.post("/v1/friends/challenge/decline", wrap(async req => service.declineChallenge(await account(req), req.body)));
  app.post("/v1/tickets", wrap(async req => service.issueTicket(await account(req), req.body)));
  app.post("/internal/tickets/redeem", wrap(async req => service.redeemTicket(serverAuth(req), req.body)));
  app.post("/internal/heartbeat", wrap(async req => service.heartbeat(serverAuth(req), req.body)));
  app.post("/internal/results", wrap(async req => service.report(serverAuth(req), req.body)));
  app.use((_req, _res, next) => next(new ApiError(404, "NOT_FOUND", "Endpoint not found.")));
  app.use((error: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    const known = error instanceof ApiError;
    const status = known ? error.status : error.type === "entity.too.large" ? 413 : error instanceof SyntaxError ? 400 : 503;
    // Do not log request bodies, bearer tokens, password hashes or database URLs.
    if (!known && status === 503) console.error("Native backend operation failed; request rolled back.");
    res.status(status).json({ schemaVersion: 1, error: { code: known ? error.code : status === 413 ? "PAYLOAD_TOO_LARGE" : status === 400 ? "INVALID_PAYLOAD" : "SERVICE_UNAVAILABLE", message: known ? error.message : status === 503 ? "Service temporarily unavailable." : "Invalid JSON request." } });
  });
  const server = createServer(app);
  server.requestTimeout = 15000; server.headersTimeout = 10000; server.keepAliveTimeout = 5000;
  return { app, server, storage, service, close: async () => { server.closeAllConnections(); if (server.listening) await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); await storage.close(); } };
}
