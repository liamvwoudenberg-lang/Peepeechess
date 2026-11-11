// Builds godot/contracts/royal/v1/schema.json from the IMMUTABLE v1 schema plus the royal additions.
// The v1 definitions are copied verbatim (never edited); only the king-permitting Combatant/BattleRequest variants differ.
// Run `node scripts/build-royal-schema.mjs` to regenerate; tests/contracts/royal.test.ts fails if the committed file drifts.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const V1 = new URL('../godot/contracts/v1/schema.json', import.meta.url);
export const ROYAL_SCHEMA_PATH = new URL('../godot/contracts/royal/v1/schema.json', import.meta.url);
const copy = value => JSON.parse(JSON.stringify(value));
const int = (minimum, maximum) => ({ type: 'integer', minimum, maximum });
const num = (minimum, maximum) => ({ type: 'number', minimum, maximum });
const ref = name => ({ $ref: `#/$defs/${name}` });
const nullable = rule => ({ anyOf: [rule, { type: 'null' }] });
const object = (properties, required = Object.keys(properties)) => ({ type: 'object', properties, required, additionalProperties: false });
const list = (items, minItems, maxItems) => ({ type: 'array', items, minItems, maxItems });
const RULESET = { const: 'battle-royal-v1' };
const VERSION = { const: 1 };

export function buildRoyalSchema(v1 = JSON.parse(readFileSync(V1, 'utf8'))) {
  const d = v1.$defs;
  const id = copy(d.Combatant.properties.playerId);
  const reused = ['CharacterId', 'FighterStats', 'BattleResult', 'FighterSnapshot', 'CombatEvent', 'CombatSnapshot', 'Piece', 'HistoryEntry', 'ChessGameState'];
  const defs = {};
  for (const name of reused) defs[name] = copy(d[name]);

  // The only v1 rule the king breaks: Combatant.role excludes "k". Everything else is byte-for-byte v1.
  defs.RoyalCombatant = copy(d.Combatant);
  defs.RoyalCombatant.properties.role = { enum: ['p', 'n', 'b', 'r', 'q', 'k'] };
  defs.RoyalBattleRequest = copy(d.BattleRequest);
  defs.RoyalBattleRequest.properties.attacker = ref('RoyalCombatant');
  defs.RoyalBattleRequest.properties.defender = ref('RoyalCombatant');

  defs.RoyalKingState = object({ hp: int(0, 10000), stamina: num(0, 10000), cooldownTicks: int(0, 2147483647) });
  defs.RoyalKingCombatant = copy(d.Combatant);
  defs.RoyalKingCombatant.properties.role = { enum: ['k'] };
  defs.RoyalKingCombatant.properties.startHp = int(1, 10000);
  defs.RoyalKingCombatant.properties.startStamina = num(0, 10000);
  defs.RoyalKingCombatant.properties.startCooldown = int(0, 2147483647);
  defs.RoyalKingCombatant.required = [...defs.RoyalKingCombatant.required, 'startHp', 'startStamina', 'startCooldown'];

  const header = { schemaVersion: VERSION, rulesetId: RULESET };
  const requestFields = { battleId: id, matchId: id };
  defs.RoyalSequenceRequest = object({
    ...header, ...requestFields,
    expectedRevision: int(0, 2147483647),
    beforeFen: copy(d.BattleRequest.properties.beforeFen),
    mated: { enum: ['w', 'b'] },
    king: ref('RoyalKingCombatant'),
    attackers: list(ref('RoyalCombatant'), 1, 16),
    arenaId: copy(d.BattleRequest.properties.arenaId),
    startTick: int(0, 2147483647),
  });
  defs.RoyalDuelRequest = object({
    ...header, battleId: id,
    duelIndex: int(0, 15),
    duelCount: int(1, 16),
    kingStart: ref('RoyalKingState'),
    battle: ref('RoyalBattleRequest'),
  });
  defs.RoyalDuelResult = object({
    ...header, battleId: id,
    duelIndex: int(0, 15),
    duelCount: int(1, 16),
    result: ref('BattleResult'),
    kingEnd: ref('RoyalKingState'),
    kingSurvived: { type: 'boolean' },
  });
  defs.RoyalSequenceProgress = object({
    ...header, ...requestFields,
    status: { enum: ['active'] },
    duelIndex: int(0, 15),
    duelCount: int(1, 16),
    currentBattleId: nullable(id),
    king: ref('RoyalKingState'),
    defeated: list(id, 0, 16),
    remaining: list(id, 0, 16),
  });
  defs.RoyalSequenceResult = object({
    ...header, ...requestFields,
    expectedRevision: int(0, 2147483647),
    outcome: { enum: ['king_survived', 'king_fell', 'unplayable', 'abandoned'] },
    duels: list(ref('RoyalDuelResult'), 0, 16),
    defeated: list(id, 0, 16),
    kingEnd: ref('RoyalKingState'),
    resolvedTick: int(0, 2147483647),
    matchResult: nullable({ enum: ['1-0', '0-1', '1/2-1/2'] }),
    reason: nullable({ type: 'string', maxLength: 160 }),
    fenAfter: copy(d.BattleRequest.properties.beforeFen),
  });
  const matchState = copy(d.MatchState);
  matchState.properties.mode = { enum: ['battle'] };
  matchState.properties.rulesetId = RULESET;
  matchState.properties.battle = nullable(ref('RoyalBattleRequest'));
  matchState.properties.royal = nullable(ref('RoyalSequenceProgress'));
  matchState.required = [...matchState.required, 'royal'];
  defs.RoyalMatchState = matchState;

  return {
    $schema: v1.$schema,
    $id: 'https://peepeechess.invalid/contracts/royal/v1/schema.json',
    title: 'Peepeechess battle-royal-v1 last-stand sequence contracts',
    $defs: defs,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeFileSync(ROYAL_SCHEMA_PATH, JSON.stringify(buildRoyalSchema(), null, 2) + '\n');
  console.log('wrote godot/contracts/royal/v1/schema.json');
}
