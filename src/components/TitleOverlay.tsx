import React, { useCallback, useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Castle,
  Swords,
  Shield,
  Crown,
  Sparkles,
  Trophy,
  Flame,
  CloudRain,
  Snowflake,
  Sun,
  Layers,
  Compass,
  Zap,
  Sliders,
  Volume2,
  VolumeX,
  Eye,
  EyeOff,
  Check,
  BookOpen,
  Clock,
  Activity,
  HelpCircle,
  Award,
} from 'lucide-react';
import {
  ArenaTheme,
  BotDifficulty,
  FactionSkin,
  PieceColor,
  SiegeScenario,
  WeatherEffect,
} from '../game/types';
import { VariantType } from '../types/chess';
import { SIEGE_CAMPAIGNS, FORMATION_ACADEMY } from '../game/siegeScenarios';
import { soundFx } from '../three/proceduralAudio';

export type MainMenuTab = 'play' | 'armory' | 'campaigns' | 'stats' | 'settings';

interface TitleOverlayProps {
  difficulty: BotDifficulty;
  playerColor: PieceColor;
  onlineCount: number;
  playerRating: number;
  gamesPlayed?: number;
  isFirstLaunch?: boolean;
  onCompleteOnboarding?: (diff: BotDifficulty) => void;
  arenaTheme?: ArenaTheme;
  factionSkin?: FactionSkin;
  weatherEffect?: WeatherEffect;
  onSelectDifficulty: (d: BotDifficulty) => void;
  onSelectColor: (c: PieceColor) => void;
  onSelectArena?: (a: ArenaTheme) => void;
  onSelectFaction?: (f: FactionSkin) => void;
  onSelectWeather?: (w: WeatherEffect) => void;
  onStartSolo: (customColor?: PieceColor, customDiff?: BotDifficulty, customFen?: string, variant?: VariantType) => void;
  onOpenRanked: () => void;
  onOpenSiegeModal?: () => void;
  onOpenAnalytics?: () => void;
  onOpenPuzzles?: () => void;
  onOpenVariants?: () => void;
  onOpenTournamentSocial?: () => void;
  onSelectScenario?: (s: SiegeScenario) => void;
  onToggleShowcaseOrbit?: (enabled: boolean) => void;
}

