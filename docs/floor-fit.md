# Floor fit supplement

`analysis/floor.py` refits the released observations against the fastest
request at each context length instead of the centre of the request
distribution. Provider-side queueing, routing, and cache placement add latency
but never remove it, so the per-length minimum is the closest available view of
the serving curve. `analysis/figures_floor.R` re-renders Figures 1-4 and A1 with
that fit added, in the layout and palette of the published web post (Inter
stands in for Messina Sans).

```bash
make floor
```

Outputs: `outputs/floor/fits.json`, `outputs/floor/floor_curvature.csv`,
`outputs/floor/extrapolated_ttft.csv`, `outputs/floor/marginal_latency.csv`, and
`figures/floor/*.{png,svg}`.

Quadratic coefficient γ (seconds per million tokens squared):

| model | floor fit | Student-t (upstream) | floor, drop one block | floor, drop one length |
| --- | --- | --- | --- | --- |
| GPT-5.6 Terra | 7.5 | 8.0 | 6.8 … 8.3 | 7.2 … 9.6 |
| GPT-5.6 Sol | 10.8 | 10.4 | 10.6 … 11.4 | 6.3 … 18.7 |
| Claude Sonnet 5 | 0.4 | −0.2 | −0.2 … 0.6 | 0.0 … 1.8 |
| Claude Opus 5 | 9.3 | 1.6 | 7.1 … 9.8 | 6.5 … 10.1 |
| GPT-6 Astra | 13.3 | 11.6 | 9.4 … 14.9 | 12.5 … 14.1 |

Per-pass curvature (one quadratic per chronological block) gives an
independent check that does not rely on minima: Sonnet mean γ 0.9 ± 1.2 over 14
passes (p = 0.47 against zero); Sol 10.8 ± 1.4; Terra 9.5 ± 1.6. A Welch test of
Sonnet against Sol gives t = −5.4, p = 3 × 10⁻⁴, so Sonnet's flat curve is not a
sampling fluke of a Sol-like distribution. The floor-fit 95% interval for Sonnet
is −1.4 to 2.1, which rules out Sol-like curvature but not a hybrid with a
quadratic term a third the size. Opus per-pass γ is 0 ± 4.4: within a pass the
slow requests dominate, which is why the floor, not the average, carries the
Opus signal.

Marginal TTFT per 10,000 additional input tokens, 10M relative to 1M: Terra
7.7× under the upstream fit and 7.5× under the floor fit; Sol 6.8× and 6.9×;
Sonnet 1.0× and 1.6×; Opus 1.0× and 6.4×.

The floor fit is ordinary least squares on one point per length, so its F-test
has few degrees of freedom. The whole-block bootstrap in `floor_curvature.csv`
is pessimistic for Opus: with six blocks, resampling with replacement usually
drops the block holding the true minimum at some length. The drop-one-block and
drop-one-length ranges are the more informative uncertainty summaries at this
sample size. The upstream spike-plus-contention fit at half the sigma anchor
(`outputs/tables/asymmetric_sigma_sensitivity.csv`) already gives Opus γ = 6.4.
