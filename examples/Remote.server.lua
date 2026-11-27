-- Create a RemoteEvent named BuyItem under ReplicatedStorage first.
local Players=game:GetService("Players")
local remote=game:GetService("ReplicatedStorage"):WaitForChild("BuyItem")
local RemoteGuard=require(game.ServerScriptService.RemoteGuard)
local guard=RemoteGuard.new({
 Global={Limit=20,Window=1},
 Actions={Buy={Quota={Limit=3,Window=1},Args={{Type="string",MaxBytes=64}},
  Authorize=function(player,itemId)
   return player.Parent==Players and player:GetAttribute("ShopOpen")==true
  end}},
})
remote.OnServerEvent:Connect(function(player,...)
 if not guard:Check(player,"Buy",...) then return end
 local itemId=...
 -- Integrate your authoritative shop transaction here. This example grants nothing.
end)
Players.PlayerRemoving:Connect(function(player) guard:Forget(player) end)
