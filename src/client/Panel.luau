local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Components = require(script.Parent.Components)
local Dialog = require(script.Parent.Dialog)
local PlayerList = require(script.Parent.PlayerList)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local sharedFolder = ReplicatedStorage:WaitForChild("DedhecPanel")
local Config = require(sharedFolder:WaitForChild("Config"))
local Protocol = require(sharedFolder:WaitForChild("Protocol"))

type Tone = Protocol.Tone
type Tile = Components.Tile

type ActionView = {
	Id: string,
	Glyph: string,
	Title: string,
	Description: string,
	Tone: Color3,
}

export type Mount = {
	Request: RemoteFunction,
	Access: Protocol.Access,
}

local PRIMARY_ACTIONS: { ActionView } = {
	{
		Id = "Ban",
		Glyph = "⊘",
		Title = "Ban",
		Description = "Remove and block them from rejoining",
		Tone = Theme.Colors.Danger,
	},
	{
		Id = "Kick",
		Glyph = "➜",
		Title = "Kick",
		Description = "Disconnect them from this server",
		Tone = Theme.Colors.Warning,
	},
	{
		Id = "Scare",
		Glyph = "◉",
		Title = "Scare",
		Description = "Hit their screen with a jumpscare",
		Tone = Theme.Colors.Violet,
	},
	{
		Id = "More",
		Glyph = "⋯",
		Title = "More",
		Description = "Teleport, freeze, spectate and more",
		Tone = Theme.Colors.Neutral,
	},
}

local UTILITY_ACTIONS: { ActionView } = {
	{ Id = "Kill", Glyph = "✕", Title = "Kill", Description = "Reset their health", Tone = Theme.Colors.Danger },
	{ Id = "Freeze", Glyph = "✱", Title = "Freeze", Description = "Lock their movement", Tone = Theme.Colors.Ice },
	{ Id = "Bring", Glyph = "↙", Title = "Bring", Description = "Pull them to you", Tone = Theme.Colors.Success },
	{ Id = "Goto", Glyph = "↗", Title = "Go to", Description = "Teleport to them", Tone = Theme.Colors.Info },
	{ Id = "Respawn", Glyph = "↻", Title = "Respawn", Description = "Reload character", Tone = Theme.Colors.Warning },
	{
		Id = "Spectate",
		Glyph = "◎",
		Title = "Spectate",
		Description = "View their avatar",
		Tone = Theme.Colors.Violet,
	},
}

local RESPONSE_TONES: { [string]: Tone } = {
	Success = "Success",
	Warning = "Warning",
	Error = "Error",
}

local Panel = {}

