# Load Testing with k6

This directory contains load testing scripts using [k6](https://k6.io/).

## Table of Contents

- [Prerequisites](#prerequisites)
- [Running Tests](#running-tests)
- [Environment Variables](#environment-variables)
- [Test Scenarios](#test-scenarios)
- [Interpreting Results](#interpreting-results)
- [CI Integration](#ci-integration)

---

## Prerequisites

Install k6:

```bash
# macOS
brew install k6

# Linux (Debian/Ubuntu)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# Docker
docker pull grafana/k6
```

## Running Tests

### Smoke Test (Quick validation)

```bash
k6 run --env BASE_URL=http://localhost:4000 smoke.js
```

### Load Test (Normal load)

```bash
k6 run --env BASE_URL=http://localhost:4000 load.js
```

### Stress Test (Find breaking points)

```bash
k6 run --env BASE_URL=http://localhost:4000 stress.js
```

### Spike Test (Sudden traffic surge)

```bash
k6 run --env BASE_URL=http://localhost:4000 spike.js
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BASE_URL` | Target API URL | `http://localhost:4000` |
| `AUTH_TOKEN` | Bearer token for authenticated endpoints | - |
| `VUS` | Number of virtual users (override) | varies by test |
| `DURATION` | Test duration (override) | varies by test |

## Test Scenarios

### smoke.js
- **Purpose**: Verify system works under minimal load
- **VUs**: 1
- **Duration**: 1 minute
- **Threshold**: < 500ms p95 latency, < 1% error rate

### load.js
- **Purpose**: Normal expected load testing
- **VUs**: 50
- **Duration**: 5 minutes (with ramp-up/down)
- **Threshold**: < 1s p95 latency, < 5% error rate

### stress.js
- **Purpose**: Find system limits
- **VUs**: Up to 200
- **Duration**: 10 minutes (gradually increasing)
- **Threshold**: Monitor degradation

### benchmark.js
- **Purpose**: Scheduled container performance benchmark for trend tracking
- **Mode**: Constant arrival rate against lightweight container endpoints
- **Output**: k6 summary JSON transformed into publishable report + badge payload

### spike.js
- **Purpose**: Test sudden traffic spikes
- **VUs**: Spike to 100
- **Duration**: 3 minutes with sudden spike
- **Threshold**: System recovers after spike

## Interpreting Results

k6 outputs metrics including:

- **http_req_duration**: Response time
- **http_req_failed**: Error rate
- **http_reqs**: Request rate
- **vus**: Active virtual users

Focus on:
- **p95 latency**: 95th percentile response time
- **Error rate**: % of failed requests
- **Throughput**: Requests per second

## CI Integration

This repository includes two CI uses for load testing:

- **Load Tests CI** (`.github/workflows/loadtests-ci.yml`) runs a short k6 smoke
  test against a live Phoenix app for PR/push validation.
- **Container Benchmark** (`.github/workflows/container-benchmark.yml`) runs on
  a schedule and publishes benchmark reports to GitHub Pages.

Benchmark report links:

- Latest HTML report:
  `https://jmevorach.github.io/backend-api-starter-template/benchmarks/latest.html`
- Latest badge payload JSON:
  `https://jmevorach.github.io/backend-api-starter-template/benchmarks/latest-shields.json`

Example GitHub Actions k6 step:

```yaml
- name: Run Load Tests
  uses: grafana/k6-action@v0.3.1
  with:
    filename: loadtests/smoke.js
  env:
    BASE_URL: ${{ secrets.STAGING_URL }}
```
