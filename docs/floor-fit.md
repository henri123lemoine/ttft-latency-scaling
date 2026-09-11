# Floor fit supplement

`analysis/floor.py` refits the released observations against the fastest
request at each context length instead of the centre of the request
distribution. Provider-side queueing, routing, and cache placement add latency
but never remove it, so the per-length minimum is the closest available view of
the serving curve itself. The script also fits quadratic quantile regressions
from p05 to p95 to show how curvature moves with the estimator.

```bash
make floor
```

Outputs: `outputs/floor/fits.json`, `outputs/floor/curvature_by_estimator.csv`,
`outputs/floor/extrapolated_ttft.csv`, and `figures/floor/*.{png,svg}`.

Quadratic coefficient γ (seconds per million tokens squared):

| model | floor | p10 | p25 | median | Student-t (upstream) | floor, drop one block | floor, drop one length |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GPT-5.6 Terra | 7.5 | 8.1 | 7.9 | 8.5 | 8.0 | 6.8 … 8.3 | 7.2 … 9.6 |
| GPT-5.6 Sol | 10.8 | 13.5 | 10.9 | 9.5 | 10.4 | 10.6 … 11.4 | 6.3 … 18.7 |
| GPT-6 Astra | 13.3 | 14.8 | 12.2 | 11.7 | 11.6 | 9.4 … 14.9 | 12.5 … 14.1 |
| Claude Sonnet 5 | 0.4 | 0.0 | 0.6 | 0.1 | −0.2 | −0.2 … 0.6 | 0.0 … 1.8 |
| Claude Opus 5 | 9.3 | 8.1 | 6.3 | −3.8 | 1.6 | 7.1 … 9.8 | 6.5 … 10.1 |

Floor fits are ordinary least squares on one point per length, so the F-test
column in `curvature_by_estimator.csv` has few degrees of freedom. The
whole-block bootstrap of the floor fit is reported but is pessimistic for
Opus: with six blocks, resampling with replacement usually drops the block
holding the true minimum at some length. The drop-one-block and drop-one-length
ranges are the more informative uncertainty summaries at this sample size.
Quantile fits use no block effects.

The upstream spike-plus-contention fit at half the sigma anchor
(`outputs/tables/asymmetric_sigma_sensitivity.csv`) already gives Opus γ = 6.4,
consistent with the floor fit.
