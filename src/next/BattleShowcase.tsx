import React, { useEffect, useRef, useState } from "react";
import { Play, Volume2, VolumeX } from "lucide-react";
import { ChessSceneController } from "../three/ChessSceneController";
import { battleAudio } from "../game/battleAudio";
import { UNIT_DESIGNS, ARENAS, type ArenaStyle } from "../game/battleProfiles";
import { PIECE_NAMES, type PieceSet } from "./contracts";
import type { PieceSymbol } from "../game/types";

export default function BattleShowcase({
  army,
  opponent,
  arena,
  sound,
  reducedMotion,
}: {
  army: PieceSet;
  opponent: PieceSet;
  arena: ArenaStyle;
  sound: boolean;
  reducedMotion: boolean;
}) {
  const mount = useRef<HTMLDivElement>(null),
    controller = useRef<ChessSceneController | null>(null),
    counter = useRef(0),
    lastPreview = useRef(""),
    [attacker, setAttacker] = useState<PieceSymbol>("n"),
    [defender, setDefender] = useState<PieceSymbol>("r"),
    [error, setError] = useState(false),
    [muted, setMuted] = useState(!sound),
    [playing, setPlaying] = useState(false);
  const unit = UNIT_DESIGNS[army][attacker];
  const latest = useRef({
    army,
    opponent,
    attacker,
    defender,
    muted,
    reducedMotion,
  });
  latest.current = { army, opponent, attacker, defender, muted, reducedMotion };
  function replay() {
    const c = controller.current;
    if (!c) return;
    battleAudio.setEnabled(!muted);
    battleAudio.unlock();
    c.setAnimationOptions({
      mode: "cinematic",
      reducedMotion,
      sound: !muted,
      competitive: false,
    });
    c.previewCapture(attacker, defender, army, opponent, ++counter.current);
    setPlaying(true);
  }
  useEffect(() => {
    let c: ChessSceneController | null = null;
    try {
      setError(false);
      c = new ChessSceneController(
        mount.current!,
        { current: { onSquareClick: () => {} } },
        arena,
        army === "royal" ? "high_crusaders" : army,
      );
      controller.current = c;
      const s = latest.current;
      c.setAnimationOptions({
        mode: "cinematic",
        reducedMotion: s.reducedMotion,
        sound: !s.muted,
        competitive: false,
      });
      lastPreview.current = `${s.army}/${s.attacker}>${s.opponent}/${s.defender}`;
      c.previewCapture(
        s.attacker,
        s.defender,
        s.army,
        s.opponent,
        ++counter.current,
      );
      setPlaying(true);
    } catch {
      setError(true);
    }
    const timer = setInterval(() => {
      if (c) {
        const stats = c.getPerformanceStats();
        setPlaying(stats.activeAnimations > 0);
        if (stats.contextLost) setError(true);
        if (mount.current) {
          mount.current.dataset.capture = stats.lastCapture || "";
          mount.current.dataset.animations = String(stats.animationsPlayed);
          mount.current.dataset.activeAnimations = String(
            stats.activeAnimations,
          );
          mount.current.dataset.drawCalls = String(stats.drawCalls);
        }
      }
    }, 200);
    return () => {
      clearInterval(timer);
      c?.dispose();
      controller.current = null;
    };
  }, [arena]);
  useEffect(() => {
    const c = controller.current;
    if (!c) return;
    const key = `${army}/${attacker}>${opponent}/${defender}`;
    if (lastPreview.current === key) return;
    lastPreview.current = key;
    const s = latest.current;
    c.setAnimationOptions({
      mode: "cinematic",
      reducedMotion: s.reducedMotion,
      sound: !s.muted,
      competitive: false,
    });
    c.previewCapture(attacker, defender, army, opponent, ++counter.current);
    setPlaying(true);
  }, [army, opponent, attacker, defender]);
  useEffect(() => {
    controller.current?.setAnimationOptions({
      mode: "cinematic",
      reducedMotion,
      sound: !muted,
      competitive: false,
    });
    return () => battleAudio.setEnabled(sound);
  }, [muted, reducedMotion, sound]);
  return (
    <section className="battle-showcase panel">
      <header>
        <div>
          <small>THE MINIATURES COME TO LIFE</small>
          <h2>Battle showcase</h2>
          <p>Choose two units and watch their signature encounter.</p>
        </div>
        <button
          className="icon-button"
          aria-label={muted ? "Enable preview sound" : "Mute preview sound"}
          onClick={() => {
            setMuted(!muted);
            if (muted) {
              battleAudio.setEnabled(true);
              battleAudio.unlock();
            }
          }}
        >
          {muted ? <VolumeX size={19} /> : <Volume2 size={19} />}
        </button>
      </header>
      <div className="showcase-layout">
        <div
          className="showcase-stage"
          ref={mount}
          role="img"
          aria-label={`${unit.name} versus ${PIECE_NAMES[defender]} in ${ARENAS.find((a) => a.id === arena)?.name}`}
        >
          {error && (
            <p>
              3D is unavailable on this device. Your 2D pieces and games remain
              available.
            </p>
          )}
        </div>
        <div className="showcase-controls">
          <label>
            Attacking unit
            <select
              value={attacker}
              onChange={(e) => setAttacker(e.target.value as PieceSymbol)}
            >
              {(["p", "n", "r", "b", "q", "k"] as const).map((type) => (
                <option value={type} key={type}>
                  {PIECE_NAMES[type][0].toUpperCase() +
                    PIECE_NAMES[type].slice(1)}{" "}
                  · {UNIT_DESIGNS[army][type].name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Defending unit
            <select
              value={defender}
              onChange={(e) => setDefender(e.target.value as PieceSymbol)}
            >
              {(["p", "n", "r", "b", "q", "k"] as const).map((type) => (
                <option value={type} key={type}>
                  {PIECE_NAMES[type][0].toUpperCase() +
                    PIECE_NAMES[type].slice(1)}{" "}
                  · {UNIT_DESIGNS[opponent][type].name}
                </option>
              ))}
            </select>
          </label>
          <div className="weapon-description">
            <strong>{unit.name}</strong>
            <span>{unit.weaponName}</span>
            <small>
              {defender === "r"
                ? "Breaks the shield before the finishing strike."
                : defender === "n"
                  ? "A low strike unseats the mounted defender."
                  : defender === "b"
                    ? "Interrupts the staff before its spell can form."
                    : defender === "q"
                      ? "Disarms the opposing queen before the final strike."
                      : defender === "k"
                        ? "A royal defeat ends with a fallen crown."
                        : "A direct strike breaks the defender’s guard."}
            </small>
          </div>
          <button className="primary-button" disabled={error} onClick={replay}>
            <Play size={17} />
            {playing ? "Replay encounter" : "Preview encounter"}
          </button>
          <p className="field-note">
            {reducedMotion
              ? "Reduced motion is on; encounters settle immediately."
              : defender === "k"
                ? "Showcase only. Kings are defeated by checkmate, never captured in a game."
                : "A cosmetic preview. Your game moves never wait for a battle."}
          </p>
        </div>
      </div>
    </section>
  );
}
