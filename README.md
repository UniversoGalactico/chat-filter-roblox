# RemoteGuardRoblox

A small server-side admission gate for client-triggered game actions. **1.0.0-rc.1** — candidate, MIT, no runtime dependencies.

Formerly ChatFilter. This is a deliberate redesign, not an upgrade to its chat API. Native Roblox chat needs no additional filter. Historical implementations remain in Git history and the prior development branch.

## Start

Install [RemoteGuardRoblox.lua](RemoteGuardRoblox.lua) in ServerScriptService as `RemoteGuard`.

```lua
local RemoteGuard = require(game.ServerScriptService.RemoteGuard)
local gate = RemoteGuard.new({
    Global = {Limit = 20, Window = 1},
    Actions = {
        Buy = {
            Quota = {Limit = 3, Window = 1},
            Args = {{Type = "string", MaxBytes = 64}},
            Authorize = function(player, itemId)
                return player:GetAttribute("ShopOpen") == true
            end,
        },
    },
})

remote.OnServerEvent:Connect(function(player, itemId)
    if not gate:Check(player, "Buy", itemId) then return end
    -- Server must still verify inventory, price, balance, distance and transaction rules.
end)
game:GetService("Players").PlayerRemoving:Connect(function(player)
    gate:Forget(player)
end)
```

Use a server-owned player identity and a fixed server-selected action name. Forward all client arguments with `...` when exact arity matters. The gate never installs callbacks or runs a gameplay handler.

[API and limitations](docs/API.md) · [Tests](docs/TESTING.md) · [Integration example](examples/Remote.server.lua) · [AI guide](AGENTS.md)

Not an anti-cheat, remote firewall, transaction manager or authorization substitute. It only admits requests for further server-side processing. Follow [Roblox client-server security guidance](https://create.roblox.com/docs/scripting/security/client-server-boundary).

MIT — [LICENSE](LICENSE).
