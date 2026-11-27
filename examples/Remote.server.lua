-- Two ModuleScripts (RemoteGuard, RemoteGuardServer) in ServerScriptService.
-- Create an owned RemoteEvent "BuyItem" in ReplicatedStorage.
local RemoteGuardServer=require(game.ServerScriptService.RemoteGuardServer)
local remote=game:GetService("ReplicatedStorage"):WaitForChild("BuyItem")
local guard=RemoteGuardServer.new({
 Global={Limit=20,Window=1},Server={Limit=300,Window=1},
 Actions={Buy={Quota={Limit=3,Window=1},Args={{Type="string",MaxBytes=64}},
  Authorize=function(player)return player:GetAttribute("ShopOpen")==true end}},
})
local connection=remote.OnServerEvent:Connect(guard:Wrap("Buy",function(player,_,itemId)
 -- Perform a synchronous authoritative shop transaction here.
 -- Verify actual price, balance, stock, distance, ownership and current state.
 -- No grants or simulated economy in this example.
end))
local function stop()
 connection:Disconnect();guard:Destroy()
end
-- Call stop from your match/application owner's explicit teardown.
