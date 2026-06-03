-- ChatConnector.lua (Módulo de servidor)
-- Responsabilidad única: Conectar el sistema de chat con el juego.
-- Fachada que unifica ChatFilter + ModerationManager + ProfanityData + ChatConfig.

local ChatConnector = {}

-- Dependencias internas
local ChatFilter = require(script.Parent:WaitForChild("ChatFilter", 5))
local ModerationManager = require(script.Parent:WaitForChild("ModerationManager", 5))

-- Procesa un mensaje de chat completo.
-- Retorna el mensaje si es válido, o nil y un mensaje de error si fue bloqueado.
function ChatConnector.procesarMensaje(player, mensaje)
	if not player or not player.Parent then
		return nil, "Jugador inválido."
	end
	local resultado, errorMsg = ChatFilter.validarMensaje(player, mensaje)
	if not resultado then
		return nil, errorMsg
	end
	return resultado, nil
end

-- Reporta a un jugador (para comandos como /reportar)
function ChatConnector.reportarJugador(reportero, reportado)
	return ModerationManager.reportarJugador(reportero, reportado)
end

-- Obtiene el log de auditoría (para moderadores)
function ChatConnector.obtenerLog()
	return ModerationManager.obtenerLog()
end

-- Verifica si un jugador está silenciado
function ChatConnector.estaSilenciado(player)
	return ModerationManager.estaSilenciado(player)
end

return ChatConnector
