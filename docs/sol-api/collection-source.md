# Historical collection source excerpts

These excerpts are copied from the implementation used on October 6. They are
provided as an audit record, not an executable runner. Personal credential-loader
paths and local output-root configuration are intentionally omitted. Credentials
were sourced outside the project and never included in request logs.

Recorded source SHA-256 values are in both session manifests. The public collector
has portability/schedule support differences and defaults to reasoning `none`;
it should not be assumed byte-identical to the historical core. The functions
below show the relevant per-model override, payload/timing, and collection logic.
No copied excerpt embeds a key or private account identifier.

## Model-specific reasoning and output cap

```python
def benchmark_max_output_tokens(model: dict[str, Any], benchmark: dict[str, Any]) -> int:
    """Return the collection output cap, allowing a model-specific override."""
    return int(model.get("benchmark_max_output_tokens", benchmark["max_output_tokens"]))


def reasoning_effort(model: dict[str, Any]) -> str:
    """Preserve the historical `none` default while supporting reasoning-only models."""
    return str(model.get("reasoning_effort", "none"))
```

## Staged invocation and model configuration

```python
    model = dict(provider="openai", model=args.model,
                 reasoning_effort="none" if args.model == "gpt-6-sol" else "low",
                 input_usd_per_mtok=2, cache_read_usd_per_mtok=.2 if args.model == "gpt-6-sol" else .1,
                 cache_write_usd_per_mtok=2.5, output_usd_per_mtok=10,
                 long_context_threshold=272000, long_input_multiplier=2,
                 long_output_multiplier=1.5)
```

## Request pacing, accounting and verification

```python
        def call(row, kind, block):
            nonlocal last_start
            time.sleep(max(0, 4-(time.monotonic()-last_start)))
            total_bound = row["counted"] + 128
            multiplier = 2 if total_bound > 272000 else 1
            # Reserve as if ALL input were cache-written; actual protocol only writes ~2k.
            reserve = total_bound * 2.5 * multiplier / 1e6 + 32 * 15 / 1e6
            if ledger(records) + reserve > CAP:
                raise RuntimeError("Budget cap reached before request")
            attempt = sum(r["type"] == "request_intent" for r in records) + 1
            save(dict(type="request_intent", attempt=attempt, model=args.model,
                      session=manifest["session"], kind=kind, block=block,
                      target_tokens=row["target"], reserved_usd=reserve))
            last_start = time.monotonic()
            r = cli.stream_one(client, model, BENCHMARK, corpus, row, key,
                               fixed_output=True, leading_nonce=True)
            flags = []
            if r["error"]: flags.append("provider_or_transport_error")
            if r["reasoning_tokens"] != 0: flags.append("reasoning_not_zero")
            if r["ttft_ns"] is None: flags.append("no_text_delta")
            if r["returned_model"] != args.model: flags.append("model_mismatch")
            if r["returned_service_tier"] != "default": flags.append("service_tier_mismatch")
            if r["output_preview"].strip() != "OK": flags.append("not_OK")
            if kind == "measured":
                try:
                    cli.validate_shared_cache_hit(model, r, 2048, expected_prefix, row["counted"])
                except RuntimeError:
                    flags.append("cache_or_token_mismatch")
                if r["cache_read_tokens"] != expected_prefix: flags.append("prefix_count_changed")
            else:
                try:
                    cli.validate_shared_cache_setup(model, r, 2048)
                except RuntimeError:
                    flags.append("cache_setup_mismatch")
            cost = cli.request_cost(model, r)
            fields = ("request_started_at", "request_completed_at", "headers_ns", "first_event_ns",
                      "first_content_ns", "ttft_ns", "total_ns", "status_code", "request_bytes",
                      "returned_model", "returned_service_tier", "output_preview", "total_input_tokens",
                      "new_input_tokens", "cache_read_tokens", "cache_write_tokens", "output_tokens", "reasoning_tokens")
            record = {k: r.get(k) for k in fields}
            record.update(type="sample", attempt=attempt, model=args.model, session=manifest["session"],
                          kind=kind, block=block, target_tokens=row["target"], prepared_tokens=row["counted"],
                          reasoning_effort=model["reasoning_effort"], max_output_tokens=32,
                          stable_prefix_sha256=row["stable_prefix_sha256"], prompt_sha256=row["prompt_sha256"],
                          valid=not flags, flags=flags, estimated_cost_usd=cost,
                          accounted_cost_usd=cost if cost is not None else reserve)
            save(record)
            print(json.dumps(dict(model=args.model, kind=kind, block=block, target=row["target"],
                                  ttft_s=r["ttft_ns"]/1e9 if r["ttft_ns"] else None,
                                  read=r["cache_read_tokens"], write=r["cache_write_tokens"],
                                  reasoning=r["reasoning_tokens"], valid=not flags, flags=flags,
                                  cumulative_with_pilot_usd=round(ledger(records),6))), flush=True)
            if flags:
                raise RuntimeError("Stopped on validation failure; no automatic retry")
            return r
```

