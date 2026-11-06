import { RatedPuzzle } from '../types/chess';

export const CURATED_RATED_PUZZLES: RatedPuzzle[] = [
  // 1. Knight Fork - 950 Elo
  {
    id: 'puz_fork_1',
    title: 'The Cavalier Citadel Fork',
    motif: 'fork',
    rating: 950,
    sideToMove: 'w',
    fen: 'r1bqk2r/pppp1ppp/2n5/4p3/2B1n3/2P2N2/PPP2PPP/R1BQK2R w KQkq - 0 7',
    solutionMoves: ['Qd5'], // Threatens Qxf7# and Qxe4
    description: 'White Queen strikes d5, creating an unstoppable dual assault on f7 mate and the unprotected Knight on e4.',
  },
  // 2. Absolute Pin - 1100 Elo
  {
    id: 'puz_pin_1',
    title: 'The Palisade Absolute Pin',
    motif: 'pin',
    rating: 1100,
    sideToMove: 'w',
    fen: 'r1b1k2r/pppp1ppp/8/4q3/2B1n3/8/PPP2PPP/RNBQK2R w KQkq - 0 8',
    solutionMoves: ['Qe2'], // Absolute pin of Knight to King on open e-file
    description: 'Pin the enemy cavalier on e4 against the black monarch along the central e-file.',
  },
  // 3. Back Rank Mate - 1200 Elo
  {
    id: 'puz_backrank_1',
    title: 'Bastion Corridor Breach',
    motif: 'back_rank_mate',
    rating: 1200,
    sideToMove: 'w',
    fen: '3r2k1/5ppp/8/8/8/8/4RPPP/6K1 w - - 0 1',
    solutionMoves: ['Re8+', 'Rxe8'], // or Re1 -> Re8#
    description: 'The opposing monarch is trapped behind their own foot soldier phalanx. Exploit the vulnerable 8th rank.',
  },
  // 4. Skewer - 1350 Elo
  {
    id: 'puz_skewer_1',
    title: 'The Runic Beam Skewer',
    motif: 'skewer',
    rating: 1350,
    sideToMove: 'w',
    fen: '4k3/8/8/8/8/8/2B5/r3K3 w - - 0 1',
    solutionMoves: ['Bd1'], // or skewer setup
    description: 'Line up high-value royal targets along long open diagonals.',
  },
  // 5. Smothered Mate - 1500 Elo
  {
    id: 'puz_smothered_1',
    title: 'Philidor’s Boxed Monarch',
    motif: 'smothered_mate',
    rating: 1500,
    sideToMove: 'w',
    fen: '6k1/5ppp/8/8/8/8/4N1PP/5QK1 w - - 0 1',
    solutionMoves: ['Qf7+'],
    description: 'Box the opposing sovereign into the corner and seal their fate with a knight leap.',
  },
  // 6. Deflection - 1650 Elo
  {
    id: 'puz_deflection_1',
    title: 'The Gatekeeper Decoy',
    motif: 'deflection',
    rating: 1650,
    sideToMove: 'w',
    fen: '5rk1/5ppp/8/8/3B4/8/1Q3PPP/5RK1 w - - 0 1',
    solutionMoves: ['Bxg7'],
    description: 'Deflect the key defender away from protecting the critical citadel square.',
  },
  // 7. Lucena Bridge - 1800 Elo
  {
    id: 'puz_lucena_1',
    title: 'The Lucena Bastion Bridge',
    motif: 'lucena_endgame',
    rating: 1800,
    sideToMove: 'w',
    fen: '1K1k4/1P6/8/8/8/8/5r2/2R5 w - - 0 1',
    solutionMoves: ['Rc4'], // Standard building the bridge
    description: 'Construct the classic 4th-rank rook bridge to shelter the advancing monarch and promote the pawn.',
  },
  // 8. Opposition King Endgame - 1950 Elo
  {
    id: 'puz_opposition_1',
    title: 'Direct Sovereign Opposition',
    motif: 'opposition',
    rating: 1950,
    sideToMove: 'w',
    fen: '8/8/8/4k3/8/4K3/4P3/8 w - - 0 1',
    solutionMoves: ['Kd3'], // Gaining the opposition
    description: 'Out-flank the opposing monarch by maintaining distant and direct opposition.',
  },
];
