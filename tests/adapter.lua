-- Portable Lua mock of the Roblox boundary; not a Studio or privacy integration test.
local modules = {}
for _, name in ipairs({"TextPolicy","DeliveryGate","ContextPolicy","ChatConfiguration","ProfanityData"}) do
    modules[name] = dofile("server/" .. name .. ".lua")
end
local config = modules.ChatConfiguration
local channel, otherChannel = {Name="Match"}, {Name="Other"}
local failLegacyRequire = false
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
    local p = {Parent=players, UserId=id, muted=false, group=nil}
    function p:GetAttribute(key)
        if key=="ChatFilterMuted" then return self.muted end
        if key=="MatchId" then return self.group end
        error("unexpected attribute")
    end
    lookup[id] = p
    return p
end
local a, b, c = player(1), player(2), player(3)
local function textSource(p, parent, canSend)
    return {UserId=p.UserId, Parent=parent, CanSend=canSend}
end
local sa,sb,sc=textSource(a,channel,true),textSource(b,channel,true),textSource(c,channel,false)
local warnings = 0
local env = setmetatable({
    warn = function() warnings = warnings + 1 end,
    game = { GetService = function(_, name) assert(name=="Players") return players end },
    script = { Parent = {TextPolicy="TextPolicy", DeliveryGate="DeliveryGate", ContextPolicy="ContextPolicy", ChatConfiguration="ChatConfiguration", ProfanityData="ProfanityData"} },
    require = function(name)
        if failLegacyRequire and (name=="TextPolicy" or name=="ProfanityData") then error("legacy module unavailable") end
        return assert(modules[name])
    end,
    os = { clock = function() return 10 end },
}, {__index=_G})
local filter = assert(loadfile("server/ChatFilter.lua", "t", env))()
local allow, stop, stats = filter.CreatePredicate("legacy_text")
local m = {TextChannel=channel, TextSource=sa, MessageId="one", Text="hello"}
assert(allow(m,sb) and allow(m,sc), "read-only recipient can receive")
sa.CanSend=false
assert(not allow(m,sb), "read-only sender cannot deliver")
sa.CanSend=true
sa.Parent=otherChannel
assert(not allow(m,sb), "foreign sender source")
sa.Parent=channel
sb.Parent=nil
assert(not allow(m,sb), "detached recipient source")
sb.Parent=channel
assert(allow(m,sb))
assert(not allow(m,sb,otherChannel), "bound channel mismatch")
assert(allow(m,sb,channel), "bound channel matches")
-- Same platform MessageId, different recipient-visible content.
m.Text = "IDIOTA"
assert(not allow(m,sc), "cached admission must not grant a different text")
m.Text = "hello"
assert(allow(m,sb), "denied variant must not poison another recipient")
m.Text = ""
assert(not allow(m,sc), "unavailable variant must not reuse allow")
m.Text = "hello"
a.muted = true
assert(not allow(m,sb), "context restriction must precede cached allow")
a.muted = false
assert(allow(m,sb))
m = {TextChannel=channel, TextSource=sa, MessageId="two", Text="IDIOTA"}
assert(not allow(m,sb) and not allow(m,sc))
assert(not allow(nil,sb) and not allow({},sb))
assert(not allow(m,{UserId=99, Parent=channel, CanSend=true}))
m = {TextChannel=channel, TextSource=sa, MessageId="three", Text=""}
assert(not allow(m,sb), "legacy mode cannot evaluate unavailable text")
assert(not allow(m,sc) and warnings==1, "one static warning, independent denial")
onRemoving(a)
assert(not allow(m,sb), "PlayerRemoving before Parent changes")
assert(not allow({TextChannel=channel, TextSource=sa,MessageId="after-removal",Text="hello"},sb),
    "departing sender with valid content and fresh admission must be denied")
assert(not allow({TextChannel=channel, TextSource=sb,MessageId="other",Text="hello"},sa), "departing receiver")
local rejoined = player(1)
sa.Parent=nil
assert(not allow({TextChannel=channel, TextSource=sa,MessageId="old-session",Text="hello"},sb), "detached source after rejoin")
sa=textSource(rejoined,channel,true)
assert(allow({TextChannel=channel, TextSource=sa,MessageId="four",Text="hello"},sb), "new Player identity")
assert(rejoined ~= a)
stop()
stop()
assert(not connected and not allow(m,sb), "idempotent stop")
local totals=stats()
assert(totals.allow>0 and totals.word>0 and totals.muted>0 and totals.text_unavailable>0 and totals.stopped==1)
totals.allow=0
assert(stats().allow>0, "snapshot does not mutate counters")
failLegacyRequire = true
config.ScopeAttributes={Match="MatchId"}
rejoined.group="round-1"
b.group="round-1"
c.group="round-2"
local context, stopContext, contextStats = filter.CreatePredicate("context")
config.ScopeAttributes.Match="Unexpected" -- compiled policy must not change after initialization
assert(not pcall(filter.CreatePredicate,"legacy_text"), "missing lexical dependency only affects legacy mode")
local unreadable = setmetatable({TextChannel=channel, TextSource=sa, MessageId="context1"}, {
    __index=function(_, key) error("unexpected property access: "..key) end
})
assert(context(unreadable,sb), "context mode never reads message content")
assert(not context(unreadable,sc), "same message, different gameplay scope")
c.group="round-1"
assert(context(unreadable,sc), "scope is checked at every delivery")
c.group=nil
assert(not context(unreadable,sc), "missing scope denies")
rejoined.muted=true
assert(not context(unreadable,sb), "context mute works without text")
rejoined.muted=false
assert(context(unreadable,sb))
stopContext()
assert(not context(unreadable,sb))
assert(contextStats().scope==2 and contextStats().muted==1 and contextStats().stopped==1)
assert(not pcall(filter.CreatePredicate,"invalid"))
print("PASS: adapter lifecycle, routing, and context mode isolation")
