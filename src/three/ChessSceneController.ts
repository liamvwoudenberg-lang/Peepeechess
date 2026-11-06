import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import {
  buildArticulatedCharacter,
  characterFootprint,
  createFactionMaterialRigs,
  resetCharacterPose,
  type ArticulatedCharacter,
  type CharacterMaterialRig,
} from "./fantasyCharacters";
import {
  buildCastleEnvironment,
  squareToWorldPos,
  arenaStyle,
  BOARD_HALF,
  type CastleArenaBuild,
} from "./castleEnvironment";
import { BattleEffects } from "./BattleEffects";
import {
  ARENAS,
  armyOf,
  captureProfile,
  sampleCombat,
  type Army,
  type CaptureProfile,
} from "../game/battleProfiles";
import { battleAudio } from "../game/battleAudio";
import type {
  ArenaTheme,
  FactionSkin,
  MoveAnimationEvent,
  PieceColor,
  PieceInstance,
  PieceSymbol,
  SquareId,
} from "../game/types";

export interface ChessSceneCallbacks {
  onSquareClick: (square: SquareId) => void;
  onSquareHover?: (square: SquareId | null) => void;
}
export interface AnimationOptions {
  mode: "off" | "brief" | "cinematic";
  reducedMotion: boolean;
  sound: boolean;
  competitive: boolean;
}
export class ChessSceneController {
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private camera: THREE.PerspectiveCamera | THREE.OrthographicCamera;
  private perspectiveCamera: THREE.PerspectiveCamera;
  private overheadCamera = new THREE.OrthographicCamera(
    -4.92,
    4.92,
    4.92,
    -4.92,
    0.1,
    80,
  );
  private viewMode: "overhead" | "angled" = "angled";
  private controls: OrbitControls;
  private arena: CastleArenaBuild;
  private rigs: Record<PieceColor, CharacterMaterialRig>;
  private characters = new Map<string, ArticulatedCharacter>();
  private victims: ArticulatedCharacter[] = [];
  private effects = new BattleEffects();
  private logicalPieces: PieceInstance[] = [];
  private frame = 0;
  private disposed = false;
  private resize: ResizeObserver;
  private previousTime = performance.now();
  private elapsed = 0;
  private statsTime = performance.now();
  private frames = 0;
  private fps = 60;
  private software = false;
  private options: AnimationOptions = {
    mode: "cinematic",
    reducedMotion: false,
    sound: true,
    competitive: false,
  };
  private selected: THREE.Mesh;
  private lastFrom: THREE.Mesh;
  private lastTo: THREE.Mesh;
  private hover: THREE.Mesh;
  private legalGroup = new THREE.Group();
  private ray = new THREE.Raycaster();
  private pointer = new THREE.Vector2();
  private pointerDown = { x: 0, y: 0 };
  private orientation: PieceColor = "w";
  private fullCamera = true;
  private cameraGoal = new THREE.Vector3();
  private targetGoal = new THREE.Vector3();
  private cameraMoving = false;
  private contextLost = false;
  private environmentTexture: THREE.Texture | null = null;
  private lastEvent = "";
  private animationsPlayed = 0;
  private lastCapture: string | null = null;
  private moveGeneration = 0;
  constructor(
    private container: HTMLElement,
    private callbacks: { current: ChessSceneCallbacks },
    theme: ArenaTheme = "courtyard",
    faction: FactionSkin = "high_crusaders",
    _weather = "clear",
  ) {
    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: false,
      powerPreference: "high-performance",
    });
    const gl = this.renderer.getContext(),
      ext = gl.getExtension("WEBGL_debug_renderer_info"),
      gpu = String(
        gl.getParameter(ext ? ext.UNMASKED_RENDERER_WEBGL : gl.RENDERER),
      );
    this.software = /SwiftShader|llvmpipe|softpipe|Software/i.test(gpu);
    this.renderer.setPixelRatio(
      this.software ? 0.8 : Math.min(devicePixelRatio || 1, 1.6),
    );
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.17;
    this.renderer.shadowMap.enabled = !this.software;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    const palette = ARENAS.find((a) => a.id === arenaStyle(theme))!;
    this.scene.background = new THREE.Color(palette.sky);
    this.scene.fog = new THREE.Fog(palette.sky, 22, 65);
    this.camera = new THREE.PerspectiveCamera(39, 1, 0.1, 100);
    this.perspectiveCamera = this.camera;
    this.camera.position.set(0, 12.8, 13);
    this.camera.lookAt(0, 0.2, 0);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = !this.software;
    this.controls.dampingFactor = 0.08;
    this.controls.enablePan = false;
    this.controls.minDistance = 7;
    this.controls.maxDistance = 24;
    this.controls.minPolarAngle = 0.15;
    this.controls.maxPolarAngle = 1.35;
    this.controls.target.set(0, 0.2, 0);
    this.controls.addEventListener("start", () => (this.cameraMoving = false));
    const sky = new THREE.HemisphereLight(0xe3eaf3, 0x535044, 2.1);
    this.scene.add(sky);
    const sun = new THREE.DirectionalLight(0xffe8c4, 3.1);
    sun.position.set(-6, 12, 9);
    sun.castShadow = !this.software;
    if (sun.castShadow) {
      sun.shadow.mapSize.set(1024, 1024);
      Object.assign(sun.shadow.camera, {
        left: -7,
        right: 7,
        top: 7,
        bottom: -7,
        near: 1,
        far: 28,
      });
      sun.shadow.bias = -0.0004;
      sun.shadow.normalBias = 0.035;
    }
    this.scene.add(sun);
    const rim = new THREE.DirectionalLight(
      palette.id === "ossuary" ? 0xc5a1ed : 0xb6d8e2,
      2.1,
    );
    rim.position.set(6, 8, -7);
    this.scene.add(rim);
    if (!this.software) {
      const generator = new THREE.PMREMGenerator(this.renderer);
      this.environmentTexture = generator.fromScene(
        new RoomEnvironment(),
        0.05,
      ).texture;
      this.scene.environment = this.environmentTexture;
      generator.dispose();
    }
    this.arena = buildCastleEnvironment(this.renderer, !this.software, theme);
    this.scene.add(this.arena.root, this.effects.root);
    this.rigs = createFactionMaterialRigs(this.software, faction);
    const ringGeo = new THREE.RingGeometry(0.37, 0.43, 32);
    ringGeo.rotateX(-Math.PI / 2);
    const marker = (color: number) =>
      new THREE.Mesh(
        ringGeo,
        new THREE.MeshBasicMaterial({
          color,
          transparent: true,
          opacity: 0.85,
          depthWrite: false,
        }),
      );
    this.selected = marker(0xf7d780);
    this.hover = marker(0xe3ead7);
    const plate = new THREE.PlaneGeometry(1.13, 1.13);
    plate.rotateX(-Math.PI / 2);
    const pm = new THREE.MeshBasicMaterial({
      color: 0xe3c678,
      transparent: true,
      opacity: 0.25,
      depthWrite: false,
    });
    this.lastFrom = new THREE.Mesh(plate, pm);
    this.lastTo = new THREE.Mesh(plate, pm);
    for (const m of [this.selected, this.hover, this.lastFrom, this.lastTo]) {
      m.visible = false;
      m.position.y = 0.085;
      this.scene.add(m);
    }
    this.scene.add(this.legalGroup);
    this.container.appendChild(this.renderer.domElement);
    this.renderer.domElement.dataset.testid = "chess-3d-canvas";
    this.renderer.domElement.addEventListener("pointerdown", this.down);
    this.renderer.domElement.addEventListener("pointerup", this.up);
    this.renderer.domElement.addEventListener("pointermove", this.over);
    this.renderer.domElement.addEventListener("webglcontextlost", this.lost);
    this.resize = new ResizeObserver(() => this.fit());
    this.resize.observe(container);
    this.fit();
    this.setFullBoardView("w");
    this.tick();
  }
  private fit() {
    const r = this.container.getBoundingClientRect();
    const aspect = Math.max(1, r.width) / Math.max(1, r.height);
    if (this.camera instanceof THREE.PerspectiveCamera)
      this.camera.aspect = aspect;
    else {
      this.camera.left = -4.92 * Math.max(1, aspect);
      this.camera.right = -this.camera.left;
      this.camera.top = 4.92 * Math.max(1, 1 / aspect);
      this.camera.bottom = -this.camera.top;
    }
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(Math.max(1, r.width), Math.max(1, r.height));
    if (this.fullCamera) this.setFullBoardView(this.orientation);
  }
  private down = (e: PointerEvent) => {
    this.pointerDown = { x: e.clientX, y: e.clientY };
    if (this.options.sound) battleAudio.unlock();
  };
  private up = (e: PointerEvent) => {
    if (
      Math.hypot(
        e.clientX - this.pointerDown.x,
        e.clientY - this.pointerDown.y,
      ) > 7
    )
      return;
    const sq = this.pick(e.clientX, e.clientY);
    if (sq) this.callbacks.current.onSquareClick(sq);
  };
  private over = (e: PointerEvent) => {
    const sq = this.pick(e.clientX, e.clientY);
    this.hover.visible = Boolean(sq);
    if (sq) {
      this.hover.position.copy(squareToWorldPos(sq));
      this.hover.position.y = 0.083;
    }
    this.renderer.domElement.style.cursor = sq ? "pointer" : "grab";
  };
  private lost = (e: Event) => {
    e.preventDefault();
    this.contextLost = true;
  };
  private pick(x: number, y: number) {
    const r = this.renderer.domElement.getBoundingClientRect();
    this.pointer.set(
      ((x - r.left) / r.width) * 2 - 1,
      (-(y - r.top) / r.height) * 2 + 1,
    );
    this.ray.setFromCamera(this.pointer, this.camera);
    const hit = this.ray.intersectObjects(this.arena.clickableTiles, false)[0];
    return hit ? this.arena.squareAtHit(hit) : null;
  }
  setTitleOrbitMode(_enabled: boolean) {}
  setFullBoardView(color: PieceColor) {
    this.orientation = color;
    this.fullCamera = true;
    if (this.viewMode === "overhead") {
      this.setBoardView("overhead", color);
      return;
    }
    const extra = Math.max(1, 1 / this.perspectiveCamera.aspect);
    this.cameraGoal.set(
      0,
      12.8 * extra,
      (color === "w" ? 13.2 : -13.2) * extra,
    );
    this.targetGoal.set(0, 0.15, 0);
    this.cameraMoving = true;
  }
  setBoardView(mode: "overhead" | "angled", color: PieceColor) {
    this.viewMode = mode;
    this.orientation = color;
    this.fullCamera = true;
    if (mode === "overhead") {
      this.camera = this.overheadCamera;
      this.camera.up.set(0, 0, color === "w" ? -1 : 1);
      this.camera.position.set(0, 18, 0);
      this.camera.lookAt(0, 0, 0);
      this.controls.enabled = false;
      this.cameraMoving = false;
    } else {
      this.camera = this.perspectiveCamera;
      this.camera.up.set(0, 1, 0);
      this.controls.object = this.camera;
      this.controls.enabled = true;
      this.controls.minDistance = 7;
      this.controls.maxDistance = 24;
      this.controls.target.set(0, 0.15, 0);
      this.setFullBoardView(color);
    }
    this.camera.updateProjectionMatrix();
  }
  setDuelView() {
    this.viewMode = "angled";
    this.camera = this.perspectiveCamera;
    this.controls.object = this.camera;
    this.controls.enabled = true;
    this.fullCamera = false;
    this.cameraGoal.set(3.6, 3.0, 4.5);
    this.targetGoal.set(0, 0.7, 0);
    this.cameraMoving = true;
    this.controls.minDistance = 3.8;
    this.controls.maxDistance = 11;
  }
  setCameraPreset(_preset: string, color: PieceColor = "w") {
    this.setFullBoardView(color);
  }
  setAnimationOptions(options: AnimationOptions) {
    this.options = options;
    battleAudio.setEnabled(options.sound);
    if (options.mode === "off" || options.reducedMotion) this.settle();
  }
  setArmies(white: Army, black: Army) {
    if (this.rigs.w.faction === white && this.rigs.b.faction === black) return;
    this.settle();
    const old = [this.rigs.w, this.rigs.b],
      wr = createFactionMaterialRigs(this.software, white),
      br = createFactionMaterialRigs(this.software, black);
    this.rigs = { w: wr.w, b: br.b };
    for (const rig of [wr.b, br.w])
      for (const value of Object.values(rig))
        if (value instanceof THREE.Material) value.dispose();
    for (const ch of this.characters.values()) this.removeCharacter(ch);
    this.characters.clear();
    const pieces = this.logicalPieces;
    this.logicalPieces = [];
    this.syncBoardPieces(pieces, null);
    for (const rig of old)
      for (const value of Object.values(rig))
        if (value instanceof THREE.Material) value.dispose();
  }
  private create(p: PieceInstance) {
    const ch = buildArticulatedCharacter(
      p.id,
      p.type,
      p.color,
      this.rigs[p.color],
      !this.software,
    );
    ch.root.position.copy(squareToWorldPos(p.square));
    ch.root.position.y = 0.075;
    ch.targetPos.copy(ch.root.position);
    this.scene.add(ch.root);
    this.characters.set(p.id, ch);
    return ch;
  }
  private removeCharacter(ch: ArticulatedCharacter) {
    this.scene.remove(ch.root);
    ch.root.traverse((obj) => {
      if (obj instanceof THREE.Mesh && !obj.geometry.userData.shared)
        obj.geometry.dispose();
    });
    for (const mesh of [ch.shadowDisc, ch.dangerAuraMesh]) {
      for (const mat of Array.isArray(mesh.material)
        ? mesh.material
        : [mesh.material])
        mat.dispose();
    }
  }
  private settle() {
    for (const victim of this.victims) this.removeCharacter(victim);
    this.victims = [];
    this.effects.clear();
    for (const p of this.logicalPieces) {
      let ch = this.characters.get(p.id);
      if (ch && ch.type !== p.type) {
        this.removeCharacter(ch);
        this.characters.delete(p.id);
        ch = undefined;
      }
      if (!ch) ch = this.create(p);
      ch.root.position.copy(squareToWorldPos(p.square));
      ch.root.position.y = 0.075;
      ch.targetPos.copy(ch.root.position);
      ch.root.rotation.set(0, p.color === "w" ? Math.PI : 0, 0);
      ch.targetYaw = ch.root.rotation.y;
      ch.state = "idle";
      ch.profile = undefined;
      ch.victimId = undefined;
      ch.onWalkComplete = undefined;
      resetCharacterPose(ch);
    }
    for (const [id, ch] of this.characters)
      if (!this.logicalPieces.some((p) => p.id === id)) {
        this.removeCharacter(ch);
        this.characters.delete(id);
      }
  }
  syncBoardPieces(pieces: PieceInstance[], event?: MoveAnimationEvent | null) {
    if (event && this.lastEvent === event.id) return;
    this.settle();
    this.logicalPieces = pieces.map((p) => ({ ...p }));
    if (!event || this.options.mode === "off" || this.options.reducedMotion) {
      this.settle();
      if (event) {
        this.lastEvent = event.id;
        this.showLast(event);
        const profile = event.capturedPieceType
          ? captureProfile(
              this.rigs[event.color].faction,
              event.pieceType,
              this.rigs[event.color === "w" ? "b" : "w"].faction,
              event.capturedPieceType,
              event.color,
            )
          : null;
        if (profile) this.lastCapture = profile.id;
        if (this.options.sound) {
          if (profile) {
            battleAudio.impact(profile);
            battleAudio.defeat(profile);
          } else
            battleAudio.step(this.rigs[event.color].faction, event.pieceType);
        }
      }
      return;
    }
    this.lastEvent = event.id;
    this.animationsPlayed++;
    this.moveGeneration++;
    this.showLast(event);
    let mover = this.characters.get(event.pieceId);
    if (!mover) {
      this.settle();
      return;
    }
    mover.startPos.copy(mover.root.position);
    mover.targetPos.copy(squareToWorldPos(event.to));
    mover.targetPos.y = 0.075;
    const vector = mover.targetPos.clone().sub(mover.startPos),
      distance = vector.length();
    const direction = vector.clone().normalize();
    mover.targetYaw = Math.atan2(direction.x, direction.z);
    mover.walkProgress = 0;
    mover.gaitPhase = 0;
    mover.lastStepHalfCycle = -1;
    mover.impactCount = 0;
    mover.attackImpactFired = false;
    const quick = this.options.mode === "brief" || this.options.competitive;
    mover.walkDuration = quick
      ? 0.16
      : Math.min(0.85, Math.max(0.32, distance / (5 * mover.design.pace)));
    mover.isKnightLeap = event.pieceType === "n";
    const victim = event.capturedPieceId
      ? this.characters.get(event.capturedPieceId)
      : undefined;
    if (victim) {
      const strikeVector = victim.root.position.clone().sub(mover.startPos),
        strikeDistance = strikeVector.length(),
        strikeDirection = strikeVector.normalize();
      mover.targetYaw = Math.atan2(strikeDirection.x, strikeDirection.z);
      this.characters.delete(victim.id);
      this.victims.push(victim);
      victim.state = "guarding";
      victim.targetYaw = Math.atan2(-strikeDirection.x, -strikeDirection.z);
      victim.deathOrigin.copy(victim.root.position);
      mover.victimId = victim.id;
      mover.profile = captureProfile(
        mover.army,
        mover.type,
        victim.army,
        victim.type,
        mover.color,
      );
      this.lastCapture = mover.profile.id;
      const reach = Math.min(strikeDistance * 0.8, mover.profile.reach);
      mover.stopShortPos
        .copy(victim.root.position)
        .addScaledVector(strikeDirection, -reach);
      mover.stopShortPos.y = 0.075;
    } else {
      mover.stopShortPos.copy(mover.targetPos);
      mover.profile = undefined;
      mover.victimId = undefined;
    }
    const generation = this.moveGeneration,
      role = event.promotedTo;
    mover.onWalkComplete = () => {
      if (generation !== this.moveGeneration) return;
      if (role && mover!.type !== role) {
        const pos = mover!.root.position.clone();
        this.removeCharacter(mover!);
        this.characters.delete(mover!.id);
        const p = pieces.find((p) => p.id === mover!.id);
        if (p) {
          const promoted = this.create(p);
          promoted.root.position.copy(pos);
          if (this.options.sound) battleAudio.promote(promoted.army, pos.x / 6);
        }
      }
      if (event.isCheckmate) this.checkmate(event.color === "w" ? "b" : "w");
    };
    mover.state = "walking";
    if (event.rookCastleMove) {
      const rook = this.characters.get(event.rookCastleMove.pieceId);
      if (rook) {
        rook.startPos.copy(rook.root.position);
        rook.targetPos.copy(squareToWorldPos(event.rookCastleMove.to));
        rook.targetPos.y = 0.075;
        rook.stopShortPos.copy(rook.targetPos);
        rook.walkDuration = mover.walkDuration;
        rook.walkProgress = 0;
        rook.targetYaw = Math.atan2(
          rook.targetPos.x - rook.startPos.x,
          rook.targetPos.z - rook.startPos.z,
        );
        rook.state = "walking";
        rook.victimId = undefined;
        rook.profile = undefined;
      }
    }
  }
  private showLast(event: MoveAnimationEvent) {
    this.lastFrom.position.copy(squareToWorldPos(event.from));
    this.lastTo.position.copy(squareToWorldPos(event.to));
    this.lastFrom.position.y = this.lastTo.position.y = 0.083;
    this.lastFrom.visible = this.lastTo.visible = true;
  }
  private checkmate(color: PieceColor) {
    const king = [...this.characters.values()].find(
      (c) => c.color === color && c.type === "k",
    );
    if (king) {
      king.state = "defeated";
      king.deathTimer = 0;
      king.profile = captureProfile(
        this.rigs[color === "w" ? "b" : "w"].faction,
        "k",
        king.army,
        "k",
        color === "w" ? "b" : "w",
      );
      if (this.options.sound) battleAudio.defeat(king.profile);
    }
  }
  setSelectionAndLegalMoves(
    sq: SquareId | null,
    targets: Array<{ to: SquareId; isCapture: boolean }>,
  ) {
    this.selected.visible = Boolean(sq);
    if (sq) {
      this.selected.position.copy(squareToWorldPos(sq));
      this.selected.position.y = 0.086;
    }
    for (const obj of [...this.legalGroup.children]) {
      this.legalGroup.remove(obj);
      if (obj instanceof THREE.Mesh) {
        obj.geometry.dispose();
        (obj.material as THREE.Material).dispose();
      }
    }
    for (const target of targets) {
      const geo = target.isCapture
        ? new THREE.RingGeometry(0.37, 0.43, 24)
        : new THREE.CircleGeometry(0.12, 16);
      geo.rotateX(-Math.PI / 2);
      const m = new THREE.Mesh(
        geo,
        new THREE.MeshBasicMaterial({
          color: 0xe9d296,
          transparent: true,
          opacity: 0.8,
          depthWrite: false,
        }),
      );
      m.position.copy(squareToWorldPos(target.to));
      m.position.y = 0.087;
      this.legalGroup.add(m);
    }
  }
  previewCapture(
    attacker: PieceSymbol,
    defender: PieceSymbol,
    white: Army,
    black: Army,
    sequence: number,
  ) {
    this.setArmies(white, black);
    const from = { p: "d4", n: "c4", b: "c3", r: "e2", q: "b2", k: "d4" }[
      attacker
    ];
    const attackerId = `preview_w_${attacker}`,
      defenderId = `preview_b_${defender}`;
    this.syncBoardPieces(
      [
        { id: attackerId, type: attacker, color: "w", square: from },
        { id: defenderId, type: defender, color: "b", square: "e5" },
      ],
      null,
    );
    this.syncBoardPieces(
      [{ id: attackerId, type: attacker, color: "w", square: "e5" }],
      {
        id: `showcase-${sequence}`,
        pieceId: attackerId,
        pieceType: attacker,
        color: "w",
        from,
        to: "e5",
        capturedPieceId: defenderId,
        capturedPieceType: defender,
        capturedSquare: "e5",
        isCheck: false,
        isCheckmate: false,
        san: "preview",
      },
    );
    this.setDuelView();
  }
  getPerformanceStats() {
    return {
      fps: this.fps,
      pixelRatio: this.renderer.getPixelRatio(),
      isSoftwareGl: this.software,
      contextLost: this.contextLost,
      drawCalls: this.renderer.info.render.calls,
      triangles: this.renderer.info.render.triangles,
      animationsPlayed: this.animationsPlayed,
      lastCapture: this.lastCapture,
      activeAnimations: [...this.characters.values()].filter(
        (c) => c.state === "walking" || c.state === "attacking",
      ).length,
      characters: this.characters.size,
      victims: this.victims.length,
    };
  }
  private finishMove(ch: ArticulatedCharacter) {
    ch.root.position.copy(ch.targetPos);
    ch.targetYaw = ch.color === "w" ? Math.PI : 0;
    ch.state = "idle";
    ch.victimId = undefined;
    resetCharacterPose(ch);
    const callback = ch.onWalkComplete;
    ch.onWalkComplete = undefined;
    callback?.();
  }
  private update(ch: ArticulatedCharacter, dt: number) {
    resetCharacterPose(ch);
    let yawDiff = ch.targetYaw - ch.root.rotation.y;
    yawDiff = Math.atan2(Math.sin(yawDiff), Math.cos(yawDiff));
    ch.root.rotation.y += yawDiff * (1 - Math.exp(-dt * 14));
    if (ch.state === "idle" || ch.state === "guarding") {
      const breath = this.options.reducedMotion
        ? 0
        : Math.sin(this.elapsed * 1.8 + ch.idleSeed);
      ch.torsoGroup.position.y +=
        breath * (ch.army === "skeletons" ? 0.003 : 0.008);
      ch.headGroup.rotation.y = breath * 0.025;
      ch.cape.rotation.x = this.options.reducedMotion
        ? 0
        : Math.sin(this.elapsed * 1.5 + ch.idleSeed) * 0.025;
      if (ch.state === "guarding") {
        ch.leftArmPivot.rotation.x = -0.6;
        ch.rightArmPivot.rotation.x = -0.25;
      }
      return;
    }
    if (ch.state === "walking") {
      ch.walkProgress = Math.min(1, ch.walkProgress + dt / ch.walkDuration);
      const t =
        ch.walkProgress < 0.5
          ? 2 * ch.walkProgress * ch.walkProgress
          : 1 - Math.pow(-2 * ch.walkProgress + 2, 2) / 2;
      ch.root.position.lerpVectors(ch.startPos, ch.stopShortPos, t);
      const stride =
        ch.design.gait === "grace"
          ? 0.42
          : ch.design.gait === "rattle"
            ? 0.49
            : 0.56;
      ch.gaitPhase += dt * ch.design.pace * (ch.type === "n" ? 17 : 13);
      const step = Math.sin(ch.gaitPhase);
      ch.leftLegPivot.rotation.x += step * stride;
      ch.rightLegPivot.rotation.x -= step * stride;
      ch.leftArmPivot.rotation.x -= step * 0.19;
      ch.rightArmPivot.rotation.x += step * 0.15;
      ch.torsoGroup.rotation.z = step * (ch.army === "elves" ? 0.018 : 0.035);
      ch.cape.rotation.x = -0.1 - Math.abs(step) * 0.05;
      if (ch.design.gait === "float") {
        ch.leftLegPivot.rotation.x = 0.09;
        ch.rightLegPivot.rotation.x = 0.09;
        ch.bodyContainer.position.y +=
          0.09 + Math.sin(ch.walkProgress * Math.PI) * 0.05;
      } else if (ch.type === "n") {
        for (let i = 0; i < ch.mountLegs.length; i++)
          ch.mountLegs[i].rotation.x +=
            Math.sin(ch.gaitPhase + (i < 2 ? 0 : Math.PI) + (i % 2) * 0.9) *
            0.42;
        ch.bodyContainer.position.y += Math.abs(Math.sin(ch.gaitPhase)) * 0.045;
        ch.torsoGroup.rotation.x = -0.08;
        ch.root.position.x += Math.sin(ch.walkProgress * Math.PI) * 0.17; // A shallow, readable knight arc.
      } else
        ch.bodyContainer.position.y +=
          Math.abs(Math.cos(ch.gaitPhase)) *
          (ch.army === "elves" ? 0.016 : 0.035);
      const half = Math.floor(ch.gaitPhase / Math.PI);
      if (half !== ch.lastStepHalfCycle && this.options.sound) {
        ch.lastStepHalfCycle = half;
        battleAudio.step(ch.army, ch.type, ch.root.position.x / 7);
      }
      if (ch.walkProgress >= 1) {
        if (ch.profile && ch.victimId) {
          ch.state = "attacking";
          ch.attackTimer = 0;
          if (this.options.sound)
            battleAudio.windup(ch.profile, ch.root.position.x / 7);
        } else this.finishMove(ch);
      }
      return;
    }
    if (ch.state === "attacking" && ch.profile) {
      const profile = ch.profile,
        seconds =
          this.options.competitive || this.options.mode === "brief"
            ? 0.32
            : profile.seconds;
      ch.attackTimer += dt;
      const p = Math.min(1, ch.attackTimer / seconds),
        pose = sampleCombat(profile, p);
      const victim = this.victims.find((v) => v.id === ch.victimId);
      const direction = (victim?.deathOrigin || ch.targetPos)
          .clone()
          .sub(ch.stopShortPos)
          .normalize(),
        side = new THREE.Vector3(direction.z, 0, -direction.x);
      ch.root.position
        .copy(ch.stopShortPos)
        .addScaledVector(direction, pose.advance)
        .addScaledVector(side, pose.orbit);
      ch.root.position.lerp(ch.targetPos, pose.recover);
      ch.torsoGroup.rotation.y += pose.bodyYaw;
      ch.torsoGroup.rotation.x += pose.bodyLean;
      ch.rightArmPivot.rotation.x += pose.rightX;
      ch.rightArmPivot.rotation.z += pose.rightZ;
      ch.leftArmPivot.rotation.x += pose.leftX;
      ch.leftArmPivot.rotation.z += pose.leftZ;
      ch.bodyContainer.position.y += pose.lift;
      ch.cape.rotation.x = -0.1 - Math.abs(pose.bodyYaw) * 0.12;
      const wrist = pose.wind * (1 - pose.recover),
        ranged = profile.weapon === "longbow" || profile.weapon === "wind_bow",
        magic = profile.weapon.endsWith("staff");
      const aim = magic ? 0.3 : ranged ? 0 : -0.4 + pose.hit * 2.1;
      ch.weaponGroup.rotation.x += (aim - pose.rightX - pose.bodyLean) * wrist;
      if (ranged) ch.weaponGroup.rotation.y += (Math.PI / 2) * wrist;
      if (profile.weapon === "twin_daggers" || profile.weapon === "moonblades")
        ch.offhandGroup.rotation.x +=
          (aim - pose.leftX - pose.bodyLean) * wrist;
      if (victim) {
        if (ch.impactCount === 0 && p >= profile.windup) {
          const from = ch.weaponGroup.getWorldPosition(new THREE.Vector3());
          from.y += 0.25;
          const target = victim.root.position.clone();
          target.y += profile.aimHeight;
          this.effects.launch(
            profile,
            from,
            target,
            Math.max(0.04, (profile.impact - profile.windup) * seconds),
          );
          ch.impactCount = 1;
        }
        if (!ch.attackImpactFired && p >= profile.impact) {
          ch.attackImpactFired = true;
          victim.state = "dying";
          victim.profile = profile;
          victim.deathTimer = 0;
          victim.deathOrigin.copy(victim.root.position);
          const target = victim.root.position.clone();
          target.y += profile.aimHeight;
          this.effects.impact(profile, target, direction);
          this.effects.defeat(profile, target);
          if (this.options.sound) {
            battleAudio.impact(profile, target.x / 7);
            battleAudio.defeat(profile, target.x / 7);
          }
        }
        if (
          profile.secondaryImpact &&
          ch.impactCount < 2 &&
          p >= profile.impact + 0.13
        ) {
          const target = victim.root.position.clone();
          target.y += profile.aimHeight * 0.7;
          this.effects.impact(profile, target, direction, true);
          if (this.options.sound)
            battleAudio.impact(profile, target.x / 7, true);
          ch.impactCount = 2;
        }
      }
      if (p >= 1) this.finishMove(ch);
      return;
    }
    if (ch.state === "defeated") {
      ch.deathTimer += dt;
      const p = Math.min(1, ch.deathTimer / 0.9);
      ch.bodyContainer.position.y -= p * 0.25;
      ch.torsoGroup.rotation.x = p * 0.5;
      ch.headGroup.rotation.x = p * 0.45;
      ch.rightArmPivot.rotation.x = p * 0.8;
      ch.crown.position.z += p * 0.1;
    }
  }
  private updateVictim(v: ArticulatedCharacter, dt: number) {
    if (v.state === "guarding") {
      this.update(v, dt);
      return false;
    }
    if (v.state !== "dying" || !v.profile) return false;
    resetCharacterPose(v);
    v.deathTimer += dt;
    const quick = this.options.competitive || this.options.mode === "brief",
      p = Math.min(1, v.deathTimer / (quick ? 0.22 : 0.78)),
      profile = v.profile;
    const footprint = characterFootprint(v.type, v.army);
    if (profile.death === "bone_scatter") {
      v.bodyContainer.scale.set(
        v.scale * (1 - p * 0.45) * footprint,
        v.scale * (1 - p * 0.45),
        v.scale * (1 - p * 0.45) * footprint,
      );
      v.bodyParts.forEach((part, i) => {
        const seed = i * 2.4 + v.idleSeed;
        part.position.x += Math.sin(seed) * p * 0.6;
        part.position.y += Math.sin(p * Math.PI) * 0.22 - p * 0.42;
        part.position.z += Math.cos(seed) * p * 0.4;
        part.rotation.z += p * (i % 2 ? 1 : -1) * 1.9;
        part.rotation.x += p * 1.2;
      });
    } else if (profile.death === "petal_dissolve") {
      v.bodyContainer.position.y += p * 0.28;
      v.bodyContainer.rotation.y = p * 0.8;
      v.bodyContainer.scale.set(
        v.scale * (1 - p * 0.9) * footprint,
        v.scale * (1 - p * 0.42),
        v.scale * (1 - p * 0.9) * footprint,
      );
      v.leftArmPivot.rotation.z = -p * 0.45;
      v.rightArmPivot.rotation.z = p * 0.45;
    } else if (profile.death === "royal_kneel") {
      v.bodyContainer.position.y -= p * 0.37;
      v.torsoGroup.rotation.x = p * 0.55;
      v.crown.position.y -= p * 0.3;
      v.crown.rotation.z = p * 1.1;
    } else {
      v.bodyContainer.rotation.x = -p * 1.4;
      v.bodyContainer.position.y -= p * 0.32;
      v.root.position.x = v.deathOrigin.x + Math.sin(v.targetYaw) * p * 0.17;
      v.root.position.z = v.deathOrigin.z + Math.cos(v.targetYaw) * p * 0.17;
    }
    if (profile.finisher === "shield_break") {
      v.offhandGroup.rotation.z -= p * 2;
      v.offhandGroup.position.x -= p * 0.45;
      v.offhandGroup.position.y -= p * 0.32;
    }
    if (
      profile.finisher === "disarm" ||
      profile.finisher === "staff_interrupt"
    ) {
      v.weaponGroup.rotation.z += p * 1.6;
      v.weaponGroup.position.y -= p * 0.45;
    }
    if (profile.finisher === "unhorse") {
      v.torsoGroup.rotation.z += p * 1.2;
      v.mountLegs.forEach(
        (leg, i) => (leg.rotation.z += p * (i % 2 ? 0.8 : -0.8)),
      );
    }
    v.shadowDisc.scale.setScalar(1 - p * 0.85);
    return p >= 1;
  }
  private tick = () => {
    if (this.disposed || this.contextLost) return;
    const now = performance.now(),
      dt = Math.min(0.05, (now - this.previousTime) / 1000);
    this.previousTime = now;
    this.elapsed += dt;
    if (!document.hidden) {
      if (this.cameraMoving) {
        const k = 1 - Math.exp(-dt * 8);
        this.camera.position.lerp(this.cameraGoal, k);
        this.controls.target.lerp(this.targetGoal, k);
        if (this.camera.position.distanceToSquared(this.cameraGoal) < 0.002)
          this.cameraMoving = false;
      }
      if (this.options.reducedMotion && this.cameraMoving) {
        this.camera.position.copy(this.cameraGoal);
        this.controls.target.copy(this.targetGoal);
        this.cameraMoving = false;
      }
      this.controls.update();
      for (const ch of this.characters.values()) this.update(ch, dt);
      for (let i = this.victims.length - 1; i >= 0; i--)
        if (this.updateVictim(this.victims[i], dt)) {
          this.removeCharacter(this.victims[i]);
          this.victims.splice(i, 1);
        }
      this.effects.update(dt);
      if (!this.options.reducedMotion) this.arena.updateWeather(dt, "clear");
      for (const orb of this.arena.flameCones)
        orb.scale.setScalar(
          this.options.reducedMotion
            ? 1
            : 1 + Math.sin(this.elapsed * 2.7 + orb.id) * 0.035,
        );
      this.renderer.render(this.scene, this.camera);
      this.frames++;
    }
    if (now - this.statsTime > 1000) {
      this.fps = Math.round((this.frames * 1000) / (now - this.statsTime));
      this.frames = 0;
      this.statsTime = now;
      if (
        !this.software &&
        this.fps < 28 &&
        this.renderer.getPixelRatio() > 0.7
      )
        this.renderer.setPixelRatio(
          Math.max(0.7, this.renderer.getPixelRatio() - 0.15),
        );
    }
    // Software renderers are capped, not forced to run an unbounded GPU loop.
    this.frame = this.software
      ? window.setTimeout(this.tick, 50)
      : requestAnimationFrame(this.tick);
  };
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    cancelAnimationFrame(this.frame);
    clearTimeout(this.frame);
    this.resize.disconnect();
    this.controls.dispose();
    const el = this.renderer.domElement;
    el.removeEventListener("pointerdown", this.down);
    el.removeEventListener("pointerup", this.up);
    el.removeEventListener("pointermove", this.over);
    el.removeEventListener("webglcontextlost", this.lost);
    this.effects.dispose();
    const geometries = new Set<THREE.BufferGeometry>(),
      materials = new Set<THREE.Material>(),
      textures = new Set<THREE.Texture>();
    this.scene.traverse((obj) => {
      if (obj instanceof THREE.Mesh || obj instanceof THREE.Points) {
        geometries.add(obj.geometry);
        for (const material of Array.isArray(obj.material)
          ? obj.material
          : [obj.material]) {
          materials.add(material);
          for (const value of Object.values(material))
            if (value instanceof THREE.Texture) textures.add(value);
        }
      }
    });
    for (const geo of geometries) geo.dispose();
    for (const mat of materials) mat.dispose();
    for (const tex of textures) tex.dispose();
    this.environmentTexture?.dispose();
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    el.remove();
  }
}
