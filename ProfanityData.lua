-- ProfanityData.lua (Módulo de servidor)
-- Responsabilidad única: Proveer listas de palabras, frases y emojis censurables.
-- Sin lógica. Solo datos organizados por idioma.

local ProfanityData = {}

-- Emojis de connotación sexual o insultiva (solo los más usados)
ProfanityData.EMOJI_A_TEXTO = {
	["🍆"] = "berenjena",   -- pene
	["🍒"] = "cereza",      -- senos
	["🍑"] = "melocoton",   -- trasero
	["💦"] = "semen",       -- líquido seminal
	["🥵"] = "excitado",    -- cara de calor/agitado
	["🤬"] = "insulto",     -- cara con símbolos en la boca
	["🍌"] = "platano",     -- pene
	["🍈"] = "melon",       -- senos
	["🍓"] = "fresa",       -- contexto sexual
	["🖕"] = "dedo_medio",  -- insulto directo
}

-- Palabras prohibidas por idioma
ProfanityData.INSULTOS = {
	es = {
		-- Leves
		"tonto", "bobo", "feo", "gordo", "flojo", "lento", "raro", "loco", "pesado", "torpe",
		"bruto", "payaso", "chismoso", "mentiroso", "envidioso", "sucio", "aburrido", "debil", "ridiculo", "inmaduro",
		-- Graves
		"idiota", "imbecil", "estupido", "tarado", "mogolico", "subnormal", "anormal", "enfermo", "inutil",
		"basura", "escoria", "mierda", "cagada", "pendejo", "boludo", "pelotudo", "gilipollas", "cabron", "puto",
		"maricon", "zorra", "perra", "cerdo", "rata", "sabandija",
		-- Muy graves
		"muerte", "matar", "asesino", "violador", "pedofilo", "terrorista", "nazi", "racista", "xenofobo", "homofobo",
		"machista", "suicidate", "desaparece", "explota", "quema", "ahorca", "dispara", "apunala", "envenena",
		"secuestra", "tortura", "genocidio", "holocausto", "bomba", "ataque", "masacre",
		-- Abreviaturas y jerga
		"mrd", "ptm", "ctm", "hdp", "qlero", "kl", "kk", "caca", "culo", "pedo", "pis", "vomito", "moco",
		"sangre", "muerto", "cadaver", "infierno", "diablo", "maldito", "condenado", "demonio",
		"ponerla", "chinga", "joder", "coño", "hostia", "miercoles", "carajo",
		"korer", "coger", "chupar", "mamar", "follar", "culear", "singar", "garchar",
		-- Traducciones de emojis
		"berenjena", "cereza", "melocoton", "semen", "excitado", "platano", "melon", "fresa", "dedo_medio",
		-- NUEVO: Palabras para detección de gemidos y acoso
		"gemido", "gimiendo",
		-- NUEVO: Descripciones sexuales
		"cogeria", "cogerme", "cogerte", "cogerse", "coges", "culear", "culeas", "culeamos",
		"singar", "singas", "singamos", "garchar", "garchas", "garchamos",
	},
	en = {
		"stupid", "idiot", "dumb", "ugly", "fat", "loser", "noob", "trash", "garbage",
		"moron", "imbecile", "retard", "asshole", "bastard", "bitch", "whore", "slut", "fag",
		"nigger", "chink", "spic", "kike", "terrorist", "nazi", "kill", "murder", "bomb", "attack",
		"rape", "pedo", "suicide", "kys", "wtf", "stfu",
		"fuck", "suck", "dick", "pussy", "cock", "cunt", "masturbate", "ejaculate",
		"eggplant", "cherry", "peach", "semen", "excited", "banana", "melon", "strawberry", "middle_finger",
		-- NUEVO: Traducciones para gemidos y acoso
		"moan", "moaning", "groan", "groaning",
		"fucking", "fucked", "fucker", "motherfucker",
		"sucking", "sucked", "sucker",
	},
	pt = {
		"idiota", "imbecil", "estupido", "feio", "gordo", "nojento", "lixo", "merda",
		"bosta", "puta", "viado", "bicha", "macaco", "pobre", "favelado", "burro",
		"foder", "chupar", "mamar", "cagar", "buceta", "caralho",
		"berinjela", "cereja", "pessego", "semen", "excitado", "banana", "melao", "morango", "dedo_medio",
		-- NUEVO: Traducciones para gemidos y acoso
		"gemido", "gemendo", "geme", "gemer",
		"fodendo", "fodido", "fodedor",
	},
}

