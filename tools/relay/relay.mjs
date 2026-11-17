#!/usr/bin/env node
// Peepeechess relay: pairs a game host and ONE guest by an unguessable session id and forwards opaque binary WebSocket frames both
// ways. The game's ENet + DTLS stack runs END-TO-END through it (the relay never terminates DTLS): it sees only ciphertext, so it cannot
// read or alter a game, and the two players never learn each other's IP address. The relay operator (and the platform in front of it)
// can see both IPs; the relay itself does not log IPs, session ids or payloads.
//
//   node tools/relay/relay.mjs                      # PORT=8080 HOST=0.0.0.0 by default; put wss:// termination in front (PaaS, Caddy, nginx)
//
// Paths:  GET /healthz          -> {"ok":true,"sessions":n,"connections":n}
//         WS  /h/<sid>          -> the host registers session <sid> (32 lowercase hex characters, chosen by the host)
//         WS  /g/<sid>          -> the guest joins; only while the host is connected and no other guest is connected (one guest lock)
// Frames: binary frames are game datagrams (<= MAX_FRAME bytes), forwarded to the other side. The relay sends the host text frames
//         {"t":"ready"} (registered), {"t":"guest","on":true|false}; and the guest {"t":"host","on":true|false}.
// No dependencies: a minimal RFC 6455 server (masked client frames, fragmentation, ping/pong, close).
import http from 'node:http';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

export const DEFAULTS = {
  host: '0.0.0.0',
  port: 8080,
  maxSessions: 200,          // concurrent sessions
  maxConnections: 600,       // concurrent sockets (host + guest per session, plus handshakes)
  maxFrame: 2048,            // bytes per game datagram (ENet MTU is ~1400; DTLS adds a little)
  bytesPerSecond: 262144,    // per session, both directions together
  burstBytes: 524288,
  packetsPerSecond: 1500,
  burstPackets: 3000,
  connectsPerMinute: 30,     // per source address
  waitMs: 15 * 60 * 1000,    // a session whose guest never came expires after this
  idleMs: 5 * 60 * 1000,     // no datagram in either direction for this long once a guest was seen
  hostGraceMs: 30 * 1000,    // how long a session survives its host dropping (a reconnect keeps it)
  pingMs: 25 * 1000,
  handshakeMs: 8 * 1000,
  trustProxy: false,         // true behind a PaaS proxy: the first X-Forwarded-For address is used for the connect rate limit only
};

function encodeFrame(opcode, payload = Buffer.alloc(0)) {
  const len = payload.length;
  let header;
  if (len < 126) header = Buffer.from([0x80 | opcode, len]);
  else if (len < 65536) { header = Buffer.alloc(4); header[0] = 0x80 | opcode; header[1] = 126; header.writeUInt16BE(len, 2); }
  else { header = Buffer.alloc(10); header[0] = 0x80 | opcode; header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2); }
  return Buffer.concat([header, payload]);
}

class Bucket {
  constructor(perSecond, burst, now) { this.perSecond = perSecond; this.burst = burst; this.tokens = burst; this.at = now; }
  take(amount, now) {
    this.tokens = Math.min(this.burst, this.tokens + (now - this.at) * this.perSecond / 1000);
    this.at = now;
    if (this.tokens < amount) return false;
    this.tokens -= amount;
    return true;
  }
}

