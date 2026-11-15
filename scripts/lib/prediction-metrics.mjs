import assert from 'node:assert/strict';

// The client records continuous prediction errors separately from catchups when
// prediction resumes after an action, stagger or teleport. Its hard_snaps total
// includes both. Keep the continuous-error gates strict without treating a
// legitimate authoritative teleport as a movement prediction failure.
export function assertPredictionMetrics(sample, stalled, label) {
  const total = sample.stats.hard_snaps;
  const resumed = sample.resumeHardSnaps;
  assert.ok(Number.isInteger(total) && Number.isInteger(resumed) && resumed >= 0 && resumed <= total,
    `${label}: consistent hard-snap classification`);
  assert.ok(total - resumed <= (stalled ? 4 : 0),
    `${label}: continuous prediction hard snaps ${total - resumed} (stalled=${stalled}; resume catchups=${resumed})`);
  assert.equal(sample.stats.rejected, 0, `${label}: no snapshot rejected by the client`);
  assert.ok(sample.corrections.mean < (stalled ? 0.4 : 0.15), `${label}: mean prediction error ${sample.corrections.mean}`);
  assert.ok(sample.corrections.max < (stalled ? 7 : 1.2), `${label}: worst correction ${sample.corrections.max}`);
}
