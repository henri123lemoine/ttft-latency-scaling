# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "scipy>=1.14"]
# ///
"""Compare collection designs by how well the floor fit recovers curvature.

Each simulated session draws per-request delay above the fitted Claude 5 floor from
that session's own pooled excess, keeps the fastest request per length, and fits a
quadratic. Delays are treated as independent, so absolute power is optimistic;
the ranking between designs is the useful part.

Run with `uv run analysis/design_power.py outputs/tables/request_observations.csv`.
"""
import csv, sys
import numpy as np
from scipy import stats

obs = {}
with open(sys.argv[1]) as f:
    for r in csv.DictReader(f):
        obs.setdefault(r["model"], []).append((float(r["total_input_tokens"]) / 1e6, float(r["ttft_seconds"])))

def ftest(xs, ys):
    q = np.polyfit(xs, ys, 2); l = np.polyfit(xs, ys, 1)
    rq = np.sum((ys - np.polyval(q, xs))**2); rl = np.sum((ys - np.polyval(l, xs))**2)
    df = len(xs) - 3
    X = np.column_stack([np.ones_like(xs), xs, xs**2])
    se = np.sqrt(rq / df * np.linalg.inv(X.T @ X)[2, 2])
    return q[0], stats.f.sf((rl - rq) / (rq / df), 1, df), 2 * stats.t.ppf(.975, df) * se

even = lambda n: list(np.linspace(0.05, 0.9, n))
EPOCH = [0.05, 0.1, 0.175, 0.25, 0.375, 0.55, 0.75, 0.9]
designs = {
    "Epoch grid x14": (EPOCH, 14),
    "Epoch grid x10": (EPOCH, 10),
    "Epoch grid x8": (EPOCH, 8),
    "Epoch grid x6": (EPOCH, 6),
    "12 even x6": (even(12), 6),
    "16 even x4": (even(16), 4),
    "12 even x4": (even(12), 4),
    "6 lengths x8": ([0.05, 0.1, 0.25, 0.5, 0.75, 0.9], 8),
    "4 lengths x10": ([0.05, 0.3, 0.6, 0.9], 10),
    "to 600k, 8 even x8": (list(np.linspace(0.05, 0.6, 8)), 8),
}
rng = np.random.default_rng(1)
SIMS = 4000
for model in ["Claude Opus 5", "Claude Sonnet 5"]:
    xs = np.array([x for x, _ in obs[model]]); ys = np.array([y for _, y in obs[model]])
    lens = sorted(set(np.round(xs, 3)))
    mins = np.array([ys[np.round(xs, 3) == L].min() for L in lens])
    floor = np.polyfit(lens, mins, 2)
    excess = ys - np.polyval(floor, xs)
    print(f"\n{model}: floor gamma {floor[0]:.2f} s/Mtok^2; excess median {np.median(excess):.2f}s, p90 {np.quantile(excess,.9):.2f}s")
    print(f"{'design':22s} {'Mtok':>6s} {'Opus5.5 $':>9s} {'power p<.05':>11s} {'median CI width':>15s} {'gamma sd':>8s}")
    for name, (L, R) in designs.items():
        L = np.array(L)
        g, p, w = [], [], []
        for _ in range(SIMS):
            sim = np.polyval(floor, L)[:, None] + rng.choice(excess, size=(len(L), R))
            gg, pp, ww = ftest(L, sim.min(axis=1))
            g.append(gg); p.append(pp); w.append(ww)
        mtok = L.sum() * R
        print(f"{name:22s} {mtok:6.1f} {mtok*4:9.0f} {np.mean(np.array(p)<.05):11.2f} {np.median(w):15.2f} {np.std(g):8.2f}")
