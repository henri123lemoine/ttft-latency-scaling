# Claude 5.5 replication: blockers, cost, and design

Plan for rerunning Epoch's shared-prefix TTFT session on Claude Opus 5.5, Sonnet 5.5
and Haiku 5.5, then fitting it both Epoch's way (Student-t) and with the floor fit
from `analysis/floor.py`. Checked on 2026-10-07 from a cloud session; nothing paid has
been sent yet.

## Blockers

### Needs Henri

1. **Anthropic API key.** None in the environment. The collector reads
   `ANTHROPIC_API_KEY` from `.env` or the environment.
2. **Rate limits on that key's org (unverified until the key exists).** A 900k request
   needs an input-tokens-per-minute (ITPM) limit of at least 900k per model, or it
   fails every time. From Epoch's request spacing, a session asks for roughly 2.5M (Opus) to
   5M (Sonnet) ITPM. Below that the collector retries 429s (up to 120 s each), which
   stretches the session and spaces requests unevenly. Check Console > Limits.
3. **Spend limit** of at least the budget below, plus about 10% for retried requests.

### Fixed on this branch

4. **The 5.5 models reject Epoch's request.** Epoch sent `thinking: disabled`, which
   is now accepted only by Haiku 5.5. `config/benchmark.toml` adds the three models:

   | Model | thinking | effort | Why |
   |---|---|---|---|
   | claude-opus-5-5 | adaptive | low | `disabled` is a 400 at every effort |
   | claude-sonnet-5-5 | between_tools | low | Sonnet 5.5's thinking-off mode; `disabled` is a 400 |
   | claude-haiku-5-5 | disabled | high | accepted at effort high or below |

5. **Opus 5.5 could burn paid requests with no measurement.** With a 32-token cap, a
   request that thinks first can run out before the `OK`, leaving no first text
   token. The 900k-token input is still billed. Models can now set their own
   `max_output_tokens`, and Opus 5.5 uses 1024. Claude 5 requests are unchanged.
6. **No record of why a response stopped.** The collector now logs `stop_reason`, so
   refusals and output-cap stops show up in the data.

### Checked and fine

- **Network.** `api.anthropic.com` bypasses the session's egress proxy (it is on the
  no-proxy list), so streaming is not buffered. Connect time is about 3 ms. A 3.8 MB
  body (about the size of a 900k prompt) uploads in 0.2–0.4 s. That upload time
  grows linearly with length, so it adds to the linear term, not to curvature.
- **Collector code.** The fork's `floor-fit` branch has the same collector as
  upstream `main`. Upstream's two newer commits are the GPT-6 Sol supplement only.
- **Python.** 3.13 with uv. `requirements.lock` installs, and the floor fit's
  numpy/scipy run.
- **Prompt cache.** The 5.5 minimum cacheable prefix is 512 tokens, below the 2,048
  shared prefix.
- **Request payloads.** Tested against a mocked stream for all three 5.5 models and
  Sonnet 5 (unchanged).

### Will only show up with a key (all free or nearly)

- Whether `count_tokens` accepts `between_tools` and `adaptive`. Sizing calls it
  hundreds of times per model. It is free but limited by requests per minute.
- Whether Opus 5.5 at low effort skips thinking on this prompt. If it doesn't, TTFT
  includes thinking time. The first-content-block time is the fallback timer.
- Haiku 5.5 has a newer tokenizer. It needs its own `prepare-prompts`, which is
  free; Opus and Sonnet 5.5 share the Claude 5 tokenizer.

### Needed for analysis, not for collection

- **R isn't installed** and isn't in this Ubuntu image's apt sources. It is needed
  for Epoch's Student-t fits (`analysis/reproduce.R`, MASS). conda-forge is
  reachable, so R can probably come from there (untested). The floor fit is Python
  and already runs.
- **The analysis scripts hard-code the Claude 5 sessions.** A small
  `analysis/claude_5_5.py` (floor fit) and an R counterpart are needed.
- **The container is temporary.** Raw JSONL goes to the git-ignored `live-results/`
  and must be copied to `data/raw/claude-5.5/` and pushed before the session ends.

