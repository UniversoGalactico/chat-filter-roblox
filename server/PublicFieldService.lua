-- OPTIONAL server-only module. Not loaded by ChatServer.
-- Pet/item names or short sign labels only. NEVER a chat, reply or messaging transport.
local Players=game:GetService("Players")
local MemoryStoreService=game:GetService("MemoryStoreService")
local HttpService=game:GetService("HttpService")
local TextService=game:GetService("TextService")
local Pipeline=require(script.Parent.PublicFieldPipeline)
local TextPolicy=require(script.Parent.TextPolicy)
local Config=require(script.Parent.ChatConfiguration)
local Data=require(script.Parent.ProfanityData)
local map=MemoryStoreService:GetHashMap("ChatFilter_PublicFieldCooldown_v1")
local leaving=setmetatable({}, {__mode="k"})
Players.PlayerRemoving:Connect(function(player) leaving[player]=true end)
local function identity(player)
    if typeof(player)~="Instance" or not player:IsA("Player")
        or player.Parent~=Players or leaving[player] or Players:GetPlayerByUserId(player.UserId)~=player then
        return nil
    end
    return player.UserId
end
local function claim(userId)
    local token=HttpService:GenerateGUID(false)
    if type(token)~="string" or #token==0 then error("invalid claim token") end
    -- The transform may be retried on conflict. Only the returned unique token grants admission.
    local result=map:UpdateAsync("U_"..tostring(userId),function(old)
        if old~=nil then return nil end
        return token
    end,61)
    return result==token
end
local filter=Pipeline.new({
    now=os.clock,
    identity=identity,
    claim=claim,
    beginFilter=function(raw,id) return TextService:FilterStringAsync(raw,id) end,
    broadcast=function(result) return result:GetNonChatStringForBroadcastAsync() end,
},16,TextPolicy.new(Config,Data))
local PublicFieldService={}
function PublicFieldService.FilterAsync(player,raw)
    -- Caller authorizes the field before this call and revalidates after it.
    -- Never display raw text if the filtered result is nil.
    return filter(player,raw)
end
return PublicFieldService
