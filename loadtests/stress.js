/**
 * Stress Test
 *
 * Purpose: Find the system's breaking point
 *
 * This test gradually increases load beyond normal levels to identify:
 * - Maximum capacity
 * - Failure modes
 * - Recovery behavior
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:4000 stress.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const responseTrend = new Trend('response_time');

// Test configuration - gradually increase load
export const options = {
  stages: [
    { duration: '2m', target: 20 },   // Warm up
    { duration: '2m', target: 50 },   // Normal load
    { duration: '2m', target: 100 },  // Elevated load
    { duration: '2m', target: 150 },  // High load
    { duration: '2m', target: 200 },  // Very high load
    { duration: '3m', target: 200 },  // Stay at peak
    { duration: '2m', target: 100 },  // Scale down
    { duration: '2m', target: 0 },    // Recovery
  ],
  thresholds: {
    // Relaxed thresholds - we expect degradation
    http_req_duration: ['p(95)<5000'], // 5s max
    errors: ['rate<0.20'],              // Up to 20% errors acceptable
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  // Mix of endpoints to stress different parts of the system

  // Health check (fast, lightweight)
  const healthRes = http.get(`${BASE_URL}/healthz`);
  responseTrend.add(healthRes.timings.duration);
  check(healthRes, {
    'health ok': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(0.5);

  // Root endpoint
  const rootRes = http.get(`${BASE_URL}/`);
  responseTrend.add(rootRes.timings.duration);
  check(rootRes, {
    'root ok': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(0.5);

  // Detailed health check (heavier, touches DB and cache)
  const detailedRes = http.get(`${BASE_URL}/healthz?detailed=true`);
  responseTrend.add(detailedRes.timings.duration);
  check(detailedRes, {
    'detailed health ok': (r) => r.status === 200 || r.status === 503,
  }) || errorRate.add(1);

  sleep(1);
}

export function handleSummary(data) {
  return {
    'stdout': generateStressSummary(data),
    'stress-results.json': JSON.stringify(data),
  };
}

function generateStressSummary(data) {
  const duration = data.metrics.http_req_duration;
  const requests = data.metrics.http_reqs;
  const errors = data.metrics.http_req_failed;

  return `
=== Stress Test Results ===

Total Requests: ${requests?.values?.count || 0}
Peak Request Rate: ${requests?.values?.rate?.toFixed(2) || 0} req/s

Response Time:
  - p50: ${duration?.values?.med?.toFixed(2) || 0}ms
  - p95: ${duration?.values['p(95)']?.toFixed(2) || 0}ms
  - p99: ${duration?.values['p(99)']?.toFixed(2) || 0}ms
  - max: ${duration?.values?.max?.toFixed(2) || 0}ms

Error Rate: ${((errors?.values?.rate || 0) * 100).toFixed(2)}%

Analysis:
  - If error rate stays low throughout: System can handle this load
  - If errors spike at specific VU count: That's your capacity limit
  - If recovery is slow: Consider auto-scaling tuning

Note: Some degradation is expected in stress tests.
`;
}
