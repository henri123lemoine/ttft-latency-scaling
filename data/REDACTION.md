# Public-log redactions

The checked-in JSONL files preserve every field used by the analysis, including
wall-clock timestamps, monotonic timing components, token usage, request order,
cache accounting, model identifiers, validity flags, and estimated costs.

The release preparation script removes these operational fields:

- `hostname`
- `request_id`
- `response_id`
- `retry_after`
- `ratelimit_reset_tokens`
- `ratelimit_remaining_tokens`

They are not inputs to any reported calculation. Session IDs and hashed prompt
and cache identities are retained. The final four-model logs retain the general
platform string and stated network location because they document the
experimental setup without revealing API credentials. API keys were loaded from
`.env` and were never written to the logs.

The original private logs remain outside this repository.

## September 2026 Astra API supplement

The two `data/raw/astra-api/` logs apply the same redactions. They additionally
omit `network_label`, `platform`, and the operator's `hard_cost_limit_usd` from
the session header. Measured request bodies and authorization headers were not
logged; the logs contain prompt/cache hashes, not API credentials. Timestamps,
model/generation settings, all completed measurements, and both cache-setup
records are retained. The interrupted session is not given an invented
`session_end` record. Only direct API sessions are included.

## Exploratory-session archive

The 22 files in `data/raw/exploratory/` apply the base redactions and also omit
`network_label`, `platform`, and `hard_cost_limit_usd`, where present. The flat
CSV export intentionally excludes free-text output previews and cache-buster
values, although those remain in the sanitized JSONL for protocol audit. The
archive contains direct API observations only. It does not contain API keys,
authorization headers, full serialized request bodies, subscription-account
records, or private website source.

## October 6 Sol API supplement

`raw/sol-api/20261006-sol-shared.jsonl` was recorded with an allowlisted result
schema that omits provider request/response IDs, raw error bodies, authorization
headers, and account rate-limit headers. No additional raw-log redaction was
required. It includes all 60 measured requests, both prefix-setup requests, cost
reservations, session manifests, and checkpoint dispersion summaries. The prior
reasoning pilot contributes only a historical ledger amount, not observations.
No subscription account state or private website assets are included. Credential
loader paths are omitted from the historical source excerpts. Manifest source
hashes identify the original implementation, not the portable release files.
