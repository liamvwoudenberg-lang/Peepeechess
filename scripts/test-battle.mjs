import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createBattleMatch, battleMoves, attemptBattleMove, resolveBattleCapture } from '../src/battle/rules.ts';
import { validate } from '../contracts/v1/validate.ts';
const temporary = mkdtempSync(join(tmpdir(), 'peepeechess-battle-'));
const env = { ...process.env };
for (const name of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
  env[name] = join(temporary, name); mkdirSync(env[name]);
}
const run = args => {
  const r = spawnSync(process.env.GODOT_BIN || 'godot', ['--headless', '--path', 'godot', ...args], { env, encoding: 'utf8', timeout: 180000 });
  process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
  if (r.error || r.status !== 0 || /SCRIPT ERROR|Parse Error|^ERROR:/m.test((r.stdout || '') + (r.stderr || ''))) throw r.error || Error(`Godot failed with exit ${r.status}`);
};
try {
  await import('./export-battle-stats.mjs');
  run(['--editor', '--import']);
  const output = join(temporary, 'snapshots.json');
  run(['--script', 'res://tests/battle/match_test.gd', '--', output]);
  for (const c of JSON.parse(readFileSync(output, 'utf8'))) if (!validate(c.type, c.payload)) throw Error('Battle MatchState violates v1 schema');
  run(['--script', 'res://tests/battle/flow_test.gd']);
  run(['--script', 'res://tests/battle/adapter_test.gd']);
  run(['--script', 'res://tests/battle/ui_test.gd']);
  let seed = 41831;
  const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; };
  const canonical = fen => {
    const fields = fen.split(' ');
    if (!battleMoves(fen).some(m => m.isEnPassant())) fields[3] = '-';
    return fields.join(' ');
  };
  const cases = [];
  function sample(fen) {
    const m = createBattleMatch(undefined, fen, 'ref');
    if (m.phase === 'complete') return;
    const legal = battleMoves(fen);
    const moves = [];
    for (const move of [...legal.filter(m => m.captured), ...legal.filter(m => !m.captured).slice(0, 2)]) {
      const prepared = attemptBattleMove(m, move.from, move.to, move.promotion || 'q');
      for (const outcome of move.captured ? ['attacker', 'defender'] : ['quiet']) {
        const after = outcome === 'quiet' ? prepared : resolveBattleCapture(prepared, prepared.pending.id, outcome === 'attacker' ? move.color : (move.color === 'w' ? 'b' : 'w'));
        moves.push({ from: move.from, to: move.to, promotion: move.promotion || 'q', outcome, after: canonical(after.fen), result: after.result || '', reason: after.reason || '' });
      }
    }
    cases.push({ fen, legal: legal.map(m => m.from + m.to + (m.promotion || '')), moves });
  }
  for (let game = 0; game < 5; game++) {
    let m = createBattleMatch(undefined, undefined, `game-${game}`);
    for (let ply = 0; ply < 60 && m.phase !== 'complete'; ply++) {
      if (ply % 3 === 0) sample(m.fen);
      const moves = battleMoves(m.fen);
      const move = moves[random() % moves.length];
      m = attemptBattleMove(m, move.from, move.to, move.promotion || 'q');
      if (m.pending) m = resolveBattleCapture(m, m.pending.id, random() % 2 ? 'w' : 'b');
    }
  }
  for (const fen of [
    '7k/8/8/4q3/3P4/8/8/7K w - - 0 1',
    '7k/8/8/3pP3/8/8/8/K7 w - d6 0 1',
    '7k/8/8/3pP3/4K3/8/8/8 w - d6 0 1',
    '1r5k/P7/8/8/8/8/8/K7 w - - 0 1',
    'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
    '7k/5Qr1/7K/8/8/8/8/8 w - - 0 1',
  ]) sample(fen);
  const corpus = join(temporary, 'reference.json');
  writeFileSync(corpus, JSON.stringify(cases));
  run(['--script', 'res://tests/battle/differential_test.gd', '--', corpus]);
  console.log('PASS: C0 rules, frozen requests, result validation, repeated battle transitions and UI (test-only combat double)');
} finally { rmSync(temporary, { recursive: true, force: true }); }
