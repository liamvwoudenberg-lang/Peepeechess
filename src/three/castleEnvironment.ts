import * as THREE from "three";
import { buildCastleHall } from "./castleHall";
import type { ArenaTheme, SquareId, WeatherEffect } from "../game/types";
import { ARENAS, type ArenaStyle } from "../game/battleProfiles";
import {
  box,
  cylinder,
  sphere,
  cone,
  ring,
  mesh,
  limb,
  clothGeometry,
  batchParts,
} from "./modelGeometry";

export const SQUARE_SIZE = 1.16,
  BOARD_HALF = SQUARE_SIZE * 4;
const FILES = "abcdefgh";
export function squareToWorldPos(square: SquareId, out = new THREE.Vector3()) {
  return out.set(
    (FILES.indexOf(square[0]) - 3.5) * SQUARE_SIZE,
    0,
    (3.5 - (Number(square[1]) - 1)) * SQUARE_SIZE,
  );
}
export function arenaStyle(theme: ArenaTheme | ArenaStyle): ArenaStyle {
  return theme === "silverwood"
    ? "silverwood"
    : theme === "ossuary" || theme === "dungeon_vault"
      ? "ossuary"
      : "citadel";
}
export interface CastleArenaBuild {
  root: THREE.Group;
  clickableTiles: THREE.Object3D[];
  squareMeshes: Map<SquareId, THREE.Mesh>;
  torchLights: THREE.PointLight[];
  banners: THREE.Mesh[];
  flameCones: THREE.Mesh[];
  weatherParticles: THREE.Points | null;
  weatherVelocities: Float32Array | null;
  updateWeather: (dt: number, weather: WeatherEffect) => void;
  updateArenaTheme: (theme: ArenaTheme) => void;
  squareAtHit: (hit: THREE.Intersection) => string | null;
}
function stoneTexture() {
  const size = 128,
    data = new Uint8Array(size * size * 4);
  let seed = 41021;
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      const i = (y * size + x) * 4,
        v = 222 + (seed % 21) + Math.round(Math.sin(x * 0.16 + y * 0.03) * 2);
      data[i] = data[i + 1] = data[i + 2] = Math.min(255, v);
      data[i + 3] = 255;
    }
  const tex = new THREE.DataTexture(data, size, size);
  tex.needsUpdate = true;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  return tex;
}
function glyphAtlas() {
  if (typeof document === "undefined") return stoneTexture();
  const canvas = document.createElement("canvas");
  canvas.width = 512;
  canvas.height = 128;
  const ctx = canvas.getContext("2d")!;
  ctx.clearRect(0, 0, 512, 128);
  ctx.font = "bold 36px Georgia";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = "#e8d4a0";
  for (let i = 0; i < 8; i++) {
    ctx.fillText(FILES[i], i * 64 + 32, 32);
    ctx.fillText(String(i + 1), i * 64 + 32, 96);
  }
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}
function beam(
  parent: THREE.Object3D,
  a: THREE.Vector3,
  b: THREE.Vector3,
  r: number,
  mat: THREE.Material,
) {
  const v = b.clone().sub(a),
    m = mesh(parent, cylinder(r, r, v.length(), 8), mat);
  m.position.copy(a).add(b).multiplyScalar(0.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), v.normalize());
  return m;
}
export function buildCastleEnvironment(
  renderer: THREE.WebGLRenderer,
  shadows: boolean,
  theme: ArenaTheme = "courtyard",
): CastleArenaBuild {
  const style = arenaStyle(theme),
    palette = ARENAS.find((a) => a.id === style)!,
    root = new THREE.Group();
  root.name = palette.name;
  const tex = stoneTexture();
  tex.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
  const stone = new THREE.MeshStandardMaterial({
      color: palette.stone,
      map: tex,
      roughness: 0.83,
      metalness: 0.04,
    }),
    dark = new THREE.MeshStandardMaterial({
      color: palette.dark,
      roughness: 0.58,
      metalness: 0.18,
    }),
    trim = new THREE.MeshStandardMaterial({
      color: palette.trim,
      roughness: 0.36,
      metalness: 0.7,
    }),
    ivory = new THREE.MeshStandardMaterial({
      color: 0xd8d0b9,
      roughness: 0.7,
      metalness: 0.05,
    }),
    foliage = new THREE.MeshStandardMaterial({
      color: 0x527d68,
      roughness: 0.87,
      flatShading: true,
    }),
    leaves = new THREE.MeshStandardMaterial({
      color: 0x91b9a3,
      roughness: 0.7,
      metalness: 0.06,
      flatShading: true,
    }),
    clothLight = new THREE.MeshStandardMaterial({
      color: 0xeee6ce,
      roughness: 0.9,
      side: THREE.DoubleSide,
    }),
    clothDark = new THREE.MeshStandardMaterial({
      color: 0x51213e,
      roughness: 0.9,
      side: THREE.DoubleSide,
    }),
    glow = new THREE.MeshBasicMaterial({ color: palette.accent });
  const span = BOARD_HALF * 2;
  mesh(root, cylinder(7.8, 8.5, 0.7, 48), dark, 0, -1.04, 0);
  mesh(root, cylinder(7.55, 7.8, 0.22, 48), stone, 0, -0.59, 0);
  mesh(root, cylinder(7.58, 7.6, 0.04, 48), trim, 0, -0.46, 0);
  mesh(root, box(span + 1.05, 0.3, span + 1.05, 0.11), dark, 0, -0.28, 0);
  mesh(root, box(span + 0.72, 0.13, span + 0.72, 0.055), trim, 0, -0.1, 0);
  mesh(root, box(span + 0.43, 0.07, span + 0.43, 0.04), dark, 0, -0.005, 0);
  // A smooth inlaid board; 64 beveled tiles share a single draw call.
  const tiles = new THREE.InstancedMesh(
    box(SQUARE_SIZE * 0.993, 0.075, SQUARE_SIZE * 0.993, 0.018),
    new THREE.MeshStandardMaterial({
      map: tex,
      roughness: 0.56,
      metalness: 0.1,
    }),
    64,
  );
  tiles.name = "64 inlaid chess squares";
  tiles.receiveShadow = shadows;
  const dummy = new THREE.Object3D(),
    squareIds: string[] = [];
  for (let rank = 1; rank <= 8; rank++)
    for (let file = 0; file < 8; file++) {
      const sq = `${FILES[file]}${rank}`,
        i = squareIds.length;
      dummy.position.copy(squareToWorldPos(sq));
      dummy.position.y = 0.035;
      dummy.updateMatrix();
      tiles.setMatrixAt(i, dummy.matrix);
      tiles.setColorAt(
        i,
        new THREE.Color(
          (file + rank) % 2 === 0 ? palette.lightSquare : palette.darkSquare,
        ),
      );
      squareIds.push(sq);
    }
  tiles.userData.squareIds = squareIds;
  root.add(tiles);
  tiles.computeBoundingSphere();
  const labels = new THREE.MeshBasicMaterial({
    map: glyphAtlas(),
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
  function label(
    index: number,
    rank: boolean,
    x: number,
    z: number,
    rotation = 0,
  ) {
    const geo = new THREE.PlaneGeometry(0.23, 0.23),
      uv = geo.getAttribute("uv");
    for (let i = 0; i < uv.count; i++)
      uv.setXY(i, (index + uv.getX(i)) / 8, (uv.getY(i) + (rank ? 0 : 1)) / 2);
    const m = mesh(root, geo, labels, x, 0.052, z, -Math.PI / 2, 0, rotation);
    return m;
  }
  for (let i = 0; i < 8; i++) {
    const pos = (i - 3.5) * SQUARE_SIZE;
    label(i, false, pos, BOARD_HALF + 0.23);
    label(i, false, -pos, -BOARD_HALF - 0.23, Math.PI);
    label(i, true, -BOARD_HALF - 0.23, -pos);
    label(i, true, BOARD_HALF + 0.23, -pos, Math.PI);
  }
  // Inlaid filigree, not noisy textures inside the calculation area.
  for (const sx of [-1, 1])
    for (const sz of [-1, 1]) {
      const corner = limb(
        root,
        sx * (BOARD_HALF + 0.3),
        0.08,
        sz * (BOARD_HALF + 0.3),
        "Carved corner",
      );
      const jewel = mesh(
        corner,
        new THREE.OctahedronGeometry(0.09),
        trim,
        0,
        0,
        0,
      );
      jewel.scale.y = 0.35;
      for (let i = 0; i < 3; i++) {
        mesh(
          corner,
          box(0.11, 0.025, 0.025, 0.008),
          trim,
          -sx * (0.12 + i * 0.1),
          0,
          0,
        );
        mesh(
          corner,
          box(0.025, 0.025, 0.11, 0.008),
          trim,
          0,
          0,
          -sz * (0.12 + i * 0.1),
        );
      }
    }
  // Radial flagstones and shallow, readable steps around the playing table.
  for (let i = 0; i < 40; i++) {
    const a = (i / 40) * Math.PI * 2,
      g = limb(
        root,
        Math.sin(a) * 6.6,
        -0.385,
        Math.cos(a) * 6.6,
        "Terrace paving",
      );
    g.rotation.y = a;
    mesh(g, box(0.85, 0.08, 1.12, 0.025), stone);
    if (i % 5 === 0) mesh(g, box(0.025, 0.014, 1.0, 0.002), trim, 0, 0.05, 0);
  }
  const torchLights: THREE.PointLight[] = [],
    flameCones: THREE.Mesh[] = [],
    banners: THREE.Mesh[] = [];
  function lantern(x: number, z: number, phase: number) {
    const g = limb(root, x, -0.4, z, "Carved lantern");
    mesh(g, cylinder(0.2, 0.29, 0.2, 10), trim, 0, 0.1, 0);
    mesh(g, cylinder(0.09, 0.16, 0.9, 10), stone, 0, 0.63, 0);
    mesh(g, cylinder(0.26, 0.12, 0.18, 10), trim, 0, 1.17, 0);
    const orb = mesh(g, sphere(0.12), glow, 0, 1.37, 0);
    orb.userData.keep = true;
    orb.userData.phase = phase;
    flameCones.push(orb);
    for (let i = 0; i < 4; i++) {
      const a = (i * Math.PI) / 2;
      mesh(
        g,
        cylinder(0.014, 0.014, 0.32, 5),
        trim,
        Math.sin(a) * 0.17,
        1.39,
        Math.cos(a) * 0.17,
      );
    }
    mesh(g, cone(0.24, 0.2, 8), dark, 0, 1.67, 0);
    if (phase < 2) {
      const light = new THREE.PointLight(palette.accent, 4, 6, 2);
      light.position.set(x, 1.25, z);
      light.userData.baseIntensity = 4;
      light.userData.phase = phase;
      torchLights.push(light);
      root.add(light);
    }
  }
  for (const [i, [x, z]] of [
    [-5.9, -5.9],
    [5.9, -5.9],
    [-5.9, 5.9],
    [5.9, 5.9],
  ].entries())
    lantern(x, z, i);
  function banner(x: number, z: number, white: boolean) {
    const g = limb(root, x, -0.4, z, "Heraldic standard");
    mesh(g, cylinder(0.026, 0.044, 2.7, 8), trim, 0, 1.35, 0);
    mesh(g, cone(0.09, 0.22, 7), trim, 0, 2.8, 0);
    mesh(
      g,
      cylinder(0.018, 0.018, 0.91, 7),
      trim,
      0,
      2.5,
      0,
      0,
      0,
      Math.PI / 2,
    );
    const flag = mesh(
      g,
      clothGeometry(0.79, 1.2, style === "silverwood"),
      white ? clothLight : clothDark,
      0,
      2.47,
      0,
    );
    flag.userData.keep = true;
    banners.push(flag);
    const emblem = mesh(
      g,
      new THREE.OctahedronGeometry(0.14),
      trim,
      0,
      1.99,
      0.025,
    );
    emblem.scale.set(0.5, 1, 0.12);
  }
  banner(-6.3, -3.8, false);
  banner(6.3, 3.8, true);
  if (style === "citadel") {
    for (const sx of [-1, 1])
      for (const sz of [-1, 1]) {
        const t = limb(root, sx * 7.1, -0.5, sz * 7.1, "Ivory bastion");
        mesh(t, cylinder(0.75, 0.86, 2.5, 16), stone, 0, 1.25, 0);
        mesh(t, cylinder(0.88, 0.75, 0.18, 16), trim, 0, 2.55, 0);
        mesh(t, cylinder(0.9, 0.88, 0.23, 16), stone, 0, 2.75, 0);
        for (let i = 0; i < 8; i++) {
          const a = (i / 8) * Math.PI * 2;
          mesh(
            t,
            box(0.25, 0.35, 0.22, 0.025),
            stone,
            Math.sin(a) * 0.76,
            3.0,
            Math.cos(a) * 0.76,
          );
        }
        for (let level = 0; level < 3; level++)
          mesh(
            t,
            ring(0.78, 0.018),
            dark,
            0,
            0.6 + level * 0.7,
            0,
            Math.PI / 2,
          );
        for (const side of [-1, 1])
          mesh(
            t,
            box(0.09, 0.5, 0.035, 0.02),
            dark,
            side * 0.24,
            1.75,
            sz < 0 ? 0.75 : -0.75,
          );
      }
    for (const z of [-7.6, 7.6]) {
      for (const x of [-4.2, 0, 4.2]) {
        const g = limb(root, x, -0.4, z, "Carved arch");
        for (const sign of [-1, 1]) {
          mesh(g, box(0.23, 2.1, 0.28, 0.025), stone, sign * 0.86, 1.05, 0);
          mesh(g, box(0.4, 0.14, 0.42), trim, sign * 0.86, 1.95, 0);
        }
        mesh(g, ring(0.86, 0.13, Math.PI), stone, 0, 2.0, 0);
      }
    }
    const gardenMat = new THREE.MeshStandardMaterial({
      color: 0x526a50,
      roughness: 0.9,
    });
    for (const sx of [-1, 1])
      for (const z of [-2.3, 0, 2.3]) {
        mesh(root, box(0.7, 0.25, 1.5, 0.06), stone, sx * 7.5, -0.3, z);
        mesh(root, box(0.55, 0.36, 1.3, 0.12), gardenMat, sx * 7.5, -0.06, z);
      }
  } else if (style === "silverwood") {
    const water = new THREE.MeshStandardMaterial({
      color: 0x244b51,
      metalness: 0.36,
      roughness: 0.23,
    });
    mesh(root, cylinder(27, 27, 0.04, 64), water, 0, -1.5, 0);
    const trunks = new THREE.InstancedMesh(
        cylinder(0.13, 0.25, 4.4, 9),
        stone,
        14,
      ),
      canopy = new THREE.InstancedMesh(
        new THREE.IcosahedronGeometry(1.25, 1),
        leaves,
        28,
      );
    for (let i = 0; i < 14; i++) {
      const a = (i / 14) * Math.PI * 2 + 0.17,
        r = 8.3 + (i % 3) * 0.65;
      dummy.position.set(Math.sin(a) * r, 1.5, Math.cos(a) * r);
      dummy.rotation.set(((i % 3) - 1) * 0.08, 0, ((i % 2) - 0.5) * 0.1);
      dummy.scale.setScalar(0.85 + (i % 4) * 0.1);
      dummy.updateMatrix();
      trunks.setMatrixAt(i, dummy.matrix);
      for (let j = 0; j < 2; j++) {
        dummy.position.set(
          Math.sin(a) * r + (j ? -0.5 : 0.4),
          3.65 + j * 0.43 + (i % 3) * 0.23,
          Math.cos(a) * r,
        );
        dummy.rotation.set(0, a, 0);
        dummy.scale.set(1.6, 1, 1.25);
        dummy.updateMatrix();
        canopy.setMatrixAt(i * 2 + j, dummy.matrix);
      }
      const start = new THREE.Vector3(
          Math.sin(a) * 7.1,
          -0.3,
          Math.cos(a) * 7.1,
        ),
        end = new THREE.Vector3(
          Math.sin(a + 0.07) * r,
          0.35,
          Math.cos(a + 0.07) * r,
        );
      beam(root, start, end, 0.1, stone);
    }
    root.add(trunks, canopy);
    trunks.castShadow = shadows;
    canopy.castShadow = shadows;
    for (const side of [-1, 1]) {
      const g = limb(root, 0, -0.4, side * 7.4, "Silverwood arch");
      for (const x of [-1.3, 1.3])
        mesh(
          g,
          cylinder(0.12, 0.25, 2.4, 10),
          stone,
          x,
          1.2,
          0,
          0,
          0,
          -Math.sign(x) * 0.12,
        );
      mesh(g, ring(1.18, 0.1, Math.PI), trim, 0, 2.3, 0);
      mesh(g, new THREE.OctahedronGeometry(0.16), glow, 0, 3.49, 0);
    }
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * Math.PI * 2,
        x = Math.sin(a) * 6.9,
        z = Math.cos(a) * 6.9;
      mesh(root, cylinder(0.015, 0.02, 0.18, 6), ivory, x, -0.23, z);
      const cap = mesh(
        root,
        sphere(0.11),
        i % 2 ? leaves : foliage,
        x,
        -0.12,
        z,
      );
      cap.scale.y = 0.3;
    }
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      const ripple = mesh(
        root,
        ring(0.45 + i * 0.07, 0.012),
        new THREE.MeshBasicMaterial({
          color: 0x6bada7,
          transparent: true,
          opacity: 0.25,
        }),
        Math.sin(a) * 10,
        -1.46,
        Math.cos(a) * 10,
        -Math.PI / 2,
      );
      ripple.scale.x = 2;
    }
  } else {
    for (const z of [-7.25, 7.25])
      for (const x of [-4.1, 0, 4.1]) {
        const g = limb(root, x, -0.42, z, "Ossuary rib arch");
        for (const sign of [-1, 1]) {
          mesh(g, box(0.32, 1.8, 0.4, 0.045), dark, sign * 0.91, 0.9, 0);
          for (let i = 0; i < 3; i++)
            mesh(g, sphere(0.16), ivory, sign * 0.91, 0.65 + i * 0.4, 0);
        }
        mesh(g, ring(0.91, 0.1, Math.PI), ivory, 0, 1.8, 0);
        const skull = mesh(g, sphere(0.21), ivory, 0, 2.65, 0);
        skull.scale.z = 0.7;
        for (const sign of [-1, 1])
          mesh(g, sphere(0.055), dark, sign * 0.08, 2.67, z < 0 ? 0.15 : -0.15);
      }
    for (let i = 0; i < 18; i++) {
      const a = (i / 18) * Math.PI * 2,
        r = 6.7 + (i % 3) * 0.22,
        g = limb(root, Math.sin(a) * r, -0.4, Math.cos(a) * r, "Grave marker");
      g.rotation.y = -a;
      mesh(g, box(0.46, 0.65, 0.18, 0.055), stone, 0, 0.32, 0);
      mesh(g, box(0.05, 0.3, 0.03), trim, 0, 0.36, 0.11);
      mesh(g, box(0.2, 0.05, 0.03), trim, 0, 0.4, 0.11);
    }
    for (const sx of [-1, 1])
      for (const sz of [-1, 1]) {
        const t = limb(root, sx * 7.8, -0.6, sz * 7.8, "Broken dark spire");
        mesh(t, cylinder(0.45, 0.78, 2.8, 9), dark, 0, 1.4, 0);
        mesh(t, cone(0.45, 1.1, 6), stone, 0.06, 3.25, 0, 0, 0, sx * 0.1);
        for (let i = 0; i < 4; i++)
          mesh(t, ring(0.52, 0.035), ivory, 0, 0.6 + i * 0.55, 0, Math.PI / 2);
      }
  }
  buildCastleHall(root, style, stone, dark, trim, glow);
  root.updateMatrixWorld(true);
  const staticMeshes: THREE.Mesh[] = [];
  root.traverse((obj) => {
    if (
      obj instanceof THREE.Mesh &&
      !(obj instanceof THREE.InstancedMesh) &&
      !obj.userData.keep
    )
      staticMeshes.push(obj);
  });
  for (const m of staticMeshes) root.attach(m);
  batchParts(root);
  root.traverse((obj) => {
    if (obj instanceof THREE.Mesh && !obj.userData.keep) {
      obj.receiveShadow = shadows;
      obj.castShadow = shadows;
    }
  });
  tiles.castShadow = false;
  const motesGeo = new THREE.BufferGeometry(),
    positions = new Float32Array(32 * 3);
  for (let i = 0; i < 32; i++) {
    positions[i * 3] = Math.sin(i * 3.9) * (5.5 + (i % 3));
    positions[i * 3 + 1] = 0.2 + (i % 9) * 0.28;
    positions[i * 3 + 2] = Math.cos(i * 2.6) * (5.5 + (i % 3));
  }
  motesGeo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  const motes = new THREE.Points(
    motesGeo,
    new THREE.PointsMaterial({
      color: palette.accent,
      size: 0.025,
      transparent: true,
      opacity: 0.65,
      depthWrite: false,
    }),
  );
  root.add(motes);
  return {
    root,
    clickableTiles: [tiles],
    squareMeshes: new Map(),
    torchLights,
    banners,
    flameCones,
    weatherParticles: motes,
    weatherVelocities: null,
    squareAtHit: (hit) =>
      hit.object === tiles && hit.instanceId !== undefined
        ? squareIds[hit.instanceId]
        : null,
    updateWeather: (dt) => {
      motes.rotation.y += dt * 0.012;
      for (const b of banners)
        b.rotation.x = Math.sin(performance.now() * 0.0008 + b.id) * 0.035;
    },
    updateArenaTheme: () => {},
  };
}