export function createRelay(options = {}) {
  const cfg = { ...DEFAULTS, ...options };
  const sessions = new Map();   // sid -> {host, guest, created, everGuest, lastTraffic, hostGone, bytes, packets, drops}
  const sockets = new Set();
  const connects = new Map();   // address -> Bucket (never logged, bounded)
  const stats = { forwarded: 0, dropped: 0, refused: 0 };

  const server = http.createServer((request, response) => {
    if (request.url === '/healthz') {
      response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      response.end(JSON.stringify({ ok: true, sessions: sessions.size, connections: sockets.size }));
      return;
    }
    response.writeHead(426, { 'content-type': 'text/plain' });
    response.end('Peepeechess relay: WebSocket only.\n');
  });
  server.headersTimeout = cfg.handshakeMs;

  function refuse(socket, status, text) {
    stats.refused++;
    try { socket.end(`HTTP/1.1 ${status} ${text}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`); } catch { socket.destroy(); }
  }

  function sourceAddress(request) {
    if (cfg.trustProxy) {
      const forwarded = String(request.headers['x-forwarded-for'] || '').split(',')[0].trim();
      if (forwarded) return forwarded;
    }
    return request.socket.remoteAddress || 'unknown';
  }

  function allowConnect(address, now) {
    if (!connects.has(address)) {
      if (connects.size >= 4096) {
        for (const [key, bucket] of connects) if (now - bucket.at > 120000) connects.delete(key);
        if (connects.size >= 4096) return false;
      }
      connects.set(address, new Bucket(cfg.connectsPerMinute / 60, cfg.connectsPerMinute, now));
    }
    return connects.get(address).take(1, now);
  }

  function send(connection, opcode, payload) {
    if (connection.closed) return;
    if (connection.socket.writableLength > 1 << 20) { close(connection, 1008, 'slow'); return; }   // back-pressure: a stalled peer is dropped
    connection.socket.write(encodeFrame(opcode, payload));
  }
  const sendJson = (connection, value) => send(connection, 0x1, Buffer.from(JSON.stringify(value)));

  function close(connection, code = 1000, reason = '') {
    if (connection.closed) return;
    connection.closed = true;
    try {
      const body = Buffer.alloc(2 + Buffer.byteLength(reason));
      body.writeUInt16BE(code, 0);
      body.write(reason, 2);
      connection.socket.end(encodeFrame(0x8, body));
    } catch { /* already gone */ }
    setTimeout(() => connection.socket.destroy(), 1000).unref();
    detach(connection);
  }

  function detach(connection) {
    sockets.delete(connection.socket);
    const session = connection.session;
    if (!session) return;
    if (connection.role === 'host' && session.host === connection) {
      session.host = null;
      session.hostGone = Date.now();
      if (session.guest) sendJson(session.guest, { t: 'host', on: false });
    } else if (connection.role === 'guest' && session.guest === connection) {
      session.guest = null;
      if (session.host) sendJson(session.host, { t: 'guest', on: false });
    }
  }

  function forward(connection, payload) {
    const session = connection.session;
    const now = Date.now();
    const other = connection.role === 'host' ? session.guest : session.host;
    if (!other) return;
    if (!session.bytes.take(payload.length, now) || !session.packets.take(1, now)) {
      stats.dropped++;
      if (++session.drops > 5000) close(connection, 1008, 'rate');
      return;
    }
    session.lastTraffic = now;
    const impair = cfg.testImpair;   // tests only: simulated latency and loss on the relay path (the relay stays in order, like TCP)
    if (impair) {
      if (impair.loss && Math.random() < impair.loss) { stats.dropped++; return; }
      const due = Math.max(now + (impair.delayMs || 0) + Math.random() * (impair.jitterMs || 0), connection.lastDue || 0);
      connection.lastDue = due;
      stats.forwarded++;
      setTimeout(() => send(other, 0x2, payload), Math.max(0, due - now));
      return;
    }
    stats.forwarded++;
    send(other, 0x2, payload);
  }

  function onMessage(connection, opcode, payload) {
    if (opcode === 0x2) forward(connection, payload);   // text frames from clients are ignored
  }

  function onData(connection, chunk) {
    connection.buffer = connection.buffer.length ? Buffer.concat([connection.buffer, chunk]) : chunk;
    for (;;) {
      const buffer = connection.buffer;
      if (buffer.length < 2) return;
      const fin = (buffer[0] & 0x80) !== 0;
      const opcode = buffer[0] & 0x0f;
      const masked = (buffer[1] & 0x80) !== 0;
      let length = buffer[1] & 0x7f;
      let offset = 2;
      if (length === 126) { if (buffer.length < 4) return; length = buffer.readUInt16BE(2); offset = 4; }
      else if (length === 127) {
        if (buffer.length < 10) return;
        const big = buffer.readBigUInt64BE(2);
        if (big > BigInt(cfg.maxFrame)) { close(connection, 1009, 'too big'); return; }
        length = Number(big); offset = 10;
      }
      if (!masked) { close(connection, 1002, 'unmasked'); return; }
      if (length > cfg.maxFrame) { close(connection, 1009, 'too big'); return; }
      if (buffer.length < offset + 4 + length) return;
      const mask = buffer.subarray(offset, offset + 4);
      const payload = Buffer.from(buffer.subarray(offset + 4, offset + 4 + length));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
      connection.buffer = buffer.subarray(offset + 4 + length);
      if (opcode === 0x8) { close(connection, 1000, ''); return; }
      if (opcode === 0x9) { send(connection, 0xA, payload); continue; }
      if (opcode === 0xA) { connection.alive = true; continue; }
      if (opcode === 0x0) {
        if (!connection.fragmentOpcode) { close(connection, 1002, 'bad continuation'); return; }
        connection.fragments.push(payload);
        connection.fragmentBytes += payload.length;
      } else if (opcode === 0x1 || opcode === 0x2) {
        if (connection.fragmentOpcode) { close(connection, 1002, 'bad fragment'); return; }
        connection.fragmentOpcode = opcode; connection.fragments = [payload]; connection.fragmentBytes = payload.length;
      } else { close(connection, 1002, 'bad opcode'); return; }
      if (connection.fragmentBytes > cfg.maxFrame) { close(connection, 1009, 'too big'); return; }
      if (fin) {
        const message = Buffer.concat(connection.fragments);
        const kind = connection.fragmentOpcode;
        connection.fragmentOpcode = 0; connection.fragments = []; connection.fragmentBytes = 0;
        onMessage(connection, kind, message);
        if (connection.closed) return;
      }
    }
  }

  server.on('upgrade', (request, socket) => {
    const now = Date.now();
    const address = sourceAddress(request);
    socket.on('error', () => socket.destroy());
    const match = /^\/([hg])\/([0-9a-f]{32})$/.exec(String(request.url || '').split('?')[0]);
    const key = request.headers['sec-websocket-key'];
    if (!match || !key || String(request.headers.upgrade || '').toLowerCase() !== 'websocket') return refuse(socket, 400, 'Bad Request');
    if (!allowConnect(address, now)) return refuse(socket, 429, 'Too Many Requests');
    if (sockets.size >= cfg.maxConnections) return refuse(socket, 503, 'Service Unavailable');
    const role = match[1] === 'h' ? 'host' : 'guest';
    const sid = match[2];
    let session = sessions.get(sid);
    if (role === 'host') {
      if (session && session.host) return refuse(socket, 409, 'Conflict');
      if (!session) {
        if (sessions.size >= cfg.maxSessions) return refuse(socket, 503, 'Service Unavailable');
        session = { host: null, guest: null, created: now, everGuest: false, lastTraffic: now, hostGone: 0,
          bytes: new Bucket(cfg.bytesPerSecond, cfg.burstBytes, now), packets: new Bucket(cfg.packetsPerSecond, cfg.burstPackets, now), drops: 0 };
        sessions.set(sid, session);
      }
    } else {
      if (!session || !session.host) return refuse(socket, 404, 'Not Found');
      if (session.guest) return refuse(socket, 409, 'Conflict');   // one guest at a time
    }
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${createHash('sha1').update(key + GUID).digest('base64')}\r\n\r\n`);
    socket.setNoDelay(true);
    socket.setTimeout(0);
    const connection = { socket, role, session, buffer: Buffer.alloc(0), fragments: [], fragmentOpcode: 0, fragmentBytes: 0, closed: false, alive: true };
    sockets.add(socket);
    if (role === 'host') { session.host = connection; session.hostGone = 0; }
    else { session.guest = connection; session.everGuest = true; session.lastTraffic = now; }
    socket.on('data', chunk => onData(connection, chunk));
    socket.on('close', () => { connection.closed = true; detach(connection); });
    if (role === 'host') {
      sendJson(connection, { t: 'ready' });
      if (session.guest) { sendJson(connection, { t: 'guest', on: true }); sendJson(session.guest, { t: 'host', on: true }); }
    } else {
      sendJson(connection, { t: 'host', on: true });
      sendJson(session.host, { t: 'guest', on: true });
    }
  });

  const sweeper = setInterval(() => {
    const now = Date.now();
    for (const [sid, session] of sessions) {
      const expired = (!session.everGuest && now - session.created > cfg.waitMs)
        || (session.everGuest && now - session.lastTraffic > cfg.idleMs)
        || (!session.host && session.hostGone && now - session.hostGone > cfg.hostGraceMs);
      if (expired) {
        if (session.host) close(session.host, 1001, 'expired');
        if (session.guest) close(session.guest, 1001, 'expired');
        sessions.delete(sid);
      }
    }
    for (const [address, bucket] of connects) if (now - bucket.at > 300000) connects.delete(address);
  }, cfg.sweepMs || 1000);
  sweeper.unref();

  const pinger = setInterval(() => {
    for (const session of sessions.values()) {
      for (const connection of [session.host, session.guest]) {
        if (!connection || connection.closed) continue;
        if (!connection.alive) { close(connection, 1001, 'no pong'); continue; }
        connection.alive = false;
        send(connection, 0x9);
      }
    }
  }, cfg.pingMs);
  pinger.unref();

  return {
    server,
    config: cfg,
    stats: () => ({ ...stats, sessions: sessions.size, connections: sockets.size }),
    listen: () => new Promise((resolve, reject) => { server.once('error', reject); server.listen(cfg.port, cfg.host, () => resolve(server.address().port)); }),
    close: () => new Promise(resolve => {
      clearInterval(sweeper); clearInterval(pinger);
      for (const socket of sockets) socket.destroy();
      server.close(() => resolve());
    }),
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const env = process.env;
  const number = (name, fallback) => (env[name] !== undefined && Number.isFinite(Number(env[name])) ? Number(env[name]) : fallback);
  const relay = createRelay({
    host: env.HOST || DEFAULTS.host, port: number('PORT', DEFAULTS.port), maxSessions: number('MAX_SESSIONS', DEFAULTS.maxSessions),
    maxConnections: number('MAX_CONNECTIONS', DEFAULTS.maxConnections), trustProxy: env.TRUST_PROXY === '1',
    waitMs: number('WAIT_MS', DEFAULTS.waitMs), idleMs: number('IDLE_MS', DEFAULTS.idleMs),
  });
  const port = await relay.listen();
  console.log(`Peepeechess relay listening on ${relay.config.host}:${port} (no IPs, session ids or payloads are logged)`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => relay.close().then(() => process.exit(0)));
}
