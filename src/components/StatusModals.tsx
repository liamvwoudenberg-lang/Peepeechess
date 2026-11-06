import React from 'react';
import {
  X,
  Play,
  RotateCcw,
  Home,
  Crown,
  Trophy,
  AlertTriangle,
  ShieldAlert,
  Flame,
  CheckCircle,
  HelpCircle,
  Shield,
} from 'lucide-react';
import { Chess, Square } from 'chess.js';
import { EndgameSummary, PieceSymbol, SquareId } from '../game/types';

// -------------------------------------------------------------
// Blunder Guard Confirmation Modal
// -------------------------------------------------------------
interface BlunderGuardModalProps {
  pendingMove: { from: SquareId; to: SquareId; warningText?: string; cpLoss?: number } | null;
  onConfirmPlay: () => void;
  onCancel: () => void;
}

export const BlunderGuardModal: React.FC<BlunderGuardModalProps> = ({
  pendingMove,
  onConfirmPlay,
  onCancel,
}) => {
  if (!pendingMove) return null;

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-stone-950 border-2 border-red-600/70 rounded-2xl p-6 shadow-2xl text-stone-200 space-y-4">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl bg-red-950/80 border border-red-500 flex items-center justify-center text-red-400">
            <ShieldAlert className="w-6 h-6" />
          </div>
          <div>
            <h3 className="text-lg font-serif font-bold text-red-300">
              Blunder Guard Warning!
            </h3>
            <p className="text-xs text-stone-400 font-mono">
              Potential tactical collapse detected
            </p>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-red-950/30 border border-red-800/50 text-xs text-stone-300 space-y-2 leading-relaxed">
          <p className="font-serif text-red-200">
            {pendingMove.warningText ||
              `Moving from ${pendingMove.from} to ${pendingMove.to} results in significant material loss or conceded mate!`}
          </p>
          <p className="text-stone-400 text-[11px]">
            Training Mode is active to prevent unforced blunders. You may reconsider your move or confirm to play it out.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3 pt-2">
          <button
            type="button"
            onClick={onCancel}
            className="py-2.5 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs shadow-md transition-all"
          >
            Choose Another Move
          </button>
          <button
            type="button"
            onClick={onConfirmPlay}
            className="py-2.5 px-4 rounded-xl bg-stone-900 hover:bg-red-950 border border-red-700/60 text-red-300 font-mono text-xs transition-all"
          >
            Play Anyway
          </button>
        </div>
      </div>
    </div>
  );
};

// -------------------------------------------------------------
// Pawn Promotion Modal
// -------------------------------------------------------------
interface PromotionModalProps {
  pendingMove: { from: SquareId; to: SquareId } | null;
  onSelectPromotion: (role: PieceSymbol) => void;
  onCancel: () => void;
}

export const PromotionModal: React.FC<PromotionModalProps> = ({
  pendingMove,
  onSelectPromotion,
  onCancel,
}) => {
  if (!pendingMove) return null;

  const choices: Array<{ symbol: PieceSymbol; label: string; fantasy: string }> = [
    { symbol: 'q', label: 'Queen', fantasy: 'High Sorceress' },
    { symbol: 'r', label: 'Rook', fantasy: 'Bastion Warden' },
    { symbol: 'b', label: 'Bishop', fantasy: 'Runic Cleric' },
    { symbol: 'n', label: 'Knight', fantasy: 'Crested Cavalier' },
  ];

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-sm bg-stone-950 border-2 border-amber-600/70 rounded-2xl p-5 shadow-2xl text-stone-200 space-y-4">
        <div className="text-center">
          <h3 className="text-base font-serif font-bold text-amber-200">
            Promote Vanguard Squire
          </h3>
          <p className="text-xs text-stone-400 font-serif">
            Select a higher rank for your reaching soldier
          </p>
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          {choices.map((c) => (
            <button
              key={c.symbol}
              type="button"
              onClick={() => onSelectPromotion(c.symbol)}
              className="p-3 rounded-xl bg-stone-900/90 hover:bg-amber-950/40 border border-stone-700 hover:border-amber-500 text-center transition-all group"
            >
              <div className="font-serif font-bold text-sm text-stone-200 group-hover:text-amber-300">
                {c.label}
              </div>
              <div className="text-[10px] font-mono text-amber-400/80">{c.fantasy}</div>
            </button>
          ))}
        </div>

        <button
          type="button"
          onClick={onCancel}
          className="w-full py-1.5 rounded-lg text-xs font-mono text-stone-400 hover:text-white"
        >
          Cancel
        </button>
      </div>
    </div>
  );
};

