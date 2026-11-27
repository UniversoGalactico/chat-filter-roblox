-- Portable Lua mock of the Roblox boundary; not a Studio or privacy integration test.
local modules = {}
for _, name in ipairs({"TextPolicy","DeliveryGate","ChatConfiguration","ProfanityData"}) do
    modules[name] = dofile("server/" .. name .. ".lua")
end
local config = modules.ChatConfiguration
local players = {}
local onRemoving, connected
players.PlayerRemoving = {
    Connect = function(_, callback)
        onRemoving, connected = callback, true
        return { Disconnect = function() connected = false end }
    end
}
local lookup = {}
function players:GetPlayerByUserId(id) return lookup[id] end
local function player(id)
    local p = {Parent=players, UserId=id, muted=false}
    function p:GetAttribute(key) assert(key=="ChatFilterMuted") return self.muted end
    lookup[id] = p
    return p
end
local a, b, c = player(1), player(2), player(3)
local env = setmetatable({
    game = { GetService = function(_, name) assert(name=="Players") return players end },
    script = { Parent = {TextPolicy="TextPolicy", DeliveryGate="DeliveryGate", ChatConfiguration="ChatConfiguration", ProfanityData="ProfanityData"} },
    require = function(name) return assert(modules[name]) end,
    os = { clock = function() return 10 end },
}, {__index=_G})
local filter = assert(loadfile("server/ChatFilter.lua", "t", env))()
local allow, stop = filter.CreatePredicate()
local m = {TextSource={UserId=1}, MessageId="one", Text="hello"}
assert(allow(m,b) and allow(m,c))
a.muted = true
assert(not allow(m,b), "context restriction must precede cached allow")
a.muted = false
assert(allow(m,b))
m = {TextSource={UserId=1}, MessageId="two", Text="IDIOTA"}
assert(not allow(m,b) and not allow(m,c))
assert(not allow(nil,b) and not allow({},b))
assert(not allow(m,{UserId=99}))
m = {TextSource={UserId=1}, MessageId="three", Text=""}
assert(allow(m,b), "native-only for unavailable text")
onRemoving(a)
assert(not allow(m,b), "PlayerRemoving before Parent changes")
assert(not allow({TextSource={UserId=2},MessageId="other",Text="hello"},a), "departing receiver")
local rejoined = player(1)
assert(allow({TextSource={UserId=1},MessageId="four",Text="hello"},b), "new Player identity")
assert(rejoined ~= a)
stop()
stop()
assert(not connected and not allow(m,b), "idempotent stop")
print("PASS: adapter lifecycle and routing")
