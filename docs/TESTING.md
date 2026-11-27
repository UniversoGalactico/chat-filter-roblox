# Verification

Run `python3 tests/run.py --luau /path/to/luau --optimization 2`. CI repeats O0/O1/O2 and runs strict CLI analysis. Includes a 100,000-operation independent sliding-window model per optimization, validation, lifecycle and callback tests. This is a new candidate: Studio integration, real multiplayer requests, scheduler cancellation, external numerical fuzzing and load measurements are not yet established. No production certification.
