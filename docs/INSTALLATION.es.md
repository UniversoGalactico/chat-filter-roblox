# ChatFilter v2 — instalación y validación

**Estado: candidato experimental.** No se ha probado dentro de Roblox Studio ni con servicios reales. No uses esta versión como garantía de seguridad.

## Elegir modo

| Modo | Acceso al texto de chat | Qué añade |
|---|---|---|
| native (predeterminado) | Ninguno | Deja el chat nativo intacto. |
| context | Ninguno | Restricciones adicionales por canal, cuota y estado del juego; requiere validar el callback. |
| legacy_text | Solo antes de migrar al chat integrado | Reglas léxicas adicionales; modo transitorio. |

Roblox anunció la obligatoriedad del chat integrado de plataforma en mayo de 2027. Sus scripts no podrán leer el texto de mensajes integrado. No intentes recuperar ese texto mediante RemoteEvents, GUI personalizada u otros transportes.

El [anuncio de octubre de 2026](https://devforum.roblox.com/t/important-textchatservice-updates-how-to-test-and-what%E2%80%99s-next/4948433) también prevé listas de palabras bloqueadas por creadores mediante el filtro nativo para mayo de 2027. Es una función anunciada, no una API confirmada. Migra la lista léxica a la opción oficial cuando esté documentada, revisando falsos positivos; no hace falta reconstruir un transporte de chat.

## Migración desde v1

Trabaja primero en una copia privada del juego. Elimina los scripts originales ChatServer, ChatClient, InitChatClient y el RemoteEvent ChatMessage, además de cualquier otra interfaz de chat que reenvíe texto. Conserva los controles nativos de bloqueo, silencio y denuncia.

Para el modo native no necesitas instalar módulos de ChatFilter: basta con usar TextChatService nativo. Para experimentar con una política opcional, crea esta estructura manualmente en Studio:

```text
ServerScriptService
  ChatServer (Script)
  ServerModules (Folder)
    ChatConfiguration (ModuleScript)
    ChatFilter (ModuleScript)
    ContextPolicy (ModuleScript)
    DeliveryGate (ModuleScript)
    TextPolicy (ModuleScript; solo si usas reglas léxicas)
    ProfanityData (ModuleScript; solo si usas reglas léxicas)
```

Copia cada archivo del directorio server, sin la extensión .lua en el nombre de instancia. No instales los antiguos archivos de cliente: son avisos de migración, no una interfaz.

En ChatConfiguration, conserva Mode = "native" hasta comprobar que tu experiencia mantiene el chat nativo. Para probar context, selecciona únicamente canales cuyo callback poseas. No asignes este sistema sobre callbacks de otro módulo, ni sobre canales reservados de equipo o susurros.

## Integración manual

Si tu juego ya tiene un ShouldDeliverCallback, no actives el autoenlace de ChatServer en ese canal. Desde el único script responsable del callback, integra el predicado de ChatFilter junto con tus reglas existentes:

```lua
local modules = game:GetService("ServerScriptService").ServerModules
local ChatFilter = require(modules.ChatFilter)
local predicate, stop, snapshot = ChatFilter.CreatePredicate("context")

-- Ejemplo: channel y existingGameplayRule pertenecen a tu sistema servidor.
-- existingGameplayRule no debe ceder la ejecución ni autorizar por encima de Roblox.
channel.ShouldDeliverCallback = function(message, recipient)
    local ok, allowed = pcall(existingGameplayRule, message, recipient)
    return ok and allowed == true and predicate(message, recipient, channel)
end
script.Destroying:Connect(stop)
```

El predicado solo puede añadir restricciones; Roblox sigue siendo responsable de sus reglas de comunicación. El ejemplo no crea canales, no agrega participantes y no concede permisos. Las estadísticas de snapshot cuentan decisiones por destinatario, no jugadores únicos ni mensajes entregados.

Los cambios de configuración requieren reiniciar el servidor. No se admiten reemplazos de callbacks en caliente. Si eliminas un script con su callback aún instalado, el predicado queda cerrado; reinicia el servidor para volver al chat nativo.

## Pruebas de aceptación en Studio

Marca cada caso únicamente después de observarlo, con dos o tres clientes de prueba. No uses conversaciones reales para depurar.

- [ ] La interfaz, denuncia y bloqueo nativos siguen funcionando.
- [ ] El modo native no instala callbacks ni necesita los módulos léxicos.
- [ ] context funciona sin acceder al texto; si el callback no funciona con chat integrado, vuelve a native.
- [ ] Un permiso nativo denegado no se convierte en un permiso concedido.
- [ ] La cuota se aplica por mensaje, no por destinatario.
- [ ] Dos jugadores con el mismo grupo servidor pueden superar la regla de grupo; un tercero de otro grupo no. Al cambiar o quitar atributos, la regla cambia.
- [ ] Un jugador que abandona y vuelve recibe estado nuevo. Las entregas con TextSources retirados del canal se rechazan; verifica el comportamiento real de las fuentes de texto tras reconectar.
- [ ] Los canales reservados y los callbacks de otros sistemas no son reemplazados.
- [ ] Un canal retirado o renombrado no conserva un permiso del callback anterior.
- [ ] Si pruebas legacy_text con chat no integrado, un bloqueo impide la entrega a otros, aunque el remitente pueda ver su eco local.
- [ ] No existen RemoteEvents que reenvíen texto de conversación, ni logs con texto o identificadores de mensaje.

## Extensión opcional: etiquetas de objetos

PublicFieldPipeline y PublicFieldService son independientes y no se cargan automáticamente. Solo se destinan a nombres cortos de mascotas/objetos o etiquetas unidireccionales, nunca a mensajería, respuestas o sustitutos de chat. Debes autorizar el objeto en el servidor, usar el mismo límite global en toda la experiencia y volver a validar jugador, objeto, propietario y generación al recibir el resultado filtrado.

No se permite presentar la entrada sin filtrar si MemoryStore o TextService fallan. No interpretes el retorno de Request como aprobación: solo indica que se programó el trabajo.

Comprueba con una experiencia privada publicada que el límite funciona entre servidores, que un fallo del filtro no cambia la etiqueta, que una solicitud antigua no sobrescribe una nueva generación de objeto y que la cancelación de quien solicita no deja bloqueado el módulo.

## Fuentes y límites

- [Chat guidelines](https://create.roblox.com/docs/chat/guidelines)
- [Platform-integrated chat](https://create.roblox.com/docs/chat/platform-integrated-chat)
- [TextChannel](https://create.roblox.com/docs/reference/engine/classes/TextChannel)
- [Pruebas automatizadas](../tests/README.md) y [modelo de seguridad](../SECURITY.md).

Las pruebas de Lua y Luau verifican algoritmos y simulaciones. No sustituyen las pruebas multijugador de Studio, los permisos de plataforma, la moderación de Roblox o una revisión de falsos positivos en tu juego.
