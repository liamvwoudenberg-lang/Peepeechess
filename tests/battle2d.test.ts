import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import {
  captureProfile,
  type Army,
  UNIT_DESIGNS,
} from "../src/game/battleProfiles";
import {
  COMBAT_2D,
  planBattle2D,
  attackerPoses,
  defenderPoses,
  battleLayout,
  screenSquare,
  attackerTravel,
} from "../src/game/battle2D";
import { WeaponDrawing } from "../src/next/Battle2D";
const armies: Army[] = ["royal", "elves", "skeletons"],
  roles = ["p", "n", "b", "r", "q", "k"] as const;
test("all 18 units have distinct 2D fight choreography and independent weapon artwork", () => {
  const poses = new Set<string>(),
    weapons = new Set<string>(),
    names = new Set<string>();
  for (const army of armies)
    for (const role of roles) {
      const p = captureProfile(army, role, "royal", "p"),
        plan = planBattle2D(p, { mode: "cinematic" });
      poses.add(JSON.stringify(attackerPoses(plan, 1, 0)));
      names.add(plan.style.name);
      weapons.add(
        renderToStaticMarkup(
          React.createElement(WeaponDrawing, {
            weapon: UNIT_DESIGNS[army][role].weapon,
            army,
            color: "w",
          }),
        ),
      );
    }
  assert.equal(poses.size, 18);
  assert.equal(weapons.size, 18);
  assert.equal(names.size, 18);
  assert.equal(Object.keys(COMBAT_2D).length, 18);
});
test("all 324 matchups have ordered finite keyframes, bounded timelines and role-specific defeat reactions", () => {
  const reactions = new Set<string>();
  let count = 0;
  for (const a of armies)
    for (const r of roles)
      for (const b of armies)
        for (const target of roles) {
          const p = captureProfile(a, r, b, target),
            plan = planBattle2D(p, { mode: "cinematic" });
          assert.ok(plan.duration >= 1000 && plan.duration <= 1240);
          assert.ok(
            plan.defeatAt < 1 &&
              plan.defeatAt > plan.hits[plan.hits.length - 1],
          );
          for (const frames of [
            attackerPoses(plan, 0.6, -0.8),
            defenderPoses(plan, 0.6, -0.8),
            attackerTravel(
              battleLayout(
                { x: 0, y: 7 },
                { x: 7, y: 0 },
                { x: 7, y: 0 },
                false,
              ),
            ),
          ]) {
            let at = -1;
            for (const f of frames) {
              assert.ok(Number(f.offset) >= at && Number(f.offset) <= 1);
              assert.ok(!/NaN|Infinity/.test(String(f.transform)));
              at = Number(f.offset);
            }
            assert.equal(frames[frames.length - 1].offset, 1);
          }
          if (target === "k")
            assert.equal(defenderPoses(plan, 1, 0).at(-1)?.opacity, 1);
          count++;
        }
  for (const target of roles)
    reactions.add(
      JSON.stringify(
        defenderPoses(
          planBattle2D(captureProfile("royal", "p", "royal", target), {
            mode: "brief",
          }),
          1,
          0,
        ),
      ),
    );
  assert.equal(reactions.size, 6);
  assert.equal(count, 324);
});
test("online and light 2D fights stay brief; disabled and reduced-motion settings have no animated effects", () => {
  const p = captureProfile("elves", "r", "skeletons", "q");
  assert.ok(
    planBattle2D(p, { mode: "cinematic", competitive: true }).duration <= 500,
  );
  const light = planBattle2D(p, { mode: "cinematic", lightweight: true });
  assert.ok(light.duration <= 350);
  assert.equal(light.particles, 0);
  assert.equal(light.shots, 1);
  for (const options of [
    { mode: "off" as const },
    { mode: "cinematic" as const, reducedMotion: true },
  ]) {
    const plan = planBattle2D(p, options);
    assert.equal(plan.duration, 0);
    assert.equal(plan.shots, 0);
    assert.equal(plan.particles, 0);
  }
});
test("2D combat uses the actual en-passant victim square, keeps figures upright from Black, and settles at the legal destination", () => {
  assert.deepEqual(screenSquare("a1", "w"), { x: 0, y: 7 });
  assert.deepEqual(screenSquare("a1", "b"), { x: 7, y: 0 });
  for (const orientation of ["w", "b"] as const) {
    const from = screenSquare("e5", orientation),
      to = screenSquare("d6", orientation),
      impact = screenSquare("d5", orientation),
      layout = battleLayout(from, to, impact, false);
    assert.notDeepEqual(layout.impact, { x: 0, y: 0 });
    assert.ok(
      Math.abs(
        Math.hypot(
          layout.park.x - layout.impact.x,
          layout.park.y - layout.impact.y,
        ) - 0.57,
      ) < 1e-9,
    );
    assert.equal(attackerTravel(layout).at(-1)?.transform, "translate(0%,0%)");
  }
  const ranged = battleLayout(
    { x: 1, y: 6 },
    { x: 6, y: 1 },
    { x: 6, y: 1 },
    true,
  );
  assert.deepEqual(ranged.park, ranged.from);
});
