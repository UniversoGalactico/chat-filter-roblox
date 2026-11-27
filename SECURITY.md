# Security model

ChatFilter is supplemental, not a replacement for Roblox safety mechanisms.

## Trust boundary

- Roblox TextChatService is the only transport, renderer, platform filter, recipient permission authority and reporting system.
- ChatFilter installs no chat-related RemoteEvent, does not accept messages directly from clients, and does not log, persist or export chat text.
- The optional server hook can withhold delivery; it cannot authorize a recipient against Roblox's rules.
- The default native mode installs no hook. Context mode uses server state and platform message identity without reading text. Legacy text mode is transitional only.
- Server-side game code and configured policy tables are trusted. The configured channels' delivery callbacks must have exactly one owner.

## Resource and lifecycle properties

- Every lexical input is bounded before normalization. Token count and token size are also bounded. Fuzzy matching is off by default and limited to one ASCII edit.
- Each live sender has a fixed-size cache of message admission decisions and a bounded sliding-window admission list. Duplicate recipient callbacks reuse admission, never a text verdict. Lexical rules are checked independently per eligible recipient, since TextChatMessage.Text can differ between users. Unknown IDs during cache pressure are quarantined until an idle interval, rather than evicting a live denial.
- The cache assumes the platform's MessageId uniquely identifies the same logical send and recipient callbacks occur within the configured decision TTL. A delayed callback after expiry can be treated as a new decision. No cross-server policy state is retained.
- Only known result codes are cached. Player departure discards sender state; a leaving player is rejected even before Parent changes.
- The hook is non-yielding. Optional-policy errors deny the affected delivery. Installation errors leave the native chat intact and emit static diagnostics.
- Hot replacement of delivery hooks is not supported. Restart the server after configuration changes; a stopped hook denies further deliveries if still attached.

## Known limitations

This is not a comprehensive anti-grooming system, abuse classifier, complete Unicode normalization library, or guarantee against evasion or false positives. Lexical matches do not justify automatic punishment. The sender may see a local echo even if recipients do not receive a message. A rule only covers the configured channels. Native chat is always required, including for channels not covered by ChatFilter.

Platform-integrated chat removes access to player message content. Never attempt to recover or circumvent this restriction. Context mode requires validation against the actual engine and rollout configuration; default to native mode when uncertain.

## Reporting a vulnerability

Report reproducible bugs with a minimal synthetic test, the commit SHA and the relevant mode. Never attach real player messages, personal information, credentials, or private moderation logs. If a report is sensitive, use GitHub's private vulnerability reporting if enabled. Do not test against unsuspecting players.
