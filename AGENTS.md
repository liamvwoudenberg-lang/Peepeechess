# Peepeechess: rules for every AI and person working in this repository

Read this file completely before changing anything. The owner is the human user; they decide. If a rule here is in your way, stop and ask them.

## 1. One active version: `main`

- **`main` is the only active version of the game.** It must always be playable, must build, and must pass the checks in section 3. The Windows build, the server package and every release come from `main`.
- There is **no `develop`** and no other long-lived branch. Do not create release, staging, per-agent or per-feature "home" branches.
- Every other branch is **temporary storage for work that is still being made**: one branch per piece of work, named after the work (`fix-lobby`, `steps/01-duel-anti-mash`), started from the newest `main`, living for days, not weeks.
- **When the work is finished and the checks pass, merge it into `main`, push `main`, then delete the branch** (remote and local). Finished work never stays on a branch, and a branch never contains "the real version".
- Small, finished, checked changes may go straight to `main`. Anything big or risky: use a temporary branch, merge when done.
- If you must stop before the work is finished (limit reached, blocked): commit, push the branch with a commit message starting `WIP:`, and add or update its line in `docs/development/WORK_IN_PROGRESS.md` (branch, goal, what is left, date). Remove that line when you merge and delete the branch.

## 2. Before you start (every task, every time)

1. `git status`, then `git fetch --all --prune`. A stale local copy is not evidence that something is missing.
2. Read `docs/development/WORK_IN_PROGRESS.md` and run `git branch -r --no-merged origin/main`. Another AI may be working right now (check the date of the last commit).
3. Start from the newest `origin/main`. Do not start from another branch unless the user told you to.
4. Before editing a file, make sure no active branch is changing it: `git diff --name-only origin/main...origin/<branch>`. If one is, do not edit it; tell the user, or do other work first. Never have two AIs edit the same file at the same time.
5. Fetch again before you merge or push, and merge what arrived instead of overwriting it.

## 3. Checks before anything lands on `main`

Run what your change can affect and report what you actually ran (never claim a check you did not run):
`npm run lint`, `npm test`, `npm run build`, `npm run test:contracts`; Godot changes also `npm run test:battle`, `npm run test:ui`, and the headless Godot import (`godot --headless --path godot --editor --import`); online or server changes also `npm run test:multiplayer`; combat or balance changes also the Godot combat suite (`godot --headless --path godot --script res://combat/tests/test_runner.gd`) and the duel/net reports (`docs/battle-chess/FAIRNESS_PASS.md`, `docs/deployment/VPS.md`).
Known pre-existing failures are listed in the commit messages or docs that mention them (for example the `anim_integrity` suite); do not hide new failures behind them.

## 4. Git safety

- Never force-push, never rewrite published history, never `reset --hard`, `clean -fd` or force-remove a worktree, and never discard someone's uncommitted or unmerged work. Look at `git status`, the branch and the diff before cleanup.
- Never delete a branch that still has commits that are not in `main`, unless the user says so for that branch. Never merge another AI's active branch without asking the user.
- If deleting a remote branch is refused (HTTP 403 from the proxy), do not work around it: tell the user and give them the command (`git push origin --delete <branch>`) or point them to the Branches page on GitHub.
- Never commit secrets: SSH keys, private keys (`*.key`, `*.pem`), `server.env`, `accounts.env`, tokens, passwords. The public server certificate `godot/network/trusted_server.crt` is the only certificate in the repo. Do not paste secrets into issues, PR text or chat.
- Commit often in small steps with clear messages. End commits with the attribution lines your tool gives you.

## 5. Downloadable Windows build (after major changes)

When a task finishes a major change (new feature, gameplay or balance change, UI overhaul, a fix that changes how the game plays): push to `main`. `.github/workflows/latest-windows-exe.yml` builds the exe on every push that changes the game and on demand (Actions > Latest Windows exe); the artifact is `Peepeechess-windows-x86_64`. Check the run succeeded and report its link. The exe is far too big to commit (GitHub rejects files over 100 MB): never add it to the repository. Say that it was never run on a real Windows PC.
The online server is a separate download: Actions > **Build server package** (artifact `Peepeechess-server-x86_64`). **The server and the game must be built from compatible commits**: the server refuses a client whose combat tuning (`balance_v1.json`) differs. After any balance change, redeploy the server (`docs/deployment/VPS.md`).

## 6. Product rules

- Preserve the working game while migrating; the Godot client is the main one, the React/Three/Capacitor game stays runnable until the user says otherwise.
- All balance numbers live in `godot/combat/data/balance_v1.json`. No magic numbers in logic.
- Do not advertise functionality that is not implemented. No ranked play, crossplay or store release is implied by anything in this repository.
- The server owns match state; clients send intent only (`docs/network/`, `docs/architecture/CONTRACTS.md`). A contract change must land with its tests before anything depends on it.

## 7. Where to look

`docs/development/WORK_IN_PROGRESS.md` (active branches), `docs/battle-chess/FAIRNESS_PASS.md` (combat rules, tuning, harness), `docs/deployment/VPS.md` and `ACCOUNTS.md` (server and accounts), `docs/network/` (protocol), `godot/combat/BALANCE.md`, `docs/architecture/`.
