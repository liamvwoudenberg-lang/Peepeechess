import React, { useLayoutEffect, useEffect, useRef } from "react";
import type { Color, PieceSymbol, Square } from "chess.js";
import { Piece } from "./Piece";
import { LEGION_PALETTES, hex } from "../game/legionIdentity";
import {
  UNIT_DESIGNS,
  type Army,
  type Weapon,
  type AttackMotion,
} from "../game/battleProfiles";
import { battleAudio } from "../game/battleAudio";
import {
  screenSquare,
  battleLayout,
  attackerTravel,
  attackerPoses,
  defenderPoses,
  translated,
  type Battle2DPlan,
} from "../game/battle2D";

export interface Duel2D {
  from: Square;
  to: Square;
  impact: Square;
  type: PieceSymbol;
  color: Color;
  captured: PieceSymbol;
  plan: Battle2DPlan;
  id: string;
}
const TRAILS: Record<AttackMotion, string> = {
  thrust: "M22 66H101M88 57l15 9-15 9",
  mounted_charge: "M10 48H92M4 63H107M18 79H88",
  overhead_smash: "M38 19Q100 20 85 94M72 92l12 12 13-12",
  holy_channel: "M14 61H108M78 37l19 24-19 24M30 42v38",
  royal_arc: "M27 18Q127 45 34 100",
  great_cleave: "M20 17L102 104M33 13L109 89",
  dagger_dance: "M22 24L103 97M21 96L101 22",
  mounted_archery: "M11 76Q51 31 104 58M90 46l16 12-19 9",
  bow_volley: "M10 36H105M5 60H110M15 84H101",
  moon_bind: "M95 60a35 35 0 1 1-70 0 35 35 0 1 1 70 0M82 60a22 22 0 1 1-44 0",
  crescent_dance: "M30 16Q117 34 67 99M91 22Q3 48 53 107",
  leaf_riposte: "M20 91Q32 36 104 50M90 40l16 10-18 9",
  axe_hook: "M23 24Q113 13 103 71Q91 110 45 82",
  skeletal_charge: "M7 54l18-6 19 8 17-7 21 8 28-4M11 74H105",
  maul_crush: "M26 22V88M95 22V88M12 99H110M36 91l25 17 24-17",
  soul_drain: "M104 45Q50 17 20 60Q60 110 101 72M28 52l-11 9 13 8",
  reaping_arc: "M17 31Q92 3 108 58Q88 107 24 96",
  execution: "M57 13V106M66 13V106M29 108H96",
};

