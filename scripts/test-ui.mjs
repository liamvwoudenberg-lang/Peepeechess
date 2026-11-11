// Native UI design-system checks (headless, deterministic): theme / contrast / preferences / kit, then page layout at
// six resolutions + 150 % UI scale, safe-area insets, focus traversal and interrupted transitions; then the existing
// application, online, battle and classic view UI suites so a restyle can never silently break them.
// Fails on any SCRIPT ERROR / Parse Error / "ERROR:" / "FAIL:" line.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const directory = mkdtempSync(join(tmpdir(), 'peepeechess-ui-'));
const env = { ...process.env };
for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) {
  env[key] = join(directory, key); mkdirSync(env[key]);
}
const godot = process.env.GODOT_BIN || 'godot';
const suites = [
  'res://tests/ui/ui_theme_test.gd',
  'res://tests/ui/ui_layout_test.gd',
  'res://tests/test_application_ui.gd',
  'res://tests/network/online_ui_test.gd',
  'res://tests/battle/ui_test.gd',
  'res://tests/classic/views_test.gd',
];
try {
  const run = args => {
    const r = spawnSync(godot, ['--headless', '--path', 'godot', ...args], { env, encoding: 'utf8', timeout: 600000 });
    const output = (r.stdout || '') + (r.stderr || '');
    process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
    if (r.error || r.status !== 0 || /SCRIPT ERROR|Parse Error|^ERROR:|^FAIL:/m.test(output)) throw r.error || Error(`UI check failed (${args.join(' ')}): exit ${r.status}`);
  };
  run(['--editor', '--import']);
  for (const suite of suites) run(['--script', suite]);
  console.log('PASS: native UI design system, layout, focus and existing UI suites');
} finally { rmSync(directory, { recursive: true, force: true }); }
