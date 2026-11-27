-- TEST ONLY. Place beside ChatFilter, DeliveryGate and ContextPolicy in ServerScriptService.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local Players = game:GetService("Players")
local Chat = game:GetService("TextChatService")
local Filter = require(script.Parent.ChatFilter)
local Gate = require(script.Parent.DeliveryGate)
local Context = require(script.Parent.ContextPolicy)

-- F5: immediate checks with synthetic inputs; no message content or network calls.
local gate = Gate.new({MessagesPerSecond=1, DecisionTTL=2, MaxCachedMessages=4})
assert(gate:Admit("A","one",0))
assert(gate:Admit("A","one",0.1))
assert(not gate:Admit("A","two",0.1))
assert(gate:Admit("A","three",1))
gate:Clear()
assert(gate:Admit("A","two",0))
local context = Context.new({ScopeAttributes={Test="Group"}})
local function mock(group)
    return {GetAttribute=function(_,name) if name=="Group" then return group end end}
end
assert(context(mock("A"),mock("A"),"Test"))
assert(not context(mock("A"),mock("B"),"Test"))
print("[ChatFilter TEST] PASS: 7 local checks. Native delivery is NOT yet verified.")

-- Two clients: native delivery check. No automatic sends or custom transport.
local NAME, GROUP = "ChatFilterTest", "ChatFilterTestGroup"
assert(not Chat:FindFirstChild(NAME,true),"Test channel already exists")
local controller = Filter.new({ScopeAttributes={[NAME]=GROUP}})
local channel = Instance.new("TextChannel")
channel.Name = NAME
channel.Parent = Chat
channel.ShouldDeliverCallback = controller:ForChannel(channel)
local active, joined = true, 0
local assigned = {}
local function add(player)
    if not active or player.Parent~=Players or assigned[player] then return end
    if player:GetAttribute(GROUP)~=nil then warn("[TEST] Existing group attribute; skipped") return end
    joined=joined+1
    local group=joined==1 and "A" or "B"
    assigned[player]=true
    player:SetAttribute(GROUP,group)
    local ok,source=pcall(function() return channel:AddUserAsync(player.UserId) end)
    if not active or not assigned[player] or player.Parent~=Players then
        if ok and source and source.Parent==channel then source:Destroy() end
        return
    end
    if not ok or not source then warn("[TEST] Native membership unavailable; stop integration test") end
end
local added=Players.PlayerAdded:Connect(add)
local removing=Players.PlayerRemoving:Connect(function(player)
    if assigned[player] then assigned[player]=nil player:SetAttribute(GROUP,nil) end
end)
for _,player in ipairs(Players:GetPlayers()) do task.spawn(add,player) end
local stats=script:GetAttributeChangedSignal("ShowCounts"):Connect(function()
    local c=controller:GetCounts()
    print("[TEST] allow",c.allow,"scope",c.scope,"rate",c.rate_limit,"errors",c.policy_error,"identity",c.invalid_identity)
end)
script.Destroying:Connect(function()
    if not active then return end
    active=false
    added:Disconnect()
    removing:Disconnect()
    stats:Disconnect()
    controller:Destroy()
    channel:Destroy()
    for player in pairs(assigned) do
        if player.Parent==Players then player:SetAttribute(GROUP,nil) end
    end
    table.clear(assigned)
end)
print("[TEST] Two-client check: select ChatFilterTest; change B to A and repeat. Change ShowCounts to print totals.")
