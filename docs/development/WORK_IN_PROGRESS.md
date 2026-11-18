# Work in progress (branches that are not in `main` yet)

Rule (see `/AGENTS.md`): a branch exists only while its work is being made. When it is finished and checked, merge it into `main` and delete it, then remove its line
here. If you stop early, push the branch as `WIP:` and add or update its line. Check this list and `git branch -r --no-merged origin/main` before you start, and do not
edit files another active branch is changing (`git diff --name-only origin/main...origin/<branch>`).

Last cleaned up: 2026-11-18 (all finished older work was merged into `main`; `main` is the active version).

| Branch | What it is | State on 2026-11-18 |
| --- | --- | --- |
| `ui-polish` | Minimal game screen (plates, toast, overlay menu, history drawer), UI style setting | Active (another Claude session, commits today). Conflicts with `main` in UI files; its author merges it. |
| `claude/epic-pascal-moh9lv` | Another UI session branch (board effects) | Active today. Conflicts with `main`. Check whether `ui-polish` supersedes it. |
| `claude/wave1-ui`, `claude/wave1-environment`, `claude/wave1-anim-audio` | "Wave 1" UI frames, board environment effects, audio buses | Commits today. Conflict with `main`. |
| `audio-sounds` | Sonniss audio build script (WIP) | Commits today. Conflicts with `main`. |
| `steps/01-duel-anti-mash` | Duel anti-mash rules, masher/timing bots, harness | Commits today, built on the fairness pass. Touches combat files, which are the area of `docs/battle-chess/FAIRNESS_PASS.md`: re-run the duel report after merging; unverified, no Godot was available. |
| `ccr-config-wip`, `ccr-qa-fixes-wip`, `ccr-old-fortress-wip` | "WIP snapshot (limit reached)" from earlier sessions | Not finished, not reviewed. Conflicts (config, qa-fixes) with `main`. Decide: finish, or delete. |

Everything else that used to be on a branch is in `main` now. Branches that are fully merged can be deleted; the git proxy used by the AI sessions refuses `git push origin --delete`
(HTTP 403), so delete them on GitHub (Branches page) or from your own PC. Merged branches as of this cleanup:
`ccr-a4637d6e-lypbb4 ccr-a734e4c7-xxj6nw ccr-anim-ik ccr-animations ccr-audio ccr-board-paths ccr-campaign ccr-cine-menu-1 ccr-cine-menu-2 ccr-cleanup-plan ccr-cursor-fix ccr-host-play ccr-juice ccr-keybinds ccr-menu-3d ccr-meshy-board ccr-online-fix ccr-piece-identity ccr-relay-play ccr-training-ai codex/* develop deploy/oracle-always-free ccr-ec44bcb0-i5ytwq`.
