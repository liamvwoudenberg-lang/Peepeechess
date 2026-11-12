// Builds godot/contracts/royal/network/v1/{schema,fixtures}.json: the ADDITIVE wire message family of the battle-royal-v1 ruleset
// (protocol id `peepeechess-enet-royal-v1`). Nothing of network/v1 or contracts/v1 is edited: shared definitions are copied verbatim
// from the committed network v1 and royal v1 schemas, and tests/contracts/royal-network.test.ts fails if the committed files drift.
// A client opts in by sending RoyalHello (never Hello), so a v1 server/client can never misread a royal message and vice versa.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = path => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
export const SCHEMA_PATH = new URL('../godot/contracts/royal/network/v1/schema.json', import.meta.url);
export const FIXTURES_PATH = new URL('../godot/contracts/royal/network/v1/fixtures.json', import.meta.url);
const copy = value => JSON.parse(JSON.stringify(value));
const ref = name => ({ $ref: `#/$defs/${name}` });
const object = (properties, required = Object.keys(properties)) => ({ type: 'object', properties, required, additionalProperties: false });
const PROTOCOL = { const: 'peepeechess-enet-royal-v1' };
const VERSION = { const: 1 };
const RULESET = { const: 'battle-royal-v1' };

export function buildSchema(net = read('../godot/contracts/network/v1/schema.json'), royal = read('../godot/contracts/royal/v1/schema.json')) {
  const n = net.$defs;
  const defs = {};
  for (const name of Object.keys(royal.$defs)) defs[name] = copy(royal.$defs[name]);        // every royal type, verbatim
  for (const name of ['ClockState', 'InputResume', 'JoinMatch', 'MatchCommand', 'Ping', 'Pong', 'Ack', 'ClockSync']) defs[name] = copy(n[name]); // unchanged v1 session messages
  defs.RoyalHello = object({ schemaVersion: VERSION, protocol: PROTOCOL, rulesetId: RULESET, resumeToken: copy(n.Hello.properties.resumeToken) });
  defs.RoyalWelcome = object({ ...copy(n.Welcome.properties), protocol: PROTOCOL, rulesetId: RULESET, combatRoles: { type: 'array', items: { enum: ['p', 'n', 'b', 'r', 'q', 'k'] }, minItems: 0, maxItems: 6 } });
  defs.RoyalCreateMatch = object({ schemaVersion: VERSION, commandId: copy(n.CreateMatch.properties.commandId), rulesetId: RULESET, mode: { enum: ['battle'] }, initialMs: { const: 0 }, incrementMs: { const: 0 } });
  defs.RoyalMatchFrame = object({ ...copy(n.MatchFrame.properties), state: ref('RoyalMatchState') });
  // Pushed by the server in addition to RoyalMatchFrame so a client can present the sequence without diffing frames.
  defs.RoyalSequenceNotice = object({ schemaVersion: VERSION, kind: { enum: ['progress', 'duel_result', 'sequence_result'] }, matchId: copy(n.Ack.properties.matchId), progress: { anyOf: [ref('RoyalSequenceProgress'), { type: 'null' }] }, duel: { anyOf: [ref('RoyalDuelResult'), { type: 'null' }] }, sequence: { anyOf: [ref('RoyalSequenceResult'), { type: 'null' }] } });
  return { $schema: net.$schema, $id: 'https://peepeechess.invalid/contracts/royal/network/v1/schema.json', title: 'Peepeechess battle-royal-v1 wire messages (protocol peepeechess-enet-royal-v1)', $defs: defs };
}

export function buildFixtures() {
  const royalCases = read('../godot/contracts/royal/v1/fixtures.json');
  const netCases = read('../godot/contracts/network/v1/fixtures.json');
  const state = royalCases.find(c => c.name === 'valid RoyalMatchState (first duel pending)').payload;
  const progress = state.royal;
  const hello = netCases.find(c => c.type === 'Hello' && c.valid)?.payload;
  const token = hello?.resumeToken ?? null;
  const frame = { schemaVersion: 1, frameSequence: 1, status: 'active', state, clocks: { whiteMs: 0, blackMs: 0, initialMs: 0, incrementMs: 0, running: false, timed: false, turn: 'w' }, connected: { w: true, b: true }, ready: { w: true, b: true }, drawOffer: null, inputResume: null };
  const welcome = { schemaVersion: 1, protocol: 'peepeechess-enet-royal-v1', rulesetId: 'battle-royal-v1', playerId: 'player-a', sessionToken: 'a'.repeat(64), serverId: 'server-1', expiresInSeconds: 3600, combatRoles: ['p', 'n', 'b', 'r', 'q', 'k'] };
  const create = { schemaVersion: 1, commandId: 'create-1', rulesetId: 'battle-royal-v1', mode: 'battle', initialMs: 0, incrementMs: 0 };
  const hello2 = { schemaVersion: 1, protocol: 'peepeechess-enet-royal-v1', rulesetId: 'battle-royal-v1', resumeToken: null };
  const notice = { schemaVersion: 1, kind: 'progress', matchId: state.matchId, progress, duel: null, sequence: null };
  const c = (name, type, payload, valid = true) => ({ name, type, payload, valid });
  const without = (o, k) => { const x = copy(o); delete x[k]; return x; };
  return [
    c('valid RoyalHello', 'RoyalHello', hello2),
    c('valid RoyalHello with resume token', 'RoyalHello', { ...hello2, resumeToken: token ?? 'b'.repeat(64) }),
    c('RoyalHello with the v1 protocol id', 'RoyalHello', { ...hello2, protocol: 'peepeechess-enet-v1' }, false),
    c('RoyalHello without ruleset', 'RoyalHello', without(hello2, 'rulesetId'), false),
    c('valid RoyalWelcome', 'RoyalWelcome', welcome),
    c('RoyalWelcome with the v1 protocol id', 'RoyalWelcome', { ...welcome, protocol: 'peepeechess-enet-v1' }, false),
    c('valid RoyalCreateMatch', 'RoyalCreateMatch', create),
    c('RoyalCreateMatch classic', 'RoyalCreateMatch', { ...create, mode: 'classic' }, false),
    c('RoyalCreateMatch timed', 'RoyalCreateMatch', { ...create, initialMs: 60000 }, false),
    c('valid RoyalMatchFrame (first duel pending)', 'RoyalMatchFrame', frame),
    c('RoyalMatchFrame with a v1 legacy state', 'RoyalMatchFrame', { ...frame, state: { ...state, rulesetId: 'battle-checkmate-v1' } }, false),
    c('RoyalMatchFrame without royal progress', 'RoyalMatchFrame', { ...frame, state: without(state, 'royal') }, false),
    c('valid RoyalSequenceNotice (progress)', 'RoyalSequenceNotice', notice),
    c('RoyalSequenceNotice with an unknown kind', 'RoyalSequenceNotice', { ...notice, kind: 'winner' }, false),
    c('RoyalSequenceNotice with extra client-style field', 'RoyalSequenceNotice', { ...notice, kingHp: 999 }, false),
  ];
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeFileSync(SCHEMA_PATH, JSON.stringify(buildSchema(), null, 2) + '\n');
  writeFileSync(FIXTURES_PATH, JSON.stringify(buildFixtures(), null, 2) + '\n');
  console.log('wrote godot/contracts/royal/network/v1/{schema,fixtures}.json');
}
