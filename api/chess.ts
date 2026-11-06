import { RedisKV } from "../server/onlineStorage";
import {
  onlineHandler,
  peerSettings,
  applyAppCors,
} from "../server/onlineHandler";
let handler: ReturnType<typeof onlineHandler> | null = null;
export default async function chess(req: any, res: any) {
  if (!applyAppCors(req, res)) return;
  if (
    !process.env.UPSTASH_REDIS_REST_URL ||
    !process.env.UPSTASH_REDIS_REST_TOKEN
  ) {
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
      new RedisKV(
        process.env.UPSTASH_REDIS_REST_URL,
        process.env.UPSTASH_REDIS_REST_TOKEN,
      ),
      peerSettings(),
    );
  return handler(req, res);
}
