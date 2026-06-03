-- ModerationManager.lua (Módulo de servidor)
-- Responsabilidad única: Gestionar sanciones, silencios, reportes y auditoría.
-- Delegación de configuración a ChatConfig.

local ModerationManager = {}
local Players = game:GetService("Players")

-- Dependencia
local ChatConfig = require(script.Parent:WaitForChild("ChatConfig", 5))

-- ================================================================
-- ESTADO PRIVADO (por sesión)
-- ================================================================
local sanciones = {}
local jugadoresSilenciados = {}
local historial = {}
local reportesPendientes = {}

-- ================================================================
-- UTILIDADES PRIVADAS
-- ================================================================
local function agregarAlLog(entry)
	if #historial >= ChatConfig.MAX_LOG_SIZE then
		table.remove(historial, 1)
	end
	entry.timestamp = os.time()
	table.insert(historial, entry)
end

local function aplicarSilencio(player, segundos)
	if not player or not player.Parent then return end
	jugadoresSilenciados[player.UserId] = os.time() + segundos
end

-- ================================================================
-- API PÚBLICA
-- ================================================================

function ModerationManager.estaSilenciado(player)
	if not player or not player.Parent then return false end
	local timestamp = jugadoresSilenciados[player.UserId]
	return timestamp and os.time() < timestamp
end

function ModerationManager.tiempoRestante(player)
	if not player or not player.Parent then return 0 end
	local timestamp = jugadoresSilenciados[player.UserId]
	if timestamp and os.time() < timestamp then
		return timestamp - os.time()
	end
	return 0
end

function ModerationManager.aplicarSancion(player)
	if not player or not player.Parent then return 0 end
	local userId = player.UserId

	if not sanciones[userId] then
		sanciones[userId] = { strikes = 0 }
	end
	local sancion = sanciones[userId]
	sancion.strikes += 1

	if sancion.strikes >= ChatConfig.MAX_STRIKES then
		agregarAlLog({ tipo = "kick", userId = userId, strikes = sancion.strikes })
		sanciones[userId] = nil
		jugadoresSilenciados[userId] = nil
		reportesPendientes[userId] = nil
		player:Kick("Has sido expulsado por múltiples infracciones.")
		return sancion.strikes
	end

	local tiempoSilencio = ChatConfig.TIEMPO_SILENCIO_BASE * sancion.strikes
	aplicarSilencio(player, tiempoSilencio)

	agregarAlLog({
		tipo = "strike",
		userId = userId,
		strikes = sancion.strikes,
		duracion = tiempoSilencio
	})

	return sancion.strikes
end

function ModerationManager.reportarJugador(reportero, reportado)
	if not reportero or not reportado then return "Jugador inválido." end
	if not reportero.Parent or not reportado.Parent then return "Jugador desconectado." end
	if reportero.UserId == reportado.UserId then return "No puedes reportarte a ti mismo." end

	local repId = reportado.UserId
	local rerId = reportero.UserId

	if not reportesPendientes[repId] then
		reportesPendientes[repId] = { reporteros = {} }
	end

	for _, r in ipairs(reportesPendientes[repId].reporteros) do
		if r == rerId then
			return "Ya has reportado a este jugador."
		end
	end

	table.insert(reportesPendientes[repId].reporteros, rerId)
	agregarAlLog({ tipo = "reporte", reportero = rerId, reportado = repId })

	local sancion = sanciones[repId]
	local strikesReportado = sancion and sancion.strikes or 0

	if strikesReportado >= 1 then
		local reportesNecesarios = ChatConfig.MAX_REPORTES_PARA_KICK - strikesReportado
		local reportesRecibidos = #reportesPendientes[repId].reporteros

		if reportesRecibidos >= reportesNecesarios then
			agregarAlLog({ tipo = "kick_por_reportes", userId = repId, strikes = strikesReportado })
			sanciones[repId] = nil
			jugadoresSilenciados[repId] = nil
			reportesPendientes[repId] = nil
			reportado:Kick("Has sido expulsado por múltiples reportes de la comunidad.")
			return reportado.Name .. " ha sido expulsado."
		else
			return "Reporte registrado. Se necesitan " .. (reportesNecesarios - reportesRecibidos) .. " reportes más para actuar."
		end
	else
		warn("[ModerationManager] " .. reportero.Name .. " hizo un falso reporte contra " .. reportado.Name)
		aplicarSilencio(reportero, ChatConfig.TIEMPO_SILENCIO_FALSO_REPORTE)
		agregarAlLog({ tipo = "silencio_por_falso_reporte", userId = rerId })
		return "Tu reporte fue considerado falso. Has sido silenciado por " .. ChatConfig.TIEMPO_SILENCIO_FALSO_REPORTE .. " segundos."
	end
end

function ModerationManager.obtenerLog()
	local copia = {}
	for i, entry in ipairs(historial) do
		copia[i] = entry
	end
	return copia
end

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	sanciones[userId] = nil
	jugadoresSilenciados[userId] = nil
	reportesPendientes[userId] = nil
end)

return ModerationManager
