/** Original ink drawings: Staunton silhouettes with the models' family traits. */
import { writeFileSync } from "node:fs";
import {
  LEGION_PALETTES,
  PIECE_SILHOUETTES,
  hex,
} from "../src/game/legionIdentity";
import type { Army } from "../src/game/battleProfiles";
import type { PieceSymbol, PieceColor } from "../src/game/types";

function drawing(role: PieceSymbol, side: PieceColor, army: Army) {
  const p = LEGION_PALETTES[army][side],
    A = hex(p.armor),
    C = hex(p.cloth),
    T = hex(p.trim),
    D = hex(p.dark),
    I = hex(p.ink),
    F = hex(army === "skeletons" ? p.bone : p.face),
    G = hex(p.gem),
    S = hex(p.steel);
  const path = (d: string, fill = A, width = 2.8, extra = "") =>
    `<path d="${d}" fill="${fill}" stroke="${I}" stroke-width="${width}" stroke-linejoin="round" stroke-linecap="round" ${extra}/>`;
  const line = (d: string, color = I, w = 2) =>
    `<path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
  const circle = (x: number, y: number, r: number, fill: string, w = 2) =>
    `<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}" stroke="${I}" stroke-width="${w}"/>`;
  const jewel = (x: number, y: number) =>
    path(`M${x} ${y - 4}l3 4-3 5-3-5Z`, G, 1.2);
  const face = (y: number) =>
    army === "skeletons"
      ? `${path(`M52 ${y - 7}Q64 ${y - 16} 76 ${y - 7}L75 ${y + 3} 70 ${y + 7} 70 ${y + 13} 58 ${y + 13} 58 ${y + 7} 53 ${y + 3}Z`, F, 2)}${circle(58, y, 3, D, 0)}${circle(70, y, 3, D, 0)}${path(`M64 ${y + 3}l-2 4h4Z`, D, 0)}${line(`M60 ${y + 9}v4m4-4v4m4-4v4`, D, 1.3)}`
      : `${army === "elves" ? path(`M51 ${y - 4}L40 ${y - 12} 48 ${y + 2} 55 ${y + 5}M77 ${y - 4}L88 ${y - 12} 80 ${y + 2} 73 ${y + 5}`, F, 2) : ""}${path(`M52 ${y - 8}Q64 ${y - 15} 76 ${y - 8}L75 ${y + 5} 64 ${y + 14} 53 ${y + 5}Z`, F, 2)}${army === "royal" ? path(`M51 ${y - 7}Q64 ${y - 17} 77 ${y - 7}L77 ${y + 1} 51 ${y + 1}Z`, A, 2) : line(`M52 ${y - 9}Q64 ${y - 20} 76 ${y - 9}`, T, 4)}${line(`M56 ${y}h5m6 0h5`, D, 1.8)}${line(`M61 ${y + 8}q3 2 6 0`, D, 1.2)}`;
  const emblem = (y: number) =>
    army === "elves"
      ? `${path(`M64 ${y - 7}Q80 ${y} 64 ${y + 9}Q48 ${y} 64 ${y - 7}Z`, T, 1.5)}${line(`M64 ${y - 3}v8`, D, 1.2)}`
      : army === "skeletons"
        ? `${circle(64, y, 5, F, 1.2)}${circle(62, y, 1.1, D, 0)}${circle(66, y, 1.1, D, 0)}${line(`M62 ${y + 5}h4`, D, 1.5)}`
        : jewel(64, y);
  const base = `${path("M39 108Q64 102 89 108L95 115Q64 124 33 115Z", A, 3)}${path("M34 115Q64 120 94 115L99 122H29Z", T, 2.5)}${line("M41 110Q58 107 73 109", side === "w" ? "#ffffff" : S, 1.5)}`;
  const robe = (top: number) =>
    `${path(`M52 ${top}Q43 ${top + 12} 47 87Q46 99 37 108Q64 116 91 108Q80 97 81 87Q85 ${top + 12} 76 ${top}Z`, C)}${path(`M55 ${top}L64 ${top + 15} 73 ${top} 75 100Q64 105 53 100Z`, A, 1.8)}${line(`M47 99l-3 6m36-6 4 6`, T, 2.6)}${emblem(top + 24)}`;
  let art = "";
  if (role === "p") {
    art = `${path("M50 68Q45 79 49 89L42 107Q64 113 86 107L79 89Q83 79 78 68Z", A)}${path("M47 73Q64 80 81 73L78 90Q64 96 50 90Z", C, 2)}${face(55)}${army === "royal" ? circle(64, 39, 4, T, 1.8) : army === "elves" ? path("M64 36Q76 41 70 46L64 44 58 46Q52 41 64 36Z", T, 1.5) : line("M51 46Q64 38 77 46", T, 3)}${path("M45 78l-12-3-1 22 13 4 6-9Z", A, 2)}${line("M40 82v11", T, 2)}${path(army === "skeletons" ? "M89 83l-5-7 8-9 9 3-4 11Z" : army === "elves" ? "M91 73l8-18-2 23-7 12Z" : "M90 81V60l5-10 3 10-4 22Z", S, 2)}${line("M91 82l-2 18", T, 3)}${emblem(83)}`;
  } else if (role === "n") {
    art = `${path("M41 105Q50 92 44 78L36 77 26 66 36 46 42 33 44 18 55 32 63 20 69 35Q87 43 91 65Q89 86 90 108Q64 116 41 105Z", A, 3.3)}${path("M65 34Q86 45 86 64L79 87 84 102 65 106 56 91Q70 73 65 57L55 48Z", C, 2)}${army === "skeletons" ? `${path("M36 47Q44 40 55 43L59 56 52 68 36 73 28 65Z", F, 2)}${path("M42 47l9-1-1 9-9 2Z", D, 1.3)}${line("M32 64l17 2m-13-4-1 6m6-6-1 6", D, 1.5)}${line("M69 57l13 7m-14 3 12 7m-14 3 10 7", S, 2.5)}` : `${circle(47, 51, 3, D, 0)}${line("M31 65l10 2m-2 6 12-2", D, 1.8)}${path("M39 38l11-4 18 5-6 12-12-7-14 4Z", T, 1.8)}`}${line("M58 38Q75 51 73 69", T, 3)}${army === "elves" ? path("M77 65Q96 72 81 86Q67 78 77 65Z", T, 1.8) : jewel(76, 73)}${line("M46 95l-2 9m8-5-2 7", S, 1.3)}`;
  } else if (role === "r") {
    art = `${path("M42 52L40 99 35 108Q64 115 93 108L88 99 86 52Z", A, 3)}${path("M35 23H48V33H57V23H71V33H80V23H93V50L86 57H42L35 50Z", A, 3.3)}${path("M39 47H89V56H39Z", T, 2)}${face(69)}${path("M45 85L64 80 83 85 80 103 64 111 48 103Z", C, 2)}${emblem(96)}${army === "elves" ? `${path("M94 61Q117 80 94 103Q106 81 94 61Z", T, 2)}${line("M95 64v37", S, 1.2)}` : army === "skeletons" ? `${path("M94 65l12 3-3 15-11-3Z", S, 2)}${line("M97 78l-4 28", T, 3)}` : line("M29 81l8-8m-10 0 8 8M33 78v27", T, 4)}`;
  } else {
    const fy = role === "b" ? 58 : role === "q" ? 56 : 62;
    art = robe(fy + 12) + face(fy);
    if (role === "b")
      art += `${path("M48 47Q45 33 64 12Q83 33 80 47L74 51H54Z", A, 3.1)}${line("M67 22l-9 17", D, 4)}${path("M50 46H78V53H50Z", T, 2)}${line("M94 52v53", T, 3)}${army === "elves" ? path("M99 33Q83 23 87 42Q91 49 98 44Q87 45 92 35Z", G, 2) : army === "skeletons" ? `${circle(94, 39, 7, F, 1.8)}${circle(92, 38, 1.5, D, 0)}${circle(97, 38, 1.5, D, 0)}` : `${circle(94, 39, 7, T, 1.7)}${line("M94 26v5m0 16v5m-13-13h5m16 0h5", T, 2.5)}`}`;
    if (role === "q")
      art += `${path("M44 44L37 22 52 30 53 14 64 29 75 14 76 30 91 22 84 44Z", T, 3.1)}${[37, 53, 75, 91].map((x, i) => circle(x, [20, 12, 12, 20][i], 2.6, G, 1.2)).join("")}${circle(64, 24, 2.5, G, 1.2)}${path("M45 41H83V48H45Z", A, 2)}${jewel(64, 44)}${army === "skeletons" ? `${line("M96 57v49", T, 3)}${path("M95 56Q116 58 110 77Q105 66 95 65Z", S, 2)}` : army === "elves" ? `${path("M91 69l12-18-6 29-5 13Z", S, 2)}${line("M92 86l-4 17", T, 3)}` : `${circle(93, 79, 7, G, 2)}${line("M34 77v23", S, 4)}`}`;
    if (role === "k")
      art += `${path("M60 8H68V18H78V25H68V38H60V25H50V18H60Z", T, 2.7)}${path("M45 37L50 31 57 40 64 32 71 40 78 31 83 37 80 49H48Z", T, 2.7)}${path("M48 46H80V53H48Z", A, 2)}${jewel(64, 49)}${path(army === "elves" ? "M93 55Q106 70 97 86L93 94 89 86Q84 70 93 55Z" : "M92 59L97 69V91H88V69Z", S, 2)}${line("M83 93h18m-9 0v12", T, 3)}`;
  }
  return `<svg x="0" y="0" width="192" height="192" viewBox="0 0 128 128" data-army="${army}" data-side="${side}" data-role="${role}" data-silhouette="${PIECE_SILHOUETTES[role]}"><g>${art}${base}</g></svg>`;
}
const roles: PieceSymbol[] = ["p", "n", "b", "r", "q", "k"];
let row = 0,
  body = "";
for (const army of ["royal", "elves", "skeletons"] as Army[])
  for (const side of ["w", "b"] as PieceColor[]) {
    for (const [col, role] of roles.entries())
      body += `<g transform="translate(${col * 192} ${row * 192})">${drawing(role, side, army)}</g>`;
    row++;
  }
writeFileSync(
  "public/pieces/legions-drawn.svg",
  `<svg xmlns="http://www.w3.org/2000/svg" width="1152" height="1152" viewBox="0 0 1152 1152">${body}</svg>`,
);
console.log("36 original legion drawings generated.");
