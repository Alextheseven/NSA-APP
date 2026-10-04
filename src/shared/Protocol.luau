export type Tone = "Success" | "Warning" | "Error"

export type ActionSpec = {
	RequiresTarget: boolean,
	AllowSelf: boolean,
	ProtectAdmins: boolean,
}

export type DurationOption = {
	Label: string,
	Seconds: number,
}

export type Access = {
	Authorized: boolean,
	CanTerminate: boolean,
}

local Protocol = {
	Remotes = {
		Handshake = "Handshake",
		Request = "Request",
		Effect = "Effect",
	},
	Effects = {
		Scare = "Scare",
	},
	Attributes = {
		Frozen = "DedhecFrozen",
	},
	Limits = {
		ReasonLength = 120,
		RawReasonBytes = 2048,
		RequestInterval = 0.25,
		ScareCooldown = 4,
	},
	BanDurations = {
		{ Label = "1 Hour", Seconds = 3600 },
		{ Label = "1 Day", Seconds = 86400 },
		{ Label = "7 Days", Seconds = 604800 },
		{ Label = "Permanent", Seconds = -1 },
	} :: { DurationOption },
	Actions = {
		Ban = { RequiresTarget = true, AllowSelf = false, ProtectAdmins = true },
		Kick = { RequiresTarget = true, AllowSelf = false, ProtectAdmins = true },
		Scare = { RequiresTarget = true, AllowSelf = true, ProtectAdmins = false },
		Kill = { RequiresTarget = true, AllowSelf = true, ProtectAdmins = true },
		Freeze = { RequiresTarget = true, AllowSelf = true, ProtectAdmins = true },
		Bring = { RequiresTarget = true, AllowSelf = false, ProtectAdmins = false },
		Goto = { RequiresTarget = true, AllowSelf = false, ProtectAdmins = false },
		Respawn = { RequiresTarget = true, AllowSelf = true, ProtectAdmins = false },
		Terminate = { RequiresTarget = false, AllowSelf = true, ProtectAdmins = false },
	} :: { [string]: ActionSpec },
}

return Protocol
