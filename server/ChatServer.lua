-- ServerScriptService: optional TextChatService delivery policies.
-- Default: do not install a custom hook. Native chat remains fully enabled.
local TextChatService = game:GetService("TextChatService")
local ServerScriptService = game:GetService("ServerScriptService")
local modules = ServerScriptService:WaitForChild("ServerModules", 10)
if not modules then warn("[ChatFilter] Missing ServerModules; native chat unchanged.") return end
local configModule = modules:FindFirstChild("ChatConfiguration")
if not configModule then warn("[ChatFilter] Missing configuration; native chat unchanged.") return end
local configOk, config = pcall(require, configModule)
if not configOk or type(config) ~= "table" then
    warn("[ChatFilter] Invalid configuration; native chat unchanged.")
    return
end
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
local filterOk, filter = pcall(require, filterModule)
if not filterOk or type(filter) ~= "table" or type(filter.CreatePredicate) ~= "function" then
    warn("[ChatFilter] Filter module invalid; no hook installed.")
    return
end
local channels = TextChatService:WaitForChild("TextChannels", 10)
if not channels then warn("[ChatFilter] TextChannels missing; no hook installed.") return end
local names = {}
if type(config.ChannelNames) ~= "table" or #config.ChannelNames > 32 then
    warn("[ChatFilter] Invalid channel allowlist; no hook installed.")
    return
end
for _, name in ipairs(config.ChannelNames) do
    if type(name) ~= "string" or #name == 0 or #name > 128 then
        warn("[ChatFilter] Invalid channel name; no hook installed.")
        return
    end
    names[name] = true
end
if next(names) == nil then
    warn("[ChatFilter] No channels configured; no hook installed.")
    return
end
local initialized, predicate, stop = pcall(filter.CreatePredicate, config.Mode)
if not initialized or type(predicate) ~= "function" or type(stop) ~= "function" then
    warn("[ChatFilter] Policy initialization failed; no hook installed.")
    return
end
local bound = {}
local function bind(channel)
    if channel.Parent ~= channels or not channel:IsA("TextChannel") or not names[channel.Name] or bound[channel] then return end
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
