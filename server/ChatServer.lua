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
local names = {}
if type(config.ChannelNames) ~= "table" or getmetatable(config.ChannelNames) ~= nil or #config.ChannelNames > 32 then
    warn("[ChatFilter] Invalid channel allowlist; no hook installed.")
    return
end
local count = 0
for key, name in pairs(config.ChannelNames) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #config.ChannelNames
        or type(name) ~= "string" or #name == 0 or #name > 128 or names[name] then
        warn("[ChatFilter] Invalid channel allowlist; no hook installed.")
        return
    end
    -- Never override native team, whisper, system or future reserved RBX channels.
    if name:sub(1,3):upper() == "RBX" and name ~= "RBXGeneral" then
        warn("[ChatFilter] Reserved channel cannot be auto-bound.")
        return
    end
    names[name] = true
    count = count + 1
end
if count ~= #config.ChannelNames then
    warn("[ChatFilter] Sparse channel allowlist; no hook installed.")
    return
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
local byName = {}
local active = true
local function ownsLocation(channel)
    local parent = channel.Parent
    return parent == TextChatService
        or (parent and parent.Parent == TextChatService and parent.Name == "TextChannels" and parent:IsA("Folder"))
end
local function bind(channel)
    if not active or not channel:IsA("TextChannel") or not ownsLocation(channel)
        or not names[channel.Name] or bound[channel] then return end
    local name = channel.Name
    if byName[name] then
        warn("[ChatFilter] Duplicate configured channel name; second channel left native.")
        return
    end
    -- Do not attempt to read an existing callback: Roblox callback members are write-only.
    -- The developer must explicitly own this channel before enabling auto-binding.
    local token = {}
    local function deliver(message, recipient)
        if not active or bound[channel] ~= token or channel.Name ~= name or not ownsLocation(channel) then return false end
        return predicate(message, recipient, channel)
    end
    local ok = pcall(function() channel.ShouldDeliverCallback = deliver end)
    if ok then
        bound[channel] = token
        byName[name] = channel
    else
        warn("[ChatFilter] Could not bind configured channel.")
    end
end
local function unbind(channel)
    if not bound[channel] then return end
    bound[channel] = nil
    for name, current in pairs(byName) do
        if current == channel then byName[name] = nil break end
    end
    -- Never clear a callback that another developer may have replaced.
end
local added = TextChatService.DescendantAdded:Connect(bind)
local removed = TextChatService.DescendantRemoving:Connect(unbind)
for _, channel in ipairs(TextChatService:GetDescendants()) do bind(channel) end
script.Destroying:Connect(function()
    if not active then return end
    active = false
    added:Disconnect()
    removed:Disconnect()
    stop()
    table.clear(bound)
    table.clear(byName)
end)
