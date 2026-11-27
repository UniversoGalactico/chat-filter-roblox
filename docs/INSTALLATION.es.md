# ChatFilter: instalar y probar

Si solo querés el chat nativo, no instales nada. Esta biblioteca añade restricciones opcionales a canales propios.

## Prueba rápida

1. Descargá [ChatFilterTest.rbxmx](../tests/studio/ChatFilterTest.rbxmx) e importalo en ServerScriptService de un lugar vacío privado (clic derecho, Insert from File).
2. Presioná F5. En Output del servidor debería aparecer PASS: 7 local checks. Esto comprueba módulos, no entrega de chat.
3. Para probar entrega: detené la sesión, habilitá ChannelTabsConfiguration.Enabled en TextChatService y arrancá Test > Server & Clients con 2 clientes. Elegí ChatFilterTest y enviá un mensaje inocuo desde A. B no debería recibirlo.
4. En Explorer del servidor cambiá ChatFilterTestGroup del segundo jugador a A y repetí. Comprobá visualmente la entrega, sujeta a permisos nativos. Cambiá el atributo ShowCounts del Script Smoke para ver contadores.
5. Detené y quitá el modelo de ensayo. Si el canal o callback no está disponible, no declares aprobada la integración.

En chat integrado puede ser necesario el TextChannelWindow oficial dirigido al canal de prueba. No intentes eludir permisos. El ensayo aún no se ejecutó en Studio.

## Usar en tu juego

Instalá solo ChatFilter, DeliveryGate y ContextPolicy como ModuleScripts hermanos en ServerScriptService.

```lua
local ChatFilter = require(script.Parent.ChatFilter)
local policy = ChatFilter.new({MessagesPerSecond = 3})
channel.ShouldDeliverCallback = policy:ForChannel(channel)
script.Destroying:Connect(function() policy:Destroy() end)
```

channel tiene que ser un TextChannel propio con único responsable del callback. Si ya tiene reglas, combinalas en ese mismo callback. No se leen mensajes por defecto. Reiniciá el servidor para cambiar la configuración. LegacyText=true es transitorio y requiere tres módulos adicionales; no se usa con chat integrado.

[Pruebas](../tests/README.md) · [Seguridad](../SECURITY.md) · [Auditoría](AUDIT.md).
