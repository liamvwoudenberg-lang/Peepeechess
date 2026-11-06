import React, { useState } from 'react';
import {
  X,
  Trophy,
  Users,
  Tv,
  Smile,
  Shield,
  Clock,
  Sparkles,
  ExternalLink,
  ChevronRight,
  Flame,
} from 'lucide-react';
import { createMockTournament } from '../multiplayer/tournamentEngine';
import {
  MEDIEVAL_MATCH_EMOTES,
  POPULAR_CLAN_CLUBS,
  TITLED_STREAMERS,
  WEEKLY_LEAGUE_TABLE,
} from '../multiplayer/socialHub';
import { soundFx } from '../three/proceduralAudio';
import { MatchEmote } from '../types/chess';

interface TournamentSocialModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSendEmote?: (emote: MatchEmote) => void;
}

export const TournamentSocialModal: React.FC<TournamentSocialModalProps> = ({
  isOpen,
  onClose,
  onSendEmote,
}) => {
  const [activeTab, setActiveTab] = useState<'tournaments' | 'leagues' | 'clans' | 'streams' | 'emotes'>('tournaments');
  const [tournament] = useState(() => createMockTournament());

  if (!isOpen) return null;

  const handlePlayEmote = (emote: MatchEmote) => {
    if (emote.sfx === 'metal_clash') soundFx.playHeavySwordClash();
    else if (emote.sfx === 'horn_check') soundFx.playCheckHorn();
    else if (emote.sfx === 'fanfare_victory') soundFx.playVictoryFanfare(true);
    else soundFx.playSelect();

    onSendEmote?.(emote);
  };

  return (
    <div className="fixed inset-0 z-40 bg-black/80 backdrop-blur-md flex items-center justify-center p-3 sm:p-5">
      <div className="w-full max-w-4xl bg-stone-950 border-2 border-amber-700/60 rounded-2xl shadow-2xl text-stone-200 overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <header className="p-4 border-b border-stone-800 flex items-center justify-between bg-stone-900/70">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-950/80 border border-amber-600/60 flex items-center justify-center text-amber-400">
              <Trophy className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-lg font-serif font-bold text-amber-200">
                Citadel Social Hub & Tournaments
              </h2>
              <p className="text-xs text-stone-400 font-mono">
                Automated Tournaments · Weekly Divisions · Clans · Titled Streams · Emotes
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
            onClick={() => setActiveTab('tournaments')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'tournaments'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Trophy className="w-4 h-4 text-amber-400" />
            Citadel Arena Tournaments
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('leagues')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'leagues'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Shield className="w-4 h-4 text-amber-400" />
            Weekly Divisions (XP)
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('clans')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'clans'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Users className="w-4 h-4 text-amber-400" />
            Clans & Guilds
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('streams')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'streams'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Tv className="w-4 h-4 text-amber-400" />
            Titled Streamers
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('emotes')}
            className={`py-3 px-4 font-serif font-bold flex items-center gap-2 border-b-2 shrink-0 transition-all ${
              activeTab === 'emotes'
                ? 'border-amber-500 text-amber-300 bg-stone-900/60'
                : 'border-transparent text-stone-400 hover:text-stone-200'
            }`}
          >
            <Smile className="w-4 h-4 text-amber-400" />
            Match Emotes & SFX
          </button>
        </div>

        {/* Tab Body */}
        <div className="p-4 sm:p-6 overflow-y-auto space-y-6 flex-1 text-xs">
          {/* TAB 1: TOURNAMENTS */}
          {activeTab === 'tournaments' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 flex flex-wrap items-center justify-between gap-3">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-emerald-950 border border-emerald-600/50 text-emerald-300 font-bold uppercase animate-pulse">
                      Live
                    </span>
                    <h3 className="text-sm font-serif font-bold text-amber-100">
                      {tournament.name} ({tournament.type.toUpperCase()})
                    </h3>
                  </div>
                  <p className="text-stone-400 text-xs font-serif mt-1">
                    Round {tournament.round} of {tournament.maxRounds} · 5+0 Rapid Time Control
                  </p>
                </div>

                <div className="flex items-center gap-3 font-mono text-xs text-amber-300 bg-stone-950 px-3 py-1.5 rounded-lg border border-stone-800">
                  <Clock className="w-4 h-4" />
                  <span>{Math.floor(tournament.timeRemainingSec / 60)}m {tournament.timeRemainingSec % 60}s remaining</span>
                </div>
              </div>

              {/* Tournament Standings */}
              <div>
                <h4 className="text-xs font-mono uppercase text-amber-300 font-bold mb-2 flex items-center gap-1.5">
                  <Trophy className="w-3.5 h-3.5 text-amber-400" />
                  Live Tournament Standings
                </h4>
                <div className="rounded-xl border border-stone-800 overflow-hidden divide-y divide-stone-800">
                  {tournament.players.map((p, rank) => (
                    <div
                      key={p.id}
                      className="p-2.5 bg-stone-900/40 hover:bg-stone-900/70 flex items-center justify-between font-mono"
                    >
                      <div className="flex items-center gap-3">
                        <span className="font-bold text-amber-400 w-4">#{rank + 1}</span>
                        <div className="font-serif text-stone-200 flex items-center gap-1.5">
                          <span>{p.name}</span>
                          {p.title && (
                            <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-amber-950 border border-amber-600/50 text-amber-300">
                              {p.title}
                            </span>
                          )}
                        </div>
                      </div>
                      <div className="flex items-center gap-4 text-xs">
                        <span className="text-stone-400 font-bold">{p.rating}</span>
                        <span className="text-amber-300 font-bold">{p.score} pts</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: WEEKLY LEAGUE DIVISIONS */}
          {activeTab === 'leagues' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 flex items-center justify-between">
                <div>
                  <span className="text-[10px] font-mono uppercase px-2 py-0.5 rounded bg-amber-950 border border-amber-600/50 text-amber-300 font-bold">
                    Gold Division III
                  </span>
                  <h3 className="text-sm font-serif font-bold text-amber-100 mt-1">
                    Weekly XP Championship
                  </h3>
                  <p className="text-stone-400 text-xs font-serif">
                    Top 3 promote to Platinum League on Sunday midnight
                  </p>
                </div>
                <div className="text-right font-mono">
                  <div className="text-xs text-stone-400">Your Standing</div>
                  <div className="text-base font-bold text-emerald-400">#4 (1,650 XP)</div>
                </div>
              </div>

              <div className="rounded-xl border border-stone-800 overflow-hidden divide-y divide-stone-800 font-mono text-xs">
                {WEEKLY_LEAGUE_TABLE.map((u) => (
                  <div
                    key={u.rank}
                    className={`p-3 flex items-center justify-between ${
                      u.isCurrentUser
                        ? 'bg-amber-950/40 border-l-4 border-l-amber-500 font-bold text-amber-200'
                        : u.rank <= 3
                        ? 'bg-stone-900/50 text-stone-200'
                        : 'bg-stone-900/30 text-stone-400'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className="w-4 font-bold text-amber-400">#{u.rank}</span>
                      <span className="font-serif">{u.name}</span>
                      {u.title && (
                        <span className="text-[9px] px-1 rounded bg-stone-800 text-amber-300">
                          {u.title}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-4">
                      <span>{u.rating} Elo</span>
                      <span className="text-amber-300 font-bold">{u.weeklyXp.toLocaleString()} XP</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TAB 3: CLANS & GUILDS */}
          {activeTab === 'clans' && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                {POPULAR_CLAN_CLUBS.map((clan) => (
                  <div
                    key={clan.id}
                    className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 hover:border-amber-600/50 transition-all space-y-2 flex flex-col justify-between"
                  >
                    <div>
                      <div className="flex items-center justify-between">
                        <span className="text-2xl">{clan.bannerEmblem}</span>
                        <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-amber-950 border border-amber-600/50 text-amber-300 font-bold">
                          [{clan.tag}] #{clan.weeklyRank}
                        </span>
                      </div>
                      <h4 className="text-sm font-serif font-bold text-amber-100 mt-2">
                        {clan.name}
                      </h4>
                      <p className="text-stone-400 text-xs font-serif leading-relaxed italic mt-1">
                        "{clan.motto}"
                      </p>
                    </div>

                    <div className="pt-2 border-t border-stone-800 flex items-center justify-between font-mono text-[11px] text-stone-400">
                      <span>{clan.memberCount} Knights</span>
                      <span className="text-amber-300 font-bold">{clan.totalXp.toLocaleString()} XP</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TAB 4: TITLED STREAMERS */}
          {activeTab === 'streams' && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                {TITLED_STREAMERS.map((st) => (
                  <div
                    key={st.id}
                    className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 hover:border-amber-600/50 transition-all space-y-2.5 flex flex-col justify-between"
                  >
                    <div>
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-1.5">
                          <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-amber-950 border border-amber-600/50 text-amber-300 font-bold">
                            {st.titleBadge}
                          </span>
                          <span className="font-serif font-bold text-stone-200">{st.streamerName}</span>
                        </div>
                        <span className="text-[10px] font-mono text-red-400 flex items-center gap-1">
                          <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                          {st.viewerCount.toLocaleString()}
                        </span>
                      </div>
                      <p className="text-xs text-stone-300 font-serif leading-snug line-clamp-2 mt-1">
                        {st.streamTitle}
                      </p>
                    </div>

                    <a
                      href={st.channelUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="py-1.5 px-3 rounded-lg bg-stone-800 hover:bg-stone-700 border border-stone-600 text-stone-200 font-serif text-xs flex items-center justify-center gap-1.5 transition-all"
                    >
                      <span>Watch Stream on {st.platform}</span>
                      <ExternalLink className="w-3.5 h-3.5 text-amber-400" />
                    </a>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TAB 5: MATCH EMOTES & SFX */}
          {activeTab === 'emotes' && (
            <div className="space-y-4">
              <p className="text-xs text-stone-400 font-serif">
                Select an animated medieval taunt or greeting to broadcast with audio to your opponent:
              </p>
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                {MEDIEVAL_MATCH_EMOTES.map((em) => (
                  <button
                    key={em.id}
                    type="button"
                    onClick={() => handlePlayEmote(em)}
                    className="p-3.5 rounded-xl bg-stone-900/70 hover:bg-amber-950/40 border border-stone-800 hover:border-amber-500/60 transition-all text-center space-y-1 group transform active:scale-95"
                  >
                    <div className="text-3xl group-hover:scale-110 transition-transform">{em.icon}</div>
                    <div className="text-xs font-serif font-bold text-stone-200 group-hover:text-amber-300">
                      {em.name}
                    </div>
                    <div className="text-[10px] text-stone-500 italic font-serif">
                      "{em.soundLabel}"
                    </div>
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
