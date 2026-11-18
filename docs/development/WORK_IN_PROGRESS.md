# Work in progress (branches that are not in `main` yet)

Rule (see `/AGENTS.md`): a branch exists only while its work is being made. When it is finished and checked, merge it into `main` and delete it, then remove its line
here. If you stop early, push the branch as `WIP:` and add or update its line. Check this list and `git branch -r --no-merged origin/main` before you start, and do not
edit files another active branch is changing (`git diff --name-only origin/main...origin/<branch>`).

Last cleaned up: 2026-11-18 (second pass: all finished branches merged into `main`; `main` is the active version). The list of everything unfinished is `docs/development/TODO.md`.

## Branches still holding unmerged work (skipped on purpose)

| Branch | What it is | Why it was not merged |
| --- | --- | --- |
| `audio-sounds` | Sonniss sound selection (187 MB raw WAV) and `build_sonniss.py` | The 187 MB of raw WAVs must not enter `main` history (the script itself says "kept out of git"). The script was copied to `tools/audio/build_sonniss.py`; it was never run end to end. Keep the branch until the sounds are built and the owner decides. |
| `ccr-config-wip` | Config layer: `godot/config/*.json` with meta files, dev override, balance debug panel, config tools, rules docs | WIP snapshot on a pre-fairness-pass base. It moves `balance_v1.json` to `godot/config/balance.json` (AGENTS.md says `godot/combat/data/`), conflicts in `balance_data.gd`, `test_runner.gd` and the balance file. Needs a re-base on the fairness pass and an owner decision on the file location. |
| `ccr-qa-fixes-wip` | Older balance tweaks, anim KNOWN entries, `qa_smoke.gd` | The balance numbers predate the fairness pass and would undo it. Only `godot/combat/tools/qa_smoke.gd` was taken. |
| `ccr-old-fortress-wip` | Old fortress decimation tool, two Python wheels (17 MB), old `fortress_decimated.res` | Binary junk; main uses the Meshy fortress. Probably delete (owner). |

## Merged into `main` on 2026-11-18, safe to delete on GitHub

`ui-polish`, `claude/epic-pascal-moh9lv`, `claude/wave1-ui`, `claude/wave1-environment`, `claude/wave1-anim-audio`, `steps/01-duel-anti-mash` (merged with the anti-mash rules OFF, needs calibration: docs/ROADMAP.md step 1).

Earlier merged branches, also safe to delete: `ccr-a4637d6e-lypbb4 ccr-a734e4c7-xxj6nw ccr-anim-ik ccr-animations ccr-audio ccr-board-paths ccr-campaign ccr-cine-menu-1 ccr-cine-menu-2 ccr-cleanup-plan ccr-cursor-fix ccr-host-play ccr-juice ccr-keybinds ccr-menu-3d ccr-meshy-board ccr-online-fix ccr-piece-identity ccr-relay-play ccr-training-ai ccr-ec44bcb0-i5ytwq`.

The git proxy used by the AI sessions refuses `git push origin --delete` (HTTP 403), so delete them on GitHub (Branches page) or from your own PC with `git push origin --delete <branch>`.
