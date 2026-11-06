import { RedisKV, redisConfig } from "../server/onlineStorage.js";
import {
  onlineHandler,
  peerSettings,
  applyAppCors,
} from "../server/onlineHandler.js";
let handler: ReturnType<typeof onlineHandler> | null = null;
export default async function chess(req: any, res: any) {
  if (!applyAppCors(req, res)) return;
  const storage = redisConfig();
  if (!storage) {
    res.setHeader("Cache-Control", "no-store");
    res.status(503).json({
      error:
        "Online play is not available on this server yet. You can play the computer while it is being set up.",
      code: "ONLINE_NOT_CONFIGURED",
    });
    return;
  }
  if (!handler)
    handler = onlineHandler(
      new RedisKV(storage.url, storage.token),
      peerSettings(),
    );
  return handler(req, res);
}
