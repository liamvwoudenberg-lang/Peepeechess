# Integrating and continuing this application

Feature branch: `codex/multiplayer-application`, PR6 into `develop`.
The branch includes reviewed native multiplayer PR5/0086ebb and Claude's
f8128cc combat/audio/mobile handoff on top of develop b4c6dab. New account,
matchmaking and export contracts were committed/published before consumers.
The preserved legacy web application uses its existing protocols and storage.

Fetch all branches and preserve local changes before switching or merging:

```sh
git status --short --branch
git fetch --all --prune
git worktree list
# Create a new agent-specific worktree/branch from the published application.
git worktree add -b claude/next-combat ../peepeechess-next-combat origin/codex/multiplayer-application
```

Use a different feature name/path for Codex work. Do not reset or rewrite an
existing agent worktree. Claude retains combat, generated combat asset and
Blender ownership; Codex retains UI, chess, backend, contracts, exports and
integration. The application adds no combat simulation or client winner path.
The game remains C0; royal king gauntlets are a separate future ruleset.

After reviewing the stacked PRs, merge into develop without rewriting published
history, and run the required checks on the exact integration result. If PR5
lands first, Git will retain its existing shared commits when this PR is merged.
Avoid copying whole directories across branches or choosing conflict sides
without reviewing the changed files. Keep production credentials and signing
keys outside the repository. CI produces test artifacts, not a store release.

Validation commands:

```sh
npm ci
npm run lint
npm test
npm run build
npm run test:contracts
npm run test:classic
npm run test:battle
npm run test:multiplayer
npm run test:backend
npm run test:application
```

The PostgreSQL CI job runs the backend suite against a disposable PostgreSQL17
service. The export CI job generates unsigned Windows, debug APK and test-signed
AAB artifacts. Installation, server startup, trust boundaries and validation
results are linked from README.md and this directory. Actual Windows–Android
crossplay and production signing remain release gates.

Independent follow-up work can proceed in parallel after consuming this branch:
Claude can continue combat balance/animation/audio/VFX; Codex can extend account
recovery, multi-server allocation and UI/device QA without editing combat-owned
files. Coordinate contract changes before either side implements dependents.
