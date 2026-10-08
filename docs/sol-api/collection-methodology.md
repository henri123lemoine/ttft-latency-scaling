# October 6, 2026: direct-API Sol shared-prefix replication

This experiment is separate from all Codex/subscription measurements and from the
published historical fits. The original four-model headline fits remain unchanged.

## Design and authorization

- GPT-6 Sol (`gpt-6-sol`) is collected first; GPT-6.1 Sol (`gpt-6.1-sol`) second.
- Independent chronological sessions, not paired or interleaved model requests.
- Five planned blocks per model; six sequential requests per block, one each at
  50k, 175k, 250k, 275k, 550k, and 850k nominal total input tokens.
- These are the six lengths in the finalized GPT-5.6 Sol session. Length order is
  shuffled independently in each block with fixed seeds 20261006 / 20261007;
  exact orders are stored in the two model manifests before generation begins.
- Minimum four seconds between request starts, never concurrent requests. A
  persistent HTTP client is used within each staged invocation. Resuming after a
  checkpoint creates a new client and uses a token-count request to warm the
  connection; it does not introduce an inference observation into the fit.
- The combined ceiling is USD 80. The ledger conservatively includes the earlier
  USD 0.6939188 GPT-6.1 reasoning pilot, which is excluded from analysis.
- Checkpoints after three blocks and subsequent completed blocks inspect
  dispersion and protocol correctness, not curvature significance. Operational
  warning: IQR/median >20% at two or more lengths, or at least two observations
  above twice their own length's median. IQR uses linear interpolation (R type 7).
- A warning pauses for review, not deletion of observations. Five blocks is the
  maximum in this budgeted collector. No automatic retries.

## Prompt and cache protocol

The collector calls the existing `ttft_bench.cli.shared_prefix_rows`,
`stream_one`, and cache-validation functions without modifying their source.
The corpus is the same `data/corpus/combined.txt` used historically. Its SHA-256,
the core collector SHA-256, and the wrapper SHA-256 are recorded in each manifest.

The request is a user message with two text content blocks:

1. Fixed `REFERENCE TEXT:\n` plus the beginning of the corpus, with an explicit
   cache breakpoint. The split is sized to at least 2,048 provider tokens.
2. `Benchmark nonce: ` followed by sixteen space-separated digits, a newline,
   the remaining corpus through the target-specific endpoint, and the final task:
   `Do not think or analyze. Respond immediately with exactly one word: OK`.

Each nonce is generated from `[byte % 10 for byte in uuid.uuid4().bytes]`.
The stable prefix is identical across lengths within a session, and the corpus
continuation is fixed for each length except for the fresh preceding nonce.
Nominal lengths include the prefix. Provider token-count binary search sizes the
prompts using the historical summarization instruction; generation substitutes
the fixed-OK instruction, so realized totals may differ slightly from nominal.
Exact reported input/cache/output counts are saved for every request.

Requests use explicit-only caching. Only the small prefix has a breakpoint:
the long suffix is neither read from nor written to the prompt cache. A single
cache key is retained within each model's session. Its value is reproducible from
the session identifier (`ttft:shared:` plus session). There is no assumption that
cache state transfers between models. Default TTL is 30 minutes, refreshed by
reuse according to the provider documentation.

One small prefix-only setup request with the fixed-OK task primes each session;
it is excluded from fits. This setup includes an explicit OK task rather than
the empty suffix override in the historical full-run CLI. Measured payload
construction is unchanged. The short earlier reasoning pilot is not reused as
this session's cache setup or measurement data.

Before any continuation after a checkpoint, a >10-minute inactive gap triggers
a logged prefix-only keepalive, excluded from fitting. A >25-minute gap stops
for review instead. A measured cache miss, unexpected cache write, or changed
prefix count stops collection; it is not silently accepted as a valid hit.
No keepalive is required while regular measurements maintain cache reuse.

## Generation and timing

- Direct `https://api.openai.com/v1/responses`, Standard (`service_tier=default`).
- `stream=true`, `store=false`, maximum 32 output tokens, no tools, no supplied
  temperature/top-p. GPT-6 Sol uses reasoning `none`, as GPT-5.6 Sol did.
- GPT-6.1 Sol requires reasoning `low` because `none` is unsupported. This is a
  documented protocol difference, not an assertion that the settings are equal.
- Require zero **reported** reasoning tokens, the requested returned model/tier,
  and exact visible output `OK`. Zero reported tokens does not establish absence
  of all unobserved internal processing. Failed validation pauses collection.
- Payload serialization and HTTP request construction occur before the clock
  starts. The monotonic clock starts immediately before `client.send` and TTFT
  ends on receipt/parsing of the first nonempty `response.output_text.delta`.
- Record UTC request start/end, headers/first-event/first-content timestamps,
  TTFT, total duration, token usage, and estimated cost. This is client-observed
  API latency, including network/queueing/serving effects, not kernel runtime.

## Budget, recovery, and privacy

Every attempt has a fsynced pre-request reservation and a fsynced result. A process
lock prevents overlapping collectors. Missing usage or an unresolved attempt is
charged its conservative reserved amount in the local ledger. Each reservation
allows the whole input to incur cache-write pricing, even though the protocol
only intends a short prefix write. Known usage replaces the reservation with
the token-based estimate. An unresolved attempt blocks automatic resumption.

Standard rates: both models USD 2/M ordinary input, USD 2.50/M cache writes,
USD 10/M output. Cache reads: GPT-6 Sol USD 0.20/M; GPT-6.1 Sol USD 0.10/M.
Above 272k input tokens, input/cache rates double and output rates multiply by
1.5 for the full request. Costs are estimates, not an account invoice.

Credentials are loaded from the external key file and never written to outputs.
The result schema omits raw provider error bodies, authorization headers,
provider response/request IDs, and account-identifying rate-limit headers.

## Offline analysis

`analysis/sol_api.R` loads only the historical fitting function
definitions from `analysis/sol_api_student_helpers.R` and
`analysis/sol_api_asymmetric_helpers.R`. No historical script's top-level
collection or dataset analysis is executed.

Each model/session is fitted independently. Retain all protocol-valid requests;
no trimming by latency. Fit complete six-length blocks; preserve partial/invalid
attempts in raw logs. x is actual total input tokens / 1e6 and y is TTFT seconds.
Student-t df=4, unconstrained quadratic coefficient, sum-to-zero block effects;
compare linear and quadratic versions. Report the approximate conditional
chi-square(1) LR p-value with its finite-sample/adaptive-design caveats.

Huber curvature intervals use 5,000 whole-block resamples with duplicated sampled
blocks relabeled independently; these are **Huber**, not Student-t, intervals.
Frontier and spike fits use the historical nonnegative curvature constraint and
robust negative-residual sigma anchor, with 200 whole-block bootstrap replicates
per family and sigma re-estimated inside each replicate. Include 0.5x/2x anchor
sensitivity. Five independent blocks give limited bootstrap precision; these are
not powered architecture-identification experiments.

Model sessions occur in different time windows; differences may reflect load or
serving conditions in addition to model differences. A shared prefix establishes
cache reuse, not identical workers/hardware. No inference about model popularity,
deployment utilization, or hardware identity is directly observed here.

Sources checked October 6, 2026:

- https://developers.openai.com/api/docs/models/gpt-6-sol
- https://developers.openai.com/api/docs/models/gpt-6.1-sol
- https://developers.openai.com/api/docs/guides/prompt-caching
