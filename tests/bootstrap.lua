-- Roblox bootstrap mock: no actual platform filtering or delivery is simulated.
local function signal()
    local s = {handlers={}}
    function s:Connect(cb)
        local entry={cb=cb,active=true}
        self.handlers[#self.handlers+1]=entry
        return {Disconnect=function() entry.active=false end}
    end
    function s:Fire(value)
        for _, entry in ipairs(self.handlers) do if entry.active then entry.cb(value) end end
    end
    return s
end
local function scenario(mode, options)
    options=options or {}
    local folder={ChildAdded=signal(),ChildRemoved=signal(),children={}}
    function folder:GetChildren() return self.children end
    local function channel(name,class)
        local c={Name=name,Parent=folder}
        function c:IsA(wanted) return (class or "TextChannel")==wanted end
        folder.children[#folder.children+1]=c
        return c
    end
    local general=channel("RBXGeneral")
    local team=channel("RBXTeam")
    local impostor=channel("RBXGeneral","Folder")
    local calls, stopped, warnings=0,0,0
    local function callback() return true end
    local mods={
        ChatConfiguration={Mode=mode,ChannelNames=options.names or {"RBXGeneral"}},
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
        TextChatService={WaitForChild=function(_,name,timeout)
            assert(name=="TextChannels" and timeout==10)
            if options.noChannels then return nil end
            return folder
        end},
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
        assert(calls==1 and general.ShouldDeliverCallback==callback)
        assert(team.ShouldDeliverCallback==nil and impostor.ShouldDeliverCallback==nil)
        local dynamic=channel("RBXGeneral")
        folder.ChildAdded:Fire(dynamic)
        assert(dynamic.ShouldDeliverCallback==callback)
        local unrelated=channel("RBXWhisper")
        folder.ChildAdded:Fire(unrelated)
        assert(unrelated.ShouldDeliverCallback==nil)
        local detached=channel("RBXGeneral")
        detached.Parent=nil
        folder.ChildAdded:Fire(detached)
        assert(detached.ShouldDeliverCallback==nil)
        destroying:Fire()
        assert(stopped==1)
        local after=channel("RBXGeneral")
        folder.ChildAdded:Fire(after)
        assert(after.ShouldDeliverCallback==nil)
    else
        assert(general.ShouldDeliverCallback==nil and team.ShouldDeliverCallback==nil)
        assert(calls==(options.initError and 1 or 0))
        if mode~="native" then assert(warnings>0) end
    end
end
scenario("native")
scenario("invalid")
scenario("context",{expectHook=true})
scenario("legacy_text",{expectHook=true})
scenario("context",{noModules=true})
scenario("context",{noChannels=true})
scenario("context",{badRequire="ChatConfiguration"})
scenario("context",{badRequire="ChatFilter"})
scenario("context",{names={}})
scenario("context",{names={42}})
scenario("context",{initError=true})
print("PASS: 11 bootstrap scenarios")
