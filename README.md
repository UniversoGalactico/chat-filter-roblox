# ChatFilter Lite — Native Chat Safety (v2 candidate)

Free, open-source supplemental moderation for Roblox. Roblox's native TextChatService remains the only transport, renderer and authority for chat filtering, permissions, reporting and muting.

## Why this exists

In January 2026, I was scammed in a Roblox game. I lost 79 Robux. I submitted clear evidence to Roblox support and was ignored.

I could have held a grudge. Instead, I built a chat filter and gave it away for free.

## Important platform change

Roblox requires player conversations to use TextChatService. Its platform-integrated chat is scheduled to become mandatory in May 2027 and removes script access to player message text. There is no supported workaround. This release removes the old custom RemoteEvent broadcast and custom rendering entirely.

- **Default:** native chat only, with no custom callback.
- **Optional transitional mode:** on an experience still using pre-platform-integrated TextChatService, attach a non-yielding supplemental delivery predicate to explicitly configured channels. The native platform still filters and applies recipient permissions.
- **Not supported:** interception of integrated chat content, custom chat transport, raw chat logs, report paywalls, comprehensive grooming detection, or claims that every abusive message is detected.

Sources: [chat guidelines](https://create.roblox.com/docs/chat/guidelines), [platform-integrated chat](https://create.roblox.com/docs/chat/platform-integrated-chat), [TextChannel callback](https://create.roblox.com/docs/reference/engine/classes/TextChannel).

## Migration (required for v1 users)

Delete the original ChatMessage RemoteEvent, legacy ChatServer and client GUI scripts in your experience. Remove any other code that forwards raw messages or disables the native chat interface. The two client files in this repository are inert migration stubs, not a replacement GUI. Keep Roblox reporting and mute/block controls available.

## Optional legacy policy setup

1. Put ChatConfiguration, ProfanityData, TextPolicy, DeliveryGate and ChatFilter in ServerScriptService/ServerModules as ModuleScripts (without .lua suffixes).
2. Put ChatServer in ServerScriptService as a Script.
3. In Studio, verify that platform-integrated chat is disabled and that you own the configured channel's ShouldDeliverCallback. EnableLegacyDeliveryPolicy defaults to false; enable it only after these checks. Do not overwrite another system's callback. RBXGeneral is the sole default target; other channels retain native moderation only.
4. Test with multiple clients before deploying. See tests/README.md. Do not enable this mode in integrated chat.

The optional policy uses exact normalized token and phrase matching, a small editable multilingual list, selected accent/leet folding, optional one-edit fuzzy matching (off by default), bounded processing and per-sender rate limits. Decisions are cached by platform message ID so each recipient callback does not consume a separate rate slot. Cache overflow denies new messages; entries expire; player departure cleans state. No text is retained or printed. A trusted server may set ChatFilterMuted on a Player for temporary gameplay restrictions in covered channels. This is not a platform-wide mute.

Native chat can still show a sender their own local echo even when delivery to others is denied. This library does not guarantee full Unicode normalization, contextual detection, evasion resistance, or moderation across unconfigured channels. Empty text is left to native moderation; never attempt to retrieve unavailable text. Disable the legacy hook before platform-integrated chat migration.

## Tests

Run `lua5.4 tests/regression.lua`. Pure policy/gate tests and deterministic malformed-input checks are separate from Roblox integration tests. No Studio validation is claimed.

MIT license. Contributions welcome.
