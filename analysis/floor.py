# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "scipy>=1.14", "statsmodels>=0.14", "matplotlib>=3.9"]
# ///
"""Refit the released TTFT observations against the latency floor.

The headline analysis fits the centre of each model's request distribution
(Student-t, frontier, spike models). Provider-side queueing, routing, and cache
placement can only add latency, so the fastest request at each context length
is the cleanest view of the serving curve. This script fits that floor, plus
low quantiles for a continuous view, and compares curvature across estimators.

Offline only. Reads the committed observation and fit tables and writes
outputs/floor/ and figures/floor/. Run with `uv run analysis/floor.py`.
"""

from __future__ import annotations

import csv
import json
import warnings
from collections import defaultdict
from pathlib import Path

import matplotlib
import numpy as np
import statsmodels.api as sm
from scipy import stats

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "outputs" / "floor"
FIGURES = ROOT / "figures" / "floor"

EXTRAPOLATION_TOKENS = [1_000_000, 2_000_000, 5_000_000, 10_000_000]
TABLE_QUANTILES = [0.1, 0.25, 0.5]
SWEEP_QUANTILES = [round(q, 2) for q in np.arange(0.05, 0.96, 0.05)]
BOOTSTRAP_REPLICATES = 5000
SEED = 20260910
MODEL_ORDER = [
    "GPT-5.6 Terra",
    "GPT-5.6 Sol",
    "GPT-6 Astra",
    "Claude Sonnet 5",
    "Claude Opus 5",
]
EPOCH_PRIMARY_DEGREE = {
    "GPT-5.6 Terra": 2,
    "GPT-5.6 Sol": 2,
    "GPT-6 Astra": 2,
    "Claude Sonnet 5": 1,
    "Claude Opus 5": 1,
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


def read_epoch_spike_half_sigma() -> dict[str, dict[str, float]]:
    out: dict[str, dict[str, float]] = {}
    with open(ROOT / "outputs" / "tables" / "asymmetric_sigma_sensitivity.csv") as f:
        for row in csv.DictReader(f):
            if row["estimator"] == "Spike + contention" and row["sigma_multiplier"] == "0.5":
                out[row["model"]] = {k: float(row[k]) for k in ("alpha", "beta", "gamma")}
    return out


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


def ols_curvature_test(xs: np.ndarray, ys: np.ndarray) -> dict:
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


def quantile_fit(rows: list[Observation], tau: float) -> dict:
    x = np.array([r[1] for r in rows])
    y = np.array([r[2] for r in rows])
    design = sm.add_constant(np.column_stack([x, x**2]))
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        alpha, beta, gamma = sm.QuantReg(y, design).fit(q=tau, max_iter=5000).params
    return {"tau": tau, "alpha": float(alpha), "beta": float(beta), "gamma": float(gamma)}


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


def analyse() -> list[dict]:
    observations = read_observations()
    epoch = read_epoch_fits()
    spike_half_sigma = read_epoch_spike_half_sigma()
    rng = np.random.default_rng(SEED)
    models = []
    for model in MODEL_ORDER:
        rows = observations[model]
        xs, floor = per_length_min(rows)
        floor_fit = ols_curvature_test(xs, floor)
        models.append(
            {
                "model": model,
                "observations": [{"block": b, "x": x, "ttft": y} for b, x, y in sorted(rows, key=lambda r: (r[1], r[2]))],
                "floor": [{"x": float(x), "ttft": float(y)} for x, y in zip(xs, floor)],
                "blocks": len({r[0] for r in rows}),
                "floor_fit": floor_fit,
                "floor_bootstrap": block_bootstrap(rows, rng),
                "floor_sensitivity": leave_one_out(rows),
                "quantile_fits": [quantile_fit(rows, tau) for tau in TABLE_QUANTILES],
                "quantile_sweep": [quantile_fit(rows, tau) for tau in SWEEP_QUANTILES],
                "epoch_student_t": {str(d): c for d, c in epoch[model].items()},
                "epoch_primary_degree": EPOCH_PRIMARY_DEGREE[model],
                "epoch_spike_half_sigma": spike_half_sigma.get(model),
                "extrapolation": {
                    "floor_quadratic": extrapolate(polynomial(floor_fit["quadratic"])),
                    "epoch_primary": extrapolate(polynomial(epoch[model][EPOCH_PRIMARY_DEGREE[model]])),
                },
            }
        )
    return models


def write_tables(models: list[dict]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "fits.json").write_text(json.dumps({"generated_by": "analysis/floor.py", "seed": SEED, "models": models}, indent=1) + "\n")
    with open(OUT / "curvature_by_estimator.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "model", "blocks", "floor_gamma", "floor_beta", "floor_f_statistic", "floor_p_value",
                "q10_gamma", "q25_gamma", "q50_gamma", "epoch_student_t_gamma", "epoch_spike_half_sigma_gamma",
                "floor_bootstrap_q025", "floor_bootstrap_q975", "floor_bootstrap_fraction_positive",
                "floor_drop_block_min", "floor_drop_block_max", "floor_drop_length_min", "floor_drop_length_max",
            ]
        )
        for m in models:
            q = {round(qf["tau"], 2): qf["gamma"] for qf in m["quantile_fits"]}
            s = m["floor_sensitivity"]
            b = m["floor_bootstrap"]
            spike = m["epoch_spike_half_sigma"]
            w.writerow(
                [
                    m["model"], m["blocks"], m["floor_fit"]["quadratic"]["gamma"], m["floor_fit"]["quadratic"]["beta"],
                    m["floor_fit"]["f_statistic"], m["floor_fit"]["p_value"],
                    q[0.1], q[0.25], q[0.5], m["epoch_student_t"]["2"]["gamma"], spike["gamma"] if spike else "",
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


FLOOR = "#1f77b4"
CLOUD = "#9a9a9a"
EPOCH = "#555555"
PANEL_ORDER = ["Claude Opus 5", "GPT-5.6 Sol", "Claude Sonnet 5", "GPT-5.6 Terra", "GPT-6 Astra"]


def style(ax) -> None:
    ax.spines[["top", "right"]].set_visible(False)
    ax.grid(axis="y", color="#e5e5e5", linewidth=0.6)
    ax.set_axisbelow(True)


def figure_floor_fits(models: list[dict]) -> None:
    by_name = {m["model"]: m for m in models}
    fig, axes = plt.subplots(2, 3, figsize=(12.5, 7.4), constrained_layout=True)
    x_grid = np.linspace(0, 1, 101)
    for ax, name in zip(axes.flat, PANEL_ORDER):
        m = by_name[name]
        obs_x = [o["x"] for o in m["observations"]]
        obs_y = [o["ttft"] for o in m["observations"]]
        floor_x = [o["x"] for o in m["floor"]]
        floor_y = [o["ttft"] for o in m["floor"]]
        floor_poly = polynomial(m["floor_fit"]["quadratic"])
        epoch_poly = polynomial(m["epoch_student_t"][str(m["epoch_primary_degree"])])
        ax.scatter(obs_x, obs_y, s=12, color=CLOUD, alpha=0.6, linewidths=0, label="Every other request")
        ax.scatter(floor_x, floor_y, s=22, color=FLOOR, linewidths=0, zorder=3, label="Fastest request at that length")
        ax.plot(x_grid, np.polyval(epoch_poly, x_grid), color=EPOCH, linewidth=1.3, linestyle=(0, (5, 4)),
                label="Epoch headline fit (quadratic GPT, linear Claude)")
        ax.plot(x_grid, np.polyval(floor_poly, x_grid), color=FLOOR, linewidth=2, label="Quadratic fit to the floor")
        ax.set_title(f"{name}   γ = {m['floor_fit']['quadratic']['gamma']:.1f}", loc="left", fontsize=11)
        ax.set_xlim(0, 1)
        ax.set_ylim(0, None)
        ax.set_xticks([0, 0.25, 0.5, 0.75, 1], ["0", "250k", "500k", "750k", "1M"])
        style(ax)
    axes[1, 2].axis("off")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    axes[1, 2].legend(handles, labels, loc="center left", frameon=False, fontsize=10)
    for ax in axes[:, 0]:
        ax.set_ylabel("Time to first token (s)")
    for ax in axes[1, :2]:
        ax.set_xlabel("Input context (tokens)")
    fig.suptitle("Fitted to the floor, Claude Opus 5 curves like GPT-5.6 Sol; Claude Sonnet 5 stays linear", x=0.01, ha="left", fontsize=13)
    FIGURES.mkdir(parents=True, exist_ok=True)
    for ext in ("png", "svg"):
        fig.savefig(FIGURES / f"floor_fit_five_models.{ext}", dpi=200)
    plt.close(fig)


def figure_gamma_by_quantile(models: list[dict]) -> None:
    fig, ax = plt.subplots(figsize=(8, 4.8), constrained_layout=True)
    colours = {
        "Claude Opus 5": "#d62728",
        "Claude Sonnet 5": "#ff9896",
        "GPT-5.6 Sol": "#1f77b4",
        "GPT-5.6 Terra": "#aec7e8",
        "GPT-6 Astra": "#2ca02c",
    }
    for m in models:
        taus = [q["tau"] for q in m["quantile_sweep"]]
        gammas = [q["gamma"] for q in m["quantile_sweep"]]
        ax.plot(taus, gammas, marker="o", markersize=3.5, linewidth=1.8, color=colours[m["model"]], label=m["model"])
        ax.scatter([0], [m["floor_fit"]["quadratic"]["gamma"]], marker="D", s=30, color=colours[m["model"]], zorder=3)
    ax.axhline(0, color="#999999", linewidth=0.8)
    ax.set_xlim(-0.03, 0.98)
    ax.set_xticks([0, 0.1, 0.25, 0.5, 0.75, 0.95], ["floor", "p10", "p25", "median", "p75", "p95"])
    ax.set_xlabel("Which part of the TTFT distribution the quadratic is fitted to")
    ax.set_ylabel("Quadratic coefficient γ (s per M tokens²)")
    ax.set_title("Curvature depends on the estimator only for Opus", loc="left", fontsize=12)
    ax.legend(frameon=False, fontsize=9)
    style(ax)
    for ext in ("png", "svg"):
        fig.savefig(FIGURES / f"gamma_by_quantile.{ext}", dpi=200)
    plt.close(fig)


def main() -> None:
    models = analyse()
    write_tables(models)
    figure_floor_fits(models)
    figure_gamma_by_quantile(models)
    for m in models:
        f = m["floor_fit"]
        q = {round(qf["tau"], 2): qf["gamma"] for qf in m["quantile_fits"]}
        s = m["floor_sensitivity"]
        print(
            f"{m['model']:16s} floor γ={f['quadratic']['gamma']:5.1f} (F={f['f_statistic']:5.1f}, p={f['p_value']:.3f})"
            f"  p10 γ={q[0.1]:5.1f}  p25 γ={q[0.25]:5.1f}  median γ={q[0.5]:5.1f}"
            f"  Epoch t γ={m['epoch_student_t']['2']['gamma']:5.1f}"
            f"  drop-block [{min(s['drop_one_block_gamma']):.1f}, {max(s['drop_one_block_gamma']):.1f}]"
        )


if __name__ == "__main__":
    main()
