# Branches, worktrees and integration

`develop` is the stable integration line; `main` remains the release line.
This foundation started at `29e267b04daba6aaab0c8e4ce46c0d978e22aa15` after a clean
status check. No existing tracked source was removed. Branch protections and
required checks must be configured on GitHub by a repository administrator;
version-controlled guidance does not configure those settings automatically.

## GitHub is the shared source of truth

Codex and Claude Code fetch the newest published versions before every task and
publish their own changes when finishing. A local directory can lag behind the
other agent's remote branch. Check remote branches and PRs before declaring a
handoff missing; record the exact published commit being consumed.

Some environments initially fetch only `main`. Ensure all branches are fetched:

```sh
git status --short --branch
git worktree list
git config --get-all remote.origin.fetch
# If this clone is restricted to one branch, widen its fetch configuration:
git config --replace-all remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git fetch origin --prune
git branch -r
git log -1 --oneline origin/develop
```

Use the newest integrated `origin/develop` as the baseline for a new feature.
Also inspect the latest relevant agent branches/PRs: unmerged handoffs must be
reviewed and integrated into an isolated feature branch before use. Do not pick
a baseline solely because its commit has the newest timestamp.

For an existing feature, compare its local and remote histories before merging
updates. Preserve local changes first; fast-forward when possible, otherwise
review and merge divergent history without forcing or discarding either side.
Fetch again before final integration/handoff to check for concurrent updates.
These steps never grant permission to edit another agent's active files.

## Start a task

```sh
git status --short --branch
git worktree list
git fetch origin --prune
# On a shared machine, only one person creates/reuses each worktree.
git worktree add -b codex/native-chess ../peepeechess-codex origin/develop
git worktree add -b claude/native-combat ../peepeechess-claude origin/develop
```

Use local `develop` only after verifying it matches freshly fetched
`origin/develop`; if GitHub cannot be reached, state that limitation. Never check out
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

Finishing a task includes pushing its commits and creating/updating the PR so
both agents can consume the same version. Verify the pushed branch with
`git ls-remote origin refs/heads/<feature-branch>` and compare the full commit
SHA. Include the baseline, latest consumed handoff commits, test results and any
unfinished work in the PR/final handoff. Keep incomplete work in a clearly
identified draft PR. If a push fails, report the local commit and failure;
do not claim GitHub is updated. Read-only/status checks need no empty commit.

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
