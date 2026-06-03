-- ChatServer.lua (Script en ServerScriptService)
-- Responsabilidad única: Recibir mensajes del cliente, validarlos con ChatConnector,
-- reenviarlos a todos si son válidos, o notificar solo al remitente si son bloqueados.
-- También maneja el comando /report.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- RemoteEvent para el chat propio
local chatEvent = ReplicatedStorage:WaitForChild("ChatMessage", 5)

-- Dependencia
local ServerModules = ServerScriptService:WaitForChild("ServerModules", 5)
local ChatConnector = require(ServerModules:WaitForChild("ChatConnector", 5))

-- ================================================================
-- COMANDO /report
-- ================================================================
local function procesarComandoReport(player, mensaje)
	local contenido = string.sub(mensaje, 9) -- "/report " tiene 8 caracteres
	if #contenido == 0 then
		return "Uso: /report [nombre del jugador] [motivo]"
	end

	local espacioPos = string.find(contenido, " ")
	local nombreReportado, motivo

	if espacioPos then
		nombreReportado = string.sub(contenido, 1, espacioPos - 1)
		motivo = string.sub(contenido, espacioPos + 1)
	else
		nombreReportado = contenido
		motivo = "Sin motivo especificado"
	end

	local reportado = Players:FindFirstChild(nombreReportado)
	if not reportado then
		return "Jugador '" .. nombreReportado .. "' no encontrado en el servidor."
	end

	-- Validar que no se reporte a sí mismo
	if reportado.UserId == player.UserId then
		return "No puedes reportarte a ti mismo."
	end

	-- Delegar al sistema de reportes
	return ChatConnector.reportarJugador(player, reportado)
end

-- ================================================================
-- PROCESAR MENSAJE DEL CLIENTE
-- ================================================================
chatEvent.OnServerEvent:Connect(function(player, mensaje)
	-- Validar que el jugador es válido
	if not player or not player.Parent then return end

	-- Verificar si es un comando /report
	if type(mensaje) == "string" and string.sub(mensaje, 1, 7) == "/report" then
		local resultado = procesarComandoReport(player, mensaje)
		chatEvent:FireClient(player, resultado, "Sistema", true)
		return
	end

	-- Validar con el sistema de chat
	local resultado, errorMsg = ChatConnector.procesarMensaje(player, mensaje)

	if not resultado then
		-- Mensaje bloqueado: notificar SOLO al remitente
		chatEvent:FireClient(player, errorMsg, "Sistema", true)
		-- El ChatConnector ya aplicó la sanción (strike, silencio, kick) automáticamente
	else
		-- Mensaje válido: reenviar a TODOS los jugadores
		chatEvent:FireAllClients(resultado, player.Name, false)
	end
end)

-- ================================================================
-- LIMPIEZA AL SALIR UN JUGADOR (opcional, el ModerationManager ya lo maneja)
-- ================================================================
Players.PlayerRemoving:Connect(function(player)
	-- El ModerationManager ya limpia sus datos al salir.
	-- Aquí podrías notificar a los demás jugadores si quisieras.
end)

print("[ChatServer] Sistema de chat propio activo. El chat de Roblox está desactivado.")
print("[ChatServer] Comandos disponibles: /report [nombre] [motivo]")
