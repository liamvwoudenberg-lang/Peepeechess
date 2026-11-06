import type { AttackMotion, CaptureProfile } from "./battleProfiles";
import type { PieceSymbol } from "./types";

type Beat = readonly [
  advance: number,
  side: number,
  lift: number,
  tilt: number,
  scale?: number,
];
interface Style2D {
  name: string;
  hit: number;
  ranged?: boolean;
  projectile?: "arrow" | "ray" | "orb";
  shots?: number;
  reverse?: boolean;
  double?: boolean;
  body: readonly Beat[];
  weapon: readonly number[];
}
// Six poses per unit: guard, anticipation, first strike, follow-through, recover, rest.
// The artwork stays upright; movement is resolved along/perpendicular to the attack.
export const COMBAT_2D: Record<AttackMotion, Style2D> = {
  thrust: {
    name: "Shield and sword jab",
    hit: 0.48,
    body: [
      [0, 0, 0, 0],
      [-0.1, 0, 0, -8],
      [0.26, 0, 0, 10],
      [0.12, 0, 0, 4],
      [0, 0, 0, -3],
      [0, 0, 0, 0],
    ],
    weapon: [0, -20, 8, 0, -5, 0],
  },
  mounted_charge: {
    name: "Lowered lance charge",
    hit: 0.51,
    body: [
      [0, 0, 0, 0],
      [-0.16, 0, 0.04, -6],
      [0.43, 0, 0.09, 9],
      [0.21, 0, 0, 3],
      [0.03, 0, 0.025, -2],
      [0, 0, 0, 0],
    ],
    weapon: [-28, -12, 0, 7, -15, -28],
  },
  overhead_smash: {
    name: "Siege hammer blow",
    hit: 0.56,
    body: [
      [0, 0, 0, 0],
      [-0.08, 0, 0.12, -16, 1.06],
      [0.17, 0, -0.045, 15, 0.91],
      [0.1, 0, 0, 4],
      [0, 0, 0, -3],
      [0, 0, 0, 0],
    ],
    weapon: [-50, -115, 35, 52, -25, -50],
  },
  holy_channel: {
    name: "Sunburst invocation",
    hit: 0.53,
    ranged: true,
    projectile: "ray",
    shots: 1,
    body: [
      [0, 0, 0, 0],
      [0, 0, 0.1, -4],
      [0, 0, 0.17, 0, 1.045],
      [0, 0, 0.11, 3],
      [0, 0, 0.04, 0],
      [0, 0, 0, 0],
    ],
    weapon: [-70, -88, -92, -86, -77, -70],
  },
  royal_arc: {
    name: "Sunblade sweeping arc",
    hit: 0.47,
    body: [
      [0, 0, 0, 0],
      [-0.1, -0.12, 0, -22],
      [0.26, 0.16, 0.06, 22],
      [0.17, -0.08, 0, -9],
      [0, 0, 0, 3],
      [0, 0, 0, 0],
    ],
    weapon: [-30, -110, 55, 95, 5, -30],
  },
  great_cleave: {
    name: "Two-handed royal cleave",
    hit: 0.58,
    body: [
      [0, 0, 0, 0],
      [-0.13, 0, 0.025, -19],
      [0.31, 0, 0, 17, 0.96],
      [0.17, 0.03, 0, 9],
      [0, 0, 0, -4],
      [0, 0, 0, 0],
    ],
    weapon: [-42, -133, 31, 66, -12, -42],
  },
  dagger_dance: {
    name: "Twin dagger cross",
    hit: 0.43,
    double: true,
    body: [
      [0, 0, 0, 0],
      [-0.07, -0.16, 0, -13],
      [0.25, 0.17, 0.06, 15],
      [0.27, -0.16, 0.025, -16],
      [0.03, 0.04, 0, 5],
      [0, 0, 0, 0],
    ],
    weapon: [-15, -55, 60, -65, 15, -15],
  },
  mounted_archery: {
    name: "Windrider bow shot",
    hit: 0.5,
    ranged: true,
    projectile: "arrow",
    shots: 1,
    body: [
      [0, 0, 0, 0],
      [-0.12, 0.13, 0.06, -9],
      [-0.05, -0.09, 0.12, 4],
      [0.04, 0.06, 0.03, 7],
      [0.01, 0, 0.025, -3],
      [0, 0, 0, 0],
    ],
    weapon: [0, -13, 7, -6, 3, 0],
  },
  bow_volley: {
    name: "Three-arrow thorn volley",
    hit: 0.54,
    ranged: true,
    projectile: "arrow",
    shots: 3,
    body: [
      [0, 0, 0, 0],
      [-0.09, 0, 0, -7],
      [-0.04, 0.035, 0.015, 5],
      [-0.07, -0.035, 0, -4],
      [0.015, 0, 0, 2],
      [0, 0, 0, 0],
    ],
    weapon: [0, -11, 6, -9, 4, 0],
  },
  moon_bind: {
    name: "Moonlit binding circles",
    hit: 0.57,
    ranged: true,
    projectile: "orb",
    shots: 2,
    body: [
      [0, 0, 0, 0],
      [0, -0.09, 0.11, -8],
      [0.03, 0.1, 0.18, 9],
      [-0.02, -0.06, 0.13, -5],
      [0, 0.025, 0.05, 3],
      [0, 0, 0, 0],
    ],
    weapon: [-66, -96, -77, -103, -79, -66],
  },
  crescent_dance: {
    name: "Leaping crescent blades",
    hit: 0.46,
    double: true,
    body: [
      [0, 0, 0, 0],
      [-0.1, -0.19, 0.05, -21],
      [0.29, 0.21, 0.2, 27],
      [0.2, -0.18, 0.09, -23],
      [0.02, 0.03, 0.025, 5],
      [0, 0, 0, 0],
    ],
    weapon: [-24, -95, 108, -97, 20, -24],
  },
  leaf_riposte: {
    name: "Leafblade parry and riposte",
    hit: 0.44,
    body: [
      [0, 0, 0, 0],
      [-0.18, 0.08, 0, -11],
      [0.35, -0.05, 0.035, 12],
      [0.12, 0.04, 0, -5],
      [0.01, 0, 0, 2],
      [0, 0, 0, 0],
    ],
    weapon: [-20, 48, -12, 5, -10, -20],
  },
  axe_hook: {
    name: "Hooking rust axe",
    hit: 0.49,
    body: [
      [0, 0, 0, 0],
      [-0.08, 0.12, 0, 17],
      [0.2, -0.15, 0.025, -24],
      [-0.11, 0.09, 0, 11],
      [0.02, -0.02, 0, -4],
      [0, 0, 0, 0],
    ],
    weapon: [-30, 65, -84, -125, -9, -30],
  },
  skeletal_charge: {
    name: "Bone-spear gallop",
    hit: 0.51,
    body: [
      [0, 0, 0, 0],
      [-0.11, -0.025, 0.09, -10],
      [0.4, 0.03, 0.06, 12],
      [0.16, -0.045, -0.015, -6],
      [0.04, 0.02, 0.04, 4],
      [0, 0, 0, 0],
    ],
    weapon: [-22, -4, 5, -8, 8, -22],
  },
  maul_crush: {
    name: "Double ossuary crush",
    hit: 0.54,
    double: true,
    body: [
      [0, 0, 0, 0],
      [-0.11, 0, 0.15, -22, 1.08],
      [0.22, 0, -0.06, 19, 0.88],
      [0.17, 0.035, 0.1, -14, 1.03],
      [0.09, 0, -0.03, 10, 0.94],
      [0, 0, 0, 0],
    ],
    weapon: [-55, -126, 48, -112, 58, -55],
  },
  soul_drain: {
    name: "Returning soul siphon",
    hit: 0.56,
    ranged: true,
    projectile: "orb",
    shots: 3,
    reverse: true,
    body: [
      [0, 0, 0, 0],
      [0.05, 0, 0.08, 7],
      [-0.12, 0.055, 0.13, -14],
      [-0.09, -0.04, 0.07, -8],
      [0.015, 0, 0.025, 3],
      [0, 0, 0, 0],
    ],
    weapon: [-64, -94, -106, -87, -73, -64],
  },
  reaping_arc: {
    name: "Low scythe reap",
    hit: 0.54,
    body: [
      [0, 0, 0, 0],
      [-0.07, -0.17, 0.025, -25],
      [0.31, 0.15, -0.035, 29],
      [0.18, -0.11, 0, -13],
      [0.025, 0.03, 0.015, 6],
      [0, 0, 0, 0],
    ],
    weapon: [-38, -136, 101, 140, 3, -38],
  },
  execution: {
    name: "Raised execution blade",
    hit: 0.62,
    body: [
      [0, 0, 0, 0],
      [-0.1, 0, 0.07, -13, 1.035],
      [0.12, 0, 0.13, -8],
      [0.26, 0, -0.045, 21, 0.92],
      [0.08, 0, 0, 5],
      [0, 0, 0, 0],
    ],
    weapon: [-55, -139, -153, 49, 70, -55],
  },
};

