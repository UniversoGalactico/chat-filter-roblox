-- Optional supplemental delivery predicate for pre-platform-integrated TextChatService.
-- No RemoteEvent, no manual text forwarding, no custom rendering, no raw chat logs.
local Players = game:GetService("Players")
local TextPolicy = require(script.Parent.TextPolicy)
local DeliveryGate = require(script.Parent.DeliveryGate)
local Config = require(script.Parent.ChatConfiguration)
local Data = require(script.Parent.ProfanityData)

local ChatFilter = {}
function ChatFilter.CreatePredicate()
    local evaluate = TextPolicy.new(Config, Data)
    local gate = DeliveryGate.new(Config)
    local removing = Players.PlayerRemoving:Connect(function(player)
        gate:Forget(player)
    end)
    local active = true
    local function predicate(message, recipient)
        if not active then return false end
        local ok, allow = pcall(function()
            local source = message.TextSource
            if not source or not recipient then return false end
            local sender = Players:GetPlayerByUserId(source.UserId)
            local receiver = Players:GetPlayerByUserId(recipient.UserId)
            if not sender or sender.Parent ~= Players or not receiver or receiver.Parent ~= Players then
                return false
            end
            -- Trusted server-side gameplay restriction, never a substitute for Roblox permissions.
            if sender:GetAttribute("ChatFilterMuted") == true then return false end
            return gate:Decide(sender, message.MessageId, os.clock(), function()
                if not Config.EnableTextRules then return true, "allow" end
                -- Empty/unavailable text cannot be analyzed. Do not attempt to recover it.
                -- Native moderation remains responsible; opt out of the legacy hook when migrating.
                local text = message.Text
                if text == "" then return true, "native_only" end
                return evaluate(text)
            end)
        end)
        return ok and allow == true
    end
    local function stop()
        if not active then return end
        active = false
        removing:Disconnect()
    end
    return predicate, stop
end
return ChatFilter
