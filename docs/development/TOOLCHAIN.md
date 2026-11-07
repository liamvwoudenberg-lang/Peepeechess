# Reproducible toolchain

Pinned native runtime: **Godot 4.6.3 stable**, standard GDScript build, matching
4.6.3 export templates. `.godot-version` is the source for CI's download/version
check. Compatibility renderer starts with OpenGL on Windows and OpenGL ES on
Android to keep the initial project modest. No addons or .NET runtime required.

Observed 2026-11-07 in this Linux environment:

| Tool | Observed result |
| --- | --- |
| Godot | `4.6.3.stable.official.7d41c59c4`, `/usr/local/bin/godot` and godot4 aliases |
| Blender | 4.3.2; factory-startup background Python probe completed successfully |
| Node/npm | Node v24.22.1; use Node 24 LTS and `npm ci` with committed lockfile |
| Java | OpenJDK 21.0.13 |
| Android tools | adb and sdkmanager absent from PATH; no SDK/platform android.jar found in searched /usr, /opt, /workspace paths |
| Export templates | No templates found in the inspected Godot installation/user template locations; no export was attempted |
| Existing Android project | Capacitor, Gradle 8.11.1 wrapper, AGP 8.7.2, minSdk 23 and compile/targetSdk 35; source configuration inspected, APK not built |

Godot is available; Android native/export prerequisites are incomplete. Do not
claim a Windows executable or Godot APK is validated. Blender availability does
not imply generated assets/rigs already exist. Node 24 is needed for the legacy
SQLite tests. Use installed tools as the current user.

## Local checks

From repository root:

```sh
npm ci
npm run lint
npm test
npm run build
npm run test:contracts
godot --headless --path godot --editor --import
godot --headless --path godot --quit-after 2
# Interactive native foundation:
godot --path godot
```

The nested `tests/combat/` directory is reserved for Claude's future tests;
add its glob to the test script when tests are introduced. The foundation's
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
