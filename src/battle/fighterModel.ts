import * as THREE from "three";
import type { Army } from "../game/battleProfiles";
import type { Color, PieceSymbol } from "chess.js";
import { createFactionMaterialRigs } from "../three/fantasyCharacters";
import {
  box,
  cylinder,
  sphere,
  cone,
  ring,
  mesh,
  limb,
  batchParts,
} from "../three/modelGeometry";
import type { Fighter } from "./simulation";
export interface FighterModel {
  root: THREE.Group;
  pose: (f: Fighter, time: number) => void;
}
/** Original articulated combat figures share the collection's livery and facial language. */
export function buildFighter(
  role: PieceSymbol,
  color: Color,
  army: Army,
): FighterModel {
  const rig = createFactionMaterialRigs(false, army)[color],
    root = new THREE.Group();
  root.name = `${color} ${army} ${role} fighter`;
  const width = role === "r" ? 0.72 : role === "p" ? 0.43 : 0.54,
    body = limb(root, 0, 0, 0, "combat body");
  const torso = limb(body, 0, 0.95, 0, "torso"),
    head = limb(torso, 0, 0.71, 0, "head");
  const left = limb(torso, -width * 0.7, 0.46, 0, "left arm"),
    right = limb(torso, width * 0.7, 0.46, 0, "right arm");
  const legs = [
    limb(body, -width * 0.25, 0.82, 0, "left leg"),
    limb(body, width * 0.25, 0.82, 0, "right leg"),
  ];
  if (army === "skeletons") {
    mesh(torso, cylinder(0.045, 0.05, 0.55), rig.bone, 0, 0.26, 0);
    for (let i = 0; i < 5; i++) {
      const rib = mesh(
        torso,
        ring(width * 0.42, 0.025, Math.PI * 1.7),
        rig.bone,
        0,
        0.43 - i * 0.08,
        0,
        0,
        0,
        0.45,
      );
      rib.scale.y = 0.58;
    }
    mesh(head, sphere(0.21), rig.bone, 0, 0.05, 0);
    mesh(head, box(0.27, 0.13, 0.22), rig.bone, 0, -0.12, 0.03);
    for (const x of [-0.08, 0.08])
      mesh(head, sphere(0.057), rig.dark, x, 0.07, 0.18);
    for (let i = 0; i < 5; i++)
      mesh(
        head,
        box(0.025, 0.07, 0.025),
        rig.dark,
        (i - 2) * 0.04,
        -0.13,
        0.146,
      );
  } else {
    mesh(
      torso,
      cylinder(width * 0.48, width * 0.39, 0.58),
      rig.primaryArmor,
      0,
      0.26,
      0,
    );
    mesh(torso, box(width * 0.7, 0.32, 0.1), rig.accentTrim, 0, 0.29, 0.21);
    mesh(torso, box(width * 0.56, 0.24, 0.12), rig.primaryArmor, 0, 0.29, 0.24);
    mesh(
      head,
      sphere(0.2),
      army === "elves" ? rig.face : rig.primaryArmor,
      0,
      0.04,
      0,
    );
    if (army === "elves")
      for (const x of [-1, 1])
        mesh(
          head,
          cone(0.055, 0.3, 5),
          rig.face,
          x * 0.23,
          0.11,
          0,
          0,
          0,
          -x * 0.85,
        );
    else {
      mesh(head, box(0.3, 0.035, 0.06), rig.dark, 0, 0.08, 0.17);
      mesh(head, box(0.04, 0.25, 0.05), rig.accentTrim, 0, 0.03, 0.2);
    }
  }
  mesh(
    torso,
    cylinder(width * 0.43, width * 0.53, 0.1),
    rig.accentTrim,
    0,
    -0.04,
    0,
  );
  if (["b", "q", "k"].includes(role)) {
    mesh(
      torso,
      cylinder(width * 0.39, width * 0.7, 0.55),
      rig.secondaryCloth,
      0,
      -0.29,
      -0.02,
    );
    mesh(
      torso,
      cylinder(width * 0.71, width * 0.71, 0.04),
      rig.accentTrim,
      0,
      -0.56,
      -0.02,
    );
  }
  const cape = limb(torso, 0, 0.52, -0.18, "cape");
  if (role !== "p") {
    const c = mesh(
      cape,
      box(width * 1.05, 0.91, 0.045),
      rig.secondaryCloth,
      0,
      -0.45,
      -0.12,
      0.15,
    );
    c.rotation.z = 0.04;
  }
  for (const leg of legs) {
    mesh(
      leg,
      cylinder(army === "skeletons" ? 0.048 : 0.09, 0.065, 0.65, 8),
      army === "skeletons" ? rig.bone : rig.primaryArmor,
      0,
      -0.31,
      0,
    );
    mesh(leg, box(0.19, 0.12, 0.29), rig.dark, 0, -0.74, 0.07);
    mesh(leg, box(0.19, 0.2, 0.065), rig.accentTrim, 0, -0.47, 0.075);
  }
  for (const arm of [left, right]) {
    mesh(arm, sphere(role === "r" ? 0.2 : 0.14), rig.primaryArmor, 0, 0, 0);
    mesh(
      arm,
      cylinder(0.07, 0.055, 0.51, 8),
      army === "skeletons" ? rig.bone : rig.primaryArmor,
      0,
      -0.28,
      0,
    );
    mesh(arm, box(0.13, 0.13, 0.14), rig.accentTrim, 0, -0.56, 0);
  }
  // Persistent silhouette: round pawn, plumed knight, mitred bishop, battlement rook, crowned royals.
  if (role === "p") mesh(head, sphere(0.14), rig.accentTrim, 0, 0.22, -0.02);
  if (role === "n") {
    mesh(head, cone(0.08, 0.38, 7), rig.secondaryCloth, 0, 0.39, -0.03);
    mesh(head, box(0.26, 0.06, 0.26), rig.accentTrim, 0, 0.19, 0);
  }
  if (role === "b") {
    mesh(
      head,
      cone(0.24, 0.55, 4),
      rig.primaryArmor,
      0,
      0.37,
      0,
      0,
      Math.PI / 4,
    );
    mesh(head, box(0.045, 0.26, 0.03), rig.dark, 0.03, 0.39, 0.17, 0, 0, -0.35);
  }
  if (role === "r") {
    mesh(head, cylinder(0.27, 0.25, 0.14, 12), rig.primaryArmor, 0, 0.26, 0);
    for (let i = 0; i < 6; i++) {
      const a = (i * Math.PI) / 3;
      mesh(
        head,
        box(0.13, 0.17, 0.12),
        rig.accentTrim,
        Math.sin(a) * 0.23,
        0.38,
        Math.cos(a) * 0.23,
      );
    }
  }
  if (role === "q" || role === "k") {
    mesh(head, cylinder(0.24, 0.21, 0.12, 12), rig.accentTrim, 0, 0.26, 0);
    for (let i = 0; i < (role === "q" ? 5 : 4); i++) {
      const a = (i * Math.PI * 2) / (role === "q" ? 5 : 4);
      mesh(
        head,
        cone(0.065, 0.3, 5),
        rig.accentTrim,
        Math.sin(a) * 0.21,
        0.45,
        Math.cos(a) * 0.21,
      );
    }
  }
  if (role === "k") {
    mesh(head, box(0.07, 0.4, 0.07), rig.accentTrim, 0, 0.59, 0);
    mesh(head, box(0.28, 0.07, 0.07), rig.accentTrim, 0, 0.67, 0);
  }
  if (army === "elves")
    for (const sign of [-1, 1])
      mesh(
        torso,
        cone(0.06, 0.26, 5),
        rig.accentTrim,
        sign * width * 0.68,
        0.62,
        0,
        0,
        0,
        -sign * 0.6,
      );
  const weapon = limb(right, 0, -0.55, 0.09, "signature weapon");
  weapon.rotation.x = Math.PI / 2;
  const offhand = limb(left, 0, -0.47, 0.12, "offhand");
  const blade = (parent: THREE.Group, length: number) => {
    mesh(parent, cylinder(0.032, 0.04, 0.22, 8), rig.dark, 0, -0.02, 0);
    mesh(parent, box(0.31, 0.055, 0.07), rig.accentTrim, 0, 0.11, 0);
    mesh(
      parent,
      box(0.09, length, 0.04),
      rig.weaponSteel,
      0,
      0.15 + length / 2,
      0,
    );
    mesh(
      parent,
      cone(0.064, 0.2, 4),
      rig.weaponSteel,
      0,
      0.15 + length + 0.08,
      0,
      0,
      Math.PI / 4,
    );
  };
  if (role === "p") {
    mesh(weapon, cylinder(0.03, 0.04, 1.65, 8), rig.accentTrim, 0, 0.43, 0);
    mesh(
      weapon,
      cone(0.1, 0.37, 4),
      rig.weaponSteel,
      0,
      1.41,
      0,
      0,
      Math.PI / 4,
    );
  } else if (role === "r") {
    mesh(weapon, cylinder(0.045, 0.05, 1.0, 8), rig.dark, 0, 0.26, 0);
    mesh(weapon, box(0.62, 0.3, 0.29), rig.weaponSteel, 0, 0.8, 0);
    mesh(weapon, box(0.13, 0.34, 0.32), rig.accentTrim, 0, 0.8, 0);
  } else if (role === "b") {
    mesh(weapon, cylinder(0.035, 0.04, 1.5, 8), rig.accentTrim, 0, 0.45, 0);
    mesh(weapon, ring(0.19, 0.035), rig.accentTrim, 0, 1.28, 0);
    mesh(
      weapon,
      new THREE.OctahedronGeometry(0.13),
      rig.arcaneCrystal,
      0,
      1.28,
      0,
    );
    blade(offhand, 0.37);
    offhand.rotation.x = Math.PI / 2;
  } else {
    blade(weapon, role === "k" ? 0.95 : 0.73);
    if (role === "q") {
      blade(offhand, 0.73);
      offhand.rotation.x = Math.PI / 2;
    }
  }
  if (role === "n" || role === "r") {
    mesh(
      offhand,
      box(role === "r" ? 0.59 : 0.45, role === "r" ? 0.86 : 0.57, 0.11),
      rig.primaryArmor,
      0,
      0.04,
      0.09,
    );
    mesh(
      offhand,
      box(0.08, role === "r" ? 0.91 : 0.6, 0.15),
      rig.accentTrim,
      0,
      0.04,
      0.12,
    );
    mesh(offhand, sphere(0.095), rig.arcaneCrystal, 0, 0.06, 0.2);
  }
  const mark = mesh(
    root,
    new THREE.RingGeometry(0.38, 0.43, 24),
    new THREE.MeshBasicMaterial({
      color: color === "w" ? 0xeacb87 : 0xcf70e8,
      transparent: true,
      opacity: 0.7,
      depthWrite: false,
    }),
    0,
    0.014,
    0,
    -Math.PI / 2,
  );
  const shadow = mesh(
    root,
    new THREE.CircleGeometry(0.43, 20),
    new THREE.MeshBasicMaterial({
      color: 0x060b0a,
      transparent: true,
      opacity: 0.45,
      depthWrite: false,
    }),
    0,
    0.009,
    0,
    -Math.PI / 2,
  );
  shadow.name = "contact shadow";
  batchParts(root);
  return {
    root,
    pose(f, time) {
      root.position.set(f.x, 0, f.z);
      root.rotation.y = f.yaw;
      torso.rotation.set(0, 0, 0);
      body.rotation.set(0, 0, 0);
      body.position.y = 0;
      left.rotation.set(-0.15, 0, 0.08);
      right.rotation.set(-0.18, 0, -0.12);
      legs.forEach((l) => l.rotation.set(0, 0, 0));
      const speed = Math.hypot(f.vx, f.vz),
        walk = Math.sin(time * (8 + speed * 2));
      if (f.state === "Moving") {
        legs[0].rotation.x = walk * 0.53;
        legs[1].rotation.x = -walk * 0.53;
        body.position.y = Math.abs(walk) * 0.035;
        left.rotation.x = -walk * 0.3;
      } else body.position.y = Math.sin(time * 2.1) * 0.013;
      cape.rotation.x = Math.sin(time * 3) * 0.05 + speed * 0.025;
      if (f.state === "Blocking" || f.state === "Parrying") {
        left.rotation.x = -1.05;
        left.rotation.z = -0.3;
        right.rotation.x = -0.85;
        right.rotation.z = -0.25;
        torso.rotation.y = -0.14;
      }
      if (f.attack) {
        const a = f.attack,
          p = Math.min(1, a.time / a.duration),
          anticipation = Math.min(1, a.time / a.startup),
          strike = Math.max(0, Math.min(1, (a.time - a.startup) / 0.15));
        if (a.kind === "light") {
          right.rotation.x = -0.2 - anticipation * 0.5 + strike * 0.65;
          right.position.z = strike * 0.17;
          torso.rotation.y = Math.sin(p * Math.PI * 2) * 0.3;
          right.rotation.z = -0.25 + Math.sin(p * Math.PI) * 0.5;
        } else {
          right.rotation.x = -1.55 * anticipation + strike * 2.15;
          right.rotation.z = -0.35;
          torso.rotation.x = -0.13 * anticipation + strike * 0.25;
        }
        if (role === "q") {
          left.rotation.x = -0.5 - Math.sin(p * Math.PI * 2) * 0.7;
          left.rotation.z = -Math.sin(p * Math.PI) * 0.65;
        }
        if (role === "b" && a.kind === "heavy") {
          right.rotation.x = -1;
          left.rotation.x = -0.7;
          body.position.y = 0.06 * Math.sin(p * Math.PI);
        }
      } else right.position.z = 0;
      if (f.state === "Dodging") {
        const p = Math.min(1, f.stateTime / 0.64);
        body.position.y = 0.09 * Math.sin(p * Math.PI);
        body.rotation.x = -Math.PI * 2 * Math.min(1, f.stateTime / 0.5);
      }
      if (f.state === "Staggered") {
        torso.rotation.x = -0.23;
        torso.rotation.z = Math.sin(f.stateTime * 25) * 0.12;
      }
      if (f.state === "AbilityCasting") {
        body.position.y +=
          0.12 * Math.sin(Math.min(1, f.stateTime / 0.42) * Math.PI);
        left.rotation.x = -1.2;
        right.rotation.x = -1.1;
      }
      if (f.state === "Defeated") {
        body.rotation.z = 1.45;
        body.position.y = -0.55;
        mark.visible = false;
      } else mark.visible = true;
      rig.arcaneCrystal.emissiveIntensity = f.buff > 0 ? 1.9 : 0.65;
    },
  };
}
