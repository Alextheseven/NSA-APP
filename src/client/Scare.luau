local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local Config = require(ReplicatedStorage:WaitForChild("DedhecPanel"):WaitForChild("Config"))

local BUILD_UP = 0.35
local FADE_OUT = 0.35
local SCANLINE_COUNT = 12
local HORROR_RED = Color3.fromRGB(200, 0, 18)
local GHOST_CYAN = Color3.fromRGB(0, 230, 255)

local Scare = {}

local playing = false
local random = Random.new()

local function headline(name: string, color: Color3, zIndex: number, parent: Instance): TextLabel
	return Ui.label({
		Name = name,
		Text = Config.Scare.Text,
		FontFace = Theme.Fonts.Horror,
		TextColor3 = color,
		TextTransparency = 1,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.42),
		ZIndex = zIndex,
		Parent = parent,
	}, Ui.new(Instance.new("UITextSizeConstraint"), { MaxTextSize = 240 }))
end

function Scare.play()
	if playing then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	playing = true

	local duration = math.max(Config.Scare.Duration, BUILD_UP + 0.2)

	local gui = Ui.new(Instance.new("ScreenGui"), {
		Name = "DedhecScare",
		DisplayOrder = 10000,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local backdrop = Ui.frame({
		Name = "Backdrop",
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = gui,
	})

	local flash = Ui.frame({
		Name = "Flash",
		BackgroundColor3 = HORROR_RED,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = gui,
	})

	local image: ImageLabel? = nil
	if Config.Scare.ImageId ~= "" then
		image = Ui.image({
			Name = "Image",
			Image = Config.Scare.ImageId,
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = gui,
		})
	end

	local scanlines: { Frame } = {}
	for index = 1, SCANLINE_COUNT do
		scanlines[index] = Ui.frame({
			Name = "Scanline",
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = 4,
			Parent = gui,
		})
	end

	local ghostCyan = headline("GhostCyan", GHOST_CYAN, 5, gui)
	local ghostRed = headline("GhostRed", HORROR_RED, 6, gui)
	local title = headline("Title", Color3.fromRGB(255, 236, 236), 7, gui)

	local sound: Sound? = nil
	if Config.Scare.SoundId ~= "" then
		sound = Ui.new(Instance.new("Sound"), {
			Name = "Sting",
			SoundId = Config.Scare.SoundId,
			Volume = Config.Scare.Volume,
			Parent = gui,
		})
	end

	gui.Parent = playerGui
	Ui.tween(backdrop, TweenInfo.new(0.06), { BackgroundTransparency = 0 })

	local elapsed = 0
	local revealed = false
	local connection: RBXScriptConnection? = nil

	local function jitter(label: TextLabel, strength: number, transparency: number)
		label.Position = UDim2.new(
			0.5,
			random:NextNumber(-strength, strength),
			0.5,
			random:NextNumber(-strength * 0.6, strength * 0.6)
		)
		label.Rotation = random:NextNumber(-2.5, 2.5)
		label.TextTransparency = transparency
	end

	local function finish()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		local fade = TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Ui.tween(backdrop, fade, { BackgroundTransparency = 1 })
		Ui.tween(flash, fade, { BackgroundTransparency = 1 })
		Ui.tween(title, fade, { TextTransparency = 1 })
		Ui.tween(ghostRed, fade, { TextTransparency = 1 })
		Ui.tween(ghostCyan, fade, { TextTransparency = 1 })
		if image then
			Ui.tween(image, fade, { ImageTransparency = 1 })
		end
		for _, line in scanlines do
			line.BackgroundTransparency = 1
		end
		task.delay(FADE_OUT, function()
			gui:Destroy()
			playing = false
		end)
	end

	connection = RunService.PreRender:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < BUILD_UP then
			return
		end
		if not revealed then
			revealed = true
			if sound then
				sound:Play()
			end
		end
		if elapsed >= duration then
			finish()
			return
		end

		local intensity = 1 - math.clamp((elapsed - BUILD_UP) / (duration - BUILD_UP), 0, 1) * 0.6
		flash.BackgroundTransparency = random:NextNumber(0.05, 0.75)
		backdrop.BackgroundColor3 = if random:NextNumber() < 0.15 then HORROR_RED else Theme.Colors.Black
		if image then
			image.ImageTransparency = random:NextNumber(0, 0.35)
		end
		jitter(title, 14 * intensity, 0)
		jitter(ghostRed, 26 * intensity, 0.3)
		jitter(ghostCyan, 30 * intensity, 0.45)
		for _, line in scanlines do
			line.Position = UDim2.fromScale(0, random:NextNumber())
			line.Size = UDim2.new(1, 0, 0, random:NextInteger(1, 6))
			line.BackgroundTransparency = random:NextNumber(0.55, 0.95)
		end
	end)
end

return Scare
