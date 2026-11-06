import React, { memo, useEffect, useMemo, useRef, useState } from "react";
import { Chess, type Color, type Square, type PieceSymbol } from "chess.js";
import { Piece } from "./Piece";
import { PIECE_NAMES, type PieceSet, type Ply } from "./contracts";
import { captureProfile, type CaptureProfile } from "../game/battleProfiles";
import { battleAudio } from "../game/battleAudio";

interface Props {
  fen: string;
  orientation: Color;
  pieceSet: PieceSet;
  armies?: { w: PieceSet; b: PieceSet };
  arena?: string;
  animationMode?: "off" | "brief" | "cinematic";
  reducedMotion?: boolean;
  sound?: boolean;
  selected: Square | null;
  onSelect: (sq: Square) => void;
  onMove: (from: Square, to: Square) => void;
  playerColor: Color | null;
  interactive: boolean;
  legal: Square[];
  lastMove?: Ply;
  premove?: { from: Square; to: Square } | null;
  coordinates: boolean;
  hint?: { from: string; to: string } | null;
}
export const Board = memo(function Board(props: Props) {
  const {
    fen,
    orientation,
    pieceSet,
    armies = { w: pieceSet, b: pieceSet },
    arena = "citadel",
    animationMode = "brief",
    reducedMotion = false,
    sound = false,
    selected,
    onSelect,
    onMove,
    playerColor,
    interactive,
    legal,
    lastMove,
    premove,
    coordinates,
    hint,
  } = props;
  const chess = useMemo(() => new Chess(fen), [fen]);
  const previousFen = useRef<string | null>(null);
  const [visual, setVisual] = useState<{
    from: Square;
    to: Square;
    impact: Square;
    type: PieceSymbol;
    color: Color;
    captured?: PieceSymbol;
    profile: CaptureProfile | null;
    id: string;
  } | null>(null);
  useEffect(() => {
    const before = previousFen.current;
    previousFen.current = fen;
    setVisual(null);
    if (!before || before === fen || !lastMove) return;
    let move;
    try {
      const c = new Chess(before);
      move = c.move({
        from: lastMove.from,
        to: lastMove.to,
        promotion: lastMove.promotion,
      });
      if (c.fen() !== fen) return;
    } catch {
      return;
    }
    const profile = move.captured
      ? captureProfile(
          armies[move.color],
          move.piece,
          armies[move.color === "w" ? "b" : "w"],
          move.captured,
          move.color,
        )
      : null;
    let impact = move.to;
    if (move.flags.includes("e"))
      impact = `${move.to[0]}${move.color === "w" ? "5" : "4"}` as Square;
    const animated = animationMode !== "off" && !reducedMotion;
    if (animated)
      setVisual({
        from: move.from,
        to: move.to,
        impact,
        type: move.piece,
        color: move.color,
        profile,
        captured: move.captured,
        id: `${before}-${move.san}`,
      });
    const timers: ReturnType<typeof setTimeout>[] = [];
    if (sound) {
      battleAudio.setEnabled(true);
      if (profile) {
        battleAudio.windup(profile);
        timers.push(
          setTimeout(
            () => {
              battleAudio.impact(profile);
              battleAudio.defeat(profile);
            },
            animated ? 85 : 0,
          ),
        );
      } else battleAudio.step(armies[move.color], move.piece);
    }
    if (animated)
      timers.push(setTimeout(() => setVisual(null), profile ? 310 : 150));
    return () => timers.forEach(clearTimeout);
  }, [fen, armies.w, armies.b, animationMode, reducedMotion]);
  const grid = useRef<HTMLDivElement>(null);
  const pointer = useRef<{
    from: Square;
    x: number;
    y: number;
    dragging: boolean;
    piece: { type: PieceSymbol; color: Color };
  } | null>(null);
  const skipClick = useRef(false);
  const [drag, setDrag] = useState<{
    x: number;
    y: number;
    type: PieceSymbol;
    color: Color;
  } | null>(null);
  const [focus, setFocus] = useState(orientation === "w" ? 56 : 7);
  const squares = useMemo(
    () =>
      Array.from(
        { length: 64 },
        (_, i) =>
          `${"abcdefgh"[orientation === "w" ? i % 8 : 7 - (i % 8)]}${orientation === "w" ? 8 - Math.floor(i / 8) : Math.floor(i / 8) + 1}` as Square,
      ),
    [orientation],
  );
  function destination(x: number, y: number) {
    const r = grid.current!.getBoundingClientRect();
    const col = Math.floor(((x - r.left) / r.width) * 8),
      row = Math.floor(((y - r.top) / r.height) * 8);
    return col >= 0 && col < 8 && row >= 0 && row < 8
      ? squares[row * 8 + col]
      : null;
  }
  return (
    <div className={`board-frame arena-${arena} orientation-${orientation}`}>
      <div
        className="chessboard"
        ref={grid}
        role="grid"
        aria-label={`Chessboard, ${orientation === "w" ? "White" : "Black"} at bottom`}
        onPointerDownCapture={() => {
          if (sound) {
            battleAudio.setEnabled(true);
            battleAudio.unlock();
          }
        }}
        onPointerMove={(e) => {
          const p = pointer.current;
          if (!p) return;
          if (!p.dragging && Math.hypot(e.clientX - p.x, e.clientY - p.y) > 7)
            p.dragging = true;
          if (p.dragging) {
            e.preventDefault();
            setDrag({ x: e.clientX, y: e.clientY, ...p.piece });
          }
        }}
        onPointerUp={(e) => {
          const p = pointer.current;
          pointer.current = null;
          setDrag(null);
          if (p?.dragging) {
            skipClick.current = true;
            const to = destination(e.clientX, e.clientY);
            if (to && to !== p.from) onMove(p.from, to);
            setTimeout(() => (skipClick.current = false), 0);
          }
        }}
        onPointerCancel={() => {
          pointer.current = null;
          setDrag(null);
        }}
      >
        {Array.from({ length: 8 }, (_, row) => (
          <div
            role="row"
            className="board-rank"
            key={row}
            style={{ "--rank": row } as React.CSSProperties}
          >
            {squares.slice(row * 8, row * 8 + 8).map((sq, col) => {
              const i = row * 8 + col;
              const piece = chess.get(sq),
                dark = ("abcdefgh".indexOf(sq[0]) + Number(sq[1])) % 2 === 1;
              const checked =
                piece?.type === "k" &&
                piece.color === chess.turn() &&
                chess.inCheck();
              const isLegal = legal.includes(sq);
              return (
                <button
                  key={sq}
                  type="button"
                  role="gridcell"
                  data-square={sq}
                  tabIndex={i === focus ? 0 : -1}
                  aria-selected={selected === sq}
                  aria-label={`${sq}${piece ? `, ${piece.color === "w" ? "White" : "Black"} ${PIECE_NAMES[piece.type]}` : ", empty"}${isLegal ? ", legal destination" : ""}${checked ? ", in check" : ""}`}
                  className={`square ${dark ? "dark" : "light"} ${selected === sq ? "selected" : ""} ${lastMove && [lastMove.from, lastMove.to].includes(sq) ? "last-move" : ""} ${premove && [premove.from, premove.to].includes(sq) ? "premove" : ""} ${hint && [hint.from, hint.to].includes(sq) ? "hinted" : ""} ${checked ? "king-check" : ""}`}
                  onFocus={() => setFocus(i)}
                  onKeyDown={(e) => {
                    const offsets: Record<string, number> = {
                      ArrowLeft: -1,
                      ArrowRight: 1,
                      ArrowUp: -8,
                      ArrowDown: 8,
                    };
                    if (e.key in offsets) {
                      e.preventDefault();
                      const next = Math.max(
                        0,
                        Math.min(63, i + offsets[e.key]),
                      );
                      setFocus(next);
                      grid.current
                        ?.querySelector<HTMLButtonElement>(
                          `[data-square="${squares[next]}"]`,
                        )
                        ?.focus();
                    }
                    if (e.key === "Escape") {
                      e.preventDefault();
                      onSelect(sq);
                    }
                  }}
                  onClick={() => {
                    if (!skipClick.current && interactive) onSelect(sq);
                  }}
                  onPointerDown={(e) => {
                    if (
                      e.button !== 0 ||
                      !interactive ||
                      !piece ||
                      piece.color !== playerColor
                    )
                      return;
                    pointer.current = {
                      from: sq,
                      x: e.clientX,
                      y: e.clientY,
                      dragging: false,
                      piece,
                    };
                    e.currentTarget.setPointerCapture(e.pointerId);
                  }}
                >
                  {piece && (
                    <span
                      className={
                        drag && pointer.current?.from === sq
                          ? "drag-origin"
                          : visual?.to === sq
                            ? "move-arrival"
                            : ""
                      }
                    >
                      <Piece
                        type={piece.type}
                        color={piece.color}
                        set={armies[piece.color]}
                      />
                    </span>
                  )}
                  {isLegal && (
                    <span className={piece ? "capture-ring" : "legal-dot"} />
                  )}
                  {coordinates && i % 8 === 0 && (
                    <span className="rank-coordinate">{sq[1]}</span>
                  )}
                  {coordinates && i >= 56 && (
                    <span className="file-coordinate">{sq[0]}</span>
                  )}
                </button>
              );
            })}
          </div>
        ))}
      </div>
      {visual &&
        (() => {
          const from = squares.indexOf(visual.from),
            to = squares.indexOf(visual.to),
            impact = squares.indexOf(visual.impact);
          return (
            <div
              className={`board-animation ${visual.profile ? `capture-move motion-${visual.profile.motion}` : ""}`}
              key={visual.id}
              aria-hidden="true"
            >
              <div
                className="moving-miniature"
                style={
                  {
                    left: `${(to % 8) * 12.5}%`,
                    top: `${Math.floor(to / 8) * 12.5}%`,
                    "--move-x": `${((from % 8) - (to % 8)) * 100}%`,
                    "--move-y": `${(Math.floor(from / 8) - Math.floor(to / 8)) * 100}%`,
                  } as React.CSSProperties
                }
              >
                <Piece
                  type={visual.type}
                  color={visual.color}
                  set={armies[visual.color]}
                />
              </div>
              {visual.profile && visual.captured && (
                <div
                  className={`defender-miniature death-${visual.profile.death} finisher-${visual.profile.finisher}`}
                  style={{
                    left: `${(impact % 8) * 12.5}%`,
                    top: `${Math.floor(impact / 8) * 12.5}%`,
                  }}
                >
                  <Piece
                    type={visual.captured}
                    color={visual.color === "w" ? "b" : "w"}
                    set={armies[visual.color === "w" ? "b" : "w"]}
                  />
                </div>
              )}
              {visual.profile && (
                <div
                  className={`capture-flourish fx-${visual.profile.vfx} death-${visual.profile.death}`}
                  data-capture={visual.profile.id}
                  data-finisher={visual.profile.finisher}
                  style={{
                    left: `${(impact % 8) * 12.5}%`,
                    top: `${Math.floor(impact / 8) * 12.5}%`,
                  }}
                >
                  <i />
                  <i />
                  <b />
                  <em />
                </div>
              )}
            </div>
          );
        })()}
      {drag && (
        <div
          className="drag-piece"
          style={{
            left: drag.x,
            top: drag.y,
            width: grid.current!.clientWidth / 8,
            height: grid.current!.clientWidth / 8,
          }}
        >
          <Piece type={drag.type} color={drag.color} set={armies[drag.color]} />
        </div>
      )}
    </div>
  );
});
