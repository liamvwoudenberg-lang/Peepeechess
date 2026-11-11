# Peepeechess development status

## Recovery baseline — 2026-11-11

Latest integrated accessible native application: `cb54c28` on
`origin/codex/multiplayer-application` (PR6, not merged into develop).
Latest accessible Claude work inspected: `f8128ccb6507cc1b380994eed107128f11f879d1`
on `origin/ccr-a4637d6e-lypbb4`; already an ancestor of that application.
Develop is `b4c6dab`, main is `29e267b`. No inaccessible/unpushed Claude work is
assumed available. Existing worktrees and commits are preserved.

Active milestone: stationary board-world cameras and one genuine capture duel.
Codex branch/worktree: `codex/persistent-board`, `peepeechess-persistent-board`.
Published design/interface: docs/board-world/CONTRACT.md and game/network v2.

| Area | Recovered state |
| --- | --- |
| Classic rules/clocks | Implemented; legal moves, special rules, notation, FEN, undo, draw accounting, clocks and authoritative online state. Standard material cases verified, not exhaustive arbitrary dead-position proof. Reuse engine and shared match classes. |
| Existing board views | Shared chess state works; separate 2D Control and 3D world violate the new one-board requirement. Replace active presentation with camera modes on the existing 3D board. |
| Existing Battle rules/loop | C0 two-outcome king safety, frozen capture transactions, EP/promotion/castling/draw handling and trusted one-time settlement are reusable. Current local/online loop loads a separate arena and must change. |
| Combat | Pawn/Knight/Bishop/Rook/Queen mechanics, validated damage, stamina, parry/dodge/combos and abilities implemented. Reuse owner controllers/state machine. |
| Assets/animation/audio | Six model/rig/clip sets and procedural pipeline exist. King mechanics missing; victory/hit clips not fully driven; audio assets/player exist but are not mounted in the current app. |
| Multiplayer/backend | ENet/DTLS authority, input sequencing, snapshots, reconnects, matchmaking/accounts/PostgreSQL/ratings/history implemented. Socket presentation does not enable owner's prediction; its circular geometry also differs from the new board. |
| UI/platform | Native shell/settings/profiles/history/results and Windows/APK/test AAB builds verified on prior baseline. No physical Windows–Android crossplay, mobile GPU or controller ergonomics verification. |
| Dependencies | Godot4.6.3, Node24.22.1, full JDK21, SDK36/build-tools36.1 and templates available. Production native hosting/signing keys/devices unavailable. Disk budget requires staged builds. |

Fresh recovery checks: Classic engine83, match53, views345, Battle transactions250,
application protocol21, UI49, network authority62 and578combat checks/103tests
passed in read-only audits. Baseline full regression command is running; record
its final result before implementation validation. Published cb54c28 CI was also
verified green: foundation4m40s, PostgreSQL43s, native exports2m20s.

Planned architectural improvements: versioned board-world coordinates/negotiation;
one persistent camera/render world; reusable simulation lifecycle adapter using
square collisions and actual capture squares; seamless same-world presentation.

Remaining milestones: verify repeated local/online board encounters; wire tested
prediction/reconciliation to square topology; complete owner King/RoyalCounter
and formal royal gauntlet rules; actual device crossplay/performance; refreshed
native artifacts. Update this file with commits, changed paths, checks actually
run and remaining issues as each milestone lands. No completion is implied yet.
