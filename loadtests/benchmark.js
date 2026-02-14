/**
 * Container Benchmark Test
 *
 * Purpose:
 * - Benchmark shipped container performance on core unauthenticated endpoints
 * - Produce stable metrics suitable for trend tracking in CI
 *
 * Usage:
 *   k6 run --env BASE_URL=https://localhost:8443 benchmark.js
 */

import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "https://localhost:8443";

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    benchmark: {
      executor: "constant-arrival-rate",
      rate: Number(__ENV.RATE || 25),
      timeUnit: "1s",
      duration: __ENV.DURATION || "2m",
      preAllocatedVUs: Number(__ENV.PRE_ALLOCATED_VUS || 20),
      maxVUs: Number(__ENV.MAX_VUS || 100),
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<1200", "p(99)<2500"],
    checks: ["rate>0.99"],
  },
};

export default function () {
  const rootRes = http.get(`${BASE_URL}/`);
  check(rootRes, {
    "root: status 200": (r) => r.status === 200,
  });

  const openapiRes = http.get(`${BASE_URL}/api/v1/openapi`);
  check(openapiRes, {
    "openapi: status 200": (r) => r.status === 200,
  });

  const healthRes = http.get(`${BASE_URL}/healthz`);
  check(healthRes, {
    "healthz: status 200 or 503": (r) => r.status === 200 || r.status === 503,
  });

  sleep(0.2);
}
