# Foundation validation — 2026-11-07

Reference before changes: `29e267b04daba6aaab0c8e4ce46c0d978e22aa15`.
These are local Linux checks performed for this foundation, not deployment or
physical-device certification. The matching commit is the commit containing
this report. GitHub Actions is configured but no hosted run is claimed here.

| Check actually run | Result |
| --- | --- |
| Baseline `npm test` | 69 passed, 0 failed |
| Baseline `npm run lint` | Passed |
| Foundation `npm run lint` | Passed |
| Foundation `npm test` | 71 passed, 0 failed (existing 69 plus two Battle safety/variant tests) |
| `npm run test:contracts` | 23 Node tests passed; Godot passed the same 21 valid/invalid schema cases and rejected malformed JSON; all 9 valid payloads round-tripped Node → Godot → Node with exact decoded equality |
| `npm run build` | Passed; existing large-chunk warning for procedural fantasy character bundle remains |
| Godot 4.6.3 headless editor import | Passed with writable task-local XDG directories; no script/parse/resource errors in final run |
| Godot main scene, headless `--quit-after 2` | Passed, exit 0; this is a runnable status scene, not gameplay validation |
| Blender 4.3.2 background/factory-startup Python probe | Passed, printed version and exited 0 |
| `git diff --check` | Passed before commit |

The first Godot attempts exposed the sandbox's unwritable home paths (including
a contract-runner crash). Using temporary XDG data/config/cache directories
resolved this; final runs passed. The first cross-engine roundtrip also caught
Godot's default float rounding pushing pi outside the schema bound. Full-precision
JSON output fixed it; exact equality now passes. These failures were not hidden
or counted as successful validation.

Not run: browser UI suites, Windows executable/export, Godot Android export,
Capacitor APK build, Android emulator/physical devices, external multiplayer,
native crossplay, deployment, signing/release, or a Claude Code session. Android
SDK tools/export templates were not found in inspected locations. No server
credentials are configured. The new v1 codec/schema is not wired into existing
web protocols. Authority admission/semantic checks specified in CONTRACTS.md
remain adapter implementation requirements.

Reproduce with TOOLCHAIN.md. The feature and integration worktrees run the same
tracked source after a fast-forward integration; local npm/Godot caches are not
versioned. The worktree/branch/push status is reported separately in the task
handoff, since Git commit hashes cannot include their own final value here.