-- Frases prohibidas por idioma
ProfanityData.FRASES_PROHIBIDAS = {
	es = {
		-- Amenazas y acoso grave
		"te voy a matar", "ojala te mueras", "eres un inutil", "vas a ver", "te voy a encontrar",
		"te la pongo a tu", "me cago en tu", "hijo de puta", "hijo de perra",
		"lamela", "mamala", "te voy a violar", "te voy a romper", "te voy a partir",
		
		-- Frases concatenadas (evasión por falta de espacios)
		"tevoyamatar", "tevoyaviolar", "tevoyarobartodo", "tevoyacoger",
		"quierofollarte", "quierocogerte", "quieroviolarte",
		"chupame", "chupala", "chupenme", "chupenla",
		"ojalatepasealgo", "ojalatemuera", "ojalatepase",
		
		"chupame", "chupala", "chupenme", "chupenla",
		-- Acoso sexual contextual y frases depredadoras
		"me cogeria a", "me cogeria a tu", "me cogeria a la", "me cogeria al",
		"que rica esta", "que rico esta", "que buenota esta", "que buenote esta",
		"te voy a coger", "te voy a follar", "te voy a violar",
		"quiero cogerme a", "quiero cogerme al", "quiero follarme a",
		"me la pones dura", "me pones duro", "me mojas", "me pones caliente",
		"tienes novia", "tienes novio", "cuantos anos tienes", "donde vives",
		-- Frases de gemidos simulados
		"ah~", "oh~", "uh~", "mmm~", "si~", "ahi~", "aqui~",
		},
	en = {
		-- Amenazas y acoso grave
		"i will kill you", "i hope you die", "you are useless", "i will find you",
		"i will rape you", "i will break you", "suck my", "lick my", "fuck your", "kill yourself",
		-- Acoso sexual contextual y frases depredadoras
		"i would fuck", "i want to fuck", "i wanna fuck", "i would rape",
		"she is so hot", "he is so hot", "so sexy", "so fucking hot",
		"i want to cum", "i want to ejaculate", "i am so hard", "i am so wet",
		"do you have a boyfriend", "do you have a girlfriend", "how old are you", "where do you live",
		-- Frases de gemidos simulados
		"ah~", "oh~", "uh~", "mmm~", "yes~", "right there~",
	},
}

-- Abreviaturas cortas ofensivas que deben verificarse sin límite de longitud
ProfanityData.ABREVIATURAS_OFENSIVAS = {
	"hdp", "mrd", "ptm", "ctm", "kk", "kl",
	"kys", "wtf", "stfu",
	"kac", "kck",
}

-- Palabras inocentes que NUNCA deben ser bloqueadas (evita falsos positivos)
ProfanityData.PALABRAS_INOCENTES = {
	-- Frutas y verduras (contexto culinario)
	"cereza", "melocoton", "platano", "fresa", "melon", "sandia", "uvas", "manzana", "pera",
	"naranja", "limon", "kiwi", "mango", "papaya", "piña", "coco", "higo", "dátil", "granada",
	"berenjena", "pepino", "zanahoria", "calabaza", "tomate", "lechuga", "cebolla", "ajo",
	"pimiento", "brocoli", "coliflor", "esparrago", "alcachofa", "remolacha", "nabo", "rabano",
	-- Objetos cotidianos
	"mesa", "silla", "libro", "lapiz", "papel", "puerta", "ventana", "techo", "suelo",
	"cielo", "agua", "fuego", "tierra", "aire", "luz", "sombra", "reloj", "cuchara",
	"tenedor", "cuchillo", "plato", "vaso", "botella", "caja", "bolsa", "cable", "rueda",
	-- Interjecciones y expresiones comunes inofensivas
	"bro", "oe", "re", "si", "no", "eh", "ah", "oh", "uh", "ok", "xd", "lol", "lmao", "wow",
	"hey", "yo", "ya", "va", "ve", "vi", "vo", "tu", "mi", "su", "el", "la", "lo", "los", "las",
	"un", "una", "uno", "unos", "unas", "de", "del", "en", "con", "por", "para", "sin", "mas",
	"muy", "tan", "bien", "mal", "genio", "capo", "idolo", "titan", "bestia", "maquina", "crack",
}

return ProfanityData
