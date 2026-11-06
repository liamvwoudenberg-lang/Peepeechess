import WebSocket from 'ws';
import assert from 'node:assert/strict';

const url = process.env.AUDIT_WS_URL || 'ws://localhost:3000/ws';
assert.match(url, /^ws:\/\/(localhost|127\.0\.0\.1):\d+\/ws$/, 'Review probes only target the local test server');

async function connect() {
  const ws = new WebSocket(url);
  const messages = [];
  ws.on('message', raw => messages.push(JSON.parse(String(raw))));
  await new Promise((resolve, reject) => { ws.once('open', resolve); ws.once('error', reject); });
  const next = async (type, after = 0) => {
    const start = Date.now();
    while (Date.now() - start < 6000) {
      const found = messages.slice(after).find(m => m.type === type);
      if (found) return found;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw new Error(`No ${type} message`);
  };
  await next('welcome');
  return { ws, next, messages, send: value => ws.send(JSON.stringify(value)) };
}

const player = await connect();
const outsider = await connect();
try {
  const startedAt = Date.now();
  player.send({ type: 'queue:join' });
  const start = await player.next('match:start');
  console.log(JSON.stringify({ probe: 'ranked-queue-fallback', elapsedMs: Date.now() - startedAt, matchId: start.match.matchId, opponent: start.match.black, isSiegeIncrement: start.match.isSiegeIncrement }));
  const oldRating = player.messages.find(m => m.type === 'welcome').rating;
  const beforeResign = player.messages.length;
  outsider.send({ type: 'match:resign', matchId: start.match.matchId });
  await new Promise(resolve => setTimeout(resolve, 100));
  player.send({ type: 'match:move', matchId: start.match.matchId, from: 'e2', to: 'e4' });
  await new Promise(resolve => setTimeout(resolve, 100));
  console.log(JSON.stringify({ probe: 'nonparticipant-resigns-match', endMessages: player.messages.slice(beforeResign).filter(m => m.type === 'match:over').length, subsequentLegalMoveBroadcasts: player.messages.slice(beforeResign).filter(m => m.type === 'match:move_applied').length }));
  player.send({ type: 'room:create' });
  const room = await player.next('room:created');
  const after = player.messages.length;
  outsider.send({ type: 'room:join', roomCode: room.roomCode });
  const humanMatch = await player.next('match:start', after);
  const outsiderStart = await outsider.next('match:start');
  const playerState = humanMatch.match[humanMatch.match.yourColor === 'w' ? 'white' : 'black'];
  console.log(JSON.stringify({ probe: 'rating-after-outsider-resignation-of-bot-match', ratingBefore: oldRating, ratingAfter: playerState.rating }));
  const white = humanMatch.match.yourColor === 'w' ? player : outsider;
  const black = white === player ? outsider : player;
  const errorsAfter = black.messages.length;
  black.send({ type: 'match:move', matchId: humanMatch.match.matchId, from: 'e7', to: 'e5' });
  await new Promise(resolve => setTimeout(resolve, 80));
  console.log(JSON.stringify({ probe: 'out-of-turn-move', broadcasts: black.messages.slice(errorsAfter).filter(m => m.type === 'match:move_applied').length }));
  white.send({ type: 'match:move', matchId: humanMatch.match.matchId, from: 'e2', to: 'e4' });
  const applied = await white.next('match:move_applied');
  console.log(JSON.stringify({ probe: 'human-match-legal-move', san: applied.move.san, fen: applied.fen, whiteTimeMs: applied.whiteTimeMs, blackTimeMs: applied.blackTimeMs }));
  white.send({ type: 'match:resign', matchId: humanMatch.match.matchId });
  await new Promise(resolve => setTimeout(resolve, 100));
  console.log(JSON.stringify({ probe: 'legitimate-resignation-notification', endMessages: white.messages.filter(m => m.type === 'match:over').length }));
} finally {
  player.ws.close();
  outsider.ws.close();
}
