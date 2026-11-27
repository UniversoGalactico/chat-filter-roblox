-- MANUAL STUDIO-ONLY integration aid. Never install in a production experience.
-- No custom transport, no player text logging, no automatic message sends.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() or script:GetAttribute("RunChatFilterSmoke")~=true then return end

local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local ServerScriptService=game:GetService("ServerScriptService")
local NAME="ChatFilterSmoke"
local GROUP="ChatFilterSmokeGroup"
local modules=assert(ServerScriptService:WaitForChild("ServerModules",10),"missing test modules")
local config=require(assert(modules:WaitForChild("ChatConfiguration",10)))
assert(config.Mode=="native","disable automatic hooks for this isolated test")
assert(type(config.ScopeAttributes)=="table" and config.ScopeAttributes[NAME]==GROUP,
    "configure ScopeAttributes.ChatFilterSmoke = 'ChatFilterSmokeGroup' in the test place")
assert(not TextChatService:FindFirstChild(NAME,true),"test channel already exists")
local filter=require(assert(modules:WaitForChild("ChatFilter",10)))
local predicate,stop,snapshot=filter.CreatePredicate("context")

local channel=Instance.new("TextChannel")
channel.Name=NAME
local active=true
local assigned=setmetatable({},{__mode="k"})
local inFlight=setmetatable({},{__mode="k"})
local joinIndex=0
channel.ShouldDeliverCallback=function(message,recipient)
    if not active then return false end
    return predicate(message,recipient,channel)
end
channel.Parent=TextChatService

local function add(player)
    if not active or player.Parent~=Players or assigned[player] or inFlight[player] then return end
    if player:GetAttribute(GROUP)~=nil then
        warn("[ChatFilter smoke] Existing test attribute; player skipped.")
        return
    end
    inFlight[player]=true
    joinIndex=joinIndex+1
    local group=joinIndex<=2 and "A" or "B"
    player:SetAttribute(GROUP,group)
    assigned[player]=true
    task.spawn(function()
        local ok,source=pcall(function()
            return channel:AddUserAsync(player.UserId)
        end)
        inFlight[player]=nil
        if not active or player.Parent~=Players then
            if ok and source and source.Parent==channel then source:Destroy() end
            return
        end
        if not ok or not source then
            warn("[ChatFilter smoke] Native membership unavailable; no bypass attempted.")
        else
            print("[ChatFilter smoke] Native membership created or returned.")
        end
    end)
end

local joined=Players.PlayerAdded:Connect(add)
local departing=Players.PlayerRemoving:Connect(function(player)
    if assigned[player] then
        assigned[player]=nil
        player:SetAttribute(GROUP,nil)
    end
end)
local report=script:GetAttributeChangedSignal("SnapshotRequest"):Connect(function()
    if not active then return end
    local counts=snapshot()
    print(string.format("[ChatFilter smoke] callback decisions: allow=%d scope=%d mute=%d rate=%d identity=%d error=%d",
        counts.allow,counts.scope,counts.muted,counts.rate_limit,counts.invalid_identity,counts.policy_error))
end)
script.Destroying:Connect(function()
    if not active then return end
    active=false
    joined:Disconnect()
    departing:Disconnect()
    report:Disconnect()
    stop()
    channel:Destroy()
    for player in pairs(assigned) do
        if player.Parent==Players then player:SetAttribute(GROUP,nil) end
    end
    table.clear(assigned)
end)
for _,player in ipairs(Players:GetPlayers()) do add(player) end
print("[ChatFilter smoke] Send only benign test messages manually in ChatFilterSmoke. Change SnapshotRequest to inspect aggregate decisions.")
