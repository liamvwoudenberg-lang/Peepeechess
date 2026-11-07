# Branches, worktrees and integration

`develop` is the stable integration line; `main` remains the release line.
This foundation started at `29e267b04daba6aaab0c8e4ce46c0d978e22aa15` after a clean
status check. No existing tracked source was removed. Branch protections and
required checks must be configured on GitHub by a repository administrator;
version-controlled guidance does not configure those settings automatically.

## Start a task

```sh
git status --short --branch
git worktree list
git fetch origin
# On a shared machine, only one person creates/reuses each worktree.
git worktree add -b codex/native-chess ../peepeechess-codex origin/develop
git worktree add -b claude/native-combat ../peepeechess-claude origin/develop
```

For local-only setup use `develop` instead of `origin/develop`. Never check out
the same branch in two worktrees. Each worktree installs its own dependencies
with `npm ci`. Do not share mutable node_modules or Godot .godot directories.
Before starting, announce the exact owned paths in the shared task/PR and name
the baseline commit. Codex and Claude are separate tools/sessions: a document
cannot confirm that Claude has read or accepted a contract. Claude should
acknowledge the foundation commit before starting implementation.

Only the assigned owner edits a path. To transfer a file, the current owner
commits or checkpoints it, stops editing, and confirms the handoff in the task.
The recipient records the paths and starts from that commit. No handoff is
required for read-only inspection. Do not edit a shared lock/claim file from
both worktrees as an attempted concurrency mechanism.

## Commit and integrate

```sh
# In the feature worktree: inspect, then stage only the intended paths.
git status --short
git diff --check
git diff
# git add <explicit paths>
git commit -m "Describe one coherent change"
git push -u origin HEAD
# Open a PR targeting develop; include baseline SHA, owner, changed paths,
# contract version, tests actually run, and migration limitations.
```

Codex reviews the diff, contract fixtures, chess safety and resource references.
Resolve overlapping changes with the owner; do not choose an entire side of a
conflict blindly. Run all required checks on the actual merged result. A local
foundation can be integrated without rewriting history:

```sh
# Use an integration worktree; verify it is clean first.
git worktree add ../peepeechess-integration develop
cd ../peepeechess-integration
git status --short --branch
git merge --ff-only codex/collaboration-foundation
# Run checks from TOOLCHAIN.md here, then:
git push -u origin develop
```

For divergent feature PRs, merge with a reviewed merge commit and rerun checks;
never force-update `develop`. Delete only merged branches and remove only clean
worktrees, without --force. Release PRs go from develop to main after Windows
and Android export/device verification. Neither a merge nor this task releases
a game. Use tags for releases after release gates pass.

## Work that can proceed in parallel after the foundation is shared

- Codex: Godot chess state adapter and move validation tests, 2D/3D board
  projections, app navigation, persistent authoritative service and native
  transport adapters, matchmaking, export configuration and CI.
- Claude: isolated `godot/combat/` scene/controller/state machine, fighter
  mechanics consuming BattleRequest/FighterStats and producing snapshots on the
  server, combat-only tests, Blender scripts and portable combat models/VFX.

Claude must not write chess state or choose the trusted online result in a
client. Codex must not edit combat mechanics during Claude's active task.
A headless combat authority and the networking adapter require a scheduled
integration handoff, shared fixtures, and a reviewed interface test.
