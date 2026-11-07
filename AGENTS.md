# Peepeechess collaboration rules

Read `docs/development/COLLABORATION.md`, `docs/development/OWNERSHIP.md`, and
`docs/architecture/CONTRACTS.md` before editing. The integration base is `develop`.
Preserve the React/Three/Capacitor game while the Godot client is migrated.

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
  before integration. Native changes also require the headless Godot import and
  scene smoke commands in TOOLCHAIN.md. Report checks you actually ran.
- No ranked/native crossplay, export, device validation, or deployment is implied
  by this foundation. Do not advertise unimplemented functionality.
