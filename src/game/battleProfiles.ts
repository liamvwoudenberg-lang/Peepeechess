import { BOARD_PALETTES } from "./legionIdentity";
import type { PieceSymbol, PieceColor, FactionSkin } from "./types";

export type Army = "royal" | "elves" | "skeletons";
export type ArenaStyle = "citadel" | "silverwood" | "ossuary";
export type Weapon =
  | "sword_shield"
  | "lance"
  | "warhammer"
  | "sun_staff"
  | "sunblade"
  | "greatsword"
  | "twin_daggers"
  | "wind_bow"
  | "longbow"
  | "moon_staff"
  | "moonblades"
  | "leafblade"
  | "rust_axe"
  | "bone_spear"
  | "ossuary_maul"
  | "grave_staff"
  | "soul_scythe"
  | "executioner";
export type AttackMotion =
  | "thrust"
  | "mounted_charge"
  | "overhead_smash"
  | "holy_channel"
  | "royal_arc"
  | "great_cleave"
  | "dagger_dance"
  | "mounted_archery"
  | "bow_volley"
  | "moon_bind"
  | "crescent_dance"
  | "leaf_riposte"
  | "axe_hook"
  | "skeletal_charge"
  | "maul_crush"
  | "soul_drain"
  | "reaping_arc"
  | "execution";
