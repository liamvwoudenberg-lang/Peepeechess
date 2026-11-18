// Online duel report: bot-vs-bot duels through the network simulator (latency, jitter, loss, reorder, duplication) under the real rules.
// Four Godot shards in parallel, then the summary table; exit 1 on any desync / incomplete duel at or below 150 ms / 2 % loss.
//   npm run test:net-report -- 64          (duels per profile, default 24)
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const n = process.argv[2] || '24';
const dir = mkdtempSync(join(tmpdir(), 'peepeechess-net-'));
const godot = process.env.GODOT_BIN || 'godot';
const shards = 4;
spawnSync(godot, ['--headless', '--path', 'godot', '--editor', '--import'], { stdio: 'ignore' });
await Promise.all([...Array(shards).keys()].map(i => new Promise((resolve, reject) => {
  const p = spawn(godot, ['--headless', '--path', 'godot', '--script', 'res://combat/tools/net_report.gd', '--', `n=${n}`, 'seed=1', 'profiles=all', `shard=${i}/${shards}`, `out=${join(dir, `net-${i}.json`)}`], { stdio: ['ignore', 'ignore', 'inherit'] });
  p.on('exit', code => code === 0 ? resolve() : reject(Error(`shard ${i} failed (${code})`)));
})));
const r = spawnSync('python3', ['godot/combat/tools/summarize_net.py', join(dir, 'net-*.json')], { stdio: 'inherit' });
process.exit(r.status ?? 1);
