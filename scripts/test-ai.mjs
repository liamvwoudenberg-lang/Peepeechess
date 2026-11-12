// Computer opponent + board settings suites (headless Godot). Run from the repository root: npm run test:ai
// Gate is the same as the other native suites: a non-zero exit, SCRIPT ERROR, Parse Error or any line starting with
// `ERROR:` (leaked resources at exit included) fails the run. Self-play games run as parallel shards.
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const temporary = mkdtempSync(join(tmpdir(), 'peepeechess-ai-'));
const godot = process.env.GODOT_BIN || 'godot';
const shards = Number(process.env.AI_SHARDS || 3);
const diagnostics = /SCRIPT ERROR|Parse Error|^ERROR:/m;
let counter = 0;
const run = (label, args, timeout = 900000) => new Promise((resolve, reject) => {
  const env = { ...process.env };
  const home = join(temporary, String(counter++));
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) { env[key] = join(home, key); mkdirSync(env[key], { recursive: true }); }
  const child = spawn(godot, ['--headless', '--path', 'godot', ...args], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  let log = '';
  child.stdout.on('data', d => { log += d; });
  child.stderr.on('data', d => { log += d; });
  const timer = setTimeout(() => child.kill('SIGTERM'), timeout);
  child.on('close', code => {
    clearTimeout(timer);
    process.stdout.write(`--- ${label}\n${log.split('\n').filter(l => /^(AI |RULES|STRENGTH|TACTICS|mates|budget|battle game|duel |game \d|FAIL|ERROR|SCRIPT)/.test(l)).join('\n')}\n`);
    if (code !== 0 || diagnostics.test(log)) reject(Error(`${label} failed (exit ${code})\n${log.slice(-3000)}`));
    else resolve();
  });
});
try {
  await run('import', ['--editor', '--import'], 180000);
  const jobs = [];
  for (let shard = 0; shard < shards; shard++) jobs.push(run(`rules shard ${shard}/${shards}`, ['--script', 'res://tests/ai/ai_rules_test.gd', '--', `shard=${shard}`, `shards=${shards}`]));
  await Promise.all(jobs);
  for (const name of ['ai_tactics_test', 'ai_strength_test', 'ai_battle_test', 'ai_combat_test', 'ai_ui_test']) await run(name, ['--script', `res://tests/ai/${name}.gd`]);
  console.log('PASS: computer opponent (legality, determinism, tactics, budget, cancellation, strength, Battle, combat seat) and board settings');
} finally { rmSync(temporary, { recursive: true, force: true }); }
