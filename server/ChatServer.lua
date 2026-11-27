-- ServerScriptService: optional legacy TextChatService delivery policy.
-- Default: do not install a custom hook. Native chat remains fully enabled.
local TextChatService = game:GetService("TextChatService")
local ServerScriptService = game:GetService("ServerScriptService")
local modules = ServerScriptService:WaitForChild("ServerModules", 10)
if not modules then warn("[ChatFilter] Missing ServerModules; native chat unchanged.") return end
local configModule = modules:FindFirstChild("ChatConfiguration")
if not configModule then warn("[ChatFilter] Missing configuration; native chat unchanged.") return end
local config = require(configModule)
if not config.EnableLegacyDeliveryPolicy then
    print("[ChatFilter] Native chat only. No custom delivery hook installed.")
    return
end
local filterModule = modules:WaitForChild("ChatFilter", 10)
if not filterModule then warn("[ChatFilter] Missing filter module; no hook installed.") return end
local filter = require(filterModule)
local channels = TextChatService:WaitForChild("TextChannels", 10)
if not channels then warn("[ChatFilter] TextChannels missing; no hook installed.") return end
local names = {}
for _, name in ipairs(config.ChannelNames) do names[name] = true end
local predicate, stop = filter.CreatePredicate()
local bound = {}
local function bind(channel)
    if not channel:IsA("TextChannel") or not names[channel.Name] or bound[channel] then return end
    -- ShouldDeliverCallback is a single-owner hook. Only configure channels this script owns.
    local ok = pcall(function() channel.ShouldDeliverCallback = predicate end)
    if ok then bound[channel] = true else warn("[ChatFilter] Could not bind configured channel.") end
end
local added = channels.ChildAdded:Connect(bind)
local removed = channels.ChildRemoved:Connect(function(channel) bound[channel] = nil end)
for _, channel in ipairs(channels:GetChildren()) do bind(channel) end
script.Destroying:Connect(function()
    added:Disconnect()
    removed:Disconnect()
    stop()
    -- Fail closed for previously bound callbacks until the owning channel is replaced.
    table.clear(bound)
end)
