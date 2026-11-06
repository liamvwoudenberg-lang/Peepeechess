import React, { lazy, Suspense, useEffect, useRef, useState } from "react";
import {
  X,
  ChevronLeft,
  ChevronRight,
  ChevronsLeft,
  ChevronsRight,
  Check,
  Crown,
  Shield,
  Swords,
} from "lucide-react";
import {
  TIME_CONTROLS,
  clockText,
  type Game,
  type PieceSet,
  type Preferences,
  type TimeControl,
} from "./contracts";
import type { Color } from "chess.js";
import { Piece } from "./Piece";
import { ARENAS, UNIT_DESIGNS } from "../game/battleProfiles";
const BattleShowcase = lazy(() => import("./BattleShowcase"));
class ShowcaseBoundary extends React.Component<
  { children: React.ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <div className="panel showcase-loading">
        The 3D preview could not load. Your 2D pieces are ready; reload to retry
        the preview.
      </div>
    ) : (
      this.props.children
    );
  }
}

export function Dialog({
  title,
  children,
  onClose,
}: {
  title: string;
  children: React.ReactNode;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    const before = document.activeElement as HTMLElement;
    const el = ref.current;
    el?.querySelector<HTMLElement>("button,input,select,textarea")?.focus();
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") closeRef.current();
      if (e.key === "Tab") {
        const items = el?.querySelectorAll<HTMLElement>(
          'button:not(:disabled),input,select,textarea,[tabindex="0"]',
        );
        if (!items?.length) return;
        const first = items[0],
          last = items[items.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener("keydown", key);
    return () => {
      document.removeEventListener("keydown", key);
      before?.focus();
    };
  }, []);
  return (
    <div
      className="dialog-shade"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        ref={ref}
      >
        <header>
          <h2>{title}</h2>
          <button
            className="icon-button"
            aria-label="Close dialog"
            onClick={onClose}
          >
            <X size={19} />
          </button>
        </header>
        {children}
      </div>
    </div>
  );
}
export function Clock({
  game,
  color,
  offset = 0,
  paused = false,
}: {
  game: Game | null;
  color: Color;
  offset?: number;
  paused?: boolean;
}) {
  const [, tick] = useState(0);
  const live =
    game?.status === "active" &&
    game?.clocks.turn === color &&
    game?.timeControl !== "untimed" &&
    !paused;
  useEffect(() => {
    if (!live) return;
    const id = setInterval(() => {
      if (!document.hidden) tick((n) => n + 1);
    }, 250);
    return () => clearInterval(id);
  }, [live]);
  const left = game
    ? game.clocks[color] -
      (live ? Math.max(0, Date.now() + offset - game.clocks.updatedAt) : 0)
    : 0;
  return (
    <div
      className={`clock ${live ? "running" : ""} ${left < 20000 && live ? "low-time" : ""}`}
      aria-label={
        game?.timeControl === "untimed"
          ? "Untimed"
          : `${color === "w" ? "White" : "Black"} clock`
      }
    >
      <span className="clock-turn" />
      {!game || game.timeControl === "untimed" ? (
        <span className="untimed-clock">∞</span>
      ) : (
        clockText(left, live)
      )}
    </div>
  );
}
export function TimePicker({
  value,
  onChange,
  allowUntimed = false,
  disabled = false,
}: {
  value: TimeControl;
  onChange: (tc: TimeControl) => void;
  allowUntimed?: boolean;
  disabled?: boolean;
}) {
  return (
    <div className={`time-grid ${allowUntimed ? "with-untimed" : ""}`}>
      {TIME_CONTROLS.filter((t) => allowUntimed || t.id !== "untimed").map(
        (tc) => (
          <button
            key={tc.id}
            className={`time-option ${value === tc.id ? "chosen" : ""}`}
            disabled={disabled}
            onClick={() => onChange(tc.id)}
            aria-pressed={value === tc.id}
          >
            <strong>{tc.label}</strong>
            <small>{tc.detail}</small>
          </button>
        ),
      )}
    </div>
  );
}
export function Toggle({
  checked,
  onChange,
  label,
  detail,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label: string;
  detail?: string;
}) {
  return (
    <label className="toggle-row">
      <span>
        <strong>{label}</strong>
        {detail && <small>{detail}</small>}
      </span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
      />
      <span className="switch" aria-hidden="true" />
    </label>
  );
}
export function Moves({
  game,
  cursor,
  onCursor,
}: {
  game: Game;
  cursor: number | null;
  onCursor: (ply: number) => void;
}) {
  const list = useRef<HTMLDivElement>(null);
  const history = game.history;
  useEffect(() => {
    if (cursor === null && list.current)
      list.current.scrollTop = list.current.scrollHeight;
  }, [history.length, cursor]);
  return (
    <>
      <div className="move-list" ref={list} aria-label="Move history">
        {!history.length ? (
          <div className="quiet-empty">
            <Swords size={24} />
            <p>Your story starts with a move.</p>
            <small>Moves appear here as you play.</small>
          </div>
        ) : (
          Array.from({ length: Math.ceil(history.length / 2) }, (_, i) => (
            <div className="move-row" key={i}>
              <span>{i + 1}.</span>
              {[i * 2, i * 2 + 1].map((ply) =>
                history[ply] ? (
                  <button
                    key={ply}
                    aria-label={`Go to move ${i + 1}, ${ply % 2 ? "Black" : "White"} ${history[ply].san}`}
                    className={
                      cursor === ply + 1 ||
                      (cursor === null && ply === history.length - 1)
                        ? "current"
                        : ""
                    }
                    onClick={() => onCursor(ply + 1)}
                  >
                    {history[ply].san}
                  </button>
                ) : (
                  <span key={ply} />
                ),
              )}
            </div>
          ))
        )}
      </div>
      <div className="move-navigation">
        <button aria-label="First position" onClick={() => onCursor(0)}>
          <ChevronsLeft size={19} />
        </button>
        <button
          aria-label="Previous move"
          onClick={() => onCursor(Math.max(0, (cursor ?? history.length) - 1))}
        >
          <ChevronLeft size={19} />
        </button>
        <button
          aria-label="Next move"
          onClick={() =>
            onCursor(Math.min(history.length, (cursor ?? history.length) + 1))
          }
        >
          <ChevronRight size={19} />
        </button>
        <button
          aria-label="Latest position"
          onClick={() => onCursor(history.length)}
        >
          <ChevronsRight size={19} />
        </button>
      </div>
    </>
  );
}
export const SETS: {
  id: PieceSet;
  name: string;
  tagline: string;
  description: string;
}[] = [
  {
    id: "royal",
    name: "Royal Guard",
    tagline: "Honor, carved in ivory.",
    description:
      "Angelic white plate and gilded crowns. Obsidian armor and crimson crests.",
  },
  {
    id: "elves",
    name: "Silverwood Elves",
    tagline: "Grace on every square.",
    description:
      "Leaf-forged armor, pointed ears, and elegant silverwood detailing.",
  },
  {
    id: "skeletons",
    name: "Hollow Legion",
    tagline: "An army beyond time.",
    description:
      "Armored skeleton soldiers with skull insignia and spectral eyes.",
  },
];
export function Armory({
  preferences,
  onChange,
  lowPower = false,
}: {
  preferences: Preferences;
  onChange: (next: Preferences) => void;
  lowPower?: boolean;
}) {
  const [preview, setPreview] = useState(false);
  useEffect(() => {
    if (lowPower) setPreview(false);
  }, [lowPower]);
  const opponent =
    preferences.opponentSet === "matching"
      ? preferences.pieceSet
      : preferences.opponentSet;
  return (
    <div className="armory-page">
      <div className="section-eyebrow">THE ARMORY</div>
      <h1>Choose your army.</h1>
      <p className="page-description">
        Different characters. The same unmistakable chess pieces.
      </p>
      <div className="set-grid">
        {SETS.map((set) => (
          <button
            key={set.id}
            className={`set-card ${preferences.pieceSet === set.id ? "chosen" : ""}`}
            onClick={() => onChange({ ...preferences, pieceSet: set.id })}
            aria-pressed={preferences.pieceSet === set.id}
          >
            <div className="set-preview">
              {(["k", "q", "r", "b", "n", "p"] as const).map((type) => (
                <Piece key={type} type={type} color="w" set={set.id} />
              ))}
              {(["k", "q", "r", "b", "n", "p"] as const).map((type) => (
                <Piece key={`b${type}`} type={type} color="b" set={set.id} />
              ))}
            </div>
            <div className="set-card-copy">
              <div>
                <h2>{set.name}</h2>
                <p>{set.tagline}</p>
              </div>
              <span className="set-selected">
                {preferences.pieceSet === set.id ? (
                  <Check size={18} />
                ) : (
                  <span />
                )}
              </span>
            </div>
            <p className="set-description">{set.description}</p>
          </button>
        ))}
      </div>
      <div className="design-note">
        <Shield size={23} />
        <p>
          <strong>Read the board at a glance.</strong>
          <br />
          Every set keeps the classic crowns, bishop’s mitre, rook’s
          battlements, pawn’s round head, and a true horse-shaped knight. White
          always wears luminous ivory. Black wears obsidian, crimson, and
          purple.
        </p>
      </div>
      <div className="armory-options panel">
        <label className="select-field">
          <strong>Opposing army</strong>
          <select
            value={preferences.opponentSet}
            onChange={(e) =>
              onChange({
                ...preferences,
                opponentSet: e.target.value as Preferences["opponentSet"],
              })
            }
          >
            <option value="matching">Match my set</option>
            {SETS.map((set) => (
              <option key={set.id} value={set.id}>
                {set.name}
              </option>
            ))}
          </select>
          <small>
            For computer games and previews. Online opponents bring their own
            faction.
          </small>
        </label>
        <label className="select-field">
          <strong>Battle animations</strong>
          <select
            value={preferences.battleAnimations}
            onChange={(e) =>
              onChange({
                ...preferences,
                battleAnimations: e.target
                  .value as Preferences["battleAnimations"],
              })
            }
          >
            <option value="cinematic">Cinematic · full fights in both views</option>
            <option value="brief">Brief · quick strikes</option>
            <option value="off">Off · instant moves</option>
          </select>
          <small>
            Online encounters stay brief. Reduced motion and performance mode
            take priority.
          </small>
        </label>
      </div>
      <div className="armory-section-heading">
        <div>
          <div className="section-eyebrow">THE BATTLEFIELD</div>
          <h2>A castle for every faction.</h2>
          <p>
            White plays at home. Both players share the castle of White’s chosen
            faction.
          </p>
        </div>
      </div>
      <div className="arena-grid">
        {ARENAS.map((arena) => (
          <button
            key={arena.id}
            className={`arena-card ${arena.id} ${preferences.arena === arena.id ? "chosen" : ""}`}
            aria-pressed={preferences.arena === arena.id}
            onClick={() => onChange({ ...preferences, arena: arena.id })}
          >
            <div className="arena-illustration" aria-hidden="true">
              <span className="arena-moon" />
              <i />
              <i />
              <i />
              <i />
              <div className="arena-board" />
            </div>
            <div className="arena-card-copy">
              <h3>{arena.name}</h3>
              {preferences.arena === arena.id && <Check size={18} />}
            </div>
            <p>{arena.description}</p>
          </button>
        ))}
      </div>
      {!preview || lowPower ? (
        <div className="showcase-invite panel">
          <div>
            <Swords size={25} />
            <div>
              <h2>Meet your miniatures.</h2>
              <p>Inspect weapons, movement, and finishing strikes in 3D.</p>
            </div>
          </div>
          <button
            className="secondary-button"
            disabled={lowPower}
            onClick={() => setPreview(true)}
          >
            {lowPower
              ? "3D preview off in Performance mode"
              : "Open battle showcase"}{" "}
            <Swords size={17} />
          </button>
        </div>
      ) : (
        <div>
          <div className="showcase-toolbar">
            <button className="text-button" onClick={() => setPreview(false)}>
              <X size={16} />
              Close battle showcase
            </button>
          </div>
          <ShowcaseBoundary>
            <Suspense
              fallback={
                <div className="panel showcase-loading">
                  Preparing the battlefield…
                </div>
              }
            >
              <BattleShowcase
                army={preferences.pieceSet}
                opponent={opponent}
                arena={preferences.arena}
                sound={preferences.sound}
                reducedMotion={
                  preferences.reducedMotion || preferences.efficiency === "on"
                }
              />
            </Suspense>
          </ShowcaseBoundary>
        </div>
      )}
      <details className="unit-guide panel">
        <summary>
          Weapons of the {SETS.find((s) => s.id === preferences.pieceSet)?.name}
        </summary>
        <div className="unit-guide-grid">
          {(["p", "n", "b", "r", "q", "k"] as const).map((type) => (
            <div key={type}>
              <Piece type={type} color="w" set={preferences.pieceSet} />
              <div>
                <strong>{UNIT_DESIGNS[preferences.pieceSet][type].name}</strong>
                <span>
                  {UNIT_DESIGNS[preferences.pieceSet][type].weaponName}
                </span>
              </div>
            </div>
          ))}
        </div>
      </details>
    </div>
  );
}
