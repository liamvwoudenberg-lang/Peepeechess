import React, { useState } from 'react';
import {
  X,
  Castle,
  BookOpen,
  Swords,
  Shield,
  CheckCircle2,
  ChevronRight,
  Flame,
  Award,
} from 'lucide-react';
import { SIEGE_CAMPAIGNS, FORMATION_ACADEMY } from '../game/siegeScenarios';
import { SiegeScenario } from '../game/types';

interface SiegeModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSelectScenario: (scenario: SiegeScenario) => void;
}

export const SiegeModal: React.FC<SiegeModalProps> = ({
  isOpen,
  onClose,
  onSelectScenario,
}) => {
  const [tab, setTab] = useState<'siege' | 'formation'>('siege');

  if (!isOpen) return null;

  const currentList = tab === 'siege' ? SIEGE_CAMPAIGNS : FORMATION_ACADEMY;

  return (
    <div className="fixed inset-0 z-40 bg-black/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="w-full max-w-2xl bg-stone-950 border-2 border-amber-700/60 rounded-2xl shadow-2xl text-stone-200 overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <header className="p-4 sm:p-5 border-b border-stone-800 flex items-center justify-between bg-stone-900/60">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-950/80 border border-amber-600/60 flex items-center justify-center text-amber-400">
              <Castle className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-lg font-serif font-bold text-amber-200">
                Siege Campaigns & Formation Academy
              </h2>
              <p className="text-xs text-stone-400 font-serif">
                Master historical breakthroughs and classical battle formations
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
        <div className="flex border-b border-stone-800 bg-stone-900/30">
          <button
            type="button"
            onClick={() => setTab('siege')}
            className={`flex-1 py-3 px-4 text-xs font-serif font-bold flex items-center justify-center gap-2 border-b-2 transition-all ${
              tab === 'siege'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Flame className="w-4 h-4 text-amber-400" />
            Historical Siege Battles (Tactical Puzzles)
          </button>
          <button
            type="button"
            onClick={() => setTab('formation')}
            className={`flex-1 py-3 px-4 text-xs font-serif font-bold flex items-center justify-center gap-2 border-b-2 transition-all ${
              tab === 'formation'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <BookOpen className="w-4 h-4 text-amber-400" />
            Formation Academy (Opening Drills)
          </button>
        </div>

        {/* Scenarios List */}
        <div className="p-4 sm:p-6 overflow-y-auto space-y-3.5 flex-1">
          {currentList.map((scenario) => (
            <div
              key={scenario.id}
              className="p-4 rounded-xl bg-stone-900/70 hover:bg-stone-900 border border-stone-800 hover:border-amber-600/50 transition-all flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 group"
            >
              <div className="space-y-1.5 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-mono px-2 py-0.5 rounded bg-amber-950/80 border border-amber-600/50 text-amber-300 font-bold">
                    {scenario.difficulty}
                  </span>
                  <h3 className="text-sm font-serif font-bold text-amber-100 group-hover:text-amber-300 transition-colors">
                    {scenario.title}
                  </h3>
                </div>
                <p className="text-xs text-stone-300 leading-relaxed font-serif">
                  {scenario.description}
                </p>
                <div className="text-[11px] font-mono text-amber-400/90 flex items-center gap-1.5 pt-0.5">
                  <Award className="w-3.5 h-3.5" />
                  <span>Objective: {scenario.goalText}</span>
                </div>
              </div>

              <button
                type="button"
                onClick={() => {
                  onSelectScenario(scenario);
                  onClose();
                }}
                className="py-2 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs flex items-center gap-1.5 shrink-0 shadow-md group-hover:shadow-amber-900/40 transition-all"
              >
                <span>Enter Battle</span>
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
