import { AntiCheatReport, MoveTelemetry } from '../types/chess';

const BANNED_PATTERNS = [
  /cheat/i,
  /botting/i,
  /stockfish/i,
  /trash/i,
  /idiot/i,
  /noob/i,
  /stfu/i,
  /hate/i,
];

/**
 * Filters and sanitizes in-game chat for fair play and medieval sportsmanship.
 */
export function sanitizeChatMessage(raw: string): { cleanText: string; isToxic: boolean } {
  let cleanText = raw;
  let isToxic = false;

  for (const pattern of BANNED_PATTERNS) {
    if (pattern.test(cleanText)) {
      isToxic = true;
      cleanText = cleanText.replace(pattern, '***');
    }
  }

  return { cleanText, isToxic };
}

/**
 * Evaluates move latency patterns and engine correlation to identify computer assistance.
 */
export function evaluateAntiCheatTelemetry(telemetryList: MoveTelemetry[]): AntiCheatReport {
  if (telemetryList.length < 5) {
    return {
      suspicionScore: 0,
      accuracyCorrelation: 0,
      uniformLatencyScore: 0,
      isFlaggedForAudit: false,
      recommendedPool: 'clean',
    };
  }

  // 1. Engine Correlation: % of moves matching #1 top engine suggestion
  const engineMatches = telemetryList.filter((t) => t.isEngineFirstChoice).length;
  const accuracyCorrelation = Math.round((engineMatches / telemetryList.length) * 100);

  // 2. Uniform Latency Analysis: Bots often take almost identical seconds per move (e.g. 2100ms +- 50ms)
  const latencies = telemetryList.map((t) => t.latencyMs);
  const meanLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length;
  const variance = latencies.reduce((sum, l) => sum + Math.pow(l - meanLatency, 2), 0) / latencies.length;
  const stdDev = Math.sqrt(variance);

  // If moves are played with suspiciously low standard deviation (< 350ms across 10+ moves)
  let uniformLatencyScore = 0;
  if (telemetryList.length >= 8 && stdDev < 400 && meanLatency > 1200) {
    uniformLatencyScore = Math.min(100, Math.round((1 - stdDev / 400) * 100));
  }

  // 3. Tab Switching Frequency
  const totalTabSwitches = telemetryList.reduce((sum, t) => sum + (t.tabSwitchCount || 0), 0);

  // Composite Suspicion Score
  let suspicionScore = 0;
  if (accuracyCorrelation >= 92) suspicionScore += 50;
  else if (accuracyCorrelation >= 82) suspicionScore += 25;

  if (uniformLatencyScore >= 60) suspicionScore += 30;
  if (totalTabSwitches >= 6 && accuracyCorrelation >= 80) suspicionScore += 25;

  suspicionScore = Math.min(100, suspicionScore);
  const isFlaggedForAudit = suspicionScore >= 70;

  let recommendedPool: 'clean' | 'probation' | 'isolated' = 'clean';
  if (suspicionScore >= 80) recommendedPool = 'isolated';
  else if (suspicionScore >= 50) recommendedPool = 'probation';

  return {
    suspicionScore,
    accuracyCorrelation,
    uniformLatencyScore,
    isFlaggedForAudit,
    recommendedPool,
  };
}