// -------------------------------------------------------------
// Pause Modal
// -------------------------------------------------------------
interface PauseModalProps {
  isOpen: boolean;
  onResume: () => void;
  onRestart: () => void;
  onReturnTitle: () => void;
}

export const PauseModal: React.FC<PauseModalProps> = ({
  isOpen,
  onResume,
  onRestart,
  onReturnTitle,
}) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="w-full max-w-xs bg-stone-950 border-2 border-amber-700/60 rounded-2xl p-6 shadow-2xl text-stone-200 space-y-4 text-center">
        <h3 className="text-lg font-serif font-bold text-amber-200">Citadel Paused</h3>
        <p className="text-xs text-stone-400 font-serif">The battlefield stands still.</p>

        <div className="space-y-2 pt-2">
          <button
            type="button"
            onClick={onResume}
            className="w-full py-2.5 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs flex items-center justify-center gap-2"
          >
            <Play className="w-4 h-4 fill-current" />
            Resume Battle
          </button>
          <button
            type="button"
            onClick={onRestart}
            className="w-full py-2.5 px-4 rounded-xl bg-stone-900 hover:bg-stone-800 border border-stone-700 text-stone-300 font-serif text-xs flex items-center justify-center gap-2"
          >
            <RotateCcw className="w-4 h-4" />
            Restart Match
          </button>
          <button
            type="button"
            onClick={onReturnTitle}
            className="w-full py-2.5 px-4 rounded-xl bg-stone-900 hover:bg-stone-800 border border-stone-700 text-stone-300 font-serif text-xs flex items-center justify-center gap-2"
          >
            <Home className="w-4 h-4" />
            Return to Citadel Gates
          </button>
        </div>
      </div>
    </div>
  );
};

// -------------------------------------------------------------
// Endgame Summary Modal (Post-Match Game Review)
// -------------------------------------------------------------
interface EndgameModalProps {
  summary: EndgameSummary | null;
  onPlayAgain: () => void;
  onReviewWithCoach: () => void;
  onReturnTitle: () => void;
}

