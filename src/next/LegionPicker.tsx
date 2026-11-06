import React from "react";
import { Check } from "lucide-react";
import { Piece } from "./Piece";
import { SETS } from "./ui";
import type { PieceSet } from "./contracts";

export function LegionPicker({
  value,
  confirmed = true,
  disabled = false,
  onChange,
}: {
  value: PieceSet;
  confirmed?: boolean;
  disabled?: boolean;
  onChange: (army: PieceSet) => void;
}) {
  return (
    <fieldset className="legion-picker" disabled={disabled}>
      <legend>Choose your legion</legend>
      <div className="legion-choices" role="group" aria-label="Your legion">
        {SETS.map((set) => (
          <button
            type="button"
            key={set.id}
            aria-label={`Choose ${set.name}`}
            aria-pressed={confirmed && value === set.id}
            className={
              confirmed && value === set.id
                ? "legion-choice chosen"
                : "legion-choice"
            }
            onClick={() => onChange(set.id)}
          >
            <span className="legion-portrait">
              <Piece type="k" color="w" set={set.id} />
              <Piece type="n" color="b" set={set.id} />
            </span>
            <strong>{set.name}</strong>
            {confirmed && value === set.id && (
              <Check className="legion-check" size={14} />
            )}
          </button>
        ))}
      </div>
      <p>
        {confirmed
          ? `${SETS.find((s) => s.id === value)?.name} · Same chess rules. White’s legion hosts the castle.`
          : "Pick a legion to begin. Appearance changes; chess rules stay the same."}
      </p>
    </fieldset>
  );
}
