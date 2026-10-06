# Collection decisions (before inspecting fitted curvature)

## GPT-6 Sol, after three blocks

All validation checks passed. Relative IQR was below 0.17 at every length, no
observations exceeded twice the same-length median, and 850k was tightly grouped.
Decision: complete the five planned blocks without changing the cache key/prefix.
All five blocks subsequently completed. No observations excluded by latency.

## GPT-6.1 Sol, after three blocks

The automatic noise checkpoint paused collection. Relative IQR was 0.4995 at
275k and 0.5078 at 850k; the other four cells were below 0.19. The large ranges
were driven by a single slow value at each length:

- 275k: 10.373045207, 5.204870787, 5.173434950 seconds.
- 850k: 14.367235520, 30.820969713, 16.200910575 seconds.

No request exceeded twice its own length's current median. All cache hits,
zero-reasoning, OK-output, model, and tier checks passed. The latest block was
not broadly slower. Decision: permit one further **already-budgeted** block,
through block four, to distinguish recurrent broad degradation from isolated
delays. This is a discretionary review of the predefined warning, not a claim
that it passed or that slow observations should be discarded. No regression
results had been computed or consulted at this point. Preserve the same session
and cache key, and retain all data. Ledger including the earlier pilot: $61.6358585.

## GPT-6.1 Sol, after four blocks

The aggregate warning remained (250k relative IQR 0.2408, 275k 0.2723,
850k 0.3323). The fourth block itself did not repeat the large spikes:
850k 14.814622995 s; 275k 4.815324106 s. All validation checks passed and
there were still no observations above twice their current same-length median.
Decision: finish the fifth originally planned block, then stop regardless of
its significance or dispersion. This does not classify the session as clean;
the noisier observations remain in all statistical analyses. No fitted curvature
or significance results were inspected when making this decision.
Ledger including the earlier pilot: $69.2511254. Expected final total about $76.87.