export const EndgameModal: React.FC<EndgameModalProps> = ({
  summary,
  onPlayAgain,
  onReviewWithCoach,
  onReturnTitle,
}) => {
  if (!summary) return null;

  const isVictory = summary.outcome === 'victory';

  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur-md flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-stone-950 border-2 border-amber-600/70 rounded-2xl p-6 shadow-2xl text-stone-200 space-y-5 text-center">
        {/* Outcome Banner */}
        <div className="space-y-1">
          <div
            className={`w-14 h-14 mx-auto rounded-2xl border flex items-center justify-center shadow-lg ${
              isVictory
                ? 'bg-amber-950/80 border-amber-500 text-amber-300'
                : 'bg-stone-900 border-stone-700 text-stone-400'
            }`}
          >
            <Crown className="w-8 h-8" />
          </div>
          <h2 className="text-xl font-serif font-bold text-amber-200">{summary.title}</h2>
          <p className="text-xs text-stone-400 font-serif">{summary.subtitle}</p>
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-3 gap-2.5 p-3 rounded-xl bg-stone-900/60 border border-stone-800 text-center">
          <div>
            <div className="text-[10px] font-mono text-stone-400 uppercase">Accuracy</div>
            <div className="text-base font-mono font-bold text-emerald-400">
              {summary.playerAccuracy}%
            </div>
          </div>
          <div>
            <div className="text-[10px] font-mono text-stone-400 uppercase">Optimal</div>
            <div className="text-base font-mono font-bold text-amber-300">
              {summary.optimalMoveCount}
            </div>
          </div>
          <div>
            <div className="text-[10px] font-mono text-stone-400 uppercase">Blunders</div>
            <div className="text-base font-mono font-bold text-red-400">
              {summary.blunderCount}
            </div>
          </div>
        </div>

        {typeof summary.ratingDelta === 'number' && (
          <div className="text-xs font-mono text-amber-300">
            Rating Update: {summary.ratingDelta >= 0 ? `+${summary.ratingDelta}` : summary.ratingDelta} Elo
          </div>
        )}

        {/* Actions */}
        <div className="space-y-2 pt-2">
          <button
            type="button"
            onClick={onReviewWithCoach}
            className="w-full py-2.5 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 text-stone-950 font-serif font-bold text-xs flex items-center justify-center gap-2 shadow-md transition-all"
          >
            <HelpCircle className="w-4 h-4" />
            Review Game with Grandmaster Aldric
          </button>
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={onPlayAgain}
              className="py-2.5 px-4 rounded-xl bg-stone-900 hover:bg-stone-800 border border-stone-700 text-stone-200 font-serif text-xs transition-all"
            >
              Play Again
            </button>
            <button
              type="button"
              onClick={onReturnTitle}
              className="py-2.5 px-4 rounded-xl bg-stone-900 hover:bg-stone-800 border border-stone-700 text-stone-200 font-serif text-xs transition-all"
            >
              Citadel Gates
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

// -------------------------------------------------------------
// 2D Tactical Command Popover Map
// -------------------------------------------------------------
interface TacticalCommandPopoverProps {
  isOpen: boolean;
  onClose: () => void;
  fen: string;
  selectedSquare: SquareId | null;
  onSquareClick: (sq: SquareId) => void;
}

export const TacticalCommandPopover: React.FC<TacticalCommandPopoverProps> = ({
  isOpen,
  onClose,
  fen,
  selectedSquare,
  onSquareClick,
}) => {
  if (!isOpen) return null;

  const chess = new Chess(fen);
  const board = chess.board();
  const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

  const pieceSymbols: Record<string, string> = {
    p: '♟',
    n: '♞',
    b: '♝',
    r: '♜',
    q: '♛',
    k: '♚',
  };

  return (
    <div className="fixed inset-0 z-40 bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-sm bg-stone-950 border-2 border-amber-700/60 rounded-2xl p-4 shadow-2xl text-stone-200 space-y-3">
        <div className="flex items-center justify-between pb-2 border-b border-stone-800">
          <div className="flex items-center gap-2">
            <Shield className="w-4 h-4 text-amber-400" />
            <h3 className="text-sm font-serif font-bold text-amber-200">
              2D Tactical Command Map
            </h3>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded bg-stone-900 hover:bg-stone-800 text-stone-400 hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* 8x8 Vector Grid */}
        <div className="grid grid-cols-8 gap-0.5 border border-stone-700 bg-stone-900 p-1 rounded-lg">
          {board.map((row, rIdx) =>
            row.map((cell, cIdx) => {
              const file = files[cIdx];
              const rank = 8 - rIdx;
              const sq = `${file}${rank}` as SquareId;
              const isDark = (rIdx + cIdx) % 2 === 1;
              const isSelected = selectedSquare === sq;

              return (
                <button
                  key={sq}
                  type="button"
                  onClick={() => onSquareClick(sq)}
                  className={`aspect-square flex items-center justify-center text-xl font-bold transition-all relative ${
                    isSelected
                      ? 'bg-amber-500 text-stone-950'
                      : isDark
                      ? 'bg-stone-800 hover:bg-stone-700'
                      : 'bg-stone-300 hover:bg-stone-200 text-stone-950'
                  }`}
                  title={sq}
                >
                  {cell && (
                    <span
                      className={
                        cell.color === 'w'
                          ? isDark
                            ? 'text-amber-100 drop-shadow'
                            : 'text-amber-800'
                          : isDark
                          ? 'text-stone-950 drop-shadow'
                          : 'text-stone-900'
                      }
                    >
                      {pieceSymbols[cell.type]}
                    </span>
                  )}
                  {/* Subtle rank/file label on borders */}
                  {cIdx === 0 && (
                    <span className="absolute left-0.5 top-0.5 text-[8px] font-mono opacity-50">
                      {rank}
                    </span>
                  )}
                  {rIdx === 7 && (
                    <span className="absolute right-0.5 bottom-0.5 text-[8px] font-mono opacity-50">
                      {file}
                    </span>
                  )}
                </button>
              );
            })
          )}
        </div>

        <p className="text-[11px] text-center text-stone-400 font-serif">
          Click any square to select or order troops. Synchronizes instantly with the 3D Citadel.
        </p>
      </div>
    </div>
  );
};
