# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Turning a run's raw timings into the few numbers worth reading.

Percentiles rather than a mean, because the mean of a fan-out is dominated by
whichever subscribers were cheap to reach and says nothing about the person
waiting longest. The tail is the whole question.

Server-side counters are reported as a delta across the run rather than as
the absolute since-process-start values the endpoint returns, so a run
against a server that has been up for a while still reads as what this run
did.
"""
import json
import statistics


def percentile(values, fraction):
    """The value at `fraction` through a sorted copy of `values`.

    Nearest-rank rather than interpolated: at the sample sizes a load run
    produces, an interpolated p99 invents a number no request actually saw.
    """
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))
    return ordered[index]


def summarise(values, unit="ms"):
    """The five-number view of one timing series."""
    if not values:
        return {"count": 0, "unit": unit}
    return {
        "count": len(values),
        "unit": unit,
        "min": round(min(values), 2),
        "p50": round(percentile(values, 0.50), 2),
        "p95": round(percentile(values, 0.95), 2),
        "p99": round(percentile(values, 0.99), 2),
        "max": round(max(values), 2),
        "mean": round(statistics.fmean(values), 2),
    }


def parse_prometheus(text):
    """The metric values out of prometheus text exposition, as a flat dict.

    Keeps the label set in the key verbatim, so a caller comparing two
    scrapes does not have to model labels: `slimm_requests_total{class="write"}`
    is simply a different key from the read one.
    """
    out = {}
    for line in (text or "").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, _, value = line.rpartition(" ")
        if not name:
            continue
        try:
            out[name.strip()] = float(value)
        except ValueError:
            continue
    return out


def counter_delta(first, last):
    """What changed between two scrapes, dropping anything that did not."""
    delta = {}
    for key, end in (last or {}).items():
        start = (first or {}).get(key, 0.0)
        if end != start:
            delta[key] = round(end - start, 3)
    return delta


def build(scenario, config, timings, delivery, fanout, server, failures):
    """Assembles the whole run into one JSON-serialisable record."""
    return {
        "scenario": scenario,
        "config": config,
        "send_latency": summarise(timings),
        "delivery_latency": summarise(delivery),
        "fanout": fanout,
        "server": server,
        "failures": failures,
    }


def write(report, path):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")


def render(report):
    """A short plain-text summary, for the terminal the run was started from."""
    lines = []
    config = report["config"]
    lines.append(f"scenario: {report['scenario']}")
    lines.append(f"  users={config['users']} senders={config['senders']} "
                 f"messages={config['messages']} channel={config['channel']}")
    for label, key in (("send latency (REST)", "send_latency"),
                       ("delivery latency (WS)", "delivery_latency")):
        stat = report[key]
        if not stat.get("count"):
            lines.append(f"  {label}: no samples")
            continue
        lines.append(
            f"  {label}: n={stat['count']} p50={stat['p50']}ms "
            f"p95={stat['p95']}ms p99={stat['p99']}ms max={stat['max']}ms")
    fan = report["fanout"]
    lines.append(f"  fan-out: expected={fan['expected_per_message']} "
                 f"delivered_min={fan['delivered_min']} "
                 f"delivered_max={fan['delivered_max']} "
                 f"complete={fan['complete_messages']}/{fan['messages']}")
    failures = report["failures"]
    if failures:
        lines.append(f"  failures: {len(failures)}")
        for note in failures[:5]:
            lines.append(f"    {note}")
    server = report.get("server") or {}
    for key in sorted(server.get("delta", {})):
        lines.append(f"  server {key}: +{server['delta'][key]}")
    for key in ("rss_start_bytes", "rss_end_bytes", "ws_connections_peak"):
        if server.get(key) is not None:
            lines.append(f"  server {key}: {server[key]}")
    return "\n".join(lines)
