-- Mock engine boundary; the real Studio callback still needs validation.
local modules = {}
for _, name in ipairs({"TextPolicy","DeliveryGate","ContextPolicy","ChatConfiguration","ProfanityData"}) do
    modules[name] = dofile("server/" .. name .. ".lua")
end
local failLegacyRequire = false
local chat, players = {}, {}
local function channel(name)
    local ch = {Name=name, Parent=chat}
    function ch:IsA(class) return class=="TextChannel" end
    function ch:IsDescendantOf(parent) return self.Parent==parent end
    return ch
end
local match, other, reserved = channel("Match"), channel("Other"), channel("RBXTeam")
local onRemoving, connected
players.PlayerRemoving = {
    Connect = function(_, callback)
        onRemoving, connected = callback, true
        return {Disconnect=function() connected=false end}
    end,
}
local lookup = {}
function players:GetPlayerByUserId(id) return lookup[id] end
local function player(id)
    local p={Parent=players,UserId=id,muted=false,group=nil}
    function p:GetAttribute(key)
        if key=="ChatFilterMuted" then return self.muted end
        if key=="MatchId" then return self.group end
        error("unexpected attribute")
    end
    lookup[id]=p
    return p
end
local function source(p,ch,canSend) return {UserId=p.UserId,Parent=ch,CanSend=canSend} end
local a,b,c=player(1),player(2),player(3)
local sa,sb,sc=source(a,match,true),source(b,match,true),source(c,match,false)
local warnings=0
local now=10
local env=setmetatable({
    warn=function() warnings=warnings+1 end,
    game={GetService=function(_,name) return assert(({Players=players,TextChatService=chat})[name]) end},
    script={Parent={TextPolicy="TextPolicy",DeliveryGate="DeliveryGate",ContextPolicy="ContextPolicy",ChatConfiguration="ChatConfiguration",ProfanityData="ProfanityData"}},
    require=function(name)
        if failLegacyRequire and (name=="TextPolicy" or name=="ProfanityData" or name=="ChatConfiguration") then error("legacy module unavailable") end
        return assert(modules[name])
    end,
    os={clock=function() return now end},
},{__index=_G})
local Filter=assert(loadfile("server/ChatFilter.lua","t",env))()
local legacy=Filter.new({LegacyText=true})
local allow=legacy:ForChannel(match)
local m={TextChannel=match,TextSource=sa,MessageId="one",Text="hello"}
assert(allow(m,sb) and allow(m,sc))
sa.CanSend=false
assert(not allow(m,sb))
sa.CanSend=true
sa.Parent=other
assert(not allow(m,sb))
sa.Parent=match
sb.Parent=nil
assert(not allow(m,sb))
sb.Parent=match
assert(allow(m,sb))
m.TextChannel=other
assert(not allow(m,sb))
m.TextChannel=match
match.Parent=nil
assert(not allow(m,sb))
match.Parent=chat
assert(not allow(m,sb),"detached generation does not revive")
allow=legacy:ForChannel(match)
assert(allow(m,sb))
match.Name="Renamed"
assert(not allow(m,sb))
match.Name="Match"
assert(not allow(m,sb),"renamed generation does not revive")
allow=legacy:ForChannel(match)
assert(allow(m,sb))
m.Text="IDIOTA"
assert(not allow(m,sc))
m.Text="hello"
assert(allow(m,sb))
m.Text=""
assert(not allow(m,sc) and warnings==1)
m.Text="hello"
a.muted=true
assert(not allow(m,sb))
a.muted=false
assert(allow(m,sb))
assert(not allow(nil,sb) and not allow({},sb))
assert(not allow(m,{UserId=99,Parent=match,CanSend=true}))
onRemoving(a)
assert(not allow(m,sb))
assert(not allow({TextChannel=match,TextSource=sa,MessageId="new",Text="hello"},sb))
assert(not allow({TextChannel=match,TextSource=sb,MessageId="new",Text="hello"},sa))
local rejoined=player(1)
sa.Parent=nil
assert(not allow(m,sb))
sa=source(rejoined,match,true)
assert(allow({TextChannel=match,TextSource=sa,MessageId="four",Text="hello"},sb))
legacy:Destroy()
legacy:Destroy()
assert(not connected and not allow(m,sb))
assert(not pcall(legacy.ForChannel,legacy,match))
local stats=legacy:GetCounts()
assert(stats.allow>0 and stats.word>0 and stats.muted>0 and stats.text_unavailable>0 and stats.stopped==3 and stats.channel_invalid==2)
stats.allow=0
assert(legacy:GetCounts().allow>0)
failLegacyRequire=true
local options={ScopeAttributes={Match="MatchId"}}
rejoined.group,b.group,c.group="A","A","B"
local context=Filter.new(options)
local accepts=context:ForChannel(match)
assert(match.ShouldDeliverCallback==nil,"no callback ownership side effect")
assert(not pcall(context.ForChannel,context,match),"duplicate callback generation")
assert(not pcall(context.ForChannel,context,channel("RBXGeneral")))
assert(not pcall(context.ForChannel,context,channel("")))
assert(not pcall(context.ForChannel,context,channel(string.rep("a",129))))
assert(not pcall(context.ForChannel,context,reserved))
assert(not pcall(Filter.new,{LegacyText=true}))
options.ScopeAttributes.Match="Unexpected"
local unreadable=setmetatable({TextChannel=match,TextSource=sa,MessageId="context1"},{__index=function(_,key) error("unexpected property "..key) end})
assert(accepts(unreadable,sb))
assert(not accepts(unreadable,sc))
c.group="A"
assert(accepts(unreadable,sc))
c.group=nil
assert(not accepts(unreadable,sc))
rejoined.muted=true
assert(not accepts(unreadable,sb))
rejoined.muted=false
assert(accepts(unreadable,sb))
context:ReleaseChannel(match)
assert(not accepts(unreadable,sb),"released callback denies")
local rebound=context:ForChannel(match)
assert(rebound(unreadable,sb),"new generation can deliver")
assert(not accepts(unreadable,sb),"old generation cannot revive")
context:ReleaseChannel(other)
context:Destroy()
assert(not rebound(unreadable,sb))
local counts=context:GetCounts()
assert(counts.scope==2 and counts.muted==1 and counts.stopped==3)
assert(not pcall(Filter.new,{LegacyText="true"}))
assert(not pcall(Filter.new,{MessagesPerSecond=false}))
assert(not pcall(Filter.new,false))
assert(not pcall(Filter.new,{MessagePerSecond=3}))
assert(not pcall(Filter.new,setmetatable({},{})))
-- Releasing/rebinding must not create a new sender rate budget.
local limited=Filter.new({MessagesPerSecond=1,DecisionTTL=2,MaxCachedMessages=8})
local first=limited:ForChannel(match)
local test={TextChannel=match,TextSource=sa,MessageId="budget"}
assert(first(test,sb))
limited:ReleaseChannel(match)
local second=limited:ForChannel(match)
assert(second(test,sb),"same ID shares admission after rebind")
test.MessageId="different"
assert(not second(test,sb),"rebind cannot reset quota")
local otherCallback=limited:ForChannel(other)
local otherSource,otherReceiver=source(rejoined,other,true),source(b,other,true)
assert(not otherCallback({TextChannel=other,TextSource=otherSource,MessageId="budget"},otherReceiver),"quota spans channels")
now=11
test.MessageId="after-window"
assert(second(test,sb))
now=10.9
assert(not second(test,sb),"regressed clock denied even on cached allow")
now=12
local bad=setmetatable({}, {__index=function() error("private marker must not escape callback") end})
assert(not second(bad,sb),"callback exceptions deny")
assert(limited:GetCounts().policy_error==1)
limited:Destroy()
print("PASS: explicit channel ownership, recipient variants, lifecycle, shared quotas and context isolation")
