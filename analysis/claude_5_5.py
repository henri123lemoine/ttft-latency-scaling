# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "scipy>=1.14"]
# ///
"""Floor fits for the Claude 5.5 shared-prefix sessions in data/raw/claude-5.5.

Same floor method as analysis/floor.py, applied per session: a quadratic through
the per-length minimum TTFT, the curvature F-test, a 95% interval on gamma, a
whole-block bootstrap, and marginal latency. Opus 5.5 cannot disable thinking, so
it is also fit on the time to the first content block of any kind.

A few long requests returned in well under half the typical time for their length
(same reported cache read as the rest). The floor passes through them by
construction, so each session is also fit with those requests set aside
(`ttft_excluding_fast`, a post-hoc sensitivity check) and through per-length medians.

Offline only. Run with `uv run analysis/claude_5_5.py`.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np

from floor import (
    block_bootstrap,
    curvature_test,
    floor_gamma_interval,
    leave_one_out,
    marginal_seconds_per_10k,
    per_block_curvature,
    per_length_min,
)

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "claude-5.5"
OUT = ROOT / "outputs" / "claude-5.5"
SEED = 20261007
MARGINAL_TOKENS = [50_000, 1_000_000]
MODEL_NAMES = {
    "claude-haiku-5-5": "Claude Haiku 5.5",
    "claude-sonnet-5-5": "Claude Sonnet 5.5",
    "claude-opus-5-5": "Claude Opus 5.5",
}
FAST_FRACTION_OF_MEDIAN = 0.6


def read_session(path: Path) -> dict | None:
    records = [json.loads(line) for line in path.open()]
    session = records[0]
    if not session["label"].endswith("shared-prefix"):
        return None
    samples = [r for r in records if r["type"] == "sample"]
    measured = [r for r in samples if r.get("kind") == "measured"]
    valid = [r for r in measured if r.get("valid", True)]
    tokens_by_target: dict[int, list[int]] = {}
    for r in valid:
        tokens_by_target.setdefault(r["target_tokens"], []).append(r["total_input_tokens"])
    x_by_target = {t: float(np.median(v)) / 1e6 for t, v in tokens_by_target.items()}
    return {
        "session_id": session["session"],
        "label": session["label"],
        "model": MODEL_NAMES[samples[0]["model"]],
        "started": session["timestamp"],
        "requests": len(samples),
        "measured": len(measured),
        "valid": len(valid),
        "noncompliant_output": sum(1 for r in valid if r.get("output_compliant") is False),
        "with_thinking_blocks": sum(1 for r in valid if r.get("thinking_blocks", 0) > 0),
        "stop_reasons": sorted({str(r.get("stop_reason")) for r in valid}),
        "estimated_cost_usd": sum(r.get("estimated_cost_usd") or 0.0 for r in samples),
        "rows": [
            {
                "block": r["repetition"] + 1,
                "target_tokens": r["target_tokens"],
                "total_input_tokens": r["total_input_tokens"],
                "x": x_by_target[r["target_tokens"]],
                "ttft_seconds": r["ttft_ns"] / 1e9,
                "first_content_seconds": r["first_content_ns"] / 1e9,
                "thinking_blocks": r.get("thinking_blocks", 0),
            }
            for r in valid
        ],
    }


def fast_requests(session: dict, column: str) -> list[dict]:
    medians = {
        x: float(np.median([r[column] for r in session["rows"] if r["x"] == x]))
        for x in {r["x"] for r in session["rows"]}
    }
    return [r for r in session["rows"] if r[column] < FAST_FRACTION_OF_MEDIAN * medians[r["x"]]]


def fit_timer(session: dict, column: str, rng: np.random.Generator, exclude_fast: bool = False) -> dict:
    fast = fast_requests(session, column)
    kept = [r for r in session["rows"] if not (exclude_fast and r in fast)]
    rows = [(str(r["block"]), r["x"], r[column]) for r in kept]
    xs, floor = per_length_min(rows)
    fit = curvature_test(xs, floor)
    medians = np.array([np.median([r[2] for r in rows if r[1] == x]) for x in xs])
    return {
        "fast_requests": [
            {"block": r["block"], "target_tokens": r["target_tokens"], "seconds": r[column]} for r in fast
        ],
        "median_fit": {**curvature_test(xs, medians), "gamma_interval": floor_gamma_interval(xs, medians)},
        "floor": [{"x": float(x), "seconds": float(y)} for x, y in zip(xs, floor)],
        "median": [
            {"x": float(x), "seconds": float(np.median([r[2] for r in rows if r[1] == x]))} for x in xs
        ],
        "floor_fit": fit,
        "floor_gamma_interval": floor_gamma_interval(xs, floor),
        "floor_bootstrap": block_bootstrap(rows, rng),
        "floor_sensitivity": leave_one_out(rows),
        "per_block_curvature": per_block_curvature(rows),
        "marginal_seconds_per_10k_tokens": {
            str(n): marginal_seconds_per_10k(fit["quadratic"], n) for n in MARGINAL_TOKENS
        },
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    sessions = [s for s in (read_session(p) for p in sorted(RAW.glob("*.jsonl"))) if s]
    sessions.sort(key=lambda s: list(MODEL_NAMES.values()).index(s["model"]))
    with open(OUT / "request_observations.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            ["model", "session_id", "block", "target_tokens", "total_input_tokens",
             "ttft_seconds", "first_content_seconds", "thinking_blocks"]
        )
        for s in sessions:
            for r in s["rows"]:
                w.writerow(
                    [s["model"], s["session_id"], r["block"], r["target_tokens"], r["total_input_tokens"],
                     r["ttft_seconds"], r["first_content_seconds"], r["thinking_blocks"]]
                )
    results = []
    for s in sessions:
        fits = {
            "ttft": fit_timer(s, "ttft_seconds", rng),
            "first_content": fit_timer(s, "first_content_seconds", rng),
            "ttft_excluding_fast": fit_timer(s, "ttft_seconds", rng, exclude_fast=True),
        }
        results.append({**{k: v for k, v in s.items() if k != "rows"}, "blocks": len({r["block"] for r in s["rows"]}), "fits": fits})
    (OUT / "fits.json").write_text(
        json.dumps({"generated_by": "analysis/claude_5_5.py", "seed": SEED, "sessions": results}, indent=1) + "\n"
    )
    with open(OUT / "floor_curvature.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            ["model", "timer", "blocks", "floor_alpha", "floor_beta", "floor_gamma", "gamma_ci95_low",
             "gamma_ci95_high", "f_statistic", "p_value", "bootstrap_q025", "bootstrap_q975",
             "per_block_gamma_mean", "per_block_gamma_se", "marginal_s_per_10k_at_50k", "marginal_s_per_10k_at_1m",
             "median_gamma", "median_gamma_ci95_low", "median_gamma_ci95_high", "median_p_value", "fast_requests"]
        )
        for s in results:
            for name, fit in s["fits"].items():
                q = fit["floor_fit"]["quadratic"]
                ci = fit["floor_gamma_interval"]["ci95"]
                m = fit["marginal_seconds_per_10k_tokens"]
                mf = fit["median_fit"]
                w.writerow(
                    [s["model"], name, s["blocks"], q["alpha"], q["beta"], q["gamma"], ci[0], ci[1],
                     fit["floor_fit"]["f_statistic"], fit["floor_fit"]["p_value"],
                     fit["floor_bootstrap"]["q025"], fit["floor_bootstrap"]["q975"],
                     fit["per_block_curvature"]["mean"], fit["per_block_curvature"]["se"],
                     m["50000"], m["1000000"], mf["quadratic"]["gamma"], mf["gamma_interval"]["ci95"][0],
                     mf["gamma_interval"]["ci95"][1], mf["p_value"], len(fit["fast_requests"])]
                )
                print(
                    f"{s['model']:18s} {name:20s} blocks={s['blocks']} floor γ={q['gamma']:6.2f}"
                    f" 95% CI [{ci[0]:.2f}, {ci[1]:.2f}] p={fit['floor_fit']['p_value']:.3g}"
                    f"  β={q['beta']:.2f} α={q['alpha']:.2f}"
                    f"  bootstrap [{fit['floor_bootstrap']['q025']:.2f}, {fit['floor_bootstrap']['q975']:.2f}]"
                    f"  per-block γ={fit['per_block_curvature']['mean']:.2f}±{fit['per_block_curvature']['se']:.2f}"
                    f"  s/10k @50k={m['50000']:.3f} @1M={m['1000000']:.3f}"
                    f"  median γ={mf['quadratic']['gamma']:.2f} [{mf['gamma_interval']['ci95'][0]:.2f},"
                    f" {mf['gamma_interval']['ci95'][1]:.2f}] p={mf['p_value']:.3g}  fast={len(fit['fast_requests'])}"
                )
        for s in results:
            print(
                f"{s['model']:18s} valid={s['valid']}/{s['measured']} thinking={s['with_thinking_blocks']}"
                f" noncompliant={s['noncompliant_output']} stop={s['stop_reasons']} cost=${s['estimated_cost_usd']:.2f}"
            )


if __name__ == "__main__":
    main()
