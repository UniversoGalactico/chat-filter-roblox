-- Example of a bounded yielding RemoteFunction; no real persistence or grants.
-- Create an owned RemoteFunction "LoadPreview" under ReplicatedStorage.
local RemoteGuardServer=require(game.ServerScriptService.RemoteGuardServer)
local remote=game:GetService("ReplicatedStorage"):WaitForChild("LoadPreview")
local guard=RemoteGuardServer.new({
 Global={Limit=10,Window=1},Server={Limit=100,Window=1},MaxInFlight=16,MaxInFlightPerSubject=2,
 Actions={Preview={Quota={Limit=2,Window=1},MaxInFlight=1,Args={{Type="string",Choices={"Default","Blue"}}}}},
})
remote.OnServerInvoke=guard:Wrap("Preview",function(player,token,skinId)
 -- Example asynchronous read; substitute an actual bounded server operation.
 task.wait(0.05)
 if not guard:IsCurrent(token) then return false,"Unavailable" end
 -- Revalidate real game permission and resources here before any mutation.
 -- Wrapper prepends true to these domain results; no private data returned.
 return true,skinId
end)
-- Application owner periodically calls guard:Sweep() from its existing loop
-- and guard:Destroy() at explicit teardown. Only the owning script assigns
-- OnServerInvoke. A retained callback denies after Destroy.
