/**
 * Load Test
 *
 * Purpose: Test system under normal expected load
 *
 * This test simulates typical production traffic patterns with
 * realistic user behavior and concurrent requests.
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:4000 load.js
 *   k6 run --env BASE_URL=http://localhost:4000 --env VUS=100 load.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const healthTrend = new Trend('health_duration');
const apiTrend = new Trend('api_duration');

// Test configuration
export const options = {
  stages: [
    { duration: '1m', target: 10 },   // Ramp up to 10 users
    { duration: '3m', target: 50 },   // Ramp up to 50 users
    { duration: '5m', target: 50 },   // Stay at 50 users
    { duration: '2m', target: 10 },   // Ramp down to 10 users
    { duration: '1m', target: 0 },    // Ramp down to 0
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000', 'p(99)<2000'], // Response time
    errors: ['rate<0.05'],                            // Error rate < 5%
    http_req_failed: ['rate<0.05'],                   // HTTP errors < 5%
    health_duration: ['p(95)<200'],                   // Health check fast
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const AUTH_TOKEN = __ENV.AUTH_TOKEN || '';

// Common headers
const headers = AUTH_TOKEN ? { 'Authorization': `Bearer ${AUTH_TOKEN}` } : {};
const jsonHeaders = { ...headers, 'Content-Type': 'application/json' };

export default function () {
  // Simulate realistic user behavior with multiple requests

  group('Health Check', function () {
    const res = http.get(`${BASE_URL}/healthz`);
    healthTrend.add(res.timings.duration);

    check(res, {
      'health: status 200': (r) => r.status === 200,
    }) || errorRate.add(1);
  });

  sleep(randomBetween(0.5, 1.5));

  group('API Root', function () {
    const res = http.get(`${BASE_URL}/`);
    apiTrend.add(res.timings.duration);

    check(res, {
      'root: status 200': (r) => r.status === 200,
      'root: has version': (r) => {
        try {
          return JSON.parse(r.body).version !== undefined;
        } catch {
          return false;
        }
      },
    }) || errorRate.add(1);
  });

  sleep(randomBetween(1, 3));

  // If we have auth, test authenticated endpoints
  if (AUTH_TOKEN) {
    group('Authenticated API', function () {
      const meRes = http.get(`${BASE_URL}/api/me`, { headers });
      apiTrend.add(meRes.timings.duration);

      check(meRes, {
        'me: status 200 or 401': (r) => r.status === 200 || r.status === 401,
      }) || errorRate.add(1);

      sleep(randomBetween(0.5, 1));

      // Notes API
      const notesRes = http.get(`${BASE_URL}/api/notes`, { headers });
      apiTrend.add(notesRes.timings.duration);

      check(notesRes, {
        'notes: status 200 or 401': (r) => r.status === 200 || r.status === 401,
      }) || errorRate.add(1);
    });
  }

  sleep(randomBetween(2, 5));
}

function randomBetween(min, max) {
  return Math.random() * (max - min) + min;
}

export function handleSummary(data) {
  return {
    'stdout': generateSummary(data),
    'load-results.json': JSON.stringify(data),
  };
}

function generateSummary(data) {
  const duration = data.metrics.http_req_duration;
  const requests = data.metrics.http_reqs;
  const errors = data.metrics.http_req_failed;

  return `
=== Load Test Results ===

Total Requests: ${requests?.values?.count || 0}
Request Rate:   ${requests?.values?.rate?.toFixed(2) || 0} req/s

Response Time:
  - p50: ${duration?.values?.med?.toFixed(2) || 0}ms
  - p95: ${duration?.values['p(95)']?.toFixed(2) || 0}ms
  - p99: ${duration?.values['p(99)']?.toFixed(2) || 0}ms

Error Rate: ${((errors?.values?.rate || 0) * 100).toFixed(2)}%

Thresholds:
  - p95 < 1000ms: ${(duration?.values['p(95)'] || 0) < 1000 ? '✓ PASS' : '✗ FAIL'}
  - p99 < 2000ms: ${(duration?.values['p(99)'] || 0) < 2000 ? '✓ PASS' : '✗ FAIL'}
  - Error rate < 5%: ${((errors?.values?.rate || 0) * 100) < 5 ? '✓ PASS' : '✗ FAIL'}
`;
}
