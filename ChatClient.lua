-- ChatClient.lua (ModuleScript en ReplicatedStorage.ClientModules)
-- Responsabilidad única: Construir la interfaz de chat y manejar la comunicación con el servidor.
-- El chat de Roblox queda desactivado.

local ChatClient = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencias
local chatEvent = ReplicatedStorage:WaitForChild("ChatMessage", 5)

-- Estado interno
local player = nil
local screenGui = nil
local scrollFrame = nil
local uiListLayout = nil
local textBox = nil

-- Mostrar un mensaje en el área de chat
local function mostrarMensaje(nombre, texto, esSistema)
	local label = Instance.new("TextLabel")
	label.Text = ""
	label.Font = Enum.Font.SourceSans
	label.TextSize = 16
	label.TextWrapped = true
	label.BackgroundTransparency = 1
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

-- Enviar mensaje al servidor
local function enviarMensaje(mensaje)
	if mensaje == "" then return end
	chatEvent:FireServer(mensaje)
	textBox.Text = ""
end

-- Construir la GUI del chat
local function construirGUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ChatGUI"
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- Frame contenedor
	local chatFrame = Instance.new("Frame")
	chatFrame.Name = "ChatFrame"
	chatFrame.Size = UDim2.new(0, 400, 0, 300)
	chatFrame.Position = UDim2.new(0, 10, 0.5, -150)
	chatFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	chatFrame.BackgroundTransparency = 0.7
	chatFrame.BorderSizePixel = 0
	chatFrame.Parent = screenGui

	-- Área de mensajes (ScrollingFrame)
	scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ScrollFrame"
	scrollFrame.Size = UDim2.new(1, -10, 1, -50)
	scrollFrame.Position = UDim2.new(0, 5, 0, 5)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.Parent = chatFrame

	uiListLayout = Instance.new("UIListLayout")
	uiListLayout.Parent = scrollFrame

	-- Campo de entrada
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

	-- Detectar Enter en el TextBox
	textBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			enviarMensaje(textBox.Text)
		end
	end)

	-- Recibir mensajes del servidor
	chatEvent.OnClientEvent:Connect(function(mensaje, nombreRemitente, esSistema)
		mostrarMensaje(nombreRemitente or "Sistema", mensaje, esSistema)
	end)

	-- Mensaje de bienvenida
	mostrarMensaje("Sistema", "Chat blindado activo. Sé respetuoso.", true)

	-- Desactivar el chat por defecto de Roblox
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
end

-- Inicializar el módulo
function ChatClient.Iniciar(gui)
	player = Players.LocalPlayer
	construirGUI()
end

return ChatClient
