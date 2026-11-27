# Verification

From root: `lua5.4 tests/regression.lua`, `lua5.4 tests/policy_examples.lua`, `lua5.4 tests/adapter.lua`, `python3 tests/mutation.py`, `python3 tests/studio/verify_model.py`. CI runs pure tests with checksum-pinned Luau 0.734, compiles the shipped sources and checks synthetic benchmark checksums. Regression includes 177,147 bounded exhaustive traces, scan-based admission, malformed input, phrase and edit-distance oracles. Selected mutations are not complete fault coverage. Model XML verification checks source equality, not Studio loading.

[Studio quick test](studio/README.md) remains manual. Native permissions, actual delivery and integrated chat compatibility must be observed. Never install the test in production.

## Rejected optimization
A recent-message shortcut was tested in commit bdfad80094b72718e8feb0b02acc17a992c3c8da. Against the previous Lite gate, median ratios were 0.966 (unique), 0.967 (saturated), 1.047 (fanout), with matching checksums. The small fanout gain did not justify extra state, comparisons and potentially different equality semantics for metatable-bearing table keys. It was removed. The new interleaving tests remain. These timings are synthetic and may vary.
