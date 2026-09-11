# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "scipy>=1.14"]
# ///
"""Fit the released TTFT observations against the latency floor.

Provider-side queueing, routing, and cache placement add latency but never
remove it, so the fastest request at each context length is the closest
available view of the serving curve. This script fits a quadratic to those
per-length minima, reports curvature with jackknife and whole-block bootstrap
summaries, and compares extrapolations and marginal latency with the headline
Student-t fits. Figures are rendered by analysis/figures_floor.R.

Offline only. Run with `uv run analysis/floor.py`.
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
MARGINAL_TOKENS = [100_000, 272_000, 500_000, 900_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000]
BOOTSTRAP_REPLICATES = 5000
SEED = 20260910
MODEL_ORDER = ["GPT-5.6 Terra", "GPT-5.6 Sol", "Claude Sonnet 5", "Claude Opus 5", "GPT-6 Astra"]
EPOCH_PRIMARY_DEGREE = {
    "GPT-5.6 Terra": 2,
    "GPT-5.6 Sol": 2,
    "Claude Sonnet 5": 1,
    "Claude Opus 5": 1,
    "GPT-6 Astra": 2,
}
Observation = tuple[str, float, float]


def read_observations() -> dict[str, list[Observation]]:
    observations: dict[str, list[Observation]] = defaultdict(list)
    with open(ROOT / "outputs" / "tables" / "request_observations.csv") as f:
        for row in csv.DictReader(f):
            observations[row["model"]].append(
                (row["block"], float(row["total_input_tokens"]) / 1e6, float(row["ttft_seconds"]))
            )
    with open(ROOT / "outputs" / "astra-api" / "request_observations.csv") as f:
        for row in csv.DictReader(f):
            observations[row["model"]].append((row["block"], float(row["x"]), float(row["y"])))
    return observations


def read_epoch_fits() -> dict[str, dict[int, dict[str, float]]]:
    fits: dict[str, dict[int, dict[str, float]]] = defaultdict(dict)
    for path in [
        ROOT / "outputs" / "tables" / "fit_coefficients.csv",
        ROOT / "outputs" / "astra-api" / "fit_coefficients.csv",
    ]:
        with open(path) as f:
            for row in csv.DictReader(f):
                if row["estimator"] != "Student-t":
                    continue
                fits[row["model"]][int(row["degree"])] = {
                    "alpha": float(row["alpha"]),
                    "beta": float(row["beta"]),
                    "gamma": float(row["gamma"]),
                }
    return fits


def polynomial(c: dict[str, float]) -> np.ndarray:
    return np.array([c["gamma"], c["beta"], c["alpha"]])


def coefficients(poly: np.ndarray) -> dict[str, float]:
    gamma, beta, alpha = ([0.0] * (3 - len(poly))) + list(poly)
    return {"alpha": float(alpha), "beta": float(beta), "gamma": float(gamma)}


def per_length_min(rows: list[Observation]) -> tuple[np.ndarray, np.ndarray]:
    floor: dict[float, float] = {}
    for _, x, y in rows:
        floor[x] = min(y, floor.get(x, np.inf))
    xs = np.array(sorted(floor))
    return xs, np.array([floor[x] for x in xs])


def floor_gamma(rows: list[Observation]) -> float:
    return float(np.polyfit(*per_length_min(rows), 2)[0])


def curvature_test(xs: np.ndarray, ys: np.ndarray) -> dict:
    linear = np.polyfit(xs, ys, 1)
    quadratic = np.polyfit(xs, ys, 2)
    rss_linear = float(np.sum((ys - np.polyval(linear, xs)) ** 2))
    rss_quadratic = float(np.sum((ys - np.polyval(quadratic, xs)) ** 2))
    df_residual = len(xs) - 3
    f_statistic = (rss_linear - rss_quadratic) / (rss_quadratic / df_residual)
    return {
        "linear": coefficients(linear),
        "quadratic": coefficients(quadratic),
        "rss_linear": rss_linear,
        "rss_quadratic": rss_quadratic,
        "f_statistic": float(f_statistic),
        "p_value": float(stats.f.sf(f_statistic, 1, df_residual)),
        "n_lengths": int(len(xs)),
    }


def block_bootstrap(rows: list[Observation], rng: np.random.Generator) -> dict:
    blocks = sorted({r[0] for r in rows})
    by_block = {b: [r for r in rows if r[0] == b] for b in blocks}
    gammas = np.array(
        [
            floor_gamma([row for b in rng.choice(blocks, size=len(blocks), replace=True) for row in by_block[b]])
            for _ in range(BOOTSTRAP_REPLICATES)
        ]
    )
    return {
        "replicates": BOOTSTRAP_REPLICATES,
        "q025": float(np.quantile(gammas, 0.025)),
        "median": float(np.median(gammas)),
        "q975": float(np.quantile(gammas, 0.975)),
        "fraction_positive": float(np.mean(gammas > 0)),
    }


def leave_one_out(rows: list[Observation]) -> dict:
    blocks = sorted({r[0] for r in rows})
    lengths = sorted({r[1] for r in rows})
    return {
        "drop_one_block_gamma": [floor_gamma([r for r in rows if r[0] != b]) for b in blocks],
        "drop_one_length_gamma": [floor_gamma([r for r in rows if r[1] != x]) for x in lengths],
    }


def extrapolate(poly: np.ndarray) -> list[dict]:
    return [{"input_tokens": n, "ttft_seconds": float(np.polyval(poly, n / 1e6))} for n in EXTRAPOLATION_TOKENS]


def marginal_seconds_per_10k(c: dict[str, float], tokens: int) -> float:
    return (c["beta"] + 2 * c["gamma"] * tokens / 1e6) / 100


def per_block_curvature(rows: list[Observation]) -> dict:
    gammas = []
    for block in sorted({r[0] for r in rows}):
        block_rows = [r for r in rows if r[0] == block]
        x = np.array([r[1] for r in block_rows])
        y = np.array([r[2] for r in block_rows])
        gammas.append(float(np.polyfit(x, y, 2)[0]))
    gammas = np.array(gammas)
    se = float(gammas.std(ddof=1) / np.sqrt(len(gammas)))
    t = float(gammas.mean() / se)
    return {
        "gammas": [float(g) for g in gammas],
        "mean": float(gammas.mean()),
        "se": se,
        "p_zero": float(2 * stats.t.sf(abs(t), len(gammas) - 1)),
    }


def floor_gamma_interval(xs: np.ndarray, ys: np.ndarray) -> dict:
    design = np.column_stack([np.ones_like(xs), xs, xs**2])
    beta, *_ = np.linalg.lstsq(design, ys, rcond=None)
    residual = ys - design @ beta
    df = len(xs) - 3
    covariance = (residual @ residual) / df * np.linalg.inv(design.T @ design)
    se = float(np.sqrt(covariance[2, 2]))
    half_width = float(stats.t.ppf(0.975, df) * se)
    return {"se": se, "ci95": [float(beta[2] - half_width), float(beta[2] + half_width)]}


def analyse() -> list[dict]:
    observations = read_observations()
    epoch = read_epoch_fits()
    rng = np.random.default_rng(SEED)
    models = []
    for model in MODEL_ORDER:
        rows = observations[model]
        xs, floor = per_length_min(rows)
        fit = curvature_test(xs, floor)
        epoch_primary = epoch[model][EPOCH_PRIMARY_DEGREE[model]]
        models.append(
            {
                "model": model,
                "blocks": len({r[0] for r in rows}),
                "floor": [{"x": float(x), "ttft": float(y)} for x, y in zip(xs, floor)],
                "floor_fit": fit,
                "floor_gamma_interval": floor_gamma_interval(xs, floor),
                "per_block_curvature": per_block_curvature(rows),
                "floor_bootstrap": block_bootstrap(rows, rng),
                "floor_sensitivity": leave_one_out(rows),
                "epoch_student_t": {str(d): c for d, c in epoch[model].items()},
                "epoch_primary_degree": EPOCH_PRIMARY_DEGREE[model],
                "extrapolation": {
                    "floor_quadratic": extrapolate(polynomial(fit["quadratic"])),
                    "epoch_primary": extrapolate(polynomial(epoch_primary)),
                },
                "marginal_seconds_per_10k_tokens": [
                    {
                        "input_tokens": n,
                        "epoch_primary": marginal_seconds_per_10k(epoch_primary, n),
                        "floor_quadratic": marginal_seconds_per_10k(fit["quadratic"], n),
                    }
                    for n in MARGINAL_TOKENS
                ],
            }
        )
    return models


def write_tables(models: list[dict]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "fits.json").write_text(
        json.dumps({"generated_by": "analysis/floor.py", "seed": SEED, "models": models}, indent=1) + "\n"
    )
    with open(OUT / "floor_curvature.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "model", "blocks", "floor_alpha", "floor_beta", "floor_gamma", "f_statistic", "p_value",
                "epoch_student_t_gamma", "bootstrap_q025", "bootstrap_q975", "bootstrap_fraction_positive",
                "drop_one_block_min", "drop_one_block_max", "drop_one_length_min", "drop_one_length_max",
            ]
        )
        for m in models:
            q = m["floor_fit"]["quadratic"]
            s = m["floor_sensitivity"]
            b = m["floor_bootstrap"]
            w.writerow(
                [
                    m["model"], m["blocks"], q["alpha"], q["beta"], q["gamma"],
                    m["floor_fit"]["f_statistic"], m["floor_fit"]["p_value"], m["epoch_student_t"]["2"]["gamma"],
                    b["q025"], b["q975"], b["fraction_positive"],
                    min(s["drop_one_block_gamma"]), max(s["drop_one_block_gamma"]),
                    min(s["drop_one_length_gamma"]), max(s["drop_one_length_gamma"]),
                ]
            )
    with open(OUT / "extrapolated_ttft.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["model", "input_tokens", "epoch_primary_ttft_seconds", "floor_quadratic_ttft_seconds"])
        for m in models:
            for e, fl in zip(m["extrapolation"]["epoch_primary"], m["extrapolation"]["floor_quadratic"]):
                w.writerow([m["model"], e["input_tokens"], e["ttft_seconds"], fl["ttft_seconds"]])
    with open(OUT / "marginal_latency.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["model", "input_tokens", "epoch_primary_seconds_per_10k_tokens", "floor_quadratic_seconds_per_10k_tokens"])
        for m in models:
            for row in m["marginal_seconds_per_10k_tokens"]:
                w.writerow([m["model"], row["input_tokens"], row["epoch_primary"], row["floor_quadratic"]])


def main() -> None:
    models = analyse()
    write_tables(models)
    blocks = {m["model"]: m["per_block_curvature"]["gammas"] for m in models}
    for a, b in [("Claude Sonnet 5", "GPT-5.6 Sol"), ("Claude Sonnet 5", "GPT-5.6 Terra"), ("Claude Sonnet 5", "Claude Opus 5")]:
        t, p = stats.ttest_ind(blocks[a], blocks[b], equal_var=False)
        print(f"per-block γ, {a} vs {b}: Welch t={t:.2f} p={p:.1e}")
    for m in models:
        f = m["floor_fit"]
        s = m["floor_sensitivity"]
        marginal = {row["input_tokens"]: row for row in m["marginal_seconds_per_10k_tokens"]}
        ci = m["floor_gamma_interval"]["ci95"]
        pb = m["per_block_curvature"]
        print(
            f"{m['model']:16s} floor γ={f['quadratic']['gamma']:5.1f} 95% CI [{ci[0]:.1f}, {ci[1]:.1f}]"
            f"  per-block γ mean={pb['mean']:5.1f} se={pb['se']:.1f} p(γ=0)={pb['p_zero']:.2f}"
            f"  Epoch Student-t γ={m['epoch_student_t']['2']['gamma']:5.1f}"
            f"  drop-block [{min(s['drop_one_block_gamma']):.1f}, {max(s['drop_one_block_gamma']):.1f}]"
            f"  marginal 10M/1M: Epoch {marginal[10_000_000]['epoch_primary'] / marginal[1_000_000]['epoch_primary']:.1f}x,"
            f" floor {marginal[10_000_000]['floor_quadratic'] / marginal[1_000_000]['floor_quadratic']:.1f}x"
        )


if __name__ == "__main__":
    main()
