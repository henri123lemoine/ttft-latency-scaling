# GPT-6 Sol / GPT-6.1 Sol — direct API shared-prefix replication

Collection completed October 6, 2026, within the approved USD 80 combined budget.
No subscription requests were used. This supplement does not replace the original headline fits.

## Collection and cost

| Model | Measured requests | Complete blocks | Measured window (Eastern Daylight Time) | Cost including its prefix setup |
|---|---:|---:|---|---:|
| GPT-6 Sol | 30 | 5 | 09:31:37–09:35:44 | $38.0908515 |
| GPT-6.1 Sol | 30 | 5 | 09:38:02–09:43:42 | $38.0816220 |

New collection total: **$76.1724735**. Including the earlier reasoning pilot
($0.6939188), the conservative combined ledger is **$76.8663923**, leaving
**$3.1336077** of the authorized $80. Estimates use provider-reported usage and
documented Standard prices, not an account invoice. No further collection is
running or scheduled.

All 60 measured requests returned `OK`, reported zero reasoning tokens, hit
exactly **2,051** prefix tokens, wrote **zero** cache tokens, and returned the
requested model and Standard tier. Remaining input was new. All actual total
inputs were nominal minus two tokens. There were no failed inference attempts,
retries, or incomplete blocks. The two prefix setup calls are excluded from fits.
No latency observations were removed.

Stable prefix SHA-256 (both models, identical to the finalized GPT-5.6 prefix):
`730485e7e542bd012d1a7de896a57ef9d4048173bb8dcdc412e0127ef1738836`.

The sessions use the original six-length design, original corpus, prompt
construction, and streaming timer. GPT-6 Sol used reasoning `none`; GPT-6.1 Sol
used `low`, because `none` is unsupported. Zero reported reasoning on the latter
does not establish that all underlying computation is identical across settings.

## Observed latency and dispersion

Each cell has five observations. CV is sample standard deviation / mean; it is
especially sensitive to the retained high-latency observations.

| Nominal total input | GPT-6 median TTFT | GPT-6 CV | GPT-6.1 median TTFT | GPT-6.1 CV |
|---:|---:|---:|---:|---:|
| 50,000 | 1.351887771 s | 12.6562% | 2.318832162 s | 14.2904% |
| 175,000 | 2.711317747 s | 8.6191% | 4.023936027 s | 18.9770% |
| 250,000 | 3.769130932 s | 6.0193% | 4.345943635 s | 16.1517% |
| 275,000 | 4.472620648 s | 15.6667% | 5.175445019 s | 38.4989% |
| 550,000 | 9.770058451 s | 12.7718% | 10.063403594 s | 5.7551% |
| 850,000 | 17.429677727 s | 0.9534% | 14.814622995 s | 39.1647% |

GPT-6.1 was noisier at most, but not every, length. In particular, its retained
275k observation of 10.373045207 seconds and 850k observation of 30.820969713
seconds inflated those cells' dispersion. Its other 850k observations were
14.367235520, 16.200910575, 14.814622995, and 14.602732251 seconds.

At the fifth-block checkpoint, GPT-6.1 still triggered the operational noise
warning. Collection ended at the planned five blocks; it was not declared clean.
See [checkpoint decisions](checkpoint-review.md) for the discretionary continuation
after warnings at blocks three and four. No fits or significance values were
consulted in those decisions. These observations do not measure provider load
or establish that popularity caused the dispersion difference.

## Fits using all complete blocks

All coefficients use x = actual total input tokens / 1,000,000 and TTFT in seconds.
All fits include sum-to-zero chronological block fixed effects. Curves display
the zero-block-effect baseline, not a prediction for a particular block.

Student-t quadratic: alpha + beta*x + gamma*x^2; df fixed at 4.

| Model | alpha | beta | gamma | sigma | 2 delta log L | Approximate LR p (chi-square 1) |
|---|---:|---:|---:|---:|---:|---:|
| GPT-6 Sol | 0.811160862566 | 9.605229938369 | 11.696805680579 | 0.223566695002 | 44.154489041090 | 3.034550913763e-11 |
| GPT-6.1 Sol | 1.740882429324 | 11.710841593683 | 4.765631283990 | 0.567235529416 | 4.678127807194 | 0.030549024775 |

Linear/quadratic AICc: GPT-6 **90.292884794566 / 49.904629519709**;
GPT-6.1 **113.813236714058 / 112.901342673098**. Thus Student-t curvature is much
more strongly supported for GPT-6; the GPT-6.1 AICc improvement is only about 0.91.
LR values are conditional asymptotic approximations, not block-calibrated exact
p-values or corrections for the adaptive collection reviews.

| Model | Estimator | Quadratic gamma | Whole-block bootstrap 95% interval |
|---|---|---:|---|
| GPT-6 Sol | Huber | 11.407735867528 | [5.442077487990, 12.909321401880] |
| GPT-6.1 Sol | Huber | 5.124477962720 | [0.972478285142, 25.560959787022] |
| GPT-6 Sol | Frontier | 11.748386691393 | [3.977093014479, 13.300975666308] |
| GPT-6.1 Sol | Frontier | 5.617660414460 | [1.106054214043, 10.658539854548] |
| GPT-6 Sol | Spike + contention | 12.256033864295 | [4.426968202308, 13.669110194681] |
| GPT-6.1 Sol | Spike + contention | 4.639961079198 | [1.855181073113, 9.131274002464] |

Huber intervals use 5,000 resamples per model (all successful). Asymmetric
intervals use 200 per family/model (all converged); the robust sigma anchor is
recomputed inside each replicate. Huber intervals are **not** Student-t intervals.
Five blocks provide limited independent replication and bootstrap resolution.
The frontier/spike intervals are also conditional on their asymmetric noise and
nonnegative-curvature assumptions. Full coefficients and 0.5x/2x sigma sensitivity
are provided in the CSVs below.

Point estimates have smaller curvature for GPT-6.1 across all three displayed
estimators. This is not itself a calibrated test of the between-model curvature
difference, and the Huber interval for GPT-6.1 is wide. The sessions are unpaired,
in different time windows, with different supported reasoning settings. No model
size, architecture, or hardware conclusion follows from these measurements alone.

## Reproduction

See [the supplement overview](../sol-api.md) for offline commands and all artifact paths.
