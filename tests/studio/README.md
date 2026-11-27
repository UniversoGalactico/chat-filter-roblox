# Quick Studio test (not yet run on Roblox)

1. Download [ChatFilterTest.rbxmx](ChatFilterTest.rbxmx). In a blank private place, insert it into ServerScriptService (Explorer > right click > Insert from File). Alternatively paste the three core modules and Smoke.server.lua as sibling scripts.
2. Press F5 and inspect server Output for PASS: 18 local checks. This does not verify Roblox chat delivery.
3. For delivery, stop and enable TextChatService > ChannelTabsConfiguration > Enabled. Start Test > Server & Clients with 2 clients. Select ChatFilterTest in native chat and send a benign test message from A. B should not receive it. Set the second player's ChatFilterTestGroup attribute to A in the server Explorer, then send another message; B may receive it subject to native permissions. Change the pre-created numeric attribute ShowCounts on Smoke to see fixed aggregate counters.
4. If native membership, tab or callbacks are unavailable, mark integration unverified. In platform-integrated chat, use the official TextChannelWindow targeted at the test channel if necessary (see Roblox documentation). Never circumvent permissions.

Stop the session and remove the test model. It never reads or logs conversation text and exits outside Studio. Do not ship it.

### Integrated chat
Enable PlatformIntegratedChat in Studio before the two-client test. Roblox documents that TextChannel:SendAsync and message-text access are unsupported in this mode. Use the built-in input, or a native TextChannelWindow with Target set to ChatFilterTest if the channel tab is unavailable. Do not send or render text yourself. A native window can be inserted in the client Explorer under a ScreenGui during a test. If chat is unavailable for the test accounts, report the delivery test as inconclusive. The sender's own echo is not evidence of receipt.

[Official integrated-chat setup](https://create.roblox.com/docs/chat/platform-integrated-chat)
