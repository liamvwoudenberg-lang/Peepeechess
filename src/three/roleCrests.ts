import * as THREE from "three";
import { box, cylinder, ring, mesh } from "./modelGeometry";
import type { PieceSymbol } from "../game/types";
import type { CharacterMaterialRig } from "./fantasyCharacters";
const cache = new Map<string, THREE.BufferGeometry>();
function relief(key: string, shape: THREE.Shape) {
  let g = cache.get(key);
  if (!g) {
    g = new THREE.ExtrudeGeometry(shape, {
      depth: 0.025,
      bevelEnabled: true,
      bevelSegments: 1,
      bevelSize: 0.007,
      bevelThickness: 0.005,
    });
    g.rotateX(-Math.PI / 2);
    g.userData.shared = true;
    cache.set(key, g);
  }
  return g;
}
// These are sculpted helmet/crown crests, present on the SAME models in both
// cameras. Their footprints distinguish every rank from exactly 90 degrees.
export function addRoleCrest(
  parent: THREE.Group,
  type: PieceSymbol,
  rig: CharacterMaterialRig,
) {
  const y = { p: 0.225, n: 0.34, b: 0.52, r: 0.405, q: 0.445, k: 0.53 }[type];
  const crest = new THREE.Group();
  crest.name = "Overhead identity " + type;
  crest.position.y = y;
  parent.add(crest);
  if (type === "p") {
    mesh(crest, cylinder(0.102, 0.12, 0.05, 18), rig.accentTrim);
    mesh(crest, cylinder(0.075, 0.08, 0.03, 18), rig.primaryArmor, 0, 0.032, 0);
  }
  if (type === "k") {
    mesh(crest, box(0.11, 0.04, 0.45, 0.009), rig.accentTrim);
    mesh(crest, box(0.35, 0.04, 0.11, 0.009), rig.accentTrim, 0, 0, -0.07);
    mesh(crest, box(0.045, 0.045, 0.3, 0.006), rig.primaryArmor, 0, 0.02, 0.02);
  }
  if (type === "r") {
    mesh(crest, box(0.35, 0.035, 0.35, 0.01), rig.accentTrim);
    mesh(crest, box(0.23, 0.045, 0.23, 0.008), rig.dark, 0, 0.025, 0);
    for (const x of [-0.15, 0.15])
      for (const z of [-0.15, 0.15])
        mesh(
          crest,
          box(0.105, 0.085, 0.105, 0.007),
          rig.primaryArmor,
          x,
          0.045,
          z,
        );
  }
  if (type === "q") {
    const shape = new THREE.Shape();
    for (let i = 0; i < 10; i++) {
      const a = (i * Math.PI) / 5,
        r = i % 2 ? 0.132 : 0.23;
      const x = Math.sin(a) * r,
        z = Math.cos(a) * r;
      if (i === 0) shape.moveTo(x, z);
      else shape.lineTo(x, z);
    }
    shape.closePath();
    mesh(crest, relief("queen", shape), rig.accentTrim);
    mesh(crest, cylinder(0.092, 0.1, 0.035, 16), rig.primaryArmor, 0, 0.043, 0);
    mesh(
      crest,
      ring(0.105, 0.012),
      rig.arcaneCrystal,
      0,
      0.066,
      0,
      Math.PI / 2,
    );
  }
  if (type === "b") {
    const shape = new THREE.Shape();
    shape.moveTo(0, -0.255);
    shape.bezierCurveTo(0.22, -0.05, 0.17, 0.2, 0, 0.24);
    shape.bezierCurveTo(-0.17, 0.2, -0.22, -0.05, 0, -0.255);
    mesh(crest, relief("bishop", shape), rig.primaryArmor);
    mesh(
      crest,
      box(0.027, 0.025, 0.31, 0.003),
      rig.dark,
      0.02,
      0.038,
      -0.025,
      0,
      0.52,
      0,
    );
    mesh(crest, ring(0.14, 0.012), rig.accentTrim, 0, 0.04, 0.025, Math.PI / 2);
  }
  if (type === "n") {
    const shape = new THREE.Shape();
    shape.moveTo(-0.18, -0.19);
    shape.quadraticCurveTo(-0.18, 0.04, -0.02, 0.14);
    shape.lineTo(-0.16, 0.09);
    shape.lineTo(-0.26, 0.14);
    shape.lineTo(-0.19, 0.26);
    shape.lineTo(-0.09, 0.3);
    shape.lineTo(-0.04, 0.4);
    shape.lineTo(0.035, 0.31);
    shape.lineTo(0.13, 0.34);
    shape.quadraticCurveTo(0.25, 0.19, 0.23, -0.19);
    shape.closePath();
    mesh(crest, relief("knight", shape), rig.primaryArmor, 0, 0, -0.06);
    mesh(
      crest,
      cylinder(0.021, 0.021, 0.025, 8),
      rig.dark,
      -0.07,
      0.043,
      -0.275,
    );
  }
  crest.userData.role = type;
}
