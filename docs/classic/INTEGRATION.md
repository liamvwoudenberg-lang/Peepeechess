# Integrating native Classic

Feature branch: `codex/native-chess`, based on integrated foundation `c0dfe92`.
Submit a PR into `develop`; no direct merge or main/release update is part of
this task. Only Codex-owned paths are changed. The separate Claude worktree and
all combat-owned files stay untouched.

Review/run from a clean feature worktree:

```sh
npm ci
npm run lint
npm test
npm run build
npm run test:contracts
npm run test:classic
godot --path godot
```

`test:classic` imports from a fresh editor state, runs native engine/match/view
checks, creates a seeded chess.js differential corpus, verifies native v1 states
in Node, and smoke-runs the main scene. XDG paths are temporary and writable.
For desktop play in the cloud terminal use the shared display's ordinary user
session; an isolated shell may lack its X11 authorization. This is unrelated to
the game's display support. Use `--audio-driver Dummy` on test machines without
an audio device. No new tool/dependency installation is required beyond the
foundation's Node and Godot tools.

Architecture clarifications: local undo increments board revision while reducing
ply; forward commits still increment once. New FEN imports create a new match
ID. Clock display state is a local API outside the unchanged v1 schema. Native
online integration must version clock synchronization before using snapshots
for timed remote matches. View mode/orientation/camera never appear in shared
state, and server-mode local undo/pause/play shortcuts are disabled.

Required manual review: desktop and narrow layout, 2D click/drag and promotion,
3D ray selection/orbit/zoom, clock behavior, FEN error preservation, draw claims
and view switching with history intact. Do not infer physical Android, Windows
binary or online crossplay verification from Linux/automated input tests.
