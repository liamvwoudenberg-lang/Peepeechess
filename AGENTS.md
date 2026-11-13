# Peepeechess collaboration rules

Read `docs/development/COLLABORATION.md`, `docs/development/OWNERSHIP.md`, and
`docs/architecture/CONTRACTS.md` before editing. The integration base is `develop`.
Preserve the React/Three/Capacitor game while the Godot client is migrated.

## Required GitHub synchronization

GitHub is the shared source of truth for Codex and Claude Code.

- Before every task, inspect local changes, fetch all remote branches, and check
  the latest `origin/develop` plus relevant agent branches/PRs. A stale local
  worktree is not evidence that another agent's published work is missing.
- Start from the newest integrated baseline. For a continuing feature, reconcile
  its latest published commits and relevant handoffs in the isolated feature
  worktree; preserve uncommitted work and published history.
- Fetch again before integration or handoff and assess concurrent updates.
  Keep file ownership and review/test requirements in force.
- At task completion, commit and push the task's changes, then create or update
  its PR into `develop`. For blocked partial work, publish a draft and state the
  remaining dependency. A read-only/status task needs no empty commit.
- Verify the remote branch contains the reported commit. Report the branch,
  commit, PR, checks actually run and remaining work so the other agent can
  resume from the same published version. If pushing fails, report that clearly.
- Do not reset, rewrite or update another agent's worktree to synchronize it;
  synchronize through GitHub commits and reviewed integration instead.

## Ownership and integration

- Codex owns architecture, chess, server/backend, navigation, contracts, CI,
  export configuration, integration, and all files not explicitly delegated.
- Claude Code owns the combat-only paths enumerated in OWNERSHIP.md.
- Use a separate feature branch and worktree for each agent. Never edit another
  agent's worktree. Never have two agents edit the same file concurrently.
- A cross-owner edit requires an explicit handoff recorded in the PR/task with
  the exact paths and a confirmation that the current owner has stopped editing.
  A contract change is Codex-owned and must land before dependents consume it.
- Inspect `git status`, branch, diff, and worktrees before branch changes,
  integration, cleanup, or removing files. Never discard another person's work.
- Do not rewrite published history or use reset --hard, clean -fd, forced pushes,
  or forced worktree removal. Checkpoint existing work before any cleanup.
- Run `npm run lint`, `npm test`, `npm run build`, and `npm run test:contracts`
  before integration. Native Classic changes additionally require
  `npm run test:classic`. Battle integration changes additionally require
  `npm run test:battle`. Native changes also require the headless Godot import and
  scene smoke commands in TOOLCHAIN.md. Report checks you actually ran.
- No ranked/native crossplay, export, device validation, or deployment is implied
  by this foundation. Do not advertise unimplemented functionality.

## Downloadable Windows build (after major changes)

When a task finishes a **major change** (new feature, gameplay/balance change, UI overhaul, or a fix that changes how
the game plays), the latest version must be downloadable from the GitHub repository itself:

1. After all checks pass and the work is committed, build the exe from that exact committed tree:
   `bash tools/package/build_release_local.sh <tag>` (see `docs/application/EXPORTS.md`). Never publish a `-dirty` build.
2. Run `tools/package/publish_download.sh <release_dir>`: it replaces `downloads/windows/` (zip of the exe, `SHA256SUMS.txt`,
   `LATEST.md` with the commit and hashes). Commit and push it with the change. Keep the zip under GitHub's 100 MB file limit.
3. `.github/workflows/latest-windows-exe.yml` also builds the exe on every push that changes the game and on demand
   (Actions > Latest Windows exe > Run workflow); on `main` it refreshes the rolling `latest-windows` pre-release.
   If `release-windows.yml` is dispatchable (it exists on the default branch), also publish a GitHub Release with it.
4. Say in the report where the file is, its SHA-256, and that it was never run on a real Windows PC.

Minor changes (docs, typos, small tweaks, test-only changes) do not need a new build.
