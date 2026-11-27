-- Handwritten, synthetic policy examples. No real conversations.
-- These test the intended default behavior, not prevalence, recall, or safety.
local Policy, config, data
if type(dofile)=="function" then
    Policy=dofile("server/TextPolicy.lua")
    config=dofile("server/ChatConfiguration.lua")
    data=dofile("server/ProfanityData.lua")
else
    Policy=require("../server/TextPolicy")
    config=require("../server/ChatConfiguration")
    data=require("../server/ProfanityData")
end
assert(config.EnableFuzzy==false,"default policy must remain exact-only")
local check=Policy.new(config,data)
local benign={
    es={
        "Hola equipo, ¿cómo están?", "¿Quién quiere jugar otra partida?",
        "Atacá al jefe, no al jugador.", "Necesito ayuda con la misión.",
        "El enemigo tiene poca vida.", "Cuidado con el fuego.",
        "No encontré la llave.", "Qué buena defensa, felicitaciones.",
        "El número de la sala es 12345.", "Tengo 15 monedas.",
        "Me eliminó el monstruo.", "Perdimos esta ronda.",
        "¡Vamos al castillo!", "El personaje se quedó sin energía.",
        "La mascota se llama Luna 🐱", "¿Podés cubrirme?",
        "No insultes a tus compañeros.", "Reportá el acoso.",
        "Si necesitás ayuda, hablá con un adulto de confianza.",
        "Este rompecabezas es difícil.", "Quiero elegir una clase distinta.",
        "Guardá tu progreso antes de salir.", "Vamos a jugar en equipo.",
        "El asistente nos dio una pista.", "La puerta está cerrada.",
        "El mapa es más grande que antes.", "El escudo protege del daño.",
        "El caballo se mueve de otra forma.", "La torre cuesta tres mil.",
        "Me gusta la música del juego.",
    },
    en={
        "Good game, everyone!", "Can you help me with the puzzle?",
        "Attack the boss, not the other player.", "I need a new shield.",
        "I lost that round.", "The monster has low health.",
        "Choose your class.", "The assistant gave us a hint.",
        "Pass the ball.", "Classic mode is fun.",
        "Save your progress.", "Let's try the next level.",
        "My pet is named Luna 🐱", "There are 20 coins left.",
        "The door is locked.", "Please respect the other players.",
        "Report harassment using the game tools.", "Talk to a trusted adult if you need help.",
        "Don't share personal information.", "Nice teamwork!",
        "The bridge is broken.", "Meet at the checkpoint.",
        "I need more energy.", "The game is hard but fair.",
        "You can heal your character.", "The enemy respawns.",
        "The red team won.", "Can we play again?",
        "I like the music.", "Thanks for your help!",
    },
    pt={
        "Olá equipe, tudo bem?", "Vamos jogar outra partida?",
        "Ataque o chefe, não o jogador.", "Preciso de ajuda na missão.",
        "O inimigo tem pouca vida.", "Cuidado com o fogo.",
        "Não encontrei a chave.", "Boa defesa, parabéns.",
        "O número da sala é 12345.", "Tenho 15 moedas.",
        "O monstro me eliminou.", "Perdemos esta rodada.",
        "Vamos ao castelo!", "O personagem ficou sem energia.",
        "Meu animal se chama Lua 🐱", "Você pode me ajudar?",
        "Não insulte seus colegas.", "Denuncie o assédio.",
        "Converse com um adulto de confiança se precisar.",
        "Esse quebra-cabeça é difícil.", "Quero escolher outra classe.",
        "Salve o progresso antes de sair.", "Vamos trabalhar juntos.",
        "O assistente nos deu uma dica.", "A porta está fechada.",
        "O mapa ficou maior.", "O escudo protege contra danos.",
        "O cavalo se move de outro jeito.", "A torre custa três mil.",
        "Gosto da música do jogo.",
    },
}
local benignCount=0
for language,examples in pairs(benign) do
    for index,message in ipairs(examples) do
        local allowed=check(message)
        assert(allowed==true,"benign fixture rejected: "..language.."/"..index)
        benignCount=benignCount+1
    end
end
-- Direct exact rules are also context-blind: quoting them for a report still matches.
local blocked={
    "idiota", "¿IDIOTA?", "imbécil", "estúpido", "pelotudo",
    "asshole", "bitch", "caralho", "buceta",
    "idiota🐱", "「idiota」", "ＩＤＩＯＴＡ",
    "No digas idiota", "The word idiot is not the configured token",
}
-- Last case is not a blocked rule: it documents the deliberately small vocabulary.
local expectedLast=true
for i,message in ipairs(blocked) do
    assert(check(message)==(i==#blocked and expectedLast or false),"direct fixture "..i)
end
-- Explicitly documented limitations: not a detector of intent or all insults.
local misses={"idiot","eres una mala persona","you are not welcome here"}
for i,message in ipairs(misses) do
    assert(check(message)==true,"review coverage change in limitation "..i)
end
print("PASS: "..benignCount.." benign multilingual examples; "..(#blocked-1).." direct matches; 4 documented non-matches")
