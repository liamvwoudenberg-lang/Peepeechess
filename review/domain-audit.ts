import { Chess } from 'chess.js';
import { CURATED_RATED_PUZZLES } from '../src/puzzles/puzzleDatabase';
import { MASTER_CLASS_LESSONS } from '../src/puzzles/masterClassLibrary';
import { evaluateLocalEndgameHeuristic } from '../src/analytics/tablebase';
import { getOpeningExplorerData } from '../src/analytics/openingExplorer';
import { computeMoveAccuracy } from '../src/game/chessCoachEngine';
import { calculateMoveAccuracy } from '../src/analytics/gameReview';

// Review probes: these report observed behavior; they are not regression tests.
for (const puzzle of CURATED_RATED_PUZZLES) {
  const chess = new Chess(puzzle.fen);
  const moves = [];
  for (const san of puzzle.solutionMoves) {
    try {
      const move = chess.move(san);
      moves.push({ supplied: san, actual: move.san, checkmate: chess.isCheckmate() });
    } catch (error) {
      moves.push({ supplied: san, error: String(error) });
      break;
    }
  }
  console.log(JSON.stringify({ probe: 'puzzle-line', id: puzzle.id, startsInCheck: new Chess(puzzle.fen).inCheck(), moves }));
}

for (const lesson of MASTER_CLASS_LESSONS) {
  for (const [index, step] of lesson.steps.entries()) {
    try {
      const chess = new Chess(step.fen);
      const move = chess.move(step.targetMoveSan);
      console.log(JSON.stringify({ probe: 'lesson-step', lesson: lesson.id, index, supplied: step.targetMoveSan, actual: move.san }));
    } catch (error) {
      console.log(JSON.stringify({ probe: 'lesson-step', lesson: lesson.id, index, error: String(error) }));
    }
  }
}

const pin = new Chess(CURATED_RATED_PUZZLES.find(p => p.id === 'puz_pin_1')!.fen);
pin.move('Qe2');
console.log(JSON.stringify({ probe: 'claimed-absolute-pin', legalKnightMoves: pin.moves({ square: 'e4' }) }));
const smother = new Chess(CURATED_RATED_PUZZLES.find(p => p.id === 'puz_smothered_1')!.fen);
smother.move('Qf7+');
console.log(JSON.stringify({ probe: 'claimed-smothered-mate', checkmate: smother.isCheckmate(), legalReplies: smother.moves() }));

const stalemateFen = '7k/5K2/6Q1/8/8/8/8/8 b - - 0 1';
console.log(JSON.stringify({ probe: 'stalemate-offline-evaluation', isStalemate: new Chess(stalemateFen).isStalemate(), reported: evaluateLocalEndgameHeuristic(stalemateFen) }));
const opening = new Chess();
opening.move('e4');
const candidates = getOpeningExplorerData(opening.fen(), ['e4']).moves;
console.log(JSON.stringify({ probe: 'opening-explorer-after-e4', fen: opening.fen(), candidates: candidates.map(m => ({ san: m.san, legal: opening.moves().includes(m.san) })) }));
console.log(JSON.stringify({ probe: 'two-accuracy-functions', centipawnLoss: 50, inGame: computeMoveAccuracy(50), reviewHelper: calculateMoveAccuracy(50) }));
