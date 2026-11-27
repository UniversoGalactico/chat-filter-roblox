-- Roblox bootstrap mock: channels can be direct children or under TextChannels.
local function signal()
    local s={handlers={}}
    function s:Connect(cb)
        local entry={cb=cb,active=true}
        self.handlers[#self.handlers+1]=entry
        return {Disconnect=function() entry.active=false end}
    end
    function s:Fire(value)
        for _,entry in ipairs(self.handlers) do if entry.active then entry.cb(value) end end
    end
    return s
end
local function scenario(mode, options)
    options=options or {}
    local service={DescendantAdded=signal(),DescendantRemoving=signal(),children={}}
    function service:GetDescendants() return self.children end
    local folder={Parent=service,Name="TextChannels"}
    function folder:IsA(class) return class=="Folder" end
    local function channel(name,class,parent)
        local c={Name=name,Parent=parent or folder}
        function c:IsA(wanted) return (class or "TextChannel")==wanted end
        service.children[#service.children+1]=c
        return c
    end
    local general=channel("RBXGeneral")
    local team=channel("RBXTeam")
    local impostor=channel("RBXGeneral","Folder")
    local direct=channel("Match",nil,service)
    local nested=channel("Match",nil,{Parent=service,Name="Other"})
    local calls,stopped,warnings,deliveries=0,0,0,0
    local function callback(message,recipient,boundChannel)
        deliveries=deliveries+1
        return message==boundChannel
    end
    local mods={
        ChatConfiguration={Mode=mode,ChannelNames=options.names or {"RBXGeneral","Match"}},
        ChatFilter={CreatePredicate=function(received)
            assert(received==mode)
            calls=calls+1
            if options.initError then error("private") end
            return callback,function() stopped=stopped+1 end
        end},
    }
    local moduleFolder={}
    function moduleFolder:FindFirstChild(name) return mods[name] and name or nil end
    function moduleFolder:WaitForChild(name,timeout) assert(timeout==10) return mods[name] and name or nil end
    local services={
        ServerScriptService={WaitForChild=function(_,name,timeout)
            assert(name=="ServerModules" and timeout==10)
            if options.noModules then return nil end
            return moduleFolder
        end},
        TextChatService=service,
    }
    local destroying=signal()
    local env=setmetatable({
        game={GetService=function(_,name) return assert(services[name]) end},
        script={Destroying=destroying},
        require=function(name)
            if options.badRequire==name then error("private") end
            return mods[name]
        end,
        print=function() end,
        warn=function(message) assert(type(message)=="string") warnings=warnings+1 end,
        table=setmetatable({clear=function(t) for k in pairs(t) do t[k]=nil end end},{__index=table}),
    },{__index=_G})
    assert(loadfile("server/ChatServer.lua","t",env))()
    if options.expectHook then
        assert(calls==1 and general.ShouldDeliverCallback and direct.ShouldDeliverCallback)
        assert(team.ShouldDeliverCallback==nil and impostor.ShouldDeliverCallback==nil and nested.ShouldDeliverCallback==nil)
        assert(general.ShouldDeliverCallback(general,{}))
        assert(not general.ShouldDeliverCallback(direct,{}))
        local first=general.ShouldDeliverCallback
        local duplicate=channel("RBXGeneral")
        service.DescendantAdded:Fire(duplicate)
        assert(duplicate.ShouldDeliverCallback==nil)
        general.Name="Other"
        assert(not first(general,{}))
        general.Name="RBXGeneral"
        assert(first(general,{}))
        service.DescendantRemoving:Fire(general)
        assert(not first(general,{}))
        general.Parent=nil
        service.DescendantAdded:Fire(duplicate)
        assert(duplicate.ShouldDeliverCallback and duplicate.ShouldDeliverCallback(duplicate,{}))
        local unrelated=channel("RBXWhisper")
        service.DescendantAdded:Fire(unrelated)
        assert(unrelated.ShouldDeliverCallback==nil)
        destroying:Fire()
        destroying:Fire()
        assert(stopped==1 and not duplicate.ShouldDeliverCallback(duplicate,{}) and not direct.ShouldDeliverCallback(direct,{}))
        local after=channel("Match",nil,service)
        service.DescendantAdded:Fire(after)
        assert(after.ShouldDeliverCallback==nil)
        assert(deliveries>=4)
    else
        assert(general.ShouldDeliverCallback==nil and team.ShouldDeliverCallback==nil and direct.ShouldDeliverCallback==nil)
        assert(calls==(options.initError and 1 or 0))
        if mode~="native" then assert(warnings>0) end
    end
end
scenario("native")
scenario("invalid")
scenario("context",{expectHook=true})
scenario("legacy_text",{expectHook=true})
scenario("context",{noModules=true})
scenario("context",{badRequire="ChatConfiguration"})
scenario("context",{badRequire="ChatFilter"})
scenario("context",{names={}})
scenario("context",{names={42}})
scenario("context",{names={"RBXTeam"}})
scenario("context",{names={"rbxwhisper"}})
scenario("context",{names={"RBXGeneral","RBXGeneral"}})
scenario("context",{names={[1]="Match",[3]="Other"}})
scenario("context",{initError=true})
print("PASS: 14 bootstrap scenarios")