/** Separate weapon layers can swing while the character's crown stays readable. */
export function WeaponDrawing({
  weapon,
  army,
  color,
}: {
  weapon: Weapon;
  army: Army;
  color: Color;
}) {
  const p = LEGION_PALETTES[army][color],
    steel = hex(p.steel),
    trim = hex(p.trim),
    ink = hex(p.ink),
    gem = hex(p.gem);
  const line = (d: string, width = 4, stroke = trim) => (
    <path
      d={d}
      fill="none"
      stroke={stroke}
      strokeWidth={width}
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  );
  const blade = (d: string, fill = steel) => (
    <path
      d={d}
      fill={fill}
      stroke={ink}
      strokeWidth="2"
      strokeLinejoin="round"
    />
  );
  let art: React.ReactNode;
  switch (weapon) {
    case "sword_shield":
      art = (
        <>
          {line("M47 74H72")}
          {blade("M71 69H107L117 74 107 79H71Z")}
          {line("M69 62V86", 4)}
        </>
      );
      break;
    case "lance":
      art = (
        <>
          {line("M30 74H104", 4)}
          {blade("M100 68l20 6-20 6Z")}
          {blade("M72 72V49L93 57 76 63", trim)}
        </>
      );
      break;
    case "warhammer":
      art = (
        <>
          {line("M42 74H101", 6)}
          {blade("M91 56H111V91H91Z", trim)}
          {line("M98 61V85", 3, steel)}
        </>
      );
      break;
    case "sun_staff":
      art = (
        <>
          {line("M38 74H94")}
          {
            <circle
              cx="101"
              cy="74"
              r="11"
              fill={gem}
              stroke={trim}
              strokeWidth="4"
            />
          }
          {line("M101 54V59M101 89V94M81 74H86M116 74H120", 3)}
        </>
      );
      break;
    case "sunblade":
      art = (
        <>
          {line("M43 74H67")}
          {blade("M65 68Q91 57 119 74Q92 76 68 82Z")}
          {blade("M77 70Q90 57 101 62Q94 68 104 70Z", trim)}
          {line("M65 61V88")}
        </>
      );
      break;
    case "greatsword":
      art = (
        <>
          {line("M33 74H62", 6)}
          {blade("M61 66H104L120 74 104 82H61Z")}
          {line("M59 59V90", 5)}
        </>
      );
      break;
    case "twin_daggers":
      art = (
        <>
          {line("M48 60H72")}
          {line("M48 87H72")}
          {blade("M70 55l40 5-40 8Z")}
          {blade("M70 80l43 7-43 6Z")}
        </>
      );
      break;
    case "wind_bow":
    case "longbow":
      art = (
        <>
          {line(
            weapon === "longbow"
              ? "M74 24Q122 74 74 119"
              : "M77 39Q112 74 77 109",
            5,
          )}
          {line("M77 39V109", 1.7, steel)}
          {line("M59 74H113", 2, steel)}
          {blade("M108 69l12 5-12 5Z")}
        </>
      );
      break;
    case "moon_staff":
      art = (
        <>
          {line("M37 74H96")}
          {blade(
            "M112 57Q87 48 90 77Q97 96 115 85Q95 88 99 66Q101 59 112 57Z",
            gem,
          )}
        </>
      );
      break;
    case "moonblades":
      art = (
        <>
          {blade("M48 63Q71 30 114 49Q82 43 62 76Z")}
          {blade("M48 86Q75 107 115 88Q81 100 62 73Z")}
        </>
      );
      break;
    case "leafblade":
      art = (
        <>
          {line("M42 74H68")}
          {blade("M65 74Q87 45 120 74Q89 94 65 74Z")}
          {line("M72 74H112", 1.5, trim)}
        </>
      );
      break;
    case "rust_axe":
      art = (
        <>
          {line("M40 74H101", 5)}
          {blade("M92 72L89 51 115 48 118 68 101 82Z", trim)}
        </>
      );
      break;
    case "bone_spear":
      art = (
        <>
          {line("M30 74H103", 5, hex(p.bone))}
          {line("M48 70v8M66 70v8M84 70v8", 3, ink)}
          {blade("M100 65l20 9-20 9Z")}
        </>
      );
      break;
    case "ossuary_maul":
      art = (
        <>
          {line("M38 74H97", 6, hex(p.bone))}
          {blade("M92 55l8 4 7-6 8 10-3 12 5 13-14 8-13-9Z", hex(p.bone))}
          {blade("M98 66h9v14h-9Z", gem)}
        </>
      );
      break;
    case "grave_staff":
      art = (
        <>
          {line("M36 74H98", 4, hex(p.bone))}
          {blade("M94 62Q108 53 116 65V78L110 82V89H99V82L93 77Z", hex(p.bone))}
          {<circle cx="100" cy="70" r="3" fill={ink} />}
          {<circle cx="110" cy="70" r="3" fill={ink} />}
        </>
      );
      break;
    case "soul_scythe":
      art = (
        <>
          {line("M29 74H105", 5)}
          {blade("M97 74Q114 30 70 23Q98 24 118 44Q126 62 111 84Z", gem)}
        </>
      );
      break;
    case "executioner":
      art = (
        <>
          {line("M29 74H63", 7)}
          {blade("M62 61H112L120 73 111 87H62Z")}
          {blade("M91 69h11v10H91Z", trim)}
          {line("M59 56V93", 6)}
        </>
      );
      break;
  }
  return (
    <svg
      className="duel-weapon-art"
      viewBox="0 0 128 128"
      data-weapon={weapon}
      aria-hidden="true"
    >
      {art}
    </svg>
  );
}
function Fleck({ death }: { death: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      {death === "bone_scatter" ? (
        <path d="M6 8Q0 3 4 2Q8 0 9 6L18 15Q24 15 22 20Q20 24 16 19L8 11Q3 14 2 10Q1 6 6 8Z" />
      ) : death === "petal_dissolve" ? (
        <path d="M3 21Q-1 1 23 2Q23 19 3 21Z" />
      ) : (
        <path d="M3 3L21 7 16 22 6 17Z" />
      )}
    </svg>
  );
}

