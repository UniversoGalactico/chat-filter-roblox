# Quick Studio test (not yet run on Roblox)

1. Download [ChatFilterTest.rbxmx](ChatFilterTest.rbxmx). In a blank private place, insert it into ServerScriptService (Explorer > right click > Insert from File). Alternatively paste the three core modules and Smoke.server.lua as sibling scripts.
2. Press F5 and inspect server Output for PASS: 7 local checks. This does not verify Roblox chat delivery.
3. For delivery, stop and enable TextChatService > ChannelTabsConfiguration > Enabled. Start Test > Server & Clients with 2 clients. Select ChatFilterTest in native chat and send a benign test message from A. B should not receive it. Set the second player's ChatFilterTestGroup attribute to A in the server Explorer, then send another message; B may receive it subject to native permissions. Change ShowCounts on Smoke to see fixed aggregate counters.
4. If native membership, tab or callbacks are unavailable, mark integration unverified. In platform-integrated chat, use the official TextChannelWindow targeted at the test channel if necessary (see Roblox documentation). Never circumvent permissions.

Stop the session and remove the test model. It never reads or logs conversation text and exits outside Studio. Do not ship it.
