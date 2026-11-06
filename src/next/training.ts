export interface Exercise {
  id: string;
  title: string;
  subtitle: string;
  fen: string;
  line: string[];
  explanation: string;
  theme: string;
}
export const LESSONS: Exercise[] = [
  {
    id: "pawn",
    title: "Your first move",
    subtitle:
      "A pawn may advance two squares from its starting rank. Move the e-pawn to e4.",
    fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    line: ["e4"],
    explanation:
      "e4 places a pawn in the center and opens a diagonal for your bishop. Pawns move forward, but capture diagonally.",
    theme: "The fundamentals",
  },
  {
    id: "knight",
    title: "Meet the knight",
    subtitle: "Knights jump in an L shape. Develop your g1 knight to f3.",
    fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    line: ["Nf3"],
    explanation:
      "The knight jumps over your pawns. From f3 it attacks the central squares d4 and e5.",
    theme: "Piece movement",
  },
  {
    id: "bishop",
    title: "Open a diagonal",
    subtitle: "Bishops travel diagonally. Develop your f1 bishop to c4.",
    fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
    line: ["Bc4"],
    explanation:
      "Bc4 develops a piece and points toward f7. Bishops always stay on the color of square where they started.",
    theme: "Development",
  },
  {
    id: "castle",
    title: "A safer king",
    subtitle:
      "Castle kingside: move the king from e1 to g1. The rook moves with it.",
    fen: "r3k2r/ppp2ppp/8/8/8/8/PPP2PPP/R3K2R w KQkq - 0 1",
    line: ["O-O"],
    explanation:
      "Castling moves the king two squares and the rook to f1. Neither may have moved before, the path must be empty, and the king cannot be in check or cross an attacked square.",
    theme: "Special moves",
  },
  {
    id: "pin",
    title: "An absolute pin",
    subtitle: "Move your rook to e1 to pin the e7 knight to its king.",
    fen: "4k3/4n3/8/8/8/8/8/3R2K1 w - - 0 1",
    line: ["Re1"],
    explanation:
      "The knight cannot move: leaving the e-file would expose its own king to check. That makes this an absolute pin.",
    theme: "Tactics",
  },
  {
    id: "enpassant",
    title: "En passant",
    subtitle: "Black just moved d7–d5. Capture that pawn by moving e5 to d6.",
    fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
    line: ["exd6"],
    explanation:
      "En passant is available only immediately after the opposing pawn advances two squares alongside yours. Your pawn captures as if it had moved one square.",
    theme: "Special moves",
  },
];
export const PUZZLES: Exercise[] = [
  {
    id: "backrank",
    title: "The last rank",
    subtitle: "White to move. Find checkmate in one.",
    fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1",
    line: ["Re8#"],
    explanation:
      "Re8 is checkmate. The rook controls the eighth rank while Black’s own pawns block the king’s escape.",
    theme: "Back-rank mate",
  },
  {
    id: "fork",
    title: "One knight, two targets",
    subtitle: "White to move. Check the king, then win the rook.",
    fen: "3r3k/6pp/8/4N3/8/8/8/4K3 w - - 0 1",
    line: ["Nf7+", "Kg8", "Nxd8"],
    explanation:
      "Nf7 checks the king on h8 and attacks the rook on d8. After the forced Kg8, Nxd8 wins the rook.",
    theme: "Knight fork",
  },
  {
    id: "queenmate",
    title: "Royal coordination",
    subtitle: "White to move. Use your king and queen to deliver mate.",
    fen: "7k/8/5KQ1/8/8/8/8/8 w - - 0 1",
    line: ["Qg7#"],
    explanation:
      "The queen closes every escape square. The white king protects her, so Black cannot capture on g7.",
    theme: "Queen and king",
  },
  {
    id: "smothered",
    title: "Nowhere to go",
    subtitle: "White to move. Find a smothered checkmate.",
    fen: "6rk/6pp/8/4N3/8/8/8/4K3 w - - 0 1",
    line: ["Nf7#"],
    explanation:
      "Nf7 checks the king on h8. Black’s rook and pawns occupy every escape square, and a knight’s check cannot be blocked.",
    theme: "Smothered mate",
  },
];
