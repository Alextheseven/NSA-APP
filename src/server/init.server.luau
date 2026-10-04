local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Settings = require(script.Settings)

local sharedFolder = ReplicatedStorage:WaitForChild("DedhecPanel")
local Protocol = require(sharedFolder:WaitForChild("Protocol"))

type Tone = Protocol.Tone

type Context = {
	Actor: Player,
	Target: Player?,
	Reason: string,
	DurationIndex: number,
}

type Handler = (Context) -> (Tone, string)

local function obtainRemoteFunction(name: string): RemoteFunction
	local existing = sharedFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = sharedFolder
	return remote
end

local function obtainRemoteEvent(name: string): RemoteEvent
	local existing = sharedFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = sharedFolder
	return remote
end

local effectRemote = obtainRemoteEvent(Protocol.Remotes.Effect)
local handshakeRemote = obtainRemoteFunction(Protocol.Remotes.Handshake)
local requestRemote = obtainRemoteFunction(Protocol.Remotes.Request)

local studioAccess = Settings.StudioGrantsAccess and RunService:IsStudio()
local adminCache: { [Player]: boolean } = {}
local busyActors: { [Player]: boolean } = {}
local lastRequestAt: { [Player]: number } = {}
local lastScareAt: { [Player]: number } = {}
local sessionBans: { [number]: number } = {}
local serverTerminated = false

local function rankInGroup(player: Player, groupId: number): (number, boolean)
	if groupId <= 0 then
		return 0, true
	end
	local ok, membership = pcall(GroupService.GetRolesInGroupAsync, GroupService, player.UserId, groupId)
	if not ok then
		return 0, false
	end
	if typeof(membership) ~= "table" or membership.IsMember ~= true or typeof(membership.Roles) ~= "table" then
		return 0, true
	end
	local highest = 0
	for _, role in membership.Roles do
		if typeof(role) == "table" and typeof(role.Rank) == "number" and role.Rank > highest then
			highest = role.Rank
		end
	end
	return highest, true
end

local function evaluateAdmin(player: Player): (boolean, boolean)
	if table.find(Settings.AdminUserIds, player.UserId) then
		return true, true
	end
	local reliable = true
	if Settings.CreatorHasAccess then
		if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
			return true, true
		end
		if game.CreatorType == Enum.CreatorType.Group then
			local rank, resolved = rankInGroup(player, game.CreatorId)
			if rank >= Settings.CreatorGroupMinimumRank then
				return true, true
			end
			reliable = reliable and resolved
		end
	end
	for _, rule in Settings.AdminGroups do
		local rank, resolved = rankInGroup(player, rule.GroupId)
		if rank >= rule.MinimumRank then
			return true, true
		end
		reliable = reliable and resolved
	end
	return false, reliable
end

local function isRealAdmin(player: Player): boolean
	local cached = adminCache[player]
	if cached ~= nil then
		return cached
	end
	local result, reliable = evaluateAdmin(player)
	if reliable and player.Parent == Players then
		adminCache[player] = result
	end
	return result
end

local function isAdmin(player: Player): boolean
	return studioAccess or isRealAdmin(player)
end

local function describe(player: Player): string
	if player.DisplayName ~= player.Name then
		return string.format("%s (@%s)", player.DisplayName, player.Name)
	end
	return "@" .. player.Name
end

local function sanitizeReason(raw: unknown): string
	if typeof(raw) ~= "string" or #raw > Protocol.Limits.RawReasonBytes or utf8.len(raw) == nil then
		return ""
	end
	local flattened = string.gsub(raw, "%c", " ")
	local trimmed = string.match(flattened, "^%s*(.-)%s*$") or ""
	local length = utf8.len(trimmed) or 0
	if length > Protocol.Limits.ReasonLength then
		local cut = utf8.offset(trimmed, Protocol.Limits.ReasonLength + 1)
		if cut then
			trimmed = string.sub(trimmed, 1, cut - 1)
		end
	end
	return trimmed
end

