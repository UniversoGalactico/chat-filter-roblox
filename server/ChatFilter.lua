-- Optional supplemental delivery predicate; context mode never reads message text.
-- No RemoteEvent, no manual text forwarding, no custom rendering, no raw chat logs.
local Players = game:GetService("Players")
local DeliveryGate = require(script.Parent.DeliveryGate)
local Config = require(script.Parent.ChatConfiguration)

local ChatFilter = {}
function ChatFilter.CreatePredicate(mode)
    assert(mode == "context" or mode == "legacy_text", "invalid delivery mode")
    local evaluate
    if mode == "legacy_text" then
        local TextPolicy = require(script.Parent.TextPolicy)
        local Data = require(script.Parent.ProfanityData)
        evaluate = TextPolicy.new(Config, Data)
    end
    local gate = DeliveryGate.new(Config)
    local leaving = setmetatable({}, { __mode = "k" })
    local removing = Players.PlayerRemoving:Connect(function(player)
        leaving[player] = true
        gate:Forget(player)
    end)
    local active, warnedUnavailable = true, false
    local function predicate(message, recipient, expectedChannel)
        if not active then return false end
        local ok, allow = pcall(function()
            local source = message.TextSource
            local channel = message.TextChannel
            if not source or not recipient or not channel
                or (expectedChannel and channel ~= expectedChannel) then return false end
            local sender = Players:GetPlayerByUserId(source.UserId)
            local receiver = Players:GetPlayerByUserId(recipient.UserId)
            if not sender or sender.Parent ~= Players or leaving[sender]
                or not receiver or receiver.Parent ~= Players or leaving[receiver] then
                return false
            end
            -- Trusted server-side gameplay restriction, never a substitute for Roblox permissions.
            if sender:GetAttribute("ChatFilterMuted") == true then return false end
            local admitted = gate:Admit(sender, message.MessageId, os.clock(), channel)
            if not admitted then return false end
            -- Content-independent mode must never even access the Text property.
            if mode == "context" then return true end
            -- A platform message's Text may vary by recipient. Admission is shared;
            -- each lexical verdict is independent and no text/hash is cached.
            local text = message.Text
            if type(text) ~= "string" or text == "" then
                if not warnedUnavailable then
                    warnedUnavailable = true
                    warn("[ChatFilter] Legacy text unavailable; disable legacy_text mode in Studio. No attempt to recover content.")
                end
                return false
            end
            return evaluate(text)
        end)
        return ok and allow == true
    end
    local function stop()
        if not active then return end
        active = false
        removing:Disconnect()
        gate:Clear()
    end
    return predicate, stop
end
return ChatFilter
