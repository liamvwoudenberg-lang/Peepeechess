import { copyState } from "./copyState";
import React, { useEffect, useRef, useState } from "react";
import type { Color } from "chess.js";
import { ArenaRenderer } from "./ArenaRenderer";
import { CombatControls } from "./controls";
import {
  ACTIONS,
  FIGHTERS,
  ROLE_NAMES,
  type Action,
  type Bindings,
} from "./config";
import type { BattleSnapshot } from "./session";
import type { CombatInput } from "./simulation";
import { battleAudio } from "../game/battleAudio";
import { captureProfile } from "../game/battleProfiles";
const title = (color: Color) => (color === "w" ? "White" : "Black");
export default function CombatArena({
  getSnapshot,
  colors,
  bindings,
  light,
  sound,
  onInput,
  onFailure,
  onPause,
  onContinue,
  onRecovered,
  blocked,
}: {
  blocked: boolean;
  onRecovered: () => void;
  getSnapshot: () => BattleSnapshot;
  colors: Color[];
  bindings: Record<Color, Bindings>;
  light: boolean;
  sound: boolean;
  onInput: (color: Color, input: CombatInput) => void;
  onFailure: () => void;
  onPause: () => void;
  onContinue: () => void;
}) {
  const mount = useRef<HTMLDivElement>(null),
    control = useRef<CombatControls | null>(null),
    renderer = useRef<ArenaRenderer | null>(null),
    callbacks = useRef({
      onInput,
      onFailure,
      onPause,
      onRecovered,
      blocked,
      sound,
      getSnapshot,
    });
  callbacks.current = {
    onInput,
    onFailure,
    onPause,
    onRecovered,
    blocked,
    sound,
    getSnapshot,
  };
  const [ui, setUi] = useState(() => copyState(getSnapshot())),
    [failed, setFailed] = useState(false),
    [retry, setRetry] = useState(0),
    [locked, setLocked] = useState<Record<Color, boolean>>({
      w: true,
      b: true,
    });
  const id = getSnapshot().combat!.id;
  useEffect(() => {
    if (control.current)
      control.current.bindings =
        colors.length === 1
          ? { ...bindings, [colors[0]]: bindings.w }
          : bindings;
  }, [bindings]);
  useEffect(() => {
    const escape = (e: KeyboardEvent) => {
      if (e.code === "Escape" && !callbacks.current.blocked) {
        e.preventDefault();
        callbacks.current.onPause();
      }
    };
    window.addEventListener("keydown", escape);
    return () => window.removeEventListener("keydown", escape);
  }, []);
  useEffect(() => {
    let scene: ArenaRenderer | null = null,
      inputs: CombatControls | null = null,
      wasBlocked = false,
      frame = 0,
      last = performance.now(),
      lastHud = 0,
      lastRender = 0,
      lastSound = 0,
      disposed = false;
    const fail = () => {
      if (disposed) return;
      setFailed(true);
      callbacks.current.onFailure();
    };
    try {
      scene = new ArenaRenderer(
        mount.current!,
        getSnapshot().combat!,
        getSnapshot().match.armies,
        colors,
        light,
      );
      renderer.current = scene;
      inputs = new CombatControls(
        colors,
        scene.controls,
        colors.length === 1
          ? { ...bindings, [colors[0]]: bindings.w }
          : bindings,
        getSnapshot().combat!,
      );
      control.current = inputs;
      if (retry) callbacks.current.onRecovered();
    } catch {
      scene?.dispose();
      fail();
      return;
    }
    mount.current!.addEventListener("battle-context-lost", fail);
    const animate = (time: number) => {
      if (disposed) return;
      frame = requestAnimationFrame(animate);
      const dt = Math.min(0.1, (time - last) / 1000);
      last = time;
      const snapshot = callbacks.current.getSnapshot(),
        combat = snapshot.combat;
      if (!combat) return;
      const blocked = snapshot.paused || callbacks.current.blocked;
      if (blocked !== wasBlocked) {
        inputs!.clear();
        for (const c of colors)
          inputs!.counts[c] = { ...combat.fighters[c].seen };
        wasBlocked = blocked;
      }
      inputs!.enabled = !blocked && snapshot.match.phase === "combat";
      for (const c of colors) callbacks.current.onInput(c, inputs!.read(c, dt));
      if (
        !document.hidden &&
        time - lastRender >= (light ? 33 : 16) &&
        (!snapshot.paused || time - lastRender > 200)
      ) {
        scene!.render(combat, Math.max(dt, (time - lastRender) / 1000));
        lastRender = time;
      }
      if (time - lastHud > 66) {
        lastHud = time;
        setUi(copyState(snapshot));
        setLocked({ w: scene!.controls.w.locked, b: scene!.controls.b.locked });
      }
      for (const e of combat.events)
        if (e.id > lastSound) {
          lastSound = e.id;
          if (callbacks.current.sound) {
            const f = combat.fighters[e.actor],
              d = combat.fighters[e.target],
              p = captureProfile(
                snapshot.match.armies[e.actor],
                f.role,
                snapshot.match.armies[e.target],
                d.role,
                e.actor,
              );
            battleAudio.setEnabled(true);
            if (e.type === "hit" || e.type === "guardbreak")
              battleAudio.impact(p);
            else if (e.type === "ability") battleAudio.windup(p);
            else if (e.type === "parry" || e.type === "block")
              battleAudio.step(snapshot.match.armies[e.actor], "r");
          }
        }
    };
    frame = requestAnimationFrame(animate);
    return () => {
      disposed = true;
      cancelAnimationFrame(frame);
      mount.current?.removeEventListener("battle-context-lost", fail);
      inputs?.dispose();
      control.current = null;
      scene?.dispose();
      renderer.current = null;
    };
  }, [id, retry]);
  const combat = ui.combat;
  if (!combat) return null;
  const rotate = (color: Color, dx: number, dy: number) => {
    const cam = renderer.current?.controls[color];
    if (cam) {
      cam.yaw += dx * 0.008;
      cam.pitch = Math.max(-0.08, Math.min(0.75, cam.pitch + dy * 0.006));
    }
  };
  return (
    <section
      className={`combat-stage ${colors.length === 2 ? "combat-split" : "combat-single"}`}
      aria-label="Battle Chess fighting arena"
      data-combat-id={id}
      data-phase={ui.match.phase}
    >
      <div ref={mount} className="combat-canvas" />
      <div className="combat-topline">
        <span>THE CAPTURE DUEL</span>
        <strong>
          {Math.ceil(combat.remaining)}
          <small>seconds</small>
        </strong>
        <button onClick={onPause} aria-label="Open combat menu">
          Menu
        </button>
      </div>
      <div className="combat-views">
        {colors.map((color, index) => {
          const self = combat.fighters[color],
            foe = combat.fighters[color === "w" ? "b" : "w"];
          return (
            <div
              className={`combat-view view-${color}`}
              key={color}
              data-player={color}
              onContextMenu={(e) => e.preventDefault()}
            >
              <div className="combat-hud">
                {[self, foe].map((fighter, i) => (
                  <div
                    className={`fighter-meter ${i ? "opponent" : ""}`}
                    key={fighter.color}
                    data-fighter={fighter.color}
                    data-hp={fighter.hp.toFixed(1)}
                    data-stamina={fighter.stamina.toFixed(1)}
                    data-state={fighter.state}
                  >
                    <div>
                      <strong>
                        {title(fighter.color)} · {ROLE_NAMES[fighter.role]}
                      </strong>
                      <span>
                        {Math.ceil(fighter.hp)} / {FIGHTERS[fighter.role].hp}
                      </span>
                    </div>
                    <progress
                      aria-label={`${title(color)} view ${title(fighter.color)} health`}
                      className="health-meter"
                      max={FIGHTERS[fighter.role].hp}
                      value={fighter.hp}
                    />
                    <progress
                      aria-label={`${title(color)} view ${title(fighter.color)} stamina`}
                      className="stamina-meter"
                      max={FIGHTERS[fighter.role].stamina}
                      value={fighter.stamina}
                    />
                  </div>
                ))}
              </div>
              <CameraPad
                label={`${title(color)} camera`}
                onDrag={(dx, dy) => rotate(color, dx, dy)}
                onZoom={(delta) => {
                  const cam = renderer.current?.controls[color];
                  if (cam)
                    cam.distance = Math.max(
                      2.4,
                      Math.min(5.5, cam.distance + delta * 0.003),
                    );
                }}
                onAttack={(button) => {
                  if (!control.current) return;
                  const c = colors.length === 2 ? color : colors[0];
                  control.current.mouse(c, button);
                }}
              />
              <div className="combat-feedback" aria-live="polite">
                {combat.events
                  .filter(
                    (e) =>
                      combat.time - e.at < 0.8 &&
                      (e.actor === color || e.target === color),
                  )
                  .slice(-1)
                  .map((e) => (
                    <span key={e.id} className={`feedback-${e.type}`}>
                      {e.type === "parry"
                        ? e.actor === color
                          ? "PERFECT PARRY"
                          : "PARRIED"
                        : e.type === "guardbreak"
                          ? "GUARD BROKEN"
                          : e.type === "block"
                            ? e.actor === color
                              ? "BLOCKED"
                              : "GUARD HIT"
                            : e.type === "dodge"
                              ? e.actor === color
                                ? "EVADED"
                                : "MISSED"
                              : e.type === "ability"
                                ? FIGHTERS[combat.fighters[e.actor].role]
                                    .ability
                                : e.actor === color
                                  ? `${e.damage} DAMAGE`
                                  : `−${e.damage} HP`}
                    </span>
                  ))}
              </div>
              <div className="combat-touch">
                <Joystick
                  label={`${title(color)} movement`}
                  onMove={(x, z) => {
                    if (control.current)
                      control.current.touch[color] = {
                        ...control.current.touch[color],
                        x,
                        z,
                      };
                  }}
                />
                <div className="combat-actions">
                  <ActionButton
                    label={`${title(color)} parry`}
                    text="Parry"
                    className="parry-action"
                    onPress={() => control.current?.press(color, "parry")}
                  />
                  <ActionButton
                    label={`${title(color)} block`}
                    text="Block"
                    className="block-action"
                    onPress={() => {
                      if (control.current)
                        control.current.touch[color].block = true;
                    }}
                    onRelease={() => {
                      if (control.current)
                        control.current.touch[color].block = false;
                    }}
                  />
                  <ActionButton
                    label={`${title(color)} dodge`}
                    text="Dodge"
                    onPress={() => control.current?.press(color, "dodge")}
                  />
                  <ActionButton
                    label={`${title(color)} light attack`}
                    text="Light"
                    className="light-action"
                    onPress={() => control.current?.press(color, "light")}
                  />
                  <ActionButton
                    label={`${title(color)} heavy attack`}
                    text="Heavy"
                    className="heavy-action"
                    onPress={() => control.current?.press(color, "heavy")}
                  />
                  <ActionButton
                    label={`${title(color)} special ability`}
                    text={
                      self.cooldown > 0
                        ? `${Math.ceil(self.cooldown)}s`
                        : self.role === "p" && self.hp > FIGHTERS.p.hp * 0.35
                          ? "Last Stand · low HP"
                          : FIGHTERS[self.role].ability
                    }
                    disabled={
                      self.cooldown > 0 ||
                      (self.role === "p" && self.hp > FIGHTERS.p.hp * 0.35)
                    }
                    className="ability-action"
                    onPress={() => control.current?.press(color, "ability")}
                  />
                </div>
                <button
                  className="combat-lock"
                  aria-label={`${title(color)} target lock`}
                  aria-pressed={locked[color]}
                  onClick={() => control.current?.toggle(color)}
                >
                  ⊙ {locked[color] ? "Locked" : "Free look"}
                </button>
              </div>
              <div className="combat-player-label">
                {title(color)} · {FIGHTERS[self.role].name}
                {colors.length === 2 ? (
                  <small>
                    {index === 0
                      ? "WASD · Mouse / Space / Q E R"
                      : "Arrows · J K L / U I O"}
                  </small>
                ) : (
                  <small>WASD · Mouse / Space / Q E R</small>
                )}
              </div>
            </div>
          );
        })}
      </div>
      {combat.countdown > 0 && (
        <div className="combat-announcement">
          <small>TAKE YOUR POSITIONS</small>
          <strong>{Math.ceil(combat.countdown)}</strong>
          <span>Every attack has a wind-up. Read your opponent.</span>
        </div>
      )}
      {combat.winner && (
        <div className="combat-announcement combat-victory" role="status">
          <small>{combat.reason}</small>
          <strong>{title(combat.winner)} prevails</strong>
          <span>
            {combat.winner === combat.attacker
              ? "The attacker takes the square."
              : "The defender holds. The attacking piece is removed."}
          </span>
          <button
            className="primary-button"
            disabled={ui.aftermath < 0.75}
            onClick={onContinue}
          >
            Return to board
          </button>
        </div>
      )}
      {failed && (
        <div className="combat-unavailable" role="alert">
          <h2>The 3D arena could not start</h2>
          <p>This mode needs WebGL. No battle outcome has been applied.</p>
          <button
            onClick={() => {
              setFailed(false);
              setRetry((v) => v + 1);
            }}
          >
            Retry 3D
          </button>
          <button onClick={onPause}>Match options</button>
        </div>
      )}
    </section>
  );
}
function ActionButton({
  label,
  text,
  onPress,
  onRelease,
  disabled = false,
  className = "",
}: {
  label: string;
  text: string;
  onPress: () => void;
  onRelease?: () => void;
  disabled?: boolean;
  className?: string;
}) {
  const active = useRef(new Set<number>());
  return (
    <button
      className={`combat-action ${className}`}
      aria-label={label}
      disabled={disabled}
      onPointerDown={(e) => {
        e.preventDefault();
        e.stopPropagation();
        e.currentTarget.setPointerCapture(e.pointerId);
        active.current.add(e.pointerId);
        onPress();
      }}
      onPointerUp={(e) => {
        active.current.delete(e.pointerId);
        if (!active.current.size) onRelease?.();
      }}
      onPointerCancel={(e) => {
        active.current.delete(e.pointerId);
        if (!active.current.size) onRelease?.();
      }}
      onLostPointerCapture={() => {
        active.current.clear();
        onRelease?.();
      }}
      onClick={(e) => {
        if (e.detail === 0) onPress();
      }}
    >
      {text}
    </button>
  );
}
function Joystick({
  label,
  onMove,
}: {
  label: string;
  onMove: (x: number, z: number) => void;
}) {
  const [knob, setKnob] = useState({ x: 0, y: 0 }),
    pointer = useRef<number | null>(null);
  const update = (e: React.PointerEvent<HTMLDivElement>) => {
    if (pointer.current !== e.pointerId) return;
    const b = e.currentTarget.getBoundingClientRect(),
      dx = e.clientX - b.x - b.width / 2,
      dy = e.clientY - b.y - b.height / 2,
      length = Math.hypot(dx, dy),
      scale = Math.min(1, 34 / (length || 1));
    setKnob({ x: dx * scale, y: dy * scale });
    onMove((dx * scale) / 34, (-dy * scale) / 34);
  };
  const release = () => {
    pointer.current = null;
    setKnob({ x: 0, y: 0 });
    onMove(0, 0);
  };
  return (
    <div
      className="combat-stick"
      role="group"
      aria-label={label}
      onPointerDown={(e) => {
        if (pointer.current !== null) return;
        pointer.current = e.pointerId;
        e.currentTarget.setPointerCapture(e.pointerId);
        update(e);
      }}
      onPointerMove={update}
      onPointerUp={release}
      onPointerCancel={release}
      onLostPointerCapture={release}
    >
      <span style={{ transform: `translate(${knob.x}px,${knob.y}px)` }} />
      <small>MOVE · EDGE TO RUN</small>
    </div>
  );
}
function CameraPad({
  label,
  onDrag,
  onAttack,
  onZoom,
}: {
  label: string;
  onZoom: (delta: number) => void;
  onDrag: (x: number, y: number) => void;
  onAttack: (button: number) => void;
}) {
  const pointer = useRef<{ id: number; x: number; y: number } | null>(null);
  return (
    <div
      className="combat-camera-pad"
      aria-label={label}
      onPointerDown={(e) => {
        if (pointer.current) return;
        e.currentTarget.setPointerCapture(e.pointerId);
        pointer.current = { id: e.pointerId, x: e.clientX, y: e.clientY };
        if (e.pointerType === "mouse") onAttack(e.button);
      }}
      onPointerMove={(e) => {
        const p = pointer.current;
        if (!p || p.id !== e.pointerId) return;
        onDrag(e.clientX - p.x, e.clientY - p.y);
        p.x = e.clientX;
        p.y = e.clientY;
      }}
      onPointerUp={() => (pointer.current = null)}
      onPointerCancel={() => (pointer.current = null)}
      onWheel={(e) => {
        onZoom(e.deltaY);
      }}
    />
  );
}
