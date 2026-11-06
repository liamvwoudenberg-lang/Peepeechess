import React, { useState } from 'react';
import {
  Volume2,
  VolumeX,
  RotateCcw,
  Flag,
  HelpCircle,
  Lightbulb,
  Camera,
  Layers,
  MapPin,
  Eye,
  ShieldAlert,
  Flame,
  ChevronDown,
  ChevronUp,
  Sliders,
  Settings,
  Trophy,
  Compass,
  Zap,
  Swords,
  Users,
  Smile,
  Pause,
  Play,
  Check,
  CheckCircle2,
} from 'lucide-react';
import {
  CameraPreset,
  GameMode,
  MoveAnalysis,
  OnlineMatchState,
  PieceColor,
} from '../game/types';
import { formatEvalScore } from '../game/chessCoachEngine';
import { MatchEmote, VariantType } from '../types/chess';
import { MEDIEVAL_MATCH_EMOTES } from '../multiplayer/socialHub';

interface GameHudProps {
  mode: GameMode;
  turn: PieceColor;
  inCheck: boolean;
  evalCp: number;
  whiteClockMs: number;
  blackClockMs: number;
  onlineMatch: OnlineMatchState | null;
  latestAnalysis: MoveAnalysis | null;
  cameraPreset: CameraPreset;
  hudCollapsed: boolean;
  coachOpen: boolean;
  commandMapOpen: boolean;
  muted: boolean;
  blunderGuardEnabled?: boolean;
  showHeatmap?: boolean;
  showThreatLines?: boolean;
  showDangerAuras?: boolean;
  isFirstPersonActive?: boolean;
  selectedSquare?: string | null;
  activeVariant?: VariantType;
  threeCheckCount?: { white: number; black: number };
  activeEmote?: { senderName: string; icon: string; soundLabel: string } | null;
  onToggleHudCollapsed: () => void;
  onSelectCameraPreset: (preset: CameraPreset) => void;
  onToggleCoach: () => void;
  onOpenRanked: () => void;
  onToggleCommandMap: () => void;
  onToggleMute: () => void;
  onPause: () => void;
  onRestartOrResign: () => void;
  onRequestHint: () => void;
  onToggleBlunderGuard?: () => void;
  onToggleHeatmap?: () => void;
  onToggleThreatLines?: () => void;
  onToggleDangerAuras?: () => void;
  onToggleFirstPerson?: () => void;
  onToggle2D3D?: () => void;
  onOpenAnalytics?: () => void;
  onOpenPuzzles?: () => void;
  onOpenVariants?: () => void;
  onOpenTournamentSocial?: () => void;
  onSendEmote?: (emote: MatchEmote) => void;
}