export interface Battle2DOptions {
  mode: "off" | "brief" | "cinematic";
  competitive?: boolean;
  lightweight?: boolean;
  reducedMotion?: boolean;
}
export interface Battle2DPlan {
  profile: CaptureProfile;
  style: Style2D;
  duration: number;
  hits: number[];
  defeatAt: number;
  particles: number;
  shots: number;
}
export function planBattle2D(
  profile: CaptureProfile,
  options: Battle2DOptions,
): Battle2DPlan {
  const style = COMBAT_2D[profile.motion],
    lastHit = Math.min(0.72, style.hit + profile.armor * 0.025),
    hits = [lastHit];
  if (style.double || profile.secondaryImpact)
    hits.push(Math.min(0.79, lastHit + 0.105));
  const duration =
    options.mode === "off" || options.reducedMotion
      ? 0
      : options.lightweight
        ? 340
        : options.competitive
          ? 460
          : options.mode === "brief"
            ? 480
            : Math.round(1000 + profile.armor * 160 + (style.double ? 80 : 0));
  return {
    profile,
    style,
    duration,
    hits,
    defeatAt: Math.min(0.84, hits[hits.length - 1] + 0.055),
    particles: !duration
      ? 0
      : options.lightweight
        ? 0
        : options.competitive
          ? 3
          : 6,
    shots: !duration
      ? 0
      : options.lightweight
        ? Math.min(1, style.shots || 0)
        : style.shots || 0,
  };
}
export interface ScreenPoint {
  x: number;
  y: number;
}
export function screenSquare(
  square: string,
  orientation: "w" | "b",
): ScreenPoint {
  const file = "abcdefgh".indexOf(square[0]),
    rank = Number(square[1]) - 1;
  return orientation === "w"
    ? { x: file, y: 7 - rank }
    : { x: 7 - file, y: rank };
}
export function battleLayout(
  from: ScreenPoint,
  to: ScreenPoint,
  impact: ScreenPoint,
  ranged: boolean,
) {
  const length = Math.hypot(impact.x - from.x, impact.y - from.y) || 1,
    dx = (impact.x - from.x) / length,
    dy = (impact.y - from.y) / length;
  return {
    from: { x: from.x - to.x, y: from.y - to.y },
    impact: { x: impact.x - to.x, y: impact.y - to.y },
    park: ranged
      ? { x: from.x - to.x, y: from.y - to.y }
      : { x: impact.x - to.x - dx * 0.57, y: impact.y - to.y - dy * 0.57 },
    dx,
    dy,
    angle: (Math.atan2(dy, dx) * 180) / Math.PI,
  };
}
export const translated = (x: number, y: number) =>
  `translate(${x * 100}%,${y * 100}%)`;