export interface UnitDesign {
  name: string;
  weapon: Weapon;
  weaponName: string;
  motion: AttackMotion;
  gait: "march" | "grace" | "rattle" | "gallop" | "bone_gallop" | "float";
  pace: number;
  reach: number;
  attackSeconds: number;
}
export const UNIT_DESIGNS: Record<Army, Record<PieceSymbol, UnitDesign>> = {
  royal: {
    p: {
      name: "Dawn Squire",
      weapon: "sword_shield",
      weaponName: "Arming sword & kite shield",
      motion: "thrust",
      gait: "march",
      pace: 1,
      reach: 0.6,
      attackSeconds: 0.85,
    },
    n: {
      name: "Dawn Cavalier",
      weapon: "lance",
      weaponName: "Gilded lance & armored warhorse",
      motion: "mounted_charge",
      gait: "gallop",
      pace: 1.4,
      reach: 0.88,
      attackSeconds: 0.84,
    },
    r: {
      name: "Bastion Warden",
      weapon: "warhammer",
      weaponName: "Two-handed siege hammer",
      motion: "overhead_smash",
      gait: "march",
      pace: 0.75,
      reach: 0.69,
      attackSeconds: 1.08,
    },
    b: {
      name: "Sun Prelate",
      weapon: "sun_staff",
      weaponName: "Sunburst staff",
      motion: "holy_channel",
      gait: "float",
      pace: 0.95,
      reach: 1.25,
      attackSeconds: 1.04,
    },
    q: {
      name: "Dawn Empress",
      weapon: "sunblade",
      weaponName: "Sunblade & radiant orb",
      motion: "royal_arc",
      gait: "march",
      pace: 1.06,
      reach: 0.75,
      attackSeconds: 0.98,
    },
    k: {
      name: "Crowned Sovereign",
      weapon: "greatsword",
      weaponName: "Royal greatsword",
      motion: "great_cleave",
      gait: "march",
      pace: 0.86,
      reach: 0.78,
      attackSeconds: 1.12,
    },
  },
  elves: {
    p: {
      name: "Silverwood Scout",
      weapon: "twin_daggers",
      weaponName: "Paired leaf daggers",
      motion: "dagger_dance",
      gait: "grace",
      pace: 1.35,
      reach: 0.49,
      attackSeconds: 0.72,
    },
    n: {
      name: "Windrider",
      weapon: "wind_bow",
      weaponName: "Recurve bow & silverwood steed",
      motion: "mounted_archery",
      gait: "gallop",
      pace: 1.55,
      reach: 1.35,
      attackSeconds: 0.94,
    },
    r: {
      name: "Thorn Sentinel",
      weapon: "longbow",
      weaponName: "Great thorn bow",
      motion: "bow_volley",
      gait: "grace",
      pace: 0.92,
      reach: 1.5,
      attackSeconds: 1.02,
    },
    b: {
      name: "Moon Seer",
      weapon: "moon_staff",
      weaponName: "Crescent staff",
      motion: "moon_bind",
      gait: "float",
      pace: 1.15,
      reach: 1.25,
      attackSeconds: 1.02,
    },
    q: {
      name: "Moonblade Regent",
      weapon: "moonblades",
      weaponName: "Twin crescent blades",
      motion: "crescent_dance",
      gait: "grace",
      pace: 1.35,
      reach: 0.66,
      attackSeconds: 0.89,
    },
    k: {
      name: "Silverwood High King",
      weapon: "leafblade",
      weaponName: "Leaf-forged longsword",
      motion: "leaf_riposte",
      gait: "grace",
      pace: 1.05,
      reach: 0.74,
      attackSeconds: 0.91,
    },
  },
  skeletons: {
    p: {
      name: "Grave Legionary",
      weapon: "rust_axe",
      weaponName: "Hooked rust axe & bone shield",
      motion: "axe_hook",
      gait: "rattle",
      pace: 1.02,
      reach: 0.57,
      attackSeconds: 0.91,
    },
    n: {
      name: "Grave Rider",
      weapon: "bone_spear",
      weaponName: "Bone spear & skeletal horse",
      motion: "skeletal_charge",
      gait: "bone_gallop",
      pace: 1.42,
      reach: 0.9,
      attackSeconds: 0.91,
    },
    r: {
      name: "Ossuary Colossus",
      weapon: "ossuary_maul",
      weaponName: "Ossuary maul",
      motion: "maul_crush",
      gait: "rattle",
      pace: 0.69,
      reach: 0.7,
      attackSeconds: 1.18,
    },
    b: {
      name: "Grave Oracle",
      weapon: "grave_staff",
      weaponName: "Skull-crowned grave staff",
      motion: "soul_drain",
      gait: "float",
      pace: 0.93,
      reach: 1.23,
      attackSeconds: 1.1,
    },
    q: {
      name: "Veiled Reaper",
      weapon: "soul_scythe",
      weaponName: "Soul scythe",
      motion: "reaping_arc",
      gait: "float",
      pace: 1.12,
      reach: 0.9,
      attackSeconds: 1.12,
    },
    k: {
      name: "Ossuary King",
      weapon: "executioner",
      weaponName: "Notched executioner sword",
      motion: "execution",
      gait: "rattle",
      pace: 0.81,
      reach: 0.8,
      attackSeconds: 1.2,
    },
  },
};
export const ARENAS: {
  id: ArenaStyle;
  name: string;
  description: string;
  sky: number;
  stone: number;
  dark: number;
  trim: number;
  lightSquare: number;
  darkSquare: number;
  accent: number;
}[] = [
  {
    id: "citadel",
    name: "Dawn Citadel",
    description:
      "A royal castle hall with ivory masonry, stained glass, and golden heraldry.",
    sky: 0x243443,
    stone: 0xb6b5a2,
    dark: 0x35434b,
    trim: 0xbd9d5e,
    lightSquare: BOARD_PALETTES.citadel.light,
    darkSquare: BOARD_PALETTES.citadel.dark,
    accent: 0xefce8e,
  },
  {
    id: "silverwood",
    name: "Silverwood Sanctuary",
    description:
      "An elven castle with moonlit galleries, living roots, and silver tracery.",
    sky: 0x192f35,
    stone: 0x849790,
    dark: 0x304b46,
    trim: 0xb4bd8a,
    lightSquare: BOARD_PALETTES.silverwood.light,
    darkSquare: BOARD_PALETTES.silverwood.dark,
    accent: 0xa6e9d1,
  },
  {
    id: "ossuary",
    name: "Ossuary Keep",
    description:
      "A skeletal castle keep with ribbed vaults, violet braziers, and ancient stone.",
    sky: 0x292332,
    stone: 0x777787,
    dark: 0x2a2638,
    trim: 0xab9382,
    lightSquare: BOARD_PALETTES.ossuary.light,
    darkSquare: BOARD_PALETTES.ossuary.dark,
    accent: 0xc49bd9,
  },
];
export function armyOf(faction: FactionSkin | Army): Army {
  return faction === "elves"
    ? "elves"
    : faction === "skeletons"
      ? "skeletons"
      : "royal";
}
export const TARGET_TRAITS: Record<
  PieceSymbol,
  {
    finisher: string;
    armor: number;
    height: number;
    side: number;
    delay: number;
    impulse: number;
  }
