# Studio QuickTest (real engine, one client)

1. Run `python3 tests/build_studio_model.py --out RemoteGuardQuickTest.rbxmx`, or import the supplied model.
2. Put the resulting Folder directly under ServerScriptService in a blank place.
3. Press Play (F5), not Run. No publish, DataStore, or Studio API access is required.
4. In Output, expect `[RemoteGuard] RESULT: 24/24 PASS; 0 FAIL`. If a client is missing or times out, the script prints INCOMPLETE, never a pass.

The server checks 11 direct engine cases (including actual Roblox types, exact quota boundary, authorization cancellation and `task.cancel` reaping). The LocalScript template is disabled inside the model; the server clones it into the first test Player's PlayerGui. Ten client checks invoke real RemoteFunctions and RemoteEvents. Three server checks observe handler counts, permits, errors and cancellation. The final count includes the client-reported test results; not an independent network security certification. An isolated test folder of remotes is created under ReplicatedStorage and destroyed on completion/timeout. No persistent player data is touched. The test refuses to run outside Studio.

Remaining tests after one-client smoke: multiple actual players, actual departure during a remote invocation, latency and sustained load, integration-specific game authorization, real Roblox profiler. A mock or CLI pass does not establish any of these.
