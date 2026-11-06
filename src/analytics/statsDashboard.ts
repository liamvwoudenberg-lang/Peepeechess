import { CategoryStats, LifetimeStats } from '../types/chess';

const STATS_STORAGE_KEY = 'sovereigns_gambit_lifetime_stats_v1';

function createMockHistory(baseRating: number, count = 12) {
  const points = [];
  let r = baseRating - 80;
  const now = Date.now();
  for (let i = 0; i < count; i++) {
    const delta = (Math.sin(i * 0.8) * 22) + (Math.random() * 20 - 8);
    r = Math.round(Math.max(400, r + delta));
    points.push({
      timestamp: now - (count - i) * 86400000,
      rating: r,
      opponentRating: r + Math.floor(Math.random() * 60 - 30),
      result: (Math.random() > 0.45 ? 'win' : Math.random() > 0.2 ? 'loss' : 'draw') as 'win' | 'loss' | 'draw',
    });
  }
  return points;
}

export const DEFAULT_LIFETIME_STATS: LifetimeStats = {
  bullet: {
    rating: 1180,
    peakRating: 1245,
    wins: 48,
    losses: 39,
    draws: 8,
    history: createMockHistory(1180),
  },
  blitz: {
    rating: 1260,
    peakRating: 1315,
    wins: 92,
    losses: 74,
    draws: 14,
    history: createMockHistory(1260),
  },
  rapid: {
    rating: 1340,
    peakRating: 1395,
    wins: 115,
    losses: 81,
    draws: 22,
    history: createMockHistory(1340),
  },
  daily: {
    rating: 1420,
    peakRating: 1460,
    wins: 28,
    losses: 12,
    draws: 5,
    history: createMockHistory(1420),
  },
  puzzleRating: 1540,
  puzzleRushHighscore: 24,
  tacticalAccuracyAvg: 79.4,
  tiltFactorScore: 18, // 18% (Low tilt)
  favoriteOpening: 'Italian Game (Giuoco Piano)',
};

export function loadLifetimeStats(): LifetimeStats {
  try {
    const raw = localStorage.getItem(STATS_STORAGE_KEY);
    if (raw) {
      return JSON.parse(raw);
    }
  } catch {
    // fallback
  }
  return DEFAULT_LIFETIME_STATS;
}

export function saveLifetimeStats(stats: LifetimeStats): void {
  try {
    localStorage.setItem(STATS_STORAGE_KEY, JSON.stringify(stats));
  } catch {
    // ignore
  }
}

export function recordMatchOutcome(
  category: 'bullet' | 'blitz' | 'rapid' | 'daily',
  result: 'win' | 'loss' | 'draw',
  ratingDelta: number
): LifetimeStats {
  const current = loadLifetimeStats();
  const cat = current[category];

  cat.rating = Math.max(400, cat.rating + ratingDelta);
  cat.peakRating = Math.max(cat.peakRating, cat.rating);
  if (result === 'win') cat.wins++;
  else if (result === 'loss') cat.losses++;
  else cat.draws++;

  cat.history.push({
    timestamp: Date.now(),
    rating: cat.rating,
    opponentRating: cat.rating,
    result,
  });

  // Calculate tilt factor based on last 5 games
  const recent = cat.history.slice(-5);
  const consecutiveLosses = recent.filter((p) => p.result === 'loss').length;
  current.tiltFactorScore = Math.min(100, Math.round((consecutiveLosses / 5) * 80 + 10));

  saveLifetimeStats(current);
  return current;
}
