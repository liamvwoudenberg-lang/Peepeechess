import * as THREE from "three";
import type { FactionSkin, PieceColor, PieceSymbol } from "../game/types";
import {
  armyOf,
  UNIT_DESIGNS,
  type Army,
  type UnitDesign,
  type CaptureProfile,
} from "../game/battleProfiles";
import {
  box,
  cylinder,
  sphere,
  cone,
  ring,
  mesh,
  limb,
  bladeGeometry,
  clothGeometry,
  batchParts,
} from "./modelGeometry";

export function characterFootprint(type: PieceSymbol, army: Army) {
  return type === "n" ? 0.7 : type === "q" && army === "skeletons" ? 0.62 : 1;
}
export interface CharacterMaterialRig {
  faction: Army;
  primaryArmor: THREE.MeshStandardMaterial;
  secondaryCloth: THREE.MeshStandardMaterial;
  accentTrim: THREE.MeshStandardMaterial;
  weaponSteel: THREE.MeshStandardMaterial;
  arcaneCrystal: THREE.MeshStandardMaterial;
  bone: THREE.MeshStandardMaterial;
  face: THREE.MeshStandardMaterial;
  dark: THREE.MeshStandardMaterial;
}
export interface ArticulatedCharacter {
  id: string;
  type: PieceSymbol;
  color: PieceColor;
  army: Army;
  design: UnitDesign;
  root: THREE.Group;
  bodyContainer: THREE.Group;
  torsoGroup: THREE.Group;
  headGroup: THREE.Group;
  leftLegPivot: THREE.Group;
  rightLegPivot: THREE.Group;
  leftArmPivot: THREE.Group;
  rightArmPivot: THREE.Group;
  weaponGroup: THREE.Group;
  offhandGroup: THREE.Group;
  cape: THREE.Group;
  crown: THREE.Group;
  mountLegs: THREE.Group[];
  mountNeck: THREE.Group | null;
  shadowDisc: THREE.Mesh;
  dangerAuraMesh: THREE.Mesh;
  bodyParts: THREE.Group[];
  hipHeight: number;
  scale: number;
  state: "idle" | "walking" | "attacking" | "dying" | "defeated" | "guarding";
  startPos: THREE.Vector3;
  stopShortPos: THREE.Vector3;
  targetPos: THREE.Vector3;
  walkProgress: number;
  walkDuration: number;
  gaitPhase: number;
  lastStepHalfCycle: number;
  attackTimer: number;
  attackImpactFired: boolean;
  deathTimer: number;
  targetYaw: number;
  victimId?: string;
  profile?: CaptureProfile;
  onWalkComplete?: () => void;
  idleSeed: number;
  impactCount: number;
  deathOrigin: THREE.Vector3;
  isKnightLeap: boolean;
}
const material = (color: number, roughness = 0.5, metalness = 0.15) =>
  new THREE.MeshStandardMaterial({ color, roughness, metalness });
