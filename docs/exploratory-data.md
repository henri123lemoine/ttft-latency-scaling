# Exploratory TTFT session archive

This directory releases additional direct-API observations collected while the
benchmark protocol and sampling design were being developed. It is an evidence
archive, not an extension of the confirmatory dataset. None of these sessions is
silently pooled into the authoritative four-model fits, confidence intervals,
tables, or Figures 1--4.

## Scope

The archive contains 22 sessions, 303 valid measured requests, and 15 retained
cache-prime or cache-setup requests for the same four models as the original
comparison. Every file uses the pinned Project Gutenberg corpus with SHA-256
`075768889cfef63bcbb967fa0204b6048201fdfe896124915f75e8dadc8b9e75`.

| Model | Sessions | Measured requests | Observed nominal targets |
|---|---:|---:|---|
| GPT-5.6 Terra | 3 | 40 | 50k, 250k, 375k, 750k |
| GPT-5.6 Sol | 8 | 96 | 50k--850k; see manifest for the irregular grids |
| Claude Sonnet 5 | 4 | 73 | 50k--900k; see manifest for the session-specific grids |
| Claude Opus 5 | 7 | 94 | 50k--900k; see manifest for the session-specific grids |

The observed requests comprise 90 uncached measurements, 183 measurements with
a short shared cached prefix, and 30 older cache-hit measurements with a large
cached prefix and short new suffix. These protocols answer different questions
and should not be treated as exchangeable observations by default.

## Session classifications

The reviewed registry is [`config/exploratory_sessions.json`](../config/exploratory_sessions.json),
and the generated, human-readable index is
[`data/exploratory_session_manifest.csv`](../data/exploratory_session_manifest.csv).
Each session is assigned one of three provenance statuses:

- `complete_balanced`: 14 schema-v2 sessions containing the planned number of
  valid observations and a complete `session_end` record (237 measurements).
- `legacy_balanced`: five older-schema sessions whose measured counts match the
  header or reviewed per-length plan, but whose logger did not yet emit a
  `session_end` record (58 measurements). "Balanced" here means complete versus
  that recorded/reviewed plan; one resumed session deliberately had four rather
  than five observations at its longest length.
- `partial`: three interrupted pilots retained without inventing missing
  observations or completion records (8 measurements).

The labels describe record completeness, not statistical quality. Several
complete sessions are preflights or sparse checkpoints and cannot independently
identify a context-scaling curve.

## Protocol evolution and analytical use

Collection was adaptive rather than preregistered. Context grids, cache modes,
output instructions, and repetitions changed in response to observed noise and
cost. The sessions include cache-disabled smoke tests, large-prefix cache-hit
tests, short-suffix tests, shared-prefix affinity pilots, uncached controls,
fixed-output follow-ups, and full multi-block runs. Consequently, a regression
over all 303 observations would conflate session, protocol, time, and context
effects.

The JSONL records are the authoritative source. Early legacy records predate
fields added later in schema version 2, including explicit request start/end
timestamps and, in some cases, reasoning, output-compliance, service-tier, and
prompt-construction fields. A blank field in the flat CSV means the value was
not recorded; it must not be interpreted as zero or `false`.

The release makes no new model-scaling claim. Researchers may define a
secondary analysis, but should preserve session boundaries, state the inclusion
rule in advance, distinguish cache modes, and perform sensitivity checks rather
than selecting sessions or observations based on favorable fitted curvature.

## Files and deterministic export

- `data/raw/exploratory/*.jsonl`: sanitized records in original file order.
- `data/schedules/exploratory/*.csv`: literal chronological order of measured
  requests. Blocks are one-based here and correspond to zero-based `repetition`
  values in JSONL.
- `outputs/exploratory/request_observations.csv`: one row per valid measured
  request, with nanosecond timing fields converted to seconds.
- `outputs/exploratory/session_summary.csv`: simple descriptive session totals
  and medians; no fitted coefficients.
- `data/exploratory_session_manifest.csv`: provenance, protocol role, exact
  per-length counts, schema availability, and raw/schedule paths.

Regenerate and verify all derived CSVs offline:

```bash
make exploratory
```

`scripts/export_exploratory_data.py` checks the exact session allowlist, corpus
hash, provider/model/mode identity, per-length counts, validity and HTTP status,
timing inequalities, token accounting, hash formats, completion status, and the
absence of operational fields and common credential patterns. Its `--check`
mode also requires every committed derived CSV to match a fresh deterministic
render byte for byte.

Release maintainers with the private source directory can reproduce the
sanitization step explicitly:

```bash
python3 scripts/prepare_release_data.py /path/to/private/results --exploratory-all
python3 scripts/export_exploratory_data.py
```

The first command only accepts session IDs in the reviewed public configuration.
It never discovers or releases arbitrary source logs.

## Redactions and preserved evidence

The sanitizer removes host, network/location label, platform, request/response
identifiers, rate-limit values, and operator cost-limit settings. It retains all
timing and provider token-accounting fields used for latency analysis, as well
as timestamps, request order, model identifiers, validity flags, estimated
costs, hashes, and output previews. The derived request CSV omits previews and
cache-buster strings to keep it narrowly numerical; they remain in JSONL.

See [`data/REDACTION.md`](../data/REDACTION.md) for the full policy. The public
archive contains no credentials or authorization headers.

## Important limitations

- The public API does not expose provider queueing, batching, routing, worker or
  accelerator assignment, cache placement, datacenter, or concurrent load.
- TTFT therefore measures effective public-API latency, not isolated model FLOPs,
  kernel duration, or a fixed hardware path.
- Sessions occurred at different wall-clock times and sometimes used different
  cache and instruction protocols. A session effect cannot generally recover a
  controlled comparison when protocol and time both changed.
- Legacy records do not preserve every newer protocol field. Missing values are
  unresolved, not reconstructed from later code.
- Historical provider state cannot be replayed, even when the prompt corpus and
  request schedule are available.

The primary data selection remains exactly the one documented in
[`docs/collection-methodology.md`](collection-methodology.md). This archive does
not alter that selection or any headline numerical result.
