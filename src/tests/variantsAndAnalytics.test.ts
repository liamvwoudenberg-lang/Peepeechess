import test from 'node:test';
import assert from 'node:assert/strict';
import { Chess, Square } from 'chess.js';
import { generateChess960BackRank, generateChess960Fen } from '../variants/chess960';
import {
  checkKingOfTheHillWin,
  computeAtomicExplosion,
  updateThreeCheckState,
  createInitialVariantState,
} from '../variants/variantRules';
import { evaluateLocalEndgameHeuristic } from '../analytics/tablebase';
import { calculateMoveAccuracy, generateGameReviewReport } from '../analytics/gameReview';
import { evaluateAntiCheatTelemetry } from '../security/antiCheatEngine';

test('Chess960 generator satisfies all FIDE constraints', () => {
  for (let i = 0; i < 20; i++) {
    const { backRank, index } = generateChess960BackRank(i * 47);
    assert.equal(backRank.length, 8, 'Back rank must have 8 pieces');

    // 1. Bishops on opposite colors
    const bishopIndices: number[] = [];
    backRank.forEach((p, idx) => {
      if (p === 'B') bishopIndices.push(idx);
    });
    assert.equal(bishopIndices.length, 2, 'Must have exactly 2 bishops');
    assert.notEqual(bishopIndices[0] % 2, bishopIndices[1] % 2, 'Bishops must be on opposite-colored squares');

    // 2. King strictly between the two Rooks
    const rookIndices: number[] = [];
    let kingIndex = -1;
    backRank.forEach((p, idx) => {
      if (p === 'R') rookIndices.push(idx);
      if (p === 'K') kingIndex = idx;
    });
    assert.equal(rookIndices.length, 2, 'Must have exactly 2 rooks');
    assert.ok(kingIndex > rookIndices[0] && kingIndex < rookIndices[1], 'King must sit strictly between the two rooks');
  }

  const setup = generateChess960Fen(518); // 518 is standard chess in Fischer 960
  assert.ok(setup.fen.includes('w KQkq - 0 1'), 'Generated FEN must contain valid FIDE castling flags');
});

test('King of the Hill variant awards instant victory when monarch reaches center', () => {
  // White king on d4
  const chessWin = new Chess('8/8/8/8/3K4/8/8/4k3 w - - 0 1');
  const winCheck = checkKingOfTheHillWin(chessWin);
  assert.ok(winCheck !== null, 'Monarch on d4 must trigger King of the Hill win');
  assert.equal(winCheck?.winner, 'w');

  // Kings not on hill
  const chessNoWin = new Chess('8/8/8/8/8/8/8/K3k3 w - - 0 1');
  assert.equal(checkKingOfTheHillWin(chessNoWin), null);
});

test('3-Check variant tracks checks and triggers win on 3rd check', () => {
  let state = createInitialVariantState('three_check');
  const chess = new Chess('4k3/4R3/8/8/8/8/8/4K3 b - - 0 1'); // In check

  // First check
  let res = updateThreeCheckState(state, chess, 'w');
  assert.equal(res.state.threeCheckCount.white, 1);
  assert.equal(res.winner, null);

  // Second check
  res = updateThreeCheckState(res.state, chess, 'w');
  assert.equal(res.state.threeCheckCount.white, 2);
  assert.equal(res.winner, null);

  // Third check -> Win!
  res = updateThreeCheckState(res.state, chess, 'w');
  assert.equal(res.state.threeCheckCount.white, 3);
  assert.equal(res.winner, 'w');
  assert.ok(res.reason?.includes('3 Checks'));
});

test('Atomic chess vaporizes surrounding non-pawn pieces on capture while pawns survive', () => {
  // Capture on d5 where e5 has a Knight and c5 has a Pawn
  const chess = new Chess('rnbqkbnr/8/8/2p1n3/3P4/8/8/RNBQKBNR w KQkq - 0 1');
  // pawn on d4 captures on e5
  const explosion = computeAtomicExplosion(chess, 'e5' as Square);
  assert.ok(explosion.explodedSquares.includes('e5'), 'Target capture square must explode');
  // Pawn on c5 should not explode because pawns are immune to collateral explosion
  assert.ok(!explosion.explodedSquares.includes('c5'), 'Collateral pawn should survive atomic blast');
});

test('Syzygy tablebase heuristics correctly classify elementary endgames', () => {
  // Lone kings (8 ranks)
  const tbKings = evaluateLocalEndgameHeuristic('8/8/8/8/4k3/8/8/4K3 w - - 0 1');
  assert.equal(tbKings.category, 'draw');
  assert.equal(tbKings.pieceCount, 2);

  // King + Queen vs King (8 ranks)
  const tbKQ = evaluateLocalEndgameHeuristic('8/8/8/8/4k3/8/8/4KQ2 w - - 0 1');
  assert.equal(tbKQ.category, 'win');
  assert.equal(tbKQ.pieceCount, 3);
});

test('Game review accuracy formula reflects centipawn loss accurately', () => {
  assert.equal(calculateMoveAccuracy(0), 100);
  assert.ok(calculateMoveAccuracy(50) >= 80 && calculateMoveAccuracy(50) <= 90);
  assert.ok(calculateMoveAccuracy(400) <= 30);
});

test('Anti-cheat telemetry detects highly uniform bot latency and engine correlation', () => {
  // Inhuman bot telemetry: 100% top choice, 2100ms with 0 latency variance
  const botTelemetry = Array.from({ length: 12 }, (_, i) => ({
    moveNumber: i + 1,
    san: 'Nf3',
    latencyMs: 2100 + (i % 2 === 0 ? 5 : -5),
    evalDifferenceCp: 0,
    isEngineFirstChoice: true,
    tabSwitchCount: 8,
  }));

  const report = evaluateAntiCheatTelemetry(botTelemetry);
  assert.ok(report.suspicionScore >= 70, 'Bot telemetry should produce high suspicion score');
  assert.equal(report.isFlaggedForAudit, true);
  assert.equal(report.recommendedPool, 'isolated');
});
