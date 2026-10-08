# Claude 5.5 shared-prefix TTFT results (2026-10-07)

Epoch's protocol: 8 lengths from 50k to 900k tokens, a shared 2,048-token cached prefix,
randomized blocks, fixed `OK` output, collected from a laptop. First sessions ran 20:49 to
21:13 UTC on 2026-10-07; second Sonnet and Opus sessions ran 00:08 to 00:25 UTC on
2026-10-08. A model's two sessions are pooled below; per-session floors are in
`outputs/claude-5.5/fits.json`. Plan and design: `docs/claude-5.5-replication.md`.

| Model | Blocks | Requests | Thinking | Retries | Cost |
|---|---:|---:|---|---:|---:|
| Haiku 5.5 | 8 | 64 | disabled | 0 | $12.07 |
| Sonnet 5.5 | 5 + 5 | 80 | `between_tools`, effort low | 0 | $62.72 |
| Opus 5.5 | 4 + 5 | 72 | adaptive, effort low | 0 | $112.89 |

Total with the preflight: $188.30 (collector estimate from reported usage). Every request
returned 200, exactly `OK`, `end_turn`, and about 2,050 cache-read tokens. No measured
request had a thinking block, Opus 5.5 included, so first-token and first-content times
are identical.

## Fits

γ is the quadratic coefficient in seconds per (million tokens)². Intervals are 95%.

| Model | Student-t γ (Epoch's fit) | ΔAICc, linear − quadratic | Huber block bootstrap | Floor γ | Floor p | Median γ |
|---|---:|---:|---|---|---:|---|
| Haiku 5.5 | 14.4 | +67.7 | 11.4 to 16.8 | 17.4 (2.8 to 32.1) | 0.03 | 14.1 (12.6 to 15.6) |
| Sonnet 5.5 | 3.9 | −1.5 | −3.5 to 15.2 | −5.7 (−45.5 to 34.2) | 0.73 | 2.6 (−7.1 to 12.3) |
| Opus 5.5 | 11.7 | −1.5 | −15.6 to 38.4 | 8.3 (−11.4 to 28.1) | 0.33 | 14.8 (−0.5 to 30.0) |

For comparison, floor γ on Epoch's Claude 5 sessions (`outputs/floor/update_floor_curvature.csv`):
Opus 5 9.3 (4.4 to 14.2) on Aug 13 and 4.3 (2.4 to 6.3) on Aug 14; Sonnet 5 0.4 (−1.4 to 2.1)
and 0.6 (−4.0 to 5.2).

## Reading

- **Haiku 5.5 is curved.** Every estimator agrees and every interval excludes zero.
- **Sonnet 5.5 is linear under Epoch's fit** (slope about 19 s per million tokens against
  Sonnet 5's 12); its floor curvature is undetermined.
- **Opus 5.5 is undetermined** under both methods after 9 blocks.

## Fast requests

Requests under 60% of the median for their length: 2 of 64 for Haiku 5.5, 5 of 80 for
Sonnet 5.5, 10 of 72 for Opus 5.5, and none in Epoch's Claude 5 or GPT-5.6 sessions.
Examples: a 900k Sonnet 5.5 request in 5.4 s against an 18 s median, a 900k Opus 5.5
request in 9.4 s against 28 s. Their reported cache reads match every other request.
The floor fit passes through them, so the Sonnet 5.5 and Opus 5.5 floors sit 2 to 3
times below the typical request at 900k and are set by fast requests at some lengths
and not others. If noise only slows requests, they are the true floor and it is rarely
sampled; if they took a different serving path, the floor is the faster of two curves.
This data cannot tell those apart. `outputs/claude-5.5/` also carries a sensitivity fit
with them set aside (`ttft_excluding_fast`): Haiku 9.6 (6.0 to 13.2), Sonnet −0.9 (−5.2
to 3.3), Opus 1.5 (−17.2 to 20.2).

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
