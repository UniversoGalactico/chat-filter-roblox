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
local invisible = { 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0xFE0E, 0xFE0F, 0x300, 0x301, 0x302, 0x303, 0x308, 0x327 }
for cp = 0x202A, 0x202E do invisible[#invisible + 1] = cp end
for cp = 0x2066, 0x2069 do invisible[#invisible + 1] = cp end
local ignored, fold = {}, {}
for _, cp in ipairs(invisible) do ignored[cp] = true end
for char, replacement in pairs(accents) do fold[utf8.codepoint(char)] = replacement end
local function isSeparator(cp)
    return cp <= 32 or cp == 127 or (cp >= 33 and cp <= 47)
        or (cp >= 58 and cp <= 64) or (cp >= 91 and cp <= 96)
        or (cp >= 123 and cp <= 126) or cp == 0xA0 or cp == 0x1680
        or (cp >= 0x2000 and cp <= 0x200A) or (cp >= 0x2010 and cp <= 0x2029)
        or cp == 0x202F or cp == 0x205F or cp == 0x3000
        -- Selected punctuation and emoji are word boundaries, not blocked content.
        or cp == 0xA1 or cp == 0xBF or cp == 0xAB or cp == 0xBB or cp == 0xB7
        or cp == 0x3001 or cp == 0x3002 or (cp >= 0x3008 and cp <= 0x3011)
        or (cp >= 0x2600 and cp <= 0x27BF) or (cp >= 0x1F000 and cp <= 0x1FAFF)
end
local leet = { ["0"]="o", ["1"]="i", ["3"]="e", ["4"]="a", ["5"]="s", ["7"]="t" }

local function tokenize(text, maxTokens, maxTokenBytes)
    -- Fast path: all ASCII bytes are valid UTF-8. Use the same explicit separator
    -- ranges as the Unicode path, not locale-dependent character classes.
    if not text:find("[\128-\255]") then
        text = text:lower():gsub("[%z\1-\47\58-\64\91-\96\123-\127]+", " ")
    else
        if not utf8.len(text) then return nil, "invalid_utf8" end
        local parts = {}
        for _, cp in utf8.codes(text) do
            if cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then return nil, "invalid_utf8" end
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
    end
    local tokens = {}
    for token in text:gmatch("[^ ]+") do
        if #tokens >= maxTokens or #token > maxTokenBytes then return nil, "complexity_limit" end
        -- Keep standalone numbers intact.
        if token:find("[013457]") and token:find("[a-z]") then token = token:gsub("[013457]", leet) end
        tokens[#tokens + 1] = token
    end
    return tokens
end

-- A one-edit index for ASCII words of length 6..32:
--   exact shorter word in the deletion index => one deletion
--   deleting one byte of a longer input hits a word => one insertion
--   same-position masked signature => one substitution
-- No candidate scan, no edit-distance matrix, and no approximate hash collisions.
local function removeAt(word, i)
    return word:sub(1,i-1) .. word:sub(i+1)
end
local function maskAt(word, i)
    return word:sub(1,i-1) .. "\0" .. word:sub(i+1)
end
local function isFuzzyWord(word)
    return #word >= 6 and #word <= 32 and word:match("^[a-z]+$") ~= nil
end
local function denseArray(list, limit)
    assert(type(list) == "table" and getmetatable(list) == nil, "policy list must be a plain array")
    local length = #list
    assert(length <= limit, "too many policy entries")
    local count = 0
    for key in pairs(list) do
        assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= length, "invalid policy array index")
        count = count + 1
    end
    assert(count == length, "sparse policy array")
    return list
end

local function boundedInt(value, lo, hi)
    assert(type(value) == "number" and value >= lo and value <= hi and value % 1 == 0, "invalid policy limit")
    return value
end

function TextPolicy.new(config, data)
    local maxBytes = boundedInt(config.MaxMessageBytes, 1, 2048)
    local maxTokens = boundedInt(config.MaxTokens, 1, 128)
    local maxTokenBytes = boundedInt(config.MaxTokenBytes, 1, 128)
    assert(config.EnableFuzzy == nil or type(config.EnableFuzzy) == "boolean", "EnableFuzzy must be boolean")
    local fuzzy = config.EnableFuzzy == true
    local words, allowed, phraseRoot, symbols = {}, {}, {}, {}
    local fuzzyWords, deletions, substitutions = {}, {}, {}
    local function load(list, sink, single)
        for _, raw in ipairs(denseArray(list, 256)) do
            assert(type(raw) == "string" and #raw <= maxBytes, "invalid policy entry")
            local tokens = tokenize(raw, maxTokens, maxTokenBytes)
            assert(tokens and #tokens > 0 and (not single or #tokens == 1), "invalid normalized policy entry")
            sink(table.concat(tokens, " "), tokens)
        end
    end
    load(data.Words, function(word)
        if not words[word] then
            words[word] = true
            if fuzzy and isFuzzyWord(word) then
                fuzzyWords[word] = true
                for i = 1, #word do
                    deletions[removeAt(word, i)] = true
                    substitutions[maskAt(word, i)] = true
                end
            end
        end
    end, true)
    load(data.AllowWords, function(word) allowed[word] = true end, true)
    -- Token trie; phrase matching never treats a substring of a word as a phrase.
    load(data.Phrases, function(_, tokens)
        local node = phraseRoot
        for _, token in ipairs(tokens) do
            if not node[token] then node[token] = {} end
            node = node[token]
        end
        node[true] = true -- boolean key cannot collide with string tokens
    end, false)
    for _, symbol in ipairs(denseArray(data.BlockSymbols, 32)) do
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
        for i = 1, #tokens do
            local node = phraseRoot
            for j = i, #tokens do
                node = node[tokens[j]]
                if not node then break end
                if node[true] then return false, "phrase" end
            end
        end
        for _, token in ipairs(tokens) do
            -- Explicit exact blocks take precedence over accidental allow-list conflicts.
            if words[token] then return false, "word" end
            if fuzzy and not allowed[token] and #token >= 6 and #token <= 33
                and token:match("^[a-z]+$") then
                if deletions[token] then return false, "fuzzy" end
                for i = 1, #token do
                    if fuzzyWords[removeAt(token,i)] or substitutions[maskAt(token,i)] then
                        return false, "fuzzy"
                    end
                end
            end
        end
        -- Punctuation-only/emoji-only messages are left to native moderation.
        return true, "allow"
    end
end

return TextPolicy