export function Battle2D({
  duel,
  orientation,
  armies,
  sound,
}: {
  duel: Duel2D;
  orientation: Color;
  armies: { w: Army; b: Army };
  sound: boolean;
}) {
  const { plan } = duel,
    { profile, style } = plan,
    to = screenSquare(duel.to, orientation),
    impact = screenSquare(duel.impact, orientation),
    from = screenSquare(duel.from, orientation),
    layout = battleLayout(from, to, impact, Boolean(style.ranged));
  const attacker = useRef<HTMLDivElement>(null),
    pose = useRef<HTMLDivElement>(null),
    weapon = useRef<HTMLDivElement>(null),
    defender = useRef<HTMLDivElement>(null),
    guard = useRef<HTMLDivElement>(null),
    burst = useRef<HTMLDivElement>(null),
    beam = useRef<SVGSVGElement>(null),
    shots = useRef<(HTMLDivElement | null)[]>([]),
    flecks = useRef<(HTMLSpanElement | null)[]>([]),
    started = useRef(0);
  const foe = duel.color === "w" ? "b" : "w",
    color = "#" + profile.color.toString(16).padStart(6, "0");
  useLayoutEffect(() => {
    started.current = performance.now();
    const running: Animation[] = [],
      opts: KeyframeAnimationOptions = {
        duration: plan.duration,
        fill: "both",
        easing: "linear",
      };
    const animate = (el: Element | null, frames: Keyframe[]) => {
      if (el && plan.duration) running.push(el.animate(frames, opts));
    };
    animate(attacker.current, attackerTravel(layout));
    animate(pose.current, attackerPoses(plan, layout.dx, layout.dy));
    animate(defender.current, defenderPoses(plan, layout.dx, layout.dy));
    const times = [
      0,
      0.27,
      plan.hits[0],
      Math.min(0.79, plan.hits[0] + 0.105),
      0.87,
      1,
    ];
    animate(
      weapon.current,
      style.weapon.map((angle, i) => ({
        offset: times[i],
        transform: `rotate(${angle}deg)`,
        opacity: i === 0 || i === 5 ? 0 : 1,
      })),
    );
    const last = plan.hits[plan.hits.length - 1];
    animate(guard.current, [
      { offset: 0, transform: "rotate(-18deg)", opacity: 1 },
      {
        offset: Math.max(0.1, plan.hits[0] - 0.08),
        transform: "rotate(30deg)",
        opacity: 1,
      },
      { offset: last, transform: "rotate(-22deg)", opacity: 1 },
      {
        offset: 1,
        transform: `translate(${layout.dx * 55}%,-20%) rotate(${profile.defender === "q" ? 170 : 95}deg)`,
        opacity: 0,
      },
    ]);
    const flash: Keyframe[] = [
      { offset: 0, opacity: 0, transform: "scale(.35)" },
      {
        offset: Math.max(0.1, plan.hits[0] - 0.04),
        opacity: 0,
        transform: "scale(.45)",
      },
      { offset: plan.hits[0], opacity: 1, transform: "scale(1)" },
      {
        offset: Math.min(0.9, last + 0.1),
        opacity: 0.7,
        transform: "scale(1.35)",
      },
      { offset: 1, opacity: 0, transform: "scale(1.7)" },
    ];
    animate(burst.current, flash);
    animate(beam.current, [
      { offset: 0, opacity: 0 },
      { offset: 0.28, opacity: 0 },
      { offset: plan.hits[0] - 0.02, opacity: 0.8 },
      { offset: plan.defeatAt, opacity: 0.65 },
      { offset: 0.9, opacity: 0 },
      { offset: 1, opacity: 0 },
    ]);
    shots.current.forEach((shot, i) => {
      const a = style.reverse ? layout.impact : layout.park,
        b = style.reverse ? layout.park : layout.impact,
        start = 0.28 + i * 0.035,
        end = Math.min(0.78, plan.hits[0] + i * 0.024);
      animate(shot, [
        { offset: 0, opacity: 0, transform: translated(a.x, a.y) },
        { offset: start, opacity: 0, transform: translated(a.x, a.y) },
        { offset: start + 0.015, opacity: 1, transform: translated(a.x, a.y) },
        { offset: end, opacity: 1, transform: translated(b.x, b.y) },
        {
          offset: Math.min(0.9, end + 0.035),
          opacity: 0,
          transform: translated(b.x, b.y),
        },
        { offset: 1, opacity: 0, transform: translated(b.x, b.y) },
      ]);
    });
    flecks.current.forEach((fleck, i) => {
      const a = (i / Math.max(1, plan.particles)) * Math.PI * 2,
        spread =
          profile.death === "bone_scatter"
            ? 75
            : profile.death === "petal_dissolve"
              ? 50
              : 35,
        up = profile.death === "petal_dissolve" ? -45 : 20;
      animate(fleck, [
        { offset: 0, opacity: 0, transform: "translate(0,0) scale(.5)" },
        {
          offset: plan.defeatAt,
          opacity: 0,
          transform: "translate(0,0) scale(.8)",
        },
        {
          offset: Math.min(0.9, plan.defeatAt + 0.045),
          opacity: 1,
          transform: `translate(${Math.cos(a) * spread * 0.4}%,${Math.sin(a) * spread * 0.4}%) rotate(${i * 43}deg)`,
        },
        {
          offset: 1,
          opacity: 0,
          transform: `translate(${Math.cos(a) * spread}%,${Math.sin(a) * spread + up}%) rotate(${i * 86 + 90}deg) scale(.45)`,
        },
      ]);
    });
    return () => running.forEach((a) => a.cancel());
  }, [duel.id, orientation, plan]);
  useEffect(() => {
    if (!sound) return;
    battleAudio.setEnabled(true);
    const timers: ReturnType<typeof setTimeout>[] = [],
      elapsed = performance.now() - started.current;
    const at = (fraction: number, fn: () => void) => {
      const wait = plan.duration * fraction - elapsed;
      if (wait >= -20) timers.push(setTimeout(fn, Math.max(0, wait)));
    };
    at(0.22, () => battleAudio.windup(profile));
    plan.hits.forEach((hit) => at(hit, () => battleAudio.impact(profile)));
    at(plan.defeatAt, () => battleAudio.defeat(profile));
    return () => timers.forEach(clearTimeout);
  }, [sound, duel.id, plan]);
  const targetStyle = {
      left: `${impact.x * 12.5}%`,
      top: `${impact.y * 12.5}%`,
    },
    endStyle = { left: `${to.x * 12.5}%`, top: `${to.y * 12.5}%` };
  const actorPos = { x: to.x + layout.park.x, y: to.y + layout.park.y },
    magic = style.projectile === "ray" || style.projectile === "orb";
  return (
    <div
      className={`board-animation battle-2d battle-${profile.motion} target-${profile.defender} defeat-${profile.death} ${plan.particles === 0 ? "battle-light" : ""}`}
      data-from={duel.from}
      data-to={duel.to}
      data-impact={duel.impact}
      data-capture={profile.id}
      data-motion={profile.motion}
      data-weapon={profile.weapon}
      data-duration={plan.duration}
      data-finisher={profile.finisher}
      key={duel.id}
      aria-hidden="true"
      style={{ "--battle-color": color } as React.CSSProperties}
    >
      {magic && plan.particles > 0 && (
        <svg
          ref={beam}
          className="duel-beam"
          viewBox="0 0 800 800"
          preserveAspectRatio="none"
        >
          <path
            d={`M${actorPos.x * 100 + 50} ${actorPos.y * 100 + 54} Q${(actorPos.x + impact.x) * 50 + 50 - layout.dy * 22} ${(actorPos.y + impact.y) * 50 + 54 + layout.dx * 22} ${impact.x * 100 + 50} ${impact.y * 100 + 54}`}
            fill="none"
            stroke={color}
            strokeWidth={style.projectile === "ray" ? 6 : 3}
            strokeDasharray={style.reverse ? "9 7" : "none"}
          />
        </svg>
      )}
      <div
        ref={defender}
        className="duel-actor duel-defender"
        style={targetStyle}
      >
        <Piece type={duel.captured} color={foe} set={armies[foe]} unarmed />
        <div
          className="duel-aim"
          style={{ transform: `rotate(${layout.angle + 180}deg)` }}
        >
          <div ref={guard} className="duel-weapon">
            <WeaponDrawing
              weapon={UNIT_DESIGNS[armies[foe]][duel.captured].weapon}
              army={armies[foe]}
              color={foe}
            />
          </div>
        </div>
      </div>
      <div ref={attacker} className="duel-actor duel-attacker" style={endStyle}>
        <div ref={pose} className="duel-pose">
          <Piece
            type={duel.type}
            color={duel.color}
            set={armies[duel.color]}
            unarmed
          />
          <div
            className="duel-aim"
            style={{ transform: `rotate(${layout.angle}deg)` }}
          >
            <div ref={weapon} className="duel-weapon">
              <WeaponDrawing
                weapon={profile.weapon}
                army={armies[duel.color]}
                color={duel.color}
              />
            </div>
          </div>
        </div>
      </div>
      {Array.from({ length: plan.shots }, (_, i) => (
        <div
          key={i}
          ref={(el) => {
            shots.current[i] = el;
          }}
          className={`duel-projectile projectile-${style.projectile}`}
          style={endStyle}
        >
          <svg
            viewBox="0 0 128 128"
            style={{
              transform: `rotate(${layout.angle + (style.reverse ? 180 : 0)}deg)`,
            }}
          >
            {style.projectile === "arrow" ? (
              <>
                <path
                  d="M25 64H104m-8-7 13 7-13 7M26 64l-7-6m7 6-7 6"
                  fill="none"
                  stroke={color}
                  strokeWidth="3"
                  strokeLinecap="round"
                />
              </>
            ) : style.projectile === "ray" ? (
              <path
                d="M25 64H109M54 57h42M54 71h42"
                fill="none"
                stroke={color}
                strokeWidth="5"
              />
            ) : (
              <>
                <circle cx="64" cy="64" r="10" fill={color} />
                <path
                  d="M24 66Q47 37 61 57"
                  fill="none"
                  stroke={color}
                  strokeWidth="3"
                />
              </>
            )}
          </svg>
        </div>
      ))}
      <div ref={burst} className="duel-impact" style={targetStyle}>
        <svg
          viewBox="0 0 128 128"
          style={{ transform: `rotate(${layout.angle}deg)` }}
        >
          <path
            d={TRAILS[profile.motion]}
            fill="none"
            stroke={color}
            strokeWidth={profile.armor > 0.8 ? 4 : 3}
            strokeLinecap="round"
          />
          {profile.armor > 0.8 && (
            <path
              d="M42 46l17 12-8 8 20 14"
              fill="none"
              stroke={color}
              strokeWidth="4"
            />
          )}
        </svg>
      </div>
      {Array.from({ length: plan.particles }, (_, i) => (
        <span
          key={i}
          ref={(el) => {
            flecks.current[i] = el;
          }}
          className="duel-fleck-cell"
          style={targetStyle}
        >
          <span className="duel-fleck">
            <Fleck death={profile.death} />
          </span>
        </span>
      ))}
    </div>
  );
}
