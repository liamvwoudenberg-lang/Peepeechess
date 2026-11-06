import React, { useEffect, useRef } from "react";
import type { Color, Square } from "chess.js";
import { ChessSceneController } from "../three/ChessSceneController";
import { sceneTransition, type ScenePosition } from "../game/sceneTransition";
import type { Army, ArenaStyle } from "../game/battleProfiles";
import type { Ply } from "./contracts";

export default function Scene({
  view = "angled",
  fen,
  lastMove,
  orientation,
  armies,
  arena,
  animationMode,
  reducedMotion,
  sound,
  competitive,
  allowSlow,
  selected,
  legal,
  onSelect,
  onFail,
  onReady,
}: {
  view?: "overhead" | "angled";
  fen: string;
  lastMove?: Ply;
  orientation: Color;
  armies: { w: Army; b: Army };
  arena: ArenaStyle;
  animationMode: "off" | "brief" | "cinematic";
  reducedMotion: boolean;
  sound: boolean;
  competitive: boolean;
  allowSlow: boolean;
  selected: Square | null;
  legal: Square[];
  onSelect: (square: Square) => void;
  onFail: () => void;
  onReady?: () => void;
}) {
  const mount = useRef<HTMLDivElement>(null),
    scene = useRef<ChessSceneController | null>(null),
    position = useRef<ScenePosition | null>(null),
    sequence = useRef(0);
  const callbacks = useRef({
      onSquareClick: (sq: string) => onSelect(sq as Square),
    }),
    failure = useRef(onFail),
    ready = useRef(onReady),
    settings = useRef({
      animationMode,
      reducedMotion,
      sound,
      competitive,
      allowSlow,
      armies,
      fen,
      orientation,
    });
  callbacks.current.onSquareClick = (sq) => onSelect(sq as Square);
  failure.current = onFail;
  ready.current = onReady;
  settings.current = {
    animationMode,
    reducedMotion,
    sound,
    competitive,
    allowSlow,
    armies,
    fen,
    orientation,
  };
  useEffect(() => {
    let controller: ChessSceneController | null = null;
    try {
      const s = settings.current;
      controller = new ChessSceneController(
        mount.current!,
        callbacks,
        arena,
        s.armies.w === "royal" ? "high_crusaders" : s.armies.w,
        "clear",
      );
      scene.current = controller;
      if (controller.getPerformanceStats().isSoftwareGl && !s.allowSlow) {
        controller.dispose();
        controller = null;
        scene.current = null;
        Promise.resolve().then(() => failure.current());
        return;
      }
      controller.setAnimationOptions({
        mode: s.animationMode,
        reducedMotion: s.reducedMotion,
        sound: s.sound,
        competitive: s.competitive,
      });
      controller.setArmies(s.armies.w, s.armies.b);
      controller.setBoardView(view, s.orientation);
      const initial = sceneTransition(
        null,
        s.fen,
        undefined,
        ++sequence.current,
      );
      position.current = initial.position;
      controller.syncBoardPieces(initial.position.pieces, null);
      requestAnimationFrame(() => ready.current?.());
    } catch {
      Promise.resolve().then(() => failure.current());
    }
    let slow = 0;
    const interval = setInterval(() => {
      const stats = controller?.getPerformanceStats();
      if (!stats) return;
      if (mount.current) {
        mount.current.dataset.drawCalls = String(stats.drawCalls);
        mount.current.dataset.lastCapture = stats.lastCapture || "";
        mount.current.dataset.animations = String(stats.animationsPlayed);
        mount.current.dataset.activeAnimations = String(stats.activeAnimations);
        mount.current.dataset.fps = String(stats.fps);
      }
      if (stats.contextLost) {
        failure.current();
        return;
      }
      if (!document.hidden && stats.fps > 0 && stats.fps < 15) slow++;
      else slow = 0;
      if (slow >= 4 && !settings.current.allowSlow) failure.current();
    }, 1500);
    return () => {
      clearInterval(interval);
      controller?.dispose();
      scene.current = null;
      position.current = null;
    };
  }, [arena]);
  useEffect(() => {
    scene.current?.setAnimationOptions({
      mode: animationMode,
      reducedMotion,
      sound,
      competitive,
    });
  }, [animationMode, reducedMotion, sound, competitive]);
  useEffect(() => {
    scene.current?.setArmies(armies.w, armies.b);
  }, [armies.w, armies.b]);
  useEffect(() => {
    if (position.current?.fen === fen) return;
    const result = sceneTransition(
      position.current,
      fen,
      lastMove,
      ++sequence.current,
    );
    position.current = result.position;
    scene.current?.syncBoardPieces(result.position.pieces, result.event);
  }, [fen, lastMove]);
  useEffect(() => {
    scene.current?.setBoardView(view, orientation);
  }, [orientation, view]);
  useEffect(() => {
    scene.current?.setSelectionAndLegalMoves(
      selected,
      legal.map((to) => ({ to, isCapture: false })),
    );
  }, [selected, legal]);
  return (
    <div
      className="scene-mount"
      ref={mount}
      data-arena={arena}
      data-white-army={armies.w}
      data-black-army={armies.b}
      aria-hidden={view === "overhead"}
      role="img"
      aria-label="Castle view. Choose 2D pieces for keyboard or screen reader play."
    />
  );
}