> = {
  p: {
    finisher: "center_break",
    armor: 0.25,
    height: 0.72,
    side: 0.03,
    delay: 0,
    impulse: 0.7,
  },
  n: {
    finisher: "unhorse",
    armor: 0.55,
    height: 1.08,
    side: -0.14,
    delay: 0.09,
    impulse: 1.05,
  },
  r: {
    finisher: "shield_break",
    armor: 1,
    height: 1.02,
    side: 0.1,
    delay: 0.16,
    impulse: 0.58,
  },
  b: {
    finisher: "staff_interrupt",
    armor: 0.2,
    height: 1.13,
    side: -0.09,
    delay: 0.06,
    impulse: 0.82,
  },
  q: {
    finisher: "disarm",
    armor: 0.45,
    height: 1.17,
    side: 0.17,
    delay: 0.12,
    impulse: 0.92,
  },
  k: {
    finisher: "crown_fall",
    armor: 0.85,
    height: 1.25,
    side: -0.04,
    delay: 0.2,
    impulse: 0.65,
  },
};
export interface CaptureProfile {
  id: string;
  attackerArmy: Army;
  attacker: PieceSymbol;
  defenderArmy: Army;
  defender: PieceSymbol;
  weapon: Weapon;
  motion: AttackMotion;
  finisher: string;
  seconds: number;
  windup: number;
  impact: number;
  recovery: number;
  reach: number;
  aimHeight: number;
  sidestep: number;
  impulse: number;
  armor: number;
  death: "armor_fall" | "petal_dissolve" | "bone_scatter" | "royal_kneel";
  vfx: "steel" | "sun" | "wind" | "moon" | "bone" | "soul";
  color: number;
  secondaryImpact: boolean;
}
export function captureProfile(
  attackerArmy: Army,
  attacker: PieceSymbol,
  defenderArmy: Army,
  defender: PieceSymbol,
  color: PieceColor = "w",
): CaptureProfile {
  const unit = UNIT_DESIGNS[attackerArmy][attacker],
    target = TARGET_TRAITS[defender];
  const magic = ["sun_staff", "moon_staff", "grave_staff"].includes(
    unit.weapon,
  );
  return {
    id: `${attackerArmy}/${attacker}>${defenderArmy}/${defender}`,
    attackerArmy,
    attacker,
    defenderArmy,
    defender,
    weapon: unit.weapon,
    motion: unit.motion,
    finisher: target.finisher,
    seconds: unit.attackSeconds + target.delay,
    windup: 0.26 + target.armor * 0.055,
    impact: 0.44 + target.armor * 0.04,
    recovery: 0.68,
    reach: unit.reach,
    aimHeight: target.height,
    sidestep: target.side,
    impulse: target.impulse,
    armor: target.armor,
    death:
      defender === "k"
        ? "royal_kneel"
        : defenderArmy === "skeletons"
          ? "bone_scatter"
          : defenderArmy === "elves"
            ? "petal_dissolve"
            : "armor_fall",
    vfx:
      attackerArmy === "royal"
        ? magic || attacker === "q"
          ? "sun"
          : "steel"
        : attackerArmy === "elves"
          ? magic
            ? "moon"
            : "wind"
          : magic || attacker === "q"
            ? "soul"
            : "bone",
    color:
      color === "w"
        ? attackerArmy === "elves"
          ? 0xc8f3e4
          : attackerArmy === "skeletons"
            ? 0xdddafa
            : 0xffdda0
        : attackerArmy === "elves"
          ? 0xb68cde
          : attackerArmy === "skeletons"
            ? 0xbb75dc
            : 0xd56587,
    secondaryImpact: defender === "r" || defender === "q",
  };
}

