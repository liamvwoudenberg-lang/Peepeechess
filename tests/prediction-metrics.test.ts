import test from 'node:test';
import assert from 'node:assert/strict';
import { assertPredictionMetrics } from '../scripts/lib/prediction-metrics.mjs';

test('online movement gates distinguish action-resume teleports from continuous prediction failures', () => {
  // Values from the real Bishop/Knight socket scenario on 2026-11-15:
  // 2.517 m resume catchup; continuous error max 0.834 m and mean 0.021 m.
  const sample = {
    stats: { hard_snaps: 1, rejected: 0 },
    resumeHardSnaps: 1,
    corrections: { mean: 0.021129, max: 0.833889 },
  };
  assert.doesNotThrow(() => assertPredictionMetrics(sample, false, 'bishop resume'));
  assert.throws(() => assertPredictionMetrics({ ...sample, resumeHardSnaps: 0 }, false, 'continuous snap'), /continuous prediction hard snaps/);
  assert.throws(() => assertPredictionMetrics({ ...sample, corrections: { mean: 0.02, max: 1.21 } }, false, 'large continuous error'), /worst correction/);
  assert.throws(() => assertPredictionMetrics({ ...sample, corrections: { mean: 0.16, max: 0.8 } }, false, 'persistent error'), /mean prediction error/);
  assert.throws(() => assertPredictionMetrics({ ...sample, stats: { hard_snaps: 1, rejected: 1 } }, false, 'invalid snapshot'), /no snapshot rejected/);
  assert.throws(() => assertPredictionMetrics({ ...sample, resumeHardSnaps: 2 }, false, 'invalid counts'), /consistent hard-snap classification/);
  assert.throws(() => assertPredictionMetrics({ ...sample, resumeHardSnaps: -1 }, false, 'negative counts'), /consistent hard-snap classification/);
  assert.doesNotThrow(() => assertPredictionMetrics({ ...sample, resumeHardSnaps: 0 }, true, 'stalled link'));
  assert.throws(() => assertPredictionMetrics({ ...sample, stats: { hard_snaps: 6, rejected: 0 } }, true, 'unbounded stalled link'), /continuous prediction hard snaps/);
});
