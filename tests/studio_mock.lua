-- Execute the actual Studio smoke script against a small engine double.
-- This verifies its setup and cleanup code, not native chat delivery.
local function signal()
    local s={handlers={}}
    function s:Connect(fn)
        local connection={active=true}
        function connection:Disconnect() self.active=false end
        self.handlers[#self.handlers+1]={fn=fn,connection=connection}
        return connection
    end
    function s:Fire(...)
        for _,h in ipairs(self.handlers) do if h.connection.active then h.fn(...) end end
    end
    return s
end
local function run(studio, nativeAvailable)
    local players={PlayerAdded=signal(),PlayerRemoving=signal(),list={}}
    local chat={channels={}}
    function chat:FindFirstChild(name)
        for _,c in ipairs(self.channels) do if c.Parent==self and c.Name==name then return c end end
    end
    function players:GetPlayers() return self.list end
    function players:GetPlayerByUserId(id)
        for _,p in ipairs(self.list) do if p.UserId==id then return p end end
    end
    local function player(id)
        local p={UserId=id,Parent=players,attrs={}}
        function p:GetAttribute(name) return self.attrs[name] end
        function p:SetAttribute(name,value) self.attrs[name]=value end
        players.list[#players.list+1]=p
        return p
    end
    local a,b=player(101),player(102)
    local function newChannel()
        local ch={Name="",sources={},destroyed=false}
        function ch:IsA(name) return name=="TextChannel" end
        function ch:IsDescendantOf(parent) return self.Parent==parent end
        function ch:AddUserAsync(id)
            if not nativeAvailable then return nil,false end
            local source={UserId=id,CanSend=true,Parent=self}
            function source:Destroy() self.Parent=nil end
            self.sources[id]=source
            return source,true
        end
        function ch:Destroy()
            self.destroyed=true self.Parent=nil
            for _,source in pairs(self.sources) do source:Destroy() end
        end
        chat.channels[#chat.channels+1]=ch
        return ch
    end
    local scriptObject={Destroying=signal(),attrs={},signals={},Parent={ChatFilter="ChatFilter",DeliveryGate="DeliveryGate",ContextPolicy="ContextPolicy"}}
    function scriptObject:SetAttribute(name,value)
        self.attrs[name]=value
        if self.signals[name] then self.signals[name]:Fire() end
    end
    function scriptObject:GetAttributeChangedSignal(name)
        self.signals[name]=self.signals[name] or signal()
        return self.signals[name]
    end
    local logs,warnings={},{}
    local modules={DeliveryGate=dofile("server/DeliveryGate.lua"),ContextPolicy=dofile("server/ContextPolicy.lua")}
    local env=setmetatable({
        game={GetService=function(_,name) return assert(({Players=players,TextChatService=chat,RunService={IsStudio=function() return studio end}})[name]) end},
        script=scriptObject,Instance={new=function(class) assert(class=="TextChannel") return newChannel() end},
        require=function(name) return assert(modules[name]) end,
        task={spawn=function(fn,...) fn(...) end},
        os={clock=function() return 20 end},
        table=setmetatable({clear=function(t) for k in pairs(t) do t[k]=nil end end},{__index=table}),
        print=function(...) logs[#logs+1]={...} end,
        warn=function(...) warnings[#warnings+1]={...} end,
    },{__index=_G})
    modules.ChatFilter=assert(loadfile("server/ChatFilter.lua","t",env))()
    assert(loadfile("tests/studio/Smoke.server.lua","t",env))()
    if not studio then assert(#chat.channels==0 and #logs==0) return end
    local channel=assert(chat:FindFirstChild("ChatFilterTest"))
    assert(a:GetAttribute("ChatFilterTestGroup")=="A" and b:GetAttribute("ChatFilterTestGroup")=="B")
    assert(scriptObject.attrs.ShowCounts==0)
    assert(logs[1][1]:find("PASS: 18 local checks",1,true))
    if nativeAvailable then
        local msg={TextChannel=channel,TextSource=channel.sources[101],MessageId="one"}
        assert(not channel.ShouldDeliverCallback(msg,channel.sources[102]))
        b:SetAttribute("ChatFilterTestGroup","A")
        assert(channel.ShouldDeliverCallback(msg,channel.sources[102]))
        players.PlayerRemoving:Fire(b)
        assert(not channel.ShouldDeliverCallback(msg,channel.sources[102]))
        assert(b:GetAttribute("ChatFilterTestGroup")==nil)
    else
        assert(#warnings==2,"missing membership is reported rather than treated as success")
    end
    scriptObject:SetAttribute("ShowCounts",1)
    assert(logs[#logs][1]=="[TEST] allow")
    scriptObject.Destroying:Fire()
    assert(channel.destroyed and a:GetAttribute("ChatFilterTestGroup")==nil and b:GetAttribute("ChatFilterTestGroup")==nil)
    local late=player(103)
    players.PlayerAdded:Fire(late)
    assert(late:GetAttribute("ChatFilterTestGroup")==nil)
end
run(false,false)
run(true,false)
run(true,true)
print("PASS: actual Studio smoke script setup, no-membership handling, group changes and cleanup (mock)")
