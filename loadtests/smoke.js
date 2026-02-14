/**
 * Smoke Test
 *
 * Purpose: Verify the system works under minimal load
 *
 * This test should be run:
 * - After deployments
 * - As a quick sanity check
 * - In CI pipelines
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:4000 smoke.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
export const options = {
  vus: 1,
  duration: __ENV.DURATION || '1m',
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests should be below 500ms
    errors: ['rate<0.01'],             // Error rate should be below 1%
    http_req_failed: ['rate<0.01'],    // HTTP errors should be below 1%
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  // Test health endpoint
  const healthRes = http.get(`${BASE_URL}/healthz`);
  check(healthRes, {
    'health status is 200 or 503': (r) => r.status === 200 || r.status === 503,
    'health response has status': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status !== undefined;
      } catch {
        return false;
      }
    },
  }) || errorRate.add(1);

  sleep(1);

  // Test root endpoint
  const rootRes = http.get(`${BASE_URL}/`);
  check(rootRes, {
    'root status is 200': (r) => r.status === 200,
    'root has service metadata': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.service !== undefined && body.version !== undefined;
      } catch {
        return false;
      }
    },
  }) || errorRate.add(1);

  sleep(1);

  // Test OpenAPI endpoint
  const openapiRes = http.get(`${BASE_URL}/api/v1/openapi`);
  check(openapiRes, {
    'openapi status is 200': (r) => r.status === 200,
    'openapi payload has openapi field': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.openapi !== undefined;
      } catch {
        return false;
      }
    },
  }) || errorRate.add(1);

  sleep(1);

  // Test unauthenticated protected endpoint
  const meRes = http.get(`${BASE_URL}/api/v1/me`);
  check(meRes, {
    'me status is 401 when unauthenticated': (r) => r.status === 401,
  }) || errorRate.add(1);

  sleep(1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'smoke-results.json': JSON.stringify(data),
  };
}

function textSummary(data, opts) {
  // Simple text summary
  const duration = data.metrics.http_req_duration;
  const requests = data.metrics.http_reqs;
  const errors = data.metrics.http_req_failed;

  return `
=== Smoke Test Results ===

Requests:     ${requests?.values?.count || 0}
Duration:     p50=${duration?.values?.med?.toFixed(2) || 0}ms, p95=${duration?.values['p(95)']?.toFixed(2) || 0}ms
Error Rate:   ${((errors?.values?.rate || 0) * 100).toFixed(2)}%

Thresholds:
  - p95 < 500ms: ${(duration?.values['p(95)'] || 0) < 500 ? '✓ PASS' : '✗ FAIL'}
  - Error rate < 1%: ${((errors?.values?.rate || 0) * 100) < 1 ? '✓ PASS' : '✗ FAIL'}
`;
}
