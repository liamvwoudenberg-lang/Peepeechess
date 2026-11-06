import React, { useState } from 'react';
import {
  X,
  Trophy,
  Users,
  Swords,
  Shield,
  Globe,
  PlusCircle,
  LogIn,
  AlertCircle,
  Loader2,
  Clock,
  Sparkles,
} from 'lucide-react';
import { LeaderboardEntry } from '../game/types';

interface RankedModalProps {
  isOpen: boolean;
  onClose: () => void;
  wsConnected: boolean;
  playerName: string;
  playerRegion: string;
  playerRating: number;
  inQueue: boolean;
  createdRoomCode: string | null;
  onlineCount: number;
  queueCount: number;
  leaderboard: LeaderboardEntry[];
  serverError: string | null;
  onClearError: () => void;
  onUpdateProfile: (name: string, region: string) => void;
  onJoinQueue: (name: string, region: string, isSiegeIncrement?: boolean) => void;
  onLeaveQueue: () => void;
  onCreateRoom: (name: string) => void;
  onJoinRoom: (name: string, roomCode: string) => void;
  onStartRankedSparring: (name: string, region: string, diff: 'knight' | 'grandmaster') => void;
}

export const RankedModal: React.FC<RankedModalProps> = ({
  isOpen,
  onClose,
  wsConnected,
  playerName,
  playerRegion,
  playerRating,
  inQueue,
  createdRoomCode,
  onlineCount,
  queueCount,
  leaderboard,
  serverError,
  onClearError,
  onUpdateProfile,
  onJoinQueue,
  onLeaveQueue,
  onCreateRoom,
  onJoinRoom,
  onStartRankedSparring,
}) => {
  const [nameInput, setNameInput] = useState(playerName);
  const [regionInput, setRegionInput] = useState(playerRegion);
  const [roomCodeInput, setRoomCodeInput] = useState('');
  const [siegeIncrement, setSiegeIncrement] = useState(true);

  if (!isOpen) return null;

  const handleSaveProfile = (e: React.FormEvent) => {
    e.preventDefault();
    onUpdateProfile(nameInput.trim() || 'Commander', regionInput);
  };

  return (
    <div className="fixed inset-0 z-40 bg-black/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="w-full max-w-2xl bg-stone-950 border-2 border-amber-700/60 rounded-2xl shadow-2xl text-stone-200 overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <header className="p-4 sm:p-5 border-b border-stone-800 flex items-center justify-between bg-stone-900/60">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-950/80 border border-amber-600/60 flex items-center justify-center text-amber-400">
              <Trophy className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-lg font-serif font-bold text-amber-200">
                Citadel Ranked Arena
              </h2>
              <div className="flex items-center gap-3 text-xs text-stone-400 font-mono">
                <span className="flex items-center gap-1.5">
                  <span
                    className={`w-2 h-2 rounded-full ${
                      wsConnected ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'
                    }`}
                  />
                  {wsConnected ? 'Connected' : 'Connecting...'}
                </span>
                <span>• {onlineCount} online</span>
                <span>• {queueCount} in queue</span>
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

        {/* Server Error Warning */}
        {serverError && (
          <div className="p-3 bg-red-950/80 border-b border-red-700/60 flex items-center justify-between text-xs text-red-200">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 text-red-400" />
              <span>{serverError}</span>
            </div>
            <button
              type="button"
              onClick={onClearError}
              className="text-stone-400 hover:text-white font-mono uppercase text-[10px]"
            >
              Dismiss
            </button>
          </div>
        )}

        <div className="p-4 sm:p-6 overflow-y-auto space-y-6 flex-1">
          {/* Profile Banner */}
          <form
            onSubmit={handleSaveProfile}
            className="p-4 rounded-xl bg-stone-900/70 border border-stone-800 grid grid-cols-1 sm:grid-cols-3 gap-3 items-end"
          >
            <div>
              <label className="block text-[11px] font-mono text-stone-400 uppercase mb-1">
                Commander Callsign
              </label>
              <input
                type="text"
                value={nameInput}
                onChange={(e) => setNameInput(e.target.value)}
                maxLength={24}
                className="w-full bg-stone-950 border border-stone-700 rounded-lg px-2.5 py-1.5 text-xs text-stone-200 focus:outline-none focus:border-amber-500 font-serif"
              />
            </div>
            <div>
              <label className="block text-[11px] font-mono text-stone-400 uppercase mb-1">
                Realm / Region
              </label>
              <select
                value={regionInput}
                onChange={(e) => setRegionInput(e.target.value)}
                className="w-full bg-stone-950 border border-stone-700 rounded-lg px-2.5 py-1.5 text-xs text-stone-200 focus:outline-none focus:border-amber-500 font-serif"
              >
                <option value="EU-Citadel">EU - High Citadel</option>
                <option value="NA-Bastion">NA - Iron Bastion</option>
                <option value="ASIA-Sanctum">Asia - Runic Sanctum</option>
                <option value="GLOBAL-All">Global Realms</option>
              </select>
            </div>
            <div className="flex items-center gap-2">
              <button
                type="submit"
                className="flex-1 py-1.5 px-3 rounded-lg bg-stone-800 hover:bg-stone-700 border border-stone-600 text-xs font-mono font-medium transition-all"
              >
                Save
              </button>
              <div className="px-3 py-1.5 rounded-lg bg-amber-950/60 border border-amber-600/40 text-amber-300 font-mono font-bold text-xs text-center shrink-0">
                {playerRating} Elo
              </div>
            </div>
          </form>

          {/* Matchmaking Queue & Siege Increment Options */}
          <div className="p-4 rounded-xl bg-amber-950/20 border border-amber-700/40 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <h3 className="text-sm font-serif font-bold text-amber-200 flex items-center gap-2">
                  <Swords className="w-4 h-4 text-amber-400" />
                  Rated Citadel Duel (5+0 Rapid)
                </h3>
                <p className="text-xs text-stone-400">
                  Matches you with players worldwide or automated ranking challengers.
                </p>
              </div>

              {/* Siege Increment Toggle */}
              <label className="flex items-center gap-2 text-xs font-mono text-amber-300 cursor-pointer">
                <input
                  type="checkbox"
                  checked={siegeIncrement}
                  onChange={(e) => setSiegeIncrement(e.target.checked)}
                  className="rounded border-stone-700 text-amber-600 focus:ring-0"
                />
                <span className="flex items-center gap-1">
                  <Clock className="w-3.5 h-3.5" />
                  Siege Increment (+5s per capture)
                </span>
              </label>
            </div>

            <div className="pt-2">
              {inQueue ? (
                <div className="flex items-center justify-between p-3 rounded-xl bg-stone-900 border border-amber-500/60">
                  <div className="flex items-center gap-3">
                    <Loader2 className="w-5 h-5 text-amber-400 animate-spin" />
                    <div>
                      <div className="text-xs font-mono font-bold text-amber-300">
                        Searching for opponent...
                      </div>
                      <div className="text-[11px] text-stone-400">
                        Pairing with closest Elo or sparring sentinel
                      </div>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={onLeaveQueue}
                    className="py-1.5 px-3 rounded-lg bg-red-950 hover:bg-red-900 border border-red-700 text-xs font-mono text-red-200"
                  >
                    Cancel Queue
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <button
                    type="button"
                    onClick={() =>
                      onJoinQueue(
                        nameInput.trim() || 'Commander',
                        regionInput,
                        siegeIncrement
                      )
                    }
                    className="py-3 px-4 rounded-xl bg-gradient-to-r from-amber-600 to-amber-700 hover:from-amber-500 hover:to-amber-600 text-stone-950 font-serif font-bold text-sm shadow-lg flex items-center justify-center gap-2 transition-all transform active:scale-95"
                  >
                    <Swords className="w-4 h-4 text-stone-950" />
                    Find Ranked Match
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      onStartRankedSparring(
                        nameInput.trim() || 'Commander',
                        regionInput,
                        'knight'
                      )
                    }
                    className="py-3 px-4 rounded-xl bg-stone-900 hover:bg-stone-800 border border-amber-600/50 text-amber-200 font-serif font-medium text-sm flex items-center justify-center gap-2 transition-all"
                  >
                    <Shield className="w-4 h-4 text-amber-400" />
                    Spar with AI Sentinel
                  </button>
                </div>
              )}
            </div>
          </div>

          {/* Custom Room Creation / Join */}
          <div className="p-4 rounded-xl bg-stone-900/50 border border-stone-800 grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
            <div>
              <label className="block font-mono text-stone-400 uppercase mb-1.5">
                Host Private Citadel Room
              </label>
              {createdRoomCode ? (
                <div className="p-2.5 rounded-lg bg-amber-950/60 border border-amber-600/60 text-center font-mono">
                  <div className="text-[10px] text-amber-400 uppercase">Share Room Code</div>
                  <div className="text-base font-bold tracking-widest text-white">
                    {createdRoomCode}
                  </div>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => onCreateRoom(nameInput.trim() || 'Commander')}
                  className="w-full py-2 px-3 rounded-lg bg-stone-800 hover:bg-stone-700 border border-stone-600 text-stone-200 font-serif flex items-center justify-center gap-2"
                >
                  <PlusCircle className="w-3.5 h-3.5 text-amber-400" />
                  Generate Room Code
                </button>
              )}
            </div>

            <div>
              <label className="block font-mono text-stone-400 uppercase mb-1.5">
                Join with Room Code
              </label>
              <div className="flex gap-2">
                <input
                  type="text"
                  value={roomCodeInput}
                  onChange={(e) => setRoomCodeInput(e.target.value.toUpperCase())}
                  placeholder="e.g. 5K7Q"
                  maxLength={6}
                  className="w-full bg-stone-950 border border-stone-700 rounded-lg px-2.5 py-1.5 text-xs text-stone-200 font-mono tracking-widest uppercase focus:outline-none focus:border-amber-500"
                />
                <button
                  type="button"
                  onClick={() =>
                    onJoinRoom(nameInput.trim() || 'Commander', roomCodeInput.trim())
                  }
                  disabled={!roomCodeInput.trim()}
                  className="py-1.5 px-3 rounded-lg bg-stone-800 hover:bg-stone-700 disabled:opacity-40 border border-stone-600 text-stone-200 font-serif flex items-center gap-1 shrink-0"
                >
                  <LogIn className="w-3.5 h-3.5" />
                  Join
                </button>
              </div>
            </div>
          </div>

          {/* Citadel Global Leaderboard */}
          <div>
            <h3 className="text-xs font-mono uppercase text-amber-300 font-bold mb-2.5 flex items-center gap-1.5">
              <Trophy className="w-3.5 h-3.5 text-amber-400" />
              High Citadel Leaderboard
            </h3>
            <div className="rounded-xl border border-stone-800 overflow-hidden divide-y divide-stone-800 text-xs">
              {leaderboard.map((champ, rank) => (
                <div
                  key={champ.id}
                  className="p-2.5 bg-stone-900/40 hover:bg-stone-900/70 flex items-center justify-between gap-3"
                >
                  <div className="flex items-center gap-3">
                    <span className="font-mono font-bold text-amber-500 w-4 text-center">
                      #{rank + 1}
                    </span>
                    <div>
                      <div className="font-serif font-semibold text-stone-200 flex items-center gap-1.5">
                        <span>{champ.name}</span>
                        <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-stone-800 border border-stone-700 text-stone-400">
                          {champ.title}
                        </span>
                      </div>
                      <div className="text-[10px] text-stone-500 font-mono">
                        {champ.region} · {champ.wins}W / {champ.losses}L / {champ.draws}D
                      </div>
                    </div>
                  </div>
                  <div className="font-mono font-bold text-amber-300">{champ.rating} Elo</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
