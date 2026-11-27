# ChatFilter Lite — Native Chat Safety (v2 candidate)

Free, open-source supplemental moderation for Roblox. Roblox's native TextChatService remains the only transport, renderer and authority for chat filtering, permissions, reporting and muting.

## Why this exists

In January 2026, I was scammed in a Roblox game. I lost 79 Robux. I submitted clear evidence to Roblox support and was ignored.

I could have held a grudge. Instead, I built a chat filter and gave it away for free.

## Important platform change

Roblox requires player conversations to use TextChatService. Its platform-integrated chat is scheduled to become mandatory in May 2027 and removes script access to player message text. There is no supported workaround. This release removes the old custom RemoteEvent broadcast and custom rendering entirely.

- **native (default):** native chat only, with no custom callback. Recommended for platform-integrated chat.
- **context (experimental):** optional content-independent rate, temporary server-defined mute and gameplay group restrictions on explicitly owned channels. Never reads message text or loads lexical dependencies. Actual integrated-chat callback behavior requires Studio validation.
- **legacy_text (transitional):** pre-platform-integrated TextChatService only; adds supplemental lexical rules. The native platform still owns filtering and recipient permissions.
- **Not supported:** interception of integrated chat content, custom chat transport, raw chat logs, report paywalls, comprehensive grooming detection, or claims that every abusive message is detected.

Roblox's October 22, 2026 roadmap update also announced native creator-defined blocked words on top of its filter, planned by May 2027. The announcement says channel membership, sender identity, delivery status, timestamps and message IDs are preserved. This is a roadmap, not a guarantee of any unpublished API. Treat the lexical list as a transitional policy and review it for native migration when Roblox documents the feature; this repository does not implement an unofficial integration.

Sources: [October 2026 announcement](https://devforum.roblox.com/t/important-textchatservice-updates-how-to-test-and-what%E2%80%99s-next/4948433), [chat guidelines](https://create.roblox.com/docs/chat/guidelines), [platform-integrated chat](https://create.roblox.com/docs/chat/platform-integrated-chat), [TextChannel callback](https://create.roblox.com/docs/reference/engine/classes/TextChannel).

[Guía de instalación y validación en español](docs/INSTALLATION.es.md).

## Migration (required for v1 users)

Delete the original ChatMessage RemoteEvent, legacy ChatServer and client GUI scripts in your experience. Remove any other code that forwards raw messages or disables the native chat interface. The two client files in this repository are inert migration stubs, not a replacement GUI. Keep Roblox reporting and mute/block controls available.

## Optional policy setup

1. Put ChatConfiguration, ProfanityData, TextPolicy, ContextPolicy, DeliveryGate and ChatFilter in ServerScriptService/ServerModules as ModuleScripts (without .lua suffixes).
2. Put ChatServer in ServerScriptService as a Script.
3. Set Mode to context only after confirming the callback works in your Studio configuration and you own the configured channel's ShouldDeliverCallback. Set Mode to legacy_text only if pre-platform-integrated TextChatService is in use. The default native mode installs no callback. Do not overwrite another system's callback. RBXGeneral is the sole default target; other channels retain native moderation only. Auto-binding accepts owned custom channels directly under TextChatService or inside its TextChannels folder; reserved RBX-prefixed channels other than RBXGeneral are rejected. Duplicate names are unsupported. For a channel with existing game rules, integrate CreatePredicate manually into your existing non-yielding callback instead of enabling auto-binding for that channel.
4. Test with multiple clients before deploying. See tests/README.md. Never enable legacy_text in integrated chat.

The optional policy uses exact normalized token and phrase matching, a small editable multilingual list, selected accent/leet folding and punctuation/emoji boundaries with an independently tested ASCII fast path, optional indexed one-edit fuzzy matching for ASCII dictionary words of 6–32 bytes (off by default), bounded processing and per-sender rate limits using a fixed-capacity expiry ring. Admission decisions are cached by channel identity plus platform message ID so each recipient callback does not consume a separate rate slot. Lexical policy is evaluated independently for every eligible recipient because Roblox does not guarantee identical text across recipients. Cache overflow quarantines unseen message IDs until a quiet TTL interval; live cached admission decisions are preserved. Entries expire, and player departure cleans state. No text is retained or printed. A trusted server may set ChatFilterMuted on a Player for temporary gameplay restrictions in covered channels. This is not a platform-wide mute. You can also set `ScopeAttributes = {Match = "MatchId"}` for an owned custom channel named Match: both players must have the same valid server-owned MatchId attribute. Missing or malformed membership denies. This is a gameplay partition, not a replacement for Roblox chat permissions or age-based safety.

For manual server integration, `ChatFilter.CreatePredicate(mode)` returns `predicate, stop, snapshot`. The optional snapshot contains only aggregate counters by fixed reason code, counted per callback (not unique messages or players). An allow counter is a local policy decision, not proof of platform delivery. No automatic telemetry is sent.

Native chat can still show a sender their own local echo even when delivery to others is denied. This library does not guarantee full Unicode normalization, contextual detection, evasion resistance, or moderation across unconfigured channels. In legacy_text mode, empty/unavailable text is denied with a one-time static diagnostic. No attempt is made to retrieve unavailable content. Switch to native mode before platform-integrated chat migration. The experimental context mode does not read text at all; no claim of post-migration compatibility is made until verified in Studio.

## Optional one-way public fields (experimental, not chat)

`PublicFieldService` is a separate server-only opt-in for short pet/item names or sign labels. It is never loaded by ChatServer. Do not use it for messages, replies, mail, phones, radios, text-based gameplay coordination, or any chat substitute. Native TextChatService is required for conversations.

Install PublicFieldPipeline and PublicFieldService beside the other server modules only if needed. The caller must authenticate the Player and authorize the specific editable object on the server before calling `PublicFieldService.Request(player, raw, onResult)`. The service owns its worker; cancellation of the caller's coroutine cannot strand the filter reservation. The returned boolean means scheduling only, not approval. A trusted server callback receives `filtered, reason` (possibly immediately for a rejected request). Revalidate the same player, object, ownership and object generation inside the callback; assign only the non-nil filtered label without yielding between revalidation and assignment. Never show the raw input or fall back to it. Do not expose this function or callback directly to clients.

The service applies a local 60-second attempt cooldown and a shared universe-wide MemoryStore atomic cooldown (61-second expiry), then uses Roblox TextService and GetNonChatStringForBroadcastAsync. The optional lexical policy is additional only. A failure in either service rejects the edit; stale results are discarded, and at most 16 calls run concurrently in a server. No player text is stored, logged or forwarded by this module. The short-lived MemoryStore key contains a user ID and random claim token solely for cooldown enforcement. This adds a service dependency and requires tests in a published test universe; every editable field in every place must share the gate.

See [Roblox editable text rules](https://create.roblox.com/docs/chat/guidelines) and [rate-limited text surfaces](https://create.roblox.com/docs/ui/temporary-limits).

## Tests

Run `lua5.4 tests/regression.lua`, `lua5.4 tests/adapter.lua`, `lua5.4 tests/bootstrap.lua` and `luau tests/regression.lua`. The mock suites exercise the Roblox boundary, startup and optional public field service; additional pure public-field tests exercise yielding races; the pure suite includes differential edit-distance checks for the signature index, deterministic malformed input, and randomized delivery interleavings checked against an independent scan-based admission reference. No Studio validation is claimed. CI also runs targeted mutation checks against temporary copies and comparative synthetic benchmarks against the exact previous algorithm commits; medians are diagnostic, not a performance guarantee. See [security assumptions](SECURITY.md).

MIT license. Contributions welcome.
