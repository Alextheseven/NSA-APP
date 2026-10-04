local Players = game:GetService("Players")

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

export type Callbacks = {
	OnSelect: (player: Player?, departed: Player?) -> (),
	OnCountChanged: (count: number) -> (),
}

export type Handle = {
	select: (player: Player?) -> (),
	getSelected: () -> Player?,
}

type Entry = {
	Player: Player,
	Button: TextButton,
	Stroke: UIStroke,
	Marker: Frame,
	Hovered: boolean,
}

local LIST_TOP = 82

local PlayerList = {}

local function buildSearchGlyph(parent: Instance): Frame
	local glyph = Ui.frame({
		Name = "SearchGlyph",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		Parent = parent,
	})
	Ui.frame({
		Name = "Lens",
		Size = UDim2.fromOffset(11, 11),
		Parent = glyph,
	}, Ui.corner(UDim.new(0.5, 0)), Ui.stroke(Theme.Colors.TextFaint, 2))
	Ui.frame({
		Name = "Handle",
		BackgroundColor3 = Theme.Colors.TextFaint,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(13, 13),
		Size = UDim2.fromOffset(2, 7),
		Rotation = -45,
		Parent = glyph,
	}, Ui.corner(1))
	return glyph
end

function PlayerList.new(parent: GuiObject, callbacks: Callbacks): Handle
	local localPlayer = Players.LocalPlayer
	local entries: { [Player]: Entry } = {}
	local selected: Player? = nil
	local count = 0

	local header = Ui.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 22),
		Parent = parent,
	})
	Ui.label({
		Name = "Caption",
		Text = "PLAYERS",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextFaint,
		Size = UDim2.new(1, -60, 1, 0),
		Parent = header,
	})
	local badge, badgeLabel = Components.chip("0", Theme.Colors.Accent)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.fromScale(1, 0.5)
	badge.Parent = header

	local searchStroke = Ui.stroke(Theme.Colors.Stroke)
	local searchField = Ui.frame({
		Name = "Search",
		BackgroundColor3 = Theme.Colors.Raised,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = parent,
	}, Ui.corner(11), searchStroke)
	buildSearchGlyph(searchField)

	local searchBox = Ui.new(Instance.new("TextBox"), {
		Name = "Query",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		FontFace = Theme.Fonts.Medium,
		PlaceholderText = "Search players",
		PlaceholderColor3 = Theme.Colors.TextFaint,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -76, 1, 0),
		Parent = searchField,
	})

	local clearButton = Ui.button({
		Name = "Clear",
		Text = "×",
		TextSize = 20,
		TextColor3 = Theme.Colors.TextFaint,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		Visible = false,
		Parent = searchField,
	}, Ui.corner(8))

	local scroller = Ui.new(Instance.new("ScrollingFrame"), {
		Name = "List",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		Position = UDim2.fromOffset(0, LIST_TOP),
		ScrollBarImageColor3 = Theme.Colors.StrokeStrong,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.new(1, 0, 1, -LIST_TOP),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Parent = parent,
	}, Ui.list(Enum.FillDirection.Vertical, 6), Ui.padding(1, 4, 1, 1))

	local emptyState = Ui.label({
		Name = "Empty",
		Text = "",
		FontFace = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.TextFaint,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, LIST_TOP + 24),
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
		Parent = parent,
	})

	local function paint(entry: Entry, info: TweenInfo)
		local isSelected = entry.Player == selected
		Ui.tween(entry.Button, info, {
			BackgroundColor3 = if isSelected then Theme.Colors.Elevated else Theme.Colors.Raised,
			BackgroundTransparency = if isSelected or entry.Hovered then 0 else 1,
		})
		Ui.tween(entry.Stroke, info, {
			Color = if isSelected then Theme.Colors.Accent else Theme.Colors.Stroke,
			Transparency = if isSelected then 0.35 elseif entry.Hovered then 0 else 1,
		})
		Ui.tween(entry.Marker, info, { BackgroundTransparency = if isSelected then 0 else 1 })
	end

	local function applyFilter()
		local query = string.lower(Ui.trim(searchBox.Text))
		local visible = 0
		for player, entry in entries do
			local matches = query == ""
				or string.find(string.lower(player.Name), query, 1, true) ~= nil
				or string.find(string.lower(player.DisplayName), query, 1, true) ~= nil
			entry.Button.Visible = matches
			if matches then
				visible += 1
			end
		end
		clearButton.Visible = searchBox.Text ~= ""
		emptyState.Visible = visible == 0
		emptyState.Text = if count == 0 then "No players online" else string.format('No matches for "%s"', query)
	end

	local function sortEntries()
		local ordered: { Player } = {}
		for player in entries do
			table.insert(ordered, player)
		end
		table.sort(ordered, function(a: Player, b: Player): boolean
			if a == b then
				return false
			end
			if a == localPlayer then
				return true
			end
			if b == localPlayer then
				return false
			end
			local left = string.lower(a.DisplayName)
			local right = string.lower(b.DisplayName)
			if left ~= right then
				return left < right
			end
			return a.UserId < b.UserId
		end)
		for index, player in ordered do
			entries[player].Button.LayoutOrder = index
		end
	end

	local function select(player: Player?)
		local candidate = if player and entries[player] then player else nil
		if candidate == selected then
			return
		end
		local previous = selected
		selected = candidate
		if previous and entries[previous] then
			paint(entries[previous], Theme.Motion.Smooth)
		end
		if candidate then
			paint(entries[candidate], Theme.Motion.Smooth)
		end
		callbacks.OnSelect(candidate, nil)
	end

	local function addEntry(player: Player)
		if entries[player] or player.Parent ~= Players then
			return
		end

		local stroke = Ui.stroke(Theme.Colors.Stroke, 1, 1)
		local button = Ui.button({
			Name = player.Name,
			BackgroundColor3 = Theme.Colors.Raised,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 56),
			Parent = scroller,
		}, Ui.corner(12), stroke)

		local marker = Ui.frame({
			Name = "Marker",
			BackgroundColor3 = Theme.Colors.Accent,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(3, 24),
			Parent = button,
		}, Ui.corner(2))

		Ui.image({
			Name = "Avatar",
			BackgroundColor3 = Theme.Colors.Elevated,
			BackgroundTransparency = 0,
			Image = Ui.headshot(player.UserId),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(36, 36),
			Parent = button,
		}, Ui.corner(UDim.new(0.5, 0)))

		local isLocal = player == localPlayer
		local textWidth = if isLocal then -112 else -66

		Ui.label({
			Name = "DisplayName",
			Text = player.DisplayName,
			FontFace = Theme.Fonts.Bold,
			TextSize = 15,
			Position = UDim2.fromOffset(58, 10),
			Size = UDim2.new(1, textWidth, 0, 18),
			Parent = button,
		})
		Ui.label({
			Name = "Username",
			Text = "@" .. player.Name,
			TextSize = 12,
			TextColor3 = Theme.Colors.TextMuted,
			Position = UDim2.fromOffset(58, 29),
			Size = UDim2.new(1, textWidth, 0, 16),
			Parent = button,
		})

		if isLocal then
			local chip = Components.chip("YOU", Theme.Colors.Accent)
			chip.AnchorPoint = Vector2.new(1, 0.5)
			chip.Position = UDim2.new(1, -12, 0.5, 0)
			chip.Parent = button
		end

		local entry: Entry = {
			Player = player,
			Button = button,
			Stroke = stroke,
			Marker = marker,
			Hovered = false,
		}
		entries[player] = entry
		count += 1

		button.MouseEnter:Connect(function()
			entry.Hovered = true
			paint(entry, Theme.Motion.Hover)
		end)
		button.MouseLeave:Connect(function()
			entry.Hovered = false
			paint(entry, Theme.Motion.Hover)
		end)
		button.Activated:Connect(function()
			select(player)
		end)

		sortEntries()
		applyFilter()
		badgeLabel.Text = tostring(count)
		callbacks.OnCountChanged(count)
	end

	local function removeEntry(player: Player)
		local entry = entries[player]
		if not entry then
			return
		end
		entries[player] = nil
		count -= 1
		entry.Button:Destroy()
		sortEntries()
		applyFilter()
		badgeLabel.Text = tostring(count)
		callbacks.OnCountChanged(count)
		if selected == player then
			selected = nil
			callbacks.OnSelect(nil, player)
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)
	searchBox.Focused:Connect(function()
		Ui.tween(searchStroke, Theme.Motion.Hover, { Color = Theme.Colors.Accent, Transparency = 0.3 })
	end)
	searchBox.FocusLost:Connect(function()
		Ui.tween(searchStroke, Theme.Motion.Hover, { Color = Theme.Colors.Stroke, Transparency = 0 })
	end)
	clearButton.MouseEnter:Connect(function()
		Ui.tween(clearButton, Theme.Motion.Hover, { TextColor3 = Theme.Colors.Text })
	end)
	clearButton.MouseLeave:Connect(function()
		Ui.tween(clearButton, Theme.Motion.Hover, { TextColor3 = Theme.Colors.TextFaint })
	end)
	clearButton.Activated:Connect(function()
		searchBox.Text = ""
	end)

	Players.PlayerAdded:Connect(addEntry)
	Players.PlayerRemoving:Connect(removeEntry)
	for _, player in Players:GetPlayers() do
		addEntry(player)
	end
	applyFilter()

	return {
		select = select,
		getSelected = function(): Player?
			return selected
		end,
	}
end

return PlayerList
