import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

test("native export presets separate test APK, release AAB and Windows without secrets", () => {
  const presets = readFileSync("godot/export_presets.cfg", "utf8");
  assert.match(presets, /name="Windows Desktop"/);
  assert.match(presets, /binary_format\/embed_pck=true/);
  assert.match(presets, /binary_format\/architecture="x86_64"/);
  assert.match(presets, /name="Android Debug APK"/);
  assert.match(presets, /name="Android Release AAB"/);
  assert.equal((presets.match(/permissions\/internet=true/g) || []).length, 2);
  assert.equal((presets.match(/user_data_backup\/allow=false/g) || []).length, 2);
  assert.match(presets, /gradle_build\/export_format=1/);
  assert.match(presets, /gradle_build\/target_sdk="36"/);
  assert.match(presets, /gradle_build\/min_sdk="26"/);
  assert.doesNotMatch(presets, /(?:keystore|password|private_key).*=/);
  assert.doesNotMatch(presets, /[A-Z]:\\|\/workspace\//);
});

test("Godot controller presentation controls preserve fixed authoritative tick frequency", () => {
  const temporary = mkdtempSync(join(tmpdir(), "peepeechess-export-controls-"));
  try {
    const script = join(temporary, "check.gd");
    writeFileSync(script, `extends SceneTree
const Platform = preload("res://ui/platform_input.gd")
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var initial_hz := Engine.physics_ticks_per_second
    var controls = Platform.new()
    root.add_child(controls)
    assert(InputMap.has_action("app_menu"))
    assert(InputMap.has_action("app_back"))
    for level in ["low", "balanced", "high", "invalid"]:
        Platform.set_quality(level)
        assert(Engine.physics_ticks_per_second == initial_hz)
    Platform.set_quality("low")
    assert(Engine.max_fps == 30)
    assert(root.msaa_3d == Viewport.MSAA_DISABLED)
    Platform.set_quality("balanced")
    assert(Engine.max_fps == 60)
    assert(root.msaa_3d == Viewport.MSAA_2X)
    var child_view := SubViewport.new()
    root.add_child(child_view)
    assert(child_view.msaa_3d == Viewport.MSAA_2X)
    controls.set_cursor_enabled(false)
    assert(not controls.cursor_enabled)
    controls.set_cursor_enabled(true)
    assert(controls.cursor_enabled)
    child_view.free()
    controls.free()
    print("NATIVE_EXPORT_CONTROLS_OK")
    quit(0)
`);
    const result = spawnSync(process.env.GODOT_BIN || "godot", ["--headless", "--path", resolve("godot"), "--script", script], {
      encoding: "utf8", timeout: 30000,
      env: { ...process.env, XDG_DATA_HOME: join(temporary, "data"), XDG_CONFIG_HOME: join(temporary, "config"), XDG_CACHE_HOME: join(temporary, "cache") },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /SCRIPT ERROR|Parse Error|ERROR:/);
    assert.match(output, /NATIVE_EXPORT_CONTROLS_OK/);
  } finally { rmSync(temporary, { recursive: true, force: true }); }
});

test("export script rejects zero-exit Godot errors and aligns inherited Android SDK paths", () => {
  const temporary = mkdtempSync(join(tmpdir(), "peepeechess-export-diagnostics-"));
  try {
    mkdirSync(join(temporary, "scripts"));
    const script = join(temporary, "scripts", "export-native.sh");
    writeFileSync(script, readFileSync("scripts/export-native.sh", "utf8"));
    const templates = join(temporary, "toolchains", "godot", "templates", "4.6.3.stable");
    mkdirSync(templates, { recursive: true });
    const fakeGodot = join(temporary, "godot-probe");
    writeFileSync(fakeGodot, `#!/bin/sh
if [ "$1" = "--version" ]; then
  printf '%s\\n' '4.6.3.stable.official.test'
else
  printf '%s\\n' "SDK_ROOT=$ANDROID_SDK_ROOT" 'SCRIPT ERROR: injected zero-exit import failure'
fi
exit 0
`, { mode: 0o755 });
    const sdk = join(temporary, "selected-sdk");
    const result = spawnSync("bash", [script, "windows"], {
      encoding: "utf8", timeout: 15000,
      env: {
        ...process.env, GODOT_BIN: fakeGodot,
        PEEPEECHESS_TOOLCHAIN_DIR: join(temporary, "toolchains"),
        ANDROID_HOME: sdk, ANDROID_SDK_ROOT: "/inherited/different/sdk",
      },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 1, output);
    assert.ok(output.includes(`SDK_ROOT=${sdk}`), output);
    assert.match(output, /Godot export\/import reported errors/);
    assert.doesNotMatch(output, /rg:.*not found/);
  } finally { rmSync(temporary, { recursive: true, force: true }); }
});
