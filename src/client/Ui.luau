local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

export type Props = { [string]: any }

local Ui = {}

function Ui.new<T>(instance: T, props: Props?, ...: Instance): T
	local target: any = instance
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				target[key] = value
			end
		end
	end
	for index = 1, select("#", ...) do
		local child = select(index, ...)
		child.Parent = target
	end
	if parent then
		target.Parent = parent
	end
	return instance
end

function Ui.corner(radius: number | UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if typeof(radius) == "number" then UDim.new(0, radius) else radius
	return corner
end

function Ui.stroke(color: Color3, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	return stroke
end

function Ui.padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right or top)
	padding.PaddingBottom = UDim.new(0, bottom or top)
	padding.PaddingLeft = UDim.new(0, left or right or top)
	return padding
end

function Ui.list(
	direction: Enum.FillDirection,
	gap: number,
	horizontal: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = vertical or Enum.VerticalAlignment.Top
	return layout
end

function Ui.gradient(color: ColorSequence, rotation: number, transparency: NumberSequence?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = color
	gradient.Rotation = rotation
	if transparency then
		gradient.Transparency = transparency
	end
	return gradient
end

function Ui.frame(props: Props?, ...: Instance): Frame
	local frame = Ui.new(Instance.new("Frame"), {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	return Ui.new(frame, props, ...)
end

function Ui.label(props: Props?, ...: Instance): TextLabel
	local label = Ui.new(Instance.new("TextLabel"), {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Regular,
		TextColor3 = Theme.Colors.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})
	return Ui.new(label, props, ...)
end

function Ui.button(props: Props?, ...: Instance): TextButton
	local button = Ui.new(Instance.new("TextButton"), {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextSize = 14,
		Text = "",
	})
	return Ui.new(button, props, ...)
end

function Ui.image(props: Props?, ...: Instance): ImageLabel
	local image = Ui.new(Instance.new("ImageLabel"), {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Crop,
	})
	return Ui.new(image, props, ...)
end

function Ui.tween(instance: Instance, info: TweenInfo, goals: Props): Tween
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	return tween
end

function Ui.headshot(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

function Ui.hex(color: Color3): string
	return "#" .. color:ToHex()
end

function Ui.thousands(value: number): string
	local digits = tostring(math.floor(value))
	local formatted, replaced = string.gsub(digits, "^(-?%d+)(%d%d%d)", "%1,%2")
	while replaced > 0 do
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	end
	return formatted
end

function Ui.trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") or ""
end

function Ui.clampLength(text: string, maxCharacters: number): string
	local length = utf8.len(text)
	if length == nil or length <= maxCharacters then
		return text
	end
	local cut = utf8.offset(text, maxCharacters + 1)
	if not cut then
		return text
	end
	return string.sub(text, 1, cut - 1)
end

return Ui
