import test from "node:test";
import assert from "node:assert/strict";
import { Chess } from "chess.js";
import * as THREE from "three";
import {
  UNIT_DESIGNS,
  ARENAS,
  captureProfile,
  sampleCombat,
  type Army,
} from "../src/game/battleProfiles";
import { WEAPON_TONES } from "../src/game/battleAudio";
import {
  sceneTransition,
  type ScenePosition,
} from "../src/game/sceneTransition";
import {
  buildArticulatedCharacter,
  createFactionMaterialRigs,
  resetCharacterPose,
} from "../src/three/fantasyCharacters";
import {
  buildCastleEnvironment,
  squareToWorldPos,
} from "../src/three/castleEnvironment";
import type { PieceSymbol } from "../src/game/types";
import type { Ply } from "../src/next/contracts";
const armies: Army[] = ["royal", "elves", "skeletons"],
  roles: PieceSymbol[] = ["p", "n", "b", "r", "q", "k"];

test("all 324 encounters have deterministic choreography, target reactions, and finite poses", () => {
  const ids = new Set<string>(),
    weapons = new Set<string>(),
    motions = new Set<string>();
  for (const army of armies)
    for (const role of roles)
      for (const enemy of armies)
        for (const target of roles) {
          const profile = captureProfile(army, role, enemy, target);
          ids.add(profile.id);
          weapons.add(profile.weapon);
          motions.add(profile.motion);
          assert.deepEqual(captureProfile(army, role, enemy, target), profile);
          assert.ok(
            profile.windup < profile.impact &&
              profile.impact < profile.recovery &&
              profile.recovery < 1,
          );
          assert.ok(profile.seconds > 0 && profile.seconds < 1.5);
          assert.equal(profile.weapon, UNIT_DESIGNS[army][role].weapon);
          assert.ok(WEAPON_TONES[profile.weapon]);
          for (let i = 0; i <= 40; i++)
            assert.ok(
              Object.values(sampleCombat(profile, i / 40)).every(
                Number.isFinite,
              ),
              profile.id,
            );
          const rest = sampleCombat(profile, 1);
          assert.ok(
            Math.abs(rest.rightX) < 0.001 && Math.abs(rest.advance) < 0.001,
          );
        }
  assert.equal(ids.size, 324);
  assert.equal(weapons.size, 18);
  assert.equal(motions.size, 18);
  assert.equal(
    new Set(
      armies.flatMap((army) =>
        roles.map((role) =>
          JSON.stringify(
            [0.3, 0.5, 0.7].map((p) =>
              sampleCombat(captureProfile(army, role, "royal", "p"), p),
            ),
          ),
        ),
      ),
    ).size,
    18,
  );
  assert.equal(
    new Set(Object.values(WEAPON_TONES).map((x) => JSON.stringify(x))).size,
    18,
  );
  const profiles = roles.map((role) =>
    captureProfile("elves", "q", "skeletons", role),
  );
  assert.equal(new Set(profiles.map((x) => x.finisher)).size, 6);
  assert.equal(
    captureProfile("royal", "r", "skeletons", "p").death,
    "bone_scatter",
  );
  assert.equal(
    captureProfile("royal", "r", "elves", "p").death,
    "petal_dissolve",
  );
  assert.equal(captureProfile("royal", "r", "royal", "p").death, "armor_fall");
});

function transition(fen: string, san: string) {
  const chess = new Chess(fen),
    initial = sceneTransition(null, fen, undefined, 0).position,
    move = chess.move(san);
  return {
    initial,
    result: sceneTransition(initial, chess.fen(), move as unknown as Ply, 1),
    chess,
  };
}
test("scene preserves identities across captures, castling, en passant, and underpromotion", () => {
  const castle = transition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "O-O");
  assert.ok(castle.result.event?.rookCastleMove);
  assert.equal(castle.result.event?.rookCastleMove?.to, "f1");
  const ep = transition("7k/8/8/3pP3/8/8/8/7K w - d6 0 1", "exd6");
  assert.equal(ep.result.event?.capturedSquare, "d5");
  assert.equal(ep.result.event?.capturedPieceType, "p");
  assert.equal(ep.result.position.pieces.length, 3);
  const promote = transition("1r5k/P7/8/8/8/8/8/7K w - - 0 1", "axb8=N");
  assert.equal(promote.result.event?.pieceType, "p");
  assert.equal(promote.result.event?.promotedTo, "n");
  assert.equal(
    promote.result.position.pieces.find((p) => p.square === "b8")?.type,
    "n",
  );
  assert.equal(
    promote.result.event?.pieceId,
    promote.initial.pieces.find((p) => p.square === "a7")?.id,
  );
  const chess = new Chess();
  let position: ScenePosition = sceneTransition(
    null,
    chess.fen(),
    undefined,
    0,
  ).position;
  for (const [i, san] of ["e4", "d5", "exd5", "Qxd5", "Nc3", "Qd8"].entries()) {
    const m = chess.move(san),
      result = sceneTransition(
        position,
        chess.fen(),
        m as unknown as Ply,
        i + 1,
      );
    assert.ok(result.event);
    assert.equal(
      result.position.pieces.length,
      chess.board().flat().filter(Boolean).length,
    );
    position = result.position;
  }
  assert.equal(
    sceneTransition(position, chess.fen(), undefined, 30).event,
    null,
  );
  assert.equal(
    sceneTransition(position, new Chess().fen(), undefined, 31).event,
    null,
  );
});