export interface CombatPose {
  wind: number;
  hit: number;
  recover: number;
  bodyYaw: number;
  bodyLean: number;
  rightX: number;
  rightZ: number;
  leftX: number;
  leftZ: number;
  lift: number;
  advance: number;
  orbit: number;
  weaponScale: number;
}
const clamp = (v: number) => Math.max(0, Math.min(1, v));
const smooth = (v: number) => {
  v = clamp(v);
  return v * v * (3 - 2 * v);
};
// A deterministic pose sampler: identical attacker/defender pairs use the same choreography.
export function sampleCombat(
  profile: CaptureProfile,
  progress: number,
): CombatPose {
  const p = clamp(progress),
    w = smooth(p / profile.windup),
    h = smooth((p - profile.windup) / (profile.impact - profile.windup)),
    r = smooth((p - profile.recovery) / (1 - profile.recovery));
  const fade = 1 - r,
    slash = Math.sin(h * Math.PI),
    pose: CombatPose = {
      wind: w,
      hit: h,
      recover: r,
      bodyYaw: 0,
      bodyLean: 0,
      rightX: 0,
      rightZ: 0,
      leftX: 0,
      leftZ: 0,
      lift: 0,
      advance: 0,
      orbit: 0,
      weaponScale: 1,
    };
  switch (profile.motion) {
    case "thrust":
      pose.bodyLean = (w * 0.12 - h * 0.31) * fade;
      pose.rightX = (-w * 0.72 - h * 0.9) * fade;
      pose.leftX = -w * 0.6 * fade;
      pose.advance = h * 0.22 * fade;
      break;
    case "mounted_charge":
    case "skeletal_charge":
      pose.bodyLean = -0.15 * w * fade;
      pose.rightX = -1.3 * w * fade;
      pose.advance = h * 0.42 * fade;
      pose.lift = Math.sin(p * Math.PI) * 0.11;
      break;
    case "overhead_smash":
    case "maul_crush":
      pose.rightX = (-2.5 * w + 1.4 * h) * fade;
      pose.leftX = (-2.1 * w + 1.15 * h) * fade;
      pose.bodyLean = (-0.15 * w + 0.24 * h) * fade;
      pose.lift = Math.sin(w * Math.PI) * 0.06;
      break;
    case "holy_channel":
    case "moon_bind":
    case "soul_drain":
      pose.rightX = -1.12 * w * fade;
      pose.leftX = -1.2 * w * fade;
      pose.leftZ = -0.6 * w * fade;
      pose.lift = Math.sin(p * Math.PI) * 0.12;
      pose.bodyYaw = Math.sin(p * Math.PI * 2) * 0.13;
      break;
    case "royal_arc":
      pose.rightX = -1.2 * w * fade;
      pose.rightZ = (1.05 * w - 2.25 * h) * fade;
      pose.bodyYaw = (-0.45 * w + 1.05 * h) * fade;
      pose.leftX = -0.6 * w * fade;
      break;
    case "great_cleave":
    case "execution":
      pose.rightX = (-2.4 * w + 1.2 * h) * fade;
      pose.leftX = -1.7 * w * fade;
      pose.bodyYaw = (-0.25 * w + 0.7 * h) * fade;
      pose.advance = h * 0.15 * fade;
      break;
    case "dagger_dance":
      pose.rightX = -1.4 * w * fade;
      pose.leftX = (-0.4 * w - 1.2 * slash) * fade;
      pose.rightZ = (-0.6 * w + 1.6 * h) * fade;
      pose.leftZ = 0.7 * slash * fade;
      pose.bodyYaw = (-0.55 * w + 1.3 * h) * fade;
      pose.orbit = slash * 0.22;
      pose.advance = slash * 0.17;
      break;
    case "mounted_archery":
    case "bow_volley":
      pose.leftX = -1.4 * w * fade;
      pose.rightX = -0.95 * w * fade;
      pose.rightZ = (-0.95 * w + 0.8 * h) * fade;
      pose.bodyYaw = -0.42 * w * fade;
      pose.advance = -slash * 0.1;
      break;
    case "crescent_dance":
      pose.rightX = -1.2 * w * fade;
      pose.leftX = -1.4 * w * fade;
      pose.rightZ = (1.2 * w - 2.8 * h) * fade;
      pose.leftZ = (-1.1 * w + 2.4 * h) * fade;
      pose.bodyYaw = (-0.6 * w + 1.5 * h) * fade;
      pose.orbit = slash * 0.28;
      pose.lift = slash * 0.05;
      break;
    case "leaf_riposte":
      pose.rightX = (-0.7 * w - 1.05 * h) * fade;
      pose.rightZ = (-0.5 * w + 1.4 * h) * fade;
      pose.bodyYaw = (-0.35 * w + 0.9 * h) * fade;
      pose.advance = slash * 0.22;
      break;
    case "axe_hook":
      pose.rightX = (-1.1 * w + 1.7 * h) * fade;
      pose.rightZ = (0.65 * w - 1.6 * h) * fade;
      pose.bodyLean = (-0.1 * w + 0.2 * h) * fade;
      pose.leftX = -0.8 * w * fade;
      break;
    case "reaping_arc":
      pose.rightX = -1.25 * w * fade;
      pose.rightZ = (-0.9 * w + 2.2 * h) * fade;
      pose.leftX = -0.7 * w * fade;
      pose.bodyYaw = (0.6 * w - 1.5 * h) * fade;
      pose.orbit = -slash * 0.18;
      break;
  }
  // Shared physical actions retain a separate performance for each unit.
  if (profile.motion === "skeletal_charge") {
    pose.bodyLean += Math.sin(p * Math.PI * 3) * 0.08 * fade;
    pose.rightZ = -0.19 * w * fade;
    pose.lift += slash * 0.055;
  }
  if (profile.motion === "maul_crush") {
    pose.bodyYaw = (-0.3 * w + 0.5 * h) * fade;
    pose.lift += slash * 0.08;
    pose.advance += h * 0.1 * fade;
  }
  if (profile.motion === "execution") {
    pose.bodyLean += (-0.2 * w + 0.26 * h) * fade;
    pose.leftZ = -0.22 * w * fade;
    pose.rightZ = 0.13 * h * fade;
  }
  if (profile.motion === "moon_bind") {
    pose.bodyYaw += Math.sin(p * Math.PI * 2) * 0.35 * fade;
    pose.leftZ -= slash * 0.45;
    pose.orbit += slash * 0.12;
  }
  if (profile.motion === "soul_drain") {
    pose.bodyLean = -0.18 * w * fade;
    pose.leftX -= slash * 0.35;
    pose.leftZ -= slash * 0.2;
    pose.lift += slash * 0.08;
  }
  if (profile.motion === "mounted_archery") {
    pose.bodyLean = -0.15 * w * fade;
    pose.bodyYaw -= 0.24 * w * fade;
    pose.lift += slash * 0.07;
  }
  pose.orbit += profile.sidestep * Math.sin(p * Math.PI);
  if (profile.finisher === "staff_interrupt")
    pose.rightZ += Math.sin(p * Math.PI) * 0.16;
  if (profile.finisher === "disarm")
    pose.leftZ -= Math.sin(p * Math.PI * 2) * 0.15;
  if (profile.finisher === "shield_break")
    pose.bodyLean += Math.sin(p * Math.PI) * 0.07;
  return pose;
}

export const homeArena = (army: Army): ArenaStyle =>
  army === "elves"
    ? "silverwood"
    : army === "skeletons"
      ? "ossuary"
      : "citadel";
