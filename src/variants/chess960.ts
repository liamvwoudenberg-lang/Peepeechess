/**
 * Fischer Random (Chess960) Setup Generator.
 * Strictly adheres to FIDE regulations:
 * 1. Bishops must be on opposite-colored squares.
 * 2. King must be placed on a square between the two Rooks.
 * 3. Black back rank mirrors White back rank.
 * 4. Pawns occupy standard ranks 2 and 7.
 */

export interface Chess960Setup {
  index: number;
  backRank: string[]; // 8 chars e.g. ['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R']
  fen: string;
}

export function generateChess960BackRank(seedIndex?: number): { backRank: string[]; index: number } {
  // Total 960 combinations
  const index = typeof seedIndex === 'number'
    ? Math.max(0, Math.min(959, Math.floor(seedIndex)))
    : Math.floor(Math.random() * 960);

  const rank = new Array(8).fill('');

  // 1. Light-square Bishop: squares 1, 3, 5, 7 (b1, d1, f1, h1) -> 4 possibilities
  const lightSquares = [1, 3, 5, 7];
  const b1Pos = lightSquares[index % 4];
  rank[b1Pos] = 'B';

  // 2. Dark-square Bishop: squares 0, 2, 4, 6 (a1, c1, e1, g1) -> 4 possibilities
  const darkSquares = [0, 2, 4, 6];
  const b2Pos = darkSquares[Math.floor(index / 4) % 4];
  rank[b2Pos] = 'B';

  // 3. Queen placement: 6 remaining empty squares -> 6 possibilities
  const remainingAfterBishops: number[] = [];
  for (let i = 0; i < 8; i++) {
    if (rank[i] === '') remainingAfterBishops.push(i);
  }
  const qPosIndex = Math.floor(index / 16) % 6;
  rank[remainingAfterBishops[qPosIndex]] = 'Q';

  // 4. Knight placements: 5 remaining empty squares -> 10 combinations (5 choose 2)
  const remainingAfterQueen: number[] = [];
  for (let i = 0; i < 8; i++) {
    if (rank[i] === '') remainingAfterQueen.push(i);
  }

  // 10 distinct knight pair combinations across 5 slots:
  const knightPairs = [
    [0, 1], [0, 2], [0, 3], [0, 4],
    [1, 2], [1, 3], [1, 4],
    [2, 3], [2, 4],
    [3, 4],
  ];
  const knightIndex = Math.floor(index / 96) % 10;
  const pair = knightPairs[knightIndex];
  rank[remainingAfterQueen[pair[0]]] = 'N';
  rank[remainingAfterQueen[pair[1]]] = 'N';

  // 5. Remaining 3 empty squares MUST be R - K - R (King between the two Rooks)
  const remainingForRKR: number[] = [];
  for (let i = 0; i < 8; i++) {
    if (rank[i] === '') remainingForRKR.push(i);
  }
  rank[remainingForRKR[0]] = 'R';
  rank[remainingForRKR[1]] = 'K';
  rank[remainingForRKR[2]] = 'R';

  return { backRank: rank, index };
}

export function generateChess960Fen(seedIndex?: number): Chess960Setup {
  const { backRank, index } = generateChess960BackRank(seedIndex);

  const whiteRank = backRank.join('');
  const blackRank = backRank.map((p) => p.toLowerCase()).join('');

  // Castling string in Chess960 standard
  const fen = `${blackRank}/pppppppp/8/8/8/8/PPPPPPPP/${whiteRank} w KQkq - 0 1`;

  return {
    index,
    backRank,
    fen,
  };
}
