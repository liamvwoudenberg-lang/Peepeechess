import React, { useState, useEffect } from 'react';
import {
  X,
  Compass,
  Database,
  BarChart3,
  TrendingUp,
  RefreshCw,
  Award,
  AlertTriangle,
  CheckCircle2,
  ChevronRight,
  Flame,
  Shield,
  Layers,
} from 'lucide-react';
import { MoveAnalysis, SquareId } from '../game/types';
import { querySyzygyTablebase, countPiecesFromFen } from '../analytics/tablebase';
import { getOpeningExplorerData } from '../analytics/openingExplorer';
import { generateGameReviewReport } from '../analytics/gameReview';
import { loadLifetimeStats } from '../analytics/statsDashboard';
import { SyzygyTablebaseResult, GameReviewReport, KeyMoment, LifetimeStats } from '../types/chess';

interface AnalyticsModalProps {
  isOpen: boolean;
  onClose: () => void;
  currentFen: string;
  analyses: MoveAnalysis[];
  onPlayMoveOnBoard?: (from: SquareId, to: SquareId) => void;
}

export const AnalyticsModal: React.FC<AnalyticsModalProps> = ({
  isOpen,
  onClose,
  currentFen,
  analyses,
  onPlayMoveOnBoard,
}) => {
  const [activeTab, setActiveTab] = useState<'review' | 'tablebase' | 'explorer' | 'stats'>('review');

  // Tablebase State
  const [tablebaseResult, setTablebaseResult] = useState<SyzygyTablebaseResult | null>(null);
  const [isQueryingTablebase, setIsQueryingTablebase] = useState(false);

  // Opening Explorer State
  const movesSan = analyses.map((a) => a.san);
  const openingData = getOpeningExplorerData(currentFen, movesSan);

  // Game Review State
  const [reviewReport, setReviewReport] = useState<GameReviewReport | null>(null);
  const [selectedKeyMoment, setSelectedKeyMoment] = useState<KeyMoment | null>(null);
  const [retryInput, setRetryInput] = useState('');
  const [retryFeedback, setRetryFeedback] = useState<string | null>(null);

  // Lifetime Stats State
  const [stats, setStats] = useState<LifetimeStats>(loadLifetimeStats());

  useEffect(() => {
    if (analyses.length > 0) {
      const rep = generateGameReviewReport(analyses);
      setReviewReport(rep);
      if (rep.keyMoments.length > 0) {
        setSelectedKeyMoment(rep.keyMoments[0]);
      }
    }
  }, [analyses]);

  useEffect(() => {
    setStats(loadLifetimeStats());
  }, [isOpen]);

  const handleQueryTablebase = async () => {
    setIsQueryingTablebase(true);
    const res = await querySyzygyTablebase(currentFen);
    setTablebaseResult(res);
    setIsQueryingTablebase(false);
  };

  const handleTestRetryMove = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedKeyMoment || !retryInput.trim()) return;

    const clean = retryInput.trim();
    if (
      clean.toLowerCase() === selectedKeyMoment.bestMove.san.toLowerCase() ||
      clean.toLowerCase() === `${selectedKeyMoment.bestMove.from}${selectedKeyMoment.bestMove.to}`.toLowerCase()
    ) {
      setRetryFeedback('Correct! You found the Grandmaster refutation!');
      selectedKeyMoment.solved = true;
      if (onPlayMoveOnBoard) {
        onPlayMoveOnBoard(selectedKeyMoment.bestMove.from, selectedKeyMoment.bestMove.to);
      }
    } else {
      setRetryFeedback(`Not quite. Grandmaster Aldric recommended ${selectedKeyMoment.bestMove.san}.`);
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
              <Compass className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-lg font-serif font-bold text-amber-200">
                Grandmaster Analytics & Competitive Suite
              </h2>
              <p className="text-xs text-stone-400 font-mono">
                Syzygy Tablebase · Opening Explorer · Game Review · Rating Progression
              </p>
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
            onClick={() => setActiveTab('review')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'review'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Award className="w-4 h-4 text-amber-400" />
            Game Review & Accuracy
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab('tablebase');
              if (!tablebaseResult) handleQueryTablebase();
            }}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'tablebase'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Database className="w-4 h-4 text-amber-400" />
            Syzygy 7-Piece Tablebase
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('explorer')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'explorer'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Layers className="w-4 h-4 text-amber-400" />
            Opening Explorer & ECO
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('stats')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'stats'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <TrendingUp className="w-4 h-4 text-amber-400" />
            Rating Progression & Stats
          </button>
        </div>

        {/* Tab Content */}
        <div className="p-4 sm:p-6 overflow-y-auto space-y-6 flex-1">
          {/* TAB 1: GAME REVIEW & ACCURACY */}
          {activeTab === 'review' && (
            <div className="space-y-6">
              {reviewReport ? (
                <>
                  {/* Accuracy Comparison */}
                  <div className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div className="p-3.5 rounded-lg bg-amber-950/20 border border-amber-600/30 text-center">
                      <div className="text-xs font-mono text-amber-400 uppercase">White Accuracy</div>
                      <div className="text-3xl font-mono font-bold text-amber-200 my-1">
                        {reviewReport.whiteAccuracy}%
                      </div>
                      <div className="text-[11px] text-stone-400 font-serif">
                        {reviewReport.whiteClassificationCounts.Brilliant} Brilliant ·{' '}
                        {reviewReport.whiteClassificationCounts.Best + reviewReport.whiteClassificationCounts.Optimal} Optimal ·{' '}
                        {reviewReport.whiteClassificationCounts.Blunder} Blunders
                      </div>
                    </div>

                    <div className="p-3.5 rounded-lg bg-stone-900 border border-stone-700 text-center">
                      <div className="text-xs font-mono text-stone-400 uppercase">Black Accuracy</div>
                      <div className="text-3xl font-mono font-bold text-stone-200 my-1">
                        {reviewReport.blackAccuracy}%
                      </div>
                      <div className="text-[11px] text-stone-400 font-serif">
                        {reviewReport.blackClassificationCounts.Brilliant} Brilliant ·{' '}
                        {reviewReport.blackClassificationCounts.Best + reviewReport.blackClassificationCounts.Optimal} Optimal ·{' '}
                        {reviewReport.blackClassificationCounts.Blunder} Blunders
                      </div>
                    </div>
                  </div>

                  {/* Summary Narrative */}
                  <div className="p-3.5 rounded-xl bg-stone-900/60 border border-stone-800 text-xs font-serif text-stone-300 leading-relaxed">
                    <span className="font-bold text-amber-300 block mb-1">Citadel Game Summary:</span>
                    {reviewReport.summaryNarrative}
                  </div>

                  {/* Interactive "Retry Key Moments" */}
                  <div>
                    <h3 className="text-xs font-mono uppercase text-amber-300 font-bold mb-3 flex items-center gap-1.5">
                      <AlertTriangle className="w-4 h-4 text-amber-400" />
                      Retry Key Moments ({reviewReport.keyMoments.length} Turning Points)
                    </h3>

                    {reviewReport.keyMoments.length === 0 ? (
                      <p className="text-xs text-stone-500 italic p-4 bg-stone-900/40 rounded-xl">
                        Clean game! No major tactical blunders detected in this match.
                      </p>
                    ) : (
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {/* Moments List */}
                        <div className="space-y-2 max-h-56 overflow-y-auto pr-1">
                          {reviewReport.keyMoments.map((km, idx) => (
                            <button
                              key={idx}
                              type="button"
                              onClick={() => {
                                setSelectedKeyMoment(km);
                                setRetryFeedback(null);
                                setRetryInput('');
                              }}
                              className={`w-full p-2.5 rounded-lg border text-left text-xs transition-all flex items-center justify-between ${
                                selectedKeyMoment === km
                                  ? 'bg-amber-950/40 border-amber-500 text-amber-200 font-bold'
                                  : 'bg-stone-900/60 border-stone-800 text-stone-400 hover:border-stone-700'
                              }`}
                            >
                              <div className="flex items-center gap-2">
                                <span
                                  className={`px-1.5 py-0.5 rounded text-[10px] uppercase font-mono font-bold ${
                                    km.verdict === 'Blunder'
                                      ? 'bg-red-950 text-red-300 border border-red-700'
                                      : 'bg-orange-950 text-orange-300 border border-orange-700'
                                  }`}
                                >
                                  {km.verdict}
                                </span>
                                <span>
                                  Move {km.moveNumber} ({km.color === 'w' ? 'White' : 'Black'}): {km.playedMove.san}
                                </span>
                              </div>
                              {km.solved && <CheckCircle2 className="w-4 h-4 text-emerald-400" />}
                            </button>
                          ))}
                        </div>

                        {/* Interactive Retry Solver */}
                        {selectedKeyMoment && (
                          <div className="p-4 rounded-xl bg-stone-900/80 border border-amber-700/40 space-y-3 text-xs">
                            <div className="font-serif font-bold text-amber-200">
                              Retry Move {selectedKeyMoment.moveNumber}: You played{' '}
                              <span className="text-red-400 line-through">{selectedKeyMoment.playedMove.san}</span>
                            </div>
                            <p className="text-stone-300 text-[11px] font-serif leading-relaxed">
                              {selectedKeyMoment.explanation}
                            </p>

                            <form onSubmit={handleTestRetryMove} className="space-y-2 pt-1">
                              <div className="flex gap-2">
                                <input
                                  type="text"
                                  value={retryInput}
                                  onChange={(e) => setRetryInput(e.target.value)}
                                  placeholder={`What should ${selectedKeyMoment.color === 'w' ? 'White' : 'Black'} play? (e.g. ${selectedKeyMoment.bestMove.san})`}
                                  className="flex-1 bg-stone-950 border border-stone-700 rounded-lg px-2.5 py-1.5 text-xs text-stone-200 font-mono focus:outline-none focus:border-amber-500"
                                />
                                <button
                                  type="submit"
                                  className="px-3 py-1.5 rounded-lg bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs"
                                >
                                  Verify
                                </button>
                              </div>
                              {retryFeedback && (
                                <div
                                  className={`p-2 rounded text-[11px] font-mono ${
                                    retryFeedback.startsWith('Correct')
                                      ? 'bg-emerald-950/60 text-emerald-300 border border-emerald-600/50'
                                      : 'bg-red-950/60 text-red-300 border border-red-600/50'
                                  }`}
                                >
                                  {retryFeedback}
                                </div>
                              )}
                            </form>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                </>
              ) : (
                <div className="text-center py-12 text-stone-500 font-serif">
                  Play moves on the board to generate post-game accuracy curves and key moments review.
                </div>
              )}
            </div>
          )}

          {/* TAB 2: SYZYGY 7-PIECE TABLEBASE */}
          {activeTab === 'tablebase' && (
            <div className="space-y-4">
              <div className="flex flex-wrap items-center justify-between gap-3 p-3.5 rounded-xl bg-stone-900/60 border border-stone-800 text-xs">
                <div>
                  <div className="font-serif font-bold text-stone-200">
                    Current Position: {countPiecesFromFen(currentFen)} Pieces on Board
                  </div>
                  <div className="text-stone-400 text-[11px] font-mono">
                    {countPiecesFromFen(currentFen) <= 7
                      ? 'Within 7-piece theoretical tablebase range'
                      : 'More than 7 pieces (Tablebase activates in endgame)'}
                  </div>
                </div>

                <button
                  type="button"
                  onClick={handleQueryTablebase}
                  disabled={isQueryingTablebase}
                  className="py-1.5 px-3 rounded-lg bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-stone-950 font-serif font-bold flex items-center gap-1.5 transition-all"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${isQueryingTablebase ? 'animate-spin' : ''}`} />
                  Query Tablebase
                </button>
              </div>

              {tablebaseResult && (
                <div className="p-4 rounded-xl bg-amber-950/20 border border-amber-700/40 space-y-4 text-xs">
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-amber-300 uppercase font-bold text-sm">
                      Evaluation: {tablebaseResult.preciseEval}
                    </span>
                    <span
                      className={`px-2 py-0.5 rounded text-[10px] font-mono uppercase font-bold ${
                        tablebaseResult.category === 'win'
                          ? 'bg-emerald-950 text-emerald-300 border border-emerald-600'
                          : tablebaseResult.category === 'loss'
                          ? 'bg-red-950 text-red-300 border border-red-600'
                          : 'bg-stone-800 text-stone-300'
                      }`}
                    >
                      {tablebaseResult.category}
                    </span>
                  </div>

                  <p className="text-stone-300 font-serif leading-relaxed">
                    {tablebaseResult.explanation}
                  </p>

                  {/* Best Theoretical Moves */}
                  {tablebaseResult.bestMoves.length > 0 && (
                    <div>
                      <div className="text-[11px] font-mono uppercase text-amber-400 mb-2 font-bold">
                        Top Mathematical Continuations:
                      </div>
                      <div className="space-y-1.5">
                        {tablebaseResult.bestMoves.map((m, i) => (
                          <div
                            key={i}
                            className="p-2 rounded bg-stone-900 border border-stone-800 flex items-center justify-between text-xs font-mono"
                          >
                            <span className="font-bold text-amber-200">{m.san || m.uci}</span>
                            <span className="text-stone-400 text-[11px]">
                              {m.dtm !== null && m.dtm !== undefined ? `DTM ${m.dtm}` : `DTZ ${m.dtz || 0}`} · {m.category}
                            </span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* TAB 3: OPENING EXPLORER & ECO */}
          {activeTab === 'explorer' && (
            <div className="space-y-4 text-xs">
              <div className="p-3.5 rounded-xl bg-stone-900/60 border border-stone-800 flex items-center justify-between">
                <div>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-amber-950 border border-amber-600/50 text-amber-300 font-bold uppercase">
                    ECO: {openingData.currentEco}
                  </span>
                  <h3 className="text-sm font-serif font-bold text-amber-100 mt-1">
                    {openingData.openingName}
                  </h3>
                </div>
                <div className="text-right text-[11px] text-stone-400 font-mono">
                  {openingData.totalGames.toLocaleString()} Master Games
                </div>
              </div>

              {/* Master Move Frequency Table */}
              <div className="rounded-xl border border-stone-800 overflow-hidden divide-y divide-stone-800">
                <div className="p-2.5 bg-stone-900/80 font-mono text-[10px] uppercase text-stone-400 grid grid-cols-12 gap-2">
                  <span className="col-span-2">Move</span>
                  <span className="col-span-2 text-center">Games</span>
                  <span className="col-span-5 text-center">Master Result (1 - X - 0)</span>
                  <span className="col-span-3 text-right">Your Win Rate</span>
                </div>
                {openingData.moves.map((m, idx) => (
                  <div
                    key={idx}
                    className="p-2.5 bg-stone-900/40 hover:bg-stone-900/70 grid grid-cols-12 gap-2 items-center font-mono text-xs"
                  >
                    <span className="col-span-2 font-bold text-amber-300">{m.san}</span>
                    <span className="col-span-2 text-center text-stone-400 text-[11px]">
                      {m.masterGamesCount.toLocaleString()}
                    </span>
                    {/* Visual Bar: White win / Draw / Black win */}
                    <div className="col-span-5 flex h-2 rounded overflow-hidden">
                      <div className="bg-amber-200" style={{ width: `${m.whiteWinRate}%` }} title={`White: ${m.whiteWinRate}%`} />
                      <div className="bg-stone-600" style={{ width: `${m.drawRate}%` }} title={`Draw: ${m.drawRate}%`} />
                      <div className="bg-stone-900" style={{ width: `${m.blackWinRate}%` }} title={`Black: ${m.blackWinRate}%`} />
                    </div>
                    <span className="col-span-3 text-right font-bold text-emerald-400">
                      {m.userWinRate}% ({m.userGamesCount}g)
                    </span>
                  </div>
                ))}
              </div>

              {openingData.notableGrandmasterGame && (
                <div className="p-3 rounded-lg bg-stone-900/50 border border-stone-800 text-[11px] text-stone-400 font-serif">
                  <span className="text-amber-400 font-bold block mb-0.5">Historical Master Reference:</span>
                  {openingData.notableGrandmasterGame.white} vs. {openingData.notableGrandmasterGame.black} ({openingData.notableGrandmasterGame.year}) · Result: {openingData.notableGrandmasterGame.result}
                </div>
              )}
            </div>
          )}

          {/* TAB 4: RATING PROGRESSION & STAT DASHBOARD */}
          {activeTab === 'stats' && (
            <div className="space-y-5 text-xs">
              {/* Category Ratings Grid */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                {(['bullet', 'blitz', 'rapid', 'daily'] as const).map((cat) => {
                  const cStats = stats[cat];
                  return (
                    <div key={cat} className="p-3.5 rounded-xl bg-stone-900/70 border border-stone-800 text-center">
                      <div className="text-[10px] font-mono uppercase text-stone-400">{cat}</div>
                      <div className="text-xl font-mono font-bold text-amber-200 my-1">
                        {cStats.rating}
                      </div>
                      <div className="text-[10px] text-stone-400 font-mono">
                        Peak: {cStats.peakRating} · {cStats.wins}W / {cStats.losses}L
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Extended Metrics: Tilt, Tactical Accuracy, Favorite Opening */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div className="p-3.5 rounded-xl bg-stone-900/60 border border-stone-800">
                  <div className="text-[10px] font-mono text-stone-400 uppercase">Tactical Accuracy Avg</div>
                  <div className="text-xl font-mono font-bold text-emerald-400 my-0.5">
                    {stats.tacticalAccuracyAvg}%
                  </div>
                  <div className="text-[10px] text-stone-400 font-serif">
                    Centipawn consistency across matches
                  </div>
                </div>

                <div className="p-3.5 rounded-xl bg-stone-900/60 border border-stone-800">
                  <div className="text-[10px] font-mono text-stone-400 uppercase">Mental Tilt Index</div>
                  <div className="text-xl font-mono font-bold text-cyan-400 my-0.5">
                    {stats.tiltFactorScore}%
                  </div>
                  <div className="text-[10px] text-stone-400 font-serif">
                    {stats.tiltFactorScore < 30 ? 'Disciplined & Calm' : 'Fatigued / Elevated Risk'}
                  </div>
                </div>

                <div className="p-3.5 rounded-xl bg-stone-900/60 border border-stone-800">
                  <div className="text-[10px] font-mono text-stone-400 uppercase">Favorite Formation</div>
                  <div className="text-xs font-serif font-bold text-amber-300 my-1 truncate">
                    {stats.favoriteOpening}
                  </div>
                  <div className="text-[10px] text-stone-400 font-mono">
                    Highest win-rate repertoire line
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
