-- ChatFilter.lua | Versión Lite (Gratuita)
-- Doble capa: TextService (Roblox) + Sistema propio (normalización, Levenshtein, emojis).
-- Sin dependencia de ModerationManager. Solo devuelve válido/inválido.

local ChatFilter = {}
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local ChatConfig = require(script.Parent:WaitForChild("ChatConfig", 5))
local ProfanityData = require(script.Parent:WaitForChild("ProfanityData", 5))

-- Estado privado (rate limiting)
local peticionesPorJugador = {}

-- Normalización: traduce emojis, minúsculas, colapsa espacios, números a letras, elimina símbolos
local function normalizar(texto)
	local t = texto
	for emoji, traduccion in pairs(ProfanityData.EMOJI_A_TEXTO) do
		t = string.gsub(t, emoji, " " .. traduccion .. " ")
	end
	t = string.lower(t)
	t = string.gsub(t, "%s+", " ")
	t = string.gsub(t, "3", "e"); t = string.gsub(t, "4", "a")
	t = string.gsub(t, "1", "i"); t = string.gsub(t, "0", "o")
	t = string.gsub(t, "5", "s"); t = string.gsub(t, "7", "t")
	t = string.gsub(t, "[^%a%s]", "")
	return t
end

-- Distancia de Levenshtein
local function distanciaLevenshtein(s, t)
	local s_len, t_len = #s, #t
	if s_len == 0 then return t_len end
	if t_len == 0 then return s_len end
	local d = {}
	for i = 0, s_len do d[i] = {[0] = i} end
	for j = 0, t_len do d[0][j] = j end
	for i = 1, s_len do
		for j = 1, t_len do
			local cost = s:sub(i,i) == t:sub(j,j) and 0 or 1
			d[i][j] = math.min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
		end
	end
	return d[s_len][t_len]
end

-- Rate limiting
local function esPeticionExcesiva(userId)
	local now = os.clock()
	peticionesPorJugador[userId] = peticionesPorJugador[userId] or {}
	local timestamps = peticionesPorJugador[userId]
	local i = 1
	while timestamps[i] and (now - timestamps[i]) > 1.0 do
		table.remove(timestamps, i)
	end
	if #timestamps >= ChatConfig.MAX_MENSAJES_POR_SEGUNDO then return true end
	table.insert(timestamps, now)
	return false
end

-- Detecta el símbolo ~ como intento de simular gemidos
local function contieneGemido(mensaje)
	if string.find(mensaje, "~") then
		return true
	end
	return false
end

-- Verifica frases prohibidas en el mensaje normalizado
local function contieneFraseProhibida(mensajeNormalizado)
	for _, lista in pairs(ProfanityData.FRASES_PROHIBIDAS) do
		for _, frase in ipairs(lista) do
			if string.find(mensajeNormalizado, frase, 1, true) then
				return true
			end
		end
	end
	return false
end

-- Verifica si una palabra normalizada es un insulto
local function esInsulto(palabraNormalizada)
	local len = #palabraNormalizada

	-- Verificar abreviaturas cortas ofensivas (sin límite de longitud)
	for _, abrev in ipairs(ProfanityData.ABREVIATURAS_OFENSIVAS) do
		if palabraNormalizada == abrev then
			return true
		end
	end

	-- Ignorar palabras de menos de 4 caracteres para evitar falsos positivos
	if len < 4 then return false end
	if len > ChatConfig.MAX_PALABRA_LENGTH then return false end

	-- Lista blanca: palabras inocentes que NUNCA se bloquean
	for _, inocente in ipairs(ProfanityData.PALABRAS_INOCENTES) do
		if palabraNormalizada == inocente then
			return false
		end
	end

	-- Buscar en listas de insultos
	for _, listaIdioma in pairs(ProfanityData.INSULTOS) do
		for _, insulto in ipairs(listaIdioma) do
			if palabraNormalizada == insulto then return true end
			local diff = math.abs(len - #insulto)
			if diff <= ChatConfig.LEVENSHTEIN_DIFF_MAX and
				distanciaLevenshtein(palabraNormalizada, insulto) <= ChatConfig.LEVENSHTEIN_UMBRAL then
				return true
			end
		end
	end
	return false
end

-- ================================================================
-- API PÚBLICA (VERSIÓN LITE - Solo filtra, no sanciona)
-- ================================================================

function ChatFilter.validarMensaje(player, mensaje)
	-- Validaciones defensivas
	if not player or not player.Parent then
		return false, "Jugador inválido."
	end
	if type(mensaje) ~= "string" or #mensaje > ChatConfig.MAX_MENSAJE_LENGTH then
		return false, "Mensaje no válido."
	end

	-- CAPA 1: Roblox (FilterStringAsync)
	local exitoRoblox, resultadoRoblox = pcall(function()
		return TextService:FilterStringAsync(mensaje, player.UserId)
	end)

	if exitoRoblox and resultadoRoblox then
		local mensajeFiltradoRoblox = resultadoRoblox:GetNonChatStringForBroadcastAsync()
		if mensajeFiltradoRoblox ~= mensaje then
			-- Roblox detectó contenido inapropiado
			print("[ChatFilter] CAPA 1 (Roblox): Mensaje bloqueado de " .. player.Name)
			return false, "Tu mensaje fue bloqueado por el sistema de seguridad."
		end
	end
	-- Si falla FilterStringAsync (error de red), dejamos pasar a la Capa 2

	-- CAPA 2: Sistema propio (gemidos, rate limiting, insultos)
	if contieneGemido(mensaje) then
		print("[ChatFilter] CAPA 2: Gemido detectado de " .. player.Name)
		return false, "Tu mensaje contiene símbolos no permitidos."
	end

	if esPeticionExcesiva(player.UserId) then
		print("[ChatFilter] CAPA 2: Rate limiting activado para " .. player.Name)
		return false, "Demasiados mensajes. Espera un momento."
	end

	if ChatFilter.contieneInsulto(mensaje) then
		print("[ChatFilter] CAPA 2: Insulto detectado de " .. player.Name)
		return false, "Tu mensaje contiene lenguaje inapropiado."
	end

	-- Si pasó ambas capas, el mensaje es válido
	return true, mensaje
end

function ChatFilter.contieneInsulto(mensaje)
	if type(mensaje) ~= "string" or #mensaje > ChatConfig.MAX_MENSAJE_LENGTH then return false end
	if contieneGemido(mensaje) then return true end
	local normalizado = normalizar(mensaje)
	if contieneFraseProhibida(normalizado) then return true end
	for palabra in string.gmatch(normalizado, "%S+") do
		if esInsulto(palabra) then return true end
	end
	return false
end

Players.PlayerRemoving:Connect(function(player)
	peticionesPorJugador[player.UserId] = nil
end)

return ChatFilter
