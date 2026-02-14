#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import pathlib


def load_summary(path: pathlib.Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def num(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return float(default)


def color_for_p95(p95_ms: float) -> str:
    if p95_ms <= 300:
        return "brightgreen"
    if p95_ms <= 600:
        return "green"
    if p95_ms <= 900:
        return "yellowgreen"
    if p95_ms <= 1200:
        return "yellow"
    if p95_ms <= 1800:
        return "orange"
    return "red"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate benchmark reports and badge payload.")
    parser.add_argument("--input", required=True, help="k6 summary export JSON path")
    parser.add_argument("--output-dir", required=True, help="Directory to write report files")
    args = parser.parse_args()

    summary = load_summary(pathlib.Path(args.input))
    metrics = summary.get("metrics", {})

    req_duration = metrics.get("http_req_duration", {}).get("values", {})
    req_failed = metrics.get("http_req_failed", {}).get("values", {})
    req_total = metrics.get("http_reqs", {}).get("values", {})

    p50 = num(req_duration.get("med"))
    p95 = num(req_duration.get("p(95)"))
    p99 = num(req_duration.get("p(99)"))
    error_rate = num(req_failed.get("rate")) * 100.0
    rps = num(req_total.get("rate"))
    total_requests = int(num(req_total.get("count")))
    generated_at = dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

    out_dir = pathlib.Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    history_dir = out_dir / "history"
    history_dir.mkdir(parents=True, exist_ok=True)

    report_payload = {
        "generated_at": generated_at,
        "metrics": {
            "requests_total": total_requests,
            "rps": round(rps, 2),
            "latency_ms": {"p50": round(p50, 2), "p95": round(p95, 2), "p99": round(p99, 2)},
            "http_error_rate_pct": round(error_rate, 3),
        },
    }

    (out_dir / "latest.json").write_text(json.dumps(report_payload, indent=2) + "\n", encoding="utf-8")

    timestamp = dt.datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    (history_dir / f"{timestamp}.json").write_text(
        json.dumps(report_payload, indent=2) + "\n", encoding="utf-8"
    )

    badge_payload = {
        "schemaVersion": 1,
        "label": "container p95",
        "message": f"{round(p95)}ms",
        "color": color_for_p95(p95),
    }
    (out_dir / "latest-shields.json").write_text(
        json.dumps(badge_payload, indent=2) + "\n", encoding="utf-8"
    )

    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Container Benchmark Report</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 860px; margin: 32px auto; padding: 0 16px; color: #111; }}
    h1 {{ margin-bottom: 8px; }}
    .muted {{ color: #666; }}
    table {{ border-collapse: collapse; width: 100%; margin-top: 20px; }}
    th, td {{ border: 1px solid #ddd; padding: 10px; text-align: left; }}
    th {{ background: #f5f5f5; }}
    code {{ background: #f5f5f5; padding: 2px 4px; border-radius: 4px; }}
  </style>
</head>
<body>
  <h1>Container Benchmark Report</h1>
  <p class="muted">Generated at {generated_at}</p>
  <table>
    <tr><th>Metric</th><th>Value</th></tr>
    <tr><td>Total Requests</td><td>{total_requests}</td></tr>
    <tr><td>Throughput</td><td>{rps:.2f} req/s</td></tr>
    <tr><td>Latency p50</td><td>{p50:.2f} ms</td></tr>
    <tr><td>Latency p95</td><td>{p95:.2f} ms</td></tr>
    <tr><td>Latency p99</td><td>{p99:.2f} ms</td></tr>
    <tr><td>HTTP Error Rate</td><td>{error_rate:.3f}%</td></tr>
  </table>
  <p>Raw JSON: <a href="./latest.json"><code>latest.json</code></a></p>
</body>
</html>
"""
    (out_dir / "latest.html").write_text(html, encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
