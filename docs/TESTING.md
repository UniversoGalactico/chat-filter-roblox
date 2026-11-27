# Verification and limitations

CI runs a checksum-pinned official Luau 0.734 executable. Local external-tool campaigns use the separately pinned LuauProof 3.20 runtime. Neither is Roblox Studio or a formal proof.

## Reproduce

- `python3 tests/typecheck.py --analyzer /path/to/luau-analyze`: strict CLI analysis with minimal Roblox boundary stubs (Studio analyzer remains separate).
- `python3 tests/run.py --luau /path/to/luau --optimization 2`: 29 suites including the original sliding-window reference (100,000 operations) plus a 64-campaign, 512,000-operation independent list model of quotas, admission, permits, lifecycle, statistics and sweep. Add `--large` for a million-operation independent list-model comparison of large, wrapped timestamp rings, with positive coverage requirements for each quota denial. CI repeats O0/O1/O2 with the large model.
- `python3 tests/run_adapter.py --luau /path/to/luau --optimization 2`: eight suites with service doubles and real CLI coroutines. Add `--model` for 160,000 operations across sixteen campaigns interleaving handler completion, denial, departure, cancellation and reaping. CI repeats O0/O1/O2 with this model. These do not simulate actual Roblox network transport.
- `python3 tests/schema_fuzz.py --luau /path/to/luau --seed 38101 --out schema.json`: independent Python interpreter versus generated schemas and payloads (repeat 38102). CI uses a smaller generated campaign.
- `python3 tests/exhaustive.py --luau /path/to/luau --depth 9 --plans 32 --out exhaustive.json`: independent immutable integer-age model, representative-path concrete replay of every outgoing command of every expanded reachable state. CI uses a smaller depth-6 campaign. State equivalence omits nonbehavioral lifetime counters; scope is finite configurations, two subjects, two actions, one outstanding permit, discrete time and 13 commands.
- `python3 tests/mutation.py --luau /path/to/luau --compiler /path/to/luau-compile`: selected deliberately broken implementations, each compiled; only semantic test failures count, no syntax or timeout credit.
- `python3 tests/luauproof_attack.py --luauproof /path/to/luauproof --seed 32071 --out audit.json`: original pinned external numerical generator, exact rational binary64 oracle and bundled Luau VM (repeat 32072). Toolkit not bundled and not required by CI.
- `python3 tests/build_studio_model.py --out RemoteGuardQuickTest.rbxmx`: exact XML source equality verification; import/run in Studio separately. See [STUDIO.md](../tests/STUDIO.md).

- `python3 tests/extended_models.py --luau /path/to/luau --out extended.json`: capture all six extended model runs and source hashes.
- `python3 tests/resource_audit.py --luau /path/to/luau --compiler /path/to/luau-compile --out resource.json`: inspect internal invariants through a temporary instrumented copy, including 12,800 retirement checks, 660 capacity checks and five semantic negative controls. No audit hooks are shipped in the runtime.

- `python3 tests/verify_evidence.py`: check recorded source hashes, reconstruct baseline and negative-control sources, and verify recorded totals; this checks consistency, not authenticity.

## Local evidence

[Machine-readable evidence](../tests/evidence/) records source hashes, seeds, counts, tool hashes and scope. The two numerical campaigns check generated arithmetic, argument acceptance, UTF-8, exact represented time boundaries for three quota layers and Sweep. Counts include repeated inputs across optimization levels and arithmetic-oracle checks; not unique attacks. Negative control: reconstruct rounded comparison from `rounded_negative.diff` and repeat seed 32071. The minimized early-admission witness is start `2^-60`, window `1`, now `1`: binary64 subtraction rounds to 1 but exact represented interval is less than 1. TwoSum residual resolves the boundary without extending ordinary windows.

The two numerical campaigns record 982,275 counted checks with zero discrepancies on the candidate. The deliberately rounded comparison negative control produces 41,922 failed checks in the first seed.

The two schema campaigns each compare 512 generated rules times 100 payloads at O0/O1/O2 to an independent Python interpreter. The exhaustive O2 campaign covered 376,433 reachable abstract states (including the unexpanded depth boundary), 2,674,724 concrete outgoing command replays, zero observed differences. It is not proof of arbitrary schedules or engine behavior. All 39 selected semantic mutations were detected by the regression/adapter suites; not a universal mutation score.

`benchmark.py --luau /path/to/luau --baseline /path/to/reconstructed/pre_ring.lua --out bench.json` compares five alternating trials of the candidate before/after expired-prefix and lazy cycle-map allocation optimizations. Apply `pre_ring.diff` to a copy of the current core and verify the recorded source hash. The test isolates first admission after expiry of a filled 8192-entry server ring; ordinary primitive/nested requests also measured. The comparison includes both changes, so ordinary request timings cannot isolate the effect of the ring alone. The result is local CPU time, not network latency or Roblox throughput. Old numeric timestamps remain in allocated ring slots for reuse, bounded by quota limits. No raw payload references are retained by the rings.

The extended models exercise 4,836,000 core operations and 480,000 adapter lifecycle operations across O0/O1/O2 (same deterministic seeds across modes). These include the original 100,000-operation and 512,000-operation models, plus the additional million-operation ring model per mode. The resource campaign additionally detects all five selected private-invariant negative controls; these are separate from the 39 public-behavior mutants.

See [design audit](AUDIT.md) for reasoning and residual risks.

## Remaining gates

Studio test has not been executed here. It must verify real engine datatypes, cancellation, Player identity and a real client-server exchange. Production needs multiple actual players, departure/latency/load checks and the application's own authoritative game logic. No guarantee against arbitrary side effects, infinite loops, detached work, network/engine deserialization attacks, cross-server abuse or production outages.
