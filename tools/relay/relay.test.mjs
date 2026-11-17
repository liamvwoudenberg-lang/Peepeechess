// Relay tests: node --test tools/relay/relay.test.mjs   (uses Node's built-in WebSocket client, no dependencies)
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import net from 'node:net';
import { createRelay } from './relay.mjs';

const sid = () => randomBytes(16).toString('hex');

async function start(options = {}) {
  const relay = createRelay({ host: '127.0.0.1', port: 0, ...options });
  const port = await relay.listen();
  return { relay, port, url: `ws://127.0.0.1:${port}` };
}

function open(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.binaryType = 'arraybuffer';
    const inbox = { binary: [], text: [] };
    ws.addEventListener('message', event => {
      if (typeof event.data === 'string') inbox.text.push(JSON.parse(event.data));
      else inbox.binary.push(Buffer.from(event.data));
    });
    ws.addEventListener('open', () => resolve({ ws, inbox }), { once: true });
    ws.addEventListener('error', () => reject(new Error('refused')), { once: true });
  });
}

const settle = (ms = 60) => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(test_, ms = 3000) {
  const end = Date.now() + ms;
  while (!test_()) {
    if (Date.now() > end) throw new Error('timeout');
    await settle(10);
  }
}
const refused = promise => promise.then(() => false, () => true);

test('host registers, guest pairs, datagrams flow both ways', async () => {
  const { relay, url } = await start();
  const id = sid();
  const host = await open(`${url}/h/${id}`);
  await waitFor(() => host.inbox.text.some(m => m.t === 'ready'));
  const guest = await open(`${url}/g/${id}`);
  await waitFor(() => host.inbox.text.some(m => m.t === 'guest' && m.on));
  await waitFor(() => guest.inbox.text.some(m => m.t === 'host' && m.on));
  host.ws.send(Buffer.from([1, 2, 3]));
  guest.ws.send(Buffer.from([9, 8, 7, 6]));
  await waitFor(() => host.inbox.binary.length === 1 && guest.inbox.binary.length === 1);
  assert.deepEqual([...guest.inbox.binary[0]], [1, 2, 3]);
  assert.deepEqual([...host.inbox.binary[0]], [9, 8, 7, 6]);
  guest.ws.close();
  await waitFor(() => host.inbox.text.some(m => m.t === 'guest' && !m.on));
  host.ws.close();
  await relay.close();
});

test('a guest needs a registered host; paths and ids are validated', async () => {
  const { relay, url } = await start();
  assert.ok(await refused(open(`${url}/g/${sid()}`)), 'no host yet');
  assert.ok(await refused(open(`${url}/h/not-a-session`)), 'bad id');
  assert.ok(await refused(open(`${url}/x/${sid()}`)), 'bad role');
  assert.ok(await refused(open(`${url}/`)), 'no path');
  const health = await fetch(`${url.replace('ws', 'http')}/healthz`).then(r => r.json());
  assert.equal(health.ok, true);
  await relay.close();
});

test('one guest at a time (lock); a second host with the same id is refused; a guest can come back', async () => {
  const { relay, url } = await start();
  const id = sid();
  const host = await open(`${url}/h/${id}`);
  const first = await open(`${url}/g/${id}`);
  assert.ok(await refused(open(`${url}/g/${id}`)), 'second guest while the first is connected');
  assert.ok(await refused(open(`${url}/h/${id}`)), 'second host');
  first.ws.close();
  await waitFor(() => host.inbox.text.some(m => m.t === 'guest' && !m.on));
  const again = await open(`${url}/g/${id}`);   // reconnect after a drop
  again.ws.send(Buffer.from([5]));
  await waitFor(() => host.inbox.binary.length === 1);
  again.ws.close(); host.ws.close();
  await relay.close();
});

test('traffic never crosses between sessions', async () => {
  const { relay, url } = await start();
  const a = sid(); const b = sid();
  const hostA = await open(`${url}/h/${a}`); const hostB = await open(`${url}/h/${b}`);
  const guestA = await open(`${url}/g/${a}`);
  guestA.ws.send(Buffer.from([42]));
  await waitFor(() => hostA.inbox.binary.length === 1);
  await settle(100);
  assert.equal(hostB.inbox.binary.length, 0);
  for (const c of [hostA, hostB, guestA]) c.ws.close();
  await relay.close();
});

