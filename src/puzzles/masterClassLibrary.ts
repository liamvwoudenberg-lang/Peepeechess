import { MasterClassLesson } from '../types/chess';

export const MASTER_CLASS_LESSONS: MasterClassLesson[] = [
  {
    id: 'lesson_italian_vanguard',
    title: 'The Italian Game: Commanding the Royal Vanguard',
    category: 'openings',
    difficulty: 'Squire',
    summary: 'Master the classical Italian development, placing the runic bishop onto c4 to exert direct pressure on the vulnerable f7 monarch flank.',
    steps: [
      {
        fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
        instruction: 'Develop your light-squared Bishop to the active c4 outpost.',
        hint: 'Aim at the weak f7 square.',
        targetMoveSan: 'Bc4',
        explanationOnSuccess: 'Bc4 activates your bishop on the most aggressive diagonal targeting the uncastled sovereign.',
      },
      {
        fen: 'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
        instruction: 'Castle your sovereign kingside to tuck your monarch safely into the bastion tower.',
        hint: 'Move your king two squares towards the h1 rook.',
        targetMoveSan: 'O-O',
        explanationOnSuccess: 'Castling secures king safety and mobilizes the rook to contest the central open file.',
      },
    ],
  },
  {
    id: 'lesson_lucena_bridge',
    title: 'Endgame Mastery: The Lucena Bridge',
    category: 'endgame',
    difficulty: 'Paladin',
    summary: 'The fundamental theoretical technique to win Rook + Pawn endgames with a pawn on the 7th rank.',
    steps: [
      {
        fen: '1K1k4/1P6/8/8/8/8/5r2/2R5 w - - 0 1',
        instruction: 'Construct the bridge! Lift your Bastion Warden (Rook) to the 4th rank.',
        hint: 'Move the rook to c4 to later shield your king from checks.',
        targetMoveSan: 'Rc4',
        explanationOnSuccess: 'Rc4 establishes the bridge barrier along the 4th rank to intercept opposing rook checks.',
      },
      {
        fen: '1K1k4/1P6/8/8/2R5/8/1r6/8 w - - 2 2',
        instruction: 'Step your Monarch out of the promotion square to unblock the pawn.',
        hint: 'Move king to a7.',
        targetMoveSan: 'Ka7',
        explanationOnSuccess: 'The monarch steps aside; the incoming checks will be safely intercepted by your rook on c4.',
      },
    ],
  },
  {
    id: 'lesson_pin_skewer_motifs',
    title: 'Tactical Weaponry: Pins & Skewers',
    category: 'middlegame',
    difficulty: 'Knight',
    summary: 'Harness geometric alignments across open ranks and diagonals to paralyze opponent forces.',
    steps: [
      {
        fen: 'r1b1k2r/pppp1ppp/8/4q3/2B1n3/8/PPP2PPP/RNBQK2R w KQkq - 0 8',
        instruction: 'Execute an absolute pin on the central open file.',
        hint: 'Move queen to e2.',
        targetMoveSan: 'Qe2',
        explanationOnSuccess: 'The knight on e4 is paralyzed—it cannot move because doing so exposes the black king to check.',
      },
    ],
  },
];
