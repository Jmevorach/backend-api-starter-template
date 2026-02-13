/**
 * Spike Test
 *
 * Purpose: Test system behavior under sudden traffic spikes
 *
 * This simulates scenarios like:
 * - Marketing campaign launch
 * - Product announcement
 * - Traffic redirect from another service
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:4000 spike.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Normal load
    { duration: '10s', target: 100 },  // Sudden spike!
    { duration: '1m', target: 100 },   // Stay at spike
    { duration: '10s', target: 10 },   // Drop back
    { duration: '1m', target: 10 },    // Recovery period
    { duration: '30s', target: 0 },    // Cool down
  ],
  thresholds: {
    // Focus on recovery rather than spike performance
    http_req_duration: ['p(95)<3000'],
    errors: ['rate<0.15'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  // Simulate burst of requests

  const responses = http.batch([
    ['GET', `${BASE_URL}/healthz`],
    ['GET', `${BASE_URL}/`],
  ]);

  responses.forEach((res, i) => {
    check(res, {
      [`batch ${i}: status ok`]: (r) => r.status === 200,
    }) || errorRate.add(1);
  });

  sleep(0.5);
}

export function handleSummary(data) {
  return {
    'stdout': generateSpikeSummary(data),
    'spike-results.json': JSON.stringify(data),
  };
}

function generateSpikeSummary(data) {
  const duration = data.metrics.http_req_duration;
  const requests = data.metrics.http_reqs;
  const errors = data.metrics.http_req_failed;

  return `
=== Spike Test Results ===

Total Requests: ${requests?.values?.count || 0}
Request Rate:   ${requests?.values?.rate?.toFixed(2) || 0} req/s

Response Time:
  - p50: ${duration?.values?.med?.toFixed(2) || 0}ms
  - p95: ${duration?.values['p(95)']?.toFixed(2) || 0}ms
  - p99: ${duration?.values['p(99)']?.toFixed(2) || 0}ms

Error Rate: ${((errors?.values?.rate || 0) * 100).toFixed(2)}%

Key Questions:
  1. Did the system handle the spike without crashing?
  2. How quickly did response times recover after the spike?
  3. Were there any cascading failures?

If error rate > 15% during spike: Consider rate limiting or queue-based load leveling
If recovery is slow: Auto-scaling may need tuning
`;
}
