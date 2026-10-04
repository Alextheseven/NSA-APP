local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

export type TileSpec = {
	Name: string,
	Glyph: string,
	Title: string,
	Description: string,
	Tone: Color3,
	Compact: boolean,
	Chevron: boolean?,
	LayoutOrder: number,
	Parent: Instance,
}

export type Tile = {
	Button: TextButton,
	setEnabled: (enabled: boolean) -> (),
	setBusy: (busy: boolean) -> (),
	setTitle: (title: string) -> (),
	setDescription: (description: string) -> (),
	isAvailable: () -> boolean,
}

export type IconButtonSpec = {
	Name: string,
	Glyph: string,
	Size: number,
	HoverColor: Color3,
	LayoutOrder: number?,
	Parent: Instance,
}

local Components = {}

function Components.tile(spec: TileSpec): Tile
	local enabled = true
	local busy = false
	local hovered = false
	local description = spec.Description

	local stroke = Ui.stroke(Theme.Colors.Stroke)
	local scale = Instance.new("UIScale")
	local button = Ui.button({
		Name = spec.Name,
		BackgroundColor3 = Theme.Colors.Raised,
		BackgroundTransparency = 0,
		LayoutOrder = spec.LayoutOrder,
		Parent = spec.Parent,
	}, Ui.corner(Theme.Layout.Radius), stroke, scale)

	local iconSize = if spec.Compact then 32 else 44
	local iconBox = Ui.frame({
		Name = "Icon",
		BackgroundColor3 = spec.Tone,
		BackgroundTransparency = 0.84,
		AnchorPoint = if spec.Compact then Vector2.zero else Vector2.new(0, 0.5),
		Position = if spec.Compact then UDim2.fromOffset(14, 14) else UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(iconSize, iconSize),
		Parent = button,
	}, Ui.corner(if spec.Compact then 9 else 12))

	local glyph = Ui.label({
		Name = "Glyph",
		Text = spec.Glyph,
		FontFace = Theme.Fonts.Bold,
		TextSize = if spec.Compact then 17 else 21,
		TextColor3 = spec.Tone,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = iconBox,
	})

	local title: TextLabel
	local caption: TextLabel
	if spec.Compact then
		title = Ui.label({
			Name = "Title",
			Text = spec.Title,
			FontFace = Theme.Fonts.Bold,
			TextSize = 15,
			Position = UDim2.new(0, 14, 1, -46),
			Size = UDim2.new(1, -28, 0, 18),
			Parent = button,
		})
		caption = Ui.label({
			Name = "Caption",
			Text = description,
			TextSize = 12,
			TextColor3 = Theme.Colors.TextMuted,
			Position = UDim2.new(0, 14, 1, -26),
			Size = UDim2.new(1, -28, 0, 14),
			Parent = button,
		})
	else
		local textBlock = Ui.frame({
			Name = "Text",
			Position = UDim2.fromOffset(74, 0),
			Size = UDim2.new(1, if spec.Chevron then -112 else -90, 1, 0),
			Parent = button,
		}, Ui.list(Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center))
		title = Ui.label({
			Name = "Title",
			Text = spec.Title,
			FontFace = Theme.Fonts.Bold,
			TextSize = 17,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1,
			Parent = textBlock,
		})
		caption = Ui.label({
			Name = "Caption",
			Text = description,
			TextSize = 13,
			TextColor3 = Theme.Colors.TextMuted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = 2,
			Parent = textBlock,
		})
	end

	if spec.Chevron then
		Ui.label({
			Name = "Chevron",
			Text = "›",
			FontFace = Theme.Fonts.Bold,
			TextSize = 26,
			TextColor3 = Theme.Colors.TextFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, -2),
			Size = UDim2.fromOffset(18, 28),
			Parent = button,
		})
	end

	local function paint(info: TweenInfo)
		local available = enabled and not busy
		local highlight = available and hovered
		Ui.tween(button, info, {
			BackgroundColor3 = if highlight then Theme.Colors.Elevated else Theme.Colors.Raised,
		})
		Ui.tween(stroke, info, {
			Color = if highlight then spec.Tone else Theme.Colors.Stroke,
			Transparency = if highlight then 0.35 else 0,
		})
		Ui.tween(iconBox, info, {
			BackgroundTransparency = if highlight then 0.72 elseif enabled then 0.84 else 0.94,
		})
		Ui.tween(glyph, info, { TextTransparency = if enabled then 0 else 0.65 })
		Ui.tween(title, info, { TextColor3 = if enabled then Theme.Colors.Text else Theme.Colors.TextFaint })
		Ui.tween(caption, info, { TextColor3 = if enabled then Theme.Colors.TextMuted else Theme.Colors.TextFaint })
	end

	button.MouseEnter:Connect(function()
		hovered = true
		paint(Theme.Motion.Hover)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		Ui.tween(scale, Theme.Motion.Release, { Scale = 1 })
		paint(Theme.Motion.Hover)
	end)
	button.MouseButton1Down:Connect(function()
		if enabled and not busy then
			Ui.tween(scale, Theme.Motion.Press, { Scale = 0.97 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		Ui.tween(scale, Theme.Motion.Release, { Scale = 1 })
	end)

	return {
		Button = button,
		setEnabled = function(value: boolean)
			if enabled == value then
				return
			end
			enabled = value
			button.Selectable = value
			paint(Theme.Motion.Smooth)
		end,
		setBusy = function(value: boolean)
			if busy == value then
				return
			end
			busy = value
			caption.Text = if value then "Working…" else description
			paint(Theme.Motion.Smooth)
		end,
		setTitle = function(text: string)
			title.Text = text
		end,
		setDescription = function(text: string)
			description = text
			if not busy then
				caption.Text = text
			end
		end,
		isAvailable = function(): boolean
			return enabled and not busy
		end,
	}
end

function Components.iconButton(spec: IconButtonSpec): TextButton
	local stroke = Ui.stroke(Theme.Colors.Stroke)
	local button = Ui.button({
		Name = spec.Name,
		Text = spec.Glyph,
		FontFace = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = Theme.Colors.TextMuted,
		BackgroundColor3 = Theme.Colors.Raised,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(spec.Size, spec.Size),
		LayoutOrder = spec.LayoutOrder or 0,
		Parent = spec.Parent,
	}, Ui.corner(10), stroke)

	button.MouseEnter:Connect(function()
		Ui.tween(button, Theme.Motion.Hover, { BackgroundColor3 = spec.HoverColor, TextColor3 = Theme.Colors.White })
		Ui.tween(stroke, Theme.Motion.Hover, { Color = spec.HoverColor })
	end)
	button.MouseLeave:Connect(function()
		Ui.tween(
			button,
			Theme.Motion.Hover,
			{ BackgroundColor3 = Theme.Colors.Raised, TextColor3 = Theme.Colors.TextMuted }
		)
		Ui.tween(stroke, Theme.Motion.Hover, { Color = Theme.Colors.Stroke })
	end)

	return button
end

function Components.chip(text: string, color: Color3, layoutOrder: number?): (Frame, TextLabel)
	local chip = Ui.frame({
		Name = "Chip",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.84,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		LayoutOrder = layoutOrder or 0,
	}, Ui.corner(6), Ui.padding(0, 8, 0, 8))
	local label = Ui.label({
		Name = "Label",
		Text = text,
		FontFace = Theme.Fonts.MonoBold,
		TextSize = 11,
		TextColor3 = color,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = chip,
	})
	return chip, label
end

return Components
