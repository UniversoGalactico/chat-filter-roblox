-- Small, conservative, editable supplemental policy. Not a safety classifier.
-- Do not block ordinary gameplay vocabulary, food names or all emoji.
return {
    Words = {
        "gilipollas", "pelotudo", "imbecil", "idiota", "estupido",
        "asshole", "motherfucker", "fuck", "fucking", "bitch",
        "caralho", "buceta", "fodendo",
        "kys", "hdp",
    },
    Phrases = {
        "kill yourself", "i will rape you", "i hope you die",
        "matate", "suicidate", "te voy a violar",
        "se mate", "vou te matar",
    },
    AllowWords = { "assistant", "assist", "class", "classic", "pass" },
    -- Optional unambiguous symbols only; context-dependent emojis remain allowed.
    BlockSymbols = {},
}
