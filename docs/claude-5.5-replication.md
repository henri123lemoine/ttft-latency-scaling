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

| Blocks | Opus 5.5 | Sonnet 5.5 | Haiku 5.5 | Total (5.5) | + Opus 5 control | + Sonnet 5 control |
|---:|---:|---:|---:|---:|---:|---:|
| 6 | $75 | $38 | $9 | $122 | $94 | $38 |
| **8** | **$100** | **$50** | **$12** | **$163** | **$125** | **$50** |
| 14 (Epoch's Sonnet) | $176 | $88 | $21 | $285 | $220 | $88 |

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

**Skip the Claude 5 controls if the budget is tight.** They're the only way to tell
"5.5 differs from 5" apart from "today's load differs from August's". The floor fit
is less sensitive to load than Epoch's fits, though, and the post's own Aug 13 vs 14
check showed Opus 5's curvature held across days. Running Opus 5 at 6 blocks ($94)
is a middle ground.

## Recommended run

Preflight first (under $1): `prepare-prompts` for the three models, then a
two-request session per model at 50k to confirm each payload is accepted, the output
is exactly `OK`, the cache hits, and the stop reason is `end_turn`.

Then 8 blocks per 5.5 model, in parallel, on Epoch's grid:

```bash
PYTHONPATH=src python -m ttft_bench.cli run \
  --models anthropic_opus_5_5 \
  --lengths 50000,100000,175000,250000,375000,550000,750000,900000 \
  --repetitions 8 --shared-cache-prefix-tokens 2048 \
  --shared-cache-min-interval-seconds 4 \
  --skip-warmup --fixed-output --leading-nonce \
  --label opus-5-5-shared-prefix --network-label cloud \
  --max-cost-usd 115
```

That's about $163 for the 5.5 models, or about $338 with 8-block Claude 5 controls.