## Cost

Measured requests carry the shared 2,048-token cached prefix. Everything else is
new input at full price. All numbers come from the collector's `estimate` with
current list prices.

| Blocks | Opus 5.5 | Sonnet 5.5 | Haiku 5.5 | Total |
|---:|---:|---:|---:|---:|
| 1 | $12.6 | $6.3 | $1.5 | $20 |
| 6 | $75 | $38 | $9 | $122 |
| 8 | $100 | $50 | $12 | $163 |
| 14 (Epoch's Sonnet) | $176 | $88 | $21 | $285 |

Same-day Claude 5 controls were considered and dropped: too expensive for what they add.

Haiku's prompts over 100k tokens bill at 5x ($0.50/M), which is most of its cost.
Sizing calls are free, and a two-request preflight per model costs under $0.25.

## What can't be made cheaper

- **Batch API (50% off):** no. Batches don't stream and run in a queue for minutes to
  hours, so there is no time to first token to measure.
- **Caching more of the prompt:** no. Prefill of new tokens is what's being measured.
  Epoch tried a large cached prefix with a 1k–10k-token new suffix. They dropped it
  because the signal was lost in the noise, and it answers a different question.
- **Fast mode and Priority Tier:** fast mode doubles Opus 5.5's price and changes the
  thing being measured. Priority Tier isn't offered for these models.

## What can be made cheaper or faster

**Use 8 blocks instead of 14.** `analysis/design_power.py` resamples Epoch's own
Claude 5 sessions under alternative designs (4,000 simulated sessions per design):

| Design | Mtok per model | Power vs Opus-5-sized curvature | 95% CI width on γ, Sonnet-5-like floor |
|---|---:|---:|---:|
| Epoch grid, 14 blocks | 44 | 1.00 | 2.0 |
| Epoch grid, 8 blocks | 25 | 1.00 | 2.5 |
| Epoch grid, 6 blocks | 19 | 0.98 | 2.8 |
| 12 even lengths, 4 blocks | 23 | 0.88 | 2.7 |
| 6 lengths, 8 blocks | 20 | 0.97 | 3.2 |
| 4 lengths, 10 blocks | 19 | 0.62 | 9.4 |
| Capped at 600k, 8 blocks | 21 | 0.80 | 5.6 |

Epoch's eight-length grid is already a good design. Dropping lengths or capping the
range saves little, because the longest prompts dominate the bill, and it costs
much more precision than it saves. Fewer blocks is the lever that works: 8 blocks
cut cost 43% from 14 and still detect Opus-5-sized curvature. The cost is a CI on
γ about 25% wider for a near-linear model like Sonnet. Absolute power is
optimistic because the simulation treats delays as independent; the ranking is the
useful part.

**Run the three models at once.** Each model has its own rate limits and serving
fleet. Running three collector processes in parallel should cut wall time from roughly
40 minutes to roughly 15, an estimate from Epoch's request spacing (sizing plus the
Opus session, the slowest). Within a model,
requests stay sequential as Epoch's were.

## Within $100

