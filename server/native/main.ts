import "dotenv/config";
import { createNativeBackend } from "./http.js";
const env = process.env;
const bind = env.NATIVE_API_BIND || "127.0.0.1", port = Number(env.NATIVE_API_PORT || 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid NATIVE_API_PORT.");
if (env.NODE_ENV === "production" && !env.DATABASE_URL) throw new Error("Production native backend requires PostgreSQL DATABASE_URL.");
if (!["127.0.0.1", "::1", "localhost"].includes(bind) && env.NATIVE_API_TLS_PROXY !== "1") throw new Error("External API bind requires NATIVE_API_TLS_PROXY=1 and an HTTPS reverse proxy/firewall.");
const insecure = env.NATIVE_GAME_INSECURE_LOCAL === "1", host = env.NATIVE_GAME_HOST || "127.0.0.1";
if (insecure && !["127.0.0.1", "::1", "localhost"].includes(host)) throw new Error("Plaintext ENet is restricted to explicit loopback development.");
const gamePort = Number(env.NATIVE_GAME_PORT || 2456);
if (!Number.isInteger(gamePort) || gamePort < 1 || gamePort > 65535) throw new Error("Invalid NATIVE_GAME_PORT.");
const backend = await createNativeBackend({
  databaseUrl: env.DATABASE_URL,
  filename: env.NATIVE_DATABASE_PATH,
  serverId: env.NATIVE_SERVER_ID || "local-1",
  serverSecret: env.NATIVE_SERVER_SECRET || "",
  endpoint: { host, port: gamePort, serverName: env.NATIVE_GAME_SERVER_NAME || host, caCertificate: env.NATIVE_GAME_CA_CERTIFICATE || "", insecureLocal: insecure },
});
backend.server.listen(port, bind, () => console.log(`Native application API listening on ${bind}:${port} (${backend.storage.kind}).`));
let closing = false;
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => { if (closing) return; closing = true; void backend.close().then(() => process.exit(0)); });
