-- Opt in only while the experience uses pre-platform-integrated TextChatService.
-- Keep false in platform-integrated chat. Roblox owns all message transport.
return {
    EnableLegacyDeliveryPolicy = false,
    ChannelNames = { "RBXGeneral" }, -- explicitly owned callbacks only
    EnableTextRules = true,
    EnableFuzzy = false, -- opt in after measuring false positives
    MaxMessageBytes = 512,
    MaxTokens = 80,
    MaxTokenBytes = 64,
    MessagesPerSecond = 3,
    DecisionTTL = 10,
    MaxCachedMessages = 64,
}
