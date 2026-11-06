import React, { useState, useEffect } from 'react';
import {
  X,
  Zap,
  Target,
  Swords,
  BookOpen,
  Trophy,
  Flame,
  AlertCircle,
  CheckCircle2,
  HelpCircle,
  Clock,
  RotateCcw,
  Sparkles,
} from 'lucide-react';
import { CURATED_RATED_PUZZLES } from '../puzzles/puzzleDatabase';
import {
  createInitialPuzzleRush,
  getNextRushPuzzle,
  handleRushAnswer,
  calculatePuzzleRatingChange,
} from '../puzzles/puzzleRushEngine';
import { MASTER_CLASS_LESSONS } from '../puzzles/masterClassLibrary';
import {
  MasterClassLesson,
  PuzzleBattleOpponent,
  PuzzleRushMode,
  PuzzleRushState,
  RatedPuzzle,
} from '../types/chess';
import { SquareId } from '../game/types';

interface PuzzleSuiteModalProps {
  isOpen: boolean;
  onClose: () => void;
  userPuzzleRating: number;
  onUpdatePuzzleRating: (newRating: number) => void;
  onLoadPuzzleOnBoard?: (fen: string, expectedMoveSan: string) => void;
}

export const PuzzleSuiteModal: React.FC<PuzzleSuiteModalProps> = ({
  isOpen,
  onClose,
  userPuzzleRating,
  onUpdatePuzzleRating,
  onLoadPuzzleOnBoard,
}) => {
  const [activeTab, setActiveTab] = useState<'rated' | 'rush' | 'battle' | 'masterclass'>('rated');

  // Rated Puzzle state
  const [puzzleIndex, setPuzzleIndex] = useState(0);
  const currentRatedPuzzle = CURATED_RATED_PUZZLES[puzzleIndex % CURATED_RATED_PUZZLES.length];
  const [ratedInput, setRatedInput] = useState('');
  const [ratedFeedback, setRatedFeedback] = useState<string | null>(null);
  const [solveStartTime, setSolveStartTime] = useState(Date.now());
  const [hintsUsed, setHintsUsed] = useState(false);

  // Puzzle Rush state
  const [rushMode, setRushMode] = useState<PuzzleRushMode>('3min');
  const [rushState, setRushState] = useState<PuzzleRushState>(createInitialPuzzleRush('3min'));
  const [rushInput, setRushInput] = useState('');
  const [rushFeedback, setRushFeedback] = useState<string | null>(null);

  // Puzzle Battle state (1v1 live race)
  const [battleOpponent, setBattleOpponent] = useState<PuzzleBattleOpponent>({
    id: 'opp_valkyrie',
    name: 'Valkyrie Astrid',
    rating: 1520,
    avatar: '⚔️',
    score: 0,
    strikes: 0,
  });
  const [battleUserScore, setBattleUserScore] = useState(0);
  const [battleTimeLeftSec, setBattleTimeLeftSec] = useState(120);
  const [isBattleActive, setIsBattleActive] = useState(false);

  // Master Class state
  const [selectedLesson, setSelectedLesson] = useState<MasterClassLesson>(MASTER_CLASS_LESSONS[0]);
  const [lessonStepIdx, setLessonStepIdx] = useState(0);
  const [lessonInput, setLessonInput] = useState('');
  const [lessonFeedback, setLessonFeedback] = useState<string | null>(null);

  // Timer tick for Puzzle Rush
  useEffect(() => {
    if (!rushState.isActive || rushState.isFinished || rushState.mode === 'survival') return;
    const interval = window.setInterval(() => {
      setRushState((prev) => {
        if (prev.timeRemainingMs <= 1000) {
          return { ...prev, timeRemainingMs: 0, isActive: false, isFinished: true };
        }
        return { ...prev, timeRemainingMs: prev.timeRemainingMs - 1000 };
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [rushState.isActive, rushState.isFinished, rushState.mode]);

  // Battle loop (simulated live opponent progress)
  useEffect(() => {
    if (!isBattleActive) return;
    const interval = window.setInterval(() => {
      setBattleTimeLeftSec((t) => {
        if (t <= 1) {
          setIsBattleActive(false);
          return 0;
        }
        return t - 1;
      });

      // Opponent periodically scores
      if (Math.random() > 0.65) {
        setBattleOpponent((prev) => ({
          ...prev,
          score: prev.score + 1,
        }));
      }
    }, 1000);
    return () => clearInterval(interval);
  }, [isBattleActive]);

  const handleTestRatedSolve = (e: React.FormEvent) => {
    e.preventDefault();
    if (!ratedInput.trim()) return;

    const clean = ratedInput.trim().toLowerCase();
    const target = currentRatedPuzzle.solutionMoves[0].toLowerCase();

    const isCorrect = clean === target;
    const solveSec = (Date.now() - solveStartTime) / 1000;
    const ratingDelta = calculatePuzzleRatingChange(userPuzzleRating, currentRatedPuzzle.rating, isCorrect, solveSec);

    if (isCorrect) {
      setRatedFeedback(`Victory! +${Math.max(4, ratingDelta)} Elo points earned.`);
      onUpdatePuzzleRating(userPuzzleRating + Math.max(4, ratingDelta));
      setTimeout(() => {
        setPuzzleIndex((prev) => prev + 1);
        setRatedInput('');
        setRatedFeedback(null);
        setHintsUsed(false);
        setSolveStartTime(Date.now());
      }, 1400);
    } else {
      setRatedFeedback(`Incorrect move. Grandmaster expected ${currentRatedPuzzle.solutionMoves[0]}. (-${Math.abs(ratingDelta)} Elo)`);
      onUpdatePuzzleRating(Math.max(400, userPuzzleRating + Math.min(-4, ratingDelta)));
    }
  };

  const handleTestRushSolve = (e: React.FormEvent) => {
    e.preventDefault();
    if (!rushInput.trim() || rushState.isFinished) return;

    const currentPuz = getNextRushPuzzle(rushState.currentPuzzleIdx);
    const clean = rushInput.trim().toLowerCase();
    const target = currentPuz.solutionMoves[0].toLowerCase();
    const isCorrect = clean === target;

    const nextState = handleRushAnswer(rushState, isCorrect);
    setRushState(nextState);

    if (isCorrect) {
      setRushFeedback('Strike Solved! +1');
      setRushInput('');
      setTimeout(() => setRushFeedback(null), 800);
    } else {
      setRushFeedback(`Wrong move! Strike ${nextState.strikes}/3.`);
      setRushInput('');
      setTimeout(() => setRushFeedback(null), 1100);
    }
  };

  const handleTestLessonStep = (e: React.FormEvent) => {
    e.preventDefault();
    const step = selectedLesson.steps[lessonStepIdx];
    if (!step || !lessonInput.trim()) return;

    const clean = lessonInput.trim().toLowerCase();
    const target = step.targetMoveSan.toLowerCase();

    if (clean === target) {
      setLessonFeedback(step.explanationOnSuccess);
      setTimeout(() => {
        if (lessonStepIdx + 1 < selectedLesson.steps.length) {
          setLessonStepIdx((prev) => prev + 1);
          setLessonInput('');
          setLessonFeedback(null);
        } else {
          setLessonFeedback('Lesson Completed! Outstanding tactical mastery.');
        }
      }, 1600);
    } else {
      setLessonFeedback(`Try again. Hint: ${step.hint}`);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-40 bg-black/80 backdrop-blur-md flex items-center justify-center p-3 sm:p-5">
      <div className="w-full max-w-4xl bg-stone-950 border-2 border-amber-700/60 rounded-2xl shadow-2xl text-stone-200 overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <header className="p-4 border-b border-stone-800 flex items-center justify-between bg-stone-900/70">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-950/80 border border-amber-600/60 flex items-center justify-center text-amber-400">
              <Zap className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-lg font-serif font-bold text-amber-200">
                Citadel Tactical Suite & Puzzles
              </h2>
              <div className="flex items-center gap-3 text-xs text-stone-400 font-mono">
                <span>Tactical Rating: <strong className="text-amber-300">{userPuzzleRating} Elo</strong></span>
                <span>• Puzzle Rush & 1v1 Battle Modes</span>
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg bg-stone-900 hover:bg-stone-800 text-stone-400 hover:text-white border border-stone-700 transition-all"
          >
            <X className="w-5 h-5" />
          </button>
        </header>

        {/* Tab Switcher */}
        <div className="flex border-b border-stone-800 bg-stone-900/30 overflow-x-auto text-xs">
          <button
            type="button"
            onClick={() => setActiveTab('rated')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'rated'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Target className="w-4 h-4 text-amber-400" />
            Elo-Rated Puzzles
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('rush')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'rush'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Flame className="w-4 h-4 text-amber-400" />
            Puzzle Rush (3-Strike)
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('battle')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'battle'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Swords className="w-4 h-4 text-amber-400" />
            Puzzle Battle (1v1 Race)
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('masterclass')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'masterclass'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <BookOpen className="w-4 h-4 text-amber-400" />
            Master Class & Drills
          </button>
        </div>

        {/* Tab Body */}
        <div className="p-4 sm:p-6 overflow-y-auto space-y-6 flex-1 text-xs">
          {/* TAB 1: ELO-RATED PUZZLE */}
          {activeTab === 'rated' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-amber-950 border border-amber-600/50 text-amber-300 font-bold uppercase">
                      {currentRatedPuzzle.motif.replace('_', ' ')}
                    </span>
                    <h3 className="text-sm font-serif font-bold text-amber-100">
                      {currentRatedPuzzle.title}
                    </h3>
                  </div>
                  <div className="font-mono text-stone-400 font-bold">
                    Puzzle Rating: {currentRatedPuzzle.rating}
                  </div>
                </div>

                <p className="text-stone-300 font-serif leading-relaxed text-xs">
                  {currentRatedPuzzle.description}
                </p>

                <div className="p-3 rounded-lg bg-stone-950 border border-stone-800 font-mono text-[11px] text-amber-400">
                  Side to move: <strong className="text-amber-200 uppercase">{currentRatedPuzzle.sideToMove === 'w' ? 'White' : 'Black'}</strong>
                </div>

                {/* Submit move input */}
                <form onSubmit={handleTestRatedSolve} className="space-y-2 pt-2">
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={ratedInput}
                      onChange={(e) => setRatedInput(e.target.value)}
                      placeholder={`Enter winning move (e.g. ${currentRatedPuzzle.solutionMoves[0]})`}
                      className="flex-1 bg-stone-950 border border-stone-700 rounded-lg px-3 py-2 text-xs text-stone-200 font-mono focus:outline-none focus:border-amber-500"
                    />
                    <button
                      type="submit"
                      className="py-2 px-4 rounded-lg bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs"
                    >
                      Submit Move
                    </button>
                    <button
                      type="button"
                      onClick={() => setHintsUsed(true)}
                      className="py-2 px-3 rounded-lg bg-stone-800 hover:bg-stone-700 border border-stone-700 text-stone-300 font-serif text-xs flex items-center gap-1"
                    >
                      <HelpCircle className="w-3.5 h-3.5" />
                      Hint
                    </button>
                  </div>

                  {hintsUsed && (
                    <div className="p-2 rounded bg-amber-950/40 border border-amber-700/50 text-[11px] text-amber-300 font-serif">
                      Hint: The key move starts from {currentRatedPuzzle.solutionMoves[0].slice(0, 2)}.
                    </div>
                  )}

                  {ratedFeedback && (
                    <div
                      className={`p-2.5 rounded text-xs font-mono font-bold ${
                        ratedFeedback.startsWith('Victory')
                          ? 'bg-emerald-950/70 text-emerald-300 border border-emerald-600'
                          : 'bg-red-950/70 text-red-300 border border-red-600'
                      }`}
                    >
                      {ratedFeedback}
                    </div>
                  )}
                </form>
              </div>
            </div>
          )}

          {/* TAB 2: PUZZLE RUSH */}
          {activeTab === 'rush' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  {(['3min', '5min', 'survival'] as PuzzleRushMode[]).map((m) => (
                    <button
                      key={m}
                      type="button"
                      onClick={() => {
                        setRushMode(m);
                        setRushState(createInitialPuzzleRush(m));
                      }}
                      className={`py-1.5 px-3 rounded-lg border text-xs capitalize font-serif font-medium transition-all ${
                        rushMode === m
                          ? 'bg-amber-600/30 text-amber-200 border-amber-500 font-bold'
                          : 'bg-stone-950 text-stone-400 border-stone-800'
                      }`}
                    >
                      {m === '3min' ? '3-Minute' : m === '5min' ? '5-Minute' : 'Survival'}
                    </button>
                  ))}
                </div>

                <div className="flex items-center gap-4 font-mono text-xs">
                  <div className="flex items-center gap-1 text-amber-300">
                    <Clock className="w-4 h-4" />
                    <span>{Math.ceil(rushState.timeRemainingMs / 1000)}s</span>
                  </div>
                  <div className="text-emerald-400 font-bold">Score: {rushState.score}</div>
                  <div className="text-red-400 font-bold">
                    Strikes: {'❌'.repeat(rushState.strikes)}{'⚪'.repeat(3 - rushState.strikes)}
                  </div>
                </div>
              </div>

              {/* Active Rush Card */}
              {rushState.isFinished ? (
                <div className="p-6 rounded-xl bg-stone-900 border border-stone-800 text-center space-y-3">
                  <Trophy className="w-10 h-10 mx-auto text-amber-400" />
                  <h3 className="text-lg font-serif font-bold text-amber-200">
                    Rush Finished! Final Score: {rushState.score}
                  </h3>
                  <button
                    type="button"
                    onClick={() => setRushState(createInitialPuzzleRush(rushMode))}
                    className="py-2 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold"
                  >
                    Play Again
                  </button>
                </div>
              ) : (
                <div className="p-4 rounded-xl bg-stone-900/50 border border-stone-800 space-y-3">
                  <div className="font-serif font-bold text-amber-200">
                    Puzzle #{rushState.currentPuzzleIdx + 1}: {getNextRushPuzzle(rushState.currentPuzzleIdx).title}
                  </div>
                  <p className="text-stone-300 text-xs font-serif">
                    {getNextRushPuzzle(rushState.currentPuzzleIdx).description}
                  </p>

                  <form onSubmit={handleTestRushSolve} className="flex gap-2 pt-2">
                    <input
                      type="text"
                      value={rushInput}
                      onChange={(e) => setRushInput(e.target.value)}
                      placeholder="Type winning move..."
                      className="flex-1 bg-stone-950 border border-stone-700 rounded-lg px-3 py-2 text-xs text-stone-200 font-mono focus:outline-none focus:border-amber-500"
                    />
                    <button
                      type="submit"
                      className="py-2 px-4 rounded-lg bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs"
                    >
                      Fire
                    </button>
                  </form>

                  {rushFeedback && (
                    <div className="p-2 rounded text-xs font-mono font-bold bg-amber-950/60 text-amber-300 border border-amber-700/50">
                      {rushFeedback}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* TAB 3: PUZZLE BATTLE */}
          {activeTab === 'battle' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-stone-900/80 border border-stone-800 flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-serif font-bold text-amber-200">
                    Citadel 1v1 Tactical Battle
                  </h3>
                  <p className="text-xs text-stone-400 font-serif">
                    Solve tactical rushes faster than your opposing champion
                  </p>
                </div>
                {!isBattleActive && (
                  <button
                    type="button"
                    onClick={() => {
                      setIsBattleActive(true);
                      setBattleUserScore(0);
                      setBattleOpponent((prev) => ({ ...prev, score: 0 }));
                      setBattleTimeLeftSec(120);
                    }}
                    className="py-2 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold"
                  >
                    Start Duel Race
                  </button>
                )}
              </div>

              {/* Live Battle Scoreboard */}
              <div className="p-4 rounded-xl bg-stone-900/60 border border-stone-800 grid grid-cols-3 gap-4 text-center items-center">
                <div className="p-3 rounded-lg bg-stone-950 border border-stone-800">
                  <div className="text-[10px] font-mono text-stone-400 uppercase">You (Commander)</div>
                  <div className="text-3xl font-mono font-bold text-amber-300 my-1">{battleUserScore}</div>
                  <div className="text-[10px] text-stone-500 font-mono">Strikes: 0/3</div>
                </div>

                <div className="text-center font-mono font-bold text-stone-400">
                  <div className="text-xs uppercase text-stone-500 mb-1">Time Left</div>
                  <div className="text-xl text-amber-200">{battleTimeLeftSec}s</div>
                </div>

                <div className="p-3 rounded-lg bg-stone-950 border border-stone-800">
                  <div className="text-[10px] font-mono text-stone-400 uppercase">
                    {battleOpponent.name} ({battleOpponent.rating})
                  </div>
                  <div className="text-3xl font-mono font-bold text-red-400 my-1">
                    {battleOpponent.score}
                  </div>
                  <div className="text-[10px] text-stone-500 font-mono">Live Rival Feed</div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 4: MASTER CLASS LIBRARY */}
          {activeTab === 'masterclass' && (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {/* Lessons Selector */}
              <div className="space-y-2">
                {MASTER_CLASS_LESSONS.map((lesson) => (
                  <button
                    key={lesson.id}
                    type="button"
                    onClick={() => {
                      setSelectedLesson(lesson);
                      setLessonStepIdx(0);
                      setLessonFeedback(null);
                      setLessonInput('');
                    }}
                    className={`w-full p-3 rounded-xl border text-left transition-all ${
                      selectedLesson.id === lesson.id
                        ? 'bg-amber-950/40 border-amber-500 text-amber-200 font-bold'
                        : 'bg-stone-900/60 border-stone-800 text-stone-400 hover:border-stone-700'
                    }`}
                  >
                    <div className="text-[10px] font-mono uppercase text-amber-400 font-bold mb-1">
                      {lesson.category} · {lesson.difficulty}
                    </div>
                    <div className="text-xs font-serif font-bold text-stone-200 leading-snug">
                      {lesson.title}
                    </div>
                  </button>
                ))}
              </div>

              {/* Lesson Interactive Stage */}
              <div className="md:col-span-2 p-4 rounded-xl bg-stone-900/80 border border-stone-800 space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-serif font-bold text-amber-200">
                    {selectedLesson.title}
                  </h3>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-stone-800 text-stone-300">
                    Step {lessonStepIdx + 1} of {selectedLesson.steps.length}
                  </span>
                </div>

                <p className="text-stone-300 text-xs font-serif leading-relaxed">
                  {selectedLesson.steps[lessonStepIdx]?.instruction}
                </p>

                <form onSubmit={handleTestLessonStep} className="space-y-2 pt-2">
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={lessonInput}
                      onChange={(e) => setLessonInput(e.target.value)}
                      placeholder={`Enter step move (e.g. ${selectedLesson.steps[lessonStepIdx]?.targetMoveSan})`}
                      className="flex-1 bg-stone-950 border border-stone-700 rounded-lg px-3 py-2 text-xs text-stone-200 font-mono focus:outline-none focus:border-amber-500"
                    />
                    <button
                      type="submit"
                      className="py-2 px-4 rounded-lg bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs"
                    >
                      Execute Step
                    </button>
                  </div>

                  {lessonFeedback && (
                    <div className="p-2.5 rounded text-xs font-serif bg-amber-950/60 text-amber-200 border border-amber-600/40">
                      {lessonFeedback}
                    </div>
                  )}
                </form>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
