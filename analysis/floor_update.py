# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "scipy>=1.14"]
# ///
"""Floor fits for the second full Claude sessions in Epoch's exploratory archive.

The archive (upstream commit 29763e4) contains one more complete 8-length,
6-block session per Claude model collected with the same shared-prefix protocol
as the headline sessions, a day apart. This script fits the floor of each
session separately and of both sessions pooled, and writes
outputs/floor/update.json for analysis/figures_floor_update.R.

Offline only. Run with `uv run analysis/floor_update.py`.
"""

from __future__ import annotations

import csv
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy import stats

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "outputs" / "floor"
EXTRAPOLATION_TOKENS = [1_000_000, 2_000_000, 5_000_000, 10_000_000]
MARGINAL_TOKENS = [50_000, 1_000_000, 10_000_000]

HEADLINE_SESSIONS = {
    "Claude Sonnet 5": {"session_id": "20260814T154718Z-5dc271b9", "date": "2026-08-14", "start_edt": "11:48"},
    "Claude Opus 5": {"session_id": "20260813T163222Z-b3406d60", "date": "2026-08-13", "start_edt": "12:33"},
}
EXPLORATORY_SESSIONS = {
    "Claude Sonnet 5": {"session_id": "20260813T165440Z-0e5adc75", "date": "2026-08-13", "start_edt": "12:54"},
    "Claude Opus 5": {"session_id": "20260814T134405Z-c4566a73", "date": "2026-08-14", "start_edt": "09:44"},
}
Observation = tuple[int, float, float]


def read_headline() -> dict[str, list[Observation]]:
    rows: dict[str, list[Observation]] = defaultdict(list)
    with open(ROOT / "outputs" / "tables" / "request_observations.csv") as f:
        for r in csv.DictReader(f):
            rows[r["model"]].append((int(r["block"]), float(r["total_input_tokens"]) / 1e6, float(r["ttft_seconds"])))
    return rows


def read_exploratory() -> dict[str, list[Observation]]:
    rows: dict[str, list[Observation]] = defaultdict(list)
    with open(ROOT / "outputs" / "exploratory" / "request_observations.csv") as f:
        for r in csv.DictReader(f):
            rows[r["session_id"]].append((int(r["block"]), float(r["total_input_tokens"]) / 1e6, float(r["ttft_seconds"])))
    return rows


def per_length_min(rows: list[Observation]) -> tuple[np.ndarray, np.ndarray]:
    floor: dict[float, float] = {}
    for _, x, y in rows:
        floor[x] = min(y, floor.get(x, np.inf))
    xs = np.array(sorted(floor))
    return xs, np.array([floor[x] for x in xs])


def quadratic_fit(xs: np.ndarray, ys: np.ndarray) -> dict:
    design = np.column_stack([np.ones_like(xs), xs, xs**2])
    beta, *_ = np.linalg.lstsq(design, ys, rcond=None)
    residual = ys - design @ beta
    df = len(xs) - 3
    covariance = (residual @ residual) / df * np.linalg.inv(design.T @ design)
    se = float(np.sqrt(covariance[2, 2]))
    half_width = float(stats.t.ppf(0.975, df) * se)
    linear = np.polyfit(xs, ys, 1)
    rss_linear = float(np.sum((ys - np.polyval(linear, xs)) ** 2))
    rss_quadratic = float(residual @ residual)
    f_statistic = (rss_linear - rss_quadratic) / (rss_quadratic / df)
    return {
        "alpha": float(beta[0]),
        "beta": float(beta[1]),
        "gamma": float(beta[2]),
        "gamma_ci95": [float(beta[2] - half_width), float(beta[2] + half_width)],
        "p_value": float(stats.f.sf(f_statistic, 1, df)),
        "n_lengths": int(len(xs)),
    }


def describe(rows: list[Observation]) -> dict:
    xs, floor = per_length_min(rows)
    fit = quadratic_fit(xs, floor)
    poly = np.array([fit["gamma"], fit["beta"], fit["alpha"]])
    return {
        "blocks": len({r[0] for r in rows}),
        "requests": len(rows),
        "points": [{"block": b, "x": x, "ttft": y} for b, x, y in rows],
        "floor": [{"x": float(x), "ttft": float(y)} for x, y in zip(xs, floor)],
        "fit": fit,
        "extrapolation": [{"input_tokens": n, "ttft_seconds": float(np.polyval(poly, n / 1e6))} for n in EXTRAPOLATION_TOKENS],
        "marginal_seconds_per_10k_tokens": [
            {"input_tokens": n, "seconds": (fit["beta"] + 2 * fit["gamma"] * n / 1e6) / 100} for n in MARGINAL_TOKENS
        ],
    }


def main() -> None:
    headline = read_headline()
    exploratory = read_exploratory()
    reference = {
        m["model"]: {"gamma": m["floor_fit"]["quadratic"]["gamma"], "gamma_ci95": m["floor_gamma_interval"]["ci95"], "blocks": m["blocks"]}
        for m in json.loads((OUT / "fits.json").read_text())["models"]
        if m["model"].startswith("GPT")
    }
    models = []
    for model in ["Claude Sonnet 5", "Claude Opus 5"]:
        head_rows = headline[model]
        expl_rows = exploratory[EXPLORATORY_SESSIONS[model]["session_id"]]
        models.append(
            {
                "model": model,
                "headline": {**HEADLINE_SESSIONS[model], **describe(head_rows)},
                "exploratory": {**EXPLORATORY_SESSIONS[model], **describe(expl_rows)},
                "pooled": describe(head_rows + expl_rows),
            }
        )
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "update.json").write_text(
        json.dumps({"generated_by": "analysis/floor_update.py", "models": models, "reference": reference}, indent=1) + "\n"
    )
    with open(OUT / "update_floor_curvature.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["model", "session", "date", "blocks", "floor_alpha", "floor_beta", "floor_gamma", "gamma_ci_low", "gamma_ci_high", "p_value", "ttft_10m_minutes"])
        for m in models:
            for key in ["headline", "exploratory", "pooled"]:
                s = m[key]
                fit = s["fit"]
                w.writerow(
                    [
                        m["model"], key, s.get("date", "both"), s["blocks"], fit["alpha"], fit["beta"], fit["gamma"],
                        *fit["gamma_ci95"], fit["p_value"], s["extrapolation"][-1]["ttft_seconds"] / 60,
                    ]
                )
    for m in models:
        print(m["model"])
        for key in ["headline", "exploratory", "pooled"]:
            s = m[key]
            fit = s["fit"]
            ci = fit["gamma_ci95"]
            print(
                f"  {key:12s} {s.get('date', 'both'):10s} γ={fit['gamma']:5.2f} [{ci[0]:5.2f}, {ci[1]:5.2f}]"
                f" p={fit['p_value']:.3f}  10M={s['extrapolation'][-1]['ttft_seconds'] / 60:5.1f} min"
                f"  floor@0.9M={s['floor'][-1]['ttft']:5.2f}s"
            )


if __name__ == "__main__":
    main()