local function filterForBroadcast(text: string, fromUserId: number): string?
	if text == "" then
		return nil
	end
	local ok, result = pcall(function(): string
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and result ~= "" then
		return result
	end
	return nil
end

local function readOptions(raw: unknown): (unknown, unknown)
	if typeof(raw) ~= "table" then
		return nil, nil
	end
	local options = raw :: { [unknown]: unknown }
	return rawget(options, "Reason"), rawget(options, "DurationIndex")
end

local function readDurationIndex(raw: unknown): number?
	if typeof(raw) ~= "number" or raw % 1 ~= 0 or raw < 1 or raw > #Protocol.BanDurations then
		return nil
	end
	return raw
end

local function getRig(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return character, nil, nil
	end
	return character, humanoid, humanoid.RootPart
end

local function releaseSeat(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	if not seat then
		return
	end
	humanoid.Sit = false
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
end

local function levelled(cframe: CFrame): CFrame
	local look = cframe.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		return CFrame.new(cframe.Position)
	end
	return CFrame.lookAt(cframe.Position, cframe.Position + look.Unit)
end

local handlers: { [string]: Handler } = {}

handlers.Kick = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	local label = describe(target)
	local reason = filterForBroadcast(context.Reason, context.Actor.UserId) or Settings.Messages.DefaultReason
	target:Kick(string.format(Settings.Messages.Kick, reason))
	return "Success", string.format("Kicked %s.", label)
end

handlers.Ban = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	local label = describe(target)
	local duration = Protocol.BanDurations[context.DurationIndex]
	local reason = filterForBroadcast(context.Reason, context.Actor.UserId) or Settings.Messages.DefaultReason
	sessionBans[target.UserId] = if duration.Seconds < 0 then math.huge else os.clock() + duration.Seconds
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { target.UserId },
			Duration = duration.Seconds,
			DisplayReason = reason,
			PrivateReason = string.format(
				"Issued by %s (%d) through DEDHEC Panel. Reason: %s",
				context.Actor.Name,
				context.Actor.UserId,
				reason
			),
			ExcludeAltAccounts = false,
			ApplyToUniverse = true,
		})
	end)
	if target.Parent == Players then
		target:Kick(string.format(Settings.Messages.Ban, reason))
	end
	if ok then
		return "Success", string.format("Banned %s for %s.", label, string.lower(duration.Label))
	end
	warn(string.format("[DEDHEC] BanAsync failed for %d: %s", target.UserId, tostring(err)))
	return "Warning", string.format("Ban API unavailable, %s is banned from this server only.", label)
end

handlers.Scare = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	local now = os.clock()
	local previous = lastScareAt[target]
	if previous and now - previous < Protocol.Limits.ScareCooldown then
		return "Warning", string.format("%s was scared moments ago.", describe(target))
	end
	lastScareAt[target] = now
	effectRemote:FireClient(target, Protocol.Effects.Scare)
	return "Success", string.format("Scared %s.", describe(target))
end

handlers.Kill = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	local _, humanoid = getRig(target)
	if not humanoid or humanoid.Health <= 0 then
		return "Warning", string.format("%s has no living character.", describe(target))
	end
	humanoid.Health = 0
	return "Success", string.format("Killed %s.", describe(target))
end

handlers.Freeze = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	local character, humanoid, root = getRig(target)
	if not character or not humanoid or not root then
		return "Warning", string.format("%s has no character to freeze.", describe(target))
	end
	if character:GetAttribute(Protocol.Attributes.Frozen) == true then
		root.Anchored = false
		character:SetAttribute(Protocol.Attributes.Frozen, nil)
		return "Success", string.format("Unfroze %s.", describe(target))
	end
	releaseSeat(humanoid)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	character:SetAttribute(Protocol.Attributes.Frozen, true)
	return "Success", string.format("Froze %s.", describe(target))
end

handlers.Bring = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	local _, _, actorRoot = getRig(context.Actor)
	local targetCharacter, targetHumanoid = getRig(target)
	if not actorRoot then
		return "Warning", "You need a character to bring players."
	end
	if not targetCharacter or not targetHumanoid then
		return "Warning", string.format("%s has no character.", describe(target))
	end
	releaseSeat(targetHumanoid)
	targetCharacter:PivotTo(levelled(actorRoot.CFrame) * CFrame.new(0, 0, -5) * CFrame.Angles(0, math.pi, 0))
	return "Success", string.format("Brought %s to you.", describe(target))
end

handlers.Goto = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	local actorCharacter, actorHumanoid = getRig(context.Actor)
	local _, _, targetRoot = getRig(target)
	if not actorCharacter or not actorHumanoid then
		return "Warning", "You need a character to teleport."
	end
	if not targetRoot then
		return "Warning", string.format("%s has no character.", describe(target))
	end
	releaseSeat(actorHumanoid)
	actorCharacter:PivotTo(levelled(targetRoot.CFrame) * CFrame.new(0, 0, 5))
	return "Success", string.format("Teleported to %s.", describe(target))
