import { MoveAnalysis } from '../game/types';
import { GameReviewReport, KeyMoment } from '../types/chess';

/**
 * Calculates a standard Chess.com / Lichess-style non-linear move accuracy score
 * based on centipawn loss.
 */
export function calculateMoveAccuracy(cpLoss: number): number {
  if (cpLoss <= 0) return 100;
  // Non-linear exponential curve: 0 cp = 100%, 50 cp = 88%, 150 cp = 65%, 300+ cp = < 35%
  const acc = 103.1668 * Math.exp(-0.0039 * cpLoss) - 3.1668;
  return Math.max(0, Math.min(100, Math.round(acc)));
}

/**
 * Generates full post-game analysis report, classifications, and interactive retry key moments.
 */
export function generateGameReviewReport(allAnalyses: MoveAnalysis[]): GameReviewReport {
  const whiteMoves = allAnalyses.filter((m) => m.color === 'w');
  const blackMoves = allAnalyses.filter((m) => m.color === 'b');

  const calcAvgAcc = (moves: MoveAnalysis[]) => {
    if (moves.length === 0) return 100;
    const total = moves.reduce((sum, m) => sum + (m.accuracy || calculateMoveAccuracy(m.cpLoss)), 0);
    return Math.round(total / moves.length);
  };

  const whiteAccuracy = calcAvgAcc(whiteMoves);
  const blackAccuracy = calcAvgAcc(blackMoves);

  const initCounts = () => ({
    Brilliant: 0,
    Great: 0,
    Best: 0,
    Book: 0,
    Optimal: 0,
    Inaccuracy: 0,
    Mistake: 0,
    Blunder: 0,
  });

  const whiteClassificationCounts = initCounts();
  const blackClassificationCounts = initCounts();

  whiteMoves.forEach((m) => {
    if (m.verdict in whiteClassificationCounts) {
      whiteClassificationCounts[m.verdict as keyof typeof whiteClassificationCounts]++;
    }
  });

  blackMoves.forEach((m) => {
    if (m.verdict in blackClassificationCounts) {
      blackClassificationCounts[m.verdict as keyof typeof blackClassificationCounts]++;
    }
  });

  // Extract Key Moments (Inaccuracies, Mistakes, Blunders)
  const keyMoments: KeyMoment[] = [];
  let turningPointMoveNumber: number | null = null;
  let maxCpSwing = 0;

  allAnalyses.forEach((m, idx) => {
    if (m.verdict === 'Blunder' || m.verdict === 'Mistake' || m.verdict === 'Inaccuracy') {
      const moment: KeyMoment = {
        moveIndex: idx,
        moveNumber: m.moveNumber,
        color: m.color,
        fenBefore: m.fenBefore,
        playedMove: { from: m.from, to: m.to, san: m.san },
        bestMove: { from: m.bestMoveFrom, to: m.bestMoveTo, san: m.bestMoveSan },
        verdict: m.verdict as 'Inaccuracy' | 'Mistake' | 'Blunder',
        cpLoss: m.cpLoss,
        explanation: m.optimalComparison || m.whyReasons[0] || 'A missed tactical opportunity.',
        solved: false,
      };
      keyMoments.push(moment);

      if (m.cpLoss > maxCpSwing && m.cpLoss >= 180) {
        maxCpSwing = m.cpLoss;
        turningPointMoveNumber = m.moveNumber;
      }
    }
  });

  // Narrative summary
  let summaryNarrative = 'A balanced duel across the Citadel.';
  if (whiteAccuracy > blackAccuracy + 15) {
    summaryNarrative = 'White dominated the battlefield with superior positional harmony and central pressure.';
  } else if (blackAccuracy > whiteAccuracy + 15) {
    summaryNarrative = 'Black seized the tactical initiative and punished white defensive oversights.';
  } else if (whiteClassificationCounts.Blunder === 0 && blackClassificationCounts.Blunder === 0) {
    summaryNarrative = 'High-accuracy Grandmaster battle with precision play from both commanders.';
  } else {
    summaryNarrative = `Game swung dynamically around move ${turningPointMoveNumber || 10}. Review the key moments below to master the defensive lines.`;
  }

  return {
    whiteAccuracy,
    blackAccuracy,
    whiteClassificationCounts,
    blackClassificationCounts,
    keyMoments,
    summaryNarrative,
    turningPointMoveNumber,
  };
}
