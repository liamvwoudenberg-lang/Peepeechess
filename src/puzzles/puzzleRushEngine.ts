import { PuzzleRushMode, PuzzleRushState, RatedPuzzle } from '../types/chess';
import { CURATED_RATED_PUZZLES } from './puzzleDatabase';

export function createInitialPuzzleRush(mode: PuzzleRushMode): PuzzleRushState {
  const durations: Record<PuzzleRushMode, number> = {
    '3min': 180 * 1000,
    '5min': 300 * 1000,
    survival: 9999 * 1000, // unlimited time
  };

  return {
    mode,
    isActive: true,
    score: 0,
    strikes: 0,
    maxStrikes: 3,
    timeRemainingMs: durations[mode],
    currentPuzzleIdx: 0,
    isFinished: false,
  };
}

export function getNextRushPuzzle(currentIdx: number): RatedPuzzle {
  return CURATED_RATED_PUZZLES[currentIdx % CURATED_RATED_PUZZLES.length];
}

export function handleRushAnswer(
  state: PuzzleRushState,
  isCorrect: boolean
): PuzzleRushState {
  if (state.isFinished || !state.isActive) return state;

  if (isCorrect) {
    return {
      ...state,
      score: state.score + 1,
      currentPuzzleIdx: state.currentPuzzleIdx + 1,
    };
  } else {
    const nextStrikes = state.strikes + 1;
    const isFinished = nextStrikes >= state.maxStrikes;
    return {
      ...state,
      strikes: nextStrikes,
      isFinished,
      isActive: !isFinished,
      currentPuzzleIdx: state.currentPuzzleIdx + 1,
    };
  }
}

/**
 * Calculates dynamic puzzle Elo rating adjustment based on solve time and difficulty.
 */
export function calculatePuzzleRatingChange(
  userRating: number,
  puzzleRating: number,
  isCorrect: boolean,
  solveTimeSeconds: number
): number {
  const expected = 1 / (1 + Math.pow(10, (puzzleRating - userRating) / 400));
  let delta = 32 * ((isCorrect ? 1 : 0) - expected);

  // Speed bonus if solved within 8 seconds
  if (isCorrect && solveTimeSeconds <= 8) {
    delta += 4;
  } else if (!isCorrect && solveTimeSeconds > 30) {
    delta -= 3;
  }

  return Math.round(delta);
}
