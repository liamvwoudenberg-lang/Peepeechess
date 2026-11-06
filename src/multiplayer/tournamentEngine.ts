import { Tournament, TournamentMatch, TournamentPlayer, TournamentType } from '../types/chess';

export function createMockTournament(name = 'The Grand Citadel Open', type: TournamentType = 'arena'): Tournament {
  const initialPlayers: TournamentPlayer[] = [
    { id: 't_1', name: 'Archmage Aldric', rating: 2480, title: 'GM', score: 12, tiebreakScore: 28, streak: 4, status: 'active' },
    { id: 't_2', name: 'Lady Eleanor of York', rating: 2315, title: 'IM', score: 9, tiebreakScore: 22, streak: 2, status: 'active' },
    { id: 't_3', name: 'Sir Galahad the Iron', rating: 2260, title: 'GM', score: 8, tiebreakScore: 19, streak: 1, status: 'active' },
    { id: 't_4', name: 'Valkyrie Astrid', rating: 2140, title: 'FM', score: 6, tiebreakScore: 14, streak: 0, status: 'active' },
    { id: 't_5', name: 'Shadowblade Morvath', rating: 2025, title: 'CM', score: 5, tiebreakScore: 11, streak: 0, status: 'active' },
    { id: 't_6', name: 'Crusader Baldwin', rating: 1890, score: 3, tiebreakScore: 7, streak: 0, status: 'active' },
    { id: 't_7', name: 'You (Commander Valen)', rating: 1200, score: 2, tiebreakScore: 4, streak: 0, status: 'active' },
  ];

  const matches: TournamentMatch[] = [
    { id: 'm_1', round: 1, white: initialPlayers[0], black: initialPlayers[1], status: 'completed', result: '1-0' },
    { id: 'm_2', round: 1, white: initialPlayers[2], black: initialPlayers[3], status: 'completed', result: '1-0' },
    { id: 'm_3', round: 2, white: initialPlayers[0], black: initialPlayers[2], status: 'in_progress' },
    { id: 'm_4', round: 2, white: initialPlayers[6], black: initialPlayers[5], status: 'in_progress' },
  ];

  return {
    id: `tourn_${Date.now()}`,
    name,
    type,
    durationMinutes: 45,
    timeRemainingSec: 28 * 60 + 14,
    round: 2,
    maxRounds: 5,
    players: initialPlayers,
    matches,
    status: 'live',
  };
}

/**
 * Automates Swiss pairing for the next round.
 */
export function pairNextSwissRound(tournament: Tournament): TournamentMatch[] {
  const active = tournament.players.filter((p) => p.status === 'active');
  // Sort by score descending
  active.sort((a, b) => b.score - a.score);

  const nextMatches: TournamentMatch[] = [];
  for (let i = 0; i < active.length - 1; i += 2) {
    nextMatches.push({
      id: `match_${tournament.round + 1}_${i}`,
      round: tournament.round + 1,
      white: active[i],
      black: active[i + 1],
      status: 'pending',
    });
  }

  return nextMatches;
}
