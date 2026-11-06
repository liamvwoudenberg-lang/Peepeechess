import test from "node:test";
import assert from "node:assert/strict";
import { buildSync } from "esbuild";
import { mkdtempSync, writeFileSync, symlinkSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";
test("the Vercel API runs as emitted native ESM without a TypeScript loader", () => {
  const dir = mkdtempSync(join(tmpdir(), "chess-vercel-"));
  try {
    buildSync({
      entryPoints: [
        "api/chess.ts",
        "server/onlineStorage.ts",
        "server/onlineService.ts",
        "server/onlineHandler.ts",
        "src/next/contracts.ts",
      ],
      outbase: ".",
      outdir: dir,
      bundle: false,
      format: "esm",
      platform: "node",
      target: "node22",
      logLevel: "silent",
    });
    writeFileSync(join(dir, "package.json"), '{"type":"module"}');
    symlinkSync(resolve("node_modules"), join(dir, "node_modules"), "dir");
    const output = execFileSync(
      process.execPath,
      [
        "--input-type=module",
        "-e",
        `const {default:handler}=await import(${JSON.stringify(join(dir, "api/chess.js"))});delete process.env.UPSTASH_REDIS_REST_URL;delete process.env.UPSTASH_REDIS_REST_TOKEN;const headers={};let code=0,body;const res={setHeader:(k,v)=>headers[k]=v,status(n){code=n;return this;},json(v){body=v;}};await handler({method:'GET',headers:{origin:'https://localhost',host:'cheesy-indol.vercel.app'}},res);console.log(JSON.stringify({code,body,headers}));`,
      ],
      { encoding: "utf8" },
    );
    const r = JSON.parse(output);
    assert.equal(r.code, 503);
    assert.equal(r.body.code, "ONLINE_NOT_CONFIGURED");
    assert.equal(r.headers["Access-Control-Allow-Origin"], "https://localhost");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
