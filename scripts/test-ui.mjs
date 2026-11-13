// Native UI design-system checks (headless, deterministic): theme / contrast / preferences / kit, then page layout at
// six resolutions + 150 % UI scale, safe-area insets, focus traversal and interrupted transitions; then an overlap audit
// (nothing visible may sit on top of anything else visible) over pages, the chess screen, dialogs and a battle; then the existing
// opening screen (3D intro), application, online, battle and classic view UI suites so a restyle can never silently break them.
// Fails on any SCRIPT ERROR / Parse Error / "ERROR:" / "FAIL:" line.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const directory = mkdtempSync(join(tmpdir(), 'peepeechess-ui-'));
// Every suite gets its own user:// / cache directories: suites save preferences (touch controls, quality...) and
// must not influence each other.
let counter = 0;
const freshEnv = () => {
  const env = { ...process.env };
  const base = join(directory, String(counter++));
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
    env[key] = join(base, key); mkdirSync(env[key], { recursive: true });
  }
  return env;
};
const importEnv = freshEnv();
const godot = process.env.GODOT_BIN || 'godot';
// The online and battle suites save view3d=true into preferences; the classic view suite is order-sensitive to
// that when every run shares one user:// directory (an existing coupling), so it runs before them.
const suites = [
  'res://tests/ui/ui_theme_test.gd',
  'res://tests/ui/ui_layout_test.gd',
  'res://tests/ui/ui_overlap_test.gd',   // overlap / clipping / tiny-target audit of every page, the match screen, dialogs and a whole battle
  'res://tests/ui/opening_screen_test.gd',
  'res://tests/test_application_ui.gd',
  'res://tests/classic/views_test.gd',
  'res://tests/network/online_ui_test.gd',
  'res://tests/battle/ui_test.gd',
];
try {
  const run = (args, env = freshEnv()) => {
    const r = spawnSync(godot, ['--headless', '--path', 'godot', ...args], { env, encoding: 'utf8', timeout: 600000 });
    const output = (r.stdout || '') + (r.stderr || '');
    process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
    if (r.error || r.status !== 0 || /SCRIPT ERROR|Parse Error|^ERROR:|^FAIL:/m.test(output)) throw r.error || Error(`UI check failed (${args.join(' ')}): exit ${r.status}`);
  };
  run(['--editor', '--import'], importEnv);
  for (const suite of suites) run(['--script', suite]);
  console.log('PASS: native UI design system, layout, focus and existing UI suites');
} finally { rmSync(directory, { recursive: true, force: true }); }
