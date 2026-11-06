import test from "node:test";
import assert from "node:assert/strict";
import {
  LEGION_PALETTES,
  BOARD_PALETTES,
  PIECE_SILHOUETTES,
} from "../src/game/legionIdentity";
import { createFactionMaterialRigs } from "../src/three/fantasyCharacters";
import { readFileSync } from "node:fs";
const luminance = (hex: number) => {
  const c = [hex >> 16, (hex >> 8) & 255, hex & 255].map((n) => {
    const s = n / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
};
const contrast = (a: number, b: number) =>
  (Math.max(luminance(a), luminance(b)) + 0.05) /
  (Math.min(luminance(a), luminance(b)) + 0.05);
test("all board palettes distinguish both ivory and obsidian armor with at least 3:1 source-color contrast", () => {
  for (const [name, palette] of Object.entries(BOARD_PALETTES))
    for (const side of ["w", "b"] as const)
      for (const square of [palette.light, palette.dark])
        assert.ok(
          contrast(LEGION_PALETTES.royal[side].armor, square) >= 3,
          `${name}/${side}: ${contrast(LEGION_PALETTES.royal[side].armor, square)}`,
        );
});
test("all 36 original drawings share the 3D models’ livery and six role identities", () => {
  const svg = readFileSync("public/pieces/legions-drawn.svg", "utf8");
  assert.equal((svg.match(/data-silhouette=/g) || []).length, 36);
  for (const army of ["royal", "elves", "skeletons"] as const) {
    const rigs = createFactionMaterialRigs(true, army);
    for (const side of ["w", "b"] as const) {
      assert.equal(
        rigs[side].primaryArmor.color.getHex(),
        LEGION_PALETTES[army][side].armor,
      );
      assert.equal(
        rigs[side].secondaryCloth.color.getHex(),
        LEGION_PALETTES[army][side].cloth,
      );
      for (const role of ["p", "n", "b", "r", "q", "k"] as const)
        assert.ok(
          svg.includes(
            `data-army="${army}" data-side="${side}" data-role="${role}" data-silhouette="${PIECE_SILHOUETTES[role]}"`,
          ),
        );
    }
  }
});

test("the forest cuts away foreground canopies for either side without removing the distant trees", async () => {
  const THREE = await import("three");
  const { buildCastleEnvironment } = await import(
    "../src/three/castleEnvironment"
  );
  const arena = buildCastleEnvironment(
    { capabilities: { getMaxAnisotropy: () => 1 } } as any,
    false,
    "silverwood",
  );
  const canopy = arena.root.getObjectByName(
    "Silverwood canopy",
  ) as import("three").InstancedMesh;
  const poses = Array.from({ length: canopy.count }, (_, i) => {
    const matrix = new THREE.Matrix4();
    canopy.getMatrixAt(i, matrix);
    return matrix;
  });
  for (const sign of [1, -1]) {
    arena.updateSightline(new THREE.Vector3(0, 12, 13 * sign));
    let shown = 0,
      hidden = 0;
    for (let i = 0; i < canopy.count; i++) {
      const actual = new THREE.Matrix4();
      canopy.getMatrixAt(i, actual);
      const size = new THREE.Vector3().setFromMatrixScale(actual).length();
      if (poses[i].elements[14] * sign > 0) {
        assert.equal(size, 0);
        hidden++;
      } else {
        assert.ok(size > 1);
        shown++;
      }
    }
    assert.ok(shown > 8 && hidden > 8);
  }
});
