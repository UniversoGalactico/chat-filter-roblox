-- Optional supplemental delivery predicate; context mode never reads message text.
-- No RemoteEvent, no manual text forwarding, no custom rendering, no raw chat logs.
local Players = game:GetService("Players")
local DeliveryGate = require(script.Parent.DeliveryGate)
local ContextPolicy = require(script.Parent.ContextPolicy)
local Config = require(script.Parent.ChatConfiguration)

local ChatFilter = {}
local REASONS = {
    allow=true, invalid_identity=true, muted=true, scope=true, invalid_clock=true,
    clock_regression=true, rate_limit=true, cache_capacity=true, text_unavailable=true,
    invalid_length=true, invalid_utf8=true, complexity_limit=true, symbol=true, phrase=true,
    word=true, fuzzy=true, policy_error=true, stopped=true,
}
local MAX_COUNT = 2^53 - 1
function ChatFilter.CreatePredicate(mode)
    assert(mode == "context" or mode == "legacy_text", "invalid delivery mode")
    local evaluate
    if mode == "legacy_text" then
        local TextPolicy = require(script.Parent.TextPolicy)
        local Data = require(script.Parent.ProfanityData)
        evaluate = TextPolicy.new(Config, Data)
    end
    local gate = DeliveryGate.new(Config)
    local context = ContextPolicy.new(Config)
    local counters = {}
    local function record(reason)
        if not REASONS[reason] then reason = "policy_error" end
        counters[reason] = math.min((counters[reason] or 0) + 1, MAX_COUNT)
    end
    local function snapshot()
        local result = {}
        for reason in pairs(REASONS) do result[reason] = counters[reason] or 0 end
        return result
    end
    local leaving = setmetatable({}, { __mode = "k" })
    local removing = Players.PlayerRemoving:Connect(function(player)
        leaving[player] = true
        gate:Forget(player)
    end)
    local active, warnedUnavailable = true, false
    local function predicate(message, recipient, expectedChannel)
        if not active then record("stopped") return false end
        local ok, allow, reason = pcall(function()
            local source = message.TextSource
            local channel = message.TextChannel
            if not source or not recipient or not channel
                or (expectedChannel and channel ~= expectedChannel) then return false, "invalid_identity" end
            -- Roblox creates TextSources directly under the channel. Reject detached
            -- or foreign sources before resolving a possibly rejoined Player.
            if source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true then
                return false, "invalid_identity"
            end
            local sender = Players:GetPlayerByUserId(source.UserId)
            local receiver = Players:GetPlayerByUserId(recipient.UserId)
            if not sender or sender.Parent ~= Players or leaving[sender]
                or not receiver or receiver.Parent ~= Players or leaving[receiver] then
                return false, "invalid_identity"
            end
            local permitted, contextReason = context(sender, receiver, channel.Name)
            if not permitted then return false, contextReason end
            local admitted, admissionReason = gate:Admit(sender, message.MessageId, os.clock(), channel)
            if not admitted then return false, admissionReason end
            -- Content-independent mode must never even access the Text property.
            if mode == "context" then return true, "allow" end
            -- A platform message's Text may vary by recipient. Admission is shared;
            -- each lexical verdict is independent and no text/hash is cached.
            local text = message.Text
            if type(text) ~= "string" or text == "" then
                if not warnedUnavailable then
                    warnedUnavailable = true
                    warn("[ChatFilter] Legacy text unavailable; disable legacy_text mode in Studio. No attempt to recover content.")
                end
                return false, "text_unavailable"
            end
            return evaluate(text)
        end)
        if not ok or type(allow) ~= "boolean" or not REASONS[reason]
            or (allow and reason ~= "allow") or (not allow and reason == "allow") then
            record("policy_error")
            return false
        end
        record(reason)
        return allow
    end
    local function stop()
        if not active then return end
        active = false
        removing:Disconnect()
        gate:Clear()
    end
    return predicate, stop, snapshot
end
return ChatFilter
