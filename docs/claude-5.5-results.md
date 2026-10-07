# Claude 5.5 shared-prefix TTFT results (2026-10-07)

One session per model on Epoch's protocol: 8 lengths from 50k to 900k tokens, a shared
2,048-token cached prefix, randomized blocks, fixed `OK` output, collected from a laptop
between 20:49 and 21:13 UTC. Plan and design: `docs/claude-5.5-replication.md`.

| Model | Blocks | Requests | Thinking | Retries | Cost |
|---|---:|---:|---|---:|---:|
| Haiku 5.5 | 8 | 64 | disabled | 0 | $12.07 |
| Sonnet 5.5 | 5 | 40 | `between_tools`, effort low | 0 | $31.36 |
| Opus 5.5 | 4 | 32 | adaptive, effort low | 0 | $50.18 |

Total with the preflight: $94.23 (collector estimate from reported usage). Every request
returned 200, exactly `OK`, `end_turn`, and about 2,050 cache-read tokens. No measured
request had a thinking block, Opus 5.5 included, so first-token and first-content times
are identical and the Opus 5.5 numbers are thinking-free.

## Fits

γ is the quadratic coefficient in seconds per (million tokens)². Intervals are 95%.

| Model | Student-t γ (Epoch's fit) | ΔAICc, linear − quadratic | Huber block bootstrap | Floor γ, fast requests set aside | Floor p | Median γ |
|---|---:|---:|---|---|---:|---|
| Haiku 5.5 | 14.4 | +67.7 | 11.4 to 16.8 | 9.6 (6.0 to 13.2) | 0.001 | 14.1 (12.6 to 15.6) |
| Sonnet 5.5 | 2.6 | −2.9 | −6.5 to 23.1 | 0.35 (−5.2 to 5.9) | 0.88 | 6.6 (−0.5 to 13.7) |
| Opus 5.5 | 15.1 | −1.2 | 0.3 to 44.1 | −0.05 (−17.5 to 17.4) | 0.99 | 16.2 (0.6 to 31.9) |

For comparison, floor γ on Epoch's Claude 5 sessions (`outputs/floor/update_floor_curvature.csv`):
Opus 5 9.3 (4.4 to 14.2) on Aug 13 and 4.3 (2.4 to 6.3) on Aug 14; Sonnet 5 0.4 (−1.4 to 2.1)
and 0.6 (−4.0 to 5.2).

Marginal latency from the floor fit, seconds per 10k tokens at 50k and at 1M:
Haiku 5.5 0.056 and 0.238; Sonnet 5.5 0.153 and 0.160; Opus 5.5 0.196 and 0.195.

## Reading

- **Haiku 5.5 is curved.** Every estimator agrees and every interval excludes zero. Its
  curvature is at least as large as Opus 5's, on a much lower base: medians run from
  1.1 s at 50k to 14.8 s at 900k.
- **Sonnet 5.5 is consistent with linear**, like Sonnet 5, with a steeper slope (about
  15 s per million tokens against 12). Five blocks do not exclude a mild curve: the
  Student-t fit prefers linear, the floor is flat, and the medians lean curved.
- **Opus 5.5 is undetermined.** Four blocks were too few for this session's noise. The
  bulk of requests leans curved (Student-t γ 15, median γ 16, both intervals barely
  excluding zero), while the floor is a straight line with an interval of ±17 that
  contains both zero and Opus 5's 9.3. Opus 5.5 is also slower than Opus 5 at every
  length: about 20 s per million tokens at the floor against 12.6.

## Fast requests

Seven requests came back in under 60% of the median for their length, some far under:
a 900k Sonnet 5.5 request in 5.4 s against a 16.7 s median, two 550k Haiku 5.5 requests
in about 3 s against 6.7 s. Their reported cache reads match every other request. The
floor method assumes the fastest request is the serving curve, so these break it: the
unfiltered floor γ is 17.4 (2.8 to 32.1) for Haiku, −14.0 (−53 to 25) for Sonnet and 5.9
(−21 to 33) for Opus. The table above sets them aside with a rule chosen after seeing
the data (`ttft_excluding_fast` in `outputs/claude-5.5/`); both versions are reported
there. Whether they are a second serving path or unreported cache reuse is unknown.

## Files

- `data/raw/claude-5.5/`: session logs, with the usual release redactions
  (`scripts/prepare_claude_5_5_data.py`). The three `preflight-*` files are the
  two-request checks.
- `analysis/claude_5_5.py`: floor and median fits. `analysis/claude_5_5.R`: Epoch's
  Student-t fits, Huber block bootstrap and `figures/claude-5.5-floor.png`.
- `outputs/claude-5.5/`: `floor_curvature.csv`, `student_t_fits.csv`, `fits.json`,
  `request_observations.csv`.
