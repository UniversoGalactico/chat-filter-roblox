# Verification

From root: `lua5.4 tests/regression.lua`, `lua5.4 tests/policy_examples.lua`, `lua5.4 tests/adapter.lua`, `python3 tests/mutation.py`, `python3 tests/studio/verify_model.py`. CI runs pure tests with checksum-pinned Luau 0.734, compiles the shipped sources and checks synthetic benchmark checksums. Regression includes 177,147 bounded exhaustive traces, scan-based admission, malformed input, phrase and edit-distance oracles. Selected mutations are not complete fault coverage. Model XML verification checks source equality, not Studio loading.

[Studio quick test](studio/README.md) remains manual. Native permissions, actual delivery and integrated chat compatibility must be observed. Never install the test in production.
