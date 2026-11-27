-- Optional Roblox delivery policy. Native TextChatService remains authoritative.
-- Install ChatFilter, DeliveryGate and ContextPolicy as sibling server ModuleScripts.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local DeliveryGate = require(script.Parent.DeliveryGate)
local ContextPolicy = require(script.Parent.ContextPolicy)

local ChatFilter = {}
local REASONS = {
    allow=true, invalid_identity=true, muted=true, scope=true, invalid_clock=true,
    clock_regression=true, rate_limit=true, cache_capacity=true, text_unavailable=true,
    invalid_length=true, invalid_utf8=true, complexity_limit=true, symbol=true, phrase=true,
    word=true, fuzzy=true, policy_error=true, stopped=true, channel_invalid=true,
}
local MAX_COUNT = 2^53 - 1

function ChatFilter.new(options)
    if options == nil then options = {} end
    assert(type(options) == "table" and getmetatable(options) == nil, "options must be a plain table")
    local known = {MessagesPerSecond=true, DecisionTTL=true, MaxCachedMessages=true, ScopeAttributes=true, LegacyText=true}
    for key in pairs(options) do assert(known[key], "unknown ChatFilter option") end
    assert(options.LegacyText == nil or type(options.LegacyText) == "boolean", "LegacyText must be boolean")
    local gate = DeliveryGate.new({
        MessagesPerSecond = options.MessagesPerSecond == nil and 3 or options.MessagesPerSecond,
        DecisionTTL = options.DecisionTTL == nil and 10 or options.DecisionTTL,
        MaxCachedMessages = options.MaxCachedMessages == nil and 64 or options.MaxCachedMessages,
    })
    local context = ContextPolicy.new(options)
    local evaluate
    if options.LegacyText == true then
        local TextPolicy = require(script.Parent.TextPolicy)
        local Data = require(script.Parent.ProfanityData)
        local config = require(script.Parent.ChatConfiguration)
        evaluate = TextPolicy.new(config, Data)
    end

    local active, warnedUnavailable = true, false
    local counters, leaving = {}, setmetatable({}, {__mode="k"})
    local removing = Players.PlayerRemoving:Connect(function(player)
        leaving[player] = true
        gate:Forget(player)
    end)
    local function record(reason)
        counters[reason] = math.min((counters[reason] or 0) + 1, MAX_COUNT)
    end
    local function decide(message, recipient, channel, name)
        if not channel:IsDescendantOf(TextChatService) or channel.Name ~= name then return false, "channel_invalid" end
        if message.TextChannel ~= channel then return false, "invalid_identity" end
        local source = message.TextSource
        if not source or not recipient then return false, "invalid_identity" end
        if source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true then
            return false, "invalid_identity"
        end
        local sender = Players:GetPlayerByUserId(source.UserId)
        local receiver = Players:GetPlayerByUserId(recipient.UserId)
        if not sender or sender.Parent ~= Players or leaving[sender]
            or not receiver or receiver.Parent ~= Players or leaving[receiver] then
            return false, "invalid_identity"
        end
        -- Charge once per valid logical send even if a recipient fails the group rule.
        -- Context is never cached: a mute or group change can still deny a cached admission.
        local admitted, admissionReason = gate:Admit(sender, message.MessageId, os.clock(), channel)
        if not admitted then return false, admissionReason end
        local permitted, reason = context(sender, receiver, name)
        if not permitted then return false, reason end
        if not evaluate then return true, "allow" end
        local text = message.Text -- legacy only; never cache this verdict or content
        if type(text) ~= "string" or text == "" then
            if not warnedUnavailable then
                warnedUnavailable = true
                warn("[ChatFilter] Legacy text unavailable. Disable LegacyText.")
            end
            return false, "text_unavailable"
        end
        return evaluate(text)
    end
    -- One active callback generation per channel. A released callback never revives.
    local bindings = setmetatable({}, {__mode="k"})
    local controller = {}
    function controller:ReleaseChannel(channel)
        if channel == nil then return end
        bindings[channel] = nil
    end
    function controller:ForChannel(channel)
        assert(active, "controller destroyed")
        assert(channel:IsA("TextChannel") and channel:IsDescendantOf(TextChatService), "expected live TextChannel")
        local name = channel.Name
        assert(#name > 0 and #name <= 128, "invalid channel name length")
        assert(name:sub(1,3):upper() ~= "RBX", "reserved channel")
        assert(not bindings[channel], "channel already bound; release before rebinding")
        local token = {}
        bindings[channel] = token
        -- Does NOT assign or replace ShouldDeliverCallback. The sole owner does that.
        return function(message, recipient)
            if not active or bindings[channel] ~= token then record("stopped") return false end
            local ok, allow, reason = pcall(decide, message, recipient, channel, name)
            if not ok or type(allow) ~= "boolean" or not REASONS[reason]
                or allow ~= (reason == "allow") then
                record("policy_error")
                return false
            end
            -- Observed detachment/rename invalidates this generation permanently.
            -- Restoring the old name or parent must not silently resume delivery.
            if reason == "channel_invalid" then bindings[channel] = nil end
            record(reason)
            return allow
        end
    end
    function controller:GetCounts()
        local copy = {}
        for reason in pairs(REASONS) do copy[reason] = counters[reason] or 0 end
        return copy
    end
    function controller:Destroy()
        if not active then return end
        active = false
        removing:Disconnect()
        for channel in pairs(bindings) do bindings[channel] = nil end
        gate:Clear()
    end
    return controller
end
return ChatFilter
