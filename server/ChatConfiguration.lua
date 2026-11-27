-- Optional lexical settings; also used by pure tests.
return {
    EnableFuzzy = false,
    MaxMessageBytes = 512,
    MaxTokens = 80,
    MaxTokenBytes = 64,
    MessagesPerSecond = 3,
    DecisionTTL = 10,
    MaxCachedMessages = 64,
}
