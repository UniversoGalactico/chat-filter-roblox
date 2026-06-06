-- IniciarChat.lua (LocalScript en StarterGui)
-- Responsabilidad única: Iniciar el módulo ChatClient.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChatClient = require(ReplicatedStorage.ClientModules:WaitForChild("ChatClient", 5))
ChatClient.Iniciar(script.Parent)
