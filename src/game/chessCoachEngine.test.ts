import test from 'node:test';
import assert from 'node:assert/strict';
import { Chess } from 'chess.js';
import {
  analyzePlayerMove,
  calculateEloDelta,
  checkBlunderGuard,
  computeMoveAccuracy,
  computeTacticalVision,
  evaluatePositionCp,
  getRankTitle,
  selectBotMove,
} from './chessCoachEngine';
import { applyMoveToPieceInstances, buildPiecesFromFen, determineCombatRole } from './pieceTracker';

test('opening move e4 is recognized as Book or Optimal with high accuracy', () => {
  const startFen = new Chess().fen();
  const analysis = analyzePlayerMove(startFen, { from: 'e2', to: 'e4' }, 1);

  assert.equal(analysis.san, 'e4');
  assert.ok(
    analysis.verdict === 'Book' || analysis.verdict === 'Optimal' || analysis.verdict === 'Best',
    `Expected Book, Optimal, or Best, got ${analysis.verdict}`
  );
  assert.ok(analysis.accuracy >= 90);
  assert.ok(analysis.whyReasons.length >= 2);
});

test('hanging a Queen in front of a defended pawn is flagged as a Blunder with causal explanation', () => {
  const chess = new Chess();
  chess.move('e4');
  chess.move('e5');
  chess.move('Qh5');
  chess.move('Nc6');
  const fenBeforeBlunder = chess.fen();

  const analysis = analyzePlayerMove(fenBeforeBlunder, { from: 'h5', to: 'e5' }, 3);

  assert.equal(analysis.verdict, 'Blunder');
  assert.ok(analysis.cpLoss > 300, `Expected heavy cpLoss > 300, got ${analysis.cpLoss}`);
  assert.notEqual(analysis.bestMoveSan, 'Qxe5+');
  assert.ok(analysis.whyReasons.length >= 2);
  assert.ok(analysis.optimalComparison.includes(analysis.bestMoveSan));
});

test('blunder guard catches devastating queen blunders prior to move execution', () => {
  const chess = new Chess();
  chess.move('e4');
  chess.move('e5');
  chess.move('Qh5');
  chess.move('Nc6');

  const check = checkBlunderGuard(chess.fen(), { from: 'h5', to: 'e5' });
  assert.equal(check.isBlunder, true);
  assert.ok(check.warningText?.includes('Blunder Guard'));
});

test('computeTacticalVision calculates square controls and danger squares accurately', () => {
  const chess = new Chess();
  const vision = computeTacticalVision(chess);

  // In initial chess position, white pawns control d3, e3, f3 etc.
  assert.ok(vision.controlMap['e3']);
  assert.equal(vision.controlMap['e3'].whiteControl, 1);
  assert.equal(vision.controlMap['e3'].netLeader, 'w');
  assert.equal(vision.dangerSquares.size, 0); // No hanging pieces on initial board
});

test('combat role mapping assigns cinematic animation keys to captures', () => {
  assert.equal(determineCombatRole('n', true), 'knight_charge');
  assert.equal(determineCombatRole('r', true), 'rook_ballista');
  assert.equal(determineCombatRole('q', true), 'queen_sorcery');
  assert.equal(determineCombatRole('p', false), undefined);
});

test('pieceTracker preserves character IDs across walks, captures, and castling', () => {
  const chess = new Chess();
  let pieces = buildPiecesFromFen(chess.fen());
  assert.equal(pieces.length, 32);

  const m1 = chess.move('e4')!;
  const r1 = applyMoveToPieceInstances(pieces, m1, chess, 1);
  pieces = r1.nextPieces;
  assert.equal(r1.animEvent.pieceId, 'w_p_e2');
  assert.equal(r1.animEvent.from, 'e2');
  assert.equal(r1.animEvent.to, 'e4');

  chess.move('e5') && (pieces = applyMoveToPieceInstances(pieces, chess.history({ verbose: true }).at(-1)!, chess, 2).nextPieces);
  chess.move('Nf3') && (pieces = applyMoveToPieceInstances(pieces, chess.history({ verbose: true }).at(-1)!, chess, 3).nextPieces);
  chess.move('Nc6') && (pieces = applyMoveToPieceInstances(pieces, chess.history({ verbose: true }).at(-1)!, chess, 4).nextPieces);
  chess.move('Bc4') && (pieces = applyMoveToPieceInstances(pieces, chess.history({ verbose: true }).at(-1)!, chess, 5).nextPieces);
  chess.move('Nf6') && (pieces = applyMoveToPieceInstances(pieces, chess.history({ verbose: true }).at(-1)!, chess, 6).nextPieces);

  const castleMove = chess.move('O-O')!;
  const castleRes = applyMoveToPieceInstances(pieces, castleMove, chess, 7);
  assert.equal(castleRes.animEvent.pieceId, 'w_k_e1');
  assert.ok(castleRes.animEvent.rookCastleMove);
  assert.equal(castleRes.animEvent.rookCastleMove?.from, 'h1');
  assert.equal(castleRes.animEvent.rookCastleMove?.to, 'f1');
});
