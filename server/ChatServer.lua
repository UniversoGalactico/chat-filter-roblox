-- ServerScriptService: optional TextChatService delivery policies.
-- Default: do not install a custom hook. Native chat remains fully enabled.
local TextChatService = game:GetService("TextChatService")
local ServerScriptService = game:GetService("ServerScriptService")
local modules = ServerScriptService:WaitForChild("ServerModules", 10)
if not modules then warn("[ChatFilter] Missing ServerModules; native chat unchanged.") return end
local configModule = modules:FindFirstChild("ChatConfiguration")
if not configModule then warn("[ChatFilter] Missing configuration; native chat unchanged.") return end
local config = require(configModule)
if config.Mode == "native" then
    print("[ChatFilter] Native chat only. No custom delivery hook installed.")
    return
end
if config.Mode ~= "context" and config.Mode ~= "legacy_text" then
    warn("[ChatFilter] Unknown Mode; native chat unchanged.")
    return
end
local filterModule = modules:WaitForChild("ChatFilter", 10)
if not filterModule then warn("[ChatFilter] Missing filter module; no hook installed.") return end
local filter = require(filterModule)
local channels = TextChatService:WaitForChild("TextChannels", 10)
if not channels then warn("[ChatFilter] TextChannels missing; no hook installed.") return end
local names = {}
assert(type(config.ChannelNames) == "table" and #config.ChannelNames <= 32, "invalid channel allowlist")
for _, name in ipairs(config.ChannelNames) do
    assert(type(name) == "string" and #name > 0 and #name <= 128, "invalid channel name")
    names[name] = true
end
local predicate, stop = filter.CreatePredicate(config.Mode)
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