## Priming, continuity and checkpoint review

```python
        previous = [r for r in records if r["type"] == "sample" and r["model"] == args.model]
        prime = dict(rows[LENGTHS[0]])
        prime.update(end=prime["split"], target=3000, counted=3000)
        if not previous:
            setup = call(prime, "cache_setup", -1)
            expected_prefix = cli.validate_shared_cache_setup(model, setup, 2048)
        else:
            expected_prefix = previous[0]["cache_read_tokens"] + previous[0]["cache_write_tokens"]
            elapsed = (datetime.now(timezone.utc)-datetime.fromisoformat(previous[-1]["request_completed_at"])).total_seconds()
            if elapsed > 600:
                if elapsed > 1500:
                    raise RuntimeError("Cache continuity uncertain after >25min gap: stop for review")
                call(prime, "keepalive", -1)
        existing = {(r["block"], r["target_tokens"]) for r in previous if r["kind"] == "measured"}
        for block in range(args.through):
            if all((block,n) in existing for n in LENGTHS):
                continue
            for n in manifest["schedules"][block]:
                if (block,n) not in existing:
                    call(rows[n], "measured", block)
            samples = [r for r in records if r["type"] == "sample" and r["model"] == args.model and r["kind"] == "measured"]
            stats = dispersion(samples)
            warning = block >= 2 and (sum(s["relative_IQR"] > .20 for s in stats) >= 2 or
                                      sum(s["over_twice_median"] for s in stats) >= 2)
            save(dict(type="checkpoint", model=args.model, completed_blocks=block+1,
                      dispersion=stats, noise_warning=warning, cumulative_with_pilot_usd=ledger(records)))
            print("CHECKPOINT " + json.dumps(records[-1]), flush=True)
            if warning:
                print("NOISE REVIEW REQUIRED; retaining all observations", flush=True)
                break
        print("STAGED RUN FINISHED", flush=True)


if __name__ == "__main__":
    main()
```

The unchanged prompt splitting, explicit-cache content blocks, provider usage
parsing and timing logic are in `src/ttft_bench/cli.py`. The historical main
streaming payload selected the model-specific reasoning effort shown above;
benchmark output cap=32 and service tier=default. No temperature/top-p or tools
were supplied. The public core's original fixed `none` setting is not an accurate
configuration for 6.1; the archived manifests and this override are authoritative.

### Timing and prompt implementation verification

Provider payload construction and UTF-8 serialization precede the monotonic
start immediately before sending the prepared HTTP request. The first nonempty
text delta determines `ttft_ns`; `first_content_ns` also includes content events
that are not output text and is not substituted for TTFT in this analysis.

The nonce is formed using `" ".join(str(byte % 10) for byte in uuid.uuid4().bytes)`.
It precedes the long shared corpus continuation, after the cached prefix. The
manifests retain fixed prefix/sizing-prompt hashes; fresh nonce bytes themselves
were not logged, so exact byte-for-byte replay of a measured request is not claimed.
