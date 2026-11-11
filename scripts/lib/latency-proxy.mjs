// UDP impairment proxy for the ENet/DTLS tests. One proxy instance fronts the server for ONE client: every datagram in either
// direction is delayed by `delayMs` (+ uniform jitter), dropped with probability `loss`, or dropped completely during a
// blackout. A client's UDP endpoint is preserved across the NAT (see scripts/test-multiplayer.mjs for why). Everything random
// comes from a seeded LCG so a run is reproducible given the same packet schedule (wall-clock scheduling still varies).
//
// "RTT" in the test matrix = 2 x delayMs (+ mean jitter x 2). This is a userspace proxy on loopback: it models delay, jitter and
// independent random loss only. It does NOT model bandwidth limits, bursty loss, reordering beyond what jitter causes,
// NAT rebinding or MTU effects.
import dgram from 'node:dgram';

export async function startProxy(serverPort, { delayMs = 0, jitterMs = 0, loss = 0, seed = 1 } = {}) {
  const socket = dgram.createSocket('udp4');
  const upstreams = new Map();
  let state = seed >>> 0;
  const random = () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 2 ** 32; };
  const config = { delayMs, jitterMs, loss, blackout: false };
  const stats = { received: 0, dropped: 0, forwarded: 0, blackedOut: 0 };
  const timers = new Set();
  function forward(data, sender, destination) {
    stats.received++;
    if (config.blackout) { stats.blackedOut++; return; }
    if (config.loss > 0 && random() < config.loss) { stats.dropped++; return; }
    const delay = config.delayMs + (config.jitterMs > 0 ? random() * config.jitterMs : 0);
    const timer = setTimeout(() => {
      timers.delete(timer);
      if (config.blackout) { stats.blackedOut++; return; }
      sender.send(data, destination.port, destination.address);
      stats.forwarded++;
    }, delay);
    timers.add(timer);
  }
  socket.on('message', (data, info) => {
    const key = `${info.address}:${info.port}`;
    if (!upstreams.has(key)) {
      const upstream = dgram.createSocket('udp4');
      upstream.on('message', reply => forward(reply, socket, { port: info.port, address: info.address }));
      upstreams.set(key, upstream);
    }
    forward(data, upstreams.get(key), { port: serverPort, address: '127.0.0.1' });
  });
  await new Promise(resolve => socket.bind(0, '127.0.0.1', resolve));
  return {
    port: socket.address().port,
    config,
    stats,
    blackout(ms) { config.blackout = true; return new Promise(resolve => setTimeout(() => { config.blackout = false; resolve(); }, ms)); },
    close() { for (const timer of timers) clearTimeout(timer); for (const upstream of upstreams.values()) upstream.close(); socket.close(); },
  };
}

export async function freeUdpPort() {
  const socket = dgram.createSocket('udp4');
  await new Promise(resolve => socket.bind(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  socket.close();
  return port;
}
