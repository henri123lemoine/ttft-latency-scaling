# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "scipy>=1.14"]
# ///
"""Floor fits for the second full Claude sessions in Epoch's exploratory archive.

The archive (upstream commit 29763e4) contains one more complete 8-length,
6-block session per Claude model collected with the same shared-prefix protocol
as the headline sessions, a day apart. This script fits the floor of each
session separately, then tests whether the two sessions share a curvature
(per-session intercept and slope, one quadratic term), and writes
outputs/floor/update.json for analysis/figures_floor_update.R. Minima are not
pooled across sessions: the sessions differ in level and slope, so the envelope
of the two is not any one serving curve.

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


def shared_curvature(head_rows: list[Observation], expl_rows: list[Observation]) -> dict:
    x_head, y_head = per_length_min(head_rows)
    x_expl, y_expl = per_length_min(expl_rows)
    x = np.concatenate([x_head, x_expl])
    y = np.concatenate([y_head, y_expl])
    s = np.concatenate([np.zeros_like(x_head), np.ones_like(x_expl)])

    def least_squares(design: np.ndarray) -> tuple[np.ndarray, float, int, np.ndarray]:
        beta, *_ = np.linalg.lstsq(design, y, rcond=None)
        residual = y - design @ beta
        df = len(y) - design.shape[1]
        covariance = (residual @ residual) / df * np.linalg.inv(design.T @ design)
        return beta, float(residual @ residual), df, covariance

    shared = np.column_stack([1 - s, s, (1 - s) * x, s * x, x**2])
    beta, rss, df, covariance = least_squares(shared)
    half_width = float(stats.t.ppf(0.975, df) * np.sqrt(covariance[4, 4]))
    _, rss_linear, _, _ = least_squares(np.column_stack([1 - s, s, (1 - s) * x, s * x]))
    f_zero = (rss_linear - rss) / (rss / df)
    _, rss_separate, df_separate, _ = least_squares(
        np.column_stack([1 - s, s, (1 - s) * x, s * x, (1 - s) * x**2, s * x**2])
    )
    f_differs = (rss - rss_separate) / (rss_separate / df_separate)
    f_joint = ((rss_linear - rss_separate) / 2) / (rss_separate / df_separate)
    return {
        "gamma": float(beta[4]),
        "gamma_ci95": [float(beta[4] - half_width), float(beta[4] + half_width)],
        "p_gamma_zero": float(stats.f.sf(f_zero, 1, df)),
        "p_gamma_differs_by_session": float(stats.f.sf(f_differs, 1, df_separate)),
        "p_no_curvature_in_either_session": float(stats.f.sf(f_joint, 2, df_separate)),
        "headline": {"alpha": float(beta[0]), "beta": float(beta[2])},
        "exploratory": {"alpha": float(beta[1]), "beta": float(beta[3])},
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
                "shared_curvature": shared_curvature(head_rows, expl_rows),
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
            for key in ["headline", "exploratory"]:
                s = m[key]
                fit = s["fit"]
                w.writerow(
                    [
                        m["model"], key, s["date"], s["blocks"], fit["alpha"], fit["beta"], fit["gamma"],
                        *fit["gamma_ci95"], fit["p_value"], s["extrapolation"][-1]["ttft_seconds"] / 60,
                    ]
                )
    for m in models:
        print(m["model"])
        for key in ["headline", "exploratory"]:
            s = m[key]
            fit = s["fit"]
            ci = fit["gamma_ci95"]
            print(
                f"  {key:12s} {s['date']:10s} γ={fit['gamma']:5.2f} [{ci[0]:5.2f}, {ci[1]:5.2f}]"
                f" p={fit['p_value']:.3f}  10M={s['extrapolation'][-1]['ttft_seconds'] / 60:5.1f} min"
                f"  floor@0.9M={s['floor'][-1]['ttft']:5.2f}s"
            )
        sc = m["shared_curvature"]
        print(
            f"  shared γ={sc['gamma']:5.2f} [{sc['gamma_ci95'][0]:5.2f}, {sc['gamma_ci95'][1]:5.2f}]"
            f" p(γ=0)={sc['p_gamma_zero']:.4f}  p(γ differs by session)={sc['p_gamma_differs_by_session']:.2f}"
            f"  joint p(no curvature in either session)={sc['p_no_curvature_in_either_session']:.5f}"
        )


if __name__ == "__main__":
    main()