test("all 36 miniatures keep articulated weapons, side palettes, and bounded geometry", () => {
  for (const army of armies) {
    const rigs = createFactionMaterialRigs(true, army);
    assert.ok(rigs.w.primaryArmor.color.getHSL({ h: 0, s: 0, l: 0 }).l > 0.8);
    assert.ok(rigs.b.primaryArmor.color.getHSL({ h: 0, s: 0, l: 0 }).l < 0.25);
    for (const side of ["w", "b"] as const)
      for (const role of roles) {
        const c = buildArticulatedCharacter(
          `${side}${role}`,
          role,
          side,
          rigs[side],
          false,
        );
        let calls = 0,
          triangles = 0;
        c.root.traverse((m) => {
          if (m instanceof THREE.Mesh) {
            calls++;
            triangles +=
              (m.geometry.index?.count ??
                m.geometry.attributes.position.count) / 3;
          }
        });
        assert.ok(calls <= 48, `${army}/${role}: ${calls}`);
        assert.ok(triangles < 9500);
        assert.equal(c.root.userData.weapon, UNIT_DESIGNS[army][role].weapon);
        assert.ok(c.weaponGroup.children.length > 0);
        assert.ok(c.crown.children.length > 0);
        assert.ok(c.root.getObjectByName("Chess identity " + role));
        assert.equal(c.mountLegs.length, role === "n" ? 4 : 0);
        assert.equal(Boolean(c.mountNeck), role === "n");
        c.rightArmPivot.rotation.x = 2;
        c.weaponGroup.position.y = 5;
        resetCharacterPose(c);
        assert.equal(
          c.weaponGroup.position.y,
          c.weaponGroup.userData.restPosition.y,
        );
        const footprint = new THREE.Box3()
          .setFromObject(c.root)
          .getSize(new THREE.Vector3());
        assert.ok(
          footprint.x <= 1.16 && footprint.z <= 1.16,
          `${army}/${role} occupies another square`,
        );
        assert.ok(
          new THREE.Box3().setFromObject(c.root).getSize(new THREE.Vector3())
            .y > 1,
        );
      }
  }
});

test("three arenas share a correct instanced chessboard and small scenery draw budgets", () => {
  const fakeRenderer = {
    capabilities: { getMaxAnisotropy: () => 4 },
  } as THREE.WebGLRenderer;
  for (const palette of ARENAS) {
    const arena = buildCastleEnvironment(fakeRenderer, false, palette.id);
    assert.equal(arena.root.name, palette.name);
    const tiles = arena.clickableTiles[0] as THREE.InstancedMesh;
    assert.equal(tiles.count, 64);
    assert.equal(new Set(tiles.userData.squareIds).size, 64);
    assert.equal(
      arena.squareAtHit({
        object: tiles,
        instanceId: 0,
        distance: 0,
        point: new THREE.Vector3(),
      }),
      "a1",
    );
    assert.equal(
      arena.squareAtHit({
        object: tiles,
        instanceId: 63,
        distance: 0,
        point: new THREE.Vector3(),
      }),
      "h8",
    );
    const color = new THREE.Color();
    tiles.getColorAt(0, color);
    assert.equal(color.getHex(), palette.darkSquare);
    let meshes = 0;
    arena.root.traverse((obj) => {
      if (obj instanceof THREE.Mesh) meshes++;
    });
    assert.ok(meshes <= 40, `${palette.id}: ${meshes}`);
    assert.equal(arena.torchLights.length, 2);
  }
  assert.ok(squareToWorldPos("a1").x < squareToWorldPos("h1").x);
  assert.ok(squareToWorldPos("a1").z > squareToWorldPos("a8").z);
});
