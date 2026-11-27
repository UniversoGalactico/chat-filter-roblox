# ChatFilter Lite — Native Chat Safety (v2 candidate)

Free, open-source supplemental moderation for Roblox. Roblox's native TextChatService remains the only transport, renderer and authority for chat filtering, permissions, reporting and muting.

## Why this exists

In January 2026, I was scammed in a Roblox game. I lost 79 Robux. I submitted clear evidence to Roblox support and was ignored.

I could have held a grudge. Instead, I built a chat filter and gave it away for free.

## Important platform change

Roblox requires player conversations to use TextChatService. Its platform-integrated chat is scheduled to become mandatory in May 2027 and removes script access to player message text. There is no supported workaround. This release removes the old custom RemoteEvent broadcast and custom rendering entirely.

- **native (default):** native chat only, with no custom callback. Recommended for platform-integrated chat.
- **context (experimental):** optional content-independent rate and server-defined restrictions on explicitly owned channels. Never reads message text. Actual integrated-chat callback behavior requires Studio validation.
- **legacy_text (transitional):** pre-platform-integrated TextChatService only; adds supplemental lexical rules. The native platform still owns filtering and recipient permissions.
- **Not supported:** interception of integrated chat content, custom chat transport, raw chat logs, report paywalls, comprehensive grooming detection, or claims that every abusive message is detected.

Sources: [chat guidelines](https://create.roblox.com/docs/chat/guidelines), [platform-integrated chat](https://create.roblox.com/docs/chat/platform-integrated-chat), [TextChannel callback](https://create.roblox.com/docs/reference/engine/classes/TextChannel).

## Migration (required for v1 users)

Delete the original ChatMessage RemoteEvent, legacy ChatServer and client GUI scripts in your experience. Remove any other code that forwards raw messages or disables the native chat interface. The two client files in this repository are inert migration stubs, not a replacement GUI. Keep Roblox reporting and mute/block controls available.

## Optional policy setup

1. Put ChatConfiguration, ProfanityData, TextPolicy, DeliveryGate and ChatFilter in ServerScriptService/ServerModules as ModuleScripts (without .lua suffixes).
2. Put ChatServer in ServerScriptService as a Script.
3. Set Mode to context only after confirming the callback works in your Studio configuration and you own the configured channel's ShouldDeliverCallback. Set Mode to legacy_text only if pre-platform-integrated TextChatService is in use. The default native mode installs no callback. Do not overwrite another system's callback. RBXGeneral is the sole default target; other channels retain native moderation only.
4. Test with multiple clients before deploying. See tests/README.md. Never enable legacy_text in integrated chat.

The optional policy uses exact normalized token and phrase matching, a small editable multilingual list, selected accent/leet folding, optional one-edit fuzzy matching (off by default), bounded processing and per-sender rate limits using a fixed-capacity expiry ring. Admission decisions are cached by platform message ID so each recipient callback does not consume a separate rate slot. Lexical policy is evaluated independently for every eligible recipient because Roblox does not guarantee identical text across recipients. Cache overflow quarantines unseen message IDs until a quiet TTL interval; live cached admission decisions are preserved. Entries expire, and player departure cleans state. No text is retained or printed. A trusted server may set ChatFilterMuted on a Player for temporary gameplay restrictions in covered channels. This is not a platform-wide mute.

Native chat can still show a sender their own local echo even when delivery to others is denied. This library does not guarantee full Unicode normalization, contextual detection, evasion resistance, or moderation across unconfigured channels. In legacy_text mode, empty/unavailable text is denied with a one-time static diagnostic. No attempt is made to retrieve unavailable content. Switch to native mode before platform-integrated chat migration. The experimental context mode does not read text at all; no claim of post-migration compatibility is made until verified in Studio.

## Tests

Run `lua5.4 tests/regression.lua`, `lua5.4 tests/adapter.lua`, `lua5.4 tests/bootstrap.lua` and `luau tests/regression.lua`. The two mock suites exercise the Roblox boundary and startup; the pure suite includes differential edit-distance checks, deterministic malformed input, and randomized delivery interleavings checked against an independent scan-based admission reference. No Studio validation is claimed. See [security assumptions](SECURITY.md).

MIT license. Contributions welcome.
