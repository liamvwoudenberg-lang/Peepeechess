# Reproducible toolchain

Pinned native runtime: **Godot 4.6.3 stable**, standard GDScript build, matching
4.6.3 export templates. `.godot-version` is the source for CI's download/version
check. Compatibility renderer starts with OpenGL on Windows and OpenGL ES on
Android to keep the initial project modest. No addons or .NET runtime required.

Foundation snapshot observed 2026-11-07 in this Linux environment (historical;
see the native application export update below):

| Tool | Observed result |
| --- | --- |
| Godot | `4.6.3.stable.official.7d41c59c4`, `/usr/local/bin/godot` and godot4 aliases |
| Blender | 4.3.2; factory-startup background Python probe completed successfully |
| Node/npm | Node v24.22.1; use Node 24 LTS and `npm ci` with committed lockfile |
| Java | OpenJDK 21.0.13 |
| Android tools | adb and sdkmanager absent from PATH; no SDK/platform android.jar found in searched /usr, /opt, /workspace paths |
| Export templates | No templates found in the inspected Godot installation/user template locations; no export was attempted |
| Existing Android project | Capacitor, Gradle 8.11.1 wrapper, AGP 8.7.2, minSdk 23 and compile/targetSdk 35; source configuration inspected, APK not built |

At the foundation stage Android export prerequisites were incomplete. The native
application task has since installed them and produced actual Windows, APK and
test-signed AAB artifacts; see [current export instructions](../application/EXPORTS.md).
A successful export does not imply a physical device test. Node 24 is needed for the legacy
SQLite tests. Use installed tools as the current user.

## Local checks

From repository root:

```sh
npm ci
npm run lint
npm test
npm run build
npm run test:contracts
npm run test:classic
godot --headless --path godot --editor --import
godot --headless --path godot --quit-after 2
# Interactive native foundation:
godot --path godot
```

`npm test` runs Claude's unchanged native combat suites and standalone arena
through `scripts/test-native-combat.mjs`. Its fixed 60 Hz presentation clock
keeps animated asset sampling reproducible; socket/server clock tests use real
time. Claude's optional `tests/combat/` Node wrapper still uses its own launch
configuration. No combat-owned assertions are skipped or changed. The foundation's
contract tests are a separate mandatory check (`test:contracts`), not included
silently in the existing `npm test` glob.

On machines with an unwritable home (as in this cloud sandbox), point the XDG
paths to a task-local scratch directory **without changing HOME**:

```sh
mkdir -p work/runtime/data work/runtime/config work/runtime/cache
export XDG_DATA_HOME="$PWD/work/runtime/data"
export XDG_CONFIG_HOME="$PWD/work/runtime/config"
export XDG_CACHE_HOME="$PWD/work/runtime/cache"
godot --headless --path godot --editor --import
godot --headless --path godot --quit-after 2
```

The contract runner creates temporary writable XDG directories automatically.
Set `GODOT_BIN` if the binary has another path. Godot import/scene checks must
have exit code 0 **and** no SCRIPT ERROR/parse/resource errors in their output;
Godot can exit successfully despite some script import errors. The CI workflow
checks these diagnostics explicitly.

## Android and release follow-up

Install matching official Godot 4.6.3 templates plus Android command-line tools,
platform-tools, Android platform/build-tools required by the 4.6.3 exporter and
accept SDK licenses. Verify exact requirements against the pinned Godot Android
export documentation before committing native export presets. Preserve existing
Capacitor API 35 configuration until its own migration is reviewed. Record SDK,
NDK (only if a custom native build needs it), JDK, package identifiers and signing
requirements in the export PR. Do not commit local SDK paths or keystores.

This task deliberately adds no unverified export preset or release pipeline.
CI validates the current web build and native foundation; Windows/Android export,
signing, store distribution and device runs are subsequent release gates.

## Native application update — 2026-11-11

Accounts and matchmaking use Node24, PostgreSQL17 (production) or SQLite
(local tests), plus the existing Godot dedicated server. Run `npm run test:backend`
and `npm run test:application` in addition to the checks above. PostgreSQL
transactions also run in CI against a disposable PostgreSQL17 service.

Official4.6.3 templates, Android SDK36/build-tools36.1.0 and a full Temurin
JDK21 are now installed in ignored task-local directories. APK signing uses a
disposable debug key; the actual AAB is test-signed, not a store release.
See EXPORTS.md for checksums, installation and production-signing requirements.

The combat owner tests inject logical control positions into a physical-coordinate
API. `godot/tests/run_combat_tests.gd` gives those fixtures an unscaled window
without modifying their assertions. `test_scaled_touch.gd` separately verifies
physical touch coordinates under the application's real canvas scaling. Both
run from the existing `npm test` combat harness. Fixed60FPS is still test-only.
