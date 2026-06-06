-- ChatServer.lua (Script en ServerScriptService)
-- Versión Lite: usa ChatFilter directamente, sin ModerationManager.
-- El comando /report invita a adquirir la versión Pro.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local chatEvent = ReplicatedStorage:WaitForChild("ChatMessage", 5)

local ServerModules = ServerScriptService:WaitForChild("ServerModules", 5)
local ChatFilter = require(ServerModules:WaitForChild("ChatFilter", 5))

-- ================================================================
-- COMANDO /report (NO DISPONIBLE en versión Lite)
-- ================================================================
local function procesarComandoReport(player, mensaje)
	-- En la versión Lite, el sistema de reportes no está disponible.
	-- Invitamos al desarrollador a adquirir ModerationManager Pro.
	return "El sistema de reportes no está disponible en la versión gratuita. Adquiere ModerationManager Pro para activarlo."
end

-- ================================================================
-- PROCESAR MENSAJE DEL CLIENTE
-- ================================================================
chatEvent.OnServerEvent:Connect(function(player, mensaje)
	if not player or not player.Parent then return end

	-- Comando /report (no disponible en Lite)
	if type(mensaje) == "string" and string.sub(mensaje, 1, 7) == "/report" then
		local resultado = procesarComandoReport(player, mensaje)
		chatEvent:FireClient(player, resultado, "Sistema", true)
		return
	end

	-- Validar con ChatFilter Lite
	local esValido, resultado = ChatFilter.validarMensaje(player, mensaje)

	if not esValido then
		-- Mensaje bloqueado: notificar SOLO al remitente
		chatEvent:FireClient(player, resultado, "Sistema", true)
	else
		-- Mensaje válido: reenviar a TODOS los jugadores
		chatEvent:FireAllClients(resultado, player.Name, false)
	end
end)

print("[ChatServer] ChatFilter Lite activo. El chat de Roblox está desactivado.")
print("[ChatServer] Reportes no disponibles. Adquiere ModerationManager Pro para activarlos.")
