import test from "node:test";
import assert from "node:assert/strict";
import { RoomClient } from "../src/battle/RoomClient";
test("a rejected Battle room admission keeps its real error and does not reconnect forever as if a seat had disconnected", () => {
  const original = globalThis.WebSocket,
    status: string[] = [];
  let socket: any;
  class FakeSocket {
    static OPEN = 1;
    readyState = 1;
    closed = false;
    onopen: any;
    onclose: any;
    onmessage: any;
    onerror: any;
    constructor(_url: any) {
      socket = this;
    }
    send() {}
    close() {
      this.closed = true;
      this.onclose?.();
    }
  }
  try {
    globalThis.WebSocket = FakeSocket as any;
    const client = new RoomClient(
      "http://localhost:3000",
      { type: "join", army: "royal", code: "000000000000" },
      () => {},
      () => {},
      (s) => status.push(s),
    );
    socket.onopen();
    socket.onmessage({
      data: JSON.stringify({
        type: "error",
        message: "Room not found or expired.",
      }),
    });
    assert.equal(socket.closed, true);
    assert.equal(status.at(-1), "Room not found or expired.");
    assert.ok(!status.some((s) => s.includes("forfeits")));
    client.close();
  } finally {
    globalThis.WebSocket = original;
  }
});