export function attackerTravel(
  layout: ReturnType<typeof battleLayout>,
): Keyframe[] {
  return [
    { offset: 0, transform: translated(layout.from.x, layout.from.y) },
    { offset: 0.24, transform: translated(layout.park.x, layout.park.y) },
    { offset: 0.83, transform: translated(layout.park.x, layout.park.y) },
    { offset: 1, transform: translated(0, 0) },
  ];
}
export function attackerPoses(
  plan: Battle2DPlan,
  dx: number,
  dy: number,
): Keyframe[] {
  const times = [
    0,
    0.27,
    plan.hits[0],
    Math.min(0.79, plan.hits[0] + 0.105),
    0.87,
    1,
  ];
  return plan.style.body.map(([advance, side, lift, tilt, scale = 1], i) => ({
    offset: times[i],
    transform: `${translated(dx * advance - dy * side, dy * advance + dx * side - lift)} rotate(${tilt * (dx < 0 ? -1 : 1)}deg) scale(${scale})`,
  }));
}
export function defenderPoses(
  plan: Battle2DPlan,
  dx: number,
  dy: number,
): Keyframe[] {
  const { profile } = plan,
    hit = plan.hits[0],
    end = plan.defeatAt;
  const reactions: Record<
    PieceSymbol,
    { x: number; y: number; tilt: number; size: number }
  > = {
    p: { x: 0.18, y: 0.21, tilt: 64, size: 0.62 },
    n: { x: 0.36, y: 0.24, tilt: 101, size: 0.55 },
    r: { x: 0.11, y: 0.13, tilt: 22, size: 0.73 },
    b: { x: -0.17, y: 0.28, tilt: -48, size: 0.5 },
    q: { x: 0.25, y: -0.14, tilt: -74, size: 0.65 },
    k: { x: 0, y: 0.17, tilt: 6, size: 0.88 },
  };
  const r = reactions[profile.defender],
    direction = dx < 0 ? -1 : 1,
    hook =
      profile.motion === "axe_hook" || profile.motion === "soul_drain" ? -1 : 1;
  return [
    { offset: 0, transform: translated(0, 0), opacity: 1 },
    {
      offset: Math.max(0.1, hit - 0.1),
      transform: `${translated(-dy * profile.sidestep, dx * profile.sidestep)} rotate(${-direction * profile.armor * 6}deg)`,
      opacity: 1,
    },
    {
      offset: hit,
      transform: `${translated(dx * 0.09 * hook, dy * 0.09 * hook - 0.045)} rotate(${direction * 11}deg)`,
      opacity: 1,
    },
    {
      offset: end,
      transform: `${translated(dx * 0.14 * hook, dy * 0.14 * hook)} rotate(${direction * 17}deg)`,
      opacity: 0.95,
    },
    {
      offset: 1,
      transform: `${translated(dx * r.x * hook - dy * 0.05, dy * r.x * hook + r.y)} rotate(${direction * r.tilt}deg) scale(${r.size})`,
      opacity: profile.defender === "k" ? 1 : 0,
    },
  ];
}
