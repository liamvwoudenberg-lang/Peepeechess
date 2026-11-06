import type { Army } from "./battleProfiles";
import type { PieceColor, PieceSymbol } from "./types";

// The drawn pieces and the articulated models share these family traits.
export const PIECE_SILHOUETTES: Record<PieceSymbol, string> = {
  p: "round-pawn",
  n: "horse-knight",
  b: "split-mitre",
  r: "battlements",
  q: "five-point-crown",
  k: "royal-cross",
};
export interface LegionPalette {
  armor: number;
  cloth: number;
  trim: number;
  steel: number;
  bone: number;
  face: number;
  dark: number;
  gem: number;
  ink: number;
}
export const LEGION_PALETTES = Object.fromEntries(
  (["royal", "elves", "skeletons"] as Army[]).map((army) => [
    army,
    {
      w: {
        armor: 0xfffbef,
        cloth: 0xf2efdf,
        trim: army === "elves" ? 0x7d956f : 0xb78a3d,
        steel: 0xdbe6ec,
        bone: 0xf4e9cf,
        face: 0xe8ceb0,
        dark: 0x25313e,
        gem: 0x9adbc5,
        ink: 0x29313d,
      },
      b: {
        armor: 0x191622,
        cloth: army === "elves" ? 0x382047 : 0x4f142d,
        trim: army === "elves" ? 0xa88ac4 : 0xbc6883,
        steel: 0x91a1b4,
        bone: 0xa79aaf,
        face: 0x9b7a9e,
        dark: 0x0c0e16,
        gem: 0xce88e6,
        ink: 0xebd9e9,
      },
    },
  ]),
) as Record<Army, Record<PieceColor, LegionPalette>>;
// Midtone squares keep both ivory and obsidian silhouettes clear.
export const BOARD_PALETTES = {
  citadel: { light: 0x81909f, dark: 0x586e81 },
  silverwood: { light: 0x7f9391, dark: 0x567678 },
  ossuary: { light: 0x8c8999, dark: 0x6b657f },
} as const;
export const hex = (value: number) => "#" + value.toString(16).padStart(6, "0");
