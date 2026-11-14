-- Luacheck settings: Lua 5.1 as the game runs it, plus the game's globals the add-on reads.
std = "lua51"
max_line_length = false
exclude_files = { "dist/" }
-- Unused arguments are usually a callback's fixed signature (self, event, ...).
unused_args = false

globals = { "CraftingAndFarmingForeverDB", "SLASH_CFF1", "SLASH_CFF2" }

read_globals = {
	"ATTACHMENTS_MAX_RECEIVE", "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
	"AUCTION_SOLD_MAIL_SUBJECT", "AuctionHouseFrame", "Auctionator", "CANCEL", "C_AddOns", "C_AuctionHouse",
	"C_Container", "C_Item", "C_Map", "C_QuestLog", "C_Spell", "C_Timer", "C_TradeSkillUI", "ChatEdit_GetLastTellTarget",
	"ChatFrame1", "ChatFrameUtil", "ChatFrame_OpenChat", "CreateColor", "CreateFrame", "Enum", "GameTooltip",
	"GameTooltip_Hide", "GetCVarBool", "GetChannelList", "GetCursorPosition", "GetInboxHeaderInfo",
	"GetInboxInvoiceInfo", "GetInboxItem", "GetInboxNumItems", "GetMoney", "GetRealmName", "GetSpellInfo",
	"GetSpellTexture", "GetTime", "HideUIPanel", "InCombatLockdown", "IsControlKeyDown", "IsInGuild", "IsInInstance",
	"InterfaceOptions_AddCategory", "IsShiftKeyDown", "ItemLocation", "LibStub", "Minimap", "NO", "ProfessionsFrame", "Settings", "SettingsPanel", "StaticPopup_Hide",
	"StaticPopup_Show", "TRADE", "UIParent", "UnitCastingInfo", "UnitClass", "UnitGUID", "UnitName", "YES",
	"date", "geterrorhandler", "hooksecurefunc", "issecretvalue", "time", "wipe",
	-- Tables the add-on adds entries to.
	SlashCmdList = { other_fields = true, read_only = false },
	StaticPopupDialogs = { other_fields = true, read_only = false },
	UISpecialFrames = { other_fields = true, read_only = false },
}

-- Generated data.
files["Sources.lua"] = { ignore = { "631" } }
-- The tests stand in for the game, so they define its globals.
files["tests/"] = { std = "lua51", ignore = { "111", "112", "113", "121", "122", "131", "142", "143", "4.." } }