Budget-limited designs, simulated against two noise levels (Opus 5's Aug 13 session,
which was noisy, and Sonnet 5's, which was clean) and three true curvatures. Cells
are power to reject linear at p < 0.05 and the median 95% half-width on γ
(`analysis/design_power.py` approach, 3,000 runs each; optimistic in absolute terms).

| Blocks (Epoch grid) | Opus noise, γ 9.3 | Opus noise, γ 4.3 | Opus noise, γ 0 | Sonnet noise, γ 4.3 | Sonnet noise, γ 0 |
|---:|---|---|---|---|---|
| 3 | 0.67, ±6.4 | 0.31, ±6.2 | 0.05, ±6.3 | 0.90, ±2.1 | 0.05, ±2.2 |
| 4 | 0.85, ±4.7 | 0.46, ±4.6 | 0.05, ±4.7 | 0.97, ±1.7 | 0.04, ±1.7 |
| 5 | 0.94, ±3.8 | 0.60, ±3.8 | 0.05, ±3.8 | 0.99, ±1.5 | 0.05, ±1.5 |
| 6 | 0.97, ±3.2 | 0.70, ±3.1 | 0.06, ±3.2 | 1.00, ±1.4 | 0.04, ±1.4 |

γ 9.3 and 4.3 are Opus 5's floor curvature on Aug 13 and 14. Six or five lengths at
matched cost were no better: about even under Opus noise, worse under Sonnet noise.

Plan for $100, run in this order so later spending can react to earlier noise:

1. Preflight, all three models (under $1).
2. Haiku 5.5, 8 blocks ($12).
3. Sonnet 5.5, 5 blocks ($32).
4. Opus 5.5, 4 blocks ($50), the most expensive and the noisiest last time.

That leaves about $5 for billed retries. If a 5.5 model is as clean as Sonnet 5, 4–5
blocks detect even Opus-5-Aug-14-sized curvature almost every time. If Opus 5.5 is
as noisy as Opus 5 was, 4 blocks usually (85%) tell "Opus-5-like" (γ around 9)
from linear, but a γ around 4 only about half the time; the CI will say which case it is.

## Recommended run

Preflight first (under $1): `prepare-prompts` for the three models, then a
two-request session per model at 50k to confirm each payload is accepted, the output
is exactly `OK`, the cache hits, and the stop reason is `end_turn`.

Then the blocks above per model on Epoch's grid, in the order above (8 each if the
budget allows, and then the three can run in parallel):

```bash
PYTHONPATH=src python -m ttft_bench.cli run \
  --models anthropic_opus_5_5 \
  --lengths 50000,100000,175000,250000,375000,550000,750000,900000 \
  --repetitions 4 --shared-cache-prefix-tokens 2048 \
  --shared-cache-min-interval-seconds 4 \
  --skip-warmup --fixed-output --leading-nonce \
  --label opus-5-5-shared-prefix --network-label cloud \
  --max-cost-usd 52
```

Set `--max-cost-usd` per model to its share of the budget.

## Runbook for the $100 run

1. Python 3.12+ venv, `pip install -r requirements.lock`, `ANTHROPIC_API_KEY` in the shell
   or `.env` (never in chat or git).
2. `PYTHONPATH=src python -m ttft_bench.cli prepare-prompts --models anthropic_haiku_5_5,anthropic_sonnet_5_5,anthropic_opus_5_5 --lengths 50000,100000,175000,250000,375000,550000,750000,900000`
   (count_tokens only, free).
3. Preflight: one `run` per model with `--lengths 50000 --repetitions 2` and the
   shared-prefix flags below. Check that each request is accepted, the output is exactly `OK`,
   about 2,052 cache-read tokens are reported, `stop_reason` is `end_turn`, and Sonnet and Haiku
   have zero thinking blocks. If a payload is rejected, stop and report; don't work around
   it with paid requests.
4. Paid runs, one after another, on the 8-length grid with
   `--shared-cache-prefix-tokens 2048 --shared-cache-min-interval-seconds 4 --skip-warmup --fixed-output --leading-nonce`:
   Haiku 5.5 `--repetitions 8 --max-cost-usd 14`, then Sonnet 5.5
   `--repetitions 5 --max-cost-usd 34`, then Opus 5.5 `--repetitions 4 --max-cost-usd 52`.
   Repeated 429s mean the org's input-token rate limit is too low for 900k requests;
   report that rather than looping.
5. Copy `live-results/*.jsonl` to `data/raw/claude-5.5/`. Floor fit per model, as in
   `analysis/floor.py`: quadratic through the per-length minimum TTFT, curvature F-test
   p, 95% CI on γ, and marginal seconds per 10k tokens at 50k and 1M. For Opus 5.5,
   also fit `first_content_ns` and count requests with thinking blocks. Epoch's
   Student-t fits too if R is available.
6. Report per model: linear or quadratic, γ with CI, p, and the actual spend. Compare
   with the post: Opus 5's floor γ was about 9.3 (Aug 13) and 4.3 (Aug 14), both
   excluding zero; Sonnet 5's was about 0.4, with a CI that includes zero.
