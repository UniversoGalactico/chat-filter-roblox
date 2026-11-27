-- Run from repository root: lua5.4 tests/regression.lua
local Policy = dofile("server/TextPolicy.lua")
local Gate = dofile("server/DeliveryGate.lua")
local config = dofile("server/ChatConfiguration.lua")
local data = dofile("server/ProfanityData.lua")
local check = Policy.new(config, data)
local count = 0
local function expect(value, wanted, label)
    count = count + 1
    assert(value == wanted, label .. ": expected " .. tostring(wanted) .. ", got " .. tostring(value))
end
for _, s in ipairs({"hola", "banana", "cereza", "attack the boss", "kill the NPC", "nice class", "hello ~", "🥵", "12345", "bom dia", "mesa", "asistente"}) do
    expect(check(s), true, "benign")
end
for _, s in ipairs({"IDIOTA", "imbécil", "IMBÉCIL", "imbe" .. utf8.char(0x301) .. "cil", "1diota", "idi" .. utf8.char(0x200B) .. "ota", "hdp", "kill yourself!", "hello, kill yourself", "vou te matar"}) do
    expect(check(s), false, "blocked")
end
expect(check("skill yourselfish"), true, "phrase boundary")
expect(check("assistant"), true, "word boundary")
expect(check(""), false, "empty")
expect(check(nil), false, "nil")
expect(check({}), false, "table")
expect(check(string.char(255)), false, "invalid UTF8")
expect(check(string.rep("a", 513)), false, "byte budget")
expect(check(string.rep("a", 65)), false, "token budget")
expect(check(string.rep("a ", 81)), false, "token count")
local fuzzyConfig = {}
for k, v in pairs(config) do fuzzyConfig[k] = v end
fuzzyConfig.EnableFuzzy = true
local fuzzy = Policy.new(fuzzyConfig, data)
expect(fuzzy("pelotud"), false, "one deletion")

expect(fuzzy("pelotxdo"), false, "one substitution")
expect(fuzzy("pelotudoz"), false, "one insertion")
expect(fuzzy("pelxxudo"), true, "two edits")
expect(check("pelotxdo"), true, "fuzzy disabled by default")

local gate = Gate.new(config)
local calls = 0
local function yes() calls = calls + 1 return true, "allow" end
local function no() calls = calls + 1 return false, "word" end
expect(gate:Decide("A", "id1", 0, yes), true, "first")
for i = 1, 200 do expect(gate:Decide("A", "id1", 0.1, no), true, "recipient dedup") end
expect(calls, 1, "evaluate once")
expect(gate:Decide("A", "id2", 0.1, no), false, "deny")
expect(gate:Decide("A", "id2", 0.2, yes), false, "deny cached")
expect(gate:Decide("A", "id3", 0.2, yes), true, "third")
expect(gate:Decide("A", "id4", 0.3, yes), false, "rate limit")
expect(gate:Decide("A", "id4", 1.2, yes), false, "denial stable after rate window")
expect(gate:Decide("A", "id5", 1.2, yes), true, "new window")
expect(gate:Decide("B", "id1", 0, yes), true, "separate sender")
expect(gate:Decide("A", "backwards", 1, yes), false, "clock regression")
expect(gate:Decide("A", "", 2, yes), false, "empty ID")
expect(gate:Decide("A", "badclock", 0/0, yes), false, "nan clock")
expect(gate:Decide("A", "throw", 2.5, function() error("private") end), false, "error closed")
expect(gate:Decide("A", "throw", 2.6, yes), false, "error cached")
gate:Forget("A")
expect(gate:Decide("A", "id4", 0, yes), true, "forget")
local tiny = Gate.new({MessagesPerSecond=1, DecisionTTL=2, MaxCachedMessages=2})
expect(tiny:Decide("X", "1", 0, yes), true, "capacity first")
expect(tiny:Decide("X", "2", 0, no), false, "capacity deny")
expect(tiny:Decide("X", "3", 1.5, yes), false, "capacity full")
expect(tiny:Decide("X", "2", 1.5, yes), false, "cached deny not evicted")
expect(tiny:Decide("X", "3", 2, yes), true, "expiry recovers")
-- Deterministic malformed/random-byte smoke test; no raw input printed.
local rng = 7
for i = 1, 1000 do
    rng = (rng * 48271) % 2147483647
    local parts = {}
    for j = 1, rng % 40 do
        rng = (rng * 48271) % 2147483647
        parts[j] = string.char(rng % 256)
    end
    local ok, result = pcall(check, table.concat(parts))
    expect(ok, true, "random input does not crash")
    expect(type(result), "boolean", "random input decision type")
end
print("PASS: " .. count .. " assertions")
