import * as THREE from "three";
import { type CaptureProfile } from "../game/battleProfiles";
import { ring, cone, mesh, cylinder, sphere } from "./modelGeometry";
interface Effect {
  root: THREE.Group;
  elapsed: number;
  seconds: number;
  update: (p: number) => void;
}
export class BattleEffects {
  root = new THREE.Group();
  private effects: Effect[] = [];
  private positions = new Float32Array(96 * 3);
  private colors = new Float32Array(96 * 3);
  private particles: Array<{
    life: number;
    total: number;
    pos: THREE.Vector3;
    velocity: THREE.Vector3;
  }> = [];
  private geometry = new THREE.BufferGeometry();
  private points: THREE.Points;
  constructor() {
    for (let i = 0; i < 96; i++) {
      this.positions[i * 3 + 1] = -100;
      this.particles.push({
        life: 2,
        total: 1,
        pos: new THREE.Vector3(0, -100, 0),
        velocity: new THREE.Vector3(),
      });
    }
    this.geometry.setAttribute(
      "position",
      new THREE.BufferAttribute(this.positions, 3),
    );
    this.geometry.setAttribute(
      "color",
      new THREE.BufferAttribute(this.colors, 3),
    );
    this.points = new THREE.Points(
      this.geometry,
      new THREE.PointsMaterial({
        size: 0.045,
        vertexColors: true,
        transparent: true,
        opacity: 0.9,
        depthWrite: false,
      }),
    );
    this.points.frustumCulled = false;
    this.root.add(this.points);
  }
  private effect(
    seconds: number,
    create: (group: THREE.Group) => (p: number) => void,
  ) {
    if (this.effects.length >= 12) return;
    const root = new THREE.Group(),
      update = create(root);
    this.root.add(root);
    this.effects.push({ root, update, seconds, elapsed: 0 });
  }
  launch(
    profile: CaptureProfile,
    from: THREE.Vector3,
    to: THREE.Vector3,
    seconds = 0.18,
  ) {
    if (!["sun", "soul", "moon", "wind"].includes(profile.vfx)) return;
    const ranged =
      profile.weapon === "longbow" || profile.weapon === "wind_bow";
    this.effect(seconds, (g) => {
      const mat = new THREE.MeshBasicMaterial({
        color: profile.color,
        transparent: true,
        opacity: 0.9,
      });
      const projectile = mesh(
        g,
        ranged ? cylinder(0.012, 0.012, 0.37, 6) : sphere(0.075),
        mat,
      );
      if (ranged) {
        mesh(g, cone(0.037, 0.11, 5), mat, 0, 0.23, 0);
        g.quaternion.setFromUnitVectors(
          new THREE.Vector3(0, 1, 0),
          to.clone().sub(from).normalize(),
        );
      }
      const glow = mesh(g, ring(0.08, 0.012), mat);
      glow.rotation.x = Math.PI / 2;
      return (p) => {
        g.position.lerpVectors(from, to, p);
        projectile.rotation.y += 0.12;
        glow.scale.setScalar(0.5 + Math.sin(p * Math.PI));
        mat.opacity = 1 - p * 0.25;
      };
    });
  }
  impact(
    profile: CaptureProfile,
    target: THREE.Vector3,
    direction: THREE.Vector3,
    secondary = false,
  ) {
    const magic = ["sun", "moon", "soul"].includes(profile.vfx);
    this.burst(
      target,
      profile.color,
      secondary ? 10 : 24,
      profile.vfx === "bone",
    );
    this.effect(0.4, (g) => {
      g.position.copy(target);
      g.rotation.y = Math.atan2(direction.x, direction.z);
      const mat = new THREE.MeshBasicMaterial({
        color: profile.color,
        transparent: true,
        opacity: 0.8,
        side: THREE.DoubleSide,
        depthWrite: false,
      });
      const slash = mesh(
        g,
        ring(magic ? 0.27 : 0.25, 0.018, magic ? Math.PI * 2 : Math.PI * 1.4),
        mat,
        0,
        0,
        0,
        magic ? Math.PI / 2 : 0,
        0,
        profile.attackerArmy === "elves" ? -0.6 : 0.6,
      );
      const counter = mesh(
        g,
        ring(0.17, 0.009, Math.PI * 1.3),
        mat,
        0,
        0.05,
        0.02,
        0.4,
        0,
        -0.55,
      );
      return (p) => {
        const scale = 0.4 + p * (magic ? 2.7 : 1.8);
        slash.scale.setScalar(scale);
        slash.rotation.z += profile.attackerArmy === "skeletons" ? -0.04 : 0.05;
        counter.scale.setScalar(scale * 0.8);
        mat.opacity = (1 - p) * 0.8;
      };
    });
  }
  defeat(profile: CaptureProfile, target: THREE.Vector3) {
    this.burst(
      target,
      profile.defenderArmy === "skeletons"
        ? 0xbcb1cb
        : profile.defenderArmy === "elves"
          ? 0xaacbbb
          : 0xddd0a2,
      profile.defenderArmy === "skeletons" ? 28 : 16,
      profile.defenderArmy === "skeletons",
    );
  }
  private burst(
    origin: THREE.Vector3,
    color: number,
    count: number,
    bone = false,
  ) {
    const c = new THREE.Color(color);
    let created = 0;
    for (let i = 0; i < 96 && created < count; i++) {
      const p = this.particles[i];
      if (p.life < p.total) continue;
      const a = i * 2.399963 + created * 0.17,
        s = 0.4 + (i % 7) * 0.13;
      p.pos.copy(origin);
      p.velocity.set(Math.sin(a) * s, 0.8 + (i % 5) * 0.22, Math.cos(a) * s);
      p.life = 0;
      p.total = bone ? 0.75 : 0.45;
      this.colors[i * 3] = c.r;
      this.colors[i * 3 + 1] = c.g;
      this.colors[i * 3 + 2] = c.b;
      created++;
    }
    this.geometry.getAttribute("color").needsUpdate = true;
  }
  update(dt: number) {
    for (let i = this.effects.length - 1; i >= 0; i--) {
      const fx = this.effects[i];
      fx.elapsed += dt;
      fx.update(Math.min(1, fx.elapsed / fx.seconds));
      if (fx.elapsed >= fx.seconds) {
        this.root.remove(fx.root);
        fx.root.traverse((obj) => {
          if (obj instanceof THREE.Mesh) {
            for (const material of Array.isArray(obj.material)
              ? obj.material
              : [obj.material])
              material.dispose();
          }
        });
        this.effects.splice(i, 1);
      }
    }
    let dirty = false;
    for (let i = 0; i < 96; i++) {
      const p = this.particles[i];
      if (p.life >= p.total) continue;
      dirty = true;
      p.life += dt;
      p.velocity.y -= dt * 4;
      p.pos.addScaledVector(p.velocity, dt);
      if (p.life >= p.total) this.positions[i * 3 + 1] = -100;
      else {
        this.positions[i * 3] = p.pos.x;
        this.positions[i * 3 + 1] = Math.max(0.08, p.pos.y);
        this.positions[i * 3 + 2] = p.pos.z;
      }
    }
    if (dirty) this.geometry.getAttribute("position").needsUpdate = true;
  }
  clear() {
    const materials = new Set<THREE.Material>();
    for (const e of this.effects) {
      this.root.remove(e.root);
      e.root.traverse((obj) => {
        if (obj instanceof THREE.Mesh)
          for (const mat of Array.isArray(obj.material)
            ? obj.material
            : [obj.material])
            materials.add(mat);
      });
    }
    for (const mat of materials) mat.dispose();
    this.effects = [];
    for (let i = 0; i < 96; i++) {
      this.particles[i].life = 2;
      this.positions[i * 3 + 1] = -100;
    }
    this.geometry.getAttribute("position").needsUpdate = true;
  }
  dispose() {
    this.clear();
    this.geometry.dispose();
    (this.points.material as THREE.Material).dispose();
  }
}
