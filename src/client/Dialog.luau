local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

export type DurationOption = {
	Label: string,
	Seconds: number,
}

export type Spec = {
	Glyph: string,
	Title: string,
	Body: string,
	ConfirmText: string,
	Tone: Color3,
	MaxReasonLength: number,
	Durations: { DurationOption }?,
	DefaultDuration: number?,
	OnConfirm: (reason: string, durationIndex: number) -> (),
}

export type Handle = {
	open: (spec: Spec) -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

local CHIP_GAP = 8

local Dialog = {}

local function sectionCaption(text: string, parent: Instance): TextLabel
	return Ui.label({
		Name = "Caption",
		Text = text,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 11,
		TextColor3 = Theme.Colors.TextFaint,
		Size = UDim2.new(1, -70, 0, 14),
		Parent = parent,
	})
end

function Dialog.new(parent: GuiObject): Handle
	local current: Spec? = nil
	local tone = Theme.Colors.Accent
	local maxLength = 120
	local durationIndex = 1
	local visibilityToken = 0
	local chips: { TextButton } = {}

	local overlay = Ui.button({
		Name = "DialogOverlay",
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 1,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	}, Ui.corner(Theme.Layout.Radius + 2))

	local cardScale = Instance.new("UIScale")
	local card = Ui.button(
		{
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Colors.Raised,
			BackgroundTransparency = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Selectable = false,
			Size = UDim2.fromOffset(400, 0),
			Parent = overlay,
		},
		Ui.corner(16),
		Ui.stroke(Theme.Colors.StrokeStrong),
		Ui.padding(22),
		Ui.list(Enum.FillDirection.Vertical, 18),
		cardScale
	)

	local header = Ui.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 46),
		LayoutOrder = 1,
		Parent = card,
	})
	local badge = Ui.frame({
		Name = "Badge",
		BackgroundColor3 = tone,
		BackgroundTransparency = 0.84,
		Size = UDim2.fromOffset(46, 46),
		Parent = header,
	}, Ui.corner(12))
	local badgeGlyph = Ui.label({
		Name = "Glyph",
		FontFace = Theme.Fonts.Bold,
		TextSize = 22,
		TextColor3 = tone,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	local title = Ui.label({
		Name = "Title",
		FontFace = Theme.Fonts.Bold,
		TextSize = 19,
		Position = UDim2.fromOffset(60, 2),
		Size = UDim2.new(1, -60, 0, 22),
		Parent = header,
	})
	local body = Ui.label({
		Name = "Body",
		TextSize = 13,
		TextColor3 = Theme.Colors.TextMuted,
		Position = UDim2.fromOffset(60, 26),
		Size = UDim2.new(1, -60, 0, 18),
		Parent = header,
	})

	local reasonSection = Ui.frame({
		Name = "Reason",
		Size = UDim2.new(1, 0, 0, 68),
		LayoutOrder = 2,
		Parent = card,
	})
	sectionCaption("REASON", reasonSection)
	local counter = Ui.label({
		Name = "Counter",
		FontFace = Theme.Fonts.Mono,
		TextSize = 11,
		TextColor3 = Theme.Colors.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(70, 14),
		Parent = reasonSection,
	})
	local fieldStroke = Ui.stroke(Theme.Colors.Stroke)
	local field = Ui.frame({
		Name = "Field",
		BackgroundColor3 = Theme.Colors.Elevated,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = reasonSection,
	}, Ui.corner(10), fieldStroke, Ui.padding(0, 14))
	local reasonBox = Ui.new(Instance.new("TextBox"), {
		Name = "Input",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		FontFace = Theme.Fonts.Medium,
		PlaceholderColor3 = Theme.Colors.TextFaint,
		PlaceholderText = "Optional, shown to the player",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = field,
	})

	local durationSection = Ui.frame({
		Name = "Duration",
		Size = UDim2.new(1, 0, 0, 62),
		LayoutOrder = 3,
		Parent = card,
	})
	sectionCaption("DURATION", durationSection)
	local chipRow = Ui.frame({
		Name = "Options",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 38),
		Parent = durationSection,
	}, Ui.list(Enum.FillDirection.Horizontal, CHIP_GAP))

	local actions = Ui.frame({
		Name = "Actions",
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 4,
		Parent = card,
	}, Ui.list(Enum.FillDirection.Horizontal, 10))
	local cancelStroke = Ui.stroke(Theme.Colors.Stroke)
	local cancelButton = Ui.button({
		Name = "Cancel",
		Text = "Cancel",
		TextSize = 15,
		TextColor3 = Theme.Colors.TextMuted,
		BackgroundColor3 = Theme.Colors.Elevated,
		BackgroundTransparency = 0,
		Size = UDim2.new(0.5, -5, 1, 0),
		LayoutOrder = 1,
		Parent = actions,
	}, Ui.corner(10), cancelStroke)
	local confirmButton = Ui.button({
		Name = "Confirm",
		Text = "Confirm",
		TextSize = 15,
		TextColor3 = Theme.Colors.White,
		BackgroundColor3 = tone,
		BackgroundTransparency = 0,
		Size = UDim2.new(0.5, -5, 1, 0),
		LayoutOrder = 2,
		Parent = actions,
	}, Ui.corner(10))

	local function paintChips(info: TweenInfo)
		for index, chip in chips do
			local active = index == durationIndex
			Ui.tween(chip, info, {
				BackgroundColor3 = if active then tone else Theme.Colors.Elevated,
				TextColor3 = if active then Theme.Colors.White else Theme.Colors.TextMuted,
			})
		end
	end

	local function buildChips(options: { DurationOption })
		for _, chip in chips do
			chip:Destroy()
		end
		table.clear(chips)
		local total = #options
		local inset = math.ceil(CHIP_GAP * (total - 1) / total)
		for index, option in options do
			local chip = Ui.button({
				Name = option.Label,
				Text = option.Label,
				TextSize = 13,
				TextColor3 = Theme.Colors.TextMuted,
				BackgroundColor3 = Theme.Colors.Elevated,
				BackgroundTransparency = 0,
				Size = UDim2.new(1 / total, -inset, 1, 0),
				LayoutOrder = index,
				Parent = chipRow,
			}, Ui.corner(9))
			chip.Activated:Connect(function()
				durationIndex = index
				paintChips(Theme.Motion.Hover)
			end)
			table.insert(chips, chip)
		end
	end

	local function updateCounter(text: string)
		counter.Text = string.format("%d/%d", utf8.len(text) or #text, maxLength)
	end

	local function close()
		if not current then
			return
		end
		current = nil
		reasonBox:ReleaseFocus()
		visibilityToken += 1
		local token = visibilityToken
		Ui.tween(overlay, Theme.Motion.Close, { BackgroundTransparency = 1 })
		Ui.tween(cardScale, Theme.Motion.Close, { Scale = 0.95 })
		task.delay(Theme.Motion.Close.Time, function()
			if token == visibilityToken then
				overlay.Visible = false
			end
		end)
	end

	local function confirm()
		local spec = current
		if not spec then
			return
		end
		local reason = Ui.trim(reasonBox.Text)
		local chosen = durationIndex
		close()
		spec.OnConfirm(reason, chosen)
	end

	local function open(spec: Spec)
		current = spec
		tone = spec.Tone
		maxLength = spec.MaxReasonLength

		badge.BackgroundColor3 = tone
		badgeGlyph.TextColor3 = tone
		badgeGlyph.Text = spec.Glyph
		title.Text = spec.Title
		body.Text = spec.Body
		confirmButton.Text = spec.ConfirmText
		confirmButton.BackgroundColor3 = tone
		fieldStroke.Color = Theme.Colors.Stroke
		reasonBox.Text = ""
		updateCounter("")

		local durations = spec.Durations
		if durations and #durations > 0 then
			buildChips(durations)
			durationIndex = math.clamp(spec.DefaultDuration or 1, 1, #durations)
			durationSection.Visible = true
			paintChips(Theme.Motion.Press)
		else
			buildChips({})
			durationIndex = 1
			durationSection.Visible = false
		end

		visibilityToken += 1
		overlay.Visible = true
		overlay.BackgroundTransparency = 1
		cardScale.Scale = 0.94
		Ui.tween(overlay, Theme.Motion.Open, { BackgroundTransparency = 0.35 })
		Ui.tween(cardScale, Theme.Motion.Open, { Scale = 1 })

		if UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled then
			task.defer(function()
				if current == spec then
					reasonBox:CaptureFocus()
				end
			end)
		end
	end

	reasonBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = reasonBox.Text
		local clamped = Ui.clampLength(text, maxLength)
		if clamped ~= text then
			reasonBox.Text = clamped
			return
		end
		updateCounter(text)
	end)
	reasonBox.Focused:Connect(function()
		Ui.tween(fieldStroke, Theme.Motion.Hover, { Color = tone })
	end)
	reasonBox.FocusLost:Connect(function(enterPressed: boolean)
		Ui.tween(fieldStroke, Theme.Motion.Hover, { Color = Theme.Colors.Stroke })
		if enterPressed then
			confirm()
		end
	end)

	cancelButton.MouseEnter:Connect(function()
		Ui.tween(
			cancelButton,
			Theme.Motion.Hover,
			{ BackgroundColor3 = Theme.Colors.Hover, TextColor3 = Theme.Colors.Text }
		)
	end)
	cancelButton.MouseLeave:Connect(function()
		Ui.tween(
			cancelButton,
			Theme.Motion.Hover,
			{ BackgroundColor3 = Theme.Colors.Elevated, TextColor3 = Theme.Colors.TextMuted }
		)
	end)
	confirmButton.MouseEnter:Connect(function()
		Ui.tween(confirmButton, Theme.Motion.Hover, { BackgroundColor3 = tone:Lerp(Theme.Colors.White, 0.14) })
	end)
	confirmButton.MouseLeave:Connect(function()
		Ui.tween(confirmButton, Theme.Motion.Hover, { BackgroundColor3 = tone })
	end)

	cancelButton.Activated:Connect(close)
	overlay.Activated:Connect(close)
	confirmButton.Activated:Connect(confirm)

	return {
		open = open,
		close = close,
		isOpen = function(): boolean
			return current ~= nil
		end,
	}
end

return Dialog
