# ChatFilter Lite

Optional server-side delivery restrictions for Roblox's native TextChatService. No custom chat, GUI, RemoteEvent or chat logs. If you only want native chat, install nothing.

## Start here

Copy three ModuleScripts into ServerScriptService: [ChatFilter](server/ChatFilter.lua), [DeliveryGate](server/DeliveryGate.lua), [ContextPolicy](server/ContextPolicy.lua). In the sole server script owning your custom channel:

```lua
local Filter = require(script.Parent.ChatFilter)
local policy = Filter.new()
channel.ShouldDeliverCallback = policy:ForChannel(channel)
script.Destroying:Connect(function() policy:Destroy() end)
```

The default policy limits new messages to three per second per sender, across channels bound to one controller. Server code may set ChatFilterMuted=true on a Player. To restrict your Match channel to matching server-owned MatchId attributes:

```lua
local policy = Filter.new({ScopeAttributes = {Match = "MatchId"}})
```

ForChannel returns a callback; it never installs one. Only one active callback per channel per controller is allowed. ReleaseChannel(channel) revokes it permanently before an explicit rebind; it does not edit the engine callback or reset the rate budget. If your channel has existing rules, combine them in the sole owning script rather than replacing them. All RBX-prefixed channels are rejected, including RBXGeneral; leave platform-owned channels alone. Destroy stops the policy; callbacks left installed deny, so restart the server to remove it.

## Quick test

[Import the Studio model](tests/studio/ChatFilterTest.rbxmx), [test instructions](tests/studio/README.md), [Spanish guide](docs/INSTALLATION.es.md). Studio has not yet been run.

## Options

| Option | Default | Purpose |
|---|---|---|
| MessagesPerSecond | 3 | One-second sender limit |
| DecisionTTL | 10 | Admission reuse in seconds |
| MaxCachedMessages | 64 | Per-sender capacity |
| ScopeAttributes | {} | Channel name to server attribute |
| LegacyText | false | Transitional lexical check only |

GetCounts() returns a copy of aggregate per-callback counts, not evidence of receipt. Destroy() is idempotent.

## Optional legacy text

Roblox plans mandatory platform-integrated chat in May 2027, removing script access to chat content, and announced native creator-defined blocked words. Never attempt to recover unavailable text. LegacyText=true is only for explicitly verified pre-integrated chat: install TextPolicy, ProfanityData and ChatConfiguration as additional siblings. Exact-only by default, fuzzy opt-in, no automatic punishment. Migrate to the official feature when documented.

The experimental one-way label pipeline and automatic binder are no longer shipped; [previous candidate](https://github.com/UniversoGalactico/chat-filter-roblox/tree/8e6e9bff949643f02305dd1864d1fb8963cff62b) retains the source in Git history.

## Evidence and limits

[Verification](tests/README.md) · [Audit](docs/AUDIT.md) · [Security](SECURITY.md). Pure tests, mocks and compilation are not actual Studio validation or a safety/accuracy guarantee. Native Roblox permissions remain authoritative.

[Roblox chat rules](https://create.roblox.com/docs/chat/guidelines) · [Platform-integrated chat](https://create.roblox.com/docs/chat/platform-integrated-chat) · [TextChannel](https://create.roblox.com/docs/reference/engine/classes/TextChannel)

MIT license.
