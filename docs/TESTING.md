# Verification and limitations

CI runs a checksum-pinned official Luau 0.734 executable. Local external-tool campaigns use the separately pinned LuauProof 3.20 runtime. Neither is Roblox Studio or a formal proof.

## Reproduce

- `python3 tests/typecheck.py --analyzer /path/to/luau-analyze`: strict CLI analysis with minimal Roblox boundary stubs (Studio analyzer remains separate).
- `python3 tests/run.py --luau /path/to/luau --optimization 2`: 29 suites including the original sliding-window reference (100,000 operations) plus a 64-campaign, 512,000-operation independent list model of quotas, admission, permits, lifecycle, statistics and sweep. CI repeats O0/O1/O2.
- `python3 tests/run_adapter.py --luau /path/to/luau --optimization 2`: eight suites with service doubles and real CLI coroutines. CI repeats O0/O1/O2. These do not simulate actual Roblox network transport.
- `python3 tests/schema_fuzz.py --luau /path/to/luau --seed 38101 --out schema.json`: independent Python interpreter versus generated schemas and payloads (repeat 38102). CI uses a smaller generated campaign.
- `python3 tests/exhaustive.py --luau /path/to/luau --depth 9 --plans 32 --out exhaustive.json`: independent immutable integer-age model, representative-path concrete replay of every outgoing command of every expanded reachable state. CI uses a smaller depth-6 campaign. State equivalence omits nonbehavioral lifetime counters; scope is finite configurations, two subjects, two actions, one outstanding permit, discrete time and 13 commands.
- `python3 tests/mutation.py --luau /path/to/luau --compiler /path/to/luau-compile`: selected deliberately broken implementations, each compiled; only semantic test failures count, no syntax or timeout credit.
- `python3 tests/luauproof_attack.py --luauproof /path/to/luauproof --seed 32071 --out audit.json`: original pinned external numerical generator, exact rational binary64 oracle and bundled Luau VM (repeat 32072). Toolkit not bundled and not required by CI.
- `python3 tests/build_studio_model.py --out RemoteGuardQuickTest.rbxmx`: exact XML source equality verification; import/run in Studio separately. See [STUDIO.md](../tests/STUDIO.md).

## Local evidence

[Machine-readable evidence](../tests/evidence/) records source hashes, seeds, counts, tool hashes and scope. The two numerical campaigns check generated arithmetic, argument acceptance, UTF-8, exact represented time boundaries for three quota layers and Sweep. Counts include repeated inputs across optimization levels and arithmetic-oracle checks; not unique attacks. Negative control: reconstruct rounded comparison from `rounded_negative.diff` and repeat seed 32071. The minimized early-admission witness is start `2^-60`, window `1`, now `1`: binary64 subtraction rounds to 1 but exact represented interval is less than 1. TwoSum residual resolves the boundary without extending ordinary windows.

The two schema campaigns each compare 512 generated rules times 100 payloads at O0/O1/O2 to an independent Python interpreter. The exhaustive O2 campaign covered 376,433 reachable abstract states (including the unexpanded depth boundary), 2,674,724 concrete outgoing command replays, zero observed differences. It is not proof of arbitrary schedules or engine behavior. All 39 selected semantic mutations were detected by the regression/adapter suites; not a universal mutation score.

`benchmark.py --luau /path/to/luau --baseline /path/to/reconstructed/pre_ring.lua --out bench.json` compares five alternating trials of the candidate before/after expired-prefix optimization. Apply `pre_ring.diff` to a copy of the current core and verify the recorded source hash. The test isolates first admission after expiry of a filled 8192-entry server ring; ordinary primitive/nested requests also measured. The result is local CPU time, not network latency or Roblox throughput. Old numeric timestamps remain in allocated ring slots for reuse, bounded by quota limits. No raw payload references are retained by the rings.

## Remaining gates

Studio test has not been executed here. It must verify real engine datatypes, cancellation, Player identity and a real client-server exchange. Production needs multiple actual players, departure/latency/load checks and the application's own authoritative game logic. No guarantee against arbitrary side effects, infinite loops, detached work, network/engine deserialization attacks, cross-server abuse or production outages.
