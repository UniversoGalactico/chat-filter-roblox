# Manual Roblox Studio smoke test (not run in CI)

This script is an optional integration aid for a **disposable private Studio place**, not part of production installation. It never logs or reads message text. Do not test with unsuspecting players. It does not prove that Roblox permissions or actual message delivery work.

1. Install the v2 server modules, remove all v1 chat transport/UI scripts, and keep native TextChatService enabled. Leave ChatConfiguration.Mode at "native" so no automatic hooks are installed. Set ScopeAttributes = {ChatFilterSmoke = "ChatFilterSmokeGroup"} in the test configuration.
2. Put Smoke.server.lua in ServerScriptService as a Script. Set its Boolean attribute RunChatFilterSmoke to true in Studio. The script will exit in any non-Studio server or without the explicit flag.
3. Set TextChatService.PlatformIntegratedChat to Enabled in Studio. Start a multi-client session with three test players. The script creates only ChatFilterSmoke, not RBXGeneral or any reserved channel, and attempts native AddUserAsync. If Roblox denies membership or the local test accounts do not have chat, stop: do not circumvent the restriction.
4. Use the native chat window (select the test channel) or a native TextChannelWindow targeted to ChatFilterSmoke. Send a short benign message manually. The first two joined test players receive group A and the third group B; actual native permissions still apply. Check in client windows whether the same-group peer sees the message and the other group does not. The sender can see a local echo even if delivery is denied.
5. In server Studio Explorer, change the third player's ChatFilterSmokeGroup to A; send another benign message after the quota interval. Then remove the attribute and repeat. Observe recipient behavior and check native permissions separately.
6. Change the script's SnapshotRequest attribute to a new value to print only fixed aggregate counts. Allow is a local predicate result, **not proof of receipt**. If all counters remain zero despite a valid send, the callback may not be invoked in that rollout configuration. Do not ship context mode until actual callback and delivery behavior are established.
7. Remove the test script or stop the session. It disconnects its signals, stops the policy and destroys its own channel on destruction. Never distribute the smoke script with production modules.

Record the Studio version, PlatformIntegratedChat setting, number of test clients, expected and observed client delivery, and aggregate counters. Do not include chat logs, player IDs, or real conversations.

The public field extension is separate and requires a private published test universe with real MemoryStore/TextService access, as described in the main verification checklist.