function Panel.mount(mount: Mount)
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local layout = Theme.Layout
	local windowSize = layout.Window
	local margin = layout.ShadowMargin

	local isOpen = false
	local busy = false
	local selected: Player? = nil
	local spectating: Player? = nil
	local windowOffset = Vector2.zero
	local visibilityToken = 0
	local selectionConnections: { RBXScriptConnection } = {}
	local characterConnection: RBXScriptConnection? = nil
	local spectateConnections: { RBXScriptConnection } = {}
	local tiles: { [string]: Tile } = {}

	local screen = Ui.new(Instance.new("ScreenGui"), {
		Name = "DedhecPanel",
		DisplayOrder = 50,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local windowScale = Instance.new("UIScale")
	local window = Ui.new(Instance.new("CanvasGroup"), {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(windowSize.X + margin * 2, windowSize.Y + margin * 2),
		Visible = false,
		Parent = screen,
	}, windowScale)

	for layer = 1, 5 do
		local spread = layer * 4
		Ui.frame({
			Name = "Shadow",
			BackgroundColor3 = Theme.Colors.Black,
			BackgroundTransparency = 0.82 + layer * 0.03,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 6),
			Size = UDim2.fromOffset(windowSize.X + spread, windowSize.Y + spread),
			ZIndex = 0,
			Parent = window,
		}, Ui.corner(layout.Radius + 2 + spread / 2))
	end

	local surface = Ui.frame(
		{
			Name = "Surface",
			Active = true,
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(windowSize.X, windowSize.Y),
			ZIndex = 1,
			Parent = window,
		},
		Ui.corner(layout.Radius + 2),
		Ui.stroke(Theme.Colors.Stroke),
		Ui.gradient(ColorSequence.new(Theme.Colors.SurfaceTop, Theme.Colors.SurfaceBottom), 90)
	)

	Ui.frame(
		{
			Name = "Glow",
			BackgroundColor3 = Theme.Colors.Accent,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0.62, 0, 0, 2),
			ZIndex = 2,
			Parent = surface,
		},
		Ui.gradient(
			ColorSequence.new(Theme.Colors.White),
			0,
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
		)
	)

	local header = Ui.frame({
		Name = "Header",
		Active = true,
		Size = UDim2.new(1, 0, 0, layout.HeaderHeight),
		Parent = surface,
	})

	Ui.frame({
		Name = "Divider",
		BackgroundColor3 = Theme.Colors.Stroke,
		BackgroundTransparency = 0,
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = header,
	})

	local logo = Ui.frame({
		Name = "Logo",
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, layout.Gutter, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		Parent = header,
	}, Ui.corner(11), Ui.gradient(ColorSequence.new(Theme.Colors.AccentBright, Theme.Colors.AccentDeep), 45))
	Ui.label({
		Name = "Mark",
		Text = "D",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 22,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = logo,
	})

	Ui.label({
		Name = "Title",
		Text = string.format('DEDHEC <font color="%s">PANEL</font>', Ui.hex(Theme.Colors.Accent)),
		RichText = true,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 20,
		Position = UDim2.fromOffset(layout.Gutter + 52, 13),
		Size = UDim2.fromOffset(260, 22),
		Parent = header,
	})
	Ui.label({
		Name = "Subtitle",
		Text = "Server administration console",
		TextSize = 13,
		TextColor3 = Theme.Colors.TextMuted,
		Position = UDim2.fromOffset(layout.Gutter + 52, 35),
		Size = UDim2.fromOffset(260, 16),
		Parent = header,
	})

	local headerTools = Ui.frame({
		Name = "Tools",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -layout.Gutter, 0.5, 0),
		Size = UDim2.fromOffset(420, 36),
		Parent = header,
	}, Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center))

	Ui.label({
		Name = "Hint",
		Text = string.format("%s to toggle", Config.ToggleKey.Name),
		FontFace = Theme.Fonts.Mono,
		TextSize = 11,
		TextColor3 = Theme.Colors.TextFaint,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 1,
		Visible = UserInputService.KeyboardEnabled,
		Parent = headerTools,
	})

	local onlinePill = Ui.frame(
		{
			Name = "Online",
			BackgroundColor3 = Theme.Colors.Raised,
			BackgroundTransparency = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			LayoutOrder = 2,
			Parent = headerTools,
		},
		Ui.corner(UDim.new(0.5, 0)),
		Ui.stroke(Theme.Colors.Stroke),
		Ui.padding(0, 12, 0, 10),
		Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	)
	Ui.frame({
		Name = "Dot",
		BackgroundColor3 = Theme.Colors.Success,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(8, 8),
		LayoutOrder = 1,
		Parent = onlinePill,
	}, Ui.corner(UDim.new(0.5, 0)))
	local onlineLabel = Ui.label({
		Name = "Count",
		FontFace = Theme.Fonts.MonoBold,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextMuted,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 2,
		Parent = onlinePill,
	})

	local closeButton = Components.iconButton({
		Name = "Close",
		Glyph = "✕",
		Size = 34,
		HoverColor = Theme.Colors.Danger,
		LayoutOrder = 3,
		Parent = headerTools,
	})

	local body = Ui.frame({
		Name = "Body",
		Position = UDim2.fromOffset(0, layout.HeaderHeight + 1),
		Size = UDim2.new(1, 0, 1, -(layout.HeaderHeight + 1 + layout.FooterHeight)),
		Parent = surface,
	}, Ui.padding(layout.Gutter))

	local sidebar = Ui.frame({
		Name = "Sidebar",
		Size = UDim2.new(0, layout.SidebarWidth, 1, 0),
		Parent = body,
	})

	local content = Ui.frame({
		Name = "Content",
		Position = UDim2.fromOffset(layout.SidebarWidth + layout.Gutter, 0),
		Size = UDim2.new(1, -(layout.SidebarWidth + layout.Gutter), 1, 0),
		Parent = body,
	})

	local targetStroke = Ui.stroke(Theme.Colors.Stroke)
	local targetCard = Ui.frame({
		Name = "Target",
		BackgroundColor3 = Theme.Colors.Raised,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 0, 92),
		Parent = content,
	}, Ui.corner(layout.Radius), targetStroke)

	local avatarRing = Ui.stroke(Theme.Colors.StrokeStrong, 2)
	local avatar = Ui.image({
		Name = "Avatar",
		BackgroundColor3 = Theme.Colors.Elevated,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(60, 60),
		Parent = targetCard,
	}, Ui.corner(UDim.new(0.5, 0)), avatarRing)
	local avatarPlaceholder = Ui.label({
		Name = "Placeholder",
		Text = "?",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 26,
		TextColor3 = Theme.Colors.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = avatar,
	})

	local targetName = Ui.label({
		Name = "DisplayName",
		FontFace = Theme.Fonts.Bold,
		TextSize = 20,
		Position = UDim2.fromOffset(92, 16),
		Size = UDim2.new(1, -240, 0, 24),
		Parent = targetCard,
	})
	local targetHandle = Ui.label({
		Name = "Username",
		TextSize = 14,
		TextColor3 = Theme.Colors.TextMuted,
		Position = UDim2.fromOffset(92, 41),
		Size = UDim2.new(1, -108, 0, 18),
		Parent = targetCard,
	})
	local targetMeta = Ui.label({
		Name = "Meta",
		FontFace = Theme.Fonts.Mono,
		TextSize = 11,
		TextColor3 = Theme.Colors.TextFaint,
		Position = UDim2.fromOffset(92, 61),
		Size = UDim2.new(1, -108, 0, 16),
		Parent = targetCard,
	})

	local statusRow = Ui.frame({
		Name = "Status",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(150, 22),
		Parent = targetCard,
	}, Ui.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center))
	local youChip = Components.chip("YOU", Theme.Colors.Accent, 1)
	youChip.Visible = false
	youChip.Parent = statusRow
	local frozenChip = Components.chip("FROZEN", Theme.Colors.Ice, 2)
	frozenChip.Visible = false
	frozenChip.Parent = statusRow
	local watchingChip = Components.chip("WATCHING", Theme.Colors.Violet, 3)
	watchingChip.Visible = false
	watchingChip.Parent = statusRow

	local sectionRow = Ui.frame({
		Name = "Section",
		Position = UDim2.fromOffset(0, 106),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = content,
	})
	local sectionCaption = Ui.label({
		Name = "Caption",
		Text = "ACTIONS",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextFaint,
		Size = UDim2.new(1, -100, 1, 0),
		Parent = sectionRow,
	})
	local backButton = Ui.button({
		Name = "Back",
		Text = "‹  Back",
		TextSize = 13,
		TextColor3 = Theme.Colors.TextMuted,
		BackgroundColor3 = Theme.Colors.Raised,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(78, 26),
		Visible = false,
		Parent = sectionRow,
	}, Ui.corner(8), Ui.stroke(Theme.Colors.Stroke))

	local pages = Ui.frame({
		Name = "Pages",
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, 138),
		Size = UDim2.new(1, 0, 1, -138),
		Parent = content,
	})
	local pageLayout = Ui.new(Instance.new("UIPageLayout"), {
		Animated = true,
		Circular = false,
		EasingDirection = Enum.EasingDirection.Out,
		EasingStyle = Enum.EasingStyle.Quint,
		FillDirection = Enum.FillDirection.Horizontal,
		GamepadInputEnabled = false,
		Padding = UDim.new(0, 24),
		ScrollWheelInputEnabled = false,
		SortOrder = Enum.SortOrder.LayoutOrder,
		TouchInputEnabled = false,
		TweenTime = 0.32,
		Parent = pages,
	})

	local function gridPage(name: string, order: number, columns: number): Frame
		local gap = 12
		return Ui.frame(
			{
				Name = name,
				Size = UDim2.fromScale(1, 1),
				LayoutOrder = order,
				Parent = pages,
			},
			Ui.new(Instance.new("UIGridLayout"), {
				CellPadding = UDim2.fromOffset(gap, gap),
				CellSize = UDim2.new(1 / columns, -math.ceil(gap * (columns - 1) / columns), 0.5, -gap / 2),
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
			})
		)
	end

	local primaryPage = gridPage("Primary", 1, 2)
	local utilityPage = gridPage("Utility", 2, 3)

	for index, view in PRIMARY_ACTIONS do
		tiles[view.Id] = Components.tile({
			Name = view.Id,
			Glyph = view.Glyph,
			Title = view.Title,
			Description = view.Description,
			Tone = view.Tone,
			Compact = false,
			Chevron = view.Id == "More",
			LayoutOrder = index,
			Parent = primaryPage,
		})
	end
	for index, view in UTILITY_ACTIONS do
		tiles[view.Id] = Components.tile({
			Name = view.Id,
			Glyph = view.Glyph,
			Title = view.Title,
			Description = view.Description,
			Tone = view.Tone,
			Compact = true,
			LayoutOrder = index,
			Parent = utilityPage,
		})
	end

	local footer = Ui.frame({
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, layout.FooterHeight),
		Parent = surface,
	}, Ui.padding(0, layout.Gutter))
	Ui.frame({
		Name = "Divider",
		BackgroundColor3 = Theme.Colors.Stroke,
		BackgroundTransparency = 0,
		Position = UDim2.new(0, -layout.Gutter, 0, 0),
		Size = UDim2.new(1, layout.Gutter * 2, 0, 1),
		Parent = footer,
	})
	local dangerBadge = Ui.frame({
		Name = "DangerBadge",
		BackgroundColor3 = Theme.Colors.Danger,
		BackgroundTransparency = 0.85,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(34, 34),
		Parent = footer,
	}, Ui.corner(10))
	Ui.label({
		Name = "Glyph",
		Text = "!",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 18,
		TextColor3 = Theme.Colors.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = dangerBadge,
	})
	Ui.label({
		Name = "DangerTitle",
		Text = "Danger zone",
		FontFace = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = Theme.Colors.Danger,
		Position = UDim2.new(0, 48, 0.5, -18),
		Size = UDim2.new(1, -330, 0, 18),
		Parent = footer,
	})
	local dangerCaption = Ui.label({
		Name = "DangerCaption",
		Text = "Disconnects every player and locks this server.",
		TextSize = 12,
		TextColor3 = Theme.Colors.TextMuted,
		Position = UDim2.new(0, 48, 0.5, 1),
		Size = UDim2.new(1, -330, 0, 16),
		Parent = footer,
	})

	local terminateStroke = Ui.stroke(Theme.Colors.Danger, 1, 0.45)
	local terminateButton = Ui.button({
		Name = "Terminate",
		BackgroundColor3 = Theme.Colors.Danger,
		BackgroundTransparency = 0.9,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(260, 44),
		ClipsDescendants = true,
		Parent = footer,
	}, Ui.corner(11), terminateStroke)
	local terminateFill = Ui.frame({
		Name = "Fill",
		BackgroundColor3 = Theme.Colors.Danger,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 1,
		Parent = terminateButton,
	}, Ui.corner(11))
	local terminateLabel = Ui.label({
		Name = "Label",
		Text = "Hold to terminate game",
		FontFace = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = Theme.Colors.AccentBright,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = terminateButton,
	})

	if not mount.Access.CanTerminate then
		terminateButton.Visible = false
		dangerCaption.Text = "Terminate is disabled for this server."
	end

	local toasts = Toasts.new(surface)
	local dialog = Dialog.new(surface)

	local launcherStroke = Ui.stroke(Theme.Colors.Stroke)
	local launcher = Ui.button({
		Name = "Launcher",
		BackgroundColor3 = Theme.Colors.Surface,
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
		Visible = Config.ShowLauncher,
		Parent = screen,
	}, Ui.corner(14), launcherStroke)
	local launcherMark = Ui.frame({
		Name = "Mark",
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(32, 32),
		Parent = launcher,
	}, Ui.corner(9), Ui.gradient(ColorSequence.new(Theme.Colors.AccentBright, Theme.Colors.AccentDeep), 45))
	Ui.label({
		Name = "Letter",
		Text = "D",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 18,
		TextColor3 = Theme.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = launcherMark,
	})

	local function currentCamera(): Camera?
		return Workspace.CurrentCamera
	end

	local function fitScale(): number
		local camera = currentCamera()
		if not camera then
			return 1
		end
		local viewport = camera.ViewportSize
		local fit = math.min((viewport.X - 24) / windowSize.X, (viewport.Y - 24) / windowSize.Y)
		return math.clamp(fit, 0.45, 1)
	end

	local function clampOffset(offset: Vector2): Vector2
		local camera = currentCamera()
		if not camera then
			return offset
		end
		local viewport = camera.ViewportSize
		local scale = fitScale()
		local limitX = math.max(0, (viewport.X - windowSize.X * scale) / 2)
		local limitY = math.max(0, (viewport.Y - windowSize.Y * scale) / 2)
		return Vector2.new(math.clamp(offset.X, -limitX, limitX), math.clamp(offset.Y, -limitY, limitY))
	end

	local function applyOffset(offset: Vector2)
		windowOffset = clampOffset(offset)
		window.Position = UDim2.new(0.5, windowOffset.X, 0.5, windowOffset.Y)
	end

	local function setPage(utility: boolean)
		pageLayout:JumpTo(if utility then utilityPage else primaryPage)
		sectionCaption.Text = if utility then "MORE ACTIONS" else "ACTIONS"
		backButton.Visible = utility
	end

	local function isFrozen(player: Player): boolean
		local character = player.Character
		return character ~= nil and character:GetAttribute(Protocol.Attributes.Frozen) == true
	end

	local function refreshTiles()
		local target = selected
		for id, tile in tiles do
			local spec = Protocol.Actions[id]
			local available = target ~= nil and not busy
			if available and spec and target == localPlayer and not spec.AllowSelf then
				available = false
			end
			if available and id == "Spectate" and target == localPlayer then
				available = false
			end
			tile.setEnabled(available or (id == "More" and not busy))
		end

		local frozen = target ~= nil and isFrozen(target)
		local watching = target ~= nil and spectating == target
		tiles.Freeze.setTitle(if frozen then "Unfreeze" else "Freeze")
		tiles.Freeze.setDescription(if frozen then "Let them move again" else "Lock their movement")
		tiles.Spectate.setTitle(if watching then "Stop" else "Spectate")
		tiles.Spectate.setDescription(if watching then "Back to your camera" else "View their avatar")
		frozenChip.Visible = frozen
		watchingChip.Visible = watching
	end

	local function disconnectAll(connections: { RBXScriptConnection })
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	local function stopSpectating()
		disconnectAll(spectateConnections)
		if not spectating then
			return
		end
		spectating = nil
		local camera = currentCamera()
		local character = localPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if camera and humanoid then
			camera.CameraSubject = humanoid
		end
	end

	local function startSpectating(target: Player)
		stopSpectating()
		spectating = target
		local function attach(character: Model)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			local camera = currentCamera()
			if spectating == target and camera and humanoid and humanoid:IsA("Humanoid") then
				camera.CameraSubject = humanoid
			end
		end
		table.insert(spectateConnections, target.CharacterAdded:Connect(attach))
		table.insert(
			spectateConnections,
			localPlayer.CharacterAdded:Connect(function()
				task.defer(function()
					if spectating == target then
						stopSpectating()
						refreshTiles()
					end
				end)
			end)
		)
		local character = target.Character
		if character then
			task.spawn(attach, character)
		end
	end

	local function bindCharacter(player: Player)
		if characterConnection then
			characterConnection:Disconnect()
			characterConnection = nil
		end
		local character = player.Character
		if character then
			characterConnection = character:GetAttributeChangedSignal(Protocol.Attributes.Frozen):Connect(refreshTiles)
		end
		refreshTiles()
	end

	local function showTarget(player: Player?)
		disconnectAll(selectionConnections)
		if characterConnection then
			characterConnection:Disconnect()
			characterConnection = nil
		end
		selected = player

		if player then
			avatar.Image = Ui.headshot(player.UserId)
			avatarPlaceholder.Visible = false
			targetName.Text = player.DisplayName
			targetName.TextColor3 = Theme.Colors.Text
			targetHandle.Text = "@" .. player.Name
			targetMeta.Text = string.format("ID %d  ·  %s days old", player.UserId, Ui.thousands(player.AccountAge))
			youChip.Visible = player == localPlayer
			Ui.tween(avatarRing, Theme.Motion.Smooth, { Color = Theme.Colors.Accent })
			Ui.tween(targetStroke, Theme.Motion.Smooth, { Color = Theme.Colors.StrokeStrong })
			table.insert(
				selectionConnections,
				player.CharacterAdded:Connect(function()
					bindCharacter(player)
				end)
			)
			table.insert(
				selectionConnections,
				player.CharacterRemoving:Connect(function()
					task.defer(refreshTiles)
				end)
			)
			bindCharacter(player)
		else
			avatar.Image = ""
			avatarPlaceholder.Visible = true
			targetName.Text = "No player selected"
			targetName.TextColor3 = Theme.Colors.TextMuted
			targetHandle.Text = "Choose someone from the list to get started."
			targetMeta.Text = ""
			youChip.Visible = false
			Ui.tween(avatarRing, Theme.Motion.Smooth, { Color = Theme.Colors.StrokeStrong })
			Ui.tween(targetStroke, Theme.Motion.Smooth, { Color = Theme.Colors.Stroke })
			refreshTiles()
		end
	end

	local function readResponse(ok: boolean, tone: unknown, message: unknown): (Tone, string)
		if not ok then
			return "Error", "Request failed. Try again in a moment."
		end
		local resolved: Tone? = if typeof(tone) == "string" then RESPONSE_TONES[tone] else nil
		if resolved and typeof(message) == "string" then
			return resolved, message
		end
		return "Error", "Unexpected response from the server."
	end

	local function submit(actionId: string, target: Player?, options: { [string]: any }?, tile: Tile?)
		if busy then
			return
		end
		if target and target.Parent ~= Players then
			toasts.push("Error", "That player already left the server.")
			return
		end
		busy = true
		if tile then
			tile.setBusy(true)
		end
		refreshTiles()
		local ok, tone, message = pcall(function()
			return mount.Request:InvokeServer(actionId, if target then target.UserId else nil, options)
		end)
		busy = false
		if tile then
			tile.setBusy(false)
		end
		refreshTiles()
		local resolvedTone: Tone, resolvedMessage: string = readResponse(ok, tone, message)
		toasts.push(resolvedTone, resolvedMessage)
	end

	local function openReasonDialog(actionId: string, target: Player)
		local isBan = actionId == "Ban"
		dialog.open({
			Glyph = if isBan then "⊘" else "➜",
			Title = string.format("%s %s", if isBan then "Ban" else "Kick", target.DisplayName),
			Body = if isBan
				then string.format("@%s will be removed and blocked from rejoining.", target.Name)
				else string.format("@%s will be disconnected from this server.", target.Name),
			ConfirmText = if isBan then "Ban player" else "Kick player",
			Tone = if isBan then Theme.Colors.Danger else Theme.Colors.Warning,
			MaxReasonLength = Protocol.Limits.ReasonLength,
			Durations = if isBan then Protocol.BanDurations else nil,
			DefaultDuration = #Protocol.BanDurations,
			OnConfirm = function(reason: string, durationIndex: number)
				submit(actionId, target, { Reason = reason, DurationIndex = durationIndex }, tiles[actionId])
			end,
		})
	end

	local function onTileActivated(id: string)
		local tile = tiles[id]
		if not tile.isAvailable() then
			return
		end
		if id == "More" then
			setPage(true)
			return
		end
		local target = selected
		if not target then
			return
		end
		if id == "Ban" or id == "Kick" then
			openReasonDialog(id, target)
		elseif id == "Spectate" then
			if spectating == target then
				stopSpectating()
			else
				startSpectating(target)
			end
			refreshTiles()
		else
			submit(id, target, nil, tile)
		end
	end

	for id, tile in tiles do
		tile.Button.Activated:Connect(function()
			onTileActivated(id)
		end)
	end

	PlayerList.new(sidebar, {
		OnSelect = function(player: Player?, departed: Player?)
			if departed then
				if spectating == departed then
					stopSpectating()
				end
				if dialog.isOpen() then
					dialog.close()
				end
				toasts.push("Warning", string.format("%s left the server.", departed.DisplayName))
			end
			showTarget(player)
		end,
		OnCountChanged = function(count: number)
			onlineLabel.Text = string.format("%d / %d online", count, Players.MaxPlayers)
		end,
	})

	Players.PlayerRemoving:Connect(function(player: Player)
		if spectating == player and selected ~= player then
			stopSpectating()
			refreshTiles()
		end
	end)

	local holdInput: InputObject? = nil
	local holdTween: Tween? = nil
	local holdToken = 0

	local function resetHold()
		holdToken += 1
		holdInput = nil
		if holdTween then
			holdTween:Cancel()
			holdTween = nil
		end
		Ui.tween(terminateFill, Theme.Motion.Release, { Size = UDim2.fromScale(0, 1) })
		Ui.tween(terminateLabel, Theme.Motion.Hover, { TextColor3 = Theme.Colors.AccentBright })
		terminateLabel.Text = "Hold to terminate game"
	end

	local function beginHold(input: InputObject)
		if busy or holdInput or not mount.Access.CanTerminate then
			return
		end
		holdInput = input
		holdToken += 1
		local token = holdToken
		local remaining = math.max(0.05, (1 - terminateFill.Size.X.Scale) * Config.TerminateHoldSeconds)
		terminateLabel.Text = "Keep holding…"
		Ui.tween(terminateLabel, Theme.Motion.Hover, { TextColor3 = Theme.Colors.White })
		local tween = TweenService:Create(
			terminateFill,
			TweenInfo.new(remaining, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) }
		)
		holdTween = tween
		tween.Completed:Connect(function(state: Enum.PlaybackState)
			if state ~= Enum.PlaybackState.Completed or token ~= holdToken then
				return
			end
			holdInput = nil
			holdTween = nil
			terminateLabel.Text = "Terminating…"
			submit("Terminate", nil, nil, nil)
			resetHold()
		end)
		tween:Play()
	end

	terminateButton.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			beginHold(input)
		end
	end)
	terminateButton.MouseEnter:Connect(function()
		Ui.tween(terminateButton, Theme.Motion.Hover, { BackgroundTransparency = 0.82 })
		Ui.tween(terminateStroke, Theme.Motion.Hover, { Transparency = 0.15 })
	end)
	terminateButton.MouseLeave:Connect(function()
		Ui.tween(terminateButton, Theme.Motion.Hover, { BackgroundTransparency = 0.9 })
		Ui.tween(terminateStroke, Theme.Motion.Hover, { Transparency = 0.45 })
		local input = holdInput
		if input and input.UserInputType == Enum.UserInputType.MouseButton1 then
			resetHold()
		end
	end)

	local dragInput: InputObject? = nil
	local dragOrigin = Vector3.zero
	local dragStartOffset = Vector2.zero

	header.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end
		dragInput = input
		dragOrigin = input.Position
		dragStartOffset = windowOffset
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local active = dragInput
		if not active then
			return
		end
		local matches = input == active
			or (
				active.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if not matches then
			return
		end
		local delta = input.Position - dragOrigin
		applyOffset(dragStartOffset + Vector2.new(delta.X, delta.Y))
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local active = dragInput
		if active and (input == active or input.UserInputType == active.UserInputType) then
			dragInput = nil
		end
		local holding = holdInput
		if holding and (input == holding or input.UserInputType == holding.UserInputType) then
			resetHold()
		end
	end)

	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		visibilityToken += 1
		local token = visibilityToken
		local scale = fitScale()

		if open then
			applyOffset(windowOffset)
			window.Visible = true
			windowScale.Scale = scale * 0.94
			Ui.tween(window, Theme.Motion.Open, { GroupTransparency = 0 })
			Ui.tween(windowScale, Theme.Motion.Open, { Scale = scale })
			launcher.Visible = false
		else
			dialog.close()
			dragInput = nil
			if holdInput then
				resetHold()
			end
			Ui.tween(window, Theme.Motion.Close, { GroupTransparency = 1 })
			Ui.tween(windowScale, Theme.Motion.Close, { Scale = scale * 0.96 })
			task.delay(Theme.Motion.Close.Time, function()
				if token == visibilityToken and not isOpen then
					window.Visible = false
					launcher.Visible = Config.ShowLauncher
				end
			end)
		end
	end

	local viewportConnection: RBXScriptConnection? = nil
	local function onViewportChanged()
		if isOpen then
			windowScale.Scale = fitScale()
		end
		applyOffset(windowOffset)
	end
	local function bindCamera()
		if viewportConnection then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end
		local camera = currentCamera()
		if camera then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
		end
		onViewportChanged()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()

	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	launcher.Activated:Connect(function()
		setOpen(true)
	end)
	launcher.MouseEnter:Connect(function()
		Ui.tween(launcherStroke, Theme.Motion.Hover, { Color = Theme.Colors.Accent })
	end)
	launcher.MouseLeave:Connect(function()
		Ui.tween(launcherStroke, Theme.Motion.Hover, { Color = Theme.Colors.Stroke })
	end)
	backButton.Activated:Connect(function()
		setPage(false)
	end)
	backButton.MouseEnter:Connect(function()
		Ui.tween(
			backButton,
			Theme.Motion.Hover,
			{ BackgroundColor3 = Theme.Colors.Elevated, TextColor3 = Theme.Colors.Text }
		)
	end)
	backButton.MouseLeave:Connect(function()
		Ui.tween(
			backButton,
			Theme.Motion.Hover,
			{ BackgroundColor3 = Theme.Colors.Raised, TextColor3 = Theme.Colors.TextMuted }
		)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= Config.ToggleKey then
			return
		end
		setOpen(not isOpen)
	end)

	showTarget(nil)
	setPage(false)
	screen.Parent = playerGui
end

return Panel