export const TitleOverlay: React.FC<TitleOverlayProps> = ({
  difficulty,
  playerColor,
  onlineCount,
  playerRating,
  gamesPlayed = 0,
  isFirstLaunch = false,
  onCompleteOnboarding,
  arenaTheme = 'courtyard',
  factionSkin = 'high_crusaders',
  weatherEffect = 'clear',
  onSelectDifficulty,
  onSelectColor,
  onSelectArena,
  onSelectFaction,
  onSelectWeather,
  onStartSolo,
  onOpenRanked,
  onOpenSiegeModal,
  onOpenAnalytics,
  onOpenPuzzles,
  onOpenVariants,
  onOpenTournamentSocial,
  onSelectScenario,
  onToggleShowcaseOrbit,
}) => {
  const [activeTab, setActiveTab] = useState<MainMenuTab>('play');
  const [isCinematicView, setIsCinematicView] = useState<boolean>(false);
  const [campaignTab, setCampaignTab] = useState<'siege' | 'formation'>('siege');
  const [showcaseOrbitActive, setShowcaseOrbitActive] = useState<boolean>(false);
  const [timeControl, setTimeControl] = useState<'10+0' | '5+3' | '3+0' | 'infinite'>('10+0');
  const [audioMuted, setAudioMuted] = useState<boolean>(false);
  const [masterVolume, setMasterVolume] = useState<number>(85);
  const [sfxVolume, setSfxVolume] = useState<number>(90);
  const [particlesEnabled, setParticlesEnabled] = useState<boolean>(true);
  const [shadowsHigh, setShadowsHigh] = useState<boolean>(true);
  const [isAltHeld, setIsAltHeld] = useState<boolean>(false);
  const [showOnboarding, setShowOnboarding] = useState<boolean>(Boolean(isFirstLaunch));

  // Tab switching with tactile audio and viewport camera response
  const handleTabChange = useCallback((tab: MainMenuTab) => {
    soundFx.playTabSwitch();
    setActiveTab(tab);
    if (tab === 'armory') {
      setShowcaseOrbitActive(true);
      onToggleShowcaseOrbit?.(true);
    } else {
      setShowcaseOrbitActive(false);
      onToggleShowcaseOrbit?.(false);
    }
  }, [onToggleShowcaseOrbit]);

  // Toggle cinematic inspection mode (unobstructed 3D Citadel view)
  const toggleCinematicView = useCallback(() => {
    soundFx.playMenuToggle();
    setIsCinematicView((prev) => !prev);
  }, []);

  // Launch match with epic battle audio
  const handleLaunchMatch = useCallback(() => {
    soundFx.playBladeDraw();
    setTimeout(() => {
      soundFx.playHeavySwordClash();
    }, 120);
    onStartSolo();
  }, [onStartSolo]);

  // Global Keyboard Navigation & Alt-Key listener
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Alt') {
        setIsAltHeld(true);
      }

      // Ignore if user is typing in an input
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }

      if (e.key === 'Enter') {
        e.preventDefault();
        handleLaunchMatch();
      } else if (e.key === 'Escape') {
        e.preventDefault();
        toggleCinematicView();
      } else if (e.key === '1') {
        handleTabChange('play');
      } else if (e.key === '2') {
        handleTabChange('armory');
      } else if (e.key === '3') {
        handleTabChange('campaigns');
      } else if (e.key === '4') {
        handleTabChange('stats');
      } else if (e.key === '5') {
        handleTabChange('settings');
      } else if (e.key === 'Tab') {
        e.preventDefault();
        const tabs: MainMenuTab[] = ['play', 'armory', 'campaigns', 'stats', 'settings'];
        const currentIdx = tabs.indexOf(activeTab);
        const nextIdx = e.shiftKey
          ? (currentIdx - 1 + tabs.length) % tabs.length
          : (currentIdx + 1) % tabs.length;
        handleTabChange(tabs[nextIdx]);
      }
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      if (e.key === 'Alt') {
        setIsAltHeld(false);
      }
    };

    const handleBlur = () => {
      setIsAltHeld(false);
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    window.addEventListener('blur', handleBlur);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
      window.removeEventListener('blur', handleBlur);
    };
  }, [activeTab, handleLaunchMatch, handleTabChange, toggleCinematicView]);

  return (
    <div className="absolute inset-0 z-20 flex flex-col justify-between pointer-events-none select-none text-stone-100">
      {/* =========================================================================
          FIRST-LAUNCH ONBOARDING MODAL
      ========================================================================= */}
      {showOnboarding && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md pointer-events-auto">
          <motion.div
            initial={{ opacity: 0, scale: 0.94 }}
            animate={{ opacity: 1, scale: 1 }}
            className="w-full max-w-lg bg-[#0b0f17] border border-amber-600/40 rounded-2xl p-6 shadow-2xl text-stone-100 space-y-4"
          >
            <div className="text-center space-y-1.5">
              <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-amber-950/70 border border-amber-600/50 text-[11px] font-mono text-amber-300">
                <Castle className="w-3.5 h-3.5 text-amber-400" />
                Citadel Orientation
              </div>
              <h2 className="text-xl font-serif font-bold text-amber-100">
                Select Your Chess Experience
              </h2>
              <p className="text-xs text-stone-400">
                Calibrate Grandmaster Aldric's sovereign depth and coaching guidance for your journey.
              </p>
            </div>

            <div className="space-y-2.5">
              {[
                {
                  id: 'apprentice',
                  label: 'Novice',
                  elo: 'Squire Depth · ~800 Elo',
                  desc: 'Tactical guidance, blunder alerts, and forgiving opening moves.',
                  icon: Shield,
                },
                {
                  id: 'knight',
                  label: 'Scholar',
                  elo: 'Knight Depth · ~1400 Elo',
                  desc: 'Balanced positional play, standard book openings, and tactical alertness.',
                  icon: Swords,
                },
                {
                  id: 'grandmaster',
                  label: 'Grandmaster',
                  elo: 'Master Depth · ~2200 Elo',
                  desc: 'Deep tactical calculations, ruthless punishment of inaccuracies, and mastery.',
                  icon: Crown,
                },
              ].map((exp) => {
                const Icon = exp.icon;
                return (
                  <button
                    key={exp.id}
                    type="button"
                    onClick={() => {
                      soundFx.playMenuToggle();
                      onSelectDifficulty(exp.id as BotDifficulty);
                      onCompleteOnboarding?.(exp.id as BotDifficulty);
                      setShowOnboarding(false);
                    }}
                    className="w-full p-3.5 rounded-xl bg-stone-900/80 hover:bg-amber-950/40 border border-stone-800 hover:border-amber-500/70 text-left transition-all duration-150 flex items-start gap-3 group cursor-pointer"
                  >
                    <div className="p-2 rounded-lg bg-stone-950 border border-stone-800 group-hover:border-amber-500/50 text-amber-400">
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-serif font-bold text-amber-200 group-hover:text-amber-100">
                          {exp.label}
                        </span>
                        <span className="text-[10px] font-mono text-amber-400/80">
                          {exp.elo}
                        </span>
                      </div>
                      <p className="text-[11px] text-stone-400 mt-0.5 leading-snug">
                        {exp.desc}
                      </p>
                    </div>
                  </button>
                );
              })}
            </div>
          </motion.div>
        </div>
      )}

      {/* =========================================================================
          TOP-RAIL FLOATING GLASS HEADER & MODULAR TAB BAR
      ========================================================================= */}
      <header className="p-2 sm:p-5 pointer-events-auto">
        <div className="max-w-7xl mx-auto flex flex-col md:flex-row items-center justify-between gap-2 sm:gap-3 px-3 sm:px-4 py-2 sm:py-2.5 rounded-2xl bg-[#0b0f17]/85 backdrop-blur-xl border border-stone-800/80 shadow-2xl shadow-black/80">
          {/* Top row on phone: Heraldry, Title & Right status */}
          <div className="w-full md:w-auto flex items-center justify-between gap-2">
            <div className="flex items-center gap-2 sm:gap-3">
              <div className="w-8 h-8 sm:w-10 sm:h-10 rounded-xl bg-gradient-to-br from-amber-700 via-amber-900 to-stone-950 border border-amber-500/40 flex items-center justify-center text-amber-300 shadow-lg shadow-amber-950/30">
                <Castle className="w-4 h-4 sm:w-5 sm:h-5 text-amber-400" />
              </div>
              <div>
                <div className="flex items-center gap-1.5 sm:gap-2">
                  <h1 className="text-lg sm:text-2xl font-serif font-bold tracking-wider text-amber-200 drop-shadow">
                    Sovereign's Gambit
                  </h1>
                  <span className="hidden md:inline-block px-2 py-0.5 rounded text-[10px] font-mono tracking-wider uppercase bg-amber-950/80 border border-amber-600/40 text-amber-300">
                    Citadel Edition
                  </span>
                </div>
                <p className="text-[10px] sm:text-[11px] text-stone-400 font-mono tracking-wide hidden sm:block">
                  3D Tactical Fantasy Chess & Real-time Grandmaster Coaching
                </p>
              </div>
            </div>

            {/* Mobile status pill cluster */}
            <div className="flex items-center gap-1.5 md:hidden">
              <div
                className="flex items-center gap-1 px-2 py-1 rounded-lg bg-amber-950/70 border border-amber-600/40 text-amber-300 text-[10px] shadow-sm"
                title={gamesPlayed === 0 ? 'Provisional Rating' : `${playerRating} Elo`}
              >
                <Trophy className="w-3 h-3 text-amber-400" />
                <span className="font-mono font-bold">
                  {gamesPlayed === 0 ? 'Prov.' : `${playerRating}`}
                </span>
              </div>

              <button
                type="button"
                onClick={toggleCinematicView}
                onMouseEnter={() => soundFx.playMenuHover()}
                title={isCinematicView ? 'Show Menu (Esc)' : 'Cinematic View (Esc)'}
                className="p-1.5 rounded-lg border bg-stone-900/80 text-stone-300 border-stone-800 cursor-pointer"
              >
                {isCinematicView ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
              </button>
            </div>
          </div>

          {/* Modular Nav Tab Bar with horizontal mobile scroll */}
          {!isCinematicView && (
            <nav className="w-full md:w-auto flex items-center gap-1 p-1 rounded-xl bg-stone-950/80 border border-stone-800/80 shadow-inner overflow-x-auto mobile-scroll-x max-w-full">
              {[
                { id: 'play', label: 'Play', icon: Swords },
                { id: 'armory', label: 'Armory & Citadel', icon: Shield },
                { id: 'campaigns', label: 'Siege Campaigns', icon: Flame },
                { id: 'stats', label: 'Stats & Review', icon: Compass },
                { id: 'settings', label: 'Settings', icon: Sliders },
              ].map((item) => {
                const Icon = item.icon;
                const isActive = activeTab === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => handleTabChange(item.id as MainMenuTab)}
                    onMouseEnter={() => soundFx.playMenuHover()}
                    className={`relative shrink-0 px-2.5 sm:px-4 py-1.5 sm:py-2 rounded-lg text-[11px] sm:text-xs font-serif font-bold flex items-center gap-1.5 sm:gap-2 transition-all duration-150 cursor-pointer ${
                      isActive
                        ? 'text-amber-200 bg-amber-950/70 border border-amber-500/50 shadow-md shadow-amber-950/40'
                        : 'text-stone-400 hover:text-stone-200 hover:bg-stone-900/60 border border-transparent'
                    }`}
                  >
                    <Icon className={`w-3.5 h-3.5 ${isActive ? 'text-amber-400' : 'text-stone-500'}`} />
                    <span>{item.label}</span>
                    {isActive && (
                      <motion.div
                        layoutId="activeTabIndicator"
                        className="absolute bottom-0 left-2 right-2 h-0.5 bg-gradient-to-r from-transparent via-amber-400 to-transparent"
                      />
                    )}
                  </button>
                );
              })}
            </nav>
          )}

          {/* Right Status & Utility Cluster (Desktop) */}
          <div className="hidden md:flex items-center gap-2">
            <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-stone-900/80 border border-stone-800 text-xs">
              <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
              <span className="font-mono text-stone-300 text-[11px]">{onlineCount} Online</span>
            </div>

            {/* Elo Display: Shows 'Provisional' if 0 games played or initial launch */}
            <div
              className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-amber-950/70 border border-amber-600/40 text-amber-300 text-xs shadow-sm"
              title={gamesPlayed === 0 ? 'Provisional Rating (0 Games Played)' : `Established Rating: ${playerRating} Elo`}
            >
              <Trophy className="w-3.5 h-3.5 text-amber-400" />
              <span className="font-mono font-bold text-[11px]">
                {gamesPlayed === 0 ? 'Provisional' : `${playerRating} Elo`}
              </span>
            </div>

            {/* Cinematic Camera Toggle */}
            <button
              type="button"
              onClick={toggleCinematicView}
              onMouseEnter={() => soundFx.playMenuHover()}
              title={isCinematicView ? 'Show Menu (Esc)' : 'Cinematic View (Esc)'}
              className={`p-2 rounded-lg border transition-all duration-150 cursor-pointer ${
                isCinematicView
                  ? 'bg-amber-600 text-stone-950 border-amber-300 font-bold shadow-lg shadow-amber-500/30'
                  : 'bg-stone-900/80 text-stone-300 border-stone-800 hover:border-amber-500/50'
              }`}
            >
              {isCinematicView ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          </div>
        </div>
      </header>

      {/* =========================================================================
          MAIN TAB CONTENT PANELS
      ========================================================================= */}
      <main className="flex-1 flex items-center justify-center p-3 sm:p-6 overflow-y-auto pointer-events-auto">
        <AnimatePresence mode="wait">
          {!isCinematicView && (
            <motion.div
              key={activeTab}
              initial={{ opacity: 0, y: 12, scale: 0.99 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -12, scale: 0.99 }}
              transition={{ duration: 0.18, ease: 'easeOut' }}
              className="w-full max-w-3xl"
            >
              {/* ===================================================================
                  TAB 1: PLAY (CLEANED UP & DE-CLUTTERED)
              =================================================================== */}
              {activeTab === 'play' && (
                <div className="p-5 sm:p-7 rounded-2xl bg-[#0b0f17]/90 backdrop-blur-2xl border border-stone-800/80 shadow-2xl shadow-black/90 text-stone-200">
                  {/* Clean Setup Header */}
                  <div className="pb-4 mb-5 border-b border-stone-800/80 text-center sm:text-left">
                    <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-amber-950/60 border border-amber-600/40 text-[11px] font-mono text-amber-300 mb-1.5">
                      <Sparkles className="w-3 h-3 text-amber-400" />
                      Grandmaster Sovereign Engine
                    </div>
                    <h2 className="text-xl sm:text-2xl font-serif font-bold text-amber-100">
                      Prepare Battle Formation
                    </h2>
                  </div>

                  {/* Core Match Configuration Grid */}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-5 mb-5">
                    {/* Allegiance & Banner Selection */}
                    <div className="p-4 rounded-xl bg-stone-950/70 border border-stone-800/80">
                      <label className="block text-xs uppercase tracking-wider font-mono text-amber-300/90 mb-2.5 flex items-center gap-1.5">
                        <Crown className="w-3.5 h-3.5 text-amber-400" />
                        Allegiance & Royal Banner
                      </label>
                      <div className="grid grid-cols-2 gap-2.5">
                        <button
                          type="button"
                          onClick={() => {
                            soundFx.playMenuToggle();
                            onSelectColor('w');
                          }}
                          onMouseEnter={() => soundFx.playMenuHover()}
                          className={`p-3 rounded-xl border text-left transition-all duration-150 cursor-pointer ${
                            playerColor === 'w'
                              ? 'bg-gradient-to-br from-amber-100 to-amber-200 text-stone-950 border-amber-400 font-bold shadow-lg shadow-amber-500/20'
                              : 'bg-stone-900/70 text-stone-300 border-stone-800 hover:border-stone-700'
                          }`}
                        >
                          <div className="flex items-center justify-between mb-1">
                            <span className="text-xs uppercase tracking-wider font-mono">White</span>
                            <Crown className="w-4 h-4 text-amber-600" />
                          </div>
                          <div className="text-sm font-serif font-bold">Radiant Vanguard</div>
                          <p className="text-[10px] opacity-80 mt-1">First Move</p>
                        </button>

                        <button
                          type="button"
                          onClick={() => {
                            soundFx.playMenuToggle();
                            onSelectColor('b');
                          }}
                          onMouseEnter={() => soundFx.playMenuHover()}
                          className={`p-3 rounded-xl border text-left transition-all duration-150 cursor-pointer ${
                            playerColor === 'b'
                              ? 'bg-gradient-to-br from-stone-900 to-stone-950 text-amber-200 border-amber-500 font-bold shadow-lg shadow-black/80'
                              : 'bg-stone-900/70 text-stone-300 border-stone-800 hover:border-stone-700'
                          }`}
                        >
                          <div className="flex items-center justify-between mb-1">
                            <span className="text-xs uppercase tracking-wider font-mono">Black</span>
                            <Shield className="w-4 h-4 text-amber-400" />
                          </div>
                          <div className="text-sm font-serif font-bold">Obsidian Host</div>
                          <p className="text-[10px] opacity-80 mt-1">Second Move</p>
                        </button>
                      </div>
                    </div>

                    {/* Coach Difficulty Selection */}
                    <div className="p-4 rounded-xl bg-stone-950/70 border border-stone-800/80">
                      <label className="block text-xs uppercase tracking-wider font-mono text-amber-300/90 mb-2.5 flex items-center gap-1.5">
                        <Award className="w-3.5 h-3.5 text-amber-400" />
                        Citadel Coach Difficulty
                      </label>
                      <div className="grid grid-cols-3 gap-2">
                        {[
                          { id: 'apprentice', label: 'Squire', elo: '800 Elo' },
                          { id: 'knight', label: 'Knight', elo: '1400 Elo' },
                          { id: 'grandmaster', label: 'Master', elo: '2200 Elo' },
                        ].map((d) => (
                          <button
                            key={d.id}
                            type="button"
                            onClick={() => {
                              soundFx.playMenuToggle();
                              onSelectDifficulty(d.id as BotDifficulty);
                            }}
                            onMouseEnter={() => soundFx.playMenuHover()}
                            className={`p-2.5 rounded-xl border text-left transition-all duration-150 cursor-pointer ${
                              difficulty === d.id
                                ? 'bg-amber-950/80 text-amber-200 border-amber-500 font-bold shadow-md shadow-amber-950/40'
                                : 'bg-stone-900/70 text-stone-400 border-stone-800 hover:border-stone-700'
                            }`}
                          >
                            <div className="text-xs font-serif font-bold text-amber-100">{d.label}</div>
                            <div className="text-[10px] font-mono text-amber-400/90 mt-0.5">{d.elo}</div>
                          </button>
                        ))}
                      </div>
                    </div>
                  </div>

                  {/* Time Control Row */}
                  <div className="p-3.5 rounded-xl bg-stone-950/60 border border-stone-800/60 flex flex-wrap items-center justify-between gap-3 mb-6 text-xs font-mono">
                    <div className="flex items-center gap-2">
                      <Clock className="w-3.5 h-3.5 text-amber-400" />
                      <span className="text-stone-400">Time Control:</span>
                      <div className="flex items-center gap-1">
                        {(['10+0', '5+3', '3+0', 'infinite'] as const).map((tc) => (
                          <button
                            key={tc}
                            type="button"
                            onClick={() => {
                              soundFx.playMenuToggle();
                              setTimeControl(tc);
                            }}
                            onMouseEnter={() => soundFx.playMenuHover()}
                            className={`px-2.5 py-1 rounded text-[11px] border transition-all duration-150 cursor-pointer ${
                              timeControl === tc
                                ? 'bg-amber-600/30 text-amber-200 border-amber-500 font-bold'
                                : 'bg-stone-900/60 text-stone-400 border-stone-800 hover:border-stone-700'
                            }`}
                          >
                            {tc === 'infinite' ? 'Untimed' : tc}
                          </button>
                        ))}
                      </div>
                    </div>

                    <div className="flex items-center gap-2 text-[11px] text-stone-400">
                      <span>Arena: <strong className="text-amber-300 font-serif capitalize">{arenaTheme.replace('_', ' ')}</strong></span>
                      <span>•</span>
                      <span>Faction: <strong className="text-amber-300 font-serif capitalize">{factionSkin.replace('_', ' ')}</strong></span>
                    </div>
                  </div>

                  {/* SINGLE PROMINENT ACTION CTA */}
                  <div className="pt-2 flex justify-center">
                    <button
                      type="button"
                      onClick={handleLaunchMatch}
                      onMouseEnter={() => soundFx.playMenuHover()}
                      className="w-full sm:w-auto min-w-[280px] py-3.5 px-8 rounded-xl bg-gradient-to-r from-amber-500 via-amber-600 to-amber-700 hover:from-amber-400 hover:via-amber-500 hover:to-amber-600 text-stone-950 font-serif font-bold text-base shadow-xl shadow-amber-950/60 flex items-center justify-center gap-2.5 transition-all duration-150 transform active:scale-95 border border-amber-300 cursor-pointer"
                    >
                      <Swords className="w-5 h-5 text-stone-950" />
                      <span>Launch Match</span>
                    </button>
                  </div>
                </div>
              )}

              {/* ===================================================================
                  TAB 2: ARMORY & CITADEL (3D SHOWROOM PREVIEW)
              =================================================================== */}
              {activeTab === 'armory' && (
                <div className="p-5 sm:p-7 rounded-2xl bg-[#0b0f17]/90 backdrop-blur-2xl border border-stone-800/80 shadow-2xl shadow-black/90 text-stone-200">
                  <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 pb-4 mb-5 border-b border-stone-800/80">
                    <div>
                      <h2 className="text-xl sm:text-2xl font-serif font-bold text-amber-100 flex items-center gap-2">
                        <Shield className="w-5 h-5 text-amber-400" />
                        Citadel Armory & Battlefield Aesthetics
                      </h2>
                      <p className="text-xs text-stone-400 font-serif mt-1">
                        Select skins, battlements, and atmospheric weather to dynamically transform the 3D scene in real time.
                      </p>
                    </div>

                    <button
                      type="button"
                      onClick={() => {
                        soundFx.playMenuToggle();
                        const next = !showcaseOrbitActive;
                        setShowcaseOrbitActive(next);
                        onToggleShowcaseOrbit?.(next);
                      }}
                      onMouseEnter={() => soundFx.playMenuHover()}
                      className={`px-3 py-1.5 rounded-lg border text-xs font-serif flex items-center gap-2 transition-all duration-150 cursor-pointer ${
                        showcaseOrbitActive
                          ? 'bg-amber-600/40 text-amber-200 border-amber-400 font-bold shadow'
                          : 'bg-stone-900/80 text-stone-300 border-stone-700 hover:border-stone-500'
                      }`}
                    >
                      <Compass className="w-3.5 h-3.5 text-amber-400 animate-spin" />
                      <span>{showcaseOrbitActive ? 'Showcase Angle: ON' : 'Inspect Showroom'}</span>
                    </button>
                  </div>

                  {/* 3-Column Interactive Showroom Grid */}
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
                    {/* Column 1: Faction Armories */}
                    <div className="space-y-2.5">
                      <div className="flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-wider text-amber-300">
                        <Layers className="w-4 h-4 text-amber-400" />
                        <span>Faction Armory</span>
                      </div>

                      <div className="space-y-2">
                        {[
                          { id: 'high_crusaders', name: 'High Crusaders', tag: 'Argent Plate & Gold', desc: 'Vanguard knights with heraldic tabards and polished iron swords.' },
                          { id: 'shadow_cultists', name: 'Shadow Cultists', tag: 'Obsidian & Arcane Runes', desc: 'Dark sorceresses, horned casters, and blighted steel blades.' },
                          { id: 'golems_gargoyles', name: 'Steel Golems & Gargoyles', tag: 'Granite & Ballistas', desc: 'Runic stone constructs with heavy siege crossbows.' },
                          { id: 'norse_raiders', name: 'Norse Raiders', tag: 'Wolfhide & Iron Runic', desc: 'Berserker axes, round timber shields, and runic battle axes.' },
                        ].map((f) => (
                          <button
                            key={f.id}
                            type="button"
                            onClick={() => {
                              soundFx.playMenuToggle();
                              onSelectFaction?.(f.id as FactionSkin);
                            }}
                            onMouseEnter={() => soundFx.playMenuHover()}
                            className={`w-full p-3 rounded-xl border text-left transition-all duration-150 cursor-pointer ${
                              factionSkin === f.id
                                ? 'bg-amber-950/80 border-amber-500 text-amber-100 shadow-md shadow-amber-950/50'
                                : 'bg-stone-950/60 border-stone-800/80 text-stone-400 hover:border-stone-700 hover:text-stone-200'
                            }`}
                          >
                            <div className="flex items-center justify-between">
                              <span className="text-xs font-serif font-bold text-amber-200">{f.name}</span>
                              {factionSkin === f.id && <Check className="w-3.5 h-3.5 text-amber-400" />}
                            </div>
                            <div className="text-[10px] font-mono text-amber-400/80 mt-0.5">{f.tag}</div>
                            <p className="text-[10px] text-stone-400 mt-1 line-clamp-1">{f.desc}</p>
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Column 2: Citadel Arenas */}
                    <div className="space-y-2.5">
                      <div className="flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-wider text-amber-300">
                        <Castle className="w-4 h-4 text-amber-400" />
                        <span>Citadel Arena</span>
                      </div>

                      <div className="space-y-2">
                        {[
                          { id: 'courtyard', name: 'Castle Courtyard', tag: 'Open Battlements', desc: 'Sunlit stonework with waving guild banners and grand parapets.' },
                          { id: 'dungeon_vault', name: 'Dungeon Vault', tag: 'Subterranean Crypt', desc: 'Dark obsidian slate, heavy iron portcullises, and mossy damp.' },
                          { id: 'besieged_ruins', name: 'Besieged Ruins', tag: 'Scorched Earth', desc: 'Crumbling stone crenellations, smoke trails, and glowing embers.' },
                          { id: 'throne_room', name: 'Royal Throne Room', tag: 'Imperial Sanctuary', desc: 'Crimson royal carpet, gold leaf inlays, and chandelier glow.' },
                        ].map((a) => (
                          <button
                            key={a.id}
                            type="button"
                            onClick={() => {
                              soundFx.playMenuToggle();
                              onSelectArena?.(a.id as ArenaTheme);
                            }}
                            onMouseEnter={() => soundFx.playMenuHover()}
                            className={`w-full p-3 rounded-xl border text-left transition-all duration-150 cursor-pointer ${
                              arenaTheme === a.id
                                ? 'bg-amber-950/80 border-amber-500 text-amber-100 shadow-md shadow-amber-950/50'
                                : 'bg-stone-950/60 border-stone-800/80 text-stone-400 hover:border-stone-700 hover:text-stone-200'
                            }`}
                          >
                            <div className="flex items-center justify-between">
                              <span className="text-xs font-serif font-bold text-amber-200">{a.name}</span>
                              {arenaTheme === a.id && <Check className="w-3.5 h-3.5 text-amber-400" />}
                            </div>
                            <div className="text-[10px] font-mono text-amber-400/80 mt-0.5">{a.tag}</div>
                            <p className="text-[10px] text-stone-400 mt-1 line-clamp-1">{a.desc}</p>
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Column 3: Atmosphere & Dynamic Weather */}
                    <div className="space-y-2.5">
                      <div className="flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-wider text-amber-300">
                        <CloudRain className="w-4 h-4 text-amber-400" />
                        <span>Atmosphere & Weather</span>
                      </div>

                      <div className="space-y-2">
                        {[
                          { id: 'clear', name: 'Clear Daylight', tag: 'Sunlight & Calm Skies', icon: Sun },
                          { id: 'rain', name: 'Torrential Rain', tag: 'Wind-blown Rain Streaks', icon: CloudRain },
                          { id: 'snow', name: 'Citadel Snow', tag: 'Drifting Flakes & Frost', icon: Snowflake },
                          { id: 'night_torches', name: 'Night Torches', tag: 'Flickering Fire Braziers', icon: Flame },
                        ].map((w) => {
                          const Icon = w.icon;
                          return (
                            <button
                              key={w.id}
                              type="button"
                              onClick={() => {
                                soundFx.playMenuToggle();
                                onSelectWeather?.(w.id as WeatherEffect);
                              }}
                              onMouseEnter={() => soundFx.playMenuHover()}
                              className={`w-full p-3 rounded-xl border text-left transition-all duration-150 cursor-pointer ${
                                weatherEffect === w.id
                                  ? 'bg-amber-950/80 border-amber-500 text-amber-100 shadow-md shadow-amber-950/50'
                                  : 'bg-stone-950/60 border-stone-800/80 text-stone-400 hover:border-stone-700 hover:text-stone-200'
                              }`}
                            >
                              <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                  <Icon className="w-3.5 h-3.5 text-amber-400" />
                                  <span className="text-xs font-serif font-bold text-amber-200">{w.name}</span>
                                </div>
                                {weatherEffect === w.id && <Check className="w-3.5 h-3.5 text-amber-400" />}
                              </div>
                              <div className="text-[10px] font-mono text-amber-400/80 mt-1">{w.tag}</div>
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* ===================================================================
                  TAB 3: SIEGE CAMPAIGNS
              =================================================================== */}
              {activeTab === 'campaigns' && (
                <div className="p-5 sm:p-7 rounded-2xl bg-[#0b0f17]/90 backdrop-blur-2xl border border-stone-800/80 shadow-2xl shadow-black/90 text-stone-200">
                  <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 pb-4 mb-5 border-b border-stone-800/80">
                    <div>
                      <h2 className="text-xl sm:text-2xl font-serif font-bold text-amber-100 flex items-center gap-2">
                        <Flame className="w-5 h-5 text-amber-400" />
                        Siege Campaigns & Formation Academy
                      </h2>
                      <p className="text-xs text-stone-400 font-serif mt-1">
                        Train classical battle formations and historical tactical breakthroughs under Grandmaster guidance.
                      </p>
                    </div>

                    {/* Sub-tab Switcher */}
                    <div className="flex p-1 rounded-xl bg-stone-950 border border-stone-800">
                      <button
                        type="button"
                        onClick={() => {
                          soundFx.playMenuToggle();
                          setCampaignTab('siege');
                        }}
                        className={`px-3 py-1.5 rounded-lg text-xs font-serif font-bold transition-all duration-150 cursor-pointer ${
                          campaignTab === 'siege'
                            ? 'bg-amber-600/30 text-amber-200 border border-amber-500/60 shadow-sm'
                            : 'text-stone-400 hover:text-stone-200'
                        }`}
                      >
                        Siege Battles
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          soundFx.playMenuToggle();
                          setCampaignTab('formation');
                        }}
                        className={`px-3 py-1.5 rounded-lg text-xs font-serif font-bold transition-all duration-150 cursor-pointer ${
                          campaignTab === 'formation'
                            ? 'bg-amber-600/30 text-amber-200 border border-amber-500/60 shadow-sm'
                            : 'text-stone-400 hover:text-stone-200'
                        }`}
                      >
                        Formation Academy
                      </button>
                    </div>
                  </div>

                  {/* Scenarios Grid */}
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3.5 max-h-[52vh] overflow-y-auto citadel-scroll pr-1">
                    {(campaignTab === 'siege' ? SIEGE_CAMPAIGNS : FORMATION_ACADEMY).map((scenario) => (
                      <div
                        key={scenario.id}
                        className="p-4 rounded-xl bg-stone-950/70 border border-stone-800 hover:border-amber-500/60 transition-all duration-150 flex flex-col justify-between group shadow-md"
                      >
                        <div>
                          <div className="flex items-center justify-between gap-2 mb-2">
                            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-amber-950/90 border border-amber-600/50 text-amber-300 font-bold">
                              {scenario.difficulty}
                            </span>
                            <span className="text-[10px] font-mono text-stone-400">
                              {scenario.category === 'siege_campaign' ? 'Tactical Siege' : 'Opening Drill'}
                            </span>
                          </div>

                          <h3 className="text-sm font-serif font-bold text-amber-100 group-hover:text-amber-300 transition-colors">
                            {scenario.title}
                          </h3>
                          <p className="text-xs text-stone-300 mt-1.5 line-clamp-2">
                            {scenario.description}
                          </p>

                          <div className="mt-2.5 pt-2 border-t border-stone-800/60 text-[11px] text-amber-400/90 font-mono">
                            Goal: <span className="text-stone-300">{scenario.goalText}</span>
                          </div>
                        </div>

                        <button
                          type="button"
                          onClick={() => {
                            soundFx.playBladeDraw();
                            if (onSelectScenario) {
                              onSelectScenario(scenario);
                            } else {
                              onOpenSiegeModal?.();
                            }
                          }}
                          onMouseEnter={() => soundFx.playMenuHover()}
                          className="mt-4 w-full py-2 px-3 rounded-lg bg-stone-900 hover:bg-amber-600 hover:text-stone-950 border border-amber-600/40 hover:border-amber-400 text-amber-200 text-xs font-serif font-bold flex items-center justify-center gap-1.5 transition-all duration-150 shadow-sm cursor-pointer"
                        >
                          <Swords className="w-3.5 h-3.5" />
                          <span>Commence Siege</span>
                        </button>
                      </div>
                    ))}
                  </div>

                  {/* Footnote launcher */}
                  <div className="mt-4 pt-3 border-t border-stone-800/80 flex items-center justify-between text-xs text-stone-400 font-mono">
                    <span>Looking for endless speed puzzles?</span>
                    <button
                      type="button"
                      onClick={onOpenPuzzles}
                      onMouseEnter={() => soundFx.playMenuHover()}
                      className="text-amber-400 hover:text-amber-300 underline font-serif flex items-center gap-1 cursor-pointer"
                    >
                      <Zap className="w-3 h-3" />
                      Open Rated Puzzles & Puzzle Rush Suite
                    </button>
                  </div>
                </div>
              )}

              {/* ===================================================================
                  TAB 4: STATS & REVIEW
              =================================================================== */}
              {activeTab === 'stats' && (
                <div className="p-5 sm:p-7 rounded-2xl bg-[#0b0f17]/90 backdrop-blur-2xl border border-stone-800/80 shadow-2xl shadow-black/90 text-stone-200">
                  <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 pb-4 mb-5 border-b border-stone-800/80">
                    <div>
                      <h2 className="text-xl sm:text-2xl font-serif font-bold text-amber-100 flex items-center gap-2">
                        <Compass className="w-5 h-5 text-amber-400" />
                        Citadel Stats & Tactical Performance
                      </h2>
                      <p className="text-xs text-stone-400 font-serif mt-1">
                        Lifetime ratings across time controls, move accuracy distributions, and opening mastery.
                      </p>
                    </div>

                    <button
                      type="button"
                      onClick={onOpenAnalytics}
                      onMouseEnter={() => soundFx.playMenuHover()}
                      className="px-3.5 py-1.5 rounded-lg bg-amber-600/30 hover:bg-amber-600/50 border border-amber-500/60 text-amber-200 text-xs font-serif font-bold flex items-center gap-2 transition-all duration-150 shadow cursor-pointer"
                    >
                      <Compass className="w-3.5 h-3.5 text-amber-400" />
                      <span>Open Full Syzygy & ECO Suite</span>
                    </button>
                  </div>

                  {/* 4 Time-Control Discipline Cards */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
                    {[
                      { discipline: 'Bullet', elo: gamesPlayed === 0 ? 'Provisional' : 1240, peak: 1310, winRate: '58%', icon: Zap },
                      { discipline: 'Blitz', elo: gamesPlayed === 0 ? 'Provisional' : 1410, peak: 1455, winRate: '62%', icon: Swords },
                      { discipline: 'Rapid', elo: gamesPlayed === 0 ? 'Provisional' : playerRating, peak: Math.max(playerRating + 40, 1560), winRate: '65%', icon: Trophy },
                      { discipline: 'Daily', elo: gamesPlayed === 0 ? 'Provisional' : 1600, peak: 1640, winRate: '71%', icon: BookOpen },
                    ].map((item) => {
                      const Icon = item.icon;
                      return (
                        <div key={item.discipline} className="p-3.5 rounded-xl bg-stone-950/70 border border-stone-800">
                          <div className="flex items-center justify-between text-xs text-stone-400 font-mono mb-1">
                            <span>{item.discipline}</span>
                            <Icon className="w-3.5 h-3.5 text-amber-400" />
                          </div>
                          <div className="text-xl font-mono font-bold text-amber-200">{item.elo}</div>
                          <div className="flex items-center justify-between text-[10px] text-stone-400 mt-1 font-mono">
                            <span>Peak: {item.peak}</span>
                            <span className="text-emerald-400 font-bold">{item.winRate} Win</span>
                          </div>
                        </div>
                      );
                    })}
                  </div>

                  {/* Accuracy & Mental State Row */}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {/* Move Accuracy Breakdown */}
                    <div className="p-4 rounded-xl bg-stone-950/70 border border-stone-800">
                      <div className="text-xs uppercase font-mono tracking-wider text-amber-300 font-bold mb-3 flex items-center gap-2">
                        <Activity className="w-3.5 h-3.5 text-amber-400" />
                        <span>Move Quality Profile</span>
                      </div>
                      <div className="space-y-2">
                        {[
                          { label: 'Brilliant', pct: 4, color: 'bg-cyan-400' },
                          { label: 'Great Moves', pct: 14, color: 'bg-blue-400' },
                          { label: 'Best Moves', pct: 44, color: 'bg-emerald-400' },
                          { label: 'Inaccuracies', pct: 24, color: 'bg-amber-400' },
                          { label: 'Blunders', pct: 14, color: 'bg-red-500' },
                        ].map((m) => (
                          <div key={m.label} className="space-y-1">
                            <div className="flex items-center justify-between text-xs font-mono">
                              <span className="text-stone-300">{m.label}</span>
                              <span className="text-amber-300 font-bold">{m.pct}%</span>
                            </div>
                            <div className="w-full h-1.5 rounded-full bg-stone-800 overflow-hidden">
                              <div className={`h-full ${m.color}`} style={{ width: `${m.pct}%` }} />
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>

                    {/* Mental Tilt & Opening Explorer Mini-Panel */}
                    <div className="p-4 rounded-xl bg-stone-950/70 border border-stone-800 flex flex-col justify-between">
                      <div>
                        <div className="text-xs uppercase font-mono tracking-wider text-amber-300 font-bold mb-2 flex items-center gap-2">
                          <Crown className="w-3.5 h-3.5 text-amber-400" />
                          <span>Citadel Mental Tilt Index</span>
                        </div>
                        <div className="p-3 rounded-lg bg-stone-900/80 border border-stone-700/60 mb-3">
                          <div className="flex items-center justify-between">
                            <span className="text-xs font-serif font-bold text-emerald-300">Calm & Resolute</span>
                            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-emerald-950 text-emerald-300 border border-emerald-600/40 font-bold">
                              Low Stress (14%)
                            </span>
                          </div>
                          <p className="text-[11px] text-stone-400 mt-1">
                            Loss streak counter is zero. Calculating with full tactical clarity and stable move cadence.
                          </p>
                        </div>
                      </div>

                      <div className="pt-3 border-t border-stone-800/60 flex items-center justify-between">
                        <span className="text-xs font-mono text-stone-400">Games Logged:</span>
                        <span className="text-sm font-mono font-bold text-amber-300">{gamesPlayed}</span>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* ===================================================================
                  TAB 5: SETTINGS
              =================================================================== */}
              {activeTab === 'settings' && (
                <div className="p-5 sm:p-7 rounded-2xl bg-[#0b0f17]/90 backdrop-blur-2xl border border-stone-800/80 shadow-2xl shadow-black/90 text-stone-200">
                  <div className="pb-4 mb-5 border-b border-stone-800/80">
                    <h2 className="text-xl sm:text-2xl font-serif font-bold text-amber-100 flex items-center gap-2">
                      <Sliders className="w-5 h-5 text-amber-400" />
                      Citadel Settings & Keybindings
                    </h2>
                    <p className="text-xs text-stone-400 font-serif mt-1">
                      Tune procedural audio levels, WebGL graphics fidelity, and inspect keyboard shortcuts.
                    </p>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-5 mb-5">
                    {/* Audio Mixers */}
                    <div className="p-4 rounded-xl bg-stone-950/70 border border-stone-800 space-y-4">
                      <div className="text-xs font-mono font-bold uppercase tracking-wider text-amber-300 flex items-center gap-2">
                        <Volume2 className="w-4 h-4 text-amber-400" />
                        <span>Procedural Audio</span>
                      </div>

                      <div className="space-y-3">
                        <div>
                          <div className="flex items-center justify-between text-xs font-mono mb-1.5">
                            <span className="text-stone-300">Master Volume</span>
                            <span className="text-amber-300 font-bold">{masterVolume}%</span>
                          </div>
                          <input
                            type="range"
                            min="0"
                            max="100"
                            value={masterVolume}
                            onChange={(e) => setMasterVolume(parseInt(e.target.value, 10))}
                            className="w-full accent-amber-500 cursor-pointer"
                          />
                        </div>

                        <div>
                          <div className="flex items-center justify-between text-xs font-mono mb-1.5">
                            <span className="text-stone-300">SFX & Clashes</span>
                            <span className="text-amber-300 font-bold">{sfxVolume}%</span>
                          </div>
                          <input
                            type="range"
                            min="0"
                            max="100"
                            value={sfxVolume}
                            onChange={(e) => setSfxVolume(parseInt(e.target.value, 10))}
                            className="w-full accent-amber-500 cursor-pointer"
                          />
                        </div>

                        <div className="pt-2 flex items-center justify-between">
                          <span className="text-xs font-mono text-stone-300">Mute Audio</span>
                          <button
                            type="button"
                            onClick={() => {
                              const next = !audioMuted;
                              setAudioMuted(next);
                              soundFx.setMuted(next);
                            }}
                            className={`px-3 py-1 rounded-lg border text-xs font-mono transition-all duration-150 cursor-pointer ${
                              audioMuted
                                ? 'bg-red-950 text-red-200 border-red-500 font-bold'
                                : 'bg-stone-900 text-stone-300 border-stone-700'
                            }`}
                          >
                            {audioMuted ? 'Muted' : 'Sound Active'}
                          </button>
                        </div>
                      </div>
                    </div>

                    {/* Graphics & Fidelity */}
                    <div className="p-4 rounded-xl bg-stone-950/70 border border-stone-800 space-y-4">
                      <div className="text-xs font-mono font-bold uppercase tracking-wider text-amber-300 flex items-center gap-2">
                        <Sparkles className="w-4 h-4 text-amber-400" />
                        <span>Graphics & Fidelity</span>
                      </div>

                      <div className="space-y-3 text-xs font-mono">
                        <div className="flex items-center justify-between">
                          <div>
                            <div className="text-stone-200 font-bold">Weather Particles</div>
                            <div className="text-[10px] text-stone-400">Rain & Snow physics</div>
                          </div>
                          <button
                            type="button"
                            onClick={() => {
                              soundFx.playMenuToggle();
                              setParticlesEnabled((v) => !v);
                            }}
                            className={`px-3 py-1 rounded-lg border transition-all duration-150 cursor-pointer ${
                              particlesEnabled
                                ? 'bg-amber-600/30 text-amber-200 border-amber-500 font-bold'
                                : 'bg-stone-900 text-stone-400 border-stone-700'
                            }`}
                          >
                            {particlesEnabled ? 'Enabled' : 'Disabled'}
                          </button>
                        </div>

                        <div className="flex items-center justify-between">
                          <div>
                            <div className="text-stone-200 font-bold">Soft Shadows</div>
                            <div className="text-[10px] text-stone-400">Real-time piece shadows</div>
                          </div>
                          <button
                            type="button"
                            onClick={() => {
                              soundFx.playMenuToggle();
                              setShadowsHigh((v) => !v);
                            }}
                            className={`px-3 py-1 rounded-lg border transition-all duration-150 cursor-pointer ${
                              shadowsHigh
                                ? 'bg-amber-600/30 text-amber-200 border-amber-500 font-bold'
                                : 'bg-stone-900 text-stone-400 border-stone-700'
                            }`}
                          >
                            {shadowsHigh ? 'High Quality' : 'Low Spec'}
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </main>

      {/* =========================================================================
          BOTTOM FOOTER: MINIMALIST BREADCRUMB & ALT POPUP
      ========================================================================= */}
      <footer className="p-3 sm:p-5 pointer-events-auto flex flex-col items-center justify-center relative">
        {/* Floating Shortcuts Popover when Alt is held */}
        <AnimatePresence>
          {isAltHeld && !isCinematicView && (
            <motion.div
              initial={{ opacity: 0, y: 8, scale: 0.96 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 8, scale: 0.96 }}
              className="absolute bottom-full mb-3 px-5 py-3 rounded-xl bg-stone-950/95 backdrop-blur-xl border border-amber-600/50 shadow-2xl shadow-black text-xs font-mono text-stone-300 z-30 space-y-1.5"
            >
              <div className="text-[10px] uppercase font-bold text-amber-400 tracking-wider">
                Keyboard Shortcuts:
              </div>
              <div className="grid grid-cols-2 gap-x-6 gap-y-1 text-[11px]">
                <span><strong className="text-amber-200">[Enter]</strong> Launch Match</span>
                <span><strong className="text-amber-200">[Space]</strong> Toggle 2D/3D</span>
                <span><strong className="text-amber-200">[Esc]</strong> Cinematic Mode</span>
                <span><strong className="text-amber-200">[Tab]</strong> Cycle Tabs</span>
                <span><strong className="text-amber-200">[1-5]</strong> Direct Tab Jump</span>
                <span><strong className="text-amber-200">[C]</strong> Coach Drawer</span>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {isCinematicView ? (
          <motion.div
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex items-center gap-3 px-5 py-2.5 rounded-full bg-[#0b0f17]/85 backdrop-blur-xl border border-stone-800/80 shadow-2xl shadow-black text-xs font-mono"
          >
            <span className="w-2 h-2 rounded-full bg-amber-400 animate-ping" />
            <span className="text-stone-300 font-serif">Cinematic Citadel Mode</span>
            <span className="text-stone-600">•</span>
            <span className="text-stone-400">Click & Drag to Orbit • Scroll to Zoom</span>
            <button
              type="button"
              onClick={toggleCinematicView}
              onMouseEnter={() => soundFx.playMenuHover()}
              className="ml-2 px-3 py-1 rounded-full bg-amber-600 hover:bg-amber-500 text-stone-950 font-bold font-serif flex items-center gap-1.5 transition-all duration-150 shadow cursor-pointer"
            >
              <span>Return to Menu</span>
              <span className="text-[10px] font-mono">[Esc]</span>
            </button>
          </motion.div>
        ) : (
          <div className="flex items-center gap-2 sm:gap-3 text-xs font-mono text-stone-400/90 bg-stone-950/70 backdrop-blur-md px-4 py-1.5 rounded-full border border-stone-800/70 shadow-lg">
            <span>[Space] 2D View</span>
            <span className="text-stone-600">•</span>
            <span>[Esc] Menu</span>
            <span className="text-stone-600">•</span>
            <span className="text-amber-300/90 font-medium">[Hold Alt] Show Shortcuts</span>
          </div>
        )}
      </footer>
    </div>
  );
};
