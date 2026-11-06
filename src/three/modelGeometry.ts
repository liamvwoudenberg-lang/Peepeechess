import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
const cache = new Map<string, THREE.BufferGeometry>();
function geometry(key: string, create: () => THREE.BufferGeometry) {
  let geo = cache.get(key);
  if (!geo) {
    geo = create();
    geo.userData.shared = true;
    cache.set(key, geo);
  }
  return geo;
}
export const box = (w: number, h: number, d: number, bevel = 0.025) =>
  geometry(
    `b:${w}:${h}:${d}:${bevel}`,
    () =>
      new RoundedBoxGeometry(w, h, d, 1, Math.min(bevel, w / 4, h / 4, d / 4)),
  );
export const cylinder = (
  top: number,
  bottom: number,
  h: number,
  segments = 12,
) =>
  geometry(
    `c:${top}:${bottom}:${h}:${segments}`,
    () => new THREE.CylinderGeometry(top, bottom, h, segments),
  );
export const sphere = (r: number) =>
  geometry(`s:${r}`, () => new THREE.SphereGeometry(r, 12, 8));
export const cone = (r: number, h: number, segments = 10) =>
  geometry(
    `k:${r}:${h}:${segments}`,
    () => new THREE.ConeGeometry(r, h, segments),
  );
export const ring = (r: number, tube: number, arc = Math.PI * 2) =>
  geometry(
    `r:${r}:${tube}:${arc}`,
    () => new THREE.TorusGeometry(r, tube, 5, 20, arc),
  );
export function mesh(
  parent: THREE.Object3D,
  geo: THREE.BufferGeometry,
  material: THREE.Material,
  x = 0,
  y = 0,
  z = 0,
  rx = 0,
  ry = 0,
  rz = 0,
) {
  const m = new THREE.Mesh(geo, material);
  m.position.set(x, y, z);
  m.rotation.set(rx, ry, rz);
  parent.add(m);
  return m;
}
export function limb(
  parent: THREE.Object3D,
  x: number,
  y: number,
  z: number,
  name: string,
) {
  const g = new THREE.Group();
  g.name = name;
  g.position.set(x, y, z);
  parent.add(g);
  return g;
}
export function bladeGeometry(curve = 0, length = 0.55, width = 0.09) {
  return geometry(`blade:${curve}:${length}:${width}`, () => {
    const s = new THREE.Shape();
    s.moveTo(-width / 2, 0);
    s.lineTo(width / 2, 0);
    s.quadraticCurveTo(width / 2 + curve, length * 0.58, curve * 0.5, length);
    s.quadraticCurveTo(
      -width * 0.65 + curve * 0.6,
      length * 0.62,
      -width / 2,
      0,
    );
    return new THREE.ExtrudeGeometry(s, {
      depth: 0.025,
      bevelEnabled: true,
      bevelSegments: 1,
      steps: 1,
      bevelSize: 0.009,
      bevelThickness: 0.009,
    });
  });
}
export function clothGeometry(w: number, h: number, leaf = false) {
  return geometry(`cloth:${w}:${h}:${leaf}`, () => {
    const geo = new THREE.BufferGeometry();
    geo.setAttribute(
      "position",
      new THREE.Float32BufferAttribute(
        [
          -w * 0.4,
          0,
          0,
          w * 0.4,
          0,
          0,
          -w * 0.5,
          -h * 0.5,
          -0.08,
          w * 0.5,
          -h * 0.5,
          -0.08,
          leaf ? 0 : -w * 0.38,
          -h,
          -0.16,
          leaf ? 0 : w * 0.38,
          -h,
          -0.16,
        ],
        3,
      ),
    );
    geo.setIndex([0, 2, 1, 1, 2, 3, 2, 4, 3, 3, 4, 5]);
    geo.computeVertexNormals();
    return geo;
  });
}
// Bake decorations together by material without merging animated joints.
export function batchParts(group: THREE.Group) {
  for (const child of [...group.children])
    if (child instanceof THREE.Group) batchParts(child);
  const byMaterial = new Map<THREE.Material, THREE.Mesh[]>();
  for (const child of [...group.children])
    if (
      child instanceof THREE.Mesh &&
      !(child instanceof THREE.InstancedMesh) &&
      !Array.isArray(child.material) &&
      !child.userData.keep
    ) {
      const list = byMaterial.get(child.material) || [];
      list.push(child);
      byMaterial.set(child.material, list);
    }
  for (const [material, parts] of byMaterial) {
    if (parts.length < 2) continue;
    const clones = parts.map((p) => {
      p.updateMatrix();
      let geo = p.geometry.index
        ? p.geometry.toNonIndexed()
        : p.geometry.clone();
      if (!geo.getAttribute("normal")) geo.computeVertexNormals();
      if (!geo.getAttribute("uv"))
        geo.setAttribute(
          "uv",
          new THREE.BufferAttribute(
            new Float32Array(geo.getAttribute("position").count * 2),
            2,
          ),
        );
      return geo.applyMatrix4(p.matrix);
    });
    const merged = mergeGeometries(clones, false);
    for (const clone of clones) clone.dispose();
    if (!merged) continue;
    merged.userData.batched = true;
    const batched = new THREE.Mesh(merged, material);
    batched.name = "Batched sculpted detail";
    group.add(batched);
    for (const p of parts) group.remove(p);
  }
}
