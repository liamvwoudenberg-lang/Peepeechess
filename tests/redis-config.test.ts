import test from "node:test";
import assert from "node:assert/strict";
import { redisConfig } from "../server/onlineStorage";
import api from "../api/chess";

test("Redis accepts Upstash and Vercel KV credential pairs without mixing incomplete configurations", () => {
  assert.equal(redisConfig({}), null);
  assert.deepEqual(
    redisConfig({
      KV_REST_API_URL: " https://kv.example.test ",
      KV_REST_API_TOKEN: " write-token ",
    }),
    { url: "https://kv.example.test", token: "write-token" },
  );
  assert.equal(
    redisConfig({
      UPSTASH_REDIS_REST_URL: "https://one.example.test",
      KV_REST_API_TOKEN: "other-token",
    }),
    null,
  );
  assert.equal(
    redisConfig({
      KV_REST_API_URL: "https://kv.example.test",
      KV_REST_API_READ_ONLY_TOKEN: "read-only",
    }),
    null,
  );
  assert.deepEqual(
    redisConfig({
      UPSTASH_REDIS_REST_URL: "https://upstash.example.test",
      UPSTASH_REDIS_REST_TOKEN: "upstash-token",
      KV_REST_API_URL: "https://kv.example.test",
      KV_REST_API_TOKEN: "kv-token",
    }),
    { url: "https://upstash.example.test", token: "upstash-token" },
  );
  assert.deepEqual(
    redisConfig({
      UPSTASH_REDIS_REST_URL: "https://incomplete.example.test",
      KV_REST_API_URL: "https://kv.example.test",
      KV_REST_API_TOKEN: "kv-token",
    }),
    { url: "https://kv.example.test", token: "kv-token" },
  );
});

test("the deployed API can reach Redis using Vercel Marketplace's KV variable names", async () => {
  const keys = [
      "UPSTASH_REDIS_REST_URL",
      "UPSTASH_REDIS_REST_TOKEN",
      "KV_REST_API_URL",
      "KV_REST_API_TOKEN",
    ],
    saved = keys.map((k) => process.env[k]),
    originalFetch = globalThis.fetch;
  try {
    keys.forEach((k) => delete process.env[k]);
    process.env.KV_REST_API_URL = "https://kv.example.test";
    process.env.KV_REST_API_TOKEN = "test-only-write-token";
    let requests = 0,
      status = 0,
      body: any;
    globalThis.fetch = (async (url, init) => {
      assert.equal(url, "https://kv.example.test");
      assert.equal(
        new Headers(init?.headers).get("Authorization"),
        "Bearer test-only-write-token",
      );
      assert.deepEqual(JSON.parse(init?.body as string), [
        "GET",
        "sg:v3:health",
      ]);
      requests++;
      return new Response(JSON.stringify({ result: null }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }) as typeof fetch;
    const res = {
      setHeader() {},
      status(n: number) {
        status = n;
        return this;
      },
      json(v: any) {
        body = v;
      },
    };
    await api({ method: "GET", headers: {} }, res);
    assert.equal(requests, 1);
    assert.equal(status, 200);
    assert.deepEqual(body, { ok: true, transport: "peerjs", storage: "ready" });
  } finally {
    globalThis.fetch = originalFetch;
    keys.forEach((k, i) =>
      saved[i] === undefined
        ? delete process.env[k]
        : (process.env[k] = saved[i]),
    );
  }
});
