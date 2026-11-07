import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Chess } from 'chess.js';
const temporary = mkdtempSync(join(tmpdir(), 'peepeechess-classic-'));
const env = { ...process.env };
for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
  env[key] = join(temporary, key);
  mkdirSync(env[key]);
}
const godot = process.env.GODOT_BIN || 'godot';
const run = args => {
  const r = spawnSync(godot, ['--headless', '--path', 'godot', ...args], { env, encoding: 'utf8', timeout: 180000 });
  process.stdout.write(r.stdout || '');
  process.stderr.write(r.stderr || '');
  if (r.error || r.status !== 0 || /SCRIPT ERROR|Parse Error|^ERROR:/m.test((r.stdout || '') + (r.stderr || ''))) {
    throw r.error || Error(`Godot failed with exit ${r.status}`);
  }
};
try {
  // Fresh checkout import registers classes and imports the original piece atlas.
  run(['--editor', '--import']);
  run(['--script', 'res://tests/classic/engine_test.gd']);
  const snapshots = join(temporary, 'snapshots.json');
  run(['--script', 'res://tests/classic/match_test.gd', '--', snapshots]);
  const { validate } = await import('../contracts/v1/validate.ts');
  for (const s of JSON.parse(readFileSync(snapshots, 'utf8'))) {
    if (!validate(s.type, s.payload)) throw Error('Native snapshot failed Node v1 schema');
  }
  let seed = 829517;
  const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; };
  const cases = [];
  const add = chess => {
    const fen = chess.fen({ forceEnpassantSquare: true });
    const moves = chess.moves({ verbose: true }).map(m => {
      chess.move(m);
      let after = chess.fen({ forceEnpassantSquare: true });
      // chess.js discards EP unless an adjacent enemy pawn exists. Native FEN
      // follows the original FEN spec: always record the passed square.
      if (m.piece === 'p' && Math.abs(Number(m.to[1]) - Number(m.from[1])) === 2) {
        const fields = after.split(' ');
        fields[3] = m.from[0] + ((Number(m.from[1]) + Number(m.to[1])) / 2);
        after = fields.join(' ');
      }
      chess.undo();
      return { uci: m.from + m.to + (m.promotion || ''), san: m.san, after };
    });
    cases.push({ fen, moves });
  };
  for (let game = 0; game < 6; game++) {
    const chess = new Chess();
    for (let ply = 0; ply < 44 && !chess.isGameOver(); ply++) {
      if (ply % 4 === 0) add(chess);
      const moves = chess.moves();
      chess.move(moves[random() % moves.length]);
    }
  }
  for (const fen of [
    'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
    'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
    '7k/8/8/3pP3/8/8/8/K7 w - d6 0 1',
    '7k/8/8/r4pPK/8/8/8/8 w - f6 0 1',
    '1r5k/P7/8/8/8/8/8/K7 w - - 0 1',
    '7k/8/8/8/8/2N1N3/8/K7 w - - 0 1',
  ]) add(new Chess(fen));
  const corpus = join(temporary, 'reference.json');
  writeFileSync(corpus, JSON.stringify(cases));
  run(['--script', 'res://tests/classic/differential_test.gd', '--', corpus]);
  run(['--script', 'res://tests/classic/views_test.gd']);
  run(['--quit-after', '3']);
  console.log('PASS: native Classic engine, authority, views, schemas and scene smoke');
} finally { rmSync(temporary, { recursive: true, force: true }); }
