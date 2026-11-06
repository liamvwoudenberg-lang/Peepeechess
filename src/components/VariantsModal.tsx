import React, { useState } from 'react';
import {
  X,
  Shuffle,
  Crown,
  Flame,
  Radio,
  EyeOff,
  Package,
  Swords,
  CheckCircle2,
} from 'lucide-react';
import { generateChess960Fen } from '../variants/chess960';
import { VariantType } from '../types/chess';

interface VariantsModalProps {
  isOpen: boolean;
  onClose: () => void;
  activeVariant: VariantType;
  onSelectVariant: (variant: VariantType, customFen?: string) => void;
}

export const VariantsModal: React.FC<VariantsModalProps> = ({
  isOpen,
  onClose,
  activeVariant,
  onSelectVariant,
}) => {
  const [chess960Seed, setChess960Seed] = useState(518);
  const [chess960Setup, setChess960Setup] = useState(() => generateChess960Fen(518));

  if (!isOpen) return null;

  const handleRandomize960 = () => {
    const randomSeed = Math.floor(Math.random() * 960);
    setChess960Seed(randomSeed);
    setChess960Setup(generateChess960Fen(randomSeed));
  };

  const variantsList = [
    {
      id: 'chess960' as VariantType,
      title: 'Chess960 (Fischer Random)',
      icon: <Shuffle className="w-5 h-5 text-amber-400" />,
      description: 'Procedurally randomized back-rank pieces. Neutralizes memorized opening theory while preserving full castling symmetry.',
    },
    {
      id: 'king_of_the_hill' as VariantType,
      title: 'King of the Hill',
      icon: <Crown className="w-5 h-5 text-amber-400" />,
      description: 'March your Monarch into the central citadel hill (d4, d5, e4, e5) to claim instant theoretical triumph.',
    },
    {
      id: 'three_check' as VariantType,
      title: '3-Check Battle',
      icon: <Flame className="w-5 h-5 text-amber-400" />,
      description: 'Deliver check to the opposing sovereign 3 times to achieve sudden-death victory.',
    },
    {
      id: 'atomic' as VariantType,
      title: 'Atomic Explosions',
      icon: <Flame className="w-5 h-5 text-red-400" />,
      description: 'Every capture triggers a shockwave explosion vaporizing the capturing unit and all adjacent non-pawn pieces.',
    },
    {
      id: 'crazyhouse' as VariantType,
      title: 'Crazyhouse Dropping',
      icon: <Package className="w-5 h-5 text-cyan-400" />,
      description: 'Captured enemy pieces join your reserve pocket and can be dropped onto any vacant citadel tile.',
    },
    {
      id: 'fog_of_war' as VariantType,
      title: 'Fog of War',
      icon: <EyeOff className="w-5 h-5 text-indigo-400" />,
      description: 'Battlefield vision is strictly restricted to squares defended or attacked by your allied units.',
    },
  ];

  return (
    <div className="fixed inset-0 z-40 bg-black/80 backdrop-blur-md flex items-center justify-center p-3 sm:p-5">
      <div className="w-full max-w-2xl bg-stone-950 border-2 border-amber-700/60 rounded-2xl shadow-2xl text-stone-200 overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <header className="p-4 border-b border-stone-800 flex items-center justify-between bg-stone-900/70">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-950/80 border border-amber-600/60 flex items-center justify-center text-amber-400">
              <Swords className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-lg font-serif font-bold text-amber-200">
                Citadel Game Variants & Rulesets
              </h2>
              <p className="text-xs text-stone-400 font-mono">
                Chess960 · King of the Hill · 3-Check · Atomic · Crazyhouse · Fog of War
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

        {/* Variants List */}
        <div className="p-4 sm:p-6 overflow-y-auto space-y-4 flex-1 text-xs">
          {variantsList.map((variant) => (
            <div
              key={variant.id}
              className={`p-4 rounded-xl border transition-all ${
                activeVariant === variant.id
                  ? 'bg-amber-950/30 border-amber-500 shadow-md'
                  : 'bg-stone-900/60 border-stone-800 hover:border-stone-700'
              }`}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-start gap-3">
                  <div className="p-2 rounded-lg bg-stone-950 border border-stone-800">
                    {variant.icon}
                  </div>
                  <div>
                    <h3 className="text-sm font-serif font-bold text-amber-100 flex items-center gap-2">
                      <span>{variant.title}</span>
                      {activeVariant === variant.id && (
                        <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-emerald-950 border border-emerald-600/50 text-emerald-300">
                          Active Ruleset
                        </span>
                      )}
                    </h3>
                    <p className="text-stone-300 text-xs font-serif leading-relaxed mt-1">
                      {variant.description}
                    </p>
                  </div>
                </div>

                <button
                  type="button"
                  onClick={() => {
                    if (variant.id === 'chess960') {
                      onSelectVariant('chess960', chess960Setup.fen);
                    } else {
                      onSelectVariant(variant.id);
                    }
                    onClose();
                  }}
                  className="py-2 px-3 rounded-lg bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs shrink-0 transition-all"
                >
                  Play {variant.title.split(' ')[0]}
                </button>
              </div>

              {/* Special Controls for Chess960 Generator */}
              {variant.id === 'chess960' && (
                <div className="mt-3 pt-3 border-t border-stone-800/80 flex flex-wrap items-center justify-between gap-3 font-mono text-[11px]">
                  <div className="flex items-center gap-2 text-stone-400">
                    <span>Position #{chess960Setup.index}:</span>
                    <span className="font-bold text-amber-300 tracking-wider">
                      {chess960Setup.backRank.join(' ')}
                    </span>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={handleRandomize960}
                      className="py-1 px-2.5 rounded bg-stone-800 hover:bg-stone-700 border border-stone-700 text-stone-200 flex items-center gap-1.5"
                    >
                      <Shuffle className="w-3 h-3 text-amber-400" />
                      Randomize (0–959)
                    </button>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
