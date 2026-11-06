import React, { memo } from "react";
import type { PieceSymbol, Color } from "chess.js";
import type { PieceSet } from "./contracts";
// Original ink drawings share role silhouettes and livery with the 3D models.
// Old phones display the same miniatures without creating a WebGL context.
export const Piece = memo(function Piece({
  type,
  color,
  set = "royal",
  decorative = false,
  unarmed = false,
}: {
  type: PieceSymbol;
  color: Color;
  set?: PieceSet;
  decorative?: boolean;
  unarmed?: boolean;
}) {
  const col = ["p", "n", "b", "r", "q", "k"].indexOf(type),
    row =
      ["royal", "elves", "skeletons"].indexOf(set) * 2 +
      (color === "b" ? 1 : 0);
  return (
    <span
      className={`chess-piece miniature-icon ${unarmed ? "battle-body" : ""} side-${color} set-${set}`}
      data-piece={`${color}${type}`}
      aria-hidden="true"
      style={{ backgroundPosition: `${col * 20}% ${row * 20}%` }}
    />
  );
});