test('size, rate and session caps', async () => {
  const { relay, url } = await start({ maxFrame: 64, maxSessions: 2, bytesPerSecond: 100, burstBytes: 100, packetsPerSecond: 1000, burstPackets: 1000 });
  const id = sid();
  const host = await open(`${url}/h/${id}`);
  const guest = await open(`${url}/g/${id}`);
  for (let i = 0; i < 20; i++) guest.ws.send(Buffer.alloc(40, i));   // 800 bytes against a 100 byte budget
  await settle(300);
  assert.ok(host.inbox.binary.length >= 1 && host.inbox.binary.length <= 4, `rate cap forwarded ${host.inbox.binary.length}`);
  assert.ok(relay.stats().dropped > 0);
  const closed = new Promise(resolve => guest.ws.addEventListener('close', resolve, { once: true }));
  guest.ws.send(Buffer.alloc(200));   // bigger than maxFrame: the connection is closed
  await closed;
  const other = sid(); const third = sid();
  const h2 = await open(`${url}/h/${other}`);
  assert.ok(await refused(open(`${url}/h/${third}`)), 'third session over the cap');
  host.ws.close(); h2.ws.close();
  await relay.close();
});

test('per-address connection rate limit', async () => {
  const { relay, url } = await start({ connectsPerMinute: 3 });
  const sockets = [];
  let accepted = 0;
  for (let i = 0; i < 6; i++) {
    try { sockets.push(await open(`${url}/h/${sid()}`)); accepted++; } catch { /* refused */ }
  }
  assert.equal(accepted, 3);
  for (const s of sockets) s.ws.close();
  await relay.close();
});

test('expiry: a session nobody joined and an idle session end; a host drop is forgiven within the grace time', async () => {
  const { relay, url } = await start({ waitMs: 300, idleMs: 400, hostGraceMs: 300, sweepMs: 50 });
  const lonely = sid();
  const host = await open(`${url}/h/${lonely}`);
  const closed = new Promise(resolve => host.ws.addEventListener('close', resolve, { once: true }));
  await closed;   // waitMs
  assert.ok(await refused(open(`${url}/g/${lonely}`)));
  const id = sid();
  const h2 = await open(`${url}/h/${id}`);
  const g2 = await open(`${url}/g/${id}`);
  const gClosed = new Promise(resolve => g2.ws.addEventListener('close', resolve, { once: true }));
  await gClosed;   // idleMs without traffic
  h2.ws.close();
  const id3 = sid();
  const h3 = await open(`${url}/h/${id3}`);
  const g3 = await open(`${url}/g/${id3}`);
  h3.ws.close();   // host drops, comes back inside the grace time
  await settle(80);
  const back = await open(`${url}/h/${id3}`);
  g3.ws.send(Buffer.from([1]));
  await waitFor(() => back.inbox.binary.length === 1);
  back.ws.close(); g3.ws.close();
  await relay.close();
});

test('malformed input does not crash the relay: unmasked frame, bad opcode, junk', async () => {
  const { relay, port, url } = await start();
  const id = sid();
  const host = await open(`${url}/h/${id}`);
  await new Promise(resolve => {
    const socket = net.connect(port, '127.0.0.1', () => {
      socket.write(`GET /g/${id} HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n`);
      setTimeout(() => { socket.write(Buffer.from([0x82, 0x03, 1, 2, 3])); }, 50);   // unmasked client frame
    });
    socket.on('close', resolve);
    socket.on('error', resolve);
    setTimeout(() => { socket.destroy(); resolve(); }, 800);
  });
  await new Promise(resolve => {
    const socket = net.connect(port, '127.0.0.1', () => { socket.write(Buffer.from('garbage\r\n\r\n')); });
    socket.on('close', resolve); socket.on('error', resolve);
    setTimeout(() => { socket.destroy(); resolve(); }, 500);
  });
  const health = await fetch(`${url.replace('ws', 'http')}/healthz`).then(r => r.json());
  assert.equal(health.ok, true);
  host.ws.close();
  await relay.close();
});
