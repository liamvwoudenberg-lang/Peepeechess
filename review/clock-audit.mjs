import WebSocket from 'ws';
import { writeFileSync } from 'node:fs';
const file = process.env.AUDIT_CLOCK_FILE;
if (!file) throw new Error('Missing AUDIT_CLOCK_FILE');
writeFileSync(file, '0');
const ws = new WebSocket('ws://localhost:3001/ws');
const messages = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const next = async type => {
  for (let i = 0; i < 500; i++) {
    const m = messages.find(m => m.type === type);
    if (m) return m;
    await delay(10);
  }
  throw new Error(`Missing ${type}`);
};
ws.on('message', data => messages.push(JSON.parse(String(data))));
await new Promise(resolve => ws.once('open', resolve));
await next('welcome');
ws.send(JSON.stringify({ type: 'sparring:start' }));
const start = await next('match:start');
writeFileSync(file, '360000');
await delay(150);
ws.send(JSON.stringify({ type: 'match:move', matchId: start.match.matchId, from: 'e2', to: 'e4' }));
const move = await next('match:move_applied');
console.log(JSON.stringify({ probe: 'move-after-clock-expiry', method: 'Date.now advanced six minutes in isolated local server', startWhiteTimeMs: start.match.whiteTimeMs, endWhiteTimeMs: move.whiteTimeMs, moveAccepted: move.move.san, endNotifications: messages.filter(m => m.type === 'match:over').length }));
ws.close();
