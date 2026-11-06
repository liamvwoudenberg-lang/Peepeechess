// Development-only fixture. It is not an entry point in the production bundle.
import React, { useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Chess, type Square, type Color } from "chess.js";
import { Board } from "../../src/next/Board";
import type { PieceSet, Ply } from "../../src/next/contracts";
import "../../src/index.css";
interface State {
  fen: string;
  lastMove?: Ply;
  serial: number;
  orientation: Color;
  armies: { w: PieceSet; b: PieceSet };
  mode: "off" | "brief" | "cinematic";
  competitive: boolean;
  lightweight: boolean;
  reducedMotion: boolean;
  sound: boolean;
}
function Harness() {
  const [state, setState] = useState<State>({
      fen: new Chess().fen(),
      serial: 0,
      orientation: "w",
      armies: { w: "royal", b: "skeletons" },
      mode: "cinematic",
      competitive: false,
      lightweight: false,
      reducedMotion: false,
      sound: false,
    }),
    [selected, setSelected] = useState<Square | null>(null),
    current = useRef(state);
  current.current = state;
  const move = (from: Square, to: Square, promotion = "q") => {
    const s = current.current,
      c = new Chess(s.fen),
      m = c.move({ from, to, promotion });
    setState({
      ...s,
      fen: c.fen(),
      lastMove: { from, to, promotion, san: m.san, fen: c.fen() },
    });
    setSelected(null);
    return c.fen();
  };
  (window as any).battleQA = {
    reset: (options: Partial<State>) => {
      const next = {
        ...current.current,
        ...options,
        lastMove: undefined,
        serial: current.current.serial + 1,
      };
      setSelected(null);
      setState(next);
      return next.serial;
    },
    move,
    mute: (enabled: boolean) =>
      setState({ ...current.current, sound: enabled }),
  };
  const c = new Chess(state.fen),
    legal = selected
      ? c.moves({ square: selected, verbose: true }).map((m) => m.to)
      : [];
  return (
    <main
      className={`qa-harness ${state.lightweight ? "efficient" : ""}`}
      style={{ width: "min(640px,100vw)", margin: "20px auto" }}
    >
      <p style={{ padding: 8 }}>
        2D capture verification · {state.armies.w} / {state.armies.b}
      </p>
      <div data-qa-fen={state.fen} data-qa-serial={state.serial}>
        <Board
          key={state.serial}
          fen={state.fen}
          orientation={state.orientation}
          pieceSet={state.armies.w}
          armies={state.armies}
          animationMode={state.mode}
          competitive={state.competitive}
          lightweight={state.lightweight}
          reducedMotion={state.reducedMotion}
          sound={state.sound}
          selected={selected}
          legal={legal}
          onSelect={(sq) => {
            if (selected && legal.includes(sq)) {
              move(selected, sq);
              return;
            }
            setSelected(sq);
          }}
          onMove={move}
          playerColor={c.turn()}
          interactive
          coordinates
          lastMove={state.lastMove}
        />
      </div>
    </main>
  );
}
createRoot(document.getElementById("qa-root")!).render(<Harness />);
