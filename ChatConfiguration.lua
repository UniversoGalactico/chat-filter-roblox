-- ChatConfig.lua (Módulo de servidor)
-- Responsabilidad única: Centralizar todas las constantes de configuración del sistema de chat.
-- Sin lógica. Solo parámetros ajustables.

local ChatConfig = {}

-- ================================================================
-- LÍMITES DE MENSAJES
-- ================================================================
ChatConfig.MAX_PALABRA_LENGTH = 20      -- Longitud máxima de una palabra para ser analizada
ChatConfig.MAX_MENSAJE_LENGTH = 1000    -- Longitud máxima de un mensaje completo
ChatConfig.MAX_MENSAJES_POR_SEGUNDO = 3 -- Rate limiting por jugador

-- ================================================================
-- SANCIONES PROGRESIVAS
-- ================================================================
ChatConfig.TIEMPO_SILENCIO_BASE = 10    -- Segundos del primer strike (se multiplica por el número de strike)
ChatConfig.MAX_STRIKES = 3              -- Cantidad de strikes antes del kick automático

-- ================================================================
-- AUDITORÍA
-- ================================================================
ChatConfig.MAX_LOG_SIZE = 200           -- Entradas máximas en el historial circular

-- ================================================================
-- REPORTES COMUNITARIOS
-- ================================================================
ChatConfig.MAX_REPORTES_PARA_KICK = 3   -- Reportes únicos necesarios para kickear a un infractor
ChatConfig.TIEMPO_SILENCIO_FALSO_REPORTE = 60 -- Segundos de silencio para quien hace un reporte falso

-- ================================================================
-- DISTANCIA DE LEVENSHTEIN
-- ================================================================
ChatConfig.LEVENSHTEIN_UMBRAL = 2       -- Distancia máxima permitida para considerar una palabra similar
ChatConfig.LEVENSHTEIN_DIFF_MAX = 2     -- Diferencia máxima de longitud para aplicar Levenshtein

return ChatConfig
