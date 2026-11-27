-- Pure supplemental text policy. Does not send, display, log or retain player text.
local TextPolicy = {}
local accents = {
    ["á"]="a", ["à"]="a", ["â"]="a", ["ã"]="a", ["ä"]="a", ["Á"]="a", ["À"]="a", ["Â"]="a", ["Ã"]="a", ["Ä"]="a",
    ["é"]="e", ["è"]="e", ["ê"]="e", ["ë"]="e", ["É"]="e", ["È"]="e", ["Ê"]="e", ["Ë"]="e",
    ["í"]="i", ["ì"]="i", ["î"]="i", ["ï"]="i", ["Í"]="i", ["Ì"]="i", ["Î"]="i", ["Ï"]="i",
    ["ó"]="o", ["ò"]="o", ["ô"]="o", ["õ"]="o", ["ö"]="o", ["Ó"]="o", ["Ò"]="o", ["Ô"]="o", ["Õ"]="o", ["Ö"]="o",
    ["ú"]="u", ["ù"]="u", ["û"]="u", ["ü"]="u", ["Ú"]="u", ["Ù"]="u", ["Û"]="u", ["Ü"]="u",
    ["ñ"]="n", ["Ñ"]="n", ["ç"]="c", ["Ç"]="c",
}
local invisible = { 0x200B, 0x200C, 0x200D, 0xFEFF, 0x300, 0x301, 0x302, 0x303, 0x308, 0x327 }
local ignored, fold = {}, {}
for _, cp in ipairs(invisible) do ignored[cp] = true end
for char, replacement in pairs(accents) do fold[utf8.codepoint(char)] = replacement end
local function isSeparator(cp)
    return cp <= 32 or cp == 127 or (cp >= 33 and cp <= 47)
        or (cp >= 58 and cp <= 64) or (cp >= 91 and cp <= 96)
        or (cp >= 123 and cp <= 126) or cp == 0xA0 or cp == 0x1680
        or (cp >= 0x2000 and cp <= 0x200A) or (cp >= 0x2010 and cp <= 0x2029)
        or cp == 0x202F or cp == 0x205F or cp == 0x3000
end
local leet = { ["0"]="o", ["1"]="i", ["3"]="e", ["4"]="a", ["5"]="s", ["7"]="t" }

local function tokenize(text, maxTokens, maxTokenBytes)
    -- Validate UTF-8 before substitutions. An invalid string never reaches rules.
    if not utf8.len(text) then return nil, "invalid_utf8" end
    -- A single codepoint pass handles the explicitly supported subset of Unicode.
    -- No claim of full normalization or cross-script confusable detection.
    local parts = {}
    for _, cp in utf8.codes(text) do
        if not ignored[cp] then
            if cp >= 0xFF01 and cp <= 0xFF5E then cp = cp - 0xFEE0 end
            local part
            if fold[cp] then
                part = fold[cp]
            elseif isSeparator(cp) then
                part = " "
            elseif cp >= 65 and cp <= 90 then
                part = string.char(cp + 32)
            else
                part = utf8.char(cp)
            end
            parts[#parts + 1] = part
        end
    end
    text = table.concat(parts)
    local tokens = {}
    for token in text:gmatch("%S+") do
        if #tokens >= maxTokens or #token > maxTokenBytes then return nil, "complexity_limit" end
        -- Keep standalone numbers intact.
        if token:find("[a-z]") then token = token:gsub("[013457]", leet) end
        tokens[#tokens + 1] = token
    end
    return tokens
end

-- One edit (insert/delete/substitute), ASCII tokens only. Linear time, constant space.
local function oneEdit(a, b)
    if math.abs(#a - #b) > 1 then return false end
    if #a > #b then a, b = b, a end
    local i, j, edits = 1, 1, 0
    while i <= #a and j <= #b do
        if a:byte(i) == b:byte(j) then
            i, j = i + 1, j + 1
        else
            edits = edits + 1
            if edits > 1 then return false end
            if #a == #b then i = i + 1 end
            j = j + 1
        end
    end
    return edits + (#b - j + 1) <= 1
end

local function boundedInt(value, lo, hi)
    assert(type(value) == "number" and value >= lo and value <= hi and value % 1 == 0, "invalid policy limit")
    return value
end

function TextPolicy.new(config, data)
    local maxBytes = boundedInt(config.MaxMessageBytes, 1, 2048)
    local maxTokens = boundedInt(config.MaxTokens, 1, 128)
    local maxTokenBytes = boundedInt(config.MaxTokenBytes, 1, 128)
    local fuzzy = config.EnableFuzzy == true
    local words, allowed, phrases, symbols, fuzzyByLength = {}, {}, {}, {}, {}
    local function load(list, sink, single)
        assert(type(list) == "table" and #list <= 256, "too many policy entries")
        for _, raw in ipairs(list) do
            assert(type(raw) == "string" and #raw <= maxBytes, "invalid policy entry")
            local tokens = tokenize(raw, maxTokens, maxTokenBytes)
            assert(tokens and #tokens > 0 and (not single or #tokens == 1), "invalid normalized policy entry")
            sink(table.concat(tokens, " "), tokens)
        end
    end
    load(data.Words, function(word)
        if not words[word] then
            words[word] = true
            if #word >= 6 and word:match("^[a-z]+$") then
                fuzzyByLength[#word] = fuzzyByLength[#word] or {}
                table.insert(fuzzyByLength[#word], word)
            end
        end
    end, true)
    load(data.AllowWords, function(word) allowed[word] = true end, true)
    load(data.Phrases, function(phrase) phrases[#phrases + 1] = " " .. phrase .. " " end, false)
    assert(type(data.BlockSymbols) == "table" and #data.BlockSymbols <= 32, "too many symbols")
    for _, symbol in ipairs(data.BlockSymbols) do
        assert(type(symbol) == "string" and #symbol > 0 and #symbol <= 32 and utf8.len(symbol), "invalid symbol")
        symbols[#symbols + 1] = symbol
    end

    return function(text)
        if type(text) ~= "string" or #text == 0 or #text > maxBytes then return false, "invalid_length" end
        local tokens, reason = tokenize(text, maxTokens, maxTokenBytes)
        if not tokens then return false, reason end
        for _, symbol in ipairs(symbols) do
            if text:find(symbol, 1, true) then return false, "symbol" end
        end
        local padded = " " .. table.concat(tokens, " ") .. " "
        for _, phrase in ipairs(phrases) do
            if padded:find(phrase, 1, true) then return false, "phrase" end
        end
        for _, token in ipairs(tokens) do
            -- Explicit exact blocks take precedence over accidental allow-list conflicts.
            if words[token] then return false, "word" end
            if fuzzy and not allowed[token] and #token >= 6 and token:match("^[a-z]+$") then
                for len = #token - 1, #token + 1 do
                    for _, word in ipairs(fuzzyByLength[len] or {}) do
                        if oneEdit(token, word) then return false, "fuzzy" end
                    end
                end
            end
        end
        -- Punctuation-only/emoji-only messages are left to native moderation.
        return true, "allow"
    end
end

return TextPolicy