export const GameHud: React.FC<GameHudProps> = ({
  mode,
  turn,
  inCheck,
  evalCp,
  whiteClockMs,
  blackClockMs,
  onlineMatch,
  latestAnalysis,
  cameraPreset,
  hudCollapsed,
  coachOpen,
  commandMapOpen,
  muted,
  blunderGuardEnabled = true,
  showHeatmap = false,
  showThreatLines = false,
  showDangerAuras = false,
  isFirstPersonActive = false,
  selectedSquare = null,
  activeVariant = 'standard',
  threeCheckCount,
  activeEmote = null,
  onToggleHudCollapsed,
  onSelectCameraPreset,
  onToggleCoach,
  onOpenRanked,
  onToggleCommandMap,
  onToggleMute,
  onPause,
  onRestartOrResign,
  onRequestHint,
  onToggleBlunderGuard,
  onToggleHeatmap,
  onToggleThreatLines,
  onToggleDangerAuras,
  onToggleFirstPerson,
  onToggle2D3D,
  onOpenAnalytics,
  onOpenPuzzles,
  onOpenVariants,
  onOpenTournamentSocial,
  onSendEmote,
}) => {
  const [tacticalVisionOpen, setTacticalVisionOpen] = useState<boolean>(false);
  const [settingsMenuOpen, setSettingsMenuOpen] = useState<boolean>(false);
  const [emoteMenuOpen, setEmoteMenuOpen] = useState<boolean>(false);

  const formatTime = (ms: number) => {
    const totalSec = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  };

  const clampedCp = Math.max(-1000, Math.min(1000, evalCp));
  const whitePercent = 50 + (clampedCp / 1000) * 45;

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
        return 'bg-red-500/20 text-red-300 border-red-500 animate-pulse';
      default:
        return 'bg-stone-800 text-stone-300 border-stone-600';
    }
  };

  // Count active tactical layers
  const activeVisionCount = [
    showHeatmap,
    showThreatLines,
    showDangerAuras,
    blunderGuardEnabled,
  ].filter(Boolean).length;

  return (
    <div className="absolute inset-0 z-10 pointer-events-none flex flex-col justify-between p-3 sm:p-5 select-none font-sans">
      {/* =========================================================================
          TOP HEADER: PLAYERS/CLOCKS, BALANCE OF POWER, AND 3 LOGICAL BUTTON GROUPS
      ========================================================================= */}
      <header className="flex flex-col sm:flex-row items-center justify-between gap-2 sm:gap-3 pointer-events-auto">
        <div className="w-full sm:w-auto flex items-center justify-between gap-2">
          {/* Left: Players & Digital Clocks */}
          <div className="flex items-center gap-1.5 sm:gap-3 bg-stone-950/85 border border-stone-800 rounded-xl p-1.5 sm:p-2.5 shadow-xl shadow-black/60 backdrop-blur-md">
            {/* Black Clock & Player */}
            <div
              className={`flex items-center gap-1.5 px-2 sm:px-3 py-1 sm:py-1.5 rounded-lg border transition-all duration-150 ${
                turn === 'b'
                  ? 'bg-stone-800 text-amber-200 border-amber-500/70 shadow-sm'
                  : 'bg-stone-900/60 text-stone-400 border-stone-800'
              }`}
            >
              <div className="w-2 h-2 sm:w-2.5 sm:h-2.5 rounded-full bg-stone-500 border border-stone-300" />
              <div className="text-left">
                <div className="text-[9px] sm:text-[10px] font-mono leading-none uppercase text-stone-400">
                  {onlineMatch ? onlineMatch.black.name : 'Black'}
                </div>
                <div className="text-xs sm:text-sm font-mono font-bold leading-tight">{formatTime(blackClockMs)}</div>
              </div>
            </div>

            <span className="text-[10px] sm:text-xs font-serif text-amber-500/80 font-bold">VS</span>

            {/* White Clock & Player */}
            <div
              className={`flex items-center gap-1.5 px-2 sm:px-3 py-1 sm:py-1.5 rounded-lg border transition-all duration-150 ${
                turn === 'w'
                  ? 'bg-amber-950/50 text-amber-200 border-amber-500/70 shadow-sm'
                  : 'bg-stone-900/60 text-stone-400 border-stone-800'
              }`}
            >
              <div className="w-2 h-2 sm:w-2.5 sm:h-2.5 rounded-full bg-amber-100 border border-amber-400" />
              <div className="text-left">
                <div className="text-[9px] sm:text-[10px] font-mono leading-none uppercase text-stone-400">
                  {onlineMatch ? onlineMatch.white.name : 'White'}
                </div>
                <div className="text-xs sm:text-sm font-mono font-bold leading-tight">{formatTime(whiteClockMs)}</div>
              </div>
            </div>
          </div>

          {/* Center on mobile: Medieval Balance-of-Power Scale */}
          <div className="flex flex-col items-center sm:hidden">
            <div className="relative w-28 h-2.5 bg-stone-950 border border-amber-700/60 rounded-full overflow-hidden shadow-inner flex items-center">
              <div
                className="h-full bg-gradient-to-r from-amber-200 to-amber-100 transition-all duration-300"
                style={{ width: `${whitePercent}%` }}
              />
              <div
                className="h-full bg-gradient-to-r from-stone-900 to-stone-950 transition-all duration-300"
                style={{ width: `${100 - whitePercent}%` }}
              />
            </div>
            <span className="text-[8px] font-mono font-bold text-amber-300/90 mt-0.5">{formatEvalScore(evalCp)}</span>
          </div>
        </div>

        {/* Center on desktop: Medieval Balance-of-Power Scale & Check Alert */}
        <div className="hidden sm:flex flex-col items-center">
          {inCheck && (
            <div className="mb-1.5 px-3 py-0.5 rounded-full bg-red-950/90 border border-red-500/80 text-red-200 text-xs font-serif font-bold tracking-widest uppercase animate-pulse flex items-center gap-1.5 shadow-lg shadow-red-900/40">
              <Flame className="w-3.5 h-3.5 text-red-400" />
              Check! Sovereign in Danger
            </div>
          )}

          {/* Active Variant Pill */}
          {activeVariant !== 'standard' && (
            <div className="mb-1 px-2.5 py-0.5 rounded-full bg-amber-950/80 border border-amber-600/60 text-amber-300 text-[11px] font-mono font-bold flex items-center gap-1.5 shadow-md">
              {activeVariant === 'king_of_the_hill' && '🏰 King of the Hill: Seize d4, d5, e4, e5'}
              {activeVariant === 'three_check' && (
                <span>
                  ⚔️ 3-Check: White ({threeCheckCount?.white || 0}/3) • Black ({threeCheckCount?.black || 0}/3)
                </span>
              )}
              {activeVariant === 'atomic' && '💥 Atomic: Captures trigger blast'}
              {activeVariant === 'crazyhouse' && '📦 Crazyhouse: Reserve drops'}
              {activeVariant === 'chess960' && '🎲 Chess960 Fischer Random'}
              {activeVariant === 'fog_of_war' && '🌫️ Fog of War Active'}
            </div>
          )}

          {/* Balance of Power Sword Scale */}
          <div className="relative w-44 sm:w-60 h-3 bg-stone-950 border border-amber-700/60 rounded-full overflow-hidden shadow-inner flex items-center">
            <div
              className="h-full bg-gradient-to-r from-amber-200 to-amber-100 transition-all duration-300"
              style={{ width: `${whitePercent}%` }}
            />
            <div
              className="h-full bg-gradient-to-r from-stone-900 to-stone-950 transition-all duration-300"
              style={{ width: `${100 - whitePercent}%` }}
            />
            <div className="absolute inset-0 flex items-center justify-between px-2 text-[9px] font-mono font-bold pointer-events-none">
              <span className="text-stone-900 drop-shadow-sm">{formatEvalScore(evalCp)}</span>
              <span className="text-stone-400 text-[8px] uppercase tracking-wider">Balance</span>
            </div>
          </div>
        </div>

        {/* Right: 3 Logical Button Groups */}
        <div className="w-full sm:w-auto flex items-center justify-end gap-1.5 sm:gap-2">
          {/* GROUP 1: ANALYSIS & COACH DRAWER ([C]) */}
          <div className="flex items-center gap-1 p-1 rounded-xl bg-stone-950/85 border border-stone-800 shadow-xl backdrop-blur-md">
            {latestAnalysis && (
              <button
                type="button"
                onClick={onToggleCoach}
                className={`px-2 py-1 rounded-lg border text-xs font-mono font-bold flex items-center gap-1.5 transition-all duration-150 cursor-pointer ${getVerdictBadge(
                  latestAnalysis.verdict
                )}`}
                title="Open Grandmaster Move Analysis"
              >
                <span>{latestAnalysis.san}</span>
                <span className="text-[10px] uppercase font-bold">{latestAnalysis.verdict}</span>
              </button>
            )}

            <button
              type="button"
              onClick={onToggleCoach}
              className={`p-1.5 sm:p-2 rounded-lg border text-xs transition-all duration-150 cursor-pointer ${
                coachOpen
                  ? 'bg-amber-600/30 text-amber-200 border-amber-500 shadow-sm'
                  : 'bg-stone-900 text-stone-300 border-stone-800 hover:text-white hover:border-stone-700'
              }`}
              title="Toggle Coach Drawer (C)"
            >
              <HelpCircle className="w-4 h-4 text-amber-400" />
            </button>

            <button
              type="button"
              onClick={onRequestHint}
              className="p-1.5 sm:p-2 rounded-lg bg-stone-900 hover:bg-stone-800 border border-stone-800 text-stone-300 hover:text-amber-300 transition-all duration-150 cursor-pointer"
              title="Ask Aldric for Recommended Move"
            >
              <Lightbulb className="w-4 h-4" />
            </button>
          </div>

          {/* GROUP 2: SOUND & SETTINGS MENU ([⚙]) */}
          <div className="relative flex items-center gap-1 p-1 rounded-xl bg-stone-950/85 border border-stone-800 shadow-xl backdrop-blur-md">
            <button
              type="button"
              onClick={onToggleMute}
              className="p-1.5 sm:p-2 rounded-lg bg-stone-900 hover:bg-stone-800 border border-stone-800 text-stone-300 transition-all duration-150 cursor-pointer"
              title={muted ? 'Unmute Sound' : 'Mute Sound'}
            >
              {muted ? <VolumeX className="w-4 h-4 text-red-400" /> : <Volume2 className="w-4 h-4" />}
            </button>

            <button
              type="button"
              onClick={() => setSettingsMenuOpen((v) => !v)}
              className={`p-1.5 sm:p-2 rounded-lg border text-xs transition-all duration-150 cursor-pointer ${
                settingsMenuOpen
                  ? 'bg-amber-600/30 text-amber-200 border-amber-500 shadow-sm'
                  : 'bg-stone-900 text-stone-300 border-stone-800 hover:text-white hover:border-stone-700'
              }`}
              title="Settings & Citadel Features"
            >
              <Settings className="w-4 h-4 text-amber-400" />
            </button>

            {/* Settings & Suites Popover Menu */}
            {settingsMenuOpen && (
              <div className="absolute right-0 top-full mt-2 w-56 bg-stone-950/95 border border-stone-800 rounded-xl p-2 shadow-2xl backdrop-blur-xl z-30 space-y-1">
                <div className="text-[10px] font-mono uppercase text-amber-400/90 px-2 py-1 border-b border-stone-800/80">
                  Citadel Suites & Hubs:
                </div>

                {onOpenAnalytics && (
                  <button
                    type="button"
                    onClick={() => {
                      onOpenAnalytics();
                      setSettingsMenuOpen(false);
                    }}
                    className="w-full px-2.5 py-1.5 rounded-lg hover:bg-stone-900 text-left text-xs font-serif flex items-center gap-2 text-stone-200 cursor-pointer"
                  >
                    <Compass className="w-3.5 h-3.5 text-amber-400" />
                    <span>Analytics & Tablebase</span>
                  </button>
                )}

                {onOpenPuzzles && (
                  <button
                    type="button"
                    onClick={() => {
                      onOpenPuzzles();
                      setSettingsMenuOpen(false);
                    }}
                    className="w-full px-2.5 py-1.5 rounded-lg hover:bg-stone-900 text-left text-xs font-serif flex items-center gap-2 text-stone-200 cursor-pointer"
                  >
                    <Zap className="w-3.5 h-3.5 text-amber-400" />
                    <span>Rated Puzzles & Rush</span>
                  </button>
                )}

                {onOpenVariants && (
                  <button
                    type="button"
                    onClick={() => {
                      onOpenVariants();
                      setSettingsMenuOpen(false);
                    }}
                    className="w-full px-2.5 py-1.5 rounded-lg hover:bg-stone-900 text-left text-xs font-serif flex items-center gap-2 text-stone-200 cursor-pointer"
                  >
                    <Swords className="w-3.5 h-3.5 text-amber-400" />
                    <span>Game Variants (960)</span>
                  </button>
                )}

                {onOpenTournamentSocial && (
                  <button
                    type="button"
                    onClick={() => {
                      onOpenTournamentSocial();
                      setSettingsMenuOpen(false);
                    }}
                    className="w-full px-2.5 py-1.5 rounded-lg hover:bg-stone-900 text-left text-xs font-serif flex items-center gap-2 text-stone-200 cursor-pointer"
                  >
                    <Users className="w-3.5 h-3.5 text-amber-400" />
                    <span>Tournaments & Clans</span>
                  </button>
                )}

                <button
                  type="button"
                  onClick={() => {
                    setEmoteMenuOpen((v) => !v);
                    setSettingsMenuOpen(false);
                  }}
                  className="w-full px-2.5 py-1.5 rounded-lg hover:bg-stone-900 text-left text-xs font-serif flex items-center gap-2 text-stone-200 cursor-pointer"
                >
                  <Smile className="w-3.5 h-3.5 text-amber-400" />
                  <span>Send Match Emote</span>
                </button>
              </div>
            )}

            {/* Emote Picker Drawer */}
            {emoteMenuOpen && (
              <div className="absolute right-0 top-full mt-2 w-48 bg-stone-950 border border-stone-800 rounded-xl p-2 shadow-2xl z-30 space-y-1">
                <div className="text-[10px] font-mono uppercase text-amber-400 px-2 py-0.5">
                  Broadcast Emote:
                </div>
                {MEDIEVAL_MATCH_EMOTES.map((em) => (
                  <button
                    key={em.id}
                    type="button"
                    onClick={() => {
                      onSendEmote?.(em);
                      setEmoteMenuOpen(false);
                    }}
                    className="w-full px-2 py-1.5 rounded-lg hover:bg-stone-900 text-left text-xs font-serif flex items-center gap-2 text-stone-200 cursor-pointer"
                  >
                    <span>{em.icon}</span>
                    <span>{em.name}</span>
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* GROUP 3: RESIGN / RESTART / PAUSE ([🏳]) */}
          <div className="flex items-center gap-1 p-1 rounded-xl bg-stone-950/85 border border-stone-800 shadow-xl backdrop-blur-md">
            <button
              type="button"
              onClick={onPause}
              className="p-1.5 sm:p-2 rounded-lg bg-stone-900 hover:bg-stone-800 border border-stone-800 text-stone-300 hover:text-white transition-all duration-150 cursor-pointer"
              title="Pause Match"
            >
              <Pause className="w-4 h-4" />
            </button>

            <button
              type="button"
              onClick={onRestartOrResign}
              className="p-1.5 sm:p-2 rounded-lg bg-stone-900 hover:bg-red-950/60 border border-stone-800 text-stone-300 hover:text-red-300 transition-all duration-150 cursor-pointer"
              title={mode === 'online_ranked' ? 'Resign Citadel' : 'Restart Match'}
            >
              {mode === 'online_ranked' ? <Flag className="w-4 h-4" /> : <RotateCcw className="w-4 h-4" />}
            </button>
          </div>
        </div>
      </header>

      {/* Floating Animated Emote Toast */}
      {activeEmote && (
        <div className="self-center my-auto z-20 pointer-events-none animate-bounce">
          <div className="bg-stone-950/90 border border-amber-500 rounded-2xl px-5 py-3 shadow-2xl flex items-center gap-3 backdrop-blur-md">
            <span className="text-4xl">{activeEmote.icon}</span>
            <div>
              <div className="text-xs font-mono uppercase text-amber-400 font-bold">
                {activeEmote.senderName}
              </div>
              <div className="text-sm font-serif font-bold text-amber-100">
                "{activeEmote.soundLabel}"
              </div>
            </div>
          </div>
        </div>
      )}

      {/* =========================================================================
          BOTTOM CONTROL BAR: SINGLE FLOATING PILL BAR (STREAMLINED & CENTERED)
      ========================================================================= */}
      <footer className="self-center pointer-events-auto relative safe-area-bottom max-w-[calc(100vw-1rem)]">
        {/* Tactical Vision Drop-Up Popover */}
        {tacticalVisionOpen && (
          <div className="absolute bottom-full mb-3 left-1/2 -translate-x-1/2 w-64 max-w-[calc(100vw-2rem)] bg-[#0b0f17]/95 backdrop-blur-xl border border-stone-800 rounded-2xl p-3 shadow-2xl shadow-black z-30 space-y-2">
            <div className="flex items-center justify-between pb-1.5 border-b border-stone-800/80">
              <span className="text-xs font-mono font-bold uppercase tracking-wider text-amber-400">
                Tactical Vision Layers
              </span>
              <span className="text-[10px] font-mono text-stone-400">
                {activeVisionCount} Active
              </span>
            </div>

            <div className="space-y-1.5 text-xs font-mono">
              {/* Heatmap Toggle */}
              {onToggleHeatmap && (
                <button
                  type="button"
                  onClick={onToggleHeatmap}
                  className={`w-full p-2 rounded-lg border text-left flex items-center justify-between transition-all duration-150 cursor-pointer ${
                    showHeatmap
                      ? 'bg-indigo-950/60 border-indigo-500/70 text-indigo-200'
                      : 'bg-stone-900/60 border-stone-800/80 text-stone-400 hover:text-stone-200'
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <Layers className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Square Control Heatmap</span>
                  </div>
                  {showHeatmap && <Check className="w-3.5 h-3.5 text-indigo-400" />}
                </button>
              )}

              {/* Threat Lines Toggle */}
              {onToggleThreatLines && (
                <button
                  type="button"
                  onClick={onToggleThreatLines}
                  className={`w-full p-2 rounded-lg border text-left flex items-center justify-between transition-all duration-150 cursor-pointer ${
                    showThreatLines
                      ? 'bg-red-950/60 border-red-500/70 text-red-200'
                      : 'bg-stone-900/60 border-stone-800/80 text-stone-400 hover:text-stone-200'
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <MapPin className="w-3.5 h-3.5 text-red-400" />
                    <span>Threat & Attack Rays</span>
                  </div>
                  {showThreatLines && <Check className="w-3.5 h-3.5 text-red-400" />}
                </button>
              )}

              {/* Danger Auras Toggle */}
              {onToggleDangerAuras && (
                <button
                  type="button"
                  onClick={onToggleDangerAuras}
                  className={`w-full p-2 rounded-lg border text-left flex items-center justify-between transition-all duration-150 cursor-pointer ${
                    showDangerAuras
                      ? 'bg-amber-950/60 border-amber-500/70 text-amber-200'
                      : 'bg-stone-900/60 border-stone-800/80 text-stone-400 hover:text-stone-200'
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <ShieldAlert className="w-3.5 h-3.5 text-amber-400" />
                    <span>Danger Alerts (Undefended)</span>
                  </div>
                  {showDangerAuras && <Check className="w-3.5 h-3.5 text-amber-400" />}
                </button>
              )}

              {/* Blunder Guard Toggle */}
              {onToggleBlunderGuard && (
                <button
                  type="button"
                  onClick={onToggleBlunderGuard}
                  className={`w-full p-2 rounded-lg border text-left flex items-center justify-between transition-all duration-150 cursor-pointer ${
                    blunderGuardEnabled
                      ? 'bg-emerald-950/60 border-emerald-500/70 text-emerald-200'
                      : 'bg-stone-900/60 border-stone-800/80 text-stone-500'
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                    <span>Blunder Interceptor</span>
                  </div>
                  <span className="text-[10px] font-bold">
                    {blunderGuardEnabled ? 'ON' : 'OFF'}
                  </span>
                </button>
              )}

              {/* 2D Command Map Overlay */}
              <button
                type="button"
                onClick={() => {
                  onToggleCommandMap();
                  setTacticalVisionOpen(false);
                }}
                className={`w-full p-2 rounded-lg border text-left flex items-center justify-between transition-all duration-150 cursor-pointer ${
                  commandMapOpen
                    ? 'bg-amber-950/60 border-amber-500/70 text-amber-200'
                    : 'bg-stone-900/60 border-stone-800/80 text-stone-400 hover:text-stone-200'
                }`}
              >
                <div className="flex items-center gap-2">
                  <Camera className="w-3.5 h-3.5 text-amber-400" />
                  <span>2D Tactical Command Map</span>
                </div>
                <span className="text-[10px] font-mono">[B]</span>
              </button>
            </div>
          </div>
        )}

        {/* Central Floating Pill Bar */}
        <div className="flex items-center gap-2 sm:gap-3 px-3 py-1.5 sm:px-4 sm:py-2 rounded-full bg-[#0b0f17]/85 backdrop-blur-xl border border-stone-800/80 shadow-2xl shadow-black/80 text-xs text-stone-300">
          {/* Segmented View Toggle: [ 3D Orbit | 2D Top | POV ] */}
          <div className="flex items-center p-0.5 rounded-full bg-stone-900/90 border border-stone-800 text-[11px] font-mono">
            <button
              type="button"
              onClick={() => {
                if (isFirstPersonActive && onToggleFirstPerson) {
                  onToggleFirstPerson();
                }
                onSelectCameraPreset('white');
              }}
              className={`px-3 py-1 rounded-full transition-all duration-150 cursor-pointer ${
                cameraPreset !== 'overhead' && !isFirstPersonActive
                  ? 'bg-amber-600/40 text-amber-200 border border-amber-500/60 font-bold shadow-sm'
                  : 'text-stone-400 hover:text-stone-200'
              }`}
            >
              3D Orbit
            </button>

            <button
              type="button"
              onClick={() => {
                if (isFirstPersonActive && onToggleFirstPerson) {
                  onToggleFirstPerson();
                }
                onSelectCameraPreset('overhead');
              }}
              className={`px-3 py-1 rounded-full transition-all duration-150 cursor-pointer ${
                cameraPreset === 'overhead'
                  ? 'bg-amber-600/40 text-amber-200 border border-amber-500/60 font-bold shadow-sm'
                  : 'text-stone-400 hover:text-stone-200'
              }`}
            >
              2D Top
            </button>

            <button
              type="button"
              onClick={() => onToggleFirstPerson?.()}
              className={`px-3 py-1 rounded-full transition-all duration-150 cursor-pointer ${
                isFirstPersonActive
                  ? 'bg-amber-600 text-stone-950 font-bold shadow-md shadow-amber-500/30'
                  : 'text-stone-400 hover:text-stone-200'
              }`}
              title={
                selectedSquare
                  ? `Shoulder POV on square ${selectedSquare}`
                  : 'Select a unit to view shoulder POV'
              }
            >
              POV {selectedSquare ? `(${selectedSquare})` : ''}
            </button>
          </div>

          {/* Divider */}
          <div className="w-px h-4 bg-stone-800" />

          {/* Expandable Tactical Vision Button */}
          <button
            type="button"
            onClick={() => setTacticalVisionOpen((v) => !v)}
            className={`flex items-center gap-1.5 px-3 py-1 rounded-full border text-[11px] font-mono transition-all duration-150 cursor-pointer ${
              tacticalVisionOpen || activeVisionCount > 0
                ? 'bg-amber-950/60 border-amber-500/60 text-amber-200'
                : 'bg-stone-900/80 border-stone-800 text-stone-400 hover:text-stone-200 hover:border-stone-700'
            }`}
          >
            <Layers className="w-3.5 h-3.5 text-amber-400" />
            <span>Tactical Vision</span>
            {activeVisionCount > 0 && (
              <span className="w-4 h-4 rounded-full bg-amber-600 text-stone-950 text-[10px] font-bold flex items-center justify-center">
                {activeVisionCount}
              </span>
            )}
            {tacticalVisionOpen ? (
              <ChevronDown className="w-3 h-3 text-stone-400" />
            ) : (
              <ChevronUp className="w-3 h-3 text-stone-400" />
            )}
          </button>
        </div>
      </footer>
    </div>
  );
};