end

handlers.Respawn = function(context: Context): (Tone, string)
	local target = context.Target :: Player
	target:LoadCharacterAsync()
	return "Success", string.format("Respawned %s.", describe(target))
end

handlers.Terminate = function(context: Context): (Tone, string)
	if not Settings.AllowTerminate then
		return "Error", "Terminate is disabled in Settings."
	end
	serverTerminated = true
	local actor = context.Actor
	for _, player in Players:GetPlayers() do
		if player ~= actor then
			player:Kick(Settings.Messages.Terminated)
		end
	end
	task.delay(1, function()
		if actor.Parent == Players then
			actor:Kick(Settings.Messages.Terminated)
		end
	end)
	return "Success", "Server terminated. Disconnecting everyone."
end

local function dispatch(actor: Player, actionId: unknown, targetUserId: unknown, rawOptions: unknown): (Tone, string)
	if not isAdmin(actor) then
		return "Error", "You are not authorized to use this panel."
	end
	if typeof(actionId) ~= "string" then
		return "Error", "Malformed request."
	end
	local spec = Protocol.Actions[actionId]
	local handler = handlers[actionId]
	if not spec or not handler then
		return "Error", "Unknown action."
	end

	local target: Player? = nil
	if spec.RequiresTarget then
		if typeof(targetUserId) ~= "number" or targetUserId % 1 ~= 0 then
			return "Error", "Malformed target."
		end
		target = Players:GetPlayerByUserId(targetUserId)
		if not target then
			return "Error", "That player is no longer in the server."
		end
		if target == actor and not spec.AllowSelf then
			return "Error", "You can't use that action on yourself."
		end
		if spec.ProtectAdmins and target ~= actor and isRealAdmin(target) then
			return "Error", string.format("%s is an administrator and is protected.", describe(target))
		end
	end

	local rawReason, rawDuration = readOptions(rawOptions)
	local durationIndex = readDurationIndex(rawDuration)
	if actionId == "Ban" and not durationIndex then
		return "Error", "Pick a valid ban duration."
	end

	local tone: Tone, message: string = handler({
		Actor = actor,
		Target = target,
		Reason = sanitizeReason(rawReason),
		DurationIndex = durationIndex or 1,
	})

	if Settings.LogActions then
		print(
			string.format(
				"[DEDHEC] %s (%d) -> %s%s",
				actor.Name,
				actor.UserId,
				actionId,
				if target then string.format(" -> %s (%d)", target.Name, target.UserId) else ""
			)
		)
	end

	return tone, message
end

handshakeRemote.OnServerInvoke = function(player: Player): Protocol.Access
	local authorized = isAdmin(player)
	return {
		Authorized = authorized,
		CanTerminate = authorized and Settings.AllowTerminate,
	}
end

requestRemote.OnServerInvoke = function(
	player: Player,
	actionId: unknown,
	targetUserId: unknown,
	rawOptions: unknown
): (string, string)
	if busyActors[player] then
		return "Warning", "Your previous action is still running."
	end
	local now = os.clock()
	local previous = lastRequestAt[player]
	if previous and now - previous < Protocol.Limits.RequestInterval then
		return "Warning", "You're doing that too fast."
	end
	lastRequestAt[player] = now
	busyActors[player] = true
	local ok, tone, message = pcall(dispatch, player, actionId, targetUserId, rawOptions)
	busyActors[player] = nil
	if not ok then
		warn(string.format("[DEDHEC] Request from %s failed: %s", player.Name, tostring(tone)))
		return "Error", "That action failed. Check the server output."
	end
	return tone, message
end

local function onPlayerAdded(player: Player)
	if serverTerminated then
		player:Kick(Settings.Messages.Terminated)
		return
	end
	local banExpiry = sessionBans[player.UserId]
	if banExpiry then
		if os.clock() < banExpiry then
			player:Kick(Settings.Messages.SessionBan)
			return
		end
		sessionBans[player.UserId] = nil
	end
	isRealAdmin(player)
end

local function onPlayerRemoving(player: Player)
	adminCache[player] = nil
	busyActors[player] = nil
	lastRequestAt[player] = nil
	lastScareAt[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