export function createFactionMaterialRigs(
  _software: boolean,
  faction: FactionSkin | Army = "royal",
): Record<PieceColor, CharacterMaterialRig> {
  const army = armyOf(faction);
  const make = (white: boolean): CharacterMaterialRig => ({
    faction: army,
    primaryArmor: material(white ? 0xf0eee3 : 0x252331, 0.3, 0.52),
    secondaryCloth: material(
      white ? 0xf9f6e9 : army === "elves" ? 0x482458 : 0x681f3c,
      0.85,
      0.02,
    ),
    accentTrim: material(
      white
        ? army === "elves"
          ? 0xc6cba5
          : 0xc6a669
        : army === "elves"
          ? 0x9877bd
          : 0xa45576,
      0.3,
      0.73,
    ),
    weaponSteel: material(white ? 0xdfe7e9 : 0x87909f, 0.25, 0.79),
    bone: material(white ? 0xe8dfc8 : 0x888099, 0.67, 0.05),
    face: material(white ? 0xe6dbc9 : 0x78657d, 0.65, 0.04),
    dark: material(white ? 0x2d3e43 : 0x12131d, 0.6, 0.08),
    arcaneCrystal: new THREE.MeshStandardMaterial({
      color: white ? 0xe1f7eb : 0xc473cf,
      emissive: white ? (army === "elves" ? 0x80d2bd : 0xd1a451) : 0x833ca6,
      emissiveIntensity: 0.7,
      roughness: 0.25,
      metalness: 0.15,
    }),
  });
  return { w: make(true), b: make(false) };
}
function sword(parent: THREE.Group, rig: CharacterMaterialRig, kind: string) {
  const long = ["greatsword", "executioner"].includes(kind),
    curved = ["leafblade", "moonblades", "sunblade", "twin_daggers"].includes(
      kind,
    );
  mesh(parent, cylinder(0.026, 0.032, 0.18, 8), rig.dark, 0, -0.04, 0);
  mesh(
    parent,
    box(long ? 0.28 : 0.19, 0.045, 0.07),
    rig.accentTrim,
    0,
    0.07,
    0,
  );
  const blade = mesh(
    parent,
    bladeGeometry(
      curved ? 0.11 : 0,
      long ? 0.72 : kind === "twin_daggers" ? 0.35 : 0.53,
      long ? 0.14 : 0.08,
    ),
    rig.weaponSteel,
    0,
    0.1,
    0,
  );
  blade.rotation.z = kind === "moonblades" ? -0.16 : 0;
  mesh(parent, sphere(0.038), rig.arcaneCrystal, 0, -0.14, 0);
  if (kind === "executioner") {
    for (let i = 0; i < 3; i++)
      mesh(
        parent,
        box(0.07, 0.025, 0.045),
        rig.dark,
        -0.045,
        0.28 + i * 0.12,
        0.02,
      );
  }
  if (kind === "sunblade")
    mesh(parent, ring(0.1, 0.012), rig.accentTrim, 0, 0.23, -0.025);
}
function staff(parent: THREE.Group, rig: CharacterMaterialRig, kind: string) {
  mesh(parent, cylinder(0.025, 0.035, 0.95, 9), rig.accentTrim, 0, 0.21, 0);
  mesh(parent, cylinder(0.038, 0.038, 0.12, 9), rig.dark, 0, -0.17, 0);
  if (kind === "sun_staff") {
    mesh(parent, ring(0.14, 0.024), rig.accentTrim, 0, 0.76, 0);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      const ray = mesh(
        parent,
        cone(0.035, 0.15, 5),
        rig.accentTrim,
        Math.sin(a) * 0.2,
        0.76 + Math.cos(a) * 0.2,
        0,
      );
      ray.rotation.z = -a;
    }
    mesh(parent, sphere(0.08), rig.arcaneCrystal, 0, 0.76, 0);
  } else if (kind === "moon_staff") {
    mesh(
      parent,
      ring(0.16, 0.029, Math.PI * 1.55),
      rig.weaponSteel,
      0,
      0.76,
      0,
      0,
      0,
      -0.85,
    );
    mesh(
      parent,
      new THREE.OctahedronGeometry(0.065),
      rig.arcaneCrystal,
      0.05,
      0.77,
      0,
    );
  } else {
    skull(parent, rig, 0.11, 0, 0.75, 0);
    mesh(
      parent,
      cone(0.03, 0.21, 5),
      rig.accentTrim,
      -0.14,
      0.78,
      0,
      0,
      0,
      -0.4,
    );
    mesh(parent, cone(0.03, 0.21, 5), rig.accentTrim, 0.14, 0.78, 0, 0, 0, 0.4);
  }
}
function bow(parent: THREE.Group, rig: CharacterMaterialRig, large = false) {
  const r = large ? 0.34 : 0.26;
  mesh(
    parent,
    ring(r, 0.025, Math.PI * 1.22),
    rig.accentTrim,
    0,
    0.2,
    0,
    0,
    0,
    -Math.PI * 0.61,
  );
  mesh(
    parent,
    cylinder(0.007, 0.007, r * 1.86, 5),
    rig.weaponSteel,
    0.085,
    0.2,
    0,
  );
  mesh(
    parent,
    cylinder(0.012, 0.012, 0.6, 6),
    rig.weaponSteel,
    0,
    0.18,
    0.07,
    0,
    0,
    Math.PI / 2,
  );
  mesh(
    parent,
    cone(0.028, 0.09, 5),
    rig.accentTrim,
    -0.34,
    0.18,
    0.07,
    0,
    0,
    Math.PI / 2,
  );
}
function skull(
  parent: THREE.Object3D,
  rig: CharacterMaterialRig,
  r: number,
  x = 0,
  y = 0,
  z = 0,
) {
  const head = mesh(parent, sphere(r), rig.bone, x, y, z);
  head.scale.set(0.9, 1.06, 0.87);
  for (const sign of [-1, 1]) {
    const socket = mesh(
      parent,
      sphere(r * 0.25),
      rig.dark,
      x + sign * r * 0.38,
      y + r * 0.11,
      z + r * 0.78,
    );
    socket.scale.set(1, 1.16, 0.5);
    mesh(
      parent,
      sphere(r * 0.095),
      rig.arcaneCrystal,
      x + sign * r * 0.38,
      y + r * 0.11,
      z + r * 0.91,
    );
  }
  mesh(
    parent,
    cone(r * 0.12, r * 0.25, 3),
    rig.dark,
    x,
    y - r * 0.18,
    z + r * 0.85,
    0,
    0,
    Math.PI,
  );
  mesh(
    parent,
    box(r * 1.1, r * 0.37, r * 0.85),
    rig.bone,
    x,
    y - r * 0.7,
    z + r * 0.18,
  );
  for (let i = -2; i <= 2; i++)
    mesh(
      parent,
      box(r * 0.12, r * 0.24, r * 0.2),
      rig.bone,
      x + i * r * 0.18,
      y - r * 0.64,
      z + r * 0.63,
    );
}
function shield(parent: THREE.Group, rig: CharacterMaterialRig, tower = false) {
  const h = tower ? 0.56 : 0.4,
    w = tower ? 0.3 : 0.26;
  mesh(parent, box(w, h, 0.07, 0.045), rig.accentTrim, 0, -0.12, 0.04);
  mesh(
    parent,
    box(w - 0.045, h - 0.045, 0.073, 0.04),
    rig.secondaryCloth,
    0,
    -0.12,
    0.085,
  );
  mesh(
    parent,
    new THREE.OctahedronGeometry(0.062),
    rig.primaryArmor,
    0,
    -0.11,
    0.14,
  );
  mesh(parent, box(0.02, h * 0.65, 0.012), rig.accentTrim, 0, -0.12, 0.13);
}
function axe(parent: THREE.Group, rig: CharacterMaterialRig, maul = false) {
  mesh(
    parent,
    cylinder(0.027, 0.036, maul ? 0.75 : 0.57, 9),
    rig.bone,
    0,
    0.16,
    0,
  );
  mesh(parent, box(0.08, 0.15, 0.075), rig.dark, 0, -0.13, 0);
  if (maul) {
    mesh(parent, box(0.38, 0.19, 0.2, 0.035), rig.primaryArmor, 0, 0.52, 0);
    for (const sign of [-1, 1])
      mesh(
        parent,
        cone(0.075, 0.16, 6),
        rig.accentTrim,
        sign * 0.24,
        0.52,
        0,
        0,
        0,
        (-sign * Math.PI) / 2,
      );
    if (rig.faction === "skeletons") skull(parent, rig, 0.075, 0, 0.53, 0.13);
  } else {
    const edge = mesh(
      parent,
      bladeGeometry(0.18, 0.32, 0.15),
      rig.weaponSteel,
      0.03,
      0.38,
      0,
    );
    edge.rotation.z = -1.35;
    mesh(parent, cone(0.035, 0.19, 6), rig.accentTrim, 0, 0.63, 0);
  }
}
function weapon(parent: THREE.Group, rig: CharacterMaterialRig, kind: string) {
  if (kind.endsWith("staff")) staff(parent, rig, kind);
  else if (kind === "longbow" || kind === "wind_bow")
    bow(parent, rig, kind === "longbow");
  else if (kind === "lance" || kind === "bone_spear") {
    mesh(
      parent,
      cylinder(0.024, 0.032, 1.0, 8),
      rig.faction === "skeletons" ? rig.bone : rig.accentTrim,
      0,
      0.31,
      0,
    );
    mesh(parent, bladeGeometry(0.025, 0.25, 0.09), rig.weaponSteel, 0, 0.83, 0);
    mesh(
      parent,
      cone(0.12, 0.16, 8),
      rig.accentTrim,
      0,
      0.03,
      0,
      Math.PI,
      0,
      0,
    );
  } else if (
    kind === "warhammer" ||
    kind === "ossuary_maul" ||
    kind === "rust_axe"
  )
    axe(parent, rig, kind !== "rust_axe");
  else if (kind === "soul_scythe") {
    mesh(parent, cylinder(0.023, 0.034, 1.12, 8), rig.bone, 0, 0.3, 0);
    mesh(
      parent,
      bladeGeometry(0.35, 0.6, 0.105),
      rig.weaponSteel,
      0,
      0.89,
      0,
      0,
      0,
      -Math.PI / 2.2,
    );
    skull(parent, rig, 0.06, 0, 0.78, 0.03);
  } else sword(parent, rig, kind);
}
function crown(
  parent: THREE.Group,
  type: PieceSymbol,
  rig: CharacterMaterialRig,
) {
  if (type === "p") {
    mesh(parent, sphere(0.105), rig.primaryArmor, 0, 0.16, -0.025);
    mesh(
      parent,
      ring(0.105, 0.012),
      rig.accentTrim,
      0,
      0.13,
      -0.025,
      Math.PI / 2,
    );
    return;
  }
  if (type === "r") {
    mesh(parent, box(0.43, 0.15, 0.37, 0.015), rig.primaryArmor, 0, 0.21, 0);
    mesh(parent, box(0.34, 0.025, 0.29, 0.005), rig.dark, 0, 0.295, 0);
    for (const x of [-0.16, 0, 0.16])
      for (const z of [-0.145, 0.145])
        mesh(
          parent,
          box(0.105, 0.15, 0.105, 0.009),
          rig.accentTrim,
          x,
          0.35,
          z,
        );
    mesh(parent, box(0.46, 0.045, 0.4, 0.01), rig.accentTrim, 0, 0.125, 0);
    return;
  }
  if (type === "b") {
    const mitre = mesh(
      parent,
      cone(0.2, 0.46, 4),
      rig.primaryArmor,
      0,
      0.32,
      0,
      0,
      Math.PI / 4,
    );
    mitre.scale.z = 0.67;
    mesh(
      parent,
      box(0.035, 0.29, 0.035),
      rig.dark,
      0.02,
      0.38,
      0.148,
      0,
      0,
      -0.28,
    );
    mesh(parent, ring(0.148, 0.018), rig.accentTrim, 0, 0.14, 0, Math.PI / 2);
    return;
  }
  if (type === "n") {
    mesh(parent, cone(0.065, 0.17, 8), rig.accentTrim, 0, 0.24, -0.025);
    return;
  }
  mesh(
    parent,
    cylinder(type === "q" ? 0.215 : 0.17, type === "q" ? 0.19 : 0.15, 0.1, 14),
    rig.accentTrim,
    0,
    0.2,
    0,
  );
  const count = type === "q" ? 5 : 4;
  for (let i = 0; i < count; i++) {
    const a = (i / count) * Math.PI * 2;
    mesh(
      parent,
      cone(type === "q" ? 0.055 : 0.04, type === "q" ? 0.25 : 0.12, 6),
      rig.accentTrim,
      Math.sin(a) * (type === "q" ? 0.18 : 0.135),
      0.32,
      Math.cos(a) * (type === "q" ? 0.18 : 0.135),
    );
    if (type === "q")
      mesh(
        parent,
        sphere(0.027),
        rig.arcaneCrystal,
        Math.sin(a) * (type === "q" ? 0.18 : 0.135),
        0.48,
        Math.cos(a) * (type === "q" ? 0.18 : 0.135),
      );
  }
  if (type === "k") {
    mesh(parent, box(0.075, 0.36, 0.065), rig.accentTrim, 0, 0.47, 0);
    mesh(parent, box(0.28, 0.065, 0.065), rig.accentTrim, 0, 0.53, 0);
  }
}
function makeHorse(parent: THREE.Group, rig: CharacterMaterialRig) {
  const legs: THREE.Group[] = [];
  const skeleton = rig.faction === "skeletons";
  const flesh = skeleton ? rig.bone : rig.primaryArmor;
  const barrel = mesh(parent, sphere(0.28), flesh, 0, 0.63, -0.02);
  barrel.scale.set(0.85, 0.88, 1.35);
  const rump = mesh(parent, sphere(0.24), flesh, 0, 0.65, -0.29);
  rump.scale.set(0.96, 1, 1.05);
  for (const x of [-0.16, 0.16])
    for (const z of [-0.27, 0.22]) {
      const leg = limb(parent, x, 0.65, z, "Horse leg");
      legs.push(leg);
      mesh(
        leg,
        cylinder(skeleton ? 0.037 : 0.066, skeleton ? 0.03 : 0.045, 0.3, 8),
        flesh,
        0,
        -0.16,
        0,
      );
      mesh(leg, sphere(0.053), rig.accentTrim, 0, -0.31, 0.02);
      mesh(leg, cylinder(0.035, 0.028, 0.25, 8), flesh, 0, -0.43, 0.03, 0.07);
      mesh(leg, box(0.11, 0.075, 0.16), rig.dark, 0, -0.57, 0.055);
      if (!skeleton)
        mesh(leg, box(0.105, 0.21, 0.09), rig.accentTrim, 0, -0.16, 0.048);
    }
  const neck = limb(parent, 0, 0.78, 0.22, "Horse neck");
  const n = mesh(
    neck,
    cylinder(0.1, 0.19, 0.48, 12),
    flesh,
    0,
    0.16,
    0.02,
    -0.45,
  );
  n.scale.z = 0.85;
  const head = mesh(neck, sphere(0.15), flesh, 0, 0.47, 0.15);
  head.scale.set(0.83, 1.04, 1.5);
  const muzzle = mesh(
    neck,
    box(0.19, 0.16, 0.34, 0.04),
    flesh,
    0,
    0.39,
    0.35,
    0.3,
  );
  muzzle.scale.z = skeleton ? 1.05 : 1;
  for (const sign of [-1, 1]) {
    mesh(
      neck,
      cone(0.045, 0.19, 7),
      flesh,
      sign * 0.07,
      0.66,
      0.09,
      0,
      0,
      sign * 0.14,
    );
    mesh(
      neck,
      sphere(0.024),
      skeleton ? rig.arcaneCrystal : rig.dark,
      sign * 0.124,
      0.5,
      0.2,
    );
    mesh(neck, sphere(0.019), rig.dark, sign * 0.072, 0.36, 0.51);
  }
  if (skeleton) {
    for (let i = 0; i < 5; i++) {
      const rib = mesh(
        parent,
        ring(0.24 - i * 0.012, 0.022, Math.PI * 1.6),
        rig.accentTrim,
        0,
        0.64,
        -0.22 + i * 0.1,
        0,
        0,
        0.62,
      );
      rib.scale.y = 0.92;
    }
    for (let i = -2; i <= 2; i++)
      mesh(neck, box(0.018, 0.05, 0.04), rig.dark, i * 0.03, 0.33, 0.49);
  } else {
    const barding = mesh(
      parent,
      clothGeometry(0.49, 0.38, rig.faction === "elves"),
      rig.secondaryCloth,
      0,
      0.79,
      -0.08,
      0,
      Math.PI / 2,
    );
    barding.scale.x = 1.25;
    mesh(parent, box(0.42, 0.06, 0.24), rig.dark, 0, 0.88, -0.12);
    mesh(neck, box(0.18, 0.28, 0.07), rig.accentTrim, 0, 0.44, 0.27, -0.3);
  }
  for (let i = 0; i < 5; i++) {
    const mane = mesh(
      neck,
      cone(0.055, 0.13, 5),
      rig.secondaryCloth,
      0,
      0.16 + i * 0.1,
      -0.11,
    );
    mane.rotation.x = -0.7;
  }
  const tail = mesh(
    parent,
    cone(0.07, 0.43, 7),
    skeleton ? rig.bone : rig.secondaryCloth,
    0,
    0.47,
    -0.53,
    0.55,
  );
  tail.rotation.z = 0.06;
  return { legs, neck };
}
export function buildArticulatedCharacter(
  id: string,
  type: PieceSymbol,
  color: PieceColor,
  rig: CharacterMaterialRig,
  castShadows: boolean,
): ArticulatedCharacter {
  const army = rig.faction,
    design = UNIT_DESIGNS[army][type],
    scale = { p: 0.76, n: 0.98, b: 0.97, r: 0.95, q: 1.04, k: 1.1 }[type];
  const root = new THREE.Group();
  root.name = `${army} ${type} ${id}`;
  root.userData = {
    silhouette: {
      p: "round-pawn",
      n: "horse-knight",
      b: "split-mitre",
      r: "battlements",
      q: "five-point-crown",
      k: "royal-cross",
    }[type],
    army,
    type,
    color,
    weapon: design.weapon,
    signature: design.motion,
  };
  const base = mesh(
    root,
    cylinder(0.34, 0.4, 0.09, 24),
    rig.primaryArmor,
    0,
    0.04,
    0,
  );
  mesh(root, cylinder(0.35, 0.36, 0.025, 24), rig.accentTrim, 0, 0.095, 0);
  mesh(root, ring(0.355, 0.011), rig.accentTrim, 0, 0.115, 0, Math.PI / 2);
  const shadowDisc = mesh(
    root,
    new THREE.CircleGeometry(0.39, 20),
    new THREE.MeshBasicMaterial({
      color: 0x10191e,
      transparent: true,
      opacity: 0.2,
      depthWrite: false,
    }),
    0,
    0.006,
    0,
    -Math.PI / 2,
  );
  const dangerAuraMesh = mesh(
    root,
    new THREE.RingGeometry(0.4, 0.45, 24),
    new THREE.MeshBasicMaterial({
      color: 0xd05d61,
      transparent: true,
      opacity: 0,
      depthWrite: false,
    }),
    0,
    0.01,
    0,
    -Math.PI / 2,
  );
  dangerAuraMesh.visible = false;
  const bodyContainer = limb(root, 0, 0.12, 0, "Body");
  bodyContainer.scale.set(
    scale * characterFootprint(type, army),
    scale,
    scale * characterFootprint(type, army),
  );
  const mounted = type === "n";
  const hipHeight = mounted ? 0.9 : 0.53;
  const torsoGroup = limb(bodyContainer, 0, hipHeight, 0, "Torso");
  if (mounted) torsoGroup.scale.setScalar(0.66);
  const width =
    type === "r" ? 0.44 : type === "k" ? 0.37 : army === "elves" ? 0.29 : 0.33;
  if (army === "skeletons") {
    mesh(torsoGroup, cylinder(0.032, 0.038, 0.42, 8), rig.bone, 0, 0.22, 0);
    for (let i = 0; i < 4; i++) {
      const rib = mesh(
        torsoGroup,
        ring(width * 0.45 - i * 0.006, 0.022, Math.PI * 1.55),
        rig.bone,
        0,
        0.35 - i * 0.065,
        0,
        0,
        0,
        0.72,
      );
      rib.scale.y = 0.7;
    }
    mesh(
      torsoGroup,
      box(width * 0.9, 0.065, 0.19),
      rig.primaryArmor,
      0,
      0.03,
      0,
    );
    mesh(
      torsoGroup,
      cone(0.035, 0.13, 5),
      rig.accentTrim,
      0,
      0.36,
      0.17,
      0,
      0,
      Math.PI,
    );
  } else {
    mesh(
      torsoGroup,
      cylinder(width * 0.57, width * 0.44, 0.42, 12),
      rig.primaryArmor,
      0,
      0.23,
      0,
    );
    const chest = mesh(
      torsoGroup,
      box(width * 0.74, 0.22, 0.055),
      rig.accentTrim,
      0,
      0.27,
      0.17,
    );
    chest.rotation.x = -0.08;
    mesh(
      torsoGroup,
      box(width * 0.59, 0.17, 0.058),
      rig.primaryArmor,
      0,
      0.28,
      0.201,
    );
    mesh(
      torsoGroup,
      new THREE.OctahedronGeometry(0.05),
      rig.arcaneCrystal,
      0,
      0.29,
      0.24,
    );
  }
  mesh(
    torsoGroup,
    cylinder(width * 0.5, width * 0.53, 0.07, 12),
    rig.accentTrim,
    0,
    0.035,
    0,
  );
  for (const sign of [-1, 1]) {
    const skirt = mesh(
      torsoGroup,
      clothGeometry(width * 0.44, 0.3, army === "elves"),
      rig.secondaryCloth,
      sign * width * 0.22,
      -0.01,
      0.12,
      0,
      0,
      -sign * 0.08,
    );
    skirt.scale.x = 1.12;
  }
  if (type === "b" || type === "q" || type === "k") {
    mesh(
      torsoGroup,
      cylinder(width * 0.45, width * 0.83, 0.58, 14),
      rig.secondaryCloth,
      0,
      -0.2,
      -0.015,
    );
    mesh(
      torsoGroup,
      cylinder(width * 0.84, width * 0.84, 0.045, 14),
      rig.accentTrim,
      0,
      -0.485,
      -0.015,
    );
  }
  if (type === "r") {
    mesh(
      torsoGroup,
      box(0.44, 0.47, 0.32, 0.025),
      rig.primaryArmor,
      0,
      -0.14,
      -0.015,
    );
    for (const y of [-0.34, -0.05])
      mesh(
        torsoGroup,
        box(0.47, 0.045, 0.35, 0.01),
        rig.accentTrim,
        0,
        y,
        -0.015,
      );
  }
  const cape = limb(torsoGroup, 0, 0.41, -0.15, "Cape");
  if (type !== "p" && type !== "n")
    mesh(
      cape,
      clothGeometry(
        width * 1.32,
        type === "q" || type === "k" ? 0.91 : 0.72,
        army === "elves",
      ),
      rig.secondaryCloth,
      0,
      0,
      0,
    );
  const leftLegPivot = limb(bodyContainer, -0.115, hipHeight, 0, "Left leg"),
    rightLegPivot = limb(bodyContainer, 0.115, hipHeight, 0, "Right leg");
  if (mounted) {
    leftLegPivot.position.x = -0.22;
    rightLegPivot.position.x = 0.22;
    leftLegPivot.rotation.x = -0.6;
    rightLegPivot.rotation.x = -0.6;
  }
  for (const leg of [leftLegPivot, rightLegPivot]) {
    mesh(
      leg,
      cylinder(
        army === "skeletons" ? 0.037 : 0.065,
        army === "skeletons" ? 0.026 : 0.05,
        0.35,
        8,
      ),
      army === "skeletons" ? rig.bone : rig.primaryArmor,
      0,
      -0.18,
      0,
    );
    mesh(leg, box(0.12, 0.09, 0.19), rig.dark, 0, -0.4, 0.04);
    mesh(leg, box(0.12, 0.12, 0.045), rig.accentTrim, 0, -0.22, 0.061);
  }
  const leftArmPivot = limb(torsoGroup, -width * 0.69, 0.41, 0, "Left arm"),
    rightArmPivot = limb(torsoGroup, width * 0.69, 0.41, 0, "Right arm");
  for (const arm of [leftArmPivot, rightArmPivot]) {
    const pauldron = mesh(
      arm,
      sphere(type === "r" ? 0.128 : 0.105),
      rig.primaryArmor,
      0,
      0,
      0,
    );
    pauldron.scale.set(1.13, 0.65, 1);
    mesh(
      arm,
      ring(0.087, 0.013, Math.PI),
      rig.accentTrim,
      0,
      0.01,
      0.035,
      Math.PI / 2,
    );
    mesh(
      arm,
      cylinder(
        army === "skeletons" ? 0.025 : 0.05,
        army === "skeletons" ? 0.02 : 0.042,
        0.28,
        8,
      ),
      army === "skeletons" ? rig.bone : rig.primaryArmor,
      0,
      -0.17,
      0,
    );
    mesh(arm, box(0.09, 0.08, 0.09), rig.accentTrim, 0, -0.32, 0.015);
  }
  const headGroup = limb(torsoGroup, 0, 0.66, 0, "Head");
  if (army === "skeletons") skull(headGroup, rig, 0.139, 0, 0.025, 0);
  else {
    const face = mesh(
      headGroup,
      sphere(0.137),
      army === "elves" ? rig.face : rig.primaryArmor,
      0,
      0.025,
      0,
    );
    face.scale.set(0.88, 1.04, 0.9);
    if (army === "elves") {
      for (const sign of [-1, 1]) {
        mesh(
          headGroup,
          cone(0.045, 0.22, 5),
          rig.face,
          sign * 0.16,
          0.06,
          0,
          0,
          0,
          -sign * 0.9,
        );
        mesh(
          headGroup,
          box(0.055, 0.018, 0.02),
          rig.dark,
          sign * 0.048,
          0.055,
          0.119,
          0,
          0,
          sign * 0.14,
        );
      }
      mesh(headGroup, cone(0.12, 0.19, 8), rig.secondaryCloth, 0, 0.17, -0.02);
    } else {
      mesh(headGroup, box(0.19, 0.025, 0.045), rig.dark, 0, 0.04, 0.112);
      mesh(headGroup, box(0.028, 0.17, 0.026), rig.accentTrim, 0, 0.015, 0.134);
      mesh(headGroup, box(0.22, 0.027, 0.04), rig.accentTrim, 0, -0.03, 0.105);
    }
  }
  const crownGroup = limb(headGroup, 0, 0, 0, "Crown");
  crown(crownGroup, type, rig);
  crownGroup.name = "Chess identity " + type;
  if (color === "w" && army === "royal" && type !== "p") {
    for (const sign of [-1, 1])
      for (let i = 0; i < 3; i++) {
        const feather = mesh(
          torsoGroup,
          cone(0.034, 0.18, 5),
          rig.accentTrim,
          sign * (width * 0.57 + 0.03 * i),
          0.43 + 0.045 * i,
          -0.03,
          0,
          0,
          -sign * 0.65,
        );
        feather.scale.z = 0.35;
      }
  }
  if (army === "elves" && type !== "n")
    for (const sign of [-1, 1])
      mesh(
        torsoGroup,
        cone(0.04, 0.18, 5),
        rig.accentTrim,
        sign * width * 0.65,
        0.47,
        0,
        0,
        0,
        -sign * 0.4,
      );
  const weaponGroup = limb(rightArmPivot, 0, -0.31, 0.055, "Weapon"),
    offhandGroup = limb(leftArmPivot, 0, -0.26, 0.08, "Offhand");
  weapon(weaponGroup, rig, design.weapon);
  if (["sword_shield", "rust_axe"].includes(design.weapon))
    shield(offhandGroup, rig, type === "r");
  else if (["twin_daggers", "moonblades"].includes(design.weapon))
    sword(offhandGroup, rig, design.weapon);
  else if (design.weapon === "sunblade")
    mesh(offhandGroup, sphere(0.09), rig.arcaneCrystal, 0, -0.04, 0.06);
  else if (type === "r") shield(offhandGroup, rig, true);
  if (type === "b") {
    weaponGroup.rotation.x = 0.05;
    offhandGroup.rotation.x = -0.4;
    mesh(
      offhandGroup,
      box(0.16, 0.21, 0.07),
      rig.secondaryCloth,
      0,
      -0.02,
      0.03,
    );
  }
  const horse = mounted ? makeHorse(bodyContainer, rig) : null;
  batchParts(root);
  root.traverse((obj) => {
    if (obj instanceof THREE.Mesh) {
      obj.castShadow = castShadows;
      obj.receiveShadow = castShadows;
    }
  });
  shadowDisc.castShadow = false;
  dangerAuraMesh.castShadow = false;
  const bodyParts = [
    headGroup,
    leftLegPivot,
    rightLegPivot,
    leftArmPivot,
    rightArmPivot,
    torsoGroup,
    crownGroup,
    weaponGroup,
  ];
  for (const group of [
    torsoGroup,
    leftLegPivot,
    rightLegPivot,
    leftArmPivot,
    rightArmPivot,
    headGroup,
    weaponGroup,
    offhandGroup,
    cape,
    crownGroup,
    ...(horse?.legs || []),
  ]) {
    group.userData.restPosition = group.position.clone();
    group.userData.restRotation = group.rotation.clone();
  }
  const idleSeed = [...id].reduce((n, c) => n + c.charCodeAt(0), 0) * 0.17;
  const initialYaw = color === "w" ? Math.PI : 0;
  root.rotation.y = initialYaw;
  return {
    id,
    type,
    color,
    army,
    design,
    root,
    bodyContainer,
    torsoGroup,
    headGroup,
    leftLegPivot,
    rightLegPivot,
    leftArmPivot,
    rightArmPivot,
    weaponGroup,
    offhandGroup,
    cape,
    crown: crownGroup,
    mountLegs: horse?.legs || [],
    mountNeck: horse?.neck || null,
    shadowDisc,
    dangerAuraMesh,
    bodyParts,
    hipHeight,
    scale,
    state: "idle",
    startPos: new THREE.Vector3(),
    stopShortPos: new THREE.Vector3(),
    targetPos: new THREE.Vector3(),
    walkProgress: 0,
    walkDuration: 0.5,
    gaitPhase: 0,
    lastStepHalfCycle: 0,
    attackTimer: 0,
    attackImpactFired: false,
    deathTimer: 0,
    targetYaw: initialYaw,
    idleSeed,
    impactCount: 0,
    deathOrigin: new THREE.Vector3(),
    isKnightLeap: false,
  };
}
export function resetCharacterPose(ch: ArticulatedCharacter) {
  for (const g of [
    ch.torsoGroup,
    ch.headGroup,
    ch.leftLegPivot,
    ch.rightLegPivot,
    ch.leftArmPivot,
    ch.rightArmPivot,
    ch.weaponGroup,
    ch.offhandGroup,
    ch.cape,
    ch.crown,
    ...ch.mountLegs,
  ]) {
    if (g.userData.restPosition) g.position.copy(g.userData.restPosition);
    if (g.userData.restRotation) g.rotation.copy(g.userData.restRotation);
    g.scale.setScalar(g === ch.torsoGroup && ch.type === "n" ? 0.66 : 1);
  }
  ch.bodyContainer.position.y = 0.12;
  ch.bodyContainer.rotation.set(0, 0, 0);
  ch.bodyContainer.scale.set(
    ch.scale * characterFootprint(ch.type, ch.army),
    ch.scale,
    ch.scale * characterFootprint(ch.type, ch.army),
  );
}
