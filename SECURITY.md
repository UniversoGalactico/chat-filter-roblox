# Security model

ChatFilter is supplemental, not a replacement for Roblox safety mechanisms.

## Trust boundary

- Roblox TextChatService is the only transport, renderer, platform filter, recipient permission authority and reporting system.
- ChatFilter installs no chat-related RemoteEvent, does not accept messages directly from clients, and does not log, persist or export chat text.
- The optional server hook can withhold delivery; it cannot authorize a recipient against Roblox's rules.
- The default native mode installs no hook. Context mode uses server state and platform message identity without reading text or loading lexical modules. Optional gameplay group rules require equal valid server-owned attributes; missing membership denies. A malformed mute attribute denies rather than silently ignoring a broken server policy. These are not a substitute for native permissions. Legacy text mode is transitional only.
- Server-side game code and configured policy tables are trusted. The configured channels' delivery callbacks must have exactly one owner. The auto-binder rejects native reserved channels other than RBXGeneral and never reads or clears an existing callback. Renamed/detached bound channels deny until explicitly rebound or restarted.

## Resource and lifecycle properties

- Every lexical input is bounded before normalization. Token count and token size are also bounded. Fuzzy matching is off by default and limited to one ASCII edit against dictionary words of 6–32 bytes. Signature indexes bound work by the input length rather than scanning the configured dictionary. Exact matching is available for longer configured words.
- Each live sender has a fixed-size cache of message admission decisions, a fixed-capacity FIFO expiry ring and a bounded sliding-window admission list. The admission engine accepts no evaluator callback and cannot yield through user code. Duplicate recipient callbacks reuse admission, never a text verdict. Lexical rules are checked independently per eligible recipient, since TextChatMessage.Text can differ between users. Unknown IDs during cache pressure are quarantined until an idle interval, rather than evicting a live denial.
- The cache keys by the channel instance plus platform MessageId and assumes the pair identifies the same logical send and recipient callbacks occur within the configured decision TTL. A delayed callback after expiry can be treated as a new decision. No cross-server policy state is retained.
- Only fixed admission result codes are cached. The adapter exposes aggregate per-callback counters by fixed reason code; no messages, user IDs, timestamps, recipient lists or content hashes are exported. Player departure discards sender state; a leaving player is rejected even before Parent changes.
- The hook is non-yielding. Optional-policy errors deny the affected delivery. Installation errors leave the native chat intact and emit static diagnostics.
- Hot replacement of delivery hooks is not supported. Restart the server after configuration changes; a stopped hook denies further deliveries if still attached.

## Optional non-chat public fields

The separate PublicFieldService uses TextService for short one-way labels only, not as a chat path. Both official filtering stages must succeed before a string is returned. Input and output are bounded valid UTF-8 with a limited blank/control check; this is not complete grapheme or rendering validation. It never falls back to raw text. An atomic MemoryStore claim enforces a shared 61-second cooldown across servers in a universe. The temporary key contains only a user ID and random token. Uncertain outcomes consume the cooldown rather than being retried. Local per-player and per-server in-flight limits are reserved before yielding; stale results are discarded after service boundaries. The Roblox adapter owns the scheduled worker and does not return a cancellable thread handle. It invokes trusted callbacks only after releasing the pipeline reservation. An indefinitely stalled dependency can occupy an in-flight slot until it returns; no watchdog releases an active operation.

The caller still owns authorization, stale target revision checks, persistence/display behavior, and ensuring that the feature cannot become a conversation. No replies or messaging. Every editable field in every place must use the same gate. No actual MemoryStore, TextService or Studio integration test is claimed.

## Known limitations

This is not a comprehensive anti-grooming system, abuse classifier, complete Unicode normalization library, or guarantee against evasion or false positives. Lexical matches do not justify automatic punishment. The sender may see a local echo even if recipients do not receive a message. A rule only covers the configured channels. Native chat is always required, including for channels not covered by ChatFilter.

Platform-integrated chat removes access to player message content. Never attempt to recover or circumvent this restriction. Context mode requires validation against the actual engine and rollout configuration; default to native mode when uncertain.

## Reporting a vulnerability

Report reproducible bugs with a minimal synthetic test, the commit SHA and the relevant mode. Never attach real player messages, personal information, credentials, or private moderation logs. If a report is sensitive, use GitHub's private vulnerability reporting if enabled. Do not test against unsuspecting players.
