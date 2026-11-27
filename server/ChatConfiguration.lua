-- Roblox owns transport and recipient permissions in every mode.
-- native: no hook (default, recommended for platform-integrated chat).
-- context: optional content-independent hook on explicitly owned channels;
--          verify actual support in Studio before enabling.
-- legacy_text: pre-platform-integrated TextChatService only.
return {
    Mode = "native",
    ChannelNames = { "RBXGeneral" }, -- explicitly owned callbacks only
    EnableFuzzy = false, -- opt in after measuring false positives
    MaxMessageBytes = 512,
    MaxTokens = 80,
    MaxTokenBytes = 64,
    MessagesPerSecond = 3,
    DecisionTTL = 10,
    MaxCachedMessages = 64,
}
