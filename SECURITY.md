# Security model

Native TextChatService owns message transport, filtering, recipient permissions, mute/block and reporting. ChatFilter only withholds delivery.

- Explicit ownership: ForChannel never assigns a callback. Use owned live channels with one owner. All reserved RBX-prefixed names (including RBXGeneral) are rejected; never overwrite a native or gameplay callback. ReleaseChannel revokes a callback generation without mutating the engine callback or clearing quota.
- Context mode: no Text access or lexical dependencies. Checks channel identity/name/ancestry, TextSource membership, CanSend, current Players, departure, server-owned mute/group attributes. Native permissions still apply.
- Admission: bounded FIFO cache by sender, channel and message ID; one-second limit; stable decisions within TTL; overflow quarantine until quiet. Lazy expiry may retain bounded entries until a new ID or departure. Assumes platform identifiers are unique for logical sends and callbacks arrive within TTL.
- Legacy text: pre-integrated chat only. Independent verdict per recipient; unavailable text denies. No recovery, full Unicode or intent guarantees. Fuzzy off by default.
- Lifecycle: Destroy disconnects the player signal and clears cache. Remaining callbacks deny after stop, detachment or rename. A generation that observes an invalid name or ancestry is permanently revoked; changes that occur and revert between callbacks may not be observed, so release explicitly before lifecycle changes. Restart after configuration changes.
- Privacy: fixed aggregate counts only; no chat text or user IDs exported. No client-trusted input path.
- Limits: pure models and mocks do not establish real engine permission behavior, integrated callback compatibility or moderation accuracy. The previous experimental public-field pipeline is historical, not shipped.

Report minimal synthetic reproductions without messages, identities or secrets.

Admission is charged before context checks for a valid sender/channel/recipient identity. Group and mute denials do not reset quota; recipient context is still reevaluated for each callback.
