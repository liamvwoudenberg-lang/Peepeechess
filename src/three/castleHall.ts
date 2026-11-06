import * as THREE from "three";
import {
  box,
  cylinder,
  cone,
  ring,
  mesh,
  limb,
  clothGeometry,
} from "./modelGeometry";
import type { ArenaStyle } from "../game/battleProfiles";
// The chess dais sits inside an open-roof castle hall. Front masonry stays low
// so the angled board remains unobstructed; all architecture is outside play.
export function buildCastleHall(
  root: THREE.Group,
  style: ArenaStyle,
  stone: THREE.Material,
  dark: THREE.Material,
  trim: THREE.Material,
  glow: THREE.Material,
) {
  const hall = limb(root, 0, 0, 0, "The castle great hall");
  hall.userData.castleHall = true;
  const pale = new THREE.MeshStandardMaterial({
      color: style === "ossuary" ? 0xb9b2aa : 0xd8d0b9,
      roughness: 0.87,
    }),
    mortar = new THREE.MeshStandardMaterial({
      color:
        style === "citadel"
          ? 0x6c7270
          : style === "silverwood"
            ? 0x3b5550
            : 0x434051,
      roughness: 0.95,
    }),
    glass = new THREE.MeshStandardMaterial({
      color:
        style === "citadel"
          ? 0x668b9c
          : style === "silverwood"
            ? 0x6da798
            : 0x866795,
      emissive:
        style === "citadel"
          ? 0x426878
          : style === "silverwood"
            ? 0x315f57
            : 0x53396a,
      emissiveIntensity: 0.5,
      roughness: 0.3,
      metalness: 0.35,
      side: THREE.DoubleSide,
    });
  mesh(hall, box(25, 0.5, 25, 0.08), dark, 0, -1.45, 0);
  const tiles = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.98,0.08,0.98),
      stone,
      24 * 24,
    ),
    dummy = new THREE.Object3D();
  tiles.name = "Castle flagstone floor";
  for (let z = 0; z < 24; z++)
    for (let x = 0; x < 24; x++) {
      dummy.position.set(x - 11.5, -1.15, z - 11.5);
      dummy.rotation.set(0, (((x + z) % 2) * Math.PI) / 2, 0);
      dummy.updateMatrix();
      const i = z * 24 + x;
      tiles.setMatrixAt(i, dummy.matrix);
      tiles.setColorAt(
        i,
        new THREE.Color().setHSL(
          style === "ossuary" ? 0.73 : 0.12,
          0.055,
          0.55 + ((x * 17 + z * 31) % 7) * 0.018,
        ),
      );
    }
  hall.add(tiles);
  const blocks = new THREE.InstancedMesh(
    new THREE.BoxGeometry(1.06,0.46,0.48),
    stone,
    3 * 20 * 11,
  );
  blocks.name = "Hand-laid castle masonry";
  let index = 0;
  for (let wall = 0; wall < 3; wall++)
    for (let row = 0; row < 11; row++)
      for (let col = 0; col < 20; col++) {
        const u = -10.45 + col * 1.1 + (row % 2) * 0.3,
          y = -0.9 + row * 0.49;
        if (wall === 0) dummy.position.set(u, y, -10.5);
        else dummy.position.set(wall === 1 ? -10.75 : 10.75, y, u);
        dummy.rotation.set(0, wall === 0 ? 0 : Math.PI / 2, 0);
        dummy.updateMatrix();
        blocks.setMatrixAt(index, dummy.matrix);
        blocks.setColorAt(
          index,
          new THREE.Color().setScalar(
            0.76 + ((col * 7 + row * 11) % 9) * 0.025,
          ),
        );
        index++;
      }
  hall.add(blocks);
  for (const x of [-10.7, 10.7]) {
    mesh(hall, box(0.7, 0.25, 22.3), trim, x, 4.42, 0);
    mesh(hall, box(0.85, 0.3, 22.5), dark, x, -0.65, 0);
  }
  mesh(hall, box(22.4, 0.25, 0.7), trim, 0, 4.42, -10.5);
  mesh(hall, box(22.4, 0.3, 0.85), dark, 0, -0.65, -10.5);
  // Buttresses, carved capitals, pointed window recesses, and glass tracery.
  for (const x of [-8, -4, 0, 4, 8]) {
    const g = limb(hall, x, -1.1, -9.85, "Gothic window and buttress");
    mesh(g, box(2.5, 3.6, 0.18, 0.02), mortar, 0, 2.75, 0);
    mesh(g, box(1.52, 2.35, 0.08, 0.01), glass, 0, 3.07, 0.11);
    mesh(g, cone(0.86, 1.1, 4), glass, 0, 4.35, 0.11, 0, Math.PI / 4);
    mesh(g, box(0.09, 3.55, 0.12), pale, 0, 3.25, 0.21);
    mesh(g, box(1.55, 0.09, 0.12), pale, 0, 3.35, 0.21);
    for (const sign of [-1, 1]) {
      mesh(g, cylinder(0.17, 0.23, 4.6, 10), pale, sign * 1.37, 2.3, 0.2);
      mesh(g, box(0.55, 0.21, 0.56, 0.03), trim, sign * 1.37, 4.45, 0.2);
      mesh(g, box(0.58, 0.25, 0.64, 0.03), dark, sign * 1.37, 0.1, 0.2);
      const arch = mesh(
        g,
        box(0.13, 1.45, 0.19),
        pale,
        sign * 0.52,
        4.45,
        0.2,
        0,
        0,
        -sign * 0.66,
      );
    }
    mesh(g, ring(0.43, 0.065), pale, 0, 4.58, 0.23);
    mesh(g, new THREE.OctahedronGeometry(0.15), glow, 0, 4.58, 0.23);
  }
  for (const side of [-1, 1])
    for (const z of [-7, -2, 3, 8]) {
      const g = limb(hall, side * 9.2, -1.1, z, "Side arcade");
      g.rotation.y = (side * Math.PI) / 2;
      for (const x of [-1, 1]) {
        mesh(g, cylinder(0.16, 0.24, 3.9, 12), pale, x, 1.95, 0);
        mesh(g, box(0.55, 0.2, 0.55), trim, x, 3.75, 0);
        mesh(g, box(0.55, 0.22, 0.65), dark, x, 0.15, 0);
      }
      mesh(g, ring(1, 0.14, Math.PI), pale, 0, 3.65, 0);
      mesh(g, box(2.5, 0.16, 0.5), trim, 0, 4.75, 0);
      const banner = mesh(
        g,
        clothGeometry(0.76, 1.8, style === "silverwood"),
        new THREE.MeshStandardMaterial({
          color:
            style === "citadel"
              ? 0x643a3a
              : style === "silverwood"
                ? 0x3d6556
                : 0x5e416a,
          roughness: 0.9,
          side: THREE.DoubleSide,
        }),
        0,
        3.75,
        0.12,
      );
      mesh(g, box(0.04, 0.46, 0.035), trim, 0, 2.94, 0.16);
      mesh(g, box(0.29, 0.04, 0.035), trim, 0, 3.04, 0.16);
    }
  // White's home throne sits at the near end; no roof hides the miniatures.
  const throne = limb(hall, 0, -1.1, 8.1, "White home throne");
  for (let i = 0; i < 3; i++)
    mesh(
      throne,
      box(3.6 - i * 0.5, 0.18, 2.2 - i * 0.25, 0.04),
      stone,
      0,
      i * 0.17,
      -i * 0.12,
    );
  mesh(throne, box(1.25, 0.25, 0.9, 0.055), trim, 0, 0.72, 0);
  mesh(throne, box(1.3, 2.45, 0.3, 0.05), pale, 0, 1.69, 0.43);
  mesh(
    throne,
    box(0.91, 1.65, 0.08, 0.025),
    new THREE.MeshStandardMaterial({
      color:
        style === "citadel"
          ? 0x8b5e54
          : style === "silverwood"
            ? 0x5b8070
            : 0x83748b,
      roughness: 0.9,
    }),
    0,
    1.7,
    0.24,
  );
  for (const s of [-1, 1]) {
    mesh(throne, box(0.18, 0.9, 1, 0.035), trim, s * 0.65, 1, 0);
    mesh(throne, cone(0.11, 0.45, 7), trim, s * 0.56, 3, 0.43);
  }
  if (style === "silverwood") {
    const vines = new THREE.MeshStandardMaterial({
        color: 0x43644b,
        roughness: 1,
      }),
      leaf = new THREE.MeshStandardMaterial({
        color: 0x799c79,
        roughness: 0.9,
      });
    for (const s of [-1, 1])
      for (let i = 0; i < 14; i++) {
        const x = s * (8.5 + Math.sin(i * 0.62) * 0.55),
          y = -0.8 + i * 0.34;
        mesh(
          hall,
          cylinder(0.055, 0.085, 0.5, 7),
          vines,
          x,
          y,
          -9.4,
          0,
          0,
          Math.sin(i) * 0.35,
        );
        mesh(
          hall,
          cone(0.16, 0.42, 5),
          leaf,
          x + s * 0.22,
          y + 0.2,
          -9.35,
          0,
          0,
          s * 0.9,
        );
      }
    for (let i = 0; i < 8; i++)
      mesh(
        throne,
        cone(0.15, 0.6, 5),
        trim,
        Math.sin((i / 8) * Math.PI * 2) * 0.55,
        2.8 + Math.cos(i) * 0.07,
        0.43,
        0,
        0,
        -Math.sin((i / 8) * Math.PI * 2) * 0.7,
      );
  } else if (style === "ossuary") {
    for (const x of [-7, -3.5, 3.5, 7])
      for (let i = 0; i < 4; i++) {
        mesh(
          hall,
          ring(0.72 + i * 0.04, 0.05, Math.PI),
          pale,
          x,
          1.7 + i * 0.55,
          -10.05,
        );
      }
    for (const s of [-1, 1])
      for (let i = 0; i < 5; i++) {
        mesh(
          throne,
          cylinder(0.045, 0.06, 0.5 + i * 0.2, 7),
          pale,
          s * (0.72 + i * 0.11),
          2.5 + i * 0.1,
          0.43,
          0,
          0,
          -s * 0.3,
        );
      }
  } else {
    mesh(throne, box(0.09, 0.58, 0.06), trim, 0, 2.24, 0.16);
    mesh(throne, box(0.4, 0.09, 0.06), trim, 0, 2.34, 0.16);
  }
  // Low entrance balustrade and two door pillars frame the castle approach.
  for (const s of [-1, 1]) {
    mesh(hall, box(5, 0.65, 0.45, 0.04), stone, s * 7.5, -0.65, 10.55);
    mesh(hall, box(5.2, 0.12, 0.65, 0.02), trim, s * 7.5, -0.28, 10.55);
    mesh(hall, box(0.7, 2.8, 0.7, 0.03), stone, s * 4.4, 0.2, 10.55);
    mesh(hall, cone(0.56, 0.9, 5), trim, s * 4.4, 2.05, 10.55);
  }
}
