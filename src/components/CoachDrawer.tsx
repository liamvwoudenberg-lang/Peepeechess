import React, { useState } from 'react';
import {
  X,
  Sparkles,
  Lightbulb,
  ArrowRight,
  Shield,
  HelpCircle,
  MessageSquare,
  CheckCircle,
  AlertTriangle,
  Send,
  GitBranch,
} from 'lucide-react';
import { MoveAnalysis, SquareId } from '../game/types';

interface CoachDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  analyses: MoveAnalysis[];
  selectedIndex: number;
  onSelectIndex: (idx: number) => void;
  currentFen: string;
  showingOptimalArrow: boolean;
  onToggleOptimalArrow: (from: SquareId | null, to: SquareId | null) => void;
}

export const CoachDrawer: React.FC<CoachDrawerProps> = ({
  isOpen,
  onClose,
  analyses,
  selectedIndex,
  onSelectIndex,
  currentFen,
  showingOptimalArrow,
  onToggleOptimalArrow,
}) => {
  const [askQuestionText, setAskQuestionText] = useState('');
  const [coachAnswer, setCoachAnswer] = useState<string | null>(null);
  const [isAsking, setIsAsking] = useState(false);

  if (!isOpen) return null;

  const currentAnalysis =
    selectedIndex >= 0 && selectedIndex < analyses.length
      ? analyses[selectedIndex]
      : analyses.length > 0
      ? analyses[analyses.length - 1]
      : null;

  const handleAskCoach = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!askQuestionText.trim() || isAsking) return;

    setIsAsking(true);
    setCoachAnswer(null);

    try {
      const res = await fetch('/api/coach/ask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fen: currentFen,
          question: askQuestionText.trim(),
          moveHistory: analyses.map((a) => a.san),
        }),
      });
      const data = await res.json();
      setCoachAnswer(data.answer || 'Grandmaster Aldric nods thoughtfully.');
    } catch {
      setCoachAnswer(
        'Grandmaster Aldric advises: "Maintain tension in the center, fortify your monarch’s fortress, and maneuver your knights toward outposts."'
      );
    } finally {
      setIsAsking(false);
    }
  };

  const getVerdictBadge = (verdict: string) => {
    switch (verdict) {
      case 'Brilliant':
        return 'bg-cyan-500/20 text-cyan-300 border-cyan-400';
      case 'Great':
      case 'Best':
      case 'Optimal':
        return 'bg-emerald-500/20 text-emerald-300 border-emerald-400';
      case 'Book':
        return 'bg-amber-500/20 text-amber-300 border-amber-400';
      case 'Inaccuracy':
        return 'bg-yellow-500/20 text-yellow-300 border-yellow-400';
      case 'Mistake':
        return 'bg-orange-500/20 text-orange-300 border-orange-400';
      case 'Blunder':
        return 'bg-red-500/20 text-red-300 border-red-500';
      default:
        return 'bg-stone-800 text-stone-300 border-stone-600';
    }
  };

  return (
    <aside className="fixed inset-y-0 right-0 z-30 w-full max-w-md bg-stone-950/95 border-l border-amber-700/50 shadow-2xl flex flex-col text-stone-200 backdrop-blur-md">
      {/* Drawer Header with Aldric Portrait */}
      <header className="p-4 border-b border-stone-800 flex items-center justify-between gap-3 bg-stone-900/50">
        <div className="flex items-center gap-3">
          <img
            src="/src/assets/images/archmage_coach_portrait_1793877996612.jpg"
            alt="Grandmaster Magister Aldric"
            className="w-12 h-12 rounded-xl object-cover border-2 border-amber-500/60 shadow-md shadow-black"
          />
          <div>
            <div className="flex items-center gap-1.5">
              <h2 className="text-base font-serif font-bold text-amber-200">Magister Aldric</h2>
              <span className="text-[10px] font-mono uppercase px-1.5 py-0.5 rounded bg-amber-950 border border-amber-600/60 text-amber-300 font-semibold">
                Royal Coach
              </span>
            </div>
            <p className="text-xs text-stone-400 font-serif">Grandmaster of Citadel Tactics</p>
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

      {/* Move Selector Strip */}
      <div className="p-2.5 border-b border-stone-800 bg-stone-950/60 overflow-x-auto flex items-center gap-1.5">
        <span className="text-[10px] font-mono uppercase text-stone-400 px-1 shrink-0">Moves:</span>
        {analyses.length === 0 ? (
          <span className="text-xs text-stone-500 italic px-2">No moves analyzed yet</span>
        ) : (
          analyses.map((m, idx) => (
            <button
              key={`${m.moveNumber}_${m.color}_${idx}`}
              type="button"
              onClick={() => {
                onSelectIndex(idx);
                onToggleOptimalArrow(m.bestMoveFrom, m.bestMoveTo);
              }}
              className={`px-2 py-1 rounded-md text-xs font-mono font-medium shrink-0 border transition-all ${
                idx === selectedIndex || (selectedIndex === -1 && idx === analyses.length - 1)
                  ? 'bg-amber-600/30 text-amber-200 border-amber-500 font-bold shadow-sm'
                  : 'bg-stone-900 text-stone-400 border-stone-800 hover:border-stone-700'
              }`}
            >
              <span>{m.color === 'w' ? `${m.moveNumber}.` : '..'}</span> {m.san}
            </button>
          ))
        )}
      </div>

      {/* Main Analysis Body */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {currentAnalysis ? (
          <>
            {/* Move Headline Card */}
            <div className="p-3.5 rounded-xl bg-stone-900/80 border border-stone-800 space-y-2">
              <div className="flex items-center justify-between gap-2">
                <span
                  className={`text-xs px-2.5 py-0.5 rounded-full border font-mono font-bold uppercase ${getVerdictBadge(
                    currentAnalysis.verdict
                  )}`}
                >
                  {currentAnalysis.verdict}
                </span>
                <span className="text-xs font-mono text-stone-400">
                  {currentAnalysis.color === 'w' ? 'White' : 'Black'} · Move {currentAnalysis.moveNumber}
                </span>
              </div>

              <h3 className="text-sm font-serif font-semibold text-amber-100">
                {currentAnalysis.headline}
              </h3>

              {currentAnalysis.openingName && (
                <div className="text-xs font-serif text-amber-400 flex items-center gap-1">
                  <Shield className="w-3.5 h-3.5" />
                  <span>Opening: {currentAnalysis.openingName}</span>
                </div>
              )}
            </div>

            {/* Why was / wasn't it optimal? (Causal Reasons) */}
            <div className="p-3.5 rounded-xl bg-stone-900/60 border border-stone-800 space-y-2">
              <h4 className="text-xs font-mono uppercase text-amber-300 font-bold flex items-center gap-1.5">
                <Lightbulb className="w-3.5 h-3.5 text-amber-400" />
                Strategic Explanation (Why this happened)
              </h4>
              <ul className="space-y-1.5 text-xs text-stone-300">
                {currentAnalysis.whyReasons.map((reason, i) => (
                  <li key={i} className="flex items-start gap-2 leading-relaxed">
                    <span className="text-amber-400 mt-0.5">•</span>
                    <span>{reason}</span>
                  </li>
                ))}
              </ul>
            </div>

            {/* Optimal Comparison */}
            <div className="p-3 rounded-xl bg-amber-950/20 border border-amber-700/40 text-xs space-y-1.5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-amber-300 font-bold flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5 text-amber-400" />
                  Grandmaster Recommendation
                </span>
                <button
                  type="button"
                  onClick={() =>
                    onToggleOptimalArrow(
                      showingOptimalArrow ? null : currentAnalysis.bestMoveFrom,
                      showingOptimalArrow ? null : currentAnalysis.bestMoveTo
                    )
                  }
                  className="px-2 py-0.5 rounded bg-amber-900/50 hover:bg-amber-800/60 border border-amber-600/50 text-[10px] text-amber-200 transition-all font-mono"
                >
                  {showingOptimalArrow ? 'Hide 3D Arrow' : 'Show 3D Arrow'}
                </button>
              </div>
              <p className="text-stone-300 font-serif leading-relaxed">
                {currentAnalysis.optimalComparison}
              </p>
            </div>

            {/* Deep Coach Note from Server */}
            {currentAnalysis.deepCoachNote && (
              <div className="p-3 rounded-xl bg-stone-900/90 border border-amber-600/30 text-xs italic text-amber-200/90">
                <span className="font-serif font-bold text-amber-300 not-italic block mb-1">
                  Magister Aldric's Council:
                </span>
                "{currentAnalysis.deepCoachNote}"
              </div>
            )}

            {/* Tactical Themes */}
            {currentAnalysis.tacticalThemes.length > 0 && (
              <div className="flex flex-wrap gap-1.5 pt-1">
                {currentAnalysis.tacticalThemes.map((theme, i) => (
                  <span
                    key={i}
                    className="text-[10px] font-mono px-2 py-0.5 rounded-md bg-stone-900 border border-stone-700 text-stone-300"
                  >
                    #{theme}
                  </span>
                ))}
              </div>
            )}
          </>
        ) : (
          <div className="text-center py-12 text-stone-400 space-y-3">
            <HelpCircle className="w-8 h-8 mx-auto text-amber-500/60" />
            <p className="text-sm font-serif">Make your opening move on the board.</p>
            <p className="text-xs text-stone-500">
              Grandmaster Aldric will provide tactical breakdown, square control analysis, and optimal lines.
            </p>
          </div>
        )}

        {/* Ask Aldric Custom Question */}
        <div className="pt-4 border-t border-stone-800 space-y-2.5">
          <h4 className="text-xs font-mono uppercase text-amber-300 font-bold flex items-center gap-1.5">
            <MessageSquare className="w-3.5 h-3.5 text-amber-400" />
            Ask the Grandmaster
          </h4>
          <form onSubmit={handleAskCoach} className="space-y-2">
            <div className="flex gap-2">
              <input
                type="text"
                value={askQuestionText}
                onChange={(e) => setAskQuestionText(e.target.value)}
                placeholder="e.g. Should I castle or push d4?"
                className="flex-1 bg-stone-900 border border-stone-700 rounded-lg px-3 py-1.5 text-xs text-stone-200 placeholder:text-stone-500 focus:outline-none focus:border-amber-500"
              />
              <button
                type="submit"
                disabled={isAsking || !askQuestionText.trim()}
                className="px-3 py-1.5 rounded-lg bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-stone-950 font-bold text-xs flex items-center gap-1 transition-all"
              >
                <Send className="w-3 h-3" />
                <span>Ask</span>
              </button>
            </div>
          </form>

          {coachAnswer && (
            <div className="p-3 rounded-lg bg-stone-900 border border-amber-600/40 text-xs text-amber-200 font-serif leading-relaxed animate-fadeIn">
              <span className="font-bold text-amber-300 block mb-0.5">Aldric Answers:</span>
              {coachAnswer}
            </div>
          )}
        </div>
      </div>
    </aside>
  );
};
