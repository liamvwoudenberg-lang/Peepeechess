// C0 balance snapshot from the existing combat configuration; no combat source edits.
import { FIGHTERS } from '../src/battle/config.ts';
import { readFileSync, writeFileSync } from 'node:fs';
const target = new URL('../godot/chess/battle_stats.json', import.meta.url);
const stats = Object.fromEntries(Object.entries(FIGHTERS).map(([role, c]) => [role, {
  schemaVersion: 1, statsId: `c0-balance-v1.${role}`, role,
  maxHp: c.hp, maxStamina: c.stamina, baseDamage: c.damage,
  moveSpeedMps: Number((1.05 + c.speed * 0.29).toFixed(2)), reachM: c.reach,
  lightTicks: Math.ceil(c.light * 60), heavyTicks: Math.ceil(c.heavy * 60),
  parryTicks: Math.ceil(c.parry * 60), abilityId: c.ability.toLowerCase().replaceAll(' ', '-'),
  cooldownTicks: Math.ceil(c.cooldown * 60),
}]));
const json = JSON.stringify(stats, null, 2) + '\n';
if (process.argv.includes('--write')) writeFileSync(target, json);
else if (readFileSync(target, 'utf8') !== json) throw Error('C0 balance snapshot differs; regenerate with --write and review the stats version');
