local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("DedhecPanel")
local Protocol = require(sharedFolder:WaitForChild("Protocol"))
local Scare = require(script.Scare)

local effectRemote = sharedFolder:WaitForChild(Protocol.Remotes.Effect) :: RemoteEvent
local handshakeRemote = sharedFolder:WaitForChild(Protocol.Remotes.Handshake) :: RemoteFunction
local requestRemote = sharedFolder:WaitForChild(Protocol.Remotes.Request) :: RemoteFunction

effectRemote.OnClientEvent:Connect(function(effect: unknown)
	if effect == Protocol.Effects.Scare then
		Scare.play()
	end
end)

local function readAccess(response: unknown): Protocol.Access?
	if typeof(response) ~= "table" then
		return nil
	end
	local fields = response :: { [unknown]: unknown }
	local authorized = rawget(fields, "Authorized")
	local canTerminate = rawget(fields, "CanTerminate")
	if typeof(authorized) ~= "boolean" or typeof(canTerminate) ~= "boolean" then
		return nil
	end
	return {
		Authorized = authorized,
		CanTerminate = canTerminate,
	}
end

local ok, response = pcall(handshakeRemote.InvokeServer, handshakeRemote)
local access = if ok then readAccess(response) else nil

if access and access.Authorized then
	require(script.Panel).mount({
		Request = requestRemote,
		Access = access,
	})
end
