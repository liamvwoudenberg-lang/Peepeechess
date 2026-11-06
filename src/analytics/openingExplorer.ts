import { ECOOpening, OpeningExplorerData, OpeningMoveStat } from '../types/chess';

export const POPULAR_ECO_OPENINGS: ECOOpening[] = [
  {
    eco: 'B20',
    name: 'Sicilian Defense',
    movesSan: ['e4', 'c5'],
    fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
  },
  {
    eco: 'B90',
    name: 'Sicilian Defense: Najdorf Variation',
    movesSan: ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6'],
    fen: 'rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 6',
  },
  {
    eco: 'C50',
    name: 'Italian Game (Giuoco Piano)',
    movesSan: ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4'],
    fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
  },
  {
    eco: 'C60',
    name: 'Ruy Lopez (Spanish Opening)',
    movesSan: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'],
    fen: 'r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
  },
  {
    eco: 'D06',
    name: "Queen's Gambit",
    movesSan: ['d4', 'd5', 'c4'],
    fen: 'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq c3 0 2',
  },
  {
    eco: 'D30',
    name: "Queen's Gambit Declined",
    movesSan: ['d4', 'd5', 'c4', 'e6'],
    fen: 'rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3',
  },
  {
    eco: 'C00',
    name: 'French Defense',
    movesSan: ['e4', 'e6'],
    fen: 'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
  },
  {
    eco: 'B10',
    name: 'Caro-Kann Defense',
    movesSan: ['e4', 'c6'],
    fen: 'rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
  },
  {
    eco: 'E60',
    name: "King's Indian Defense",
    movesSan: ['d4', 'Nf6', 'c4', 'g6'],
    fen: 'rnbqkb1r/pppppp1p/5np1/8/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3',
  },
  {
    eco: 'A10',
    name: 'English Opening',
    movesSan: ['c4'],
    fen: 'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq c3 0 1',
  },
  {
    eco: 'D02',
    name: 'London System',
    movesSan: ['d4', 'd5', 'Nf3', 'Nf6', 'Bf4'],
    fen: 'rnbqkb1r/ppp1pppp/5n2/3p4/3P1B2/5N2/PPP1PPPP/RN1QKB1R b KQkq - 3 3',
  },
];

const MASTER_MOVE_DATA: Record<string, OpeningMoveStat[]> = {
  // Initial board moves
  'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1': [
    { san: 'e4', uci: 'e2e4', masterGamesCount: 428000, whiteWinRate: 38, drawRate: 33, blackWinRate: 29, averageRating: 2540, userGamesCount: 142, userWinRate: 54 },
    { san: 'd4', uci: 'd2d4', masterGamesCount: 362000, whiteWinRate: 39, drawRate: 34, blackWinRate: 27, averageRating: 2555, userGamesCount: 88, userWinRate: 58 },
    { san: 'Nf3', uci: 'g1f3', masterGamesCount: 94000, whiteWinRate: 37, drawRate: 36, blackWinRate: 27, averageRating: 2530, userGamesCount: 22, userWinRate: 50 },
    { san: 'c4', uci: 'c2c4', masterGamesCount: 82000, whiteWinRate: 37, drawRate: 35, blackWinRate: 28, averageRating: 2538, userGamesCount: 18, userWinRate: 55 },
  ],
  // After 1. e4
  'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1': [
    { san: 'c5', uci: 'c7c5', masterGamesCount: 198000, whiteWinRate: 37, drawRate: 32, blackWinRate: 31, averageRating: 2560, userGamesCount: 65, userWinRate: 52 },
    { san: 'e5', uci: 'e7e5', masterGamesCount: 112000, whiteWinRate: 39, drawRate: 33, blackWinRate: 28, averageRating: 2542, userGamesCount: 48, userWinRate: 56 },
    { san: 'e6', uci: 'e7e6', masterGamesCount: 52000, whiteWinRate: 40, drawRate: 33, blackWinRate: 27, averageRating: 2535, userGamesCount: 19, userWinRate: 47 },
    { san: 'c6', uci: 'c7c6', masterGamesCount: 39000, whiteWinRate: 38, drawRate: 35, blackWinRate: 27, averageRating: 2540, userGamesCount: 14, userWinRate: 50 },
  ],
  // After 1. d4
  'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1': [
    { san: 'Nf6', uci: 'g8f6', masterGamesCount: 174000, whiteWinRate: 36, drawRate: 37, blackWinRate: 27, averageRating: 2562, userGamesCount: 52, userWinRate: 53 },
    { san: 'd5', uci: 'd7d5', masterGamesCount: 132000, whiteWinRate: 39, drawRate: 35, blackWinRate: 26, averageRating: 2548, userGamesCount: 38, userWinRate: 61 },
    { san: 'e6', uci: 'e7e6', masterGamesCount: 26000, whiteWinRate: 38, drawRate: 35, blackWinRate: 27, averageRating: 2530, userGamesCount: 11, userWinRate: 45 },
  ],
};

export function getOpeningExplorerData(currentFen: string, movesHistorySan: string[] = []): OpeningExplorerData {
  // Normalize FEN to board + turn position
  const fenParts = currentFen.split(' ');
  const positionKey = `${fenParts[0]} ${fenParts[1]} ${fenParts[2]} ${fenParts[3]} 0 1`;

  // Look for matching ECO Opening by moves prefix
  const matchedOpening = [...POPULAR_ECO_OPENINGS]
    .sort((a, b) => b.movesSan.length - a.movesSan.length)
    .find((op) => {
      if (movesHistorySan.length < op.movesSan.length) return false;
      return op.movesSan.every((m, idx) => movesHistorySan[idx] === m);
    });

  const eco = matchedOpening ? matchedOpening.eco : movesHistorySan.length === 0 ? 'A00' : 'Citadel Line';
  const openingName = matchedOpening ? matchedOpening.name : movesHistorySan.length === 0 ? 'Initial Citadel Array' : 'Custom Tactical Skirmish';

  // Find candidate moves from database or generate standard candidate moves
  const moveStats = MASTER_MOVE_DATA[currentFen] || MASTER_MOVE_DATA[positionKey] || [
    { san: 'Nf3', uci: 'g1f3', masterGamesCount: 14200, whiteWinRate: 38, drawRate: 34, blackWinRate: 28, averageRating: 2520, userGamesCount: 12, userWinRate: 50 },
    { san: 'Nc3', uci: 'b1c3', masterGamesCount: 9800, whiteWinRate: 36, drawRate: 35, blackWinRate: 29, averageRating: 2510, userGamesCount: 9, userWinRate: 55 },
    { san: 'c4', uci: 'c2c4', masterGamesCount: 8400, whiteWinRate: 39, drawRate: 33, blackWinRate: 28, averageRating: 2535, userGamesCount: 8, userWinRate: 62 },
  ];

  const totalGames = moveStats.reduce((sum, m) => sum + m.masterGamesCount, 0);

  return {
    currentEco: eco,
    openingName,
    fen: currentFen,
    totalGames,
    moves: moveStats,
    notableGrandmasterGame: {
      white: 'Garry Kasparov (2812)',
      black: 'Anatoly Karpov (2750)',
      event: 'World Championship Match',
      year: 1990,
      result: '1-0',
    },
  };
}
