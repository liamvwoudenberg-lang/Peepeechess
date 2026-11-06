import "dotenv/config";
import express from "express";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Store } from "./server/store";
import { BattleServer } from "./server/battleServer";
import { ChessService } from "./server/chessService";
import { WebSocketServer } from "ws";
import { LocalKV, RedisKV, redisConfig } from "./server/onlineStorage";
import { onlineHandler, peerSettings } from "./server/onlineHandler";

export async function createChessServer(
  options: {
    database?: string;
    production?: boolean;
    now?: () => number;
    peerServer?: boolean;
  } = {},
) {
  const app = express();
  app.disable("x-powered-by");
  const server = http.createServer(app);
  const service = new ChessService(
    new Store(options.database),
    server,
    options.now,
  );
  const battle = new BattleServer(server, options.now);
  app.get("/api/battle-capabilities", (_req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.json({
      enabled: true,
      transport: "websocket",
      authority: "server",
      persistence: "memory",
    });
  });
  app.use(express.json({ limit: "10kb" }));
  const storage = redisConfig();
  const kv = storage
    ? new RedisKV(storage.url, storage.token)
    : new LocalKV(service.store.db);
  app.all(
    "/api/chess",
    onlineHandler(
      kv,
      peerSettings(Boolean(options.peerServer && !process.env.PEER_HOST)),
    ),
  );
  if (options.peerServer && !process.env.PEER_HOST) {
    const { ExpressPeerServer } = await import("peer");
    app.use(
      "/peerjs",
      ExpressPeerServer(server, {
        path: "/",
        allow_discovery: false,
        proxied: true,
        createWebSocketServer: ({ path: peerPath }: any) => {
          const wss = new WebSocketServer({ noServer: true });
          const upgrade = (req: any, socket: any, head: any) => {
            if (new URL(req.url, "http://localhost").pathname !== peerPath)
              return;
            wss.handleUpgrade(req, socket, head, (ws) =>
              wss.emit("connection", ws, req),
            );
          };
          server.on("upgrade", upgrade);
          server.once("close", () => {
            server.off("upgrade", upgrade);
            wss.close();
          });
          return wss;
        },
      }),
    );
  }
  app.get("/api/health", (_req, res) => res.json({ ok: true }));
  app.use((_req, res, next) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Referrer-Policy", "same-origin");
    next();
  });
  if (options.production ?? process.env.NODE_ENV === "production") {
    app.use(
      express.static(path.resolve("dist"), {
        maxAge: "1h",
        index: false,
        setHeaders(res, file) {
          if (file.endsWith("sw.js") || file.endsWith("index.html"))
            res.setHeader("Cache-Control", "no-cache");
        },
      }),
    );
    app.get("*", (_req, res) => res.sendFile(path.resolve("dist/index.html")));
  } else {
    const { createServer } = await import("vite");
    const vite = await createServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
    server.on("close", () => {
      void vite.close();
    });
  }
  return { app, server, service, battle };
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const { server, service, battle } = await createChessServer({
    peerServer: true,
  });
  const port = Number(process.env.PORT) || 3000;
  server.listen(port, "0.0.0.0", () =>
    console.log(`Sovereign’s Gambit is ready on port ${port}`),
  );
  const stop = () => {
    battle.close();
    service.close();
    server.close(() => process.exit(0));
  };
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
}
