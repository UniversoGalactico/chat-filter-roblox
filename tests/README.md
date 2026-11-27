# Verification

From root: `lua5.4 tests/regression.lua`, `lua5.4 tests/policy_examples.lua`, `lua5.4 tests/adapter.lua`, `python3 tests/mutation.py`, `python3 tests/studio/verify_model.py`. CI runs pure tests with checksum-pinned Luau 0.734, compiles the shipped sources and checks synthetic benchmark checksums. Regression includes 177,147 bounded exhaustive traces, scan-based admission, malformed input, phrase and edit-distance oracles. Selected mutations are not complete fault coverage. Model XML verification checks source equality, not Studio loading.

[Studio quick test](studio/README.md) remains manual. Native permissions, actual delivery and integrated chat compatibility must be observed. Never install the test in production.

## Rejected optimization
A recent-message shortcut was tested in commit bdfad80094b72718e8feb0b02acc17a992c3c8da. Against the previous Lite gate, median ratios were 0.966 (unique), 0.967 (saturated), 1.047 (fanout), with matching checksums. The small fanout gain did not justify extra state, comparisons and potentially different equality semantics for metatable-bearing table keys. It was removed. The new interleaving tests remain. These timings are synthetic and may vary.

The adapter additionally checks all 1,024 combinations of ten sender/recipient/channel/context preconditions. `tests/native_adapter.py` executes the same mock suites in Luau CLI at O0/O1/O2 through a bounded in-memory source shim. This is real Luau execution, not Roblox engine validation.

The deterministic gate campaign uses a separate list-based oracle, two independent key sets and an exact binary64 time shift of 2^35 seconds. It mixes varied limits, TTLs, capacities, cache pressure, clock regression, lifecycle resets and invalid noise injected into only one gate. Both gates must reproduce the oracle decision and reason. Every observed failure includes a scenario/step for replay. Run `lua5.4 tests/gate_campaign.lua` or `luau tests/gate_campaign.lua`.

`tests/internal_invariants.py PATH_TO_VM` instruments a temporary copy (not the shipped module) and checks ring cardinality, FIFO expiry, bidirectional map identity, bucket counts, window bounds and cleanup after each operation. It also requires two deliberately corrupted implementations to be rejected by the intended invariant. Run with `--full` for the full campaign. This is white-box test evidence, not an unbounded proof.
