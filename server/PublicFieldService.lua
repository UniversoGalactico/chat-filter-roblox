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
Players.PlayerRemoving:Connect(function(player) leaving[player]=true end)

local PublicFieldService={}
function PublicFieldService.Request(player,raw,onResult)
    -- Trusted server callback only. Never accept a callback or object authority from a client.
    if type(onResult)~="function" then return false,"invalid_callback" end
    if type(raw)~="string" or #raw==0 or #raw>128 then return false,"invalid_text" end
    if not identity(player) then return false,"invalid_player" end
    -- Own the worker rather than yielding in the requester's coroutine. Cancellation
    -- of a UI/controller waiter cannot strand the pipeline's in-flight reservation.
    -- The thread handle is intentionally not returned to the caller.
    local scheduled=pcall(task.spawn,function()
        local ok,value,reason=pcall(filter,player,raw)
        if not ok then value,reason=nil,"service_error" end
        -- The pipeline releases its reservation before invoking trusted caller code.
        -- Do not retain or print callback errors; they may contain sensitive text.
        pcall(onResult,value,reason)
    end)
    if not scheduled then return false,"schedule_error" end
    return true,"scheduled"
end
return PublicFieldService
