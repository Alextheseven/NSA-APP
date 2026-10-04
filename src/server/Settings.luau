export type GroupRule = {
	GroupId: number,
	MinimumRank: number,
}

local Settings = {
	AdminUserIds = {} :: { number },
	AdminGroups = {} :: { GroupRule },
	CreatorHasAccess = true,
	CreatorGroupMinimumRank = 255,
	StudioGrantsAccess = true,
	AllowTerminate = true,
	LogActions = true,
	Messages = {
		Kick = "You were kicked by an administrator.\nReason: %s",
		Ban = "You have been banned from this experience.\nReason: %s",
		SessionBan = "You are banned from this server.",
		Terminated = "This server has been terminated by an administrator.",
		DefaultReason = "No reason provided.",
	},
}

return Settings
