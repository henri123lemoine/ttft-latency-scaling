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

| Model | Student-t γ (Epoch's fit) | ΔAICc, linear − quadratic | Huber block bootstrap | Floor γ | Floor p | Median γ |
|---|---:|---:|---|---|---:|---|
| Haiku 5.5 | 14.4 | +67.7 | 11.4 to 16.8 | 17.4 (2.8 to 32.1) | 0.03 | 14.1 (12.6 to 15.6) |
| Sonnet 5.5 | 2.6 | −2.9 | −6.5 to 23.1 | −14.0 (−53.4 to 25.4) | 0.40 | 6.6 (−0.5 to 13.7) |
| Opus 5.5 | 15.1 | −1.2 | 0.3 to 44.1 | 5.9 (−21.4 to 33.2) | 0.60 | 16.2 (0.6 to 31.9) |

For comparison, floor γ on Epoch's Claude 5 sessions (`outputs/floor/update_floor_curvature.csv`):
Opus 5 9.3 (4.4 to 14.2) on Aug 13 and 4.3 (2.4 to 6.3) on Aug 14; Sonnet 5 0.4 (−1.4 to 2.1)
and 0.6 (−4.0 to 5.2).

## Reading

- **Haiku 5.5 is curved.** Every estimator agrees and every interval excludes zero. Medians
  run from 1.1 s at 50k to 14.8 s at 900k.
- **Sonnet 5.5 is linear under Epoch's fit** (slope about 17 s per million tokens against
  Sonnet 5's 12), but its floor is undetermined.
- **Opus 5.5 is undetermined.** Epoch's criterion narrowly picks linear; the medians lean
  curved; the floor interval contains both zero and Opus 5's 9.3. Its median at 900k is
  30 s, against 21 s and 16 s in Opus 5's two sessions.

## Fast requests

Seven requests came back in under 60% of the median for their length, some far under:
a 900k Sonnet 5.5 request in 5.4 s against a 16.7 s median, two 550k Haiku 5.5 requests
in about 3 s against 6.7 s. Their reported cache reads match every other request, and
none of Epoch's Claude 5 or GPT-5.6 sessions has a request like them. The floor fit
passes through them, which is what makes the Sonnet 5.5 and Opus 5.5 floors ragged. If
noise only slows requests, they are the true floor and four or five passes rarely reach
it; if they took a different serving path, the floor mixes two curves. This data cannot
tell those apart. `outputs/claude-5.5/` also carries a sensitivity fit with them set
aside (`ttft_excluding_fast`): Haiku 9.6 (6.0 to 13.2), Sonnet 0.35 (−5.2 to 5.9), Opus
−0.05 (−17.5 to 17.4).

## Files

- `data/raw/claude-5.5/`: session logs, with the usual release redactions
  (`scripts/prepare_claude_5_5_data.py`). The three `preflight-*` files are the
  two-request checks.
- `analysis/claude_5_5.py`: floor and median fits. `analysis/claude_5_5.R`: Epoch's
  Student-t fits and Huber block bootstrap. `analysis/figures_claude_5_5.R`:
  `figures/claude-5.5/`, in the layout of the floor-fit post.
- `docs/claude-5.5-post.html`: the results as a page in the blog's style, built by
  `scripts/build_claude_5_5_page.py` from `docs/claude-5.5-post.body.html`.
- `outputs/claude-5.5/`: `floor_curvature.csv`, `student_t_fits.csv`, `fits.json`,
  `request_observations.csv`.
