# File ownership

This assignment applies to existing and new files. Each path has one active
owner; branch/worktree isolation alone does not prevent overlapping edits.

| Paths | Owner | Boundary |
| --- | --- | --- |
| `contracts/**`, `godot/contracts/**`, `docs/**`, `AGENTS.md` | Codex | Shared interfaces and decisions; Claude proposes changes via a separate request |
| `godot/app/**`, `godot/chess/**`, `godot/boards/**`, `godot/network/**`, `godot/ui/**`, `godot/project.godot`, `godot/export_presets.cfg` | Codex | App lifecycle, rules, both board views, transport, navigation and exports |
| `godot/combat/**` | Claude Code | Controllers, state machine, arenas, fighter mechanics, combat UI, VFX and shaders |
| `godot/assets/combat/**`, `tools/blender/**` | Claude Code | Generated combat models/animations, source Blender files and procedural scripts |
| `godot/assets/board/**`, `public/**`, `scripts/draw-legions.ts`, `scripts/render-*.py` | Codex | Existing board artwork/pipeline; move to Claude only through an explicit handoff |
| `src/battle/simulation.ts`, `src/battle/config.ts`, `src/battle/controls.ts`, `src/battle/fighterModel.ts`, `src/battle/ArenaRenderer.ts`, `src/battle/CombatArena.tsx`, `src/battle/battle.css` | Claude Code | Legacy combat reference/maintenance; native work should use new combat paths |
| `src/battle/rules.ts`, `src/battle/session.ts`, `src/battle/copyState.ts`, `src/battle/RoomClient.ts`, `src/battle/BattleChess.tsx` | Codex | Chess-to-combat orchestration and network boundary |
| `tests/combat/**`, `godot/combat/tests/**` | Claude Code | New combat-only tests |
| `tests/**` otherwise, `godot/tests/**`, `src/**` otherwise, `server/**`, `api/**`, `android/**`, `.github/**`, root config and scripts | Codex | Existing integrated tests stay under one owner; extract combat tests in a Codex PR before handing them over |
| Every unlisted path | Codex | Final integration ownership; assign new combat paths before edits |

Do not change the existing mixed `tests/battle-chess.test.ts` concurrently. Claude
adds new combat tests in `tests/combat/`; Codex runs/integrates them. Combat assets
must not replace board silhouettes or atlases. Commit portable GLB/glTF output;
Godot must not require Blender to import `.blend` in CI. Generated assets need a
source script, Blender version, seed and regeneration command in a local README.
No rig, animation clips, or combat assets have been ported by this foundation.
