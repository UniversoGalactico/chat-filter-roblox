-- ChatClient.lua (ModuleScript en ReplicatedStorage.ClientModules)
-- Versión con DEBUG exhaustivo

local ChatClient = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- -------------------- DEPURACIÓN INICIAL --------------------
print("[ChatClient] === INICIANDO MÓDULO ===")
print("[ChatClient] Buscando RemoteEvent 'ChatMessage' en ReplicatedStorage...")

local chatEvent = nil
local success, err = pcall(function()
	chatEvent = ReplicatedStorage:WaitForChild("ChatMessage", 10) -- timeout 10s
end)

if not success or not chatEvent then
	warn("[ChatClient] ❌ ERROR: No se encontró 'ChatMessage'. Detalles:", err)
	return ChatClient  -- no se puede continuar
end

print("[ChatClient] ✅ RemoteEvent 'ChatMessage' encontrado:", chatEvent:GetFullName())

-- Estado interno
local player = nil
local screenGui = nil
local scrollFrame = nil
local uiListLayout = nil
local textBox = nil

-- -------------------- MOSTRAR MENSAJE --------------------
local function mostrarMensaje(nombre, texto, esSistema)
	local label = Instance.new("TextLabel")
	label.Font = Enum.Font.SourceSans
	label.TextSize = 16
	label.TextWrapped = true
	label.BackgroundTransparency = 1

	-- ESTAS DOS LÍNEAS SON LA CLAVE
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y

	label.Parent = scrollFrame

	if esSistema then
		label.Text = "[Sistema] " .. texto
		label.TextColor3 = Color3.fromRGB(255, 255, 0)
	else
		label.Text = nombre .. ": " .. texto
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	-- Ajustar CanvasSize y auto-scroll
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, uiListLayout.AbsoluteContentSize.Y + 10)
	scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.CanvasSize.Y.Offset)
end

-- -------------------- ENVIAR MENSAJE --------------------
local function enviarMensaje(mensaje)
	print("[ChatClient] ✉️ enviarMensaje llamado con:", mensaje)
	if mensaje == "" then
		print("[ChatClient] ⚠️ Mensaje vacío, no se envía.")
		return
	end

	if not chatEvent then
		warn("[ChatClient] ❌ chatEvent es nil, no se puede enviar.")
		return
	end

	print("[ChatClient] FireServer con mensaje:", mensaje)
	chatEvent:FireServer(mensaje)
	textBox.Text = ""
	print("[ChatClient] ✅ FireServer ejecutado, TextBox limpiado.")
end

-- -------------------- CONSTRUIR GUI --------------------
local function construirGUI()
	print("[ChatClient] 🏗️ construirGUI iniciado...")

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ChatGUI"
	screenGui.Parent = player:WaitForChild("PlayerGui")
	print("[ChatClient] ScreenGui creado.")

	local chatFrame = Instance.new("Frame")
	chatFrame.Name = "ChatFrame"
	chatFrame.Size = UDim2.new(0, 400, 0, 300)
	chatFrame.Position = UDim2.new(0, 10, 0.5, -150)
	chatFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	chatFrame.BackgroundTransparency = 0.7
	chatFrame.BorderSizePixel = 0
	chatFrame.Parent = screenGui
	print("[ChatClient] Frame creado.")

	scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ScrollFrame"
	scrollFrame.Size = UDim2.new(1, -10, 1, -50)
	scrollFrame.Position = UDim2.new(0, 5, 0, 5)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.Parent = chatFrame
	print("[ChatClient] ScrollingFrame creado.")

	uiListLayout = Instance.new("UIListLayout")
	uiListLayout.Parent = scrollFrame
	print("[ChatClient] UIListLayout creado.")

	textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.Size = UDim2.new(1, -10, 0, 40)
	textBox.Position = UDim2.new(0, 5, 1, -45)
	textBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	textBox.Font = Enum.Font.SourceSans
	textBox.TextSize = 16
	textBox.ClearTextOnFocus = false
	textBox.Text = ""
	textBox.Parent = chatFrame
	print("[ChatClient] TextBox creado.")

	-- Detectar Enter
	textBox.FocusLost:Connect(function(enterPressed)
		print("[ChatClient] 🔘 FocusLost - enterPressed:", enterPressed)
		if enterPressed then
			enviarMensaje(textBox.Text)
		end
	end)

	-- -------------------- CONEXIÓN DEL EVENTO --------------------
	print("[ChatClient] Conectando OnClientEvent...")
	chatEvent.OnClientEvent:Connect(function(mensaje, nombreRemitente, esSistema)
		print("[ChatClient] 📩 OnClientEvent recibido:")
		print("[ChatClient]    mensaje:", mensaje)
		print("[ChatClient]    nombreRemitente:", nombreRemitente)
		print("[ChatClient]    esSistema:", esSistema)
		mostrarMensaje(nombreRemitente or "Sistema", mensaje, esSistema)
	end)
	print("[ChatClient] ✅ OnClientEvent conectado.")

	-- Mensaje de bienvenida (sin depender del servidor)
	mostrarMensaje("Sistema", "Chat blindado activo. Sé respetuoso.", true)

	-- Desactivar chat de Roblox
	print("[ChatClient] Desactivando chat por defecto de Roblox...")
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	print("[ChatClient] ✅ Chat de Roblox desactivado.")
end

-- -------------------- INICIALIZACIÓN --------------------
function ChatClient.Iniciar(gui)
	print("[ChatClient] 🚀 Iniciar llamado. gui:", gui)
	player = Players.LocalPlayer
	if not player then
		warn("[ChatClient] ❌ No se pudo obtener LocalPlayer.")
		return
	end
	print("[ChatClient] ✅ LocalPlayer:", player.Name)
	construirGUI()
end

print("[ChatClient] === MÓDULO LISTO ===")

return ChatClient
