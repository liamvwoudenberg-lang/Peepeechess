import * as THREE from "three";
import type { Color } from "chess.js";
import type { Army } from "../game/battleProfiles";
import { buildFighter, type FighterModel } from "./fighterModel";
import type { CombatState } from "./simulation";
import { box, cylinder, mesh, batchParts } from "../three/modelGeometry";
export interface CameraControl {
  yaw: number;
  pitch: number;
  distance: number;
  locked: boolean;
}
export class ArenaRenderer {
  renderer: THREE.WebGLRenderer;
  scene = new THREE.Scene();
  cameras: Record<Color, THREE.PerspectiveCamera> = {
    w: new THREE.PerspectiveCamera(58, 1, 0.1, 60),
    b: new THREE.PerspectiveCamera(58, 1, 0.1, 60),
  };
  models: Record<Color, FighterModel>;
  controls: Record<Color, CameraControl> = {
    w: { yaw: 0, pitch: 0.23, distance: 4.1, locked: true },
    b: { yaw: Math.PI, pitch: 0.23, distance: 4.1, locked: true },
  };
  disposed = false;
  private width = 0;
  private height = 0;
  private desired = new THREE.Vector3();
  private look = new THREE.Vector3();
  private initialized = false;
  private fx: THREE.Mesh;
  private lastEvent = 0;
  private fxTime = -10;
  private fxColor: Color = "w";
  constructor(
    public mount: HTMLElement,
    combat: CombatState,
    armies: Record<Color, Army>,
    public views: Color[],
    light: boolean,
  ) {
    this.renderer = new THREE.WebGLRenderer({
      antialias: !light,
      powerPreference: "low-power",
      alpha: false,
    });
    this.renderer.setPixelRatio(
      Math.min(window.devicePixelRatio || 1, light ? 0.8 : 1.5),
    );
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.25;
    this.renderer.autoClear = false;
    this.renderer.info.autoReset = false;
    this.renderer.domElement.setAttribute(
      "aria-label",
      "Third-person Battle Chess arena",
    );
    this.renderer.domElement.addEventListener(
      "webglcontextlost",
      this.contextLost,
    );
    mount.appendChild(this.renderer.domElement);
    this.scene.background = new THREE.Color(0x161b23);
    this.scene.fog = new THREE.Fog(0x161b23, 14, 35);
    this.scene.add(new THREE.HemisphereLight(0xc4d8ff, 0x42362d, 2.35));
    const sun = new THREE.DirectionalLight(0xffe0ae, 3.0);
    sun.position.set(3, 8, -4);
    this.scene.add(sun);
    const rim = new THREE.DirectionalLight(0xaaa1ff, 1.8);
    rim.position.set(-4, 4, 5);
    this.scene.add(rim);
    const arena = new THREE.Group(),
      stone = new THREE.MeshStandardMaterial({
        color:
          armies.w === "elves"
            ? 0x576961
            : armies.w === "skeletons"
              ? 0x5e5869
              : 0x77786d,
        roughness: 0.94,
      }),
      edge = new THREE.MeshStandardMaterial({
        color: 0x353c46,
        roughness: 0.85,
      }),
      trim = new THREE.MeshStandardMaterial({
        color: 0x9a8154,
        metalness: 0.35,
        roughness: 0.5,
      });
    const floor = new THREE.InstancedMesh(
        new THREE.BoxGeometry(0.97, 0.16, 0.97),
        stone,
        225,
      ),
      matrix = new THREE.Matrix4();
    for (let z = 0; z < 15; z++)
      for (let x = 0; x < 15; x++) {
        matrix.makeTranslation(x - 7, -0.09, z - 7);
        floor.setMatrixAt(z * 15 + x, matrix);
        floor.setColorAt(
          z * 15 + x,
          new THREE.Color((x + z) % 2 ? 0xc4c8bc : 0x979d9c),
        );
      }
    floor.instanceMatrix.needsUpdate = true;
    arena.add(floor);
    const masonry = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.96, 0.46, 0.44),
      new THREE.MeshStandardMaterial({
        color: armies.w === "skeletons" ? 0x4c4657 : 0x4c5657,
        roughness: 0.98,
      }),
      4 * 9 * 16,
    );
    let brick = 0;
    for (let wall = 0; wall < 4; wall++)
      for (let row = 0; row < 9; row++)
        for (let column = 0; column < 16; column++) {
          const along = column - 7.5 + (row % 2) * 0.25;
          matrix.makeRotationY(wall % 2 ? Math.PI / 2 : 0);
          matrix.setPosition(
            wall % 2 ? (wall === 1 ? 8.15 : -8.15) : along,
            0.24 + row * 0.48,
            wall % 2 ? along : wall === 0 ? 8.15 : -8.15,
          );
          masonry.setMatrixAt(brick, matrix);
          masonry.setColorAt(
            brick,
            new THREE.Color().setScalar(
              0.72 + ((column * 7 + row * 3 + wall) % 9) * 0.025,
            ),
          );
          brick++;
        }
    masonry.instanceMatrix.needsUpdate = true;
    arena.add(masonry);
    const gate = new THREE.MeshStandardMaterial({
      color: 0x151d23,
      roughness: 0.8,
      metalness: 0.3,
    });
    mesh(arena, box(2.05, 2.9, 0.08), gate, 0, 1.45, 7.87);
    for (let i = 0; i < 7; i++)
      mesh(arena, box(0.045, 2.85, 0.07), trim, (i - 3) * 0.29, 1.45, 7.8);
    mesh(
      arena,
      new THREE.TorusGeometry(1.07, 0.09, 6, 24, Math.PI),
      trim,
      0,
      2.45,
      7.78,
    );
    for (const sign of [-1, 1]) {
      mesh(arena, box(15, 0.85, 0.45), edge, 0, 0.4, sign * 7.5);
      mesh(arena, box(0.45, 0.85, 15), edge, sign * 7.5, 0.4, 0);
      mesh(arena, box(15, 0.09, 0.5), trim, 0, 0.85, sign * 7.5);
      mesh(arena, box(0.5, 0.09, 15), trim, sign * 7.5, 0.85, 0);
      for (const at of [-6, -3, 0, 3, 6]) {
        mesh(arena, cylinder(0.24, 0.31, 3.8, 8), edge, at, 1.9, sign * 7.9);
        mesh(arena, cylinder(0.37, 0.37, 0.18, 8), trim, at, 3.8, sign * 7.9);
        mesh(
          arena,
          box(0.9, 1.5, 0.05),
          new THREE.MeshStandardMaterial({
            color:
              armies.w === "elves"
                ? 0x345b47
                : armies.w === "skeletons"
                  ? 0x513050
                  : 0x7a3433,
            roughness: 1,
          }),
          at,
          2.7,
          sign * 7.66,
        );
      }
      for (const at of [-6, 0, 6]) {
        mesh(arena, cylinder(0.25, 0.33, 3.8, 8), edge, sign * 7.9, 1.9, at);
        mesh(
          arena,
          box(0.12, 0.35, 0.12),
          new THREE.MeshBasicMaterial({ color: 0xffc56e }),
          sign * 7.15,
          1.8,
          at,
        );
      }
    }
    mesh(
      arena,
      new THREE.RingGeometry(2.9, 2.94, 64),
      trim,
      0,
      0.006,
      0,
      -Math.PI / 2,
    );
    batchParts(arena);
    this.scene.add(arena);
    this.models = {
      w: buildFighter(combat.fighters.w.role, "w", armies.w),
      b: buildFighter(combat.fighters.b.role, "b", armies.b),
    };
    this.scene.add(this.models.w.root, this.models.b.root);
    this.fx = mesh(
      this.scene,
      new THREE.TorusGeometry(0.45, 0.025, 5, 24),
      new THREE.MeshBasicMaterial({
        color: 0xeed198,
        transparent: true,
        opacity: 0,
      }),
      0,
      1,
      0,
    );
    if (light) {
      const simplified = new Map<THREE.Material, THREE.Material>();
      const simple = (material: THREE.Material) => {
        if (!(material instanceof THREE.MeshStandardMaterial)) return material;
        let fast = simplified.get(material);
        if (!fast) {
          fast = new THREE.MeshLambertMaterial({
            color: material.color,
            emissive: material.emissive,
            emissiveIntensity: material.emissiveIntensity,
            transparent: material.transparent,
            opacity: material.opacity,
            side: material.side,
          });
          simplified.set(material, fast);
        }
        return fast;
      };
      this.scene.traverse((object) => {
        if (object instanceof THREE.Mesh)
          object.material = Array.isArray(object.material)
            ? object.material.map(simple)
            : simple(object.material);
      });
      simplified.forEach((_fast, original) => original.dispose());
    }
  }
  private contextLost = (e: Event) => {
    e.preventDefault();
    this.mount.dispatchEvent(new CustomEvent("battle-context-lost"));
  };
  render(s: CombatState, dt: number) {
    if (this.disposed) return;
    const width = Math.max(1, this.mount.clientWidth),
      height = Math.max(1, this.mount.clientHeight),
      canvas = this.renderer.domElement;
    if (this.width !== width || this.height !== height) {
      this.width = width;
      this.height = height;
      this.renderer.setSize(width, height);
    }
    for (const color of ["w", "b"] as Color[])
      this.models[color].pose(s.fighters[color], s.time);
    const event = s.events[s.events.length - 1];
    if (event && event.id !== this.lastEvent) {
      this.lastEvent = event.id;
      this.fxTime = s.time;
      this.fxColor =
        event.type === "hit" || event.type === "guardbreak"
          ? event.target
          : event.actor;
    }
    const flash = 1 - (s.time - this.fxTime) / 0.28;
    this.fx.visible = flash > 0;
    const target = s.fighters[this.fxColor];
    this.fx.position.set(target.x, 1.1, target.z);
    this.fx.scale.setScalar(1.7 - flash);
    (this.fx.material as THREE.MeshBasicMaterial).opacity = Math.max(0, flash);
    this.renderer.setScissorTest(false);
    this.renderer.setViewport(0, 0, width, height);
    this.renderer.clear();
    this.renderer.info.reset();
    this.renderer.setScissorTest(true);
    this.views.forEach((color, index) => {
      const f = s.fighters[color],
        enemy = s.fighters[color === "w" ? "b" : "w"],
        cam = this.cameras[color],
        control = this.controls[color],
        stacked = this.views.length === 2 && width < height,
        viewWidth = stacked ? width : width / this.views.length,
        viewHeight = stacked ? height / 2 : height;
      if (control.locked) {
        const targetYaw = Math.atan2(enemy.x - f.x, enemy.z - f.z),
          delta = Math.atan2(
            Math.sin(targetYaw - control.yaw),
            Math.cos(targetYaw - control.yaw),
          );
        control.yaw += delta * (1 - Math.exp(-8 * Math.min(0.1, dt)));
      }
      const distance = THREE.MathUtils.clamp(
        control.distance +
          Math.max(0, Math.hypot(enemy.x - f.x, enemy.z - f.z) - 4) * 0.12,
        2.4,
        5.5,
      );
      this.desired.set(
        f.x - Math.sin(control.yaw) * distance + Math.cos(control.yaw) * 1.3,
        1.95 + Math.sin(control.pitch) * distance,
        f.z - Math.cos(control.yaw) * distance - Math.sin(control.yaw) * 1.3,
      );
      // The arena is convex and its architecture sits outside these walls: a clamped camera segment cannot cross stone.
      this.desired.x = THREE.MathUtils.clamp(this.desired.x, -7.05, 7.05);
      this.desired.z = THREE.MathUtils.clamp(this.desired.z, -7.05, 7.05);
      this.desired.y = THREE.MathUtils.clamp(this.desired.y, 1.4, 5.5);
      if (!this.initialized) cam.position.copy(this.desired);
      else
        cam.position.lerp(this.desired, 1 - Math.exp(-12 * Math.min(0.1, dt)));
      this.look.set(
        f.x + (control.locked ? (enemy.x - f.x) * 0.18 : Math.sin(control.yaw)),
        1.15,
        f.z + (control.locked ? (enemy.z - f.z) * 0.18 : Math.cos(control.yaw)),
      );
      cam.lookAt(this.look);
      cam.aspect = viewWidth / viewHeight;
      cam.updateProjectionMatrix();
      const vx = stacked ? 0 : index * viewWidth,
        vy = stacked ? (1 - index) * viewHeight : 0;
      this.renderer.setViewport(vx, vy, viewWidth, viewHeight);
      this.renderer.setScissor(vx, vy, viewWidth, viewHeight);
      this.renderer.render(this.scene, cam);
    });
    this.initialized = true;
    this.mount.dataset.drawCalls = String(this.renderer.info.render.calls);
    this.mount.dataset.fighters = "2";
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.renderer.domElement.removeEventListener(
      "webglcontextlost",
      this.contextLost,
    );
    const materials = new Set<THREE.Material>(),
      geometries = new Set<THREE.BufferGeometry>();
    this.scene.traverse((o) => {
      if (o instanceof THREE.Mesh) {
        if (!o.geometry.userData.shared) geometries.add(o.geometry);
        for (const m of Array.isArray(o.material) ? o.material : [o.material])
          materials.add(m);
      }
    });
    materials.forEach((m) => m.dispose());
    geometries.forEach((g) => g.dispose());
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    this.renderer.domElement.remove();
    this.scene.clear();
  }
}
