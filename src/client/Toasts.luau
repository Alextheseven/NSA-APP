local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local Protocol = require(ReplicatedStorage:WaitForChild("DedhecPanel"):WaitForChild("Protocol"))

type Tone = Protocol.Tone

type ToneStyle = {
	Color: Color3,
	Glyph: string,
}

type Toast = {
	Slot: Frame,
	Body: Frame,
	Stroke: UIStroke,
	Badge: Frame,
	Glyph: TextLabel,
	Message: TextLabel,
	Dismissed: boolean,
}

export type Handle = {
	push: (tone: Tone, message: string) -> (),
	clear: () -> (),
}

local TONES: { [Tone]: ToneStyle } = {
	Success = { Color = Theme.Colors.Success, Glyph = "✓" },
	Warning = { Color = Theme.Colors.Warning, Glyph = "!" },
	Error = { Color = Theme.Colors.Danger, Glyph = "✕" },
}

local LIFETIME = 3.4
local MAX_VISIBLE = 4
local SLIDE_OFFSET = 28

local Toasts = {}

function Toasts.new(parent: GuiObject): Handle
	local host = Ui.frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.Layout.Gutter, 1, -(Theme.Layout.FooterHeight + 14)),
		Size = UDim2.fromOffset(320, 260),
		ZIndex = 30,
		Parent = parent,
	}, Ui.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom))

	local active: { Toast } = {}
	local sequence = 0

	local function render(toast: Toast, visible: boolean, info: TweenInfo)
		Ui.tween(toast.Body, info, {
			Position = UDim2.fromOffset(if visible then 0 else SLIDE_OFFSET, 0),
			BackgroundTransparency = if visible then 0.02 else 1,
		})
		Ui.tween(toast.Stroke, info, { Transparency = if visible then 0 else 1 })
		Ui.tween(toast.Badge, info, { BackgroundTransparency = if visible then 0.82 else 1 })
		Ui.tween(toast.Glyph, info, { TextTransparency = if visible then 0 else 1 })
		Ui.tween(toast.Message, info, { TextTransparency = if visible then 0 else 1 })
	end

	local function dismiss(toast: Toast)
		if toast.Dismissed then
			return
		end
		toast.Dismissed = true
		local index = table.find(active, toast)
		if index then
			table.remove(active, index)
		end
		render(toast, false, Theme.Motion.Close)
		task.delay(Theme.Motion.Close.Time, function()
			toast.Slot:Destroy()
		end)
	end

	local function push(tone: Tone, message: string)
		local style = TONES[tone]
		sequence += 1

		local slot = Ui.frame({
			Name = "Toast",
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = sequence,
			Parent = host,
		})
		local stroke = Ui.stroke(Theme.Colors.StrokeStrong, 1, 1)
		local body = Ui.frame({
			Name = "Body",
			BackgroundColor3 = Theme.Colors.Elevated,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(SLIDE_OFFSET, 0),
			Size = UDim2.fromScale(1, 1),
			Parent = slot,
		}, Ui.corner(12), stroke)
		local badge = Ui.frame({
			Name = "Badge",
			BackgroundColor3 = style.Color,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(26, 26),
			Parent = body,
		}, Ui.corner(UDim.new(0.5, 0)))
		local glyph = Ui.label({
			Name = "Glyph",
			Text = style.Glyph,
			FontFace = Theme.Fonts.Heavy,
			TextSize = 14,
			TextColor3 = style.Color,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.fromScale(1, 1),
			Parent = badge,
		})
		local label = Ui.label({
			Name = "Message",
			Text = message,
			FontFace = Theme.Fonts.Medium,
			TextSize = 14,
			TextTransparency = 1,
			Position = UDim2.fromOffset(48, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Parent = body,
		})

		local toast: Toast = {
			Slot = slot,
			Body = body,
			Stroke = stroke,
			Badge = badge,
			Glyph = glyph,
			Message = label,
			Dismissed = false,
		}
		table.insert(active, toast)
		render(toast, true, Theme.Motion.Open)

		while #active > MAX_VISIBLE do
			dismiss(active[1])
		end

		task.delay(LIFETIME, dismiss, toast)
	end

	local function clear()
		for index = #active, 1, -1 do
			dismiss(active[index])
		end
	end

	return {
		push = push,
		clear = clear,
	}
end

return Toasts
