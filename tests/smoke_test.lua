-- Loads the whole add-on against a stubbed client and drives the main flow, to catch runtime errors in code paths
-- that plain logic tests don't reach. It can't prove the real client behaves like the stubs.
-- Run from the repo root: lua tests/smoke_test.lua

local failures, checks = 0, 0
local function check(name, actual, expected)
	checks = checks + 1
	if actual ~= expected then
		failures = failures + 1
		print(("FAIL %s: expected %s, got %s"):format(name, tostring(expected), tostring(actual)))
	end
end

---------------------------------------------------------------------------
-- Stub client
---------------------------------------------------------------------------

local eventFrames = {}
local timers = {}

local function NewFrame()
	local frame = { scripts = {}, shown = false, height = 400 }
	return setmetatable(frame, { __index = function(_, key)
		if key == "professionID" or key == "data" or key == "target" or key == "width" then return nil end -- add-on data on a frame, not a method
		local methods = {
			SetScript = function(self, name, fn) self.scripts[name] = fn end,
			HookScript = function(self, name, fn) self.scripts[name] = fn end,
			RegisterEvent = function(self) eventFrames[self] = true end,
			Show = function(self)
				local was = self.shown
				self.shown = true
				if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
			end,
			Hide = function(self)
				local was = self.shown
				self.shown = false
				if was and self.scripts.OnHide then self.scripts.OnHide(self) end
			end,
			SetShown = function(self, on) if on then self:Show() else self:Hide() end end,
			IsShown = function(self) return self.shown end,
			IsVisible = function(self)
				local parent = rawget(self, "parent")
				return self.shown and (parent == nil or parent:IsVisible())
			end,
			GetHeight = function(self) return self.height end,
			SetHeight = function(self, height) self.height = height end,
			SetSize = function(self, width, height) self.width, self.height = width, height end,
			SetWidth = function(self, width) self.width = width end,
			GetWidth = function(self) return self.width or 0 end,
			GetLeft = function() return 100 end,
			GetRight = function() return 480 end,
			GetTop = function() return 900 end,
			SetText = function(self, text) self.text = text end,
			SetTexture = function(self, texture) self.texture = texture end,
			SetAttribute = function(self, name, value)
				rawset(self, "attributes", rawget(self, "attributes") or {})
				self.attributes[name] = value
			end,
			SetPoint = function(self, ...) self.lastPoint = { ... } end,
			GetText = function(self) return self.text end,
			GetParent = function(self) return self.parent end,
			CreateTexture = function(self) return NewFrame() end,
			CreateFontString = function(self) return NewFrame() end,
		}
		return methods[key] or function() end
	end })
end

function CreateFrame(_, _, parent)
	local frame = NewFrame()
	frame.parent = parent
	return frame
end

UIParent = NewFrame()
Minimap = NewFrame()
Minimap.GetWidth = function() return 140 end
UIParent.shown = true
UIParent.GetWidth = function() return 2000 end
ChatFrame1 = NewFrame()
function geterrorhandler() return function(err) error(err, 0) end end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
time = os.time
function UnitGUID() return "Player-1-AAA" end
function UnitName() return "Snic" end
function UnitClass() return "Paladin" end
function UnitCastingInfo() return nil end
function GetRealmName() return "Realm" end
shiftDown, ctrlDown = false, false
function IsShiftKeyDown() return shiftDown end
function IsControlKeyDown() return ctrlDown end
local clock = 0
function GetTime() clock = clock + 1 return clock end
function GameTooltip_Hide() end
GameTooltip = NewFrame()
YES, NO = "Yes", "No"
StaticPopupDialogs = {}
function StaticPopup_Show(name, _, _, data) ns_popup, ns_popupData = name, data end
function StaticPopup_Hide() end
SlashCmdList = {}
UISpecialFrames = {}
TRADE = "Trade"
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
	RegisterAddOnCategory = function(category) registeredCategory = category end,
}
channelList = { 1, "General - City", false, 2, "Trade - City", false, 4, "LocalDefense - City", false }
function GetChannelList() return unpack(channelList) end
inGuild = true
function IsInGuild() return inGuild end
playerMoney = 0
function GetMoney() return playerMoney end
inCombat = false
function InCombatLockdown() return inCombat end
inInstance = false
function IsInInstance() return inInstance, inInstance and "party" or "none" end
useKeyDown = false
function GetCVarBool() return useKeyDown end
sentChat = {}
function SendChatMessage(message, chatType, _, target) table.insert(sentChat, { message = message, chatType = chatType, target = target }) end
function ChatFrame_OpenChat(text) chatBoxText = text end
date = os.date
hooksecurefunc = function(target, name, fn)
	local original = target[name]
	target[name] = function(...)
		local a, b, c, d, e = original(...)
		fn(...)
		return a, b, c, d, e
	end
end
inbox = {}
inboxTotal = nil -- mails waiting beyond the ones shown, when set
function GetInboxNumItems() return #inbox, inboxTotal or #inbox end
function GetInboxHeaderInfo(i)
	local m = inbox[i]
	return nil, nil, "Auction House", m.subject, m.money, 0, m.daysLeft, m.itemID ~= nil
end
function GetInboxItem(i)
	local m = inbox[i]
	return "Item", m.itemID, 1, m.count
end
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
Enum = { CraftingReagentType = { Basic = 0 }, ItemClass = { Weapon = 2, Armor = 4 } }
print = print

C_AuctionHouse = {
	SendSearchQuery = function() end,
	SendSellSearchQuery = function() end,
	PostItem = function() end,
	PostCommodity = function() end,
	ConfirmCommoditiesPurchase = function() end,
	PlaceBid = function() end,
	GetNumItemSearchResults = function() return #itemResults end,
	GetItemSearchResultInfo = function(_, index) return itemResults[index] end,
	GetNumCommoditySearchResults = function() return 0 end,
	GetCommoditySearchResultInfo = function() return nil end,
	IsThrottledMessageSystemReady = function() return true end,
	MakeItemKey = function(itemID) return { itemID = itemID } end,
	GetItemKeyInfo = function() return {} end,
}
itemResults = {}
ATTACHMENTS_MAX_RECEIVE = 1
local tocVersion
for line in io.lines("CraftingAndFarmingForever.toc") do tocVersion = tocVersion or line:match("^## Version: *(%S+)") end
syndicatorLoaded = true
C_AddOns = {
	GetAddOnMetadata = function(name, field)
		if name == "CraftingAndFarmingForever" and field == "Version" then return tocVersion end
	end,
	IsAddOnLoaded = function(name) return name == "Syndicator" and syndicatorLoaded end,
}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
local function RunTimers()
	for _ = 1, 20 do
		local batch = timers
		timers = {}
		for _, fn in ipairs(batch) do fn() end
		if #timers == 0 then return end
	end
end

local names = { [1] = "Linen Cloth", [2] = "Bolt of Linen", [3] = "Coarse Thread", [4] = "Linen Shirt", [5] = "Soulbound Robe" }
local namesReady = false
local requests = {}
C_Item = {
	GetItemInfoInstant = function(itemID) return itemID, "", "", "", 1, 7, 0 end,
	GetItemNameByID = function(id) return namesReady and names[id] or nil end,
	GetItemIconByID = function() return 1 end,
	RequestLoadItemDataByID = function(id) requests[id] = true end,
	GetItemInfo = function(id)
		if not namesReady then return nil end
		local bind = id == 5 and 1 or 2
		return names[id], "link", 1, 1, 1, "", "", 1, "", 1, 1, 1, 1, bind
	end,
	GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end,
	GetItemCount = function(id) return id == 1 and 3 or 0 end,
	GetItemID = function(location) return location.itemID end,
}

local crafted = {}
local tradeSkillReady = false
C_TradeSkillUI = {
	IsTradeSkillReady = function() return tradeSkillReady end,
	GetCraftableCount = function(id) return id == 10 and 5 or 0 end,
	IsTradeSkillLinked = function() return false end,
	IsTradeSkillGuild = function() return false end,
	IsNPCCrafting = function() return false end,
	GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Tailoring" } end,
	GetChildProfessionInfo = function() return nil end,
	GetAllRecipeIDs = function() return { 10, 20, 30, 40 } end,
	-- Colours: 10 orange, 20 yellow giving 2 points, 30 grey.
	GetRecipeInfo = function(id)
		local difficulty = ({ [10] = 0, [20] = 1, [30] = 3 })[id]
		return { recipeID = id, learned = id ~= 40, name = "Recipe" .. id, relativeDifficulty = difficulty,
			numSkillUps = id == 20 and 2 or 1 }
	end,
	GetRecipeSchematic = function(id)
		local s = {
			[10] = { outputItemID = 2, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { reagentType = 0, quantityRequired = 2, reagents = { { itemID = 1 } } } } },
			[20] = { outputItemID = 4, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
				{ reagentType = 0, quantityRequired = 3, reagents = { { itemID = 2 } } },
				{ reagentType = 0, quantityRequired = 1, reagents = { { itemID = 3 } } },
				{ reagentType = 1, quantityRequired = 1, required = false, reagents = { { itemID = 99 } } },
			} },
			[30] = { outputItemID = 5, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 1 } } } } },
			[40] = { outputItemID = 5, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {} },
		}
		return s[id]
	end,
	GetRecipeItemLink = function() return nil end,
	GetTradeSkillListLink = function() return "|ctrade|Htrade:197|h[Tailoring]|h|r" end,
	CraftRecipe = function(id, count) table.insert(crafted, { id = id, count = count }) end,
	OpenRecipe = function() end,
}

-- Auctionator stand-in that keeps a real list so the sync can be checked.
local lists = {}
local createCalls = 0
local prices = { [1] = 10, [2] = 100, [4] = 1000, [5] = 500 }
local listManager = {
	GetIndexForName = function(_, name) return lists[name] and 1 or nil end,
	Delete = function(_, name) lists[name] = nil end,
	GetByName = function(_, name)
		return {
			InsertItem = function(_, s) table.insert(lists[name], s) end,
			GetAllItems = function() return lists[name] end,
		}
	end,
}
local busListener
Auctionator = {
	EventBus = { Register = function(_, listener, events) busListener = listener; busEvents = events end },
	FullScan = { Events = { ScanStart = "full start", ScanComplete = "full done", ScanFailed = "full failed" } },
	IncrementalScan = { Events = { ScanStart = "incremental start" } },
	SavedState = { TimeOfLastBrowseScan = os.time() - 90000 },
	State = {},
	Config = { Options = { REPLICATE_SCAN = "r" }, Get = function() return false end },
	Shopping = { ListManager = listManager, Tab = { Events = { SearchStart = "shopping start", SearchEnd = "shopping end" } } },
	API = { v1 = {
		GetAuctionPriceByItemID = function(_, id) return prices[id] end,
		GetVendorPriceByItemID = function(_, id) return id == 3 and 10 or nil end,
		GetAuctionAgeByItemID = function() return 0 end,
		RegisterForDBUpdate = function() end,
		ConvertToSearchString = function(_, t) return ('"%s";;;;;;;;;;;#;;%s'):format(t.searchString, tostring(t.quantity or "")) end,
		GetShoppingListItems = function(_, name) -- a copy, as the real API returns
			local copy = {}
			for i, v in ipairs(lists[name]) do copy[i] = v end
			return copy
		end,
		CreateShoppingList = function(_, name, strings) createCalls = createCalls + 1; lists[name] = strings end,
		DeleteShoppingListItem = function(_, name, s)
			for i, v in ipairs(lists[name]) do if v == s then table.remove(lists[name], i) return end end
		end,
		AlterShoppingListItem = function(_, name, old, new)
			for i, v in ipairs(lists[name]) do if v == old then lists[name][i] = new return end end
		end,
	} },
}

local page = NewFrame()
page.SchematicForm = NewFrame()
local selected = { recipeID = 20, learned = true }
page.SchematicForm.GetRecipeInfo = function() return selected end
page.CreateAllButton = NewFrame()
page.CreateMultipleInputBox = NewFrame()
page.CreateMultipleInputBox.GetValue = function() return 2 end
ProfessionsFrame = NewFrame()
ProfessionsFrame.GetProfessionInfo = function()
	return { professionID = 197, professionName = "Tailoring", skillLevel = 50, maxSkillLevel = 75 }
end
ProfessionsFrame.CraftingPage = page
AuctionHouseFrame = NewFrame()

---------------------------------------------------------------------------
-- Load the add-on
---------------------------------------------------------------------------

local ns = {}
for line in io.lines("CraftingAndFarmingForever.toc") do
	if line:match("%.lua$") then
		local chunk = assert(loadfile(line))
		chunk("CraftingAndFarmingForever", ns)
	end
end

-- Without running timers: what the add-on sees before its debounced work (like the plan rebuild) has happened.
local function FireNow(event, ...)
	for frame in pairs(eventFrames) do
		if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
	end
end

local function Fire(event, ...)
	FireNow(event, ...)
	RunTimers()
end

---------------------------------------------------------------------------
-- Flow
---------------------------------------------------------------------------

Fire("ADDON_LOADED", "CraftingAndFarmingForever")
Fire("PLAYER_LOGIN")
check("price cap on by default", ns.Queue.PriceCap() ~= nil, true)
-- The fixture's sale prices are far above material cost; the cap has its own test further down.
ns.db.ui.priceCap = false
-- And the add-on's own searches of what it has to buy, which the auction house tests would otherwise have to count.
ns.db.ui.depthCheck = false
check("no list before anything is queued", lists[ns.LIST_NAME], nil)
check("nothing unseen before the saved data is known", ns.WhatsNew.HasUnseen(), false)

ProfessionsFrame:Show()
Fire("ADDON_LOADED", "Blizzard_Professions")
Fire("TRADE_SKILL_SHOW")
Fire("TRADE_SKILL_LIST_UPDATE")
check("nothing recorded before the list is ready", next(ns.db.recipes), nil)
tradeSkillReady = true
Fire("TRADE_SKILL_LIST_UPDATE")

local me = ns.CharKey()
check("learned recipe recorded", ns.db.chars[me].recipes[10], true)
check("unlearned recipe not recorded", ns.db.chars[me].recipes[40], nil)
check("optional reagent excluded", #ns.db.recipes[20].r, 2)

-- Switching professions: the window already says Blacksmithing while the list is still Tailoring's. Reading it
-- then forgot the new profession's recipes and filed the old ones under it; it now waits for the right list.
do
	local realInfo = ProfessionsFrame.GetProfessionInfo
	ns.db.recipes[50] = { n = "Smelt", o = 6, p = 164, pn = "Blacksmithing", r = { { 1, 1 } } }
	ns.db.chars[me].recipes[50] = true
	ProfessionsFrame.GetProfessionInfo = function() return { professionID = 164, professionName = "Blacksmithing" } end
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("switching: other profession's recipes kept", ns.db.chars[me].recipes[50], true)
	check("switching: list not filed under the new one", ns.db.recipes[10].p, 197)
	ProfessionsFrame.GetProfessionInfo = realInfo
	ns.db.recipes[50], ns.db.chars[me].recipes[50] = nil, nil
end

-- A recipe cooldown read a second apart (time() is whole seconds, the time left isn't) isn't a change: it replanned
-- at every profession scan while a transmute was on cooldown.
do
	local realTime, realForget = time, ns.Restock.ForgetSmart
	local now, left, forgets = 1000000, 3599.6, 0
	time = function() return now end
	ns.Restock.ForgetSmart = function() forgets = forgets + 1 end
	C_TradeSkillUI.GetRecipeCooldown = function(id) if id == 10 then return left end end
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("cooldown: recorded", ns.db.chars[me].cooldowns[10].r, 1003599)
	forgets = 0
	now, left = 1000001, 3599.4 -- the same end, read 0.2 s later across a whole second
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("cooldown: a second's jitter is no change", forgets, 0)
	check("cooldown: ready time kept", ns.db.chars[me].cooldowns[10].r, 1003599)
	left = 0
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("cooldown: ready is a change", forgets, 1)
	C_TradeSkillUI.GetRecipeCooldown = nil
	ns.db.chars[me].cooldowns = nil
	time, ns.Restock.ForgetSmart = realTime, realForget
end

-- A known recipe is only forgotten when the game says outright, twice and 10 s apart, that it isn't learned.
do
	local realIDs, realRecipeInfo = C_TradeSkillUI.GetAllRecipeIDs, C_TradeSkillUI.GetRecipeInfo
	-- Missing from the list (still loading): kept, however often it's read.
	C_TradeSkillUI.GetAllRecipeIDs = function() return { 10, 20, 40 } end
	Fire("TRADE_SKILL_LIST_UPDATE")
	clock = clock + 60
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("missing from the list: kept", ns.db.chars[me].recipes[30], true)
	C_TradeSkillUI.GetAllRecipeIDs = realIDs
	-- Listed as not learned for a moment (the list still loading): kept.
	C_TradeSkillUI.GetRecipeInfo = function(id)
		local info = realRecipeInfo(id)
		if id == 30 then info.learned = false end
		return info
	end
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("not learned once: kept", ns.db.chars[me].recipes[30], true)
	C_TradeSkillUI.GetRecipeInfo = realRecipeInfo
	Fire("TRADE_SKILL_LIST_UPDATE")
	C_TradeSkillUI.GetRecipeInfo = function(id)
		local info = realRecipeInfo(id)
		if id == 30 then info.learned = false end
		return info
	end
	clock = clock + 60
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("learned in between: the wait starts over", ns.db.chars[me].recipes[30], true)
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("not learned again within 10 s: kept", ns.db.chars[me].recipes[30], true)
	-- Still not learned 10 s later: really unlearned.
	clock = clock + 10
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("not learned 10 s later: forgotten", ns.db.chars[me].recipes[30], nil)
	C_TradeSkillUI.GetRecipeInfo = realRecipeInfo
	Fire("TRADE_SKILL_LIST_UPDATE")
	check("learned again: back", ns.db.chars[me].recipes[30], true)
end

-- Item data not loaded yet: nothing is sent to Auctionator without a name.
ns.Queue.Add(20, 2)
RunTimers()
check("nameless items not listed", lists[ns.LIST_NAME], nil)
check("names requested", requests[1], true)
check("loading reported", ns.Shopping.status.loading > 0, true)

namesReady = true
Fire("GET_ITEM_INFO_RECEIVED", 1, true)
Fire("GET_ITEM_INFO_RECEIVED", 3, true)
Fire("GET_ITEM_INFO_RECEIVED", 5, true)

-- 2 shirts: 6 bolts crafted = 12 cloth, 3 owned, buy 9; thread is a vendor item.
check("plan buys remaining cloth", ns.plan.buy[1], 9)
check("thread on vendor list", ns.plan.vendor[3], 2)
check("list created once", createCalls, 1)
check("list has only the material, not the queued item", #lists[ns.LIST_NAME], 1)
check("list search string", lists[ns.LIST_NAME][1], '"Linen Cloth";;;;;;;;;;;#;;9')

-- The buy list shows the price the profit assumes; the vendor list shows its fixed price.
ns.UI.Show("queue")
RunTimers()
local function QueueRowText(itemID)
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "item" and row.data.itemID == itemID then return row.right.text end
	end
end
check("AH row shows price and total", QueueRowText(1), "x9, max 10c, total 90c")
check("vendor row shows price and total", QueueRowText(3), "x2, at 10c, total 20c")
local function QueueHeaders()
	local headers = {}
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "header" then table.insert(headers, row.left.text) end
	end
	return table.concat(headers, "\n")
end
check("AH section subtotal", QueueHeaders():find("Buy at auction house: 90c", 1, true) ~= nil, true)
check("vendor section subtotal", QueueHeaders():find("Buy from vendor: 20c", 1, true) ~= nil, true)
-- The Queue tab reads as a to-do list: buy first, then the sub-crafts, and the queued crafts last.
check("queue steps in order", (QueueHeaders():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), table.concat({
	"1. Buy at auction house: 90c (red: dearer since last scan, green: cheaper)",
	"2. Buy from vendor: 20c",
	"3. Sub-crafts (cheaper than buying)",
	"4. Craft your queue",
}, "\n"))

-- Queued crafts and sub-crafts are coloured by how hard they are for their crafter (20 yellow, 10 orange).
do
	local names, tooltip = {}, {}
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		local data = row.data
		if data and data.kind == "queue" then names[data.entry.recipeID] = row.left.text end
		if data and data.kind == "auto" then names[data.craft.recipeID] = row.left.text end
	end
	check("queued craft is yellow", (names[20] or ""):find("^|cffffff00") ~= nil, true)
	check("sub-craft is orange", (names[10] or ""):find("^|cffff8040") ~= nil, true)
	local realAddLine = GameTooltip.AddLine
	GameTooltip.AddLine = function(_, text) table.insert(tooltip, text) end
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "queue" then row.scripts.OnEnter(row) end
	end
	GameTooltip.AddLine = realAddLine
	check("tooltip names the colour", table.concat(tooltip, "\n"):find("Yellow|r: 2 skill points about every other craft", 1, true) ~= nil, true)
	check("unseen recipe has no colour", ns.Recipes.Difficulty(ns.CharKey(), 999999), nil)
end

-- Still to buy against the gold carried: 90c AH + 20c vendor = 1s 10c.
check("plan cost", ns.plan.cost, 110)
playerMoney = 200
check("enough gold", ns.UI.StillToBuyText(), "Still to buy: 1s 10c. |cff55dd55You have 2s 00c.|r")
playerMoney = 50
check("not enough gold", ns.UI.StillToBuyText(), "Still to buy: 1s 10c. |cffff6655You have 50c, 60c short.|r")
Fire("PLAYER_MONEY")
-- A burst of gold changes (buying at the AH, taking gold from mail) redraws the stock panes once, after the burst.
do
	local realRefresh, redraws = ns.UI.RefreshQueue, 0
	ns.UI.RefreshQueue = function() redraws = redraws + 1 end
	for _ = 1, 20 do FireNow("PLAYER_MONEY") end
	check("no redraw during a gold burst", redraws, 0)
	RunTimers()
	check("one redraw after a gold burst", redraws, 1)
	ns.UI.RefreshQueue = realRefresh
end
ns.UI.Hide()

-- Price changes: a whole-list scan starts a comparison. Dearer materials are red, cheaper green, old and new shown.
local RED, GREEN = "|cffff6655", "|cff55dd55"
ns.UI.Show("queue")
local function Rescan(changes)
	busListener:ReceiveEvent("shopping start", lists[ns.LIST_NAME])
	for id, price in pairs(changes) do prices[id] = price end
	ns.RefreshEverything()
	RunTimers()
end
local function QueueEntryText()
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "queue" then return row.left.text end
	end
end
Rescan({ [1] = 15 })
check("dearer material is red", QueueRowText(1), "x9, " .. RED .. "was 10c, now 15c|r, total 1s 35c")
Rescan({ [1] = 12 })
check("cheaper material is green", QueueRowText(1), "x9, " .. GREEN .. "was 15c, now 12c|r, total 1s 08c")
Rescan({})
check("unchanged after next scan shows no colour", QueueRowText(1), "x9, max 12c, total 1s 08c")

-- A single-item search while buying keeps the colours, and later changes in a scan keep the pre-scan price.
Rescan({ [1] = 20 })
busListener:ReceiveEvent("shopping start", { "one item" })
ns.RefreshEverything()
check("single search keeps colours", QueueRowText(1), "x9, " .. RED .. "was 12c, now 20c|r, total 1s 80c")
prices[1] = 25
ns.RefreshEverything()
check("old stays the pre-scan price", QueueRowText(1), "x9, " .. RED .. "was 12c, now 25c|r, total 2s 25c")

-- Another list's scan is ignored; a full scan starts a comparison.
busListener:ReceiveEvent("shopping start", { "a", "b", "c", "d", "e" })
check("other list keeps colours", QueueRowText(1), "x9, " .. RED .. "was 12c, now 25c|r, total 2s 25c")
busListener:ReceiveEvent("full start")
ns.RefreshEverything()
check("full scan starts a comparison", QueueRowText(1), "x9, max 25c, total 2s 25c")

-- What you're crafting: a lower sale price is bad, so it's red, and profit follows.
Rescan({ [4] = 200, [1] = 10 })
local entryText = QueueEntryText()
check("sale drop is red", entryText:find("sells |r" .. RED .. "was 10s 00c, now 2s 00c|r", 1, true) ~= nil, true)
Rescan({ [4] = 300 })
check("sale rise is green", QueueEntryText():find("sells |r" .. GREEN, 1, true) ~= nil, true)
check("profit uses the new sale price", ns.totals.revenue, 2 * 300 * 0.95)
Rescan({ [4] = 1000, [1] = 10 })
Rescan({})
ns.UI.Hide()

-- A new item has nothing to compare with.
check("no change for unknown item", ns.Prices.Change(12345), nil)

-- Bought 4 cloth: same row is altered, list isn't recreated.
C_Item.GetItemCount = function(id) return id == 1 and 7 or 0 end
Fire("BAG_UPDATE_DELAYED")
check("no recreate on update", createCalls, 1)
check("quantity updated in place", lists[ns.LIST_NAME][1], '"Linen Cloth";;;;;;;;;;;#;;5')

-- Panel, profit: bind-on-pickup results are flagged with no sale or profit, sale items ranked.
ns.UI.Show("profit")
ns.InvalidateProfit()
local sellable = {}
for _, result in ipairs(ns.UI.ComputeProfit()) do sellable[result.recipeID] = result end
check("bind-on-pickup result listed", sellable[30] ~= nil and sellable[30].bound, true)
check("bind-on-pickup has a cost", sellable[30].cost ~= nil, true)
check("bind-on-pickup has no profit", sellable[30].net, nil)
check("sellable result not flagged", sellable[20].bound, nil)
check("sellable result listed", sellable[20] ~= nil, true)
check("sub-craft cost used in profit", sellable[20].cost, 3 * 20 + 10)

-- Tabs and craft button.
ns.UI.Show("queue")
do
	local main, profit, queue = ns.UI.main, ns.UI.windows.profit, ns.UI.windows.queue
	local function Tab(key)
		for _, tab in ipairs(main.tabButtons) do if tab.key == key then return tab end end
	end
	check("tabs share one window", profit.frame.parent, queue.frame.parent)
	check("one tab shows at a time", profit.frame:IsVisible() or not queue.frame:IsVisible(), false)
	check("anchored to the screen", main.frame.lastPoint[2], UIParent)
	Tab("profit").scripts.OnClick(Tab("profit"))
	check("clicking a tab switches", profit.frame:IsVisible() and not queue.frame:IsVisible(), true)
	Tab("queue").scripts.OnClick(Tab("queue"))
	check("queue tab counts its entries", Tab("queue").label.text:find("Queue (1)", 1, true) ~= nil, true)
	check("tab choice saved", ns.db.ui.tab, "queue")

	main.frame.scripts.OnDragStop(main.frame)
	check("moved window keeps its position", ns.db.ui.positions.main.x, 100)
	ns.UI.Hide()
	ns.UI.Show("queue")
	check("reopens where it was put", main.frame.lastPoint[4], 100)
	local left, top = main.frame.lastPoint[4], main.frame.lastPoint[5]
	ProfessionsFrame.scripts.OnShow(ProfessionsFrame)
	check("other windows don't move it", main.frame.lastPoint[4] == left and main.frame.lastPoint[5] == top, true)

	-- Restock can keep the queue beside it. The window grows from its left edge.
	local width = main.frame:GetWidth()
	ns.UI.Show("restock")
	local restock = ns.UI.windows.restock
	check("restock alone", restock.frame:IsVisible() and not queue.frame:IsVisible(), true)
	ns.UI.ToggleQueueBeside()
	check("queue beside restock", restock.frame:IsVisible() and queue.frame:IsVisible(), true)
	check("window grows for it", main.frame:GetWidth() > width, true)
	check("left edge stays", main.frame.lastPoint[4], left)
	check("both tabs lit", Tab("queue").accent:IsShown() and Tab("restock").accent:IsShown(), true)
	ns.UI.Show("queue")
	check("queue already showing, no switch", ns.db.ui.tab, "restock")
	UIParent.GetWidth = function() return 1000 end
	ns.UI.Select("restock")
	check("too wide for the spot: shifts to fit", main.frame.lastPoint[4], 0)
	UIParent.GetWidth = function() return 2000 end
	ns.UI.Show("profit")
	check("beside is only for restock", queue.frame:IsVisible(), false)
	check("width back to normal", main.frame:GetWidth(), width)
	check("back in its spot", main.frame.lastPoint[4], left)
	ns.UI.Show("restock")
	ns.UI.ToggleQueueBeside()
	ns.UI.Show("queue")

	ns.UI.Toggle("queue")
	check("toggling the shown tab closes", ns.UI.IsOpen(), false)
	ns.UI.Toggle("queue")
	check("toggling opens on it", queue.frame:IsVisible(), true)
	ns.UI.ToggleMain()
	check("main toggle closes", ns.UI.IsOpen(), false)
	ns.UI.ToggleMain()
	check("main toggle reopens the last tab", queue.frame:IsVisible(), true)

	-- It closes with the profession window it opened with, unless that was for the auction house.
	ns.UI.Hide()
	ns.UI.Show("queue", true)
	AuctionHouseFrame:Show()
	ProfessionsFrame:Hide()
	check("stays open at the AH", ns.UI.IsOpen(), true)
	AuctionHouseFrame:Hide()
	ProfessionsFrame:Show()
	ProfessionsFrame:Hide()
	check("closes with the profession window", ns.UI.IsOpen(), false)
	ProfessionsFrame:Show()
	ns.UI.Show("queue")
end

-- The window title: the logo, then the full name on two lines, with the tabs placed after it.
check("title shows the full name", ns.UI.main.titleText.text, "Crafting and Farming\nForever")
check("title logo is the add-on's texture", ns.UI.main.logo.texture, "Interface\\AddOns\\CraftingAndFarmingForever\\Media\\Logo")

-- Totals: 2 shirts sell for 1000 each less 5%; each costs 3 bolts at 20 (crafted) + thread 10 = 70.
check("queue total profit", ns.totals.net, 2 * (950 - 70))
check("queue total revenue", ns.totals.revenue, 1900)
check("per-entry profit", ns.totals.entries[1], 1760)

-- Quote: material cost of the whole order plus the margin (default 10%), filled into a reply, never sent.
-- One shirt: 3 bolts at 20c + thread 10c = 70c. The queue holds 2 shirts: 140c + 10% = 1s 54c.
check("default quote margin", ns.Queue.QuoteMargin(), 10)
check("quote text, one craft", ns.Queue.QuoteText(20), "link x1: 77c")
check("quote text, whole order", ns.Queue.QuoteText(20, 2), "link x2: 1s 54c")
local function QueueRow()
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "queue" then return row end
	end
end
ns.UI.Refresh("queue")
check("material cost of the whole entry", QueueRow().cost.text, "1s 40c")
check("quote button shown", QueueRow().quote:IsShown(), true)
check("queue entry is 2 shirts", QueueRow().data.entry.qty, 2)
local chatBefore = #sentChat
function ChatEdit_GetLastTellTarget() return "Customer-Realm" end
local printed = {}
local realPrint = ns.Print
ns.Print = function(text) table.insert(printed, text) end
QueueRow().quote.scripts.OnClick(QueueRow().quote)
ns.Print = realPrint
check("quote warns about old prices", (printed[1] or ""):find("This quote may be off", 1, true) ~= nil, true)
check("quote fills a whisper for the whole order", chatBoxText, "/w Customer-Realm link x2: 1s 54c")
check("quote isn't sent", #sentChat, chatBefore)
ChatEdit_GetLastTellTarget = function() return nil end
QueueRow().quote.scripts.OnClick(QueueRow().quote)
check("quote with no known sender uses reply", chatBoxText, "/r link x2: 1s 54c")
-- WoW Forever names have two parts: /w would take only "Felo" as the name and send "Bank ..." to that player.
ChatEdit_GetLastTellTarget = function() return "Felo Bank" end
QueueRow().quote.scripts.OnClick(QueueRow().quote)
check("quote to a two-part name uses reply", chatBoxText, "/r link x2: 1s 54c")
ChatEdit_GetLastTellTarget = nil

-- Price check from the Options tab: the shirt's 70c of materials sell for 10s, over 400%, so with the check on the
-- row and the queue entry say check price, and profit still counts the 10s listing.
do
	local tabBefore = ns.db.ui.tab
	ns.UI.Show("options")
	local controls = ns.Options.Controls(ns.UI.windows.options.frame)
	controls.priceCap.GetChecked = function() return true end
	controls.priceCap.scripts.OnClick(controls.priceCap)
	check("cap turned on", ns.Option("priceCap"), true)
	RunTimers()
	check("capped queue entry flagged", ns.totals.capped[1], true)
	check("capped revenue at the listing", ns.totals.revenue, 2 * 1000 * 0.95)
	check("max box shows 400", controls.capMax:GetText(), "400")
	controls.capMax:SetText("5000")
	controls.capMax.scripts.OnEnterPressed(controls.capMax)
	RunTimers()
	check("higher limit lets the listing through", ns.totals.capped[1], nil)
	ns.Queue.SetPriceCapPercent(400)
	ns.UI.Show("profit")
	local flagged
	ns.db.ui.priceCap = true
	ns.InvalidateProfit()
	for _, row in ipairs(ns.UI.windows.profit.rows) do
		if row.data and row.data.kind == "profit" and row.data.result.capped then flagged = row end
	end
	check("profit row says check price", flagged and flagged.left:GetText():find("check price", 1, true) ~= nil, true)
	controls.priceCap.GetChecked = function() return false end
	controls.priceCap.scripts.OnClick(controls.priceCap)
	RunTimers()
	ns.UI.Show(tabBefore)
end

-- Options > Chat messages: a menu with a tick box per kind of chat line; a kind turned off stays out of chat, and
-- commands still answer.
do
	local tabBefore = ns.db.ui.tab
	ns.UI.Show("options")
	local controls = ns.Options.Controls(ns.UI.windows.options.frame)
	check("chat: button says all on", controls.chat:GetText(), "Chat messages: all on  >")
	controls.chat.scripts.OnClick(controls.chat)
	check("chat: menu opens", controls.chatMenu:IsShown(), true)
	check("chat: one box per kind", #controls.chatChecks, #ns.CHAT_KINDS)
	local sales = controls.chatChecks[2]
	sales.GetChecked = function() return false end
	sales.scripts.OnClick(sales)
	check("chat: sales off", ns.Option("chatSales"), false)
	check("chat: button counts", controls.chat:GetText(), ("Chat messages: %d of %d on  >"):format(#ns.CHAT_KINDS - 1, #ns.CHAT_KINDS))
	local said = {}
	local realPrint = print
	print = function(text) table.insert(said, text) end
	ns.Say("chatSales", "sold something")
	ns.Say("chatDone", "did something")
	ns.Print("diag line")
	print = realPrint
	check("chat: muted kind stays out", #said, 2)
	check("chat: other kinds still written", said[1]:find("did something", 1, true) ~= nil, true)
	sales.GetChecked = function() return true end
	sales.scripts.OnClick(sales)
	check("chat: sales back on", ns.Option("chatSales"), true)
	controls.chat.scripts.OnClick(controls.chat)
	check("chat: menu closes", controls.chatMenu:IsShown(), false)
	ns.UI.Show(tabBefore)
end

-- The margin box on the Options tab changes the quote and is saved.
do
	local tabBefore = ns.db.ui.tab
	ns.UI.Show("options")
	local box = ns.Options.Controls(ns.UI.windows.options.frame).margin
	check("margin box shows the margin", box:GetText(), "10")
	box:SetText("400")
	box.scripts.OnEnterPressed(box)
	check("margin saved", ns.db.ui.quoteMargin, 400)
	check("400% quote", ns.Queue.QuoteText(20, 2), "link x2: 7s 00c")
	box:SetText("0")
	box.scripts.OnEnterPressed(box)
	check("0% quote is the material cost", ns.Queue.QuoteText(20, 2), "link x2: 1s 40c")
	box:SetText("5000")
	box.scripts.OnEnterPressed(box)
	check("margin capped", ns.db.ui.quoteMargin, ns.Queue.QUOTE_MARGIN_MAX)
	check("box shows the capped margin", box:GetText(), tostring(ns.Queue.QUOTE_MARGIN_MAX))
	box:SetText("25")
	box.scripts.OnEscapePressed(box)
	check("escape keeps the saved margin", box:GetText(), tostring(ns.Queue.QUOTE_MARGIN_MAX))
	box:SetText("10")
	box.scripts.OnEnterPressed(box)
	check("margin back to 10", ns.db.ui.quoteMargin, 10)
	ns.UI.Show(tabBefore)
end

-- The amount box between - and + on a queue row: typed crafts, Escape, Shift -, and 0 removing the entry.
do
	local row = QueueRow()
	local entry = row.data.entry
	check("amount box shown", row.amount:IsShown(), true)
	check("amount box holds the crafts", row.amount:GetText(), "2")
	row.amount:SetText("5")
	row.amount.scripts.OnEnterPressed(row.amount)
	check("typed amount saved", entry.qty, 5)
	RunTimers()
	check("box shows the saved amount", QueueRow().amount:GetText(), "5")
	row = QueueRow()
	row.amount:SetText("9")
	row.amount.scripts.OnEscapePressed(row.amount)
	check("escape puts the amount back", row.amount:GetText(), "5")
	check("escape doesn't save", entry.qty, 5)
	row.amount:SetText("")
	row.amount.scripts.OnEditFocusLost(row.amount)
	check("empty box keeps the amount", entry.qty, 5)
	check("empty box shows the amount again", row.amount:GetText(), "5")
	-- Typing for one entry, then the row is reused for another: the typed amount goes to the first.
	row.amount.target = { entry = entry }
	row.amount:SetText("3")
	row.amount.scripts.OnEditFocusLost(row.amount)
	check("amount follows the entry it was typed for", entry.qty, 3)
	shiftDown = true
	row.minus.scripts.OnClick(row.minus)
	check("shift - stops at one", entry.qty, 1)
	row.minus.scripts.OnClick(row.minus)
	check("shift - at one keeps the entry", #ns.db.queue > 0 and ns.db.queue[1] == entry, true)
	shiftDown = false
	ns.Queue.Set(1, 2)
	RunTimers()

	ns.Queue.Add(10, 3)
	RunTimers()
	local bolts
	for _, r in ipairs(ns.UI.windows.queue.rows) do
		if r.data and r.data.kind == "queue" and r.data.entry.recipeID == 10 then bolts = r end
	end
	bolts.amount:SetText("0")
	bolts.amount.scripts.OnEnterPressed(bolts.amount)
	RunTimers()
	check("0 removes the entry", #ns.db.queue, 1)

	ns_popup = nil
	local clear = ns.UI.windows.queue.clearButton
	clear.scripts.OnClick(clear)
	check("clear asks first", ns_popup, "CFF_CLEAR_QUEUE")
	check("clear doesn't empty before yes", #ns.db.queue, 1)
	ns_popup = nil
end

-- Right-click on a Profit row's +: type how many crafts to queue.
do
	ns.UI.Show("profit")
	local plusRow
	for _, r in ipairs(ns.UI.windows.profit.rows) do
		if r.data and r.data.kind == "profit" and r.data.result.recipeID == 20 then plusRow = r end
	end
	plusRow.plus.scripts.OnClick(plusRow.plus, "RightButton")
	local popup = ns.UI.amountPopup
	check("right-click asks for an amount", popup ~= nil and popup:IsShown(), true)
	check("amount starts at one", popup.box:GetText(), "1")
	popup.box:SetText("4")
	popup.box.scripts.OnEnterPressed(popup.box)
	RunTimers()
	check("typed amount queued", ns.db.queue[1].qty, 6)
	check("popup closes", popup:IsShown(), false)
	ctrlDown = true
	plusRow.plus.scripts.OnClick(plusRow.plus, "LeftButton")
	ctrlDown = false
	check("ctrl-click asks too", popup:IsShown(), true)
	popup.box.scripts.OnEscapePressed(popup.box)
	check("escape closes without queuing", popup:IsShown() == false and ns.db.queue[1].qty == 6, true)
	ns.Queue.Set(1, 2)
	RunTimers()
	ns.UI.Show("queue")
end

-- A recipe with no item, such as an enchant, can still be quoted; a missing price isn't.
ns.db.recipes[600] = { n = "Enchant Boots", qmin = 1, qmax = 1, r = { { 1, 1 } } }
check("no-item recipe quote", ns.Queue.QuoteText(600, 3), "Enchant Boots x3: 33c")
ns.db.recipes[601] = { n = "Unpriced", qmin = 1, qmax = 1, r = { { 1, 77777 } } }
check("no price no quote", ns.Queue.QuoteText(601, 2), nil)
ns.db.recipes[602] = { n = "Batch", qmin = 5, qmax = 5, r = { { 1, 1 } } }
check("batch recipe counts items made", ns.Queue.QuoteText(602, 2), "Batch x10: 22c")
ns.db.recipes[600], ns.db.recipes[601], ns.db.recipes[602] = nil, nil, nil

local craft, count = ns.Queue.NextCraft()
check("next craft is the sub-craft", craft.recipeID, 10)
check("batch limited by materials", count, 5)
ns.Queue.CraftNext()
check("craft called", crafted[1].id, 10)
check("craft count", crafted[1].count, 5)

-- Profession reported under a different ID than the recipe was stored with: still recognised as open.
local realInfo = ProfessionsFrame.GetProfessionInfo
ProfessionsFrame.GetProfessionInfo = function() return { professionID = 2437, professionName = "Classic Tailoring" } end
C_TradeSkillUI.GetCraftableCount = function() return 0 end
local _, _, reason = ns.Queue.NextCraft()
check("no materials reason", reason, "Finish Recipe10 (6 left) first: needs materials.")
C_TradeSkillUI.GetRecipeRequirements = function() return { { name = "Anvil", met = false } } end
_, _, reason = ns.Queue.NextCraft()
check("station reason", reason, "Finish Recipe10 (6 left) first: needs materials and Anvil.")
C_TradeSkillUI.GetCraftableCount = function(id) return id == 10 and 5 or 0 end
_, _, reason = ns.Queue.NextCraft()
check("station blocks craft", reason, "Finish Recipe10 (6 left) first: needs Anvil.")
ProfessionsFrame.GetProfessionInfo = realInfo
C_TradeSkillUI.GetRecipeRequirements = nil

-- The sub-craft can't be made right now but the queued craft could: Craft Next waits, and says what to finish.
C_TradeSkillUI.GetCraftableCount = function(id) return id == 20 and 1 or 0 end
local skipped, _, blockedReason, blocking = ns.Queue.NextCraft()
check("never skips ahead", skipped, nil)
check("names the craft to finish", blocking and blocking.recipeID, 10)
check("says how many are left", blockedReason:find("6 left", 1, true) ~= nil, true)
ns.UI.Refresh("queue")
check("Queue tab button says finish", ns.UI.windows.queue.craftButton.text, "Finish Recipe10: 6 left")
C_TradeSkillUI.GetCraftableCount = function(id) return id == 10 and 5 or 0 end

-- A recipe that isn't in the open window does ask for its profession.
local realIDs = C_TradeSkillUI.GetAllRecipeIDs
C_TradeSkillUI.GetAllRecipeIDs = function() return { 40 } end
_, _, reason = ns.Queue.NextCraft()
check("other profession reason", reason, "Open Tailoring to finish Recipe10 (6 left).")
-- Craft Next opens that profession, then crafts once its recipes have loaded.
local openedSkill
C_TradeSkillUI.OpenTradeSkill = function(id) openedSkill = id end
local _, _, _, _, openID = ns.Queue.NextCraft()
check("Craft Next can open the profession", openID ~= nil and openID == ns.db.recipes[10].p, true)
ns.UI.Refresh("queue")
check("button offers to open", ns.UI.windows.queue.craftButton.text, "Open Tailoring: Recipe10 x6")
local craftedBefore = #crafted
ns.Queue.CraftNext()
check("opened the profession", openedSkill, ns.db.recipes[10].p)
check("nothing crafted before it's open", #crafted, craftedBefore)
C_TradeSkillUI.GetAllRecipeIDs = realIDs
Fire("TRADE_SKILL_LIST_UPDATE")
check("crafted once open", #crafted, craftedBefore + 1)
check("crafted the waiting recipe", crafted[#crafted].id, 10)
Fire("TRADE_SKILL_LIST_UPDATE")
check("crafted only once", #crafted, craftedBefore + 1)
-- If the game blocks that, the next opens wait for a second click.
Fire("ADDON_ACTION_BLOCKED", "CraftingAndFarmingForever", "CraftRecipe")
check("craft after open turned off", ns.db.ui.noCraftAfterOpen, true)
C_TradeSkillUI.GetAllRecipeIDs = function() return { 40 } end
ns.Queue.CraftNext()
C_TradeSkillUI.GetAllRecipeIDs = realIDs
Fire("TRADE_SKILL_LIST_UPDATE")
check("blocked once: opens only", #crafted, craftedBefore + 1)
ns.db.ui.noCraftAfterOpen = nil
C_TradeSkillUI.OpenTradeSkill = nil

-- Queue countdown: craft of the entry itself removes it at zero.
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 20)
check("entry counted down", ns.db.queue[1].qty, 1)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 20)
check("entry removed", #ns.db.queue, 0)
check("list emptied", #lists[ns.LIST_NAME], 0)

-- Restock without Syndicator: rows show, auctions unknown.
ns.db.restock.minProfitSilver = 0
local rows = ns.Restock.Rows()
local shirtRow
for _, row in ipairs(rows) do if row.itemID == 4 then shirtRow = row end end
check("restock lists profitable item", shirtRow ~= nil, true)
check("restock auctions unknown without Syndicator", shirtRow.onAH, nil)
check("single-stack default goal", shirtRow.goal, 1)
check("bind-on-pickup not restocked", (function()
	for _, row in ipairs(rows) do if row.itemID == 5 then return true end end
	return false
end)(), false)
do
	local seconds, direct = ns.Restock.CraftTime({ { recipeID = shirtRow.recipeID, crafts = 2, queued = 1 } })
	check("restock crafting time counts new and queued crafts", direct, 3)
	check("restock crafting time in seconds", seconds >= 3 * ns.Queue.CraftSeconds(shirtRow.recipeID), true)
end
-- Skip for now: no crafts, the goal kept and shown, back after a second click.
do
	local function Shirt()
		for _, row in ipairs((ns.Restock.Rows())) do if row.itemID == 4 then return row end end
	end
	-- Wanted: crafts before any cut to your gold.
	local function Wants() local row = Shirt(); return (row.wanted or row.crafts) > 0 end
	ns.db.restock.goals[4] = 50
	check("skip: crafts wanted before", Wants(), true)
	ns.Restock.SetSkipped(4, true)
	check("skip: no crafts", Wants(), false)
	check("skip: goal shown unchanged", Shirt().goal, 50)
	check("skip: own goal untouched", ns.db.restock.goals[4], 50)
	ns.Restock.SetSkipped(4, false)
	check("skip: crafts back", Wants(), true)
	-- The Profit column shows each row's profit per craft, and the header names it.
	local tabBefore = ns.db.ui.tab
	ns.UI.Show("restock")
	ns.UI.Refresh("restock")
	local shown, header
	for _, row in ipairs(ns.UI.windows.restock.rows) do
		if row.data and row.data.kind == "restock" and row.data.row.itemID == 4 then shown = row end
		if row.data and row.data.columns == "restock" then header = row end
	end
	check("restock profit column", shown and shown.profit:GetText():find(ns.Money(shown.data.row.net), 1, true) ~= nil, true)
	check("restock profit header", header and header.profit:GetText():find("Profit", 1, true) ~= nil, true)
	if tabBefore then ns.UI.Show(tabBefore) end
	ns.db.restock.goals[4] = nil
end
-- Camp stations on the Restock tab: one an hour, so a row needing one it can't have gets no crafts, and says why.
do
	local recipe = ns.db.recipes[shirtRow.recipeID]
	recipe.f = { "Fermenter" }
	ns.db.campCooldown = { [ns.CharKey()] = time() - 10 * 60 }
	local campRows, _, camp = ns.Restock.Rows()
	local row
	for _, each in ipairs(campRows) do if each.itemID == 4 then row = each end end
	check("restock camp: cooldown leaves it out", row and row.crafts, 0)
	check("restock camp: why", row and row.camp and row.camp.cut, "cooldown")
	check("restock camp: tab note", camp and ns.UI.RestockCampNote(camp), "Camp stations are on cooldown for 50 more "
		.. "minutes: 1 item needing one left out.")
	check("restock camp: tooltip line", row and ns.UI.RestockCampText(row.camp, camp),
		"Needs a Fermenter: camp stations are on cooldown for 50 more minutes.")
	ns.UI.Show("restock")
	ns.UI.Refresh("restock")
	check("restock camp: tab keeps it", ns.UI.restockCamp ~= nil, true)
	-- Off cooldown, no Fermenter to be had anywhere.
	ns.db.campCooldown = nil
	campRows, _, camp = ns.Restock.Rows()
	for _, each in ipairs(campRows) do if each.itemID == 4 then row = each end end
	check("restock camp: none to be had", row.camp and row.camp.cut, "none")
	check("restock camp: no station used", camp and camp.station, nil)
	check("restock camp: window text", ns.UI.RestockCampText({ station = "Fermenter", fit = 12, wanted = 20, window = 900 }),
		"Needs a Fermenter, which stands 15 minutes once placed: 12 of 20 crafts fit.")
	check("restock camp: other text", ns.UI.RestockCampText({ station = "Fermenter", cut = "other", wanted = 3 },
		{ station = "Master Forge" }), "Needs a Fermenter: only one camp station an hour (they share a 60 minute "
		.. "cooldown), and a Master Forge pays more.")
	recipe.f = nil
	ns.UI.Show("queue")
end

-- Smart goals: sales raise the goal, a goal of your own wins, and the option turns it off.
-- Days are numbered by the local date, as Sales.lua does: in UTC these checks failed between local and UTC midnight.
local function LocalDay()
	local d = os.date("*t", time())
	return math.floor(os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
end
do
	local name = ns.Items.Name(4)
	local saved, money = ns.db.sales.items[name:lower()], playerMoney
	playerMoney = 100000000
	ns.db.sales.items[name:lower()] = { name = name, itemID = 4, sold = 12, expired = 0, gold = 0, exposure = 1,
		days = { [LocalDay() - 1] = { s = 12, e = 0, g = 0 } } }
	ns.Restock.ForgetSmart()
	local savedTrips, savedLots, savedDeposits = ns.db.sales.trips, ns.db.sales.lots, ns.db.deposits
	ns.db.sales.trips, ns.db.sales.lots, ns.db.deposits = {}, {}, {}
	local smartGoal = ns.Restock.Goal(4)
	check("smart goal above the default", smartGoal > 1, true)
	local smartInfo = ns.Restock.SmartInfo(4)
	check("smart info: the sold-out day raised it", smartInfo.raised, 1)
	check("smart info: no restocks on record, auction length used", smartInfo.gapKnown, nil)
	check("smart info: deposit not seen", smartInfo.margin, nil)
	local smartLines = table.concat(ns.UI.SmartGoalLines(smartInfo, smartGoal), " ")
	check("smart lines say it was raised", smartLines:find("raised from the default") ~= nil, true)
	check("smart lines name the auction length", smartLines:find("one auction's length") ~= nil, true)
	check("smart lines say the deposit is unknown", smartLines:find("deposit isn't known") ~= nil, true)
	-- Gold only matters as the cap: spending most of it on materials leaves the goal alone.
	playerMoney = 50000000
	ns.Restock.ForgetSmart()
	check("smart goal holds while gold is spent", ns.Restock.Goal(4), smartGoal)
	playerMoney = 100000000
	-- The Stock level slider on the Restock tab: moving it redraws the goals at once and flashes the ones that moved.
	do
		ns.UI.Show("restock")
		ns.UI.Refresh("restock")
		local function ItemRow()
			for _, r in ipairs(ns.UI.windows.restock.rows) do
				if r.data and r.data.kind == "restock" and r.data.row.itemID == 4 then return r end
			end
		end
		check("slider: item listed", ItemRow() ~= nil, true)
		check("slider: first look doesn't flash", ItemRow().live.item, nil)
		local slider = ns.UI.stockLevelSliders[#ns.UI.stockLevelSliders]
		local level = ns.Restock.SmartLevel()
		slider.scripts.OnValueChanged(slider, 200)
		RunTimers()
		check("slider: level saved", ns.Restock.SmartLevel(), 200)
		check("slider: goal moved", ItemRow().data.row.goal ~= smartGoal, true)
		check("slider: changed row flashes", ItemRow().live.item, 4)
		ns.UI.Refresh("restock")
		check("slider: redraw with no change keeps the flash", ItemRow().live.item, 4)
		slider.scripts.OnValueChanged(slider, level)
		RunTimers()
		check("slider: back to the old goal", ItemRow().data.row.goal, smartGoal)
		ns.UI.windows.restock.frame.scripts.OnHide() -- what closing the tab does: forget what was shown
		ns.Restock.ForgetSmart()
	end
	-- Restocks two days apart: the stock has to last longer, so the same sales allow more.
	local at = time()
	ns.db.sales.trips = { at - 6 * 86400, at - 4 * 86400, at - 2 * 86400, at }
	ns.Restock.ForgetSmart()
	check("measured restock gap used", ns.Restock.SmartInfo(4).gap, 2)
	check("measured restock gap known", ns.Restock.SmartInfo(4).gapKnown, true)
	check("smart lines name the gap", table.concat(ns.UI.SmartGoalLines(ns.Restock.SmartInfo(4), 2), " "):find("about 2 days apart") ~= nil, true)
	-- A deposit on record gives the margin.
	ns.db.deposits[4] = 1
	ns.Restock.ForgetSmart()
	check("margin from the deposit", ns.Restock.SmartInfo(4).margin ~= nil, true)
	ns.db.deposits = {}
	-- Restock times start from the posts still on record.
	ns.db.sales.trips = nil
	ns.db.sales.lots = { { name = "x", qty = 1, at = at - 86400, dur = 3600 }, { name = "x", qty = 1, at = at - 86400 + 60, dur = 3600 },
		{ name = "x", qty = 1, at = at - 43200, dur = 3600 }, { name = "x", qty = 1, at = at - 10 * 86400, dur = 3600 } }
	check("too few restocks on record: no gap", ns.Sales.RestockGap(), nil)
	check("restock times seeded from recent posts", #ns.db.sales.trips, 2)
	-- An auction posted yesterday that's still up: yesterday can't be called sold out.
	ns.db.sales.lots = { { name = name, qty = 1, at = at - 86400, dur = 3 * 86400 } }
	ns.Restock.ForgetSmart()
	check("not sold out while its auctions run", ns.Restock.Goal(4), 1)
	-- Expiries that lose more in deposits than the sales earn: paused, with the row still listed.
	do
		local record = ns.db.sales.items[name:lower()]
		local days, today = record.days, LocalDay()
		record.days = { [today - 2] = { s = 0, e = 1, g = 0 }, [today - 1] = { s = 0, e = 1, g = 0 }, [today] = { s = 0, e = 1, g = 0 } }
		ns.db.sales.lots, ns.db.deposits = {}, { [4] = 1e9 }
		ns.Restock.ForgetSmart()
		check("losing item is paused", ns.Restock.Goal(4), 0)
		check("paused in the info", ns.Restock.SmartInfo(4).paused, true)
		check("posting doesn't ask for a paused item", ns.Restock.FullGoal(4), 0)
		local pausedLines = table.concat(ns.UI.SmartGoalLines(ns.Restock.SmartInfo(4), 0), " ")
		check("paused lines say why", pausedLines:find("Paused: lately") ~= nil, true)
		check("paused lines say when it's tried again", pausedLines:find("tried again with one in 3 days") ~= nil, true)
		local pausedRow
		for _, row in ipairs((ns.Restock.Rows())) do if row.itemID == 4 then pausedRow = row end end
		check("paused item stays listed", pausedRow ~= nil and pausedRow.crafts, 0)
		ns.Restock.SetGoal(4, 3)
		check("own goal beats a pause", ns.Restock.Goal(4), 3)
		ns.Restock.ResetGoal(4)
		-- Three days later it's tried again.
		record.days = { [today - 5] = { s = 0, e = 1, g = 0 }, [today - 4] = { s = 0, e = 1, g = 0 }, [today - 3] = { s = 0, e = 1, g = 0 } }
		ns.Restock.ForgetSmart()
		check("paused item is tried again", ns.Restock.Goal(4), 1)
		check("try in the info", ns.Restock.SmartInfo(4).retry, true)
		check("try lines", table.concat(ns.UI.SmartGoalLines(ns.Restock.SmartInfo(4), 1), " "):find("another try") ~= nil, true)
		record.days = days
	end
	ns.db.sales.trips, ns.db.sales.lots, ns.db.deposits = {}, {}, {}
	ns.Restock.ForgetSmart()
	ns.Restock.SetSmartLevel(204)
	check("stock level clamped to the slider's range", ns.Restock.SmartLevel(), 200)
	check("higher stock level, higher goal", ns.Restock.Goal(4) > smartGoal, true)
	ns.Restock.SetSmartLevel(50)
	ns.Restock.SetGoal(4, smartGoal)
	check("setting the smart goal isn't an own goal", ns.Restock.IsCustom(4), false)
	ns.Restock.SetGoal(4, 1)
	check("own goal beats smart", ns.Restock.Goal(4), 1)
	check("own goal has no smart info", ns.Restock.SmartInfo(4), nil)
	ns.Restock.ResetGoal(4)
	playerMoney = 0
	ns.Restock.ForgetSmart()
	check("no gold, smallest goal", ns.Restock.Goal(4), 1)
	check("gold named as the limit", ns.Restock.SmartInfo(4).limited, "gold")
	playerMoney = 100000000
	ns.Restock.ForgetSmart()
	ns.SetOption("smartRestock", false)
	check("smart off: default goal", ns.Restock.Goal(4), 1)
	check("smart off: no info", ns.Restock.SmartInfo(4), nil)
	ns.SetOption("smartRestock", true)
	ns.db.sales.items[name:lower()], playerMoney = saved, money
	ns.db.sales.trips, ns.db.sales.lots, ns.db.deposits = savedTrips, savedLots, savedDeposits
	ns.Restock.ForgetSmart()
end

-- No gold: the restock is cut to what costs nothing, and the tab says so.
do
	local money = playerMoney
	local _, enough = ns.Restock.Rows()
	playerMoney = 0
	ns.Restock.ForgetSmart()
	local cut, budget = ns.Restock.Rows()
	if enough and enough.full > 0 then
		check("no gold: restock is partial", budget.short, true)
		check("no gold: nothing to buy", budget.cost, 0)
		local marked = false
		for _, row in ipairs(cut) do marked = marked or row.wanted ~= nil end
		check("no gold: cut rows say what was wanted", marked, true)
		ns.UI.Show("restock")
		ns.UI.Refresh("restock")
		check("no gold: budget kept for the tab", ns.UI.restockBudget.short, true)
	end
	ns.SetOption("smartRestock", false)
	check("smart off: restock not fitted to gold", select(2, ns.Restock.Rows()), nil)
	ns.SetOption("smartRestock", true)
	playerMoney = money
	ns.Restock.ForgetSmart()
end
-- A queued restock is committed: running out of gold after shopping for it changes nothing on a second look.
do
	local money, savedQueue = playerMoney, {}
	for index, entry in ipairs(ns.db.queue) do savedQueue[index] = entry end
	wipe(ns.db.queue)
	playerMoney = 100000000
	ns.Restock.ForgetSmart()
	local first = ns.Restock.Rows()
	local asked = 0
	for _, row in ipairs(first) do if row.crafts > 0 then asked = asked + 1 end end
	check("restock asks for something", asked > 0, true)
	check("restock queued", ns.Restock.Apply(first), asked)
	local before = {}
	for index, entry in ipairs(ns.db.queue) do before[index] = entry.recipeID .. "x" .. entry.qty end
	playerMoney = 0
	ns.Restock.ForgetSmart()
	local again = ns.Restock.Rows()
	local changes, queued = 0, 0
	for _, row in ipairs(again) do
		if row.crafts > 0 or row.trim then changes = changes + 1 end
		if row.queued then queued = queued + 1 end
	end
	check("gold spent: nothing new asked, nothing cut", changes, 0)
	check("gold spent: rows show what's queued", queued, asked)
	ns.Restock.Apply(again)
	local after = {}
	for index, entry in ipairs(ns.db.queue) do after[index] = entry.recipeID .. "x" .. entry.qty end
	check("gold spent: queue unchanged", table.concat(after, ","), table.concat(before, ","))
	ns.UI.Show("restock")
	ns.UI.Refresh("restock")
	wipe(ns.db.queue)
	for index, entry in ipairs(savedQueue) do ns.db.queue[index] = entry end
	playerMoney = money
	ns.Restock.ForgetSmart()
	RunTimers()
end
ns.UI.Show("restock")
check("restock tab opens", ns.UI.windows.restock.frame:IsVisible(), true)
ns.UI.Refresh("restock")

-- A goal typed in the row's box.
do
	local function RestockRow()
		for _, r in ipairs(ns.UI.windows.restock.rows) do
			if r.data and r.data.kind == "restock" then return r end
		end
	end
	local row = RestockRow()
	local itemID = row.data.row.itemID
	local before = ns.Restock.Goal(itemID)
	check("goal box shown", row.amount:IsShown(), true)
	check("goal box holds the goal", row.amount:GetText(), tostring(row.data.row.goal))
	row.amount:SetText("7")
	row.amount.scripts.OnEnterPressed(row.amount)
	check("typed goal saved", ns.Restock.Goal(itemID), 7)
	RunTimers()
	check("goal box shows the new goal", RestockRow().amount:GetText(), "7")
	ns.Restock.SetGoal(itemID, before)
	ns.UI.Refresh("restock")
end

-- With Syndicator: auctions, alts and mail count towards the goal.
Syndicator = { API = {
	IsReady = function() return true end,
	GetCurrentCharacter = function() return "Snic-Realm" end,
	GetInventoryInfoByItemID = function(id)
		if id ~= 2 then return { characters = {} } end
		return { characters = {
			{ character = "Snic", realmNormalized = "Realm", bags = 50, bank = 50, mail = 1, auctions = 2 },
			{ character = "Alt", realmNormalized = "Realm", bags = 3, bank = 1, mail = 0, auctions = 1 },
		} }
	end,
} }
local onAH, owned = ns.Stock.ForRestock(2)
check("auctions across characters", onAH, 3)
-- Own count is 0 for this item in the stub, plus own mail 1, plus alt bags and bank 4.
check("held excludes own Syndicator bags", owned, 5)

-- Per-item goals: default follows setting until changed; matching the default clears the override.
ns.db.restock.stackGoal = 20
ns.Restock.SetGoal(2, 3)
check("override goal", ns.Restock.Goal(2), 3)
ns.Restock.SetGoal(2, ns.Restock.Goal(2) - 10)
check("goal never negative", ns.Restock.Goal(2), 0)

-- Apply: replaces earlier restock entries, leaves hand-queued ones alone.
wipe(ns.db.queue)
ns.Queue.Add(10, 2)
RunTimers()
local manual = ns.db.queue[1]
ns.Restock.Apply({ { recipeID = 20, crafts = 3 }, { recipeID = 10, crafts = 0 } })
ns.Restock.Apply({ { recipeID = 20, crafts = 1 } })
check("restock merged, not duplicated", #ns.db.queue, 2)
check("manual entry kept", ns.db.queue[1], manual)
check("restock quantity adds up", ns.db.queue[2].qty, 4)
check("restock flagged", ns.db.queue[2].restock, true)
ns.Queue.Add(20, 1)
check("manual add doesn't merge into restock", #ns.db.queue, 3)
wipe(ns.db.queue)
RunTimers()
ns.UI.Refresh("restock")
Syndicator = nil

-- Profession tabs: one per profession across characters, each showing only its items.
ns.db.recipes[500] = { n = "Bronze Bar", o = 2, qmin = 1, qmax = 1, p = 186, pn = "Mining", r = { { 1, 1 } } }
ns.db.chars["Player-2-ALT"] = { name = "Alt", class = "Mage", recipes = { [500] = true } }
ns.InvalidateProfit()
local professions = ns.Recipes.KnownProfessions()
check("tabs from all characters", #professions, 2)
check("tabs sorted by name", professions[1].name, "Mining")
ns.UI.Show("profit")
local tabs = ns.UI.windows.profit.tabs
check("All tab first", tabs[1].professionID, nil)
check("profession tab", tabs[2].professionID, 186)
check("second profession tab", tabs[3].professionID, 197)
check("unused tab hidden", tabs[4]:IsShown(), false)
ns.UI.SelectProfession("profit", 186)
local list = ns.UI.windows.profit.list
check("tab filters to its profession, under the column headings", #list, 2)
check("column headings first", list[1].columns, "profit")
check("tab shows its item", list[2].result.recipeID, 500)
tabs[1].scripts.OnClick(tabs[1])
check("All tab shows everything", #ns.UI.windows.profit.list > 2, true)
Fire("TRADE_SKILL_LIST_UPDATE")
check("clicked tab stays selected", #ns.UI.windows.profit.list > 2, true)

-- Profit search: the real box fires OnTextChanged on any text change, including its own SetText.
do
	local window = ns.UI.windows.profit
	local box = window.searchBox
	local function Search(text)
		box:SetText(text)
		box.scripts.OnTextChanged(box)
	end
	local function Shown() return math.max(0, #window.list - 1) end -- less the column headings
	local everything = Shown()
	window.offset = 5
	Search("  BRONZE b ")
	check("search ignores case and outer spaces", Shown(), 1)
	check("search finds the item", window.list[2].result.recipeID, 500)
	check("search scrolls back to the top", window.offset, 0)
	Search("no such recipe at all")
	check("search can find nothing", Shown(), 0)
	Search("[")
	check("search text is not a pattern", Shown(), 0)
	ns.UI.SelectProfession("profit", 197)
	Search("bronze")
	check("search stays within the tab", Shown(), 0)
	check("empty tab points to the All tab", window.status.text, "No matches on this tab, 1 on the All tab.")
	ns.UI.SelectProfession("profit", 186)
	check("search survives a tab change", Shown(), 1)
	check("search reports its matches", window.status.text, "1 recipe matches your search.")
	ns.InvalidateProfit()
	check("search survives a price refresh", Shown(), 1)
	ns.UI.SelectProfession("profit", nil)
	box.scripts.OnEscapePressed(box)
	box.scripts.OnTextChanged(box)
	check("escape empties the box", box:GetText(), "")
	check("clearing shows everything again", Shown(), everything)
end

-- A restock already queued is committed: a later restock adds to it and never removes it.
ns.db.queue[1] = { recipeID = 500, qty = 2, char = "Player-2-ALT", restock = true }
ns.db.queue[2] = { recipeID = 20, qty = 2, char = me, restock = true }
ns.Restock.Apply({ { recipeID = 10, crafts = 1 } }, 197)
check("earlier restock kept", ns.db.queue[1].recipeID, 500)
check("committed restock kept", ns.db.queue[2].recipeID, 20)
check("new restock added after", ns.db.queue[3].recipeID, 10)
wipe(ns.db.queue)
ns.db.chars["Player-2-ALT"] = nil
ns.db.recipes[500] = nil
ns.UI.SelectProfession("profit", nil)
RunTimers()

-- The Queue button on the recipe's pane queues the selected recipe with the amount in the Create box.
do
	local button = ns.UI.queueButton
	check("queue button sits on the recipe's pane", button.parent, page.SchematicForm)
	check("queue button anchored to that pane", button.lastPoint[2], page.SchematicForm)
	button.scripts.OnClick(button)
	RunTimers()
	check("queue button queues the selected recipe", ns.db.queue[1].recipeID, selected.recipeID)
	check("queue button uses the Create box amount", ns.db.queue[1].qty, 2)
	ns.Queue.Clear()
	RunTimers()
end

-- Bind on pickup in the queue: a crafting cost instead of a profit, and no search for it on the AH.
do
	local cost = ns.Planner.RecipeCost(ns.NewContext(), 30)
	ns.UI.Show("profit")
	local profitRow
	for _, row in ipairs(ns.UI.windows.profit.rows) do
		if row.data and row.data.result and row.data.result.recipeID == 30 then profitRow = row end
	end
	check("profit row shows craft cost", profitRow.profit.text, "|cff999999cost |r" .. ns.Money(cost))
	profitRow.plus.scripts.OnClick(profitRow.plus)
	RunTimers()
	check("plus queues a bind-on-pickup craft", ns.db.queue[1].recipeID, 30)
	check("queued bound counted apart", ns.totals.bound, 1)
	check("queued bound not a profit", ns.totals.counted, 0)
	check("queued bound not unpriced", ns.totals.excluded, 0)
	check("queued bound cost", ns.totals.boundCost, cost)
	check("bound craft is planned", ns.plan.crafts[1].recipeID, 30)
	for _, searchString in ipairs(lists[ns.LIST_NAME]) do
		check("bound result not searched on the AH", searchString:find("Soulbound Robe", 1, true), nil)
	end
	ns.UI.Show("queue")
	local queue = ns.UI.windows.queue
	check("queue total is a crafting cost", queue.totalText.text, "Crafting cost: " .. ns.Money(cost))
	local queueRow
	for _, row in ipairs(queue.rows) do
		if row.data and row.data.kind == "queue" then queueRow = row end
	end
	check("queue row shows cost", queueRow.cost.text, ns.Money(cost))
	check("a loss under half a copper is 0c, not -0c", ns.Money(-0.4), "0c")
	check("a loss of 1c keeps its sign", ns.Money(-0.6), "-1c")
	check("bound entry has no profit", queueRow.profit.text:find("can't sell", 1, true) ~= nil, true)
	ns.Queue.Clear()
	RunTimers()
	ns.UI.Show("profit")
end

-- Refresh: picks up changed prices, stock and recipes right away, without being asked to wait for an event.
ns.Queue.Add(10, 1)
RunTimers()
prices[2] = 777
ns.db.recipes[10].n = "Stale name"
C_Item.GetItemCount = function() return 0 end
local queriedAuctions = 0
C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end
C_AuctionHouse.QueryOwnedAuctions = function() queriedAuctions = queriedAuctions + 1 end
ns.RefreshEverything()
check("refresh rebuilds plan at once", ns.plan.buy[1], 2)
check("refresh rebuilds totals at once", ns.totals.revenue, 777 * 0.95)
check("no auction query away from the AH", queriedAuctions, 0)
RunTimers()
check("refresh re-reads recipes", ns.db.recipes[10].n, "Recipe10")
AuctionHouseFrame:Show()
ns.RefreshEverything()
check("auction query at the AH", queriedAuctions, 1)
AuctionHouseFrame:Hide()
RunTimers()
wipe(ns.db.queue)
RunTimers()

-- Sales: a post is only recorded once the server confirms it.
C_AuctionHouse.PostCommodity({ itemID = 2 }, 2, 10)
check("unconfirmed post not recorded", #ns.db.sales.lots, 0)
Fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
check("confirmed post recorded", #ns.db.sales.lots, 1)
check("post quantity", ns.db.sales.lots[1].qty, 10)
check("post duration", ns.db.sales.lots[1].dur, 86400)
Fire("AUCTION_HOUSE_AUCTION_CREATED", 2)
check("a second event doesn't record twice", #ns.db.sales.lots, 1)
check("the post is noted as a restock", #ns.db.sales.trips, 1)

-- Mail: sold and expired are counted, other mail and pending sales aren't. Quantities come from subject or attachment.
ns.db.sales.lots[1].at = os.time() - 3600 * 13
ns.db.sales.lots[1].dep = 3
inbox = {
	{ subject = "Auction successful: Bolt of Linen (4)", money = 950, daysLeft = 30 },
	{ subject = "Auction successful: Bolt of Linen (4)", money = 950, daysLeft = 30 },
	{ subject = "Auction expired: Bolt of Linen", itemID = 2, count = 2, daysLeft = 29.5 },
	{ subject = "Sale Pending: Bolt of Linen (4)", money = 0, daysLeft = 30 },
	{ subject = "Hello from a friend", money = 0, daysLeft = 3 },
}
Fire("MAIL_SHOW")
local bolt = ns.Sales.Item("Bolt of Linen")
check("sold units", bolt.sold, 8)
check("identical mails both counted", bolt.gold, 1900)
check("expired units", bolt.expired, 2)
do
	local lost, units = 0, 0
	for _, day in pairs(bolt.days) do lost, units = lost + (day.d or 0), units + (day.dk or 0) end
	check("deposit lost on the expired units kept", lost, 6)
	check("for the units whose post is on record", units, 2)
	local history = ns.Sales.History("Bolt of Linen", 30)
	check("history carries the deposit lost", history[1].d, 6)
end
check("expired item ID from attachment", bolt.itemID, 2)

-- The same mail seen again doesn't count again, and a slightly different expiry is still the same mail.
inbox[1].daysLeft = 29.999
Fire("MAIL_INBOX_UPDATE")
Fire("MAIL_INBOX_UPDATE")
check("rescan doesn't double count", ns.Sales.Item("Bolt of Linen").sold, 8)
table.remove(inbox, 1)
Fire("MAIL_INBOX_UPDATE")
check("collected mail doesn't change totals", ns.Sales.Item("Bolt of Linen").sold, 8)

-- Taking the gold leaves the mail in the inbox for a moment with no money: not a second sale.
do
	inbox = { { subject = "Auction successful: Emptied Item", money = 400, daysLeft = 30 } }
	Fire("MAIL_SHOW")
	inbox[1].money = 0
	Fire("MAIL_INBOX_UPDATE")
	check("emptied sale mail isn't a second sale", ns.Sales.Item("Emptied Item").sold, 1)
	check("emptied sale mail leaves no record", #ns.db.sales.seen[ns.CharKey()] > 0
		and ns.db.sales.seen[ns.CharKey()][#ns.db.sales.seen[ns.CharKey()]].key, "sold|Emptied Item|400")

	-- Saved data from before the fix: the second count is taken back out, with its cost returned to the pool.
	local savedItems, savedSeen, savedCosts = ns.db.sales.items, ns.db.sales.seen, ns.db.costs
	local when = os.time() - 3600
	local d = os.date("*t", when)
	local dayNumber = math.floor(os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
	local expires = when + 30 * 86400
	ns.db.costs = { [901] = { q = 1, c = 50 } }
	ns.db.sales.items = {
		["twice item"] = { name = "Twice Item", itemID = 901, sold = 5, expired = 0, gold = 900, exposure = 0,
			days = { [dayNumber] = { s = 5, e = 0, g = 900, c = 400, u = 1 } } },
	}
	ns.db.sales.seen = { someone = {
		{ key = "sold|Twice Item|300", expires = expires },
		{ key = "sold|Twice Item|0", expires = expires + 10 },
		{ key = "sold|Twice Item|300", expires = expires + 20 },
		{ key = "sold|Twice Item|300", expires = expires + 30 },
		{ key = "sold|Twice Item|0", expires = expires + 40 },
		{ key = "expired|Twice Item|0", expires = expires + 50 },
	} }
	ns.db.sales.emptiedMailFixed = nil
	ns.Sales.RepairEmptiedMail()
	local item, day = ns.db.sales.items["twice item"], ns.db.sales.items["twice item"].days[dayNumber]
	check("repair: units sold", item.sold, 3)
	check("repair: day's units", day.s, 3)
	check("repair: units with no cost go first", day.u, 0)
	check("repair: cost of the rest", day.c, 300)
	check("repair: money untouched", day.g, 900)
	check("repair: cost back in the pool", ns.db.costs[901].q .. "/" .. ns.db.costs[901].c, "2/150")
	check("repair: second counts forgotten", #ns.db.sales.seen.someone, 4)
	ns.Sales.RepairEmptiedMail()
	check("repair runs once", item.sold, 3)
	ns.db.sales.items, ns.db.sales.seen, ns.db.costs = savedItems, savedSeen, savedCosts
	inbox = {}
end

-- A sale whose subject states no quantity uses the invoice.
function GetInboxInvoiceInfo() return "seller", "Plain Item", "Buyer", 0, 0, 0, 0, 0, 0, 0, 7 end
inbox = { { subject = "Auction successful: Plain Item", money = 10, daysLeft = 30 } }
Fire("MAIL_SHOW")
check("quantity from invoice", ns.Sales.Item("Plain Item").sold, 7)
GetInboxInvoiceInfo = nil
inbox = { { subject = "Auction successful: Plain Item Two", money = 10, daysLeft = 30 } }
Fire("MAIL_SHOW")
check("quantity defaults to one", ns.Sales.Item("Plain Item Two").sold, 1)
inbox = {}

-- A Sales row whose item name hasn't loaded shows "Loading...", and is redrawn when the name arrives.
do
	ns.UI.Show("sales")
	RunTimers()
	local function BoltRow()
		for _, row in ipairs(ns.UI.windows.sales.rows) do
			if row.data and row.data.kind == "sales" and row.data.item.itemID == 2 then return row end
		end
	end
	local savedName = names[2]
	names[2] = nil
	ns.UI.Refresh("sales")
	check("sales row waits for the name", BoltRow().left.text:find("Loading...", 1, true) ~= nil, true)
	names[2] = savedName
	Fire("GET_ITEM_INFO_RECEIVED", 2, true)
	check("sales row redrawn when the name arrives", BoltRow().left.text:find("Bolt of Linen", 1, true) ~= nil, true)
end

-- A new identical sale is a new result.
table.insert(inbox, 1, { subject = "Auction successful: Bolt of Linen (4)", money = 950, daysLeft = 29.9 })
Fire("MAIL_INBOX_UPDATE")
check("new identical sale counted", ns.Sales.Item("Bolt of Linen").sold, 12)
inbox = {}

-- Periods and chance. Direct records with known time on the AH make the arithmetic checkable.
local now = os.time()
ns.db.sales.items = {}
ns.db.sales.lots = {}
ns.Sales.Record("sold", "Test Sword", 1, 5000, now, me, 4)
ns.Sales.Record("sold", "Test Sword", 1, 5000, now - 3 * 86400, me, 4)
ns.Sales.Record("expired", "Test Sword", 1, 0, now - 10 * 86400, me, 4)
local sword = ns.Sales.Item("test sword")
local s1 = ns.Sales.Counts(sword, 1)
local s7, e7 = ns.Sales.Counts(sword, 7)
local _, e30, g30 = ns.Sales.Counts(sword, 30)
check("sold today", s1, 1)
check("sold 7 days", s7, 2)
check("expired not in 7 days", e7, 0)
check("expired in 30 days", e30, 1)
check("earned 30 days", g30, 10000)
-- 2 sold at an assumed half day each + 1 expired at an assumed day + the 1 unit-day prior = 3 unit-days: rate 2/3.
local chance, samples = ns.Sales.Chance("Test Sword")
check("chance from rate", math.floor(chance * 1000 + 0.5), math.floor((1 - math.exp(-2 / 3)) * 1000 + 0.5))
check("chance samples", samples, 3)
check("no data no chance", ns.Sales.Chance("Never Sold"), nil)

-- Time on the AH from a real post lowers the rate compared with a shorter listing.
ns.db.sales.lots = { { itemID = 9, name = "Slow Item", qty = 1, at = now - 2 * 86400, dur = 2 * 86400, char = me } }
ns.Sales.Record("sold", "Slow Item", 1, 1, now, me, 9)
check("real time on AH used", ns.Sales.Item("Slow Item").exposure, 2)
check("post consumed", #ns.db.sales.lots, 0)

-- Results before a post don't consume it; other characters' posts aren't matched.
ns.db.sales.lots = {
	{ name = "Later", qty = 1, at = now, dur = 86400, char = me },
	{ name = "Alt Item", qty = 1, at = now - 60, dur = 86400, char = "other" },
}
ns.Sales.Record("sold", "Later", 1, 1, now - 3600, me)
ns.Sales.Record("sold", "Alt Item", 1, 1, now, me)
check("later post not consumed", #ns.db.sales.lots, 2)
ns.Sales.Record("cancelled", "Alt Item", 1, 0, now, "other")
check("cancel consumes post", #ns.db.sales.lots, 1)
check("cancel isn't a result", ns.Sales.Item("Alt Item").expired, 0)

-- Posts that ended hours before a look at the whole mailbox can't get a result any more: dropped, as nothing will
-- ever match them. Ones that ended lately, other characters' and any while mail is still waiting are kept.
do
	local savedInbox = inbox
	inbox = {}
	local function Lots()
		return {
			{ name = "Orphan", qty = 2, at = now - 12 * 3600, dur = 8 * 3600, char = me },
			{ name = "Just Ended", qty = 1, at = now - 9 * 3600, dur = 8 * 3600, char = me },
			{ name = "Running", qty = 1, at = now - 3600, dur = 8 * 3600, char = me },
			{ name = "Alt Orphan", qty = 1, at = now - 12 * 3600, dur = 8 * 3600, char = "other" },
		}
	end
	local function Names()
		local names = {}
		for _, lot in ipairs(ns.db.sales.lots) do table.insert(names, lot.name) end
		return table.concat(names, ",")
	end
	ns.db.sales.lots = Lots()
	inboxTotal = 60
	FireNow("MAIL_SHOW")
	check("mailbox just opened: inbox may not be in yet", #ns.db.sales.lots, 4)
	RunTimers()
	check("mail still waiting beyond the inbox", #ns.db.sales.lots, 4)
	Fire("MAIL_INBOX_UPDATE")
	check("still waiting at the inbox update", #ns.db.sales.lots, 4)
	inboxTotal = nil
	Fire("MAIL_INBOX_UPDATE")
	check("ended posts with no result dropped", Names(), "Just Ended,Running,Alt Orphan")
	Fire("MAIL_CLOSED")
	-- An empty mailbox may send no inbox update: a moment after opening counts as the inbox having come in.
	ns.db.sales.lots = Lots()
	FireNow("MAIL_SHOW")
	check("empty mailbox, just opened", #ns.db.sales.lots, 4)
	RunTimers()
	check("empty mailbox: dropped a moment later", Names(), "Just Ended,Running,Alt Orphan")
	Fire("MAIL_CLOSED")
	-- Closed before that moment: nothing is concluded.
	ns.db.sales.lots = Lots()
	FireNow("MAIL_SHOW")
	FireNow("MAIL_CLOSED")
	RunTimers()
	check("closed at once: kept", #ns.db.sales.lots, 4)
	inbox = savedInbox
	ns.db.sales.lots = {}
end

-- The window and row text.
ns.UI.Show("sales")
check("sales tab lists items", #ns.UI.windows.sales.list >= 1, true)
check("sales list starts with its column headings", ns.UI.windows.sales.list[1].columns, "sales")
check("best seller first", ns.UI.windows.sales.list[2].item.name, "Test Sword")
-- Every row with an item icon starts its tooltip with the game's item tooltip.
GameTooltip.SetItemByID = function(self, itemID) rawset(self, "itemID", itemID) end
local function HoverIconRows(key)
	local hovered, withItem = 0, 0
	for _, row in ipairs(ns.UI.windows[key].rows) do
		local nameOnly = row.data and row.data.kind == "sales" and not row.data.item.itemID
		if row.data and row:IsShown() and row.icon:IsShown() and row.data.kind ~= "header" and not nameOnly then
			rawset(GameTooltip, "itemID", nil)
			row.scripts.OnEnter(row)
			hovered = hovered + 1
			if rawget(GameTooltip, "itemID") then withItem = withItem + 1 end
		end
	end
	return hovered, withItem
end
local hovered, withItem = HoverIconRows("sales")
check("sales rows hovered", hovered > 0, true)
check("sales rows show the item tooltip", withItem, hovered)
ns.UI.Show("profit")
hovered, withItem = HoverIconRows("profit")
check("profit rows hovered", hovered > 0, true)
check("profit rows show the item tooltip", withItem, hovered)
ns.Queue.Add(ns.UI.windows.profit.rows[2].data.result.recipeID, 1)
RunTimers()
ns.UI.Show("queue")
hovered, withItem = HoverIconRows("queue")
check("queue rows hovered", hovered > 0, true)
check("queue rows show the item tooltip", withItem, hovered)
ns.Queue.Clear()
RunTimers()
ns.UI.Show("restock")
hovered, withItem = HoverIconRows("restock")
check("restock rows show the item tooltip", withItem, hovered)
ns.UI.Show("sales")
ns.db.sales.items = {}
ns.db.sales.lots = {}
ns.UI.Refresh("sales")
ns.UI.Hide()

-- Advertising: who may advertise, and the chat box path used by the Profit window button and slash command.
check("link kept per profession", ns.db.chars[me].links[197], "|ctrade|Htrade:197|h[Tailoring]|h|r")
check("crafting profession can advertise", ns.Advertise.Reason(197), nil)
check("gathering not advertised", ns.Advertise.Reason(186) ~= nil, true)
check("other character's profession not advertised", ns.Advertise.Reason(164) ~= nil, true)
check("nothing selected", ns.Advertise.Reason(nil) ~= nil, true)
local AD_MESSAGE = "|ctrade|Htrade:197|h[Tailoring]|h|r available for hire! Your materials, or I'll give you a price based on material cost."
local realNow = time
chatBoxText = nil
ns.Advertise.Send(197)
check("fills the chat box with the Trade command", chatBoxText, "/2 " .. AD_MESSAGE)
check("add-on never sends chat itself", #sentChat, 0)
chatBoxText = nil
ns.Advertise.Send(197)
check("cooldown stops repeats", chatBoxText, nil)

time = function() return realNow() + 120 end
channelList = { 1, "General - City", false }
ns.Advertise.Send(197)
check("no Trade channel, no ad", chatBoxText, nil)
channelList = { 1, "General", false, 2, "Trade (Services)", false, 5, "Trade - City", false }
ns.Advertise.Send(197)
check("plain Trade preferred", chatBoxText, "/5 " .. AD_MESSAGE)

-- Buttons beside the chat: secure macro buttons, one per crafting profession, with no profession window open.
ProfessionsFrame:Hide()
channelList = { 2, "Trade - City", false }
ns.db.recipes[700] = { n = "Smelt", o = 2, p = 186, pn = "Mining", r = {} }
ns.db.recipes[701] = { n = "Potion", o = 2, p = 171, pn = "Alchemy", r = {} }
ns.db.recipes[702] = { n = "Alt Only", o = 2, p = 164, pn = "Blacksmithing", r = {} }
ns.db.chars[me].recipes[700], ns.db.chars[me].recipes[701] = true, true
ns.db.chars["Player-2-ALT"] = { name = "Alt", class = "Mage", recipes = { [702] = true } }
time = function() return realNow() + 480 end
Fire("CHANNEL_UI_UPDATE")
local adButtons = ns.Advertise.buttons
local function ShownButtons()
	local names = {}
	for _, button in ipairs(adButtons) do
		if button:IsShown() then table.insert(names, button.text) end
	end
	return table.concat(names, ", ")
end
local box = ns.Advertise.box
check("one small box to start", box:IsShown(), true)
check("nothing else shown until opened", ShownButtons(), "")
check("picker closed until opened", ns.Advertise.destinationButton:IsShown(), false)
local function OpenAds()
	if not ns.Advertise.destinationButton:IsShown() then box.scripts.OnClick(box) end
end
OpenAds()
check("box opens picker", ns.Advertise.destinationButton:IsShown(), true)
box.scripts.OnClick(box)
check("box closes again", ShownButtons(), "")
inCombat = true
box.scripts.OnClick(box)
inCombat = false
check("box doesn't open in combat", ShownButtons(), "")
OpenAds()

-- A click as the client does it: the macro runs on the direction matching the setting, and PostClick fires on both.
-- Posting closes the list, so the helper opens it again for the checks that follow.
local function Click(button, keyDown)
	useKeyDown = keyDown or false
	local ranDown = useKeyDown
	macroRan = ranDown and button.attributes.macrotext or nil
	button.scripts.PostClick(button, "LeftButton", true)
	if not ranDown then macroRan = button.attributes.macrotext end
	button.scripts.PostClick(button, "LeftButton", false)
	local closedAfter = not ns.Advertise.destinationButton:IsShown()
	OpenAds()
	return macroRan, closedAfter
end
check("a button per crafting profession", ShownButtons(), "Alchemy, Tailoring")
check("buttons are macro buttons", adButtons[2].attributes.type, "macro")
check("macro posts to Trade with the link", adButtons[2].attributes.macrotext, "/2 " .. AD_MESSAGE)
check("placed on the screen, not on the chat frame", adButtons[1].lastPoint[2], UIParent)
local posted, closedAfterPost = Click(adButtons[2])
check("one click posts", posted, "/2 " .. AD_MESSAGE)
check("posting closes the list", closedAfterPost, true)
check("cooldown shown on buttons", ShownButtons():find("Alchemy %(%d+%)") ~= nil, true)
time = function() return realNow() + 600 end
RunTimers()
check("buttons return after the cooldown", ShownButtons(), "Alchemy, Tailoring")

-- The cooldown starts on the click direction that really ran the macro, whichever the setting is.
useKeyDown = false
adButtons[2].scripts.PostClick(adButtons[2], "LeftButton", true)
check("press alone starts no cooldown when macros run on release", ShownButtons(), "Alchemy, Tailoring")
Click(adButtons[2], true)
check("key-down setting starts cooldown", ShownButtons():find("%(%d+%)") ~= nil, true)
useKeyDown = false
time = function() return realNow() + 700 end
RunTimers()

-- In combat secure buttons can't change, so updates wait until combat ends.
inCombat = true
channelList = { 1, "General - Barrens", false }
Fire("ZONE_CHANGED_NEW_AREA")
check("no changes in combat", ShownButtons(), "Alchemy, Tailoring")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
check("hidden outside Trade chat once combat ends", ShownButtons(), "")
channelList = { 2, "Trade - City", false }
Fire("CHAT_MSG_CHANNEL_NOTICE")
check("back in Trade chat", ShownButtons(), "Alchemy, Tailoring")

-- The picker: each destination gets its own command, and shows its buttons even outside Trade chat.
local picker = ns.Advertise.destinationButton
local menu = ns.Advertise.destinationMenu
check("picker starts on Trade", picker.text, "To: Trade")
picker.scripts.OnClick(picker)
check("picker opens its menu", menu:IsShown(), true)
menu:Hide()
local function Pick(key)
	picker.scripts.OnClick(picker)
	menu.options[key].scripts.OnClick(menu.options[key])
end
channelList = { 1, "General - Barrens", false }
Fire("ZONE_CHANGED_NEW_AREA")
check("no buttons for Trade outside it", ShownButtons(), "")
check("picker stays available", picker:IsShown(), true)
for _, case in ipairs({ { "GUILD", "Guild", "/g " }, { "SAY", "Say", "/s " }, { "YELL", "Yell", "/y " } }) do
	Pick(case[1])
	check("picker shows " .. case[2], picker.text, "To: " .. case[2])
	check("menu closes after picking " .. case[2], menu:IsShown(), false)
	check("buttons shown for " .. case[2], ShownButtons(), "Alchemy, Tailoring")
	check("command for " .. case[2], Click(adButtons[2]), case[3] .. AD_MESSAGE)
end
check("destination saved", ns.db.ui.adDestination, "YELL")

-- Timers are per destination: Yell is cooling down, Say cooled down separately.
check("Yell waits", ShownButtons():find("%(%d+%)") ~= nil, true)
time = function() return realNow() + 1200 end
inGuild = false
Pick("GUILD")
check("no buttons without a guild", ShownButtons(), "")
chatBoxText = nil
ns.Advertise.Send(197)
check("no guild, no ad", chatBoxText, nil)
inGuild = true
ns.db.ui.adDestination = nil
time = function() return realNow() + 1800 end
channelList = { 2, "Trade - City", false }
ns.Advertise.UpdateButtons()

ns.db.chars["Player-2-ALT"] = nil
ns.db.chars[me].recipes[700], ns.db.chars[me].recipes[701] = nil, nil
ns.db.recipes[700], ns.db.recipes[701], ns.db.recipes[702] = nil, nil, nil
ProfessionsFrame:Show()
time = realNow

-- Advertise sits under the profession tabs and follows the selected one.
ns.UI.Show("profit")
ns.UI.SelectProfession("profit", 197)
check("advertise follows the tab", ns.UI.AdvertisedProfession(), 197)
check("advertise button is short", ns.UI.windows.profit.advertiseButton.text, "Advertise")

-- Profit sorting, by heading.
do
	local profit = ns.UI.windows.profit
	ns.UI.SelectProfession("profit", nil)
	local function Results()
		local results = {}
		for _, data in ipairs(profit.list) do
			if data.kind == "profit" then table.insert(results, data.result) end
		end
		return results
	end
	local function Ordered(valueOf, ascending)
		local last
		for _, result in ipairs(Results()) do
			local value = valueOf(result)
			if value ~= nil then
				if last ~= nil and (ascending and value < last or not ascending and value > last) then return false end
				last = value
			end
		end
		return true
	end
	local function Name(result) local name = ns.Items.Name(result.itemID) return name and name:lower() end
	local function Net(result) return result.net end
	check("enough recipes to sort", #Results() >= 3, true)
	check("profit, highest first by default", ns.UI.ProfitSort(), "profit")
	check("default order", Ordered(Net, false), true)
	ns.UI.SortList("profit", "name")
	check("sorted by name", ns.db.ui.profitSort, "name")
	check("names A to Z", Ordered(Name, true), true)
	ns.UI.SortList("profit", "name")
	check("second click reverses", ns.db.ui.profitSortAsc, false)
	check("names Z to A", Ordered(Name, false), true)
	ns.UI.SortList("profit", "profit")
	check("profit highest first", Ordered(Net, false), true)
	ns.UI.SortList("profit", "profit")
	check("profit lowest first", Ordered(Net, true), true)
	local seenUnpriced, pricedAfter = false, false
	for _, result in ipairs(Results()) do
		if result.net == nil then seenUnpriced = true elseif seenUnpriced then pricedAfter = true end
	end
	check("no price stays last when reversed", pricedAfter, false)
	ns.UI.SortList("profit", "chance")
	check("sells, likely first", ns.db.ui.profitSortAsc, false)
	-- Clicking a heading button.
	local headings = profit.rows[1].sortHeadings
	check("headings are buttons", headings.profit.shown and headings.chance.shown and headings.name.shown, true)
	check("sorted heading underlined", headings.chance.edge.shown, true)
	headings.profit.scripts.OnClick(headings.profit)
	check("heading click sorts by profit", ns.db.ui.profitSort, "profit")
	check("heading click starts highest first", select(2, ns.UI.ProfitSort()), false)
	check("underline moves with the sort", headings.profit.edge.shown and not headings.chance.edge.shown, true)
	ns.UI.Refresh("queue")
	ns.UI.Show("queue")
	ns.UI.Show("profit")
	check("only the Profit headings get buttons", (function()
		for _, row in ipairs(ns.UI.windows.queue.rows) do
			if row.sortHeadings.profit.shown then return false end
		end
		return true
	end)(), true)

	-- Hide unprofitable: losing and break-even recipes.
	local results = Results()
	results[1].net = -500
	results[2].net = 0
	ns.UI.Refresh("profit")
	local count = #Results()
	ns.db.ui.hideUnprofitable = true
	ns.UI.Refresh("profit")
	check("losing and break-even recipes hidden", #Results(), count - 2)
	check("hidden count kept", profit.list.hiddenUnprofitable, 2)
	check("status says how many are hidden", profit.status.text:find("2 unprofitable hidden", 1, true) ~= nil, true)
	ns.db.ui.hideUnprofitable = false
	ns.UI.Refresh("profit")
	check("shown again", #Results(), count)
	ns.InvalidateProfit()
	ns.UI.SelectProfession("profit", 197)
end

-- Skill up: the cheapest skill points for the selected profession, coloured, grey left out.
do
	local profit = ns.UI.windows.profit
	ns.UI.Show("profit")
	ns.UI.SelectProfession("profit", 197)
	profit.modeButtons[2].scripts.OnClick(profit.modeButtons[2])
	check("skill mode saved", ns.db.ui.profitMode, "skill")
	check("skill mode lit", profit.modeButtons[2].text, "|cffffffffSkill up|r")
	check("skill headings first", profit.list[1].columns, "skill")
	local rows = {}
	for _, data in ipairs(profit.list) do
		if data.kind == "skill" then rows[data.row.recipeID] = data.row end
	end
	check("orange recipe listed", rows[10] and rows[10].difficulty, 0)
	check("yellow recipe listed", rows[20] and rows[20].difficulty, 1)
	check("grey recipe left out", rows[30], nil)
	check("grey counted", profit.list.trivial, 1)
	check("yellow worth two points", rows[20].points, 2)
	-- Sorted by cost per skill point, lowest first, unless a heading is clicked.
	local function Order(field)
		local values = {}
		for _, data in ipairs(profit.list) do
			if data.kind == "skill" then table.insert(values, data.row[field]) end
		end
		return values
	end
	check("default sort is per point", (ns.UI.ListSort("skill")), "profit")
	check("default sort is lowest first", select(2, ns.UI.ListSort("skill")), true)
	local perPoint = Order("perPoint")
	check("cheapest skill point first", #perPoint == 2 and perPoint[1] <= perPoint[2], true)
	local headings = profit.rows[1].sortHeadings
	check("skill headings are buttons", headings.cost.shown and headings.profit.shown and headings.chance.shown, true)
	check("per point underlined", headings.profit.edge.shown, true)
	headings.chance.scripts.OnClick(headings.chance)
	local chances = Order("chance")
	check("chance sorts highest first", chances[1] >= chances[2], true)
	headings.chance.scripts.OnClick(headings.chance)
	chances = Order("chance")
	check("chance reversed", chances[1] <= chances[2], true)
	ns.UI.SortList("skill", "profit")
	check("per point again starts lowest first", select(2, ns.UI.ListSort("skill")), true)
	check("profit sort untouched", (ns.UI.ListSort("profit")), "profit")
	check("status shows the skill level", profit.status.text:find("Tailoring 50/75", 1, true) ~= nil, true)
	check("unprofitable box hidden in skill mode", profit.hideUnprofitable.shown, false)
	check("selling on the AH box shown in skill mode", profit.sellAH.shown, true)
	-- Item 2 (recipe 10) sells to a vendor for 1c and on the AH for 100: ticked, the AH price counts.
	check("skill: vendor price taken off", rows[10].back, 1)
	check("skill: vendor only unticked", rows[10].backKind, "vendor")
	profit.sellAH.GetChecked = function(self) return self.checked end
	profit.sellAH.checked = true
	profit.sellAH.scripts.OnClick(profit.sellAH)
	check("skill: selling on the AH saved", ns.db.ui.skillSellAH, true)
	local ahRows = {}
	for _, data in ipairs(profit.list) do
		if data.kind == "skill" then ahRows[data.row.recipeID] = data.row end
	end
	check("skill: AH price counted", ahRows[10].backKind, "ah")
	local sale = ns.Planner.Profit(ns.NewContext(), 10).saleUnit * (1 - ns.AH_CUT)
	check("skill: AH price after the cut", ahRows[10].back, sale)
	check("skill: net per craft", ahRows[10].net, ahRows[10].cost - sale)
	profit.sellAH.checked = false
	profit.sellAH.scripts.OnClick(profit.sellAH)
	check("skill: selling on the AH off again", ns.db.ui.skillSellAH, false)
	local first
	for _, row in ipairs(profit.rows) do
		if row.data and row.data.kind == "skill" then first = first or row end
	end
	check("orange text is orange", first.left.text:find("ffff8040", 1, true) ~= nil or first.left.text:find("ffffff00", 1, true) ~= nil, true)
	local queued = #ns.db.queue
	first.plus.scripts.OnClick(first.plus, "LeftButton")
	check("skill row + queues", #ns.db.queue, queued + 1)
	ns.Queue.Remove(#ns.db.queue)
	local realOpen = ns.Recipes.OpenProfession
	ns.Recipes.OpenProfession = function() return nil end
	ns.UI.SelectProfession("profit", nil)
	check("no profession, says how to pick one", profit.list[1].kind, "note")
	ns.Recipes.OpenProfession = realOpen
	profit.modeButtons[1].scripts.OnClick(profit.modeButtons[1])
	check("back to profit mode", profit.list[1].columns, "profit")
	ns.UI.SelectProfession("profit", 197)
end

-- Restock: headings, and own goals told apart from defaults.
do
	ns.UI.Show("restock")
	local restock = ns.UI.windows.restock
	check("restock headings first", restock.list[1].kind == "header" and restock.list[1].columns, "restock")
	local function FirstRow()
		for _, r in ipairs(restock.rows) do
			if r.data and r.data.kind == "restock" then return r end
		end
	end
	local row = FirstRow()
	local itemID = row.data.row.itemID
	ns.Restock.ResetGoal(itemID)
	ns.UI.Refresh("restock")
	row = FirstRow()
	check("default goal has no reset", row.reset.shown, false)
	check("craft column filled", row.colCraft.text ~= nil, true)
	ns.Restock.SetGoal(itemID, ns.Restock.Goal(itemID) + 5)
	ns.UI.Refresh("restock")
	row = FirstRow()
	check("own goal flagged", ns.Restock.IsCustom(itemID), true)
	check("own goal shows reset", row.reset.shown, true)
	row.reset.scripts.OnClick(row.reset)
	check("reset back to default", ns.Restock.IsCustom(itemID), false)
	check("reset goal is the default", ns.Restock.Goal(itemID), ns.Restock.DefaultGoal(itemID))
end

-- Resizing: the size is kept per layout, and right-click on the corner restores the default.
do
	local frame = ns.UI.main.frame
	UIParent.height = 1200
	ns.UI.Show("profit")
	check("default width", frame.width, 797)
	frame:SetSize(900, 700)
	ns.UI.SaveSize()
	ns.UI.Select("queue")
	check("width kept", frame.width, 900)
	check("height kept", frame.height, 700)
	ns.db.ui.queueBeside = true
	ns.UI.Select("restock")
	check("beside has its own width", frame.width, 1240)
	check("beside keeps the height", frame.height, 700)
	ns.db.ui.queueBeside = false
	frame:SetSize(400, 300)
	ns.UI.SaveSize()
	ns.UI.Select("profit")
	check("never narrower than the tabs", frame.width, 797)
	check("never shorter than the minimum", frame.height, 460)
	ns.UI.main.grip.scripts.OnClick(ns.UI.main.grip)
	check("reset width", frame.width, 797)
	check("reset height", frame.height, 560)
	check("reset clears saved size", ns.db.ui.width, nil)
	UIParent.height = 400
end

-- Stale prompt at the AH.
AuctionHouseFrame:Show()
Fire("AUCTION_HOUSE_SHOW")
check("stale scan prompts", ns_popup, "CFF_SCAN")

-- Slash commands.
for _, command in ipairs({ "", "", "queue", "profit", "restock", "sales", "refresh", "advertise", "auto", "auto", "clear", "options", "writs", "writs", "crates", "crates", "changelog", "diag", "bogus" }) do
	SlashCmdList.CFF(command)
end
RunTimers()

-- Late saved data: the session's queue is merged into the table the client hands over.
ns.Queue.Add(10, 1)
CraftingAndFarmingForeverDB = { queue = { { recipeID = 30, qty = 1, char = me } }, recipes = {}, chars = {},
	ui = { hideLosing = true, manualChat = {}, writCraftable = true, priceCapNormal = 150, positions = { main = { x = 1, y = 2 }, next = { x = 3, y = 4 }, farm = { x = 5, y = 6 } } },
	auctionLog = { "old" },
	costs = { [901] = { q = 5, c = 500 } }, costsSeeded = 1,
	sales = { profitFrom = 1, items = { axe = { name = "Axe", sold = 2, expired = 0, gold = 900, exposure = 0,
		days = { [1] = { s = 2, e = 0, g = 900, c = 300, u = 0 }, [0] = { s = 1, e = 0, g = 400, c = 100, u = 0, x = true } } } },
		seen = { someone = { { key = "sold|Copper Axe|2|500", expires = 1 }, { key = "sold|Copper Axe|500", expires = 1 } } } } }
RunTimers()
Fire("PLAYER_LOGOUT")
check("late data adopted", ns.db, CraftingAndFarmingForeverDB)
check("old mail record loses its count", ns.db.sales.seen.someone[1].key, "sold|Copper Axe|500")
check("new mail record left alone", ns.db.sales.seen.someone[2].key, "sold|Copper Axe|500")
ns.db.sales.seen.someone = nil
check("old auction log dropped", ns.db.auctionLog, nil)
check("market-valued costs from 1.7.0 dropped", next(ns.db.costs) == nil and ns.db.costsSeeded == nil, true)
check("their sales cost nothing", ns.db.sales.items.axe.days[1].c == 0 and ns.db.sales.items.axe.days[1].u == 2, true)
check("results from before profit untouched", ns.db.sales.items.axe.days[0].c, 100)
ns.db.sales.items.axe = nil
check("old options dropped", ns.db.ui.hideLosing == nil and ns.db.ui.manualChat == nil and ns.db.ui.writCraftable == nil, true)
check("old price check box dropped", ns.db.ui.priceCapNormal, nil)
check("old window positions dropped", ns.db.ui.positions.farm, nil)
check("main position kept", ns.db.ui.positions.main.y, 2)
check("next position kept", ns.db.ui.positions.next.x, 3)
check("session queue merged", #ns.db.queue, 2)

-- Changelog tab.
do
	local W = ns.WhatsNew
	local tab = ns.UI.main.tabButtons[8]
	check("Writs is the tab after Sales", ns.UI.main.tabButtons[5].key, "writs")
	check("Crates is the tab after Writs", ns.UI.main.tabButtons[6].key, "crates")
	check("Options is the tab before Changelog", ns.UI.main.tabButtons[7].key, "options")
	check("Changelog is the last tab", tab.key, "changelog")
	-- Saved data from a version before the notes existed counts as an update: the tab lights up, nothing opens.
	ns.dataReady, ns.savedDataFound, ns.db.lastSeenVersion = true, true, nil
	ns.UI.Show("profit")
	ns.UI.RefreshTabs()
	check("unseen notes light the tab", tab.badge.shown, true)
	check("unseen tab label is green", tab.label.text:find("ff55dd55", 1, true) ~= nil, true)
	check("nothing marked seen before the tab opens", ns.db.lastSeenVersion, nil)
	ns.UI.Show("changelog")
	RunTimers()
	check("opening the tab marks the version seen", ns.db.lastSeenVersion, tocVersion)
	check("seen notes don't light the tab", tab.badge.shown, false)
	ns.UI.Show("profit")
	check("back to profit", ns.db.ui.tab, "profit")
	check("installed version marked new", W.Text(nil, true):find("Version " .. tocVersion .. "|r  |cff55dd55new", 1, true) ~= nil, true)
	check("nothing marked new when seen", W.Text(tocVersion, false):find("new|r", 1, true), nil)
	check("needs both add-ons", W.NotesText():find("Syndicator", 1, true) ~= nil, true)
	check("TSM is coming", W.NotesText():find("TradeSkillMaster", 1, true) ~= nil, true)
	syndicatorLoaded = false
	check("missing Syndicator noted", W.NotesText():find("isn't active", 1, true) ~= nil, true)
	syndicatorLoaded = true
	check("older version", W.Compare("1.1.0", "1.2.0"), -1)
	check("same version", W.Compare("1.10.0", "1.10.0"), 0)
	check("numbers, not text", W.Compare("1.10.0", "1.9.9"), 1)
	check("not a version", W.Compare("dev", "1.0.0"), nil)
	local saved = ns.CHANGELOG
	ns.CHANGELOG = { { version = "1.3.0", lines = {} }, { version = "1.2.0", lines = {} }, { version = "1.1.0", lines = {} },
		{ version = "1.0.0", lines = {} } }
	local sections = W.Sections("1.0.0", "1.2.0")
	check("every version since the last one seen", #sections, 2)
	check("newest first", sections[1].version, "1.2.0")
	check("nothing newer than the installed version", W.Sections("1.2.0", "1.2.0")[1], nil)
	sections = W.Sections(nil, "1.2.0")
	check("no version seen shows only the newest", #sections, 1)
	check("no version seen shows the installed one", sections[1].version, "1.2.0")
	ns.CHANGELOG = saved
	-- The newest notes are for the toc's version, or for the one about to be released (release.sh bumps the toc after
	-- running these checks).
	check("changelog is up to the toc's version", (W.Compare(ns.CHANGELOG[1].version, tocVersion) or -1) >= 0, true)
end

-- Source data and instructions, on real entries of the generated table.
local realMaps = { [1411] = "Durotar", [1426] = "Dun Morogh", [1429] = "Elwynn Forest", [1412] = "Mulgore", [1420] = "Tirisfal Glades" }
local playerMap
C_Map = {
	GetMapInfo = function(id) return realMaps[id] and { name = realMaps[id] } or nil end,
	GetBestMapForUnit = function() return playerMap end,
}
check("source table loaded", ns.SourceData[2770].k, "mine")
local group, line, details = ns.Farm.Describe(2770)
check("ore grouped under mining", group, "mine")
check("ore names the vein", line:find("Mine Copper Vein", 1, true) ~= nil, true)
check("ore names a zone", line:find("Dun Morogh", 1, true) ~= nil, true)
check("ore lists every zone in the tooltip", details[#details]:find("Tirisfal Glades", 1, true) ~= nil, true)
check("not here by default", line:find("you are here", 1, true), nil)
playerMap = 1429
line = select(2, ns.Farm.Describe(2770))
check("own zone first", line:find("Mine Copper Vein: Elwynn Forest", 1, true) ~= nil, true)
check("own zone marked", line:find("you are here", 1, true) ~= nil, true)
check("leather is skinned", (ns.Farm.Describe(2318)), "skin")
check("herbs are picked", (select(2, ns.Farm.Describe(2447))):find("Pick Peacebloom", 1, true) ~= nil, true)
check("cloth is a drop", (ns.Farm.Describe(2589)), "drop")
check("dust is disenchanted", (ns.Farm.Describe(10940)), "disenchant")
check("unknown item admitted", (ns.Farm.Describe(5503)), "unknown")
-- The Farm It button switches the Queue window and Craft Next to the farm plan and leaves the shopping list alone.
do
	local function Rows(key, kind)
		local found = {}
		for _, row in ipairs(ns.UI.windows[key].rows) do
			if row.data and row:IsShown() and row.data.kind == kind then table.insert(found, row.data) end
		end
		return found
	end
	ns.Queue.Clear()
	ns.Queue.Add(20, 2)
	RunTimers()
	ns.UI.Show("queue")
	local buyList = ns.plan.buy[1]
	check("farm mode starts off", ns.ActivePlan(), ns.plan)
	local modeButtons = ns.UI.windows.queue.modeButtons
	check("Buy It lit while buying", modeButtons[1].text, "|cffffffffBuy It|r")
	check("Farm It not lit while buying", modeButtons[2].text, "Farm It")
	modeButtons[1].scripts.OnClick(modeButtons[1])
	check("pressing the lit mode changes nothing", ns.ActivePlan(), ns.plan)
	modeButtons[2].scripts.OnClick(modeButtons[2])
	check("toggle uses the farm plan", ns.ActivePlan(), ns.farmPlan)
	check("toggle keeps the buy plan", ns.plan.buy[1], buyList)
	check("farm plan buys nothing at AH", next(ns.farmPlan.buy), nil)
	check("farm plan lists what to gather", next(ns.farmPlan.farm) ~= nil, true)

	-- No separate Farm list: the Next step bar is the one window left up, and shows the first thing to gather.
	RunTimers()
	local bar, queue = ns.UI.windows.next, ns.UI.windows.queue
	check("no Farm list window", ns.UI.windows.farm, nil)
	check("main window makes way", ns.UI.IsOpen(), false)
	check("bar stays up", bar.frame:IsShown(), true)
	check("bar offers Buy It while farming", bar.buyButton.shown, true)
	check("bar says Farm It", bar.titleText.text:find("Farm It", 1, true) ~= nil, true)
	-- Gathering comes first, the errands (vendor included) after it, so the bar opens on the first gathering group.
	local barHeader
	for _, data in ipairs(bar.list) do if data.kind == "header" then barHeader = barHeader or data.text end end
	check("vendor in the farm plan", next(ns.farmPlan.vendor) ~= nil, true)
	local firstGroup
	for _, group in ipairs(ns.Farm.GROUPS) do
		for itemID in pairs(ns.farmPlan.farm) do
			if not firstGroup and ns.Farm.Describe(itemID) == group.key then firstGroup = group end
		end
	end
	check("bar starts with the first gathering group", barHeader, firstGroup.title)
	-- Every gathering group at once, each under its own heading, as one step.
	local count, groups = 0, {}
	for itemID in pairs(ns.farmPlan.farm) do
		count = count + 1
		groups[ns.Farm.Describe(itemID)] = true
	end
	local groupCount = 0
	for _ in pairs(groups) do groupCount = groupCount + 1 end
	check("each item says how to get it, all groups", #Rows("next", "how"), count)
	local headers = 0
	for _, data in ipairs(bar.list) do if data.kind == "header" then headers = headers + 1 end end
	check("a heading per gathering group", headers, groupCount)
	for _, row in ipairs(bar.rows) do
		if row.data and row.data.kind == "how" then row.scripts.OnEnter(row) break end
	end
	ns.farmPlan.vendor = vendorPlan
	check("farm choice is remembered", ns.db.ui.farmMode, true)
	count = 0
	for _ in pairs(ns.farmPlan.farm) do count = count + 1 end

	-- The profession window can bring the full Queue back while farming, for Craft Next.
	ns.UI.Show("queue")
	check("full list also follows the farm plan", #Rows("queue", "how"), count)
	check("Farm It lit while farming", modeButtons[2].text, "|cffffffffFarm It|r")
	modeButtons[2].scripts.OnClick(modeButtons[2])
	check("pressing the lit Farm It changes nothing", ns.ActivePlan(), ns.farmPlan)
	ns.UI.Hide()

	bar.buyButton.scripts.OnClick(bar.buyButton)
	RunTimers()
	check("Buy It returns to buying", ns.ActivePlan(), ns.plan)
	check("Buy It reopens the Queue", queue.frame:IsVisible(), true)
	check("how rows gone when buying", #Rows("queue", "how"), 0)
	check("bar's Buy It gone when buying", bar.buyButton.shown, false)
	check("bar back to buying steps", #Rows("next", "how"), 0)
	ns.UI.ToggleMain()
	check("hide-all leaves the bar alone", bar.frame:IsShown(), true)

	ns.ToggleFarmMode()
	ns.Queue.Clear()
	RunTimers()
	check("no bar with an empty queue, farming or not", bar.frame:IsShown(), false)
	ns.db.ui.farmMode = nil
end
for barID, smelt in pairs(ns.Farm.Smelting) do
	check("smelt yield set for " .. barID, smelt.yield >= 1 and #smelt >= 1, true)
end

-- A late invoice changes a sale's count between mailbox scans: still one sale.
do
	ns.db.sales.items, ns.db.sales.lots, ns.db.sales.seen = {}, {}, {}
	inbox = { { subject = "Auction successful: Late Item", money = 500, daysLeft = 30 } }
	local invoiceCount = nil
	GetInboxInvoiceInfo = function() return "seller", "Late Item", "Buyer", 0, 0, 0, 0, 0, 0, 0, invoiceCount end
	ns.Sales.ScanMail()
	invoiceCount = 4
	ns.Sales.ScanMail()
	check("same mail not counted twice", ns.Sales.Item("Late Item").sold, 1)
	GetInboxInvoiceInfo = nil
	inbox = {}
	ns.db.sales.items, ns.db.sales.seen = {}, {}
end

-- Durations follow the game's own text, then Auctionator's record for this version.
do
	check("no text, no record: default", ns.Sales.DurationHours(1), 12)
	Auctionator.Constants = { Durations = { Short = 2, Medium = 8, Long = 24 } }
	check("Auctionator's record", ns.Sales.DurationHours(2), 8)
	AUCTION_DURATION_ONE = "4 Hours"
	check("the game's text wins", ns.Sales.DurationHours(1), 4)
	AUCTION_DURATION_ONE = nil
	Auctionator.Constants = nil
end

-- Posts waiting for the server are matched in order, and a failed one doesn't take the next one's confirmation.
do
	ns.db.sales.lots = {}
	C_Item.GetItemID = function(location) return location.itemID end
	local realTime = time
	ns.db.sales.trips = { realTime() - 7200 }
	local trips = 1
	C_AuctionHouse.PostCommodity({ itemID = 1 }, 2, 3)
	time = function() return realTime() + 120 end
	C_AuctionHouse.PostCommodity({ itemID = 3 }, 2, 5)
	C_AuctionHouse.PostItem({ itemID = 1 }, 2, 1)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")
	check("failed post dropped", ns.db.sales.lots[1].itemID, 3)
	check("its quantity", ns.db.sales.lots[1].qty, 5)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")
	check("second post matched", ns.db.sales.lots[2].itemID, 1)
	check("posts minutes apart are one restock", #ns.db.sales.trips, trips + 1)
	time = realTime
	ns.db.sales.lots = {}

	-- A post another add-on sent (Auctionator's Selling tab) that the server refused: the next confirmation is the
	-- next post's, not the refused one's.
	C_AuctionHouse.PostItem({ itemID = 7 }, 2, 1)
	Fire("AUCTION_HOUSE_SHOW_ERROR", 10)
	C_AuctionHouse.PostItem({ itemID = 8 }, 2, 1)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")
	check("refused post from elsewhere dropped", ns.db.sales.lots[1] and ns.db.sales.lots[1].itemID, 8)
	check("one lot recorded", #ns.db.sales.lots, 1)
	-- An error long after a post isn't about it.
	ns.db.sales.lots = {}
	C_AuctionHouse.PostItem({ itemID = 9 }, 2, 1)
	time = function() return realTime() + 30 end
	Fire("AUCTION_HOUSE_SHOW_ERROR", 10)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")
	check("late error leaves the post", ns.db.sales.lots[1] and ns.db.sales.lots[1].itemID, 9)
	time = realTime
	ns.db.sales.lots = {}
end

-- Farming, every gathering group is on the bar at once as one step, each under its heading, before smelting.
do
	ns.db.ui.farmMode = true
	local realPlan = ns.farmPlan
	ns.farmPlan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, bank = {}, smelt = { [2840] = 4 }, cost = 0,
		farm = { [2770] = 6, [2447] = 3, [2318] = 2 } }
	table.insert(ns.db.queue, { recipeID = 20, qty = 1, char = ns.CharKey() })
	ns.UI.RefreshQueue()
	local bar = ns.UI.windows.next
	local headers, how = {}, 0
	for _, data in ipairs(bar.list) do
		if data.kind == "header" then table.insert(headers, data.text) end
		if data.kind == "how" then how = how + 1 end
	end
	check("three gathering headings", table.concat(headers, ","), "Mine,Pick herbs,Skin")
	check("every item says where", how, 3)
	check("gathering, smelting, crafting: three steps", bar.steps, 3)
	-- Errands (alts, bank, vendor) come after gathering, smelting after them.
	ns.farmPlan.fetch = { Alt = { [2589] = 2 } }
	ns.farmPlan.bank = { [2589] = 1 }
	ns.farmPlan.vendor = { [2320] = 1 }
	ns.UI.RefreshQueue()
	local titles = {}
	for _, data in ipairs(ns.UI.windows.queue.build()) do
		if data.kind == "header" then table.insert(titles, (data.text:gsub(":.*", ""))) end
	end
	local order = table.concat(titles, "\n")
	check("farm steps: gather, then errands", order, table.concat({
		"1. Mine", "2. Pick herbs", "3. Skin", "4. Get from Alt (log in there and mail them over)",
		"5. Take from your bank", "6. Buy from vendor", "7. Smelt with Mining", "8. Craft your queue",
	}, "\n"))
	check("bar grows for farming", bar.maxRows > 10, true)
	ns.db.ui.nextMinimized = true
	ns.UI.Refresh("next")
	check("folded title sums it up", bar.titleText.text:find("Gather materials", 1, true) ~= nil, true)
	ns.db.ui.nextMinimized = nil
	ns.farmPlan = realPlan
	ns.db.ui.farmMode = nil
	ns.Queue.Clear()
	RunTimers()
end

-- Farming, the bar includes smelting, so it can't skip to crafting while bars are still to make.
do
	ns.db.ui.farmMode = true
	local realPlan = ns.farmPlan
	ns.farmPlan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, bank = {}, farm = {}, smelt = { [2840] = 4 }, cost = 0 }
	table.insert(ns.db.queue, { recipeID = 20, qty = 1, char = ns.CharKey() })
	ns.UI.RefreshQueue()
	local list = ns.UI.windows.next.list
	-- Prices are stale here, and farming the bar is the only window up, so it starts with the scan warning.
	check("stale prices warned first", list[1].kind, "warn")
	check("warning names the age", list[1].text:find("hours old", 1, true) ~= nil, true)
	check("smelting is the step", list[2].text, "Smelt with Mining")
	check("smelting listed", list[3].itemID, 2840)
	ns.farmPlan = realPlan
	ns.db.ui.farmMode = nil
	ns.Queue.Clear()
	RunTimers()
end

-- Restocking tab: lists what's craftable in the bags, searches, suggests a price, posts and moves on.
do
	local bags = {}
	C_Container = {
		GetContainerNumSlots = function(bag) return bag == 0 and math.max(#bags, 20) or 0 end, -- room to spare: bag space has its own test
		GetContainerItemInfo = function(_, slot) return bags[slot] end,
	}
	ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot, itemID = bags[slot].itemID } end }
	-- Bag contents: soulbound left out, stacks summed, an unlocked slot preferred.
	bags[1] = { itemID = 7, stackCount = 2, isLocked = true }
	bags[2] = { itemID = 7, stackCount = 3 }
	bags[3] = { itemID = 8, stackCount = 1, isBound = true }
	local bagCounts, bagSlots = ns.Stock.BagContents()
	check("bag contents: stacks summed", bagCounts[7], 5)
	check("bag contents: soulbound left out", bagCounts[8], nil)
	check("bag contents: unlocked slot", bagSlots[7].slot, 2)
	wipe(bags)
	Enum.ItemCommodityStatus = { Commodity = 2 }
	local posts = {}
	local commodity = {}
	local listings = {}
	local ready = true
	local searches = 0
	C_AuctionHouse.IsThrottledMessageSystemReady = function() return ready end
	C_AuctionHouse.MakeItemKey = function(itemID) return { itemID = itemID } end
	local lastSearch
	local realSearch, realSellSearch = C_AuctionHouse.SendSearchQuery, C_AuctionHouse.SendSellSearchQuery
	C_AuctionHouse.SendSearchQuery = function(key, sorts, separate)
		realSearch(key, sorts, separate)
		searches = searches + 1
		lastSearch = { kind = "plain", key = key, sort = sorts[1].sortOrder }
	end
	C_AuctionHouse.SendSellSearchQuery = function(key, sorts, separate)
		realSellSearch(key, sorts, separate)
		searches = searches + 1
		lastSearch = { kind = "sell", key = key, sort = sorts[1].sortOrder }
	end
	local keyInfoMissing = {}
	C_AuctionHouse.GetItemKeyInfo = function(key) return not keyInfoMissing[key.itemID] and {} or nil end
	local sellValid = true
	C_AuctionHouse.IsSellItemValid = function() return sellValid end
	local availableCount = 99
	Enum.ItemClass = { Weapon = 2, Armor = 4 }
	local itemClass = {}
	C_Item.GetItemInfoInstant = function(itemID) return itemID, "", "", "", 1, itemClass[itemID] or 7, 0 end
	C_AuctionHouse.GetItemCommodityStatus = function(location) return commodity[location.itemID] and 2 or 1 end
	C_AuctionHouse.GetAvailablePostCount = function() return availableCount end
	C_AuctionHouse.CalculateCommodityDeposit = function() return 7 end
	C_AuctionHouse.CalculateItemDeposit = function() return 9 end
	C_AuctionHouse.GetNumItemSearchResults = function(key) return #(listings[key.itemID] or {}) end
	C_AuctionHouse.GetItemSearchResultInfo = function(key, index) return listings[key.itemID][index] end
	C_AuctionHouse.GetNumCommoditySearchResults = function(itemID) return #(listings[itemID] or {}) end
	C_AuctionHouse.GetCommoditySearchResultInfo = function(itemID, index) return listings[itemID][index] end
	local realItemPost, realCommodityPost = C_AuctionHouse.PostItem, C_AuctionHouse.PostCommodity
	C_AuctionHouse.PostItem = function(location, duration, quantity, bid, buyout)
		realItemPost(location, duration, quantity, bid, buyout)
		table.insert(posts, { itemID = location.itemID, slot = location.slot, duration = duration, quantity = quantity, bid = bid, price = buyout, kind = "item" })
	end
	C_AuctionHouse.PostCommodity = function(location, duration, quantity, price)
		realCommodityPost(location, duration, quantity, price)
		table.insert(posts, { itemID = location.itemID, duration = duration, quantity = quantity, price = price, kind = "commodity" })
	end

	local created
	LibStub = function() return { CreateTab = function(_, id, frame, label) created = { id = id, frame = frame, label = label } end } end
	ns.Queue.Clear()
	RunTimers()
	playerMoney = 100000

	-- Item 4 is the shirt from recipe 20; nothing makes the cloth, item 1.
	local shirt = ns.db.recipes[20].o
	bags = { { itemID = shirt, stackCount = 3 }, { itemID = 1, stackCount = 20 }, { itemID = shirt, stackCount = 1, isBound = true } }
	Fire("AUCTION_HOUSE_SHOW")
	RunTimers()
	check("tab named", created and created.label, "Restocking")
	check("tab added once", (function()
		local first = created
		Fire("AUCTION_HOUSE_SHOW")
		RunTimers()
		return created == first
	end)(), true)

	local window = ns.Posting.window
	AuctionHouseFrame:Show()
	created.frame:Show()
	ns.db.restock.goals[shirt] = 2
	ns.UI.Refresh("posting")
	local rows = window.list
	check("only items a recipe makes", #rows, 1)
	check("craft listed", rows[1].row.itemID, shirt)
	check("bound copy not counted", rows[1].row.inBags, 3)
	check("goal limits the suggestion", rows[1].row.toPost, 2)
	check("first row selected", rows[1].selected, true)
	check("profit each from the scanned price", rows[1].row.unitProfit,
		ns.Prices.AH(shirt) and rows[1].row.unitCost and ns.Prices.AH(shirt) * (1 - ns.AH_CUT) - rows[1].row.unitCost or nil)
	check("profit each known", rows[1].row.unitProfit ~= nil, true)
	check("search sent", searches >= 1, true)
	check("items sort by buyout", lastSearch.sort, 4)
	check("items use the plain search", lastSearch.kind, "plain")

	-- Someone else sells at 500: posted at the same price, no undercut. Below break-even raises it instead.
	listings[shirt] = { { buyoutAmount = 700, containsOwnerItem = false }, { buyoutAmount = 500, containsOwnerItem = false } }
	Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = shirt })
	-- The row's profit each follows the live lowest once the search answers, so it agrees with the form (#26).
	check("profit each at the live price", window.list[1].row.unitProfit, 500 * (1 - ns.AH_CUT) - window.list[1].row.unitCost)
	check("row knows it's the live price", window.list[1].row.livePrice, true)
	local posted = #posts
	ns.Posting.PostSelected()
	check("posted", #posts, posted + 1)
	local last = posts[#posts]
	check("item matches the lowest", last.price, 500)
	check("suggested quantity", last.quantity, 2)
	check("saved duration", last.duration, 2)
	check("item post has no bid", last.bid, nil)
	check("sent as an item", last.kind, "item")
	ns.Posting.PostSelected()
	check("double click doesn't post twice", #posts, posted + 1)

	Fire("AUCTION_HOUSE_AUCTION_CREATED")
	check("post recorded for the odds", ns.db.sales.lots[#ns.db.sales.lots].itemID, shirt)
	check("deposit per unit kept for smart goals", ns.Sales.Deposit(shirt), 9 / 2)
	bags[1].stackCount = 1
	RunTimers()
	ns.UI.Refresh("posting")
	rows = window.list
	check("posted units count at once", rows[1].row.toPost, 0)
	check("nothing left selected", rows[1].selected, false)
	check("still there to post by hand", rows[1].row.inBags, 1)

	-- By hand: selecting it works even with the goal met, and a typed price is kept when the search answers.
	ns.Posting.Select(shirt)
	check("selected by hand", window.list[1].selected, true)
	listings[shirt] = { { buyoutAmount = 400, containsOwnerItem = true } }
	Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = shirt })
	ns.Posting.PostSelected()
	check("own listing matched", posts[#posts].price, 400)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")

	-- The queue's materials are held back.
	ns.db.restock.goals[shirt] = 10
	ns.Queue.Add(20, 1)
	RunTimers()
	local bolts = ns.db.recipes[10].o
	ns.db.restock.goals[bolts] = 100
	bags = { { itemID = bolts, stackCount = 5 } }
	listings[bolts] = {}
	ns.UI.Refresh("posting")
	check("queue's materials held back", window.list[1].row.toPost, 5 - window.list[1].row.reserved)
	check("queue reserves some", window.list[1].row.reserved > 0, true)
	ns.Queue.Clear()
	RunTimers()

	-- Commodities sort by price; equipment needs the sell search and a key with no item level.
	do
		commodity[bolts] = true
		bags = { { itemID = bolts, stackCount = 5 } }
		ns.db.restock.goals[bolts] = 500
		ns.Posting.Select(bolts)
		ns.UI.Refresh("posting")
		check("commodities sort by price", lastSearch.sort, 0)
		listings[bolts] = { { unitPrice = 500, containsOwnerItem = false } }
		Fire("COMMODITY_SEARCH_RESULTS_UPDATED", bolts)
		local commodityPosts = #posts
		ns.Posting.PostSelected()
		check("commodity matches the lowest", posts[commodityPosts + 1].price, 500)
		Fire("AUCTION_HOUSE_AUCTION_CREATED")
		commodity[bolts] = nil

		itemClass[shirt] = 4
		bags = { { itemID = shirt, stackCount = 1 } }
		ns.db.restock.goals[shirt] = 500
		ns.UI.Refresh("posting")
		ns.Posting.Select(shirt)
		check("equipment uses the sell search", lastSearch.kind, "sell")
		check("equipment key has no level", lastSearch.key.itemLevel, 0)
		check("equipment sorts by buyout", lastSearch.sort, 4)
		itemClass[shirt] = nil

		-- Details not loaded: the search waits for them, as the client would ignore it.
		keyInfoMissing[shirt] = true
		local before = searches
		ns.Posting.Select(shirt)
		check("search waits for item details", searches, before)
		keyInfoMissing[shirt] = nil
		for frame in pairs(eventFrames) do
			if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, "ITEM_KEY_ITEM_INFO_RECEIVED", shirt) end
		end
		check("search goes when they arrive", searches, before + 1)

		-- Locked by another add-on: another copy is used, or it says so instead of posting.
		listings[shirt] = {}
		prices[shirt] = 5000
		RunTimers()
		bags = { { itemID = shirt, stackCount = 1, isLocked = true } }
		ns.UI.Refresh("posting")
		local count = #posts
		ns.Posting.PostSelected()
		check("locked item not posted", #posts, count)
		bags = { { itemID = shirt, stackCount = 1, isLocked = true }, { itemID = shirt, stackCount = 1 } }
		ns.UI.Refresh("posting")
		ns.Posting.PostSelected()
		check("unlocked copy posted", #posts, count + 1)
		check("from its slot", posts[#posts].slot, 2)

		-- Refused: reported with what was sent, the button works again and the record isn't kept.
		local lots = #ns.db.sales.lots
		Fire("AUCTION_HOUSE_SHOW_ERROR", 10)
		check("refusal keeps the error", ns.db.lastAuctionRefusal.code, 10)
		check("refusal kept for reading later", ns.db.lastAuctionRefusal.kind, "post")
		check("refusal says what was sent", ns.db.lastAuctionRefusal.text:find("price 5000", 1, true) ~= nil, true)
		Fire("AUCTION_HOUSE_AUCTION_CREATED")
		check("refused post not recorded", #ns.db.sales.lots, lots)
		ns.Posting.PostSelected()
		check("can post again after a refusal", #posts, count + 2)
		Fire("AUCTION_HOUSE_AUCTION_CREATED")

		-- The game says it can't be sold, or none are available.
		ns.Posting.Select(shirt)
		count = #posts
		sellValid = false
		ns.Posting.PostSelected()
		check("invalid item not posted", #posts, count)
		sellValid = true
		availableCount = 0
		ns.Posting.PostSelected()
		check("nothing available, no post", #posts, count)
		availableCount = 99

		-- A vendor pays more: asks first, and only what it asked about gets posted.
		local realInfo = C_Item.GetItemInfo
		C_Item.GetItemInfo = function(id)
			local info = { realInfo(id) }
			if id == shirt then info[11] = 6000 end
			return (table.unpack or unpack)(info, 1, 14)
		end
		ns_popup = nil
		listings[shirt] = {}
		Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = shirt })
		count = #posts
		ns.Posting.PostSelected()
		check("below vendor asks first", ns_popup, "CFF_BELOW_VENDOR")
		check("below vendor not posted yet", #posts, count)
		local dialog = StaticPopupDialogs.CFF_BELOW_VENDOR
		dialog.OnAccept(nil, ns_popupData)
		check("posted once agreed", #posts, count + 1)
		check("at the price it asked about", posts[#posts].price, 5000)
		Fire("AUCTION_HOUSE_AUCTION_CREATED")
		ns.Posting.Select(shirt)
		Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = shirt })
		ns.Posting.PostSelected()
		local asked = ns_popupData
		ns.Posting.Select(shirt) -- clears the price behind the dialog
		count = #posts
		dialog.OnAccept(nil, asked)
		check("changed behind the dialog, not posted", #posts, count)
		C_Item.GetItemInfo = realInfo
	end


	-- Busy: the search waits until the auction house can take it.
	ready = false
	local before = searches
	bags = { { itemID = shirt, stackCount = 2 } }
	ns.db.restock.goals[shirt] = 50
	AuctionHouseFrame:Hide()
	Fire("AUCTION_HOUSE_CLOSED")
	AuctionHouseFrame:Show()
	ns.UI.Refresh("posting")
	check("no search while throttled", searches, before)
	prices[shirt] = 900
	ready = true
	Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	check("search sent when ready", searches, before + 1)

	-- No answer: falls back to the last scan once the wait is over.
	RunTimers()
	ns.Posting.PostSelected()
	check("last scan used after the wait", posts[#posts].price, 900)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")

	-- Skipped with Next item, then the one after it posted: moves on down the list, not back to the skipped one.
	do
		ns.db.recipes[51] = { n = "Third Craft", o = 3, qmin = 1, qmax = 1, r = { { 1, 1 } } }
		ns.db.chars[me].recipes[51] = true
		for _, itemID in ipairs({ shirt, bolts, 3 }) do ns.db.restock.goals[itemID] = 500 end
		bags = { { itemID = shirt, stackCount = 2 }, { itemID = bolts, stackCount = 2 }, { itemID = 3, stackCount = 2 } }
		ns.UI.Refresh("posting")
		local order = {}
		for _, data in ipairs(window.list) do
			if data.row and data.row.toPost > 0 then order[#order + 1] = data.row.itemID end
		end
		check("three to post", #order, 3)
		ns.Posting.Select(order[1])
		ns.Posting.SelectNext()
		ns.UI.Refresh("posting")
		local second
		for _, data in ipairs(window.list) do if data.selected then second = data.row.itemID end end
		check("next item skips the top one", second, order[2])
		listings[second] = { { buyoutAmount = 500, unitPrice = 500, containsOwnerItem = false } }
		Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = second })
		Fire("COMMODITY_SEARCH_RESULTS_UPDATED", second)
		ns.Posting.PostSelected()
		Fire("AUCTION_HOUSE_AUCTION_CREATED")
		for _, slot in ipairs(bags) do if slot.itemID == second then slot.stackCount = 0 end end
		RunTimers()
		ns.UI.Refresh("posting")
		local now
		for _, data in ipairs(window.list) do if data.selected then now = data.row.itemID end end
		check("after a post: the one below, not the skipped top one", now, order[3])
		ns.db.recipes[51], ns.db.chars[me].recipes[51] = nil, nil
		for _, itemID in ipairs({ shirt, bolts, 3 }) do ns.db.restock.goals[itemID] = nil end
	end

	AuctionHouseFrame:Hide()
	Fire("AUCTION_HOUSE_CLOSED")
	created.frame:Hide()
	ns.db.restock.goals = {}
	ns.db.sales.lots = {}
end

-- Queue rows: losing entries shaded and removable in one go (after asking), the crafter shown when it's an alt,
-- and a hint when the queue is empty.
do
	ns.Queue.Clear()
	ns.Queue.Add(20, 2)
	RunTimers()
	ns.UI.Show("queue")
	local queue = ns.UI.windows.queue
	local function EntryRow(recipeID)
		for _, row in ipairs(queue.rows) do
			if row.data and row.data.kind == "queue" and row.data.entry.recipeID == recipeID then return row end
		end
	end
	check("profitable entry not shaded", EntryRow(20).tint:IsShown(), false)
	check("no remove-losing button without losers", queue.removeLosingButton:IsShown(), false)

	local salePrice = prices[4]
	prices[4] = 1
	ns.RefreshEverything()
	RunTimers()
	check("losing entry shaded", EntryRow(20).tint:IsShown(), true)
	check("remove-losing button shown", queue.removeLosingButton:IsShown(), true)
	check("remove-losing button counts", queue.removeLosingButton:GetText(), "Remove losing (1)")
	ns_popup = nil
	queue.removeLosingButton.scripts.OnClick(queue.removeLosingButton)
	check("remove losing asks first", ns_popup, "CFF_REMOVE_LOSING")
	check("nothing removed before yes", #ns.db.queue, 1)
	StaticPopupDialogs.CFF_REMOVE_LOSING.OnAccept()
	check("losing entry removed", #ns.db.queue, 0)
	prices[4] = salePrice
	ns.RefreshEverything()
	RunTimers()

	check("empty queue says so", queue.list[1].text, "The queue is empty.")
	check("empty queue says how to add", queue.list[2].text:find("Profit tab", 1, true) ~= nil, true)

	ns.db.recipes[500] = { n = "Bronze Bar", o = 2, qmin = 1, qmax = 1, p = 186, pn = "Mining", r = { { 1, 1 } } }
	ns.db.chars["Player-2-ALT"] = { name = "Alt", class = "Mage", recipes = { [500] = true } }
	ns.Queue.Add(500, 1)
	ns.Queue.Add(20, 1)
	RunTimers()
	check("alt's craft names the alt", EntryRow(500).left.text:find("Alt", 1, true) ~= nil, true)
	check("own craft names no one", EntryRow(20).left.text:find("Snic", 1, true), nil)
	-- The alt's entry is its own step after yours, and none of its materials are on this character's list.
	local headers = {}
	for _, data in ipairs(queue.list) do if data.kind == "header" then table.insert(headers, data.text) end end
	check("alt's step comes last", headers[#headers]:find("Log in to Alt", 1, true) ~= nil, true)
	check("own crafts before it", headers[#headers - 1]:find("Craft your queue", 1, true) ~= nil, true)
	check("alt's craft not in this character's plan", ns.plan.elsewhere["Player-2-ALT"], 1)
	for _, craft in ipairs(ns.plan.crafts) do check("no alt craft planned here", craft.recipeID ~= 500, true) end
	ns.Queue.Remove(2)
	RunTimers()
	local bar = ns.UI.windows.next
	check("only the alt left: bar says log in", bar.list[1].text, "Log in to Alt")
	check("bar lists the alt's craft", bar.list[2].kind, "next")
	local _, _, reason = ns.Queue.NextCraft()
	check("Craft Next says log in", reason, "Nothing left to craft here. Log in to Alt.")
	check("nothing bought here for the alt", next(ns.plan.buy), nil)
	ns.Queue.Clear()
	ns.db.chars["Player-2-ALT"] = nil
	ns.db.recipes[500] = nil
	RunTimers()
end

-- Next step bar: only there while something is queued, opens on the first step of the to-do list, folds to its
-- title line, and comes back folded or not as it was left.
do
	ns.Queue.Clear()
	RunTimers()
	check("no bar before anything is queued", ns.UI.windows.next == nil or not ns.UI.windows.next.frame:IsShown(), true)
	ns.Queue.Add(20, 2)
	RunTimers()
	local bar = ns.UI.windows.next
	check("bar appears with a queue", bar ~= nil and bar.frame:IsShown(), true)
	ns.UI.Show("queue")
	local firstHeader
	for _, data in ipairs(ns.UI.windows.queue.list) do
		if data.kind == "header" then firstHeader = firstHeader or data.text end
	end
	ns.UI.Hide()
	check("bar shows the first step", bar.list[1].kind, "header")
	check("first step without its number", firstHeader:find(bar.list[1].text, 1, true) ~= nil, true)
	check("step title is short", bar.list[1].text:find("(", 1, true), nil)
	check("step title unnumbered", bar.list[1].text:find("^%d"), nil)
	for _, data in ipairs(bar.list) do
		if data.kind == "item" then check("bar rows carry no prices", data.priceLabel, nil) end
	end
	check("bar names the step count", bar.countText.text ~= nil, true)
	check("bar title", bar.titleText.text, "Next step")
	local openHeight = bar.frame:GetHeight()

	bar.foldButton.scripts.OnClick(bar.foldButton)
	check("folding is remembered", ns.db.ui.nextMinimized, true)
	check("folded bar has no rows", #bar.list, 0)
	check("folded bar is shorter", bar.frame:GetHeight() < openHeight, true)
	check("folded title names the step", bar.titleText.text:find("Next: ", 1, true) ~= nil, true)
	check("folded bar still there", bar.frame:IsShown(), true)
	SlashCmdList.CFF("next")
	check("slash command unfolds", ns.db.ui.nextMinimized, nil)
	check("unfolded rows back", #bar.list > 0, true)

	-- Materials in the bags: the step is crafting the entry, as a plain row with its count, with Craft Next.
	local itemCount = C_Item.GetItemCount
	C_Item.GetItemCount = function(id) return id == 1 and 10 or 0 end
	ns.Queue.Clear()
	ns.Queue.Add(10, 3)
	RunTimers()
	check("bar still up", bar.frame:IsShown(), true)
	check("craft step title", bar.list[1].text, "Craft your queue")
	local craftRow = bar.list[2]
	check("craft row", craftRow and craftRow.kind, "next")
	check("craft row counts the entry", craftRow and craftRow.count, 3)
	check("craft row text", bar.rows[2].right.text, "x3")
	bar.rows[2].scripts.OnEnter(bar.rows[2])
	check("Craft Next on the bar", bar.craftButton.shown, true)
	check("Craft Next names the craft", bar.craftButton.text:find("Recipe10", 1, true) ~= nil, true)
	local craftable = C_TradeSkillUI.GetCraftableCount
	C_TradeSkillUI.GetCraftableCount = function() return 0 end
	ns.UI.Refresh("next")
	check("blocked: bar button stays", bar.craftButton.shown, true)
	check("blocked: bar button says finish", bar.craftButton.text, "Finish Recipe10: 3 left")
	C_TradeSkillUI.GetCraftableCount = craftable
	ns.UI.Refresh("next")

	-- The Craft Next bar is also the progress bar: crafting 3, it counts through them with the time left.
	local button = bar.craftButton
	check("idle bar says how long", button.detail.text:find("x3 takes", 1, true) ~= nil, true)
	local realTime, realCasting = GetTime, UnitCastingInfo
	local now = 100
	GetTime = function() return now end
	UnitCastingInfo = function() return "Recipe10", nil, nil, 100000, 102000 end
	Fire("UNIT_SPELLCAST_START", "player", "cast", 10)
	check("cast time measured", ns.db.craftTimes[10], 2)
	check("bar shows the craft in progress", button.text:find("1 / 3", 1, true) ~= nil, true)
	now = 101
	ns.UI.UpdateCraftBars()
	-- 1 s left on this cast, then two more crafts of 2 s cast + 0.25 s pause.
	check("bar shows time left on the recipe", button.detail.text:find("6s", 1, true) ~= nil, true)
	local progress = ns.Queue.CraftProgress()
	check("progress: casting", progress.casting, 10)
	check("progress: all crafts time", progress.allSeconds, 5.5)
	check("progress: all fill started", progress.allFraction ~= nil, true)
	UnitCastingInfo = function() return nil end
	now = 102
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 10)
	Fire("UNIT_SPELLCAST_STOP", "player", "cast", 10)
	RunTimers()
	progress = ns.Queue.CraftProgress()
	check("progress: one done", progress.done, 1)
	check("progress: of three", progress.total, 3)
	check("right after a craft: still crafting look", button.text:find("2 / 3", 1, true) ~= nil, true)
	now = 103
	ns.UI.UpdateCraftBars()
	check("paused bar is Craft Next again", button.text:find("Craft Next", 1, true) ~= nil, true)
	check("paused bar says how far", button.detail.text:find("1 / 3 done", 1, true) ~= nil, true)
	UnitCastingInfo = function() return "Recipe10", nil, nil, 102200, 104200 end
	now = 102.2
	Fire("UNIT_SPELLCAST_START", "player", "cast", 10)
	check("pause between casts learned", math.abs(ns.db.craftGap - (0.25 * 0.7 + 0.2 * 0.3)) < 1e-9, true)
	check("second craft", button.text:find("2 / 3", 1, true) ~= nil, true)
	-- The batch's next cast starts before the plan is rebuilt: the plan still counts the craft just finished,
	-- which isn't more queued (it said 3 / 4 here).
	now = 104.2
	FireNow("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 10)
	FireNow("UNIT_SPELLCAST_STOP", "player", "cast", 10)
	UnitCastingInfo = function() return "Recipe10", nil, nil, 104400, 106400 end
	now = 104.4
	FireNow("UNIT_SPELLCAST_START", "player", "cast", 10)
	progress = ns.Queue.CraftProgress()
	check("stale plan: still of three", progress.total, 3)
	check("stale plan: third craft", progress.done, 2)
	-- Craft Next takes the finished craft off too, so a click now wouldn't make a fourth.
	local _, staleCount = ns.Queue.NextCraft()
	check("stale plan: Craft Next batch is the one left", staleCount, 1)
	RunTimers()
	ns.UI.UpdateCraftBars()
	check("third craft", button.text:find("3 / 3", 1, true) ~= nil, true)
	ns.Queue.Add(10, 2)
	RunTimers()
	UnitCastingInfo = function() return nil end
	now = 106.4
	FireNow("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 10)
	UnitCastingInfo = function() return "Recipe10", nil, nil, 106600, 108600 end
	now = 106.6
	Fire("UNIT_SPELLCAST_START", "player", "cast", 10)
	-- Each craft floats up from the bar and counts the streak; the third of three finished the batch.
	local fx = button.cf.fx
	check("craft fx: layer on the bar", fx ~= nil, true)
	check("craft fx: streak counted", fx and fx.chip.shown, true)
	check("craft fx: batch banner", fx and fx.banner.shown and fx.banner.text:find("Batch complete! ", 1, true) ~= nil,
		true)
	check("craft fx: session crafts", ns.CraftFx.Diag():find("^%d+ crafts this session") ~= nil, true)
	-- 3 done, 2 more queued during the last one: a new run of the 2, though the plan still counts 3.
	progress = ns.Queue.CraftProgress()
	check("queued more: new run of two", progress.total, 2)
	check("queued more: first of them", progress.done, 0)
	UnitCastingInfo = function() return nil end
	Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast", 10)
	check("interrupted: not casting", ns.Queue.CraftProgress().casting, nil)
	GetTime, UnitCastingInfo = realTime, realCasting
	ns.Queue.Add(10, 2) -- back to 3 queued
	RunTimers()

	ns.db.ui.nextMinimized = true
	ns.UI.Refresh("next")
	check("no Craft Next when folded", bar.craftButton.shown, false)
	ns.db.ui.nextMinimized = nil
	C_Item.GetItemCount = itemCount

	ns.Queue.Clear()
	RunTimers()
	check("bar gone with an empty queue", bar.frame:IsShown(), false)
	SlashCmdList.CFF("next")
	check("slash command on empty queue doesn't fold", ns.db.ui.nextMinimized, nil)
	check("and doesn't bring the bar back", bar.frame:IsShown(), false)
	ns.db.ui.nextMinimized = true
	ns.Queue.Add(20, 1)
	RunTimers()
	check("comes back folded", bar.frame:IsShown() and #bar.list == 0, true)
	ns.db.ui.nextMinimized = nil

	-- Out of the way in combat and instances, back afterwards.
	Fire("PLAYER_REGEN_DISABLED")
	check("hidden in combat", bar.frame:IsShown(), false)
	ns.Queue.Add(20, 1)
	RunTimers()
	check("queue changes in combat don't bring it back", bar.frame:IsShown(), false)
	SlashCmdList.CFF("next")
	check("slash command in combat doesn't fold", ns.db.ui.nextMinimized, nil)
	Fire("PLAYER_REGEN_ENABLED")
	check("back after combat", bar.frame:IsShown(), true)
	inInstance = true
	Fire("PLAYER_ENTERING_WORLD")
	check("hidden in a dungeon", bar.frame:IsShown(), false)
	inInstance = false
	Fire("ZONE_CHANGED_NEW_AREA")
	RunTimers()
	check("back outside", bar.frame:IsShown(), true)
	inCombat = true
	Fire("PLAYER_ENTERING_WORLD")
	check("reloading mid-fight keeps it hidden", bar.frame:IsShown(), false)
	inCombat = false
	Fire("PLAYER_REGEN_ENABLED")
	ns.Queue.Clear()
	RunTimers()
end

-- Bought at the auction house: counts as in the mailbox right away, so it leaves the shopping list, and the queue
-- says to collect it. Opening the mailbox replaces the guess with what's really there, without counting it twice.
do
	ns.Queue.Clear()
	ns.Queue.Add(20, 2)
	RunTimers()
	local itemID, needed = next(ns.plan.buy)
	check("something to buy", itemID ~= nil, true)
	local function Listed()
		local found = false
		for _, entry in ipairs(lists[ns.LIST_NAME] or {}) do
			if entry:lower():find(names[itemID]:lower(), 1, true) then found = true end
		end
		return found
	end
	check("on the shopping list before buying", Listed(), true)

	-- Where to buy is spelled out under the step, in the Queue tab and the Next step bar, and in chat at the AH.
	ns.UI.Show("queue")
	local qlist = ns.UI.windows.queue.list
	local buyAt
	for index, data in ipairs(qlist) do
		if data.kind == "header" and data.text:find("Buy at auction house", 1, true) then buyAt = index end
	end
	check("tip right under the buy step", qlist[buyAt + 1].kind, "tip")
	check("tip names the Shopping tab", qlist[buyAt + 1].text:find("Shopping tab", 1, true) ~= nil, true)
	local tips = {}
	for _, data in ipairs(qlist) do if data.kind == "tip" then table.insert(tips, data.text) end end
	check("tip names the list", table.concat(tips, " "):find(ns.LIST_NAME, 1, true) ~= nil, true)
	ns.UI.Hide()
	local barTips = 0
	for _, data in ipairs(ns.UI.windows.next.list) do if data.kind == "tip" then barTips = barTips + 1 end end
	check("bar shows the tip too", barTips, #tips)
	for _, row in ipairs(ns.UI.windows.next.rows) do
		if row.data and row.data.kind == "tip" then row.scripts.OnEnter(row) break end
	end
	local printed = {}
	local realPrint = ns.Print
	ns.Print = function(text) table.insert(printed, text) end
	local ahShown = AuctionHouseFrame.shown
	AuctionHouseFrame.shown = true
	Fire("AUCTION_HOUSE_SHOW")
	RunTimers()
	local told = false
	for _, text in ipairs(printed) do if text:find("Shopping tab", 1, true) then told = true end end
	check("chat says where at the AH", told, true)
	AuctionHouseFrame.shown = ahShown
	ns.Print = realPrint

	C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, needed)
	Fire("COMMODITY_PURCHASE_FAILED")
	RunTimers()
	check("a failed purchase changes nothing", ns.plan.buy[itemID], needed)

	C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, needed - 1)
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	RunTimers()
	check("part bought: the rest still to buy", ns.plan.buy[itemID], 1)
	check("part bought: waiting in the mail", ns.plan.mail[itemID], needed - 1)
	check("still listed for the rest", Listed(), true)
	check("part bought: the bar still says buy", ns.UI.windows.next.list[1].text:find("^Buy at auction house") ~= nil, true)
	ns.UI.Show("queue")
	local buyStep, mailStep
	for index, data in ipairs(ns.UI.windows.queue.list) do
		if data.kind == "header" and data.text:find("Buy at auction house", 1, true) then buyStep = index end
		if data.kind == "header" and data.text:find("Collect from your mailbox", 1, true) then mailStep = index end
	end
	check("collect only after buying", buyStep < mailStep, true)
	ns.UI.Hide()

	-- A single item (not a commodity), bought out from a search's results.
	C_AuctionHouse.GetNumItemSearchResults = function() return #itemResults end
	C_AuctionHouse.GetItemSearchResultInfo = function(_, index) return itemResults[index] end
	itemResults = { { auctionID = 77, quantity = 1, buyoutAmount = 500 } }
	Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = itemID })
	C_AuctionHouse.PlaceBid(77, 400)
	Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	RunTimers()
	check("a bid below buyout isn't a purchase", ns.plan.buy[itemID], 1)
	C_AuctionHouse.PlaceBid(77, 500)
	Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
	RunTimers()
	check("bought out: nothing left to buy", ns.plan.buy[itemID], nil)
	check("leaves the shopping list", Listed(), false)
	check("queue says collect it", ns.plan.mail[itemID], needed)
	ns.UI.Show("queue")
	local collect = false
	for _, data in ipairs(ns.UI.windows.queue.list) do
		if data.kind == "header" and data.text:find("Collect from your mailbox", 1, true) then collect = true end
	end
	check("mailbox step listed", collect, true)
	ns.UI.Hide()
	check("all bought: the bar says collect, before the vendor", ns.UI.windows.next.list[1].text, "Collect from your mailbox")

	-- At the mailbox: what's there is counted once, and taking it out moves it to the bags.
	inbox = { { subject = "Auction won: " .. names[itemID], money = 0, daysLeft = 30, itemID = itemID, count = needed } }
	Fire("MAIL_SHOW")
	RunTimers()
	check("mailbox seen: not counted twice", ns.plan.mail[itemID], needed)
	check("purchases folded into the mailbox", #ns.db.purchases[ns.CharKey()], 0)
	inbox = {}
	Fire("MAIL_INBOX_UPDATE")
	RunTimers()
	check("taken out: nothing in the mail", ns.plan.mail[itemID], nil)
	check("taken out: to buy again until the bags show it", ns.plan.buy[itemID], needed)
	itemResults = {}
	ns.Queue.Clear()
	RunTimers()
end

-- Plurals.
check("plural of one", ns.Plural(1, "entry", "entries"), "1 entry")
check("plural of many", ns.Plural(3, "entry", "entries"), "3 entries")
check("plural of none", ns.Plural(0, "item", "items"), "0 items")

-- Money on its way: the game's "buyer found" chat line starts the hour before a sale's money is mailed.
do
	local realTime, realPrint = time, ns.Print
	local base = realTime()
	local said = {}
	ns.Print = function(text) table.insert(said, text) end
	time = function() return base end
	ns.db.sales.incoming = {}
	ns.db.sales.lots = {
		{ itemID = 1, name = "Test Sword", qty = 1, at = base - 600, dur = 86400, char = me, price = 10000 },
		{ itemID = 9, name = "Test Ore", qty = 20, at = base - 600, dur = 86400, char = me, price = 200, commodity = true },
	}
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Test Sword", 123)
	local list, onItsWay, waiting, nextDue, rough = ns.Sales.Incoming()
	check("sold message noted", #list, 1)
	check("amount is the posted price after the cut", list[1].amount, 9500)
	check("posted item price is exact", rough, false)
	check("on its way", onItsWay, 9500)
	check("nothing waiting yet", waiting, 0)
	check("due in an hour", nextDue, base + 3600)
	check("sale said in chat", (said[1] or ""):find("Sold: Test Sword", 1, true) ~= nil, true)
	check("the post is left for the mail to match", #ns.db.sales.lots, 2)
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 5, "Test Sword")
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 3, "Test Sword")
	check("expired and outbid notices ignored", #ns.Sales.Incoming(), 1)

	-- Stackable goods: the message doesn't say how many sold, so one unit, marked as an estimate.
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "|cffffffff|Hitem:9::::::::|h[Test Ore]|h|r")
	list, onItsWay, _, _, rough = ns.Sales.Incoming()
	check("commodity counted as one unit", list[2].amount, 190)
	check("commodity amount is an estimate", rough, true)
	check("both on their way", onItsWay, 9690)

	check("wait under an hour", ns.Sales.WaitText(42 * 60), "42 min")
	check("wait rounds up", ns.Sales.WaitText(61), "2 min")
	check("wait over an hour", ns.Sales.WaitText(65 * 60), "1 h 05 min")

	-- The Sales tab lists them above the sold items.
	ns.UI.Show("sales")
	check("incoming section first", ns.UI.windows.sales.list[1].columns, "incoming")
	check("incoming row", ns.UI.windows.sales.list[2].kind, "incoming")
	ns.UI.Hide()

	-- An hour on: waiting in the mailbox, announced once.
	said = {}
	time = function() return base + 3700 end
	RunTimers()
	_, onItsWay, waiting, nextDue = ns.Sales.Incoming()
	check("nothing on its way after the hour", onItsWay, 0)
	check("waiting in the mailbox", waiting, 9690)
	check("no next arrival", nextDue, nil)
	local announced = 0
	for _, text in ipairs(said) do if text:find("waiting in the mailbox", 1, true) then announced = announced + 1 end end
	check("arrival announced once", announced, 1)

	-- Opening the mailbox collects them.
	Fire("MAIL_SHOW")
	check("collected at the mailbox", #ns.Sales.Incoming(), 0)

	-- One still on its way stays through a mailbox visit.
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Test Sword", 123)
	Fire("MAIL_SHOW")
	check("not yet due: kept", #ns.Sales.Incoming(), 1)

	-- A busy hour of sales: money arriving sale after sale is said once, until the mailbox is opened.
	ns.db.sales.incoming = {}
	said = {}
	local function Announced()
		local n = 0
		for _, text in ipairs(said) do if text:find("waiting in the mailbox", 1, true) then n = n + 1 end end
		return n
	end
	local start = base + 4000
	for step = 0, 2 do
		time = function() return start + step * 60 end
		Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Test Sword", 200 + step)
	end
	for step = 0, 2 do
		time = function() return start + 3600 + step * 60 + 1 end
		RunTimers()
	end
	check("arrivals one after another said once", Announced(), 1)
	local first
	for _, text in ipairs(said) do if text:find("waiting in the mailbox", 1, true) then first = text end end
	check("first arrival names what's still coming", (first or ""):find("more on its way", 1, true) ~= nil, true)
	Fire("MAIL_SHOW")
	time = function() return start + 7300 end
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Test Sword", 300)
	time = function() return start + 7300 + 3601 end
	RunTimers()
	check("after a mailbox visit the next arrival is said again", Announced(), 2)

	ns.db.sales.incoming = {}
	ns.db.sales.lots = {}
	time, ns.Print = realTime, realPrint
end

-- Sales profit: what was paid for materials follows them through the craft to the sale.
do
	ns.db.sales.items, ns.db.sales.lots, ns.db.costs = {}, {}, {}
	Fire("COMMODITY_PRICE_UPDATED", 100, 1000)
	C_AuctionHouse.ConfirmCommoditiesPurchase(901, 10)
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	check("purchase recorded at the price paid", ns.db.costs[901].c, 1000)
	check("purchase units recorded", ns.db.costs[901].q, 10)

	-- 4 bought units and 2 that were already held make one item: the held ones count at the market price (50 each).
	-- Counted as free, a bag made from one bought bolt and two held ones showed far too much profit.
	local oldMarket = { prices[901], prices[903] }
	prices[901], prices[903] = 100, 50
	ns.db.recipes[9001] = { n = "Crafted Thing", o = 902, qmin = 1, qmax = 1, r = { { 4, 901 }, { 2, 903 } } }
	ns.db.chars[me].recipes[9001] = true
	ns.Sales.ForgetCraftInfo()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 9001)
	check("craft takes its materials' cost", ns.db.costs[901].c, 600)
	check("craft result carries the cost, held materials at market", ns.db.costs[902].c, 500)

	local now = os.time()
	ns.Sales.Record("sold", "Crafted Thing", 1, 950, now, me, 902)
	local thing = ns.Sales.Item("crafted thing")
	local profit, rough, sold, _, gold = ns.Sales.Profit(thing, 1)
	check("profit is the sale less what its materials cost", profit, 450)
	check("known cost isn't an estimate", rough, false)
	check("sale still counted", sold == 1 and gold == 950, true)
	check("sold unit leaves the cost record", ns.db.costs[902], nil)

	-- Something that isn't crafted: listed only when everything is asked for, and all profit when gathered.
	ns.Sales.Record("sold", "Spare Ore", 1, 100, now, me, 903)
	check("only crafts by default", #ns.Sales.AllItems(false), 1)
	check("everything on request", #ns.Sales.AllItems(true), 2)
	check("totals: crafts only", select(4, ns.Sales.Totals(1, false)), 450)
	check("totals: everything", select(4, ns.Sales.Totals(1, true)), 550)

	-- Money on its way counts before its mail is read, at the cost on record.
	ns.Sales.AddCost(902, 1, 400)
	table.insert(ns.db.sales.incoming, { name = "Crafted Thing", itemID = 902, char = me, at = now, due = now + 3600, amount = 950 })
	table.insert(ns.db.sales.incoming, { name = "New Thing", itemID = 905, char = me, at = now, due = now + 3600, amount = 70 })
	check("money on its way is in the item's profit", (ns.Sales.Profit(thing, 1)), 1000)
	check("money on its way is in the totals", select(4, ns.Sales.Totals(1, true)), 1170)
	check("sale on its way doesn't use up the cost", ns.db.costs[902].c, 400)
	ns.db.sales.incoming = {}
	ns.db.costs[902] = nil

	-- Results from before profit was counted stay out of it, and out of the list.
	ns.Sales.Record("sold", "Old Thing", 3, 900, now, me, 904)
	for _, day in pairs(ns.Sales.Item("old thing").days) do day.x = true end
	check("earlier sales not listed", #ns.Sales.AllItems(true), 2)
	check("earlier sales not in the profit", select(4, ns.Sales.Totals(nil, true)), 550)
	check("earlier sales kept for the history", ns.Sales.Item("old thing").sold, 3)
	ns.db.sales.items["old thing"] = nil

	-- A crafted item sold with no cost on record (made before costs were kept) counts at today's cost to craft
	-- one (4 x 100 + 2 x 50), marked as an estimate.
	ns.Sales.Record("sold", "Crafted Thing", 1, 950, now, me, 902)
	local noCost, noCostRough = ns.Sales.Profit(thing, 1)
	check("no cost on record: today's craft cost", noCost, 450 + 950 - 500)
	check("no cost on record: an estimate", noCostRough, true)
	-- That cost is fixed at the sale: a later price change doesn't move the profit.
	local before901 = prices[901]
	prices[901] = 999
	ns.Sales.ForgetCraftInfo()
	check("no cost on record: fixed at the sale", (ns.Sales.Profit(thing, 1)), noCost)
	prices[901] = before901
	ns.Sales.ForgetCraftInfo()

	ns.UI.Show("sales")
	local window = ns.UI.windows.sales
	check("sales list: header and the crafted item", #window.list, 2)

	-- Reset profit: asks first, then everything so far leaves the profit but stays in the history, and a sale
	-- later the same day counts again.
	table.insert(ns.db.sales.incoming, { name = "Crafted Thing", itemID = 902, char = me, at = now, due = now + 3600, amount = 950 })
	ns_popup = nil
	window.reset.scripts.OnClick(window.reset)
	check("reset profit asks first", ns_popup, "CFF_RESET_PROFIT")
	check("nothing reset before confirming", select(4, ns.Sales.Totals(nil, true)) ~= 0, true)
	StaticPopupDialogs.CFF_RESET_PROFIT.OnAccept()
	check("profit reset to zero", select(4, ns.Sales.Totals(nil, true)), 0)
	check("reset: list emptied", #ns.Sales.AllItems(true), 0)
	check("reset: history kept", ns.Sales.Counts(thing), 2)
	ns.db.sales.incoming = {}
	ns.Sales.AddCost(902, 1, 400)
	ns.Sales.Record("sold", "Crafted Thing", 1, 950, now, me, 902)
	check("a sale after the reset counts", (ns.Sales.Profit(thing, 1)), 550)
	StaticPopupDialogs.CFF_RESET_PROFIT.OnAccept()
	check("second reset the same day", (ns.Sales.Profit(thing, 1)), 0)
	check("second reset: history kept", ns.Sales.Counts(thing), 3)
	check("second reset: today's history kept", ns.Sales.Counts(thing, 1), 3)
	ns.Sales.Record("sold", "Crafted Thing", 1, 950, now, me, 902)
	ns.Sales.Record("sold", "Spare Ore", 1, 100, now, me, 903)
	window.everything.GetChecked = function() return true end
	window.everything.scripts.OnClick(window.everything)
	check("box ticked: everything listed", #window.list, 3)
	ns.db.ui.salesEverything = nil
	ns.UI.Hide()

	ns.db.recipes[9001], ns.db.chars[me].recipes[9001] = nil, nil
	prices[901], prices[903] = oldMarket[1], oldMarket[2]
	ns.db.sales.items, ns.db.costs = {}, {}
	ns.Sales.ForgetCraftInfo()
	RunTimers()
end

-- Minimap button: without the broker libraries it's the add-on's own button, under the name collectors look for.
do
	local mini = ns.MinimapButton
	check("own minimap button without the libraries", mini.button ~= nil, true)
	check("minimap button shown", mini.button:IsShown(), true)
	local x, y = mini.Offset(90, 80)
	check("minimap button at the top for 90 degrees", math.abs(x) < 0.001 and math.abs(y - 80) < 0.001, true)
	ns.UI.Hide()
	mini.button.scripts.OnClick(mini.button, "LeftButton")
	check("left-click opens the window", ns.UI.IsOpen(), true)
	mini.button.scripts.OnClick(mini.button, "LeftButton")
	check("left-click again closes it", ns.UI.IsOpen(), false)
	SlashCmdList.CFF("minimap")
	check("/cff minimap hides the button", mini.button:IsShown(), false)
	check("hidden is remembered", ns.db.ui.minimap.hide, true)
	SlashCmdList.CFF("minimap")
	check("/cff minimap shows it again", mini.button:IsShown(), true)
end

-- Options: the tab, the minimap button's right-click, and the game's own AddOns list all lead to the same controls.
do
	local mini = ns.MinimapButton
	ns.UI.Hide()
	mini.button.scripts.OnClick(mini.button, "RightButton")
	check("right-click opens the window", ns.UI.IsOpen(), true)
	check("on the Options tab", ns.db.ui.tab, "options")
	local pane = ns.UI.windows.options.frame
	local controls = ns.Options.Controls(pane)
	local function Tick(key, on)
		controls[key].GetChecked = function() return on end
		controls[key].scripts.OnClick(controls[key])
	end

	check("registered in the game's AddOns list", registeredCategory and registeredCategory.name,
		"Crafting and Farming Forever")
	local panel = ns.Options.panel
	panel.shown = false
	panel:Show()
	check("the game's page has its own controls", ns.Options.Controls(panel) ~= nil, true)
	check("which aren't the tab's", ns.Options.Controls(panel) ~= controls, true)

	-- Advertising off: no Ad box, no Advertise button, and the command says why.
	inCombat = false
	ns.Advertise.UpdateButtons()
	check("Ad box shown while advertising is on", ns.Advertise.box:IsShown(), true)
	Tick("adEnabled", false)
	check("advertising off is saved", ns.db.ui.adEnabled, false)
	check("Ad box gone", ns.Advertise.box:IsShown(), false)
	ns.UI.Show("profit")
	check("Advertise button gone", ns.UI.windows.profit.advertiseButton:IsShown(), false)
	chatBoxText = nil
	time = function() return os.time() + 100000 end
	ns.Advertise.Send(197)
	check("no ad while off", chatBoxText, nil)
	ns.UI.Show("options")
	Tick("adEnabled", true)
	check("Ad box back", ns.Advertise.box:IsShown(), true)

	-- Own advertising message.
	local box = controls.adText
	check("box shows the default message", box:GetText(), ns.Advertise.DEFAULT_TEXT)
	box:SetText("  WTS {profession} | cheap  ")
	box.scripts.OnEditFocusLost(box)
	check("own ad saved, cleaned", ns.db.ui.adText, "WTS {profession} cheap")
	ns.Advertise.Send(197)
	check("own ad used", chatBoxText:match("^/%d+ (.*)$"), "WTS |ctrade|Htrade:197|h[Tailoring]|h|r cheap")
	box.reset.scripts.OnClick(box.reset)
	check("Default puts the wording back", ns.db.ui.adText, nil)
	check("and shows it", box:GetText(), ns.Advertise.DEFAULT_TEXT)
	box:SetText("   ")
	box.scripts.OnEditFocusLost(box)
	check("an empty message is the default", ns.Advertise.Text(), ns.Advertise.DEFAULT_TEXT)
	check("and the box shows it", box:GetText(), ns.Advertise.DEFAULT_TEXT)
	check("long text is cut at a whole character", ns.CleanChatText("ab\195\169\195\169", 5), "ab\195\169")
	check("and not left ending in a space", ns.CleanChatText("abc def", 4), "abc")

	-- Where to post.
	controls.destinations.GUILD.scripts.OnClick(controls.destinations.GUILD)
	check("destination picked in Options", ns.Advertise.DestinationLabel(), "Guild")
	controls.destinations.TRADE.scripts.OnClick(controls.destinations.TRADE)

	-- Own quote message.
	ns.Queue.SetQuoteMargin(10)
	local quote = controls.quoteText
	quote:SetText("{count} {item} for {price}, {unknown} stays")
	quote.scripts.OnEditFocusLost(quote)
	check("own quote used", ns.Queue.QuoteText(20, 2), "2 link for 1s 54c, {unknown} stays")
	check("quote example shown", quote.example.text:find("20 [Healing Potion] for 5g 20s", 1, true) ~= nil, true)
	quote.reset.scripts.OnClick(quote.reset)
	check("default quote back", ns.Queue.QuoteText(20, 2), "link x2: 1s 54c")

	-- Next step bar off.
	ns.Queue.Add(20, 1)
	RunTimers()
	check("Next step bar shown with a queue", ns.UI.windows.next.frame:IsShown(), true)
	Tick("nextStep", false)
	check("Next step bar off", ns.UI.windows.next.frame:IsShown(), false)
	Tick("nextStep", true)
	check("Next step bar back", ns.UI.windows.next.frame:IsShown(), true)

	-- Minimap button and the scan question.
	Tick("minimap", false)
	check("minimap button hidden from Options", mini.button:IsShown(), false)
	Tick("minimap", true)
	check("and shown again", mini.button:IsShown(), true)
	Tick("scanPopup", false)
	ns_popup = nil
	Fire("AUCTION_HOUSE_SHOW")
	RunTimers()
	check("no scan question when turned off", ns_popup, nil)
	Tick("scanPopup", true)
	time = os.time
end

-- Craftsman's Writs tab.
do
	local KNIFE_WRIT, KNIFE = 264027, 3848
	namesReady = true
	names[KNIFE_WRIT], names[KNIFE] = "Craftsman's Writ: Big Bronze Knife", "Big Bronze Knife"
	prices[KNIFE_WRIT], prices[KNIFE] = 5000, 300
	ns.Items.Retry()
	ns.db.ui.writTier, ns.db.ui.writAll = nil, nil
	ns.UI.Show("writs")
	RunTimers()
	local window = ns.UI.windows.writs
	-- At first only writs whose item a character can craft: none here. The box shows them all.
	check("only craftable writs at first", #window.list, 0)
	ns.db.ui.writAll = true
	ns.UI.Refresh("writs")
	check("every writ listed under a heading", #window.list, 151)
	check("writs heading sorts", window.list[1].columns, "writs")
	local function Knife()
		for _, data in ipairs(window.list) do
			if data.row and data.row.writ.id == KNIFE_WRIT then return data end
		end
	end
	-- Pouch 12s less a 50s writ and a 3s knife: 41s lost for 75 reputation.
	check("writ net", Knife().row.net, 1200 - 5300)
	check("writ gold per reputation", Knife().row.perRep, 4100 / 75)
	check("priced writ sorts first", window.list[2].row.writ.id, KNIFE_WRIT)
	check("item bought when nobody crafts it", Knife().row.kind, "ah")
	-- + queues the writ: the queue's own shopping list gets the writ and the knife, nothing else.
	ns.Queue.Clear()
	RunTimers()
	ns.Queue.Want("writ", KNIFE_WRIT, 1)
	RunTimers()
	check("queued writ is marked", Knife().selected, true)
	check("writ to buy", ns.plan.buy[KNIFE_WRIT], 1)
	check("writ's item to buy", ns.plan.buy[KNIFE], 1)
	check("queue list has the writ and its item", #lists[ns.LIST_NAME], 2)
	check("queue counts the writ", ns.Queue.Count(), 1)
	local queue = ns.UI.windows.queue
	ns.UI.Show("queue")
	RunTimers()
	local want
	for _, data in ipairs(queue.list) do if data.kind == "want" then want = data end end
	check("writ listed on the Queue tab", want and want.entry.id, KNIFE_WRIT)
	check("writ row costs the writ and the item", want and want.cost, 5300)
	-- Writs aren't a step (#23): their own unnumbered section at the very end, left out of the Next step bar.
	local writHeader, lastHeader
	for _, data in ipairs(queue.list) do
		if data.kind == "header" then
			lastHeader = data
			if data.handIn then writHeader = data end
		end
	end
	check("writs under their own section", writHeader ~= nil, true)
	check("writ section is last", lastHeader == writHeader, true)
	check("writ section unnumbered", writHeader and writHeader.text:find("^%d"), nil)
	local bar = ns.UI.windows.next
	check("bar up while the writ is still to buy", bar ~= nil and bar.frame:IsShown(), true)
	for _, data in ipairs(bar and bar.list or {}) do
		if data.kind == "header" then check("bar never shows the writ section", data.text:find("Writs:", 1, true), nil) end
	end
	-- Bought and made: only the hand-in is left, so the bar goes away; the writ stays queued.
	local itemCount = C_Item.GetItemCount
	C_Item.GetItemCount = function(id) return (id == KNIFE_WRIT or id == KNIFE) and 1 or 0 end
	ns.RequestPlan()
	RunTimers()
	check("held writ: nothing to buy", ns.plan.buy[KNIFE_WRIT], nil)
	check("held writ: still queued", ns.Queue.Count(), 1)
	check("held writ: no Next step bar", bar.frame:IsShown(), false)
	C_Item.GetItemCount = itemCount
	-- Handing the writ in takes it off the queue.
	Fire("QUEST_TURNED_IN", KNIFE_WRIT - 169800)
	RunTimers()
	check("handed-in writ leaves the queue", ns.Queue.Count(), 0)
	check("nothing left to buy", next(ns.plan.buy), nil)
	ns.UI.Show("writs")
	RunTimers()
	-- One level only.
	ns.db.ui.writTier = 3
	ns.UI.Refresh("writs")
	check("artisan writs only", #window.list, 46)
	ns.db.ui.writTier = nil
	ns.UI.SortList("writs", "name")
	check("sorted by name", ns.db.ui.writSort, "name")
	-- By hand-in zone: a header per zone, each zone's writs together under it, the zone with a priced writ to buy
	-- first (the knife writ's), unknown zone last.
	ns.UI.SortList("writs", "zone")
	local seen, together, current, headers, firstZone, lastZone = {}, true, nil, 0, nil, nil
	for index = 2, #window.list do
		local data = window.list[index]
		if data.kind == "writZone" then
			headers = headers + 1
			current = data.group.zone
			if seen[current] then together = false end
			seen[current] = true
			firstZone = firstZone or data.group
			lastZone = data.group
		elseif (data.row.writ.zone or ns.Writs.NO_ZONE) ~= current then
			together = false
		end
	end
	check("writs grouped by zone", together, true)
	check("zone headers", headers > 1, true)
	check("zone not known last", lastZone.zone, ns.Writs.NO_ZONE)
	check("zone with a priced writ first", firstZone.rows[1].writ.id, KNIFE_WRIT)
	check("zone counts its priced writ", #firstZone.writs, 1)
	local knifeZone = firstZone.zone
	local before = ns.Queue.Count()
	window.rows[2].plus.scripts.OnClick(window.rows[2].plus, "LeftButton")
	RunTimers()
	check("zone + queues its writs", ns.Queue.Count(), before + 1)
	check("queued writ no longer counted", #window.list[2].group.writs, 0)
	local function ZoneRow(zone) -- queuing sorts the zone further down: scroll to its row
		for index, data in ipairs(window.list) do
			if data.kind == "writZone" and data.group.zone == zone then
				window.offset = index - 1
				ns.UI.Refresh("writs")
				return window.rows[index - window.offset]
			end
		end
	end
	check("zone - shown once a writ is queued", ZoneRow(knifeZone).minus:IsShown() and true, true)
	ZoneRow(knifeZone).minus.scripts.OnClick(ZoneRow(knifeZone).minus)
	RunTimers()
	check("zone - takes its writs off", ns.Queue.WantedCount("writ", KNIFE_WRIT), 0)
	check("zone - hidden with nothing queued", ZoneRow(knifeZone).minus:IsShown() and true, false)
	window.offset = 0
	ns.Queue.Clear()
	RunTimers()
	check("zone heading shown", window.rows[1].sortHeadings.zone:IsShown() and true, true)
	ns.UI.SortList("writs", "zone")
	check("zone sort reverses", select(2, ns.UI.ListSort("writs")), false)
	ns.UI.SortList("writs", "name") -- plain writ rows from here on
	-- Zone filter: only the knife writ's zone, the menu counts each zone, All zones brings them back.
	ns.db.ui.writAll = true
	ns.UI.Refresh("writs")
	local everyWrit = #window.list
	window.zoneButton.scripts.OnClick(window.zoneButton)
	check("zone menu opens", window.zoneMenu:IsShown() and true, true)
	local knifeOption, unknownOption
	for _, option in ipairs(window.zoneMenu.options) do
		if option.zone == knifeZone then knifeOption = option end
		if option.zone == ns.Writs.NO_ZONE then unknownOption = option end
	end
	check("zone menu lists the knife's zone", knifeOption ~= nil, true)
	check("zone menu lists unknown zones last", window.zoneMenu.options[#window.zoneMenu.options], unknownOption)
	knifeOption.scripts.OnClick(knifeOption)
	check("zone menu stays open for more picks", window.zoneMenu:IsShown() and true or false, true)
	check("zone saved", ns.db.ui.writZones and ns.db.ui.writZones[knifeZone], true)
	check("picked zone ticked", knifeOption.check:IsShown() and true or false, true)
	local onlyZone, knifeShown = true, false
	for index = 2, #window.list do
		local writ = window.list[index].row.writ
		if writ.zone ~= knifeZone then onlyZone = false end
		if writ.id == KNIFE_WRIT then knifeShown = true end
	end
	check("zone filter keeps only that zone", onlyZone, true)
	check("zone filter keeps the knife writ", knifeShown, true)
	check("zone filter shows fewer", #window.list < everyWrit, true)
	check("zone count matches the list", window.zoneCounts[knifeZone], #window.list - 1)
	check("zone button names it", window.zoneButton:GetText(), "Zone: " .. knifeZone)
	-- A second zone adds its writs.
	local oneZone = #window.list - 1
	unknownOption.scripts.OnClick(unknownOption)
	local twoOnly = true
	for index = 2, #window.list do
		local zone = window.list[index].row.writ.zone
		if zone and zone ~= knifeZone then twoOnly = false end
	end
	check("two zones: both and nothing else", twoOnly, true)
	check("two zones: more writs", #window.list - 1, oneZone + window.zoneCounts[ns.Writs.NO_ZONE])
	check("two zones: button counts them", window.zoneButton:GetText(), "Zones: 2 picked")
	-- Clicking a ticked zone unticks it.
	knifeOption.scripts.OnClick(knifeOption)
	local allUnknown = #window.list > 1
	for index = 2, #window.list do
		if window.list[index].row.writ.zone then allUnknown = false end
	end
	check("unticked zone leaves the other", allUnknown, true)
	window.zoneMenu.options[1].scripts.OnClick(window.zoneMenu.options[1])
	check("all zones again", #window.list, everyWrit)
	check("zones cleared", ns.db.ui.writZones, nil)
	check("zone button unfiltered", window.zoneButton:GetText(), "Filter by zone")
	ns.db.ui.writSort, ns.db.ui.writSortAsc, ns.db.ui.writAll = nil, nil, nil
	prices[KNIFE_WRIT], prices[KNIFE] = nil, nil
	ns.UI.Show("profit")
end

-- Waylaid Crates tab.
do
	local ORE_CRATE, SILVER, IRON = 248687, 2775, 2772
	local INGOT_CRATE, SILVER_BAR, IRON_BAR = 248706, 2842, 3575
	namesReady = true
	names[ORE_CRATE], names[SILVER], names[IRON] = "Waylaid Crate: Journeyman Ore", "Silver Ore", "Iron Ore"
	names[INGOT_CRATE], names[SILVER_BAR], names[IRON_BAR] = "Waylaid Crate: Journeyman Ingots", "Silver Bar", "Iron Bar"
	-- Ore crate 20s: 10 silver ore 50s or 20 iron ore 30s. Ingot crate 1g: 10 silver bars 60s (20 iron bars 2g).
	prices[ORE_CRATE], prices[SILVER], prices[IRON] = 2000, 500, 150
	prices[INGOT_CRATE], prices[SILVER_BAR], prices[IRON_BAR] = 10000, 600, 1000
	ns.Items.Retry()
	ns.db.ui.crateTier = nil
	ns.UI.Show("crates")
	RunTimers()
	local window = ns.UI.windows.crates
	check("every crate listed under a heading", #window.list, 31)
	check("crates heading sorts", window.list[1].columns, "crates")
	check("crate from its fill spell", ns.Crates.BySpell(ORE_CRATE + 998744).id, ORE_CRATE)
	check("other spells aren't crates", ns.Crates.BySpell(ORE_CRATE), nil)
	check("crate name without its prefix", ns.Crates.Name(ns.Crates.ByID(ORE_CRATE)), "Journeyman Ore")
	check("name without a prefix kept whole", ns.Items.ShortName(IRON), "Iron Ore")
	local function Row(crateID)
		for _, data in ipairs(window.list) do
			if data.row and data.row.crate.id == crateID then return data end
		end
	end
	-- Ore: 20s + 30s - 5s coin = 45s for 10 Favor. Ingots: 1g + 60s - 10s coin = 1g50s for 20 Favor.
	check("cheapest bundle fills the crate", Row(ORE_CRATE).row.best.item, IRON)
	check("gold per Favor", Row(ORE_CRATE).row.perToken, 450)
	check("crafted-material crates pay double", Row(INGOT_CRATE).row.tokens, 20)
	check("ingot crate per Favor", Row(INGOT_CRATE).row.perToken, 750)
	check("cheapest Favor sorts first", window.list[2].row.crate.id, ORE_CRATE)
	check("cheapest Favor is marked", window.list[2].row.cheapest, true)
	check("only one best buy", Row(INGOT_CRATE).row.cheapest, nil)
	check("best buy in the footer", window.hint.text:find("Journeyman Ore", 1, true) ~= nil, true)
	-- + queues crates: the queue's shopping list gets the crates and their cheapest bundle.
	ns.Queue.Clear()
	RunTimers()
	ns.Queue.Want("crate", ORE_CRATE, 1)
	ns.Queue.Want("crate", ORE_CRATE, 1)
	RunTimers()
	check("queued crates counted on the row", Row(ORE_CRATE).row.queued, 2)
	ns.Queue.Unwant("crate", ORE_CRATE, 5)
	check("- never goes below none", ns.Queue.WantedCount("crate", ORE_CRATE), 0)
	ns.Queue.Unwant("crate", ORE_CRATE, 1)
	check("- on a crate not queued does nothing", ns.Queue.Count(), 0)
	ns.Queue.Want("crate", ORE_CRATE, 2)
	RunTimers()
	check("crates to buy", ns.plan.buy[ORE_CRATE], 2)
	check("cheapest bundle to buy, for both", ns.plan.buy[IRON], 40)
	check("the dearer bundle isn't bought", ns.plan.buy[SILVER], nil)
	check("queue list has the crate and its fill", #lists[ns.LIST_NAME], 2)
	-- Filling one casts its Stock Crate spell: one comes off.
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, ORE_CRATE + 998744)
	RunTimers()
	check("a filled crate comes off the queue", ns.Queue.WantedCount("crate", ORE_CRATE), 1)
	ns.Queue.Clear()
	RunTimers()
	check("clear removes queued crates", ns.Queue.Count(), 0)
	-- An entry for something this version doesn't know is dropped, not left blocking an empty queue.
	table.insert(ns.db.wanted, { kind = "crate", id = 1, qty = 1 })
	ns.RequestPlan()
	RunTimers()
	check("unknown queued crate is dropped", ns.Queue.Count(), 0)
	-- Favor goal: 40 favor is four ore crates (45s each) before two ingot crates (1g50s each).
	ns.db.ui.favorTarget = 40
	ns.UI.Refresh("crates")
	do -- every crate and material priced: the solver stays quick enough for a keystroke
		local saved = {}
		for _, crate in ipairs(ns.Crates.list) do
			for _, id in ipairs({ crate.id, crate.bundles[1].item, crate.bundles[#crate.bundles].item }) do
				if saved[id] == nil then saved[id] = prices[id] or false end
				prices[id] = prices[id] or (id % 97 + 1) * 37
			end
		end
		local started = os.clock()
		ns.Crates.FavorMix(1000)
		check("favor mix quick for 1000 favor, every crate priced", os.clock() - started < 0.25, true)
		for id, price in pairs(saved) do prices[id] = price or nil end
	end
	check("favor preview in the footer", window.hint.text:find("40 favor", 1, true) ~= nil, true)
	check("favor preview mix", window.favorMix.crates[1].crate.id .. "x" .. window.favorMix.crates[1].count, ORE_CRATE .. "x4")
	ns.Queue.Want("crate", ORE_CRATE, 1) -- one queued by hand stays through the goal
	local mix = ns.Queue.SetFavorGoal(40)
	RunTimers()
	check("favor goal queued", ns.db.favorGoal and ns.db.favorGoal.target, 40)
	check("favor goal crates on top of the hand-queued one", ns.Queue.WantedCount("crate", ORE_CRATE), 5)
	check("favor goal favor reached", mix.favor, 40)
	local items = ns.Crates.FavorItems()
	check("favor check searches the crates", items[ORE_CRATE] and items[INGOT_CRATE], true)
	check("favor check searches bought fills", items[IRON], true)
	-- The listings show one ore crate at 20s, the rest at 2g: the goal turns into two ingot crates.
	ns.db.depth[ORE_CRATE] = { { 2000, 1 }, { 20000, 10 }, at = time() }
	check("favor repicked at the listings", ns.Queue.RepickFavor(), true)
	RunTimers()
	check("favor repick: hand-queued crate kept", ns.Queue.WantedCount("crate", ORE_CRATE), 1)
	check("favor repick: ingot crates", ns.Queue.WantedCount("crate", INGOT_CRATE), 2)
	check("favor repick: nothing more to change", ns.Queue.RepickFavor(), false)
	-- A goal crate the mix no longer has is a change too.
	table.insert(ns.db.wanted, { kind = "crate", id = 248682, qty = 1, favor = 1 })
	check("favor repick: leftover goal crate", ns.Queue.RepickFavor(), true)
	check("favor repick: leftover goal crate dropped", ns.Queue.WantedCount("crate", 248682), 0)
	RunTimers()
	-- Filling one takes its favor off the goal.
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, INGOT_CRATE + 998744)
	RunTimers()
	check("filled crate takes its favor off the goal", ns.db.favorGoal.target, 20)
	ns.Queue.ClearFavorGoal()
	RunTimers()
	check("clear goal: hand-queued crate kept", ns.Queue.Count(), 1)
	check("clear goal: goal gone", ns.db.favorGoal, nil)
	-- Taking the goal's crates off by hand drops the goal.
	ns.Queue.SetFavorGoal(40)
	ns.Queue.Clear()
	ns.Queue.FavorGoalLeft()
	check("goal gone with its crates", ns.db.favorGoal, nil)
	ns.db.depth[ORE_CRATE], ns.db.ui.favorTarget = nil, nil
	RunTimers()
	ns.db.ui.crateTier = 2
	ns.UI.Refresh("crates")
	check("journeyman crates only", #window.list, 8)
	ns.db.ui.crateTier = nil
	ns.UI.SortList("crates", "cost")
	check("sorted by Favor, most first", window.list[2].row.tokens, 40)
	ns.db.ui.crateSort, ns.db.ui.crateSortAsc = nil, nil
	for _, id in ipairs({ ORE_CRATE, SILVER, IRON, INGOT_CRATE, SILVER_BAR, IRON_BAR }) do prices[id] = nil end
	ns.UI.Show("profit")
end


-- Bag space: a queue whose materials don't fit is crafted in runs. One-unit stacks here, 4 slots, 1 kept free.
do
	local container, itemCount = C_Container, C_Item.GetItemCount
	C_Container = {
		GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
		GetContainerItemInfo = function() return nil end,
	}
	C_Item.GetItemCount = function() return 0 end
	ns.Queue.Clear()
	ns.Queue.Add(10, 5)
	RunTimers()
	check("bag run: buys for one craft", ns.plan.buy[1], 2)
	check("bag run: run planned", ns.plan.run and ns.plan.run.crafts, 1)
	check("bag run: saved for this character", ns.db.bagRuns[ns.CharKey()] ~= nil, true)
	ns.UI.Show("queue")
	local titles = {}
	for _, data in ipairs(ns.UI.windows.queue.list) do
		if data.kind == "header" then table.insert(titles, data.text) end
		if data.kind == "queue" then check("bag run: row carries the run", data.run, 1) end
	end
	ns.UI.Hide()
	local all = table.concat(titles, "|")
	check("bag run: run step", all:find("Craft this run: 1 craft", 1, true) ~= nil, true)
	check("bag run: no later step when one entry is split", all:find("Next run", 1, true), nil)
	ns.SetOption("bagSpace", false)
	ns.RequestPlan()
	RunTimers()
	check("bag run: off buys everything", ns.plan.buy[1], 10)
	check("bag run: off, no run", ns.plan.run, nil)
	ns.db.ui.bagSpace = nil
	ns.Queue.Clear()
	RunTimers()
	check("bag run: empty queue, nothing kept", ns.db.bagRuns[ns.CharKey()], nil)
	C_Container, C_Item.GetItemCount = container, itemCount
end


-- The bank step done from the Next step bar: put away, then take out, through the cursor, one stack at a time.
do
	local container, itemCount, bagIndex = C_Container, C_Item.GetItemCount, Enum.BagIndex
	local TAB = 12
	Enum.BagIndex = { CharacterBankTab_1 = TAB }
	local slots = { [0] = { { itemID = 4, stackCount = 1 }, false, false }, [TAB] = { { itemID = 1, stackCount = 5 }, false, false, false } }
	local cursor
	C_Container = {
		GetContainerNumSlots = function(bag) return slots[bag] and #slots[bag] or 0 end,
		GetContainerItemInfo = function(bag, slot)
			local item = slots[bag] and slots[bag][slot]
			return item or nil
		end,
		PickupContainerItem = function(bag, slot)
			if not cursor then
				cursor = { bag = bag, slot = slot, count = slots[bag][slot].stackCount }
				return
			end
			local from = slots[cursor.bag][cursor.slot]
			local target = slots[bag][slot]
			if target then
				target.stackCount = target.stackCount + cursor.count
			else
				slots[bag][slot] = { itemID = from.itemID, stackCount = cursor.count }
			end
			from.stackCount = from.stackCount - cursor.count
			if from.stackCount <= 0 then slots[cursor.bag][cursor.slot] = false end
			cursor = nil
		end,
		SplitContainerItem = function(bag, slot, count) cursor = { bag = bag, slot = slot, count = count } end,
	}
	GetCursorInfo = function() return cursor and "item" or nil end
	ClearCursor = function() cursor = nil end
	C_Item.GetItemCount = function(id, includeBank) return id == 1 and includeBank and 5 or 0 end
	ns.Queue.Clear()
	ns.Queue.Add(10, 1)
	RunTimers()
	check("bank step: plan takes from the bank", ns.plan.bank[1], 2)
	local bar = ns.UI.windows.next
	check("bank step: bar is on the bank step", bar.banking, true)
	local ok, why = ns.Bank.Run()
	check("bank step: needs the bank open", ok, false)
	check("bank step: says why", why, "Open your bank first.")
	Fire("BANKFRAME_OPENED")
	check("bank step: button closed bank", bar.bankButton.text ~= nil, true)
	ns.UI.Refresh("next")
	-- Three slots (stacks of one here): two cloth and the bolt made from them need the shirt's slot.
	check("bank step: button offers the move", bar.bankButton.text, "Bank it: put away 1, take out 2")
	check("bank step: starts", (ns.Bank.Run()), true)
	for _ = 1, 5 do RunTimers() end
	check("bank step: shirt put away", slots[TAB][2] and slots[TAB][2].itemID, 4)
	check("bank step: two taken out, split off the stack", slots[0][1] and slots[0][1].stackCount, 2)
	check("bank step: rest stays in the bank", slots[TAB][1].stackCount, 3)
	check("bank step: job finished", ns.Bank.Progress(), nil)
	check("bank step: cursor empty", cursor, nil)
	Fire("BANKFRAME_CLOSED")
	check("bank step: closed", ns.Bank.IsOpen(), false)
	ns.Queue.Clear()
	RunTimers()
	C_Container, C_Item.GetItemCount, Enum.BagIndex = container, itemCount, bagIndex
	GetCursorInfo, ClearCursor = nil, nil
end

-- Farm It knows the gathering professions of the character you're on (GitHub #9): read from the client, kept per
-- character, and a change replans.
do
	local lines = { 393, 186 } -- Skinning, Mining
	GetProfessions = function() return 1, 2 end
	GetProfessionInfo = function(index) return "p", nil, 1, 75, 0, 0, lines[index] end
	Fire("SKILL_LINES_CHANGED")
	RunTimers()
	check("gathering: skinning read", ns.Recipes.CanGather("skin"), true)
	check("gathering: mining read", ns.Recipes.CanGather("mine"), true)
	check("gathering: no herbalism", ns.Recipes.CanGather("herb"), false)
	check("gathering: Medium Leather is skinned", ns.Recipes.GatherKind(2319), "skin")
	lines = { 182 }
	GetProfessions = function() return 1 end
	Fire("SKILL_LINES_CHANGED")
	RunTimers()
	check("gathering: dropped skinning", ns.Recipes.CanGather("skin"), false)
	check("gathering: took herbalism", ns.Recipes.CanGather("herb"), true)
	GetProfessions, GetProfessionInfo = nil, nil
end

-- The vendor step done at a merchant: the Next step bar's button buys exactly what the plan gets from vendors, even
-- from a bundle (thread in fives), whatever step the bar is on.
do
	local itemCount, money = C_Item.GetItemCount, playerMoney
	local bought = 0
	-- Thread in fives for 50c; a currency item and something the queue doesn't need around it.
	local slots = {
		{ id = 7, info = { price = 100, stackCount = 1, numAvailable = -1, isPurchasable = true } },
		{ id = 3, info = { price = 50, stackCount = 5, numAvailable = -1, isPurchasable = true } },
		{ id = 1, info = { price = 0, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = true } },
	}
	local purchases = {}
	C_MerchantFrame = { GetItemInfo = function(index) return slots[index] and slots[index].info end }
	GetMerchantNumItems = function() return #slots end
	GetMerchantItemID = function(index) return slots[index] and slots[index].id end
	GetMerchantItemMaxStack = function() return 20 end
	BuyMerchantItem = function(index, amount)
		table.insert(purchases, { index = index, amount = amount })
		if slots[index].id == 3 then bought = bought + amount end
		playerMoney = playerMoney - amount * slots[index].info.price / slots[index].info.stackCount
	end
	C_Item.GetItemCount = function(id) return id == 1 and 3 or id == 3 and bought or 0 end
	playerMoney = 10
	ns.Queue.Clear()
	ns.Queue.Add(20, 2)
	RunTimers()
	check("vendor step: plan buys thread from a vendor", ns.plan.vendor[3], 2)
	local bar = ns.UI.windows.next
	check("vendor step: closed merchant, no button on another step", bar.vendoring, false)
	check("vendor step: needs a merchant", select(2, ns.Vendor.Run()), "Talk to a vendor first.")
	do -- a button's run says why it couldn't, and nothing when it could or has no reason
		local said, realPrint = {}, ns.Print
		ns.Print = function(text) said[#said + 1] = text end
		ns.SayWhyNot(ns.Vendor.Run())
		ns.SayWhyNot(true, "not this")
		ns.SayWhyNot(false)
		ns.Print = realPrint
		check("why not: said once", #said, 1)
		check("why not: the reason", said[1], "Talk to a vendor first.")
	end
	-- Walked away from the auction house and the mailbox earlier tests left open: only the merchant is here.
	Fire("AUCTION_HOUSE_CLOSED")
	Fire("MAIL_CLOSED")
	RunTimers()
	local firstStep = bar.list[1] and bar.list[1].text
	check("vendor step: another step comes first", firstStep ~= nil and not firstStep:find("^Buy from vendor"), true)
	Fire("MERCHANT_SHOW")
	check("vendor step: button at the merchant", bar.vendoring, true)
	check("vendor step: the bar jumps to the vendor step here", bar.list[1].text:find("^Buy from vendor") ~= nil, true)
	check("vendor step: says it's here", bar.here ~= nil and bar.here > 1, true)
	check("vendor step: exact units, not the bundle", bar.vendorButton.text, "Buy for your queue: 20c")
	check("vendor step: too poor", select(2, ns.Vendor.Run()), "Not enough gold: this costs 20c.")
	playerMoney = 1000
	local said = {}
	local realPrint = ns.Print
	ns.Print = function(text) table.insert(said, text) end
	check("vendor step: starts", (ns.Vendor.Run()), true)
	for _ = 1, 5 do RunTimers() end
	ns.Print = realPrint
	check("vendor step: one purchase", #purchases, 1)
	check("vendor step: the thread's slot", purchases[1] and purchases[1].index, 2)
	check("vendor step: two units", purchases[1] and purchases[1].amount, 2)
	check("vendor step: finished", ns.Vendor.Progress(), nil)
	check("vendor step: says what it bought", said[1], "Vendor: bought Coarse Thread x2 for 20c.")
	check("vendor step: plan has nothing left to buy here", ns.Vendor.Pending(), nil)
	check("vendor step: button gone once bought", bar.vendoring, false)
	check("vendor step: back to the first step once bought", bar.list[1].text, firstStep)
	check("vendor step: no longer jumped", bar.here, nil)
	-- Limited stock: what's there, and the rest named as short.
	bought = 0
	slots[2].info.numAvailable = 0
	ns.Vendor.Sync()
	check("vendor step: sold out here", ns.Vendor.Pending(), nil)
	slots[2].info.numAvailable = -1
	-- Walking away mid-job: what was bought still gets counted, after a moment.
	ns.RequestPlan()
	RunTimers()
	said = {}
	ns.Print = function(text) table.insert(said, text) end
	check("vendor step: buys again", (ns.Vendor.Run()), true)
	FireNow("MERCHANT_CLOSED")
	check("vendor step: closed", ns.Vendor.IsOpen(), false)
	check("vendor step: counts after closing, not at once", ns.Vendor.Progress() ~= nil, true)
	RunTimers()
	ns.Print = realPrint
	check("vendor step: counted the last purchase", said[1], "Vendor: bought Coarse Thread x2 for 20c.")
	check("vendor step: says why it stopped", said[2], "Vendor: stopped (the merchant closed).")
	ns.Queue.Clear()
	RunTimers()
	C_Item.GetItemCount, playerMoney = itemCount, money
	C_MerchantFrame, GetMerchantNumItems, GetMerchantItemID, GetMerchantItemMaxStack, BuyMerchantItem = nil, nil, nil, nil, nil
end

-- Listing depth: at the auction house the add-on reads every listing of what it has to buy, so buying many counts at
-- what they really cost, not all at the cheapest listing.
do
	local realSearch, realInfo, realCount = C_AuctionHouse.SendSearchQuery, C_Item.GetItemInfo, C_Item.GetItemCount
	local realReady = C_AuctionHouse.IsThrottledMessageSystemReady
	local sent, results, full, has, ready = {}, {}, true, true, true
	C_AuctionHouse.SendSearchQuery = function(key, sorts) table.insert(sent, { itemID = key.itemID, sort = sorts[1].sortOrder }) end
	C_AuctionHouse.GetNumCommoditySearchResults = function(id) return #(results[id] or {}) end
	C_AuctionHouse.GetCommoditySearchResultInfo = function(id, index) return results[id][index] end
	C_AuctionHouse.HasFullCommoditySearchResults = function() return full end
	C_AuctionHouse.HasSearchResults = function() return has end
	C_AuctionHouse.IsThrottledMessageSystemReady = function() return ready end
	C_Item.GetItemInfo = function(id) return names[id], "link", 1, 1, 1, "", "", 20, "", 1, 1, 1, 1, 2 end
	C_Item.GetItemCount = function() return 0 end
	-- One round of timers: the stub runs them at once whatever their delay, so a search's time-out would fire
	-- before it could be answered.
	local function Step()
		local batch = timers
		timers = {}
		for _, fn in ipairs(batch) do fn() end
	end
	-- The stub's clock moves a second each time it's read.
	local function Wait(seconds)
		for _ = 1, seconds do GetTime() end
	end
	local function QueueText(itemID)
		ns.UI.Show("queue")
		local text
		for _, row in ipairs(ns.UI.windows.queue.rows) do
			if row.data and row.data.kind == "item" and row.data.itemID == itemID then text = row.right.text end
		end
		ns.UI.Hide()
		return text
	end
	-- The lock lingers a moment after a check, as the plan is worked out again: these frames let it go.
	local function Linger()
		for _ = 1, 40 do ns.Lock.frame.scripts.OnUpdate(ns.Lock.frame, 0.1) end
	end
	local function BuyHeader()
		ns.UI.Show("queue")
		local text
		for _, data in ipairs(ns.UI.windows.queue.list) do
			if data.kind == "header" and data.text:find("Buy at auction house", 1, true) then text = data.text end
		end
		ns.UI.Hide()
		return text
	end
	local savedPrices = { prices[1], prices[2] }
	prices[1], prices[2] = 10, 100
	-- The bolts' own listings were read a moment ago (plenty at the scan price), so only the cloth is searched; the
	-- add-on reads both sides of a buy-or-craft choice.
	ns.db.depth = { [2] = { at = time(), { 100, 50 } } }
	ns.db.ui.depthCheck = true
	AuctionHouseFrame.shown = false
	Fire("AUCTION_HOUSE_CLOSED")
	ns.Queue.Clear()
	ns.Queue.Add(20, 2) -- 6 bolts, made from 12 cloth
	RunTimers()
	check("depth: both sides of the bolts' choice to read", ns.plan.compare[1] and ns.plan.compare[2], true)
	check("depth: cloth to buy", ns.plan.buy[1], 12)
	check("depth: cheapest listing for all, before the listings are read", ns.plan.cost, 12 * 10 + 2 * 10)
	check("depth: nothing sent away from the auction house", #sent, 0)

	-- At the auction house: one search for the cloth, as a commodity.
	AuctionHouseFrame.shown = true
	FireNow("AUCTION_HOUSE_SHOW")
	Step()
	Step()
	check("depth: search sent", #sent, 1)
	check("depth: search is for the cloth", sent[1] and sent[1].itemID, 1)
	check("depth: commodity sort", sent[1] and sent[1].sort, 0)
	check("depth: status while reading", (ns.Depth.Status()), 1)
	check("lock: screen locked while it reads", ns.Lock.Shown(), true)
	check("lock: window open on the Queue tab", ns.UI.IsOpen() and ns.db.ui.tab, "queue")
	check("lock: says the screen is locked", ns.Lock.frame.title.text,
		"Screen locked: checking what your queue's materials cost")
	check("lock: names the item being read", ns.Lock.frame.item.text, "Reading |T1:16:16:0:0|t Linen Cloth: 1 of 1")
	check("lock: notice on the window's footer", ns.Lock.frame.box.lastPoint[2] == ns.UI.main.frame
		and ns.Lock.frame.box.lastPoint[1], "BOTTOM")
	local marked = ns.Lock.Marked()
	local cloth = 0
	for _, row in ipairs(marked) do
		if row.data.kind == "item" and row.data.itemID == 1 then cloth = cloth + 1 end
	end
	-- On the Queue tab and on the Next step bar, nothing else.
	check("lock: the rows to buy it are outlined", #marked == cloth and cloth, 2)
	-- A list too short to show the cloth: it scrolls to it.
	local queueWindow = ns.UI.windows.queue
	local clothAt
	for index, data in ipairs(queueWindow.list) do
		if data.kind == "item" and data.itemID == 1 then clothAt = index end
	end
	local savedHeight = queueWindow.container.height
	queueWindow.container.height = 22 -- one row
	ns.UI.SetListOffset(queueWindow, clothAt > 1 and 0 or 1)
	check("lock: cloth out of view first", queueWindow.offset + 1 ~= clothAt, true)
	for _ = 1, 6 do ns.Lock.frame.scripts.OnUpdate(ns.Lock.frame, 0.05) end
	check("lock: list scrolled to the item being read", queueWindow.offset + 1, clothAt)
	queueWindow.container.height = savedHeight
	ns.UI.SetListOffset(queueWindow, 0)
	check("lock: shimmer while the search is out", ns.Lock.frame.note.text:find("Searching the auction house", 1, true)
		~= nil, true)
	check("depth: header says it's reading", BuyHeader():find("reading listings, 1 to go", 1, true) ~= nil, true)

	-- 2 at 10, plenty at 30, and 4 of your own at 9 that you can't buy.
	results[1] = {
		{ unitPrice = 30, quantity = 100 },
		{ unitPrice = 10, quantity = 2 },
		{ unitPrice = 9, quantity = 4, containsOwnerItem = true, numOwnerItems = 4 },
	}
	FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
	RunTimers()
	check("depth: no time-out after the answer", #sent, 1)
	check("depth: check finished", ns.Depth.Status(), nil)
	check("lock: stays a moment as the plan is worked out again", ns.Lock.Shown(), true)
	check("lock: says it's done reading", ns.Lock.frame.item.text,
		"Done reading. Working out the plan with the new prices...")
	-- The answer is counted on the cloth's row: 2 at 10c, then 10 at 30c, up to the 12 bought.
	local counted = ns.Lock.Marked()[1]
	check("lock: the read item stays outlined for its count", counted and counted.data.kind == "item"
		and counted.data.itemID, 1)
	check("lock: count starts on the row", ns.Lock.frame.note.text:find("Counting 0 / 12", 1, true) ~= nil, true)
	ns.Lock.frame.scripts.OnUpdate(ns.Lock.frame, 0.3)
	local counting = ns.Lock.frame.note.text
	check("lock: count runs across the listings", counting:find("Counting %d+ / 12, avg") ~= nil
		and not counting:find("Counting 0 /", 1, true), true)
	ns.Lock.frame.scripts.OnUpdate(ns.Lock.frame, 1)
	check("lock: count ends at the average paid", ns.Lock.frame.note.text:find("Counted 12 / 12, avg 27c", 1, true)
		~= nil, true)
	check("lock: pill says just the count", ns.Lock.PillText({ units = 87, needed = 192 }), "Counting 87 of 192")
	check("lock: cheaper than usual pulses green", ns.Lock.Verdict(27, 30), "cheap")
	check("lock: dearer than usual pulses red", ns.Lock.Verdict(31, 30), "dear")
	check("lock: no usual price, no verdict", ns.Lock.Verdict(31, nil), nil)
	check("lock: tally down the listings", select(1, ns.Lock.Tally(ns.db.depth[1], 12)), 320)
	check("lock: tally stops where the listings end", select(2, ns.Lock.Tally({ { 5, 3 } }, 12)), 3)
	-- An item read only to weigh buying against crafting counts to what the crafts use, not everything listed.
	check("lock: used by the queue's crafts", ns.Lock.Used({ crafts = { { recipeID = 7, count = 35 } } },
		{ [7] = { r = { { 2, 5, 6 }, { 1, 9 } } } }, 6), 70)
	check("lock: not used", ns.Lock.Used({ crafts = {} }, {}, 6), 0)
	Linger()
	check("lock: outline gone", #ns.Lock.Marked(), 0)
	check("lock: then gone", ns.Lock.Shown(), false)
	check("depth: cheapest tier stored", ns.db.depth[1][1][1] == 10 and ns.db.depth[1][1][2], 2)
	check("depth: next tier stored", ns.db.depth[1][2][1] == 30 and ns.db.depth[1][2][2], 100)
	check("depth: own auctions left out", #ns.db.depth[1], 2)
	check("depth: plan pays down the listings", ns.plan.paid[1], 2 * 10 + 10 * 30)
	check("depth: plan cost", ns.plan.cost, 320 + 2 * 10)
	check("plan check: after the listings check, the plan holds", ns.PlanCheck.result and ns.PlanCheck.result.count, 0)
	check("plan check: said on the window", ns.UI.lastVerdict, "Plan checked: still the cheapest way")
	check("depth: still cheaper than buying bolts", ns.plan.buy[2], nil)
	check("depth: row shows the average", QueueText(1), "x12, avg 27c, total 3s 20c")
	check("depth: header total", BuyHeader():find("3s 20c", 1, true) ~= nil, true)
	check("depth: header back to normal", BuyHeader():find("reading listings", 1, true), nil)
	ns.UI.Show("queue")
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "item" then row.scripts.OnEnter(row) end
	end
	ns.UI.Hide()

	-- The same answer again changes nothing; fresh listings aren't searched again.
	local version = ns.Depth.version
	FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
	RunTimers()
	check("depth: same listings, no change", ns.Depth.version, version)
	ns.Depth.CheckWanted()
	RunTimers()
	check("depth: fresh listings not searched again", #sent, 1)

	-- Buying two takes the cheap ones off until the next search.
	C_AuctionHouse.ConfirmCommoditiesPurchase(1, 2)
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	RunTimers()
	check("depth: bought units leave the listings", ns.db.depth[1][1][1], 30)
	check("depth: the rest costs the dearer price", ns.plan.paid[1], 10 * 30)
	-- Listings read again after the purchase was priced are already without it: nothing more comes off.
	FireNow("COMMODITY_PRICE_UPDATED", 30, 60)
	FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
	local left = ns.db.depth[1][1][2]
	C_AuctionHouse.ConfirmCommoditiesPurchase(1, 2)
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	RunTimers()
	check("depth: listings read after the purchase aren't cut twice", ns.db.depth[1][1][2], left)
	Wait(40)
	Fire("MAIL_SHOW") -- an empty inbox: the purchases are gone again
	RunTimers()

	-- You open the cloth yourself and it got dearer: read without asking, and now bolts are cheaper to buy, which
	-- is something new to look up. That waits while you're busy at the auction house.
	results[1] = { { unitPrice = 10, quantity = 2 }, { unitPrice = 80, quantity = 100 } }
	ns.db.depth[2] = nil -- the bolts' listings forgotten
	Wait(20) -- long after the add-on's own search of it
	FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
	Step()
	Step()
	check("depth: read from your own search", ns.db.depth[1][2][1], 80)
	check("lock: no lock for listings read from your search", ns.Lock.Shown(), false)
	-- One bolt is still made from the two cheap cloth (20 against 100); the other five are bought.
	check("depth: bolts bought instead", ns.plan.buy[2], 5)
	check("depth: only the cheap cloth bought", ns.plan.buy[1], 2)
	check("depth: holds off while you search", #sent, 1)
	RunTimers()
	check("depth: then looks up the bolts", sent[2] and sent[2].itemID, 2)

	-- An empty answer the client doesn't vouch for isn't believed: asked again, then given up, and the bolts stay
	-- at the scan price.
	has = false
	FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 2)
	RunTimers()
	check("depth: empty answer not stored", ns.db.depth[2], nil)
	check("depth: asked once more, then given up", #sent, 3)
	check("depth: given up", ns.Depth.Status(), nil)
	check("depth: scan price still used", ns.plan.cost, 5 * 100 + 2 * 10 + 2 * 10)
	ns.Depth.CheckWanted()
	RunTimers()
	check("depth: not asked again right away", #sent, 3)

	-- A believed empty answer: nothing listed. The row says so.
	has = true
	FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 2)
	RunTimers()
	check("depth: nothing listed stored", ns.db.depth[2] and #ns.db.depth[2], 0)
	check("depth: nothing listed, noted on the plan", ns.plan.thin[2] or ns.plan.buy[1], ns.plan.thin[2] and 5 or 12)

	-- The auction house not ready: nothing goes out until it says so. (A new visit: searches given up before
	-- are tried again.)
	ns.Queue.Clear()
	Fire("AUCTION_HOUSE_CLOSED")
	ns.db.depth = {}
	ready = false
	local before = #sent
	ns.Queue.Add(20, 1)
	RunTimers()
	check("depth: waits for the auction house", #sent, before)
	ready = true
	Wait(20)
	FireNow("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	Step()
	check("depth: sent when ready", #sent, before + 1)
	check("lock: locked again on the next check", ns.Lock.Shown(), true)
	FireNow("AUCTION_HOUSE_CLOSED")
	check("lock: gone when the auction house closes", ns.Lock.Shown(), false)
	RunTimers()
	check("depth: closing stops the check", ns.Depth.Status(), nil)

	-- The screen lock gives way: each time a new visit, with one search out and no answer yet.
	do
		local lock = ns.Lock.frame
		local function Visit()
			FireNow("AUCTION_HOUSE_CLOSED")
			RunTimers()
			ns.db.depth = { [2] = { at = time(), { 100, 50 } } } -- the bolts' listings known: only the cloth is read
			FireNow("AUCTION_HOUSE_SHOW")
			Step()
			Step()
		end
		local function Frames(count)
			for _ = 1, count do lock.scripts.OnUpdate(lock, 0.1) end
		end

		-- A fight starts.
		Visit()
		check("lock: locked on a new visit", ns.Lock.Shown(), true)
		inCombat = true
		FireNow("PLAYER_REGEN_DISABLED")
		check("lock: gone when a fight starts", ns.Lock.Shown(), false)
		check("lock: the check goes on", (ns.Depth.Status()), 1)
		Visit()
		check("lock: not put up in a fight", ns.Lock.Shown(), false)
		inCombat = false
		FireNow("PLAYER_REGEN_ENABLED")

		-- Escape takes the screen back until the check is over; other keys do nothing.
		Visit()
		lock.scripts.OnKeyDown(lock, "W")
		check("lock: keys are swallowed", ns.Lock.Shown(), true)
		lock.scripts.OnKeyDown(lock, "ESCAPE")
		check("lock: Escape unlocks", ns.Lock.Shown(), false)
		before = #sent
		Step() -- no answer: asked once more
		Step()
		check("lock: the check went on", #sent, before + 1)
		check("lock: stays away for the rest of that check", ns.Lock.Shown(), false)

		-- Nothing answered for a while.
		Visit()
		check("lock: back on the next check", ns.Lock.Shown(), true)
		Frames(ns.Lock.STALL)
		check("lock: waits for an answer", ns.Lock.Shown(), true)
		Frames(1)
		check("lock: gone when nothing is answered", ns.Lock.Shown(), false)
		check("lock: check still running then", (ns.Depth.Status()), 1)

		-- Up too long, though answers keep coming.
		Visit()
		local stall, max = ns.Lock.STALL, ns.Lock.MAX
		ns.Lock.STALL, ns.Lock.MAX = 1000, 5
		Frames(4)
		check("lock: up", ns.Lock.Shown(), true)
		Frames(2)
		check("lock: never longer than the limit", ns.Lock.Shown(), false)
		ns.Lock.STALL, ns.Lock.MAX = stall, max

		-- The check holds off for someone else's search: the lock stays, says so, and doesn't count it as stuck.
		Visit()
		FireNow("COMMODITY_PRICE_UPDATED")
		Frames(1)
		check("lock: says it's waiting", ns.Lock.frame.item.text, "Waiting for another search to finish. 1 to go.")
		Frames(ns.Lock.STALL + 2)
		check("lock: stays while the check holds off", ns.Lock.Shown(), true)
		Wait(20)
		before = #sent
		Step()
		Step()
		check("lock: check resumed", #sent, before + 1)
		check("lock: still locked as it resumes", ns.Lock.Shown(), true)

		-- The window stays on the tab you have open.
		ns.UI.Show("restock")
		Visit()
		check("lock: up with the Restock tab open", ns.Lock.Shown(), true)
		check("lock: stays on the Restock tab", ns.db.ui.tab, "restock")
		ns.UI.Hide()

		-- Refresh reads the queue's listings again though they're fresh; the check on its own doesn't.
		results[1] = { { unitPrice = 10, quantity = 100 } }
		FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
		check("refresh: listings read", ns.Depth.Status(), nil)
		before = #sent
		ns.Depth.CheckWanted()
		Step()
		Step()
		check("refresh: fresh listings left alone by the check", #sent, before)
		ns.RefreshEverything()
		Step()
		Step()
		check("refresh: Refresh searches them again", #sent, before + 1)
		check("refresh: for the cloth", sent[#sent].itemID, 1)
		check("refresh: screen locked meanwhile", ns.Lock.Shown(), true)

		-- The option turned off under it.
		ns.db.ui.depthCheck = false
		Frames(1)
		check("lock: gone with the option off", ns.Lock.Shown(), false)
		ns.db.ui.depthCheck = true
		FireNow("AUCTION_HOUSE_CLOSED")
		RunTimers()

		-- One lock for the whole check: a round ending and the new plan wanting more read keep the same lock up.
		local function TimesShown() return tonumber(ns.Lock.Diag():match("^(%d+)")) end
		Visit()
		local shown = TimesShown()
		results[1] = { { unitPrice = 10, quantity = 100 } }
		FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
		check("lock: round over, lock lingers", ns.Depth.Status() == nil and ns.Lock.Shown(), true)
		results[3] = { { unitPrice = 5, quantity = 100 } }
		ns.Depth.Check({ 3 }, true)
		Step()
		check("lock: next round sent", sent[#sent].itemID, 3)
		check("lock: still the same lock", ns.Lock.Shown() and TimesShown(), shown)
		FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 3)
		Linger()
		check("lock: gone once nothing more is read", ns.Lock.Shown(), false)

		-- A queued restock is decided again at what was read: here nothing earns the (huge) minimum, so it's cut.
		FireNow("AUCTION_HOUSE_CLOSED")
		RunTimers()
		ns.Queue.Clear()
		table.insert(ns.db.queue, { recipeID = 20, qty = 2, char = ns.CharKey(), restock = true })
		local minProfit = ns.db.restock.minProfitSilver
		ns.db.restock.minProfitSilver = 1000
		results[1] = { { unitPrice = 10, quantity = 2 }, { unitPrice = 30, quantity = 100 } }
		local told = {}
		local realPrint = ns.Print
		ns.Print = function(text) table.insert(told, text) end
		Visit()
		check("restock trim: cloth searched", sent[#sent].itemID, 1)
		FireNow("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
		RunTimers()
		ns.Print = realPrint
		check("restock trim: entry cut from the queue", #ns.db.queue, 0)
		check("restock trim: what was kept remembered", ns.Restock.CutTo(20), 0)
		check("restock trim: said in chat", (told[#told] or ""):find("Linen Shirt 2 -> none", 1, true) ~= nil, true)
		ns.db.restock.minProfitSilver = minProfit
		Linger()
		ns.db.restock.cuts = nil

		-- The Restock tab on its own doesn't search: with nothing queued, nothing is read.
		FireNow("AUCTION_HOUSE_CLOSED")
		RunTimers()
		ns.db.depth = {}
		before = #sent
		FireNow("AUCTION_HOUSE_SHOW")
		ns.UI.Show("restock")
		RunTimers()
		ns.UI.Hide()
		check("restock: no searches without a queue", #sent, before)
		check("restock: no lock without a queue", ns.Lock.Shown(), false)
	end

	-- Turned off: no searches of its own.
	ns.db.ui.depthCheck = false
	ns.db.depth = {}
	before = #sent
	FireNow("AUCTION_HOUSE_SHOW")
	RunTimers()
	check("depth: off, nothing sent", #sent, before)

	-- Old listings aren't used, and are dropped at the next login.
	ns.db.depth[1] = { at = time() - ns.Depth.MAX_AGE - 10, { 50, 100 } }
	check("depth: old listings not used", ns.Depth.Of(1), nil)

	SlashCmdList.CFF("diag")
	AuctionHouseFrame.shown = false
	ns.db.depth = {}
	ns.Queue.Clear()
	RunTimers()
	prices[1], prices[2] = savedPrices[1], savedPrices[2]
	C_AuctionHouse.SendSearchQuery, C_Item.GetItemInfo, C_Item.GetItemCount = realSearch, realInfo, realCount
	C_AuctionHouse.IsThrottledMessageSystemReady = realReady
	C_AuctionHouse.HasFullCommoditySearchResults, C_AuctionHouse.HasSearchResults = nil, nil
end

-- Camp stations: read from the recipe's requirements (place kind, a camp station's name); the queue says where to
-- place it, under the first crafting step, and marks the station on the step that gets it.
do
	local realReq = C_TradeSkillUI.GetRecipeRequirements
	C_TradeSkillUI.GetRecipeRequirements = function()
		return { { name = "Anvil", met = false, type = 0 }, { name = "Fermenter", met = false, type = 0 },
			{ name = "Blacksmith Hammer", met = false, type = 1 } }
	end
	Enum.RecipeRequirementType = { SpellFocus = 0, Totem = 1, Area = 2 }
	local stations = ns.Recipes.Stations(10)
	check("stations: the camp one, not the anvil or the tool", stations and table.concat(stations, ","), "Fermenter")
	Enum.RecipeRequirementType = nil
	stations = ns.Recipes.Stations(10)
	check("stations: no kind given, camp names", stations and table.concat(stations, ","), "Fermenter")
	C_TradeSkillUI.GetRecipeRequirements = function() return { { name = "Anvil", met = true } } end
	check("stations: none", ns.Recipes.Stations(10), nil)
	C_TradeSkillUI.GetRecipeRequirements = realReq
	check("station items by name", ns.Recipes.StationItems("Fermenter")[1], 279970)
	check("no camp anvil", #ns.Recipes.StationItems("Anvil"), 0)
	check("iron oven is a station", ns.Recipes.StationItems("Iron Oven")[1], 279982)
	check("anarchist's workbench is a station", ns.Recipes.StationItems("Anarchist's Workbench")[1], 279989)
	check("alchemy lab is the laboratory", ns.Recipes.StationItems("Alchemy Lab")[1], 279990)
	check("campfire kits", ns.Recipes.CampfireItems()[1], 279981)

	table.insert(ns.db.queue, { recipeID = 10, qty = 3, char = ns.CharKey() })
	local realPlan = ns.plan
	local craft = { recipeID = 10, count = 3, subCount = 0, char = ns.CharKey() }
	ns.plan = { crafts = { craft }, buy = { [279970] = 1 }, vendor = {}, fetch = {}, bank = {}, mail = {}, farm = {},
		smelt = {}, cost = 0, elsewhere = {}, paid = {}, deep = {}, thin = {}, tools = {}, noTool = {},
		camp = { { name = "Fermenter", itemID = 279970, fire = 279981, crafts = { craft } },
			{ name = "Loom", crafts = { craft } } },
		campItems = { [279970] = "Fermenter" } }
	local list = ns.UI.windows.queue.build()
	local titles, campRow, rows, queueUnder = {}, nil, {}, nil
	for at, data in ipairs(list) do
		if data.kind == "header" then table.insert(titles, (data.text:gsub(":.*", ""))) end
		if data.kind == "item" and data.itemID == 279970 then campRow = data end
		if data.kind == "tip" or data.kind == "warn" then rows[#rows + 1] = at .. ":" .. data.text end
		if data.kind == "queue" and not queueUnder then queueUnder = titles[#titles] end
	end
	check("camp: steps", table.concat(titles, ","), "1. Buy at auction house,2. Camp,3. Camp")
	check("camp: the station's craft on its own step", queueUnder, "2. Camp")
	check("camp: station marked on the buy row", campRow and campRow.camp, "Fermenter")
	local joined = table.concat(rows, "|")
	check("camp: place it", joined:find("Camp: place a", 1, true) ~= nil and joined:find("then a Fermenter, and craft Recipe10 x3", 1, true) ~= nil, true)
	check("camp: none to be had", joined:find("Recipe10 x3 needs a Loom and you have none", 1, true) ~= nil, true)
	check("camp: one station an hour", joined:find("Only one camp station an hour: they share a 60 minute cooldown, "
		.. "and your queue needs a Fermenter and a Loom.", 1, true) ~= nil, true)
	ns.plan.camp[2].itemID = 279959
	local twoLines = {}
	for _, data in ipairs(ns.UI.windows.queue.build()) do
		if data.kind == "tip" and data.text:find("^Camp: ") then table.insert(twoLines, data.text) end
	end
	check("camp: second station after the cooldown", twoLines[2],
		"Camp: after the cooldown, place a Loom (and a campfire if yours is out) and craft Recipe10 x3.")
	-- The user's ask: everything not needing the station first, then the station and its crafts only; the window
	-- says how many fit.
	ns.plan.camp[2] = nil
	table.insert(ns.db.queue, 1, { recipeID = 20, qty = 1, char = ns.CharKey() })
	local plainCraft = { recipeID = 20, count = 1, subCount = 0, char = ns.CharKey() }
	table.insert(ns.plan.crafts, 1, plainCraft)
	ns.plan.camp[1].window = { seconds = 900, why = "free", fits = 2, total = 3, need = 1350 }
	local function Steps()
		local found, under = {}, nil
		for _, data in ipairs(ns.UI.windows.queue.build()) do
			if data.kind == "header" then under = data.text end
			if data.kind == "queue" then found[#found + 1] = data.entry.recipeID .. "@" .. under end
			if data.kind == "warn" then found[#found + 1] = data.text end
		end
		return table.concat(found, "|")
	end
	check("camp: plain craft first, then the station's", Steps(), "20@2. Craft your queue (before the camp)|"
		.. "Only 2 of 3 crafts fit in the 15 minutes a Fermenter stands (about 7:30 each): the rest wait for the 60 "
		.. "minute cooldown.|10@3. Camp: place a Fermenter and craft beside it (it stands 15 minutes)")
	local savedBuy = ns.plan.buy
	ns.plan.buy = {}
	ns.UI.RefreshQueue()
	local barStep
	for _, data in ipairs(ns.UI.windows.next.list) do
		if data.kind == "header" and not barStep then barStep = data.text end
	end
	check("camp: Next step bar starts with the plain crafts", barStep, "Craft your queue")
	ns.plan.buy = savedBuy
	ns.plan.camp[1].window = { seconds = 0, why = "cooldown", fits = 0, total = 3, need = 1350 }
	ns.plan.campState = { cooldown = 1500, window = 900 }
	check("camp: cooldown says wait", Steps(), "20@2. Craft your queue (before the camp)|Camp stations are on cooldown "
		.. "for 25 more minutes: these crafts wait. Do everything else first.|10@3. Camp: Fermenter, after the station "
		.. "cooldown")
	ns.plan.camp[1].window, ns.plan.campState = nil, nil
	table.remove(ns.db.queue, 1)
	table.remove(ns.plan.crafts, 1)
	ns.plan.camp[1].firePlaced = true
	local function CampText()
		for _, data in ipairs(ns.UI.windows.queue.build()) do
			if data.kind == "tip" and data.text:find("^Camp: ") then return data.text end
		end
	end
	check("camp: fire lit", CampText(), "Camp: your campfire is lit: place a Fermenter beside it and craft Recipe10 x3.")
	ns.plan.camp[1].placed = true
	check("camp: station placed", CampText(), "Camp: your Fermenter is placed: craft Recipe10 x3 beside it.")
	ns.UI.RefreshQueue()
	ns.UI.Refresh("queue")
	ns.UI.Refresh("next")
	ns.plan = realPlan
	ns.Queue.Clear()
	RunTimers()
end
-- Placing a campfire kit or a station uses it up: the add-on notes it as placed, so the plan doesn't ask for another.
do
	local realSpell, realCount = C_Item.GetItemSpell, C_Item.GetItemCount
	local counts = { [279961] = 2 }
	C_Item.GetItemSpell = function(id) if id == 279981 then return "Basic Campfire", 5001 end end
	C_Item.GetItemCount = function(id) return counts[id] or 0 end
	ns.db.campPlaced = nil
	check("placed: nothing yet", ns.Recipes.CampPlaced(ns.Recipes.CampfireItems()), nil)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 5001)
	check("placed: by its use spell", ns.Recipes.CampPlaced(ns.Recipes.CampfireItems()), 279981)
	check("placed: plan context asks", ns.NewContext().campPlaced({ 279981 }), 279981)
	ns.db.campPlaced = nil
	-- Its spell not known: one fewer in the bags after a cast.
	Fire("UNIT_SPELLCAST_SENT", "player")
	counts[279961] = 1
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 4242)
	check("placed: by the count", ns.Recipes.CampPlaced(ns.Recipes.CampfireItems()), 279961)
	-- Another cast that uses no camp item changes nothing.
	Fire("UNIT_SPELLCAST_SENT", "player")
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 4243)
	check("placed: other casts don't count", ns.db.campPlaced[279970], nil)
	check("placed: a campfire starts no station cooldown", ns.Recipes.CampState().cooldown, 0)
	ns.db.campPlaced[279961].at = time() - ns.CAMP.STATION_MINUTES * 60 - 1
	check("placed: a campfire outlasts a station's 15 minutes", ns.Recipes.CampPlaced(ns.Recipes.CampfireItems()), 279961)
	ns.db.campPlaced[279961].at = time() - ns.CAMP.FIRE_MINUTES * 60 - 1
	check("placed: gone after an hour", ns.Recipes.CampPlaced(ns.Recipes.CampfireItems()), nil)
	ns.db.campPlaced[279961] = { at = time(), map = -1 }
	check("placed: left behind on another map", ns.Recipes.CampPlaced(ns.Recipes.CampfireItems()), nil)
	ns.db.campPlaced = nil
	-- A station: stands 15 minutes, and starts the hour every station shares.
	ns.db.campCooldown = nil
	counts[279970] = 1
	Fire("UNIT_SPELLCAST_SENT", "player")
	counts[279970] = 0
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 4244)
	local state = ns.Recipes.CampState()
	check("station: placed", state.itemID, 279970)
	check("station: stands 15 minutes", state.left, 15 * 60)
	check("station: cooldown an hour", state.cooldown, 60 * 60)
	check("station: a new one stands 15 minutes", state.window, 15 * 60)
	check("station: plan context", ns.NewContext().campState().itemID, 279970)
	ns.db.campPlaced[279970].at = time() - 15 * 60 - 1
	ns.db.campCooldown[ns.CharKey()] = time() - 15 * 60 - 1
	state = ns.Recipes.CampState()
	check("station: gone after 15 minutes", state.itemID, nil)
	check("station: cooldown still running", state.cooldown, 45 * 60 - 1)
	ns.db.campCooldown[ns.CharKey()] = time() - 60 * 60
	check("station: cooldown over after an hour", ns.Recipes.CampState().cooldown, 0)
	ns.db.campPlaced, ns.db.campCooldown = nil, nil
	C_Item.GetItemSpell, C_Item.GetItemCount = realSpell, realCount
end

-- Tools: read from the recipe's requirements; a tool on the bank step is marked, one you have nowhere gets its own
-- step, and one the add-on can't look for is a reminder on the crafting step.
do
	local realReq = C_TradeSkillUI.GetRecipeRequirements
	C_TradeSkillUI.GetRecipeRequirements = function()
		return { { name = "Anvil", met = false, type = 0 }, { name = "Blacksmith Hammer", met = false, type = 1 } }
	end
	Enum.RecipeRequirementType = { SpellFocus = 0, Totem = 1, Area = 2 }
	local tools = ns.Recipes.Tools(10)
	check("tools: the tool kind, not the anvil", tools and table.concat(tools, ","), "Blacksmith Hammer")
	Enum.RecipeRequirementType = nil
	tools = ns.Recipes.Tools(10)
	check("tools: no kind given, known tool names", tools and table.concat(tools, ","), "Blacksmith Hammer")
	C_TradeSkillUI.GetRecipeRequirements = function() return { { name = "Anvil", met = true } } end
	check("tools: none", ns.Recipes.Tools(10), nil)
	C_TradeSkillUI.GetRecipeRequirements = realReq
	check("tool items by name", ns.Recipes.ToolItems("Arclight Spanner")[1], 6219)

	table.insert(ns.db.queue, { recipeID = 10, qty = 1, char = ns.CharKey() })
	local realPlan = ns.plan
	ns.plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, bank = { [5956] = 1 }, mail = {}, farm = {}, smelt = {},
		cost = 0, elsewhere = {}, paid = {}, deep = {}, thin = {},
		tools = { [5956] = { name = "Blacksmith Hammer", recipeID = 10 } },
		noTool = { { name = "Arclight Spanner", recipeID = 10 }, { name = "Strange Tool", recipeID = 10, unknown = true } } }
	local list = ns.UI.windows.queue.build()
	local titles, toolRow, warns = {}, nil, {}
	for at, data in ipairs(list) do
		if data.kind == "header" then table.insert(titles, (data.text:gsub(":.*", ""))) end
		if data.kind == "item" and data.itemID == 5956 then toolRow = data end
		if data.kind == "warn" then warns[#warns + 1] = at .. ":" .. data.text end
	end
	check("tools: steps", table.concat(titles, "|"), "1. Take from your bank|2. Get your tools|3. Craft your queue")
	check("tools: bank row is the tool", toolRow and toolRow.tool and toolRow.tool.name, "Blacksmith Hammer")
	check("tools: missing one", warns[1], "4:Recipe10 needs an Arclight Spanner and you have none: a trade supplier sells it.")
	check("tools: reminder under the crafting step", warns[2], "6:Recipe10 needs a Strange Tool: have it in your bags.")
	ns.UI.RefreshQueue()
	ns.UI.Refresh("queue")
	ns.UI.Refresh("next")
	ns.plan = realPlan
	ns.Queue.Clear()
	RunTimers()
end

-- Plan check: once new prices are in (a search of the queue's list, a scan, the listings check), the plan is worked
-- out again. Rows that changed pulse; when nothing changed, the window says the plan holds.
do
	local saved = { prices[1], prices[2], ns.db.ui.depthCheck, ns.db.depth }
	ns.db.ui.depthCheck, ns.db.depth = false, {}
	prices[1], prices[2] = 10, 100
	ns.Queue.Clear()
	ns.Queue.Add(20, 2) -- 6 bolts, woven from 12 cloth
	RunTimers()
	local boltRecipe
	for _, craft in ipairs(ns.plan.crafts) do if (craft.subCount or 0) > 0 then boltRecipe = craft.recipeID end end
	check("plan check: bolts are a sub-craft", boltRecipe ~= nil, true)
	ns.UI.Show("queue")

	-- Nothing changes: the plan holds.
	ns.UI.lastVerdict = nil
	busListener:ReceiveEvent("shopping start", lists[ns.LIST_NAME])
	check("plan check: started", ns.PlanCheck.before ~= nil, true)
	busListener:ReceiveEvent("shopping end")
	RunTimers()
	check("plan check: nothing changed", ns.PlanCheck.result and ns.PlanCheck.result.count, 0)
	check("plan check: says it holds", ns.UI.lastVerdict, "Plan checked: still the cheapest way")
	check("plan check: done", ns.PlanCheck.before, nil)

	-- Cloth got dear during the search: bolts are bought now, and those rows pulse.
	busListener:ReceiveEvent("shopping start", lists[ns.LIST_NAME])
	prices[1] = 60
	busListener:ReceiveEvent("shopping end")
	RunTimers()
	local result = ns.PlanCheck.result
	check("plan check: bolts bought instead", ns.plan.buy[2], 6)
	check("plan check: three changes (cloth, bolts, the sub-craft)", result.count, 3)
	check("plan check: the bolts changed", result.changed.i2 and result.changed["r" .. boltRecipe], true)
	check("plan check: says so", ns.UI.lastVerdict, "Plan updated for the new prices: 3 changes")
	local pulsed
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "item" and row.data.itemID == 2 then pulsed = row.live.item end
	end
	check("plan check: the bolts row pulses", pulsed, "i2")

	-- Buying what the list says isn't a change: purchases waiting in the mail count the same.
	busListener:ReceiveEvent("shopping start", lists[ns.LIST_NAME])
	C_AuctionHouse.ConfirmCommoditiesPurchase(2, 6)
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	busListener:ReceiveEvent("shopping end")
	RunTimers()
	check("plan check: buying isn't a change", ns.PlanCheck.result.count, 0)

	-- Another list's search doesn't start one; a full scan does, and its end checks.
	busListener:ReceiveEvent("shopping start", { "a", "b", "c", "d", "e" })
	check("plan check: other lists ignored", ns.PlanCheck.before, nil)
	busListener:ReceiveEvent("shopping end")
	busListener:ReceiveEvent("full start")
	check("plan check: a scan starts one", ns.PlanCheck.before ~= nil, true)
	busListener:ReceiveEvent("full done")
	RunTimers()
	check("plan check: a scan ends one", ns.PlanCheck.before, nil)

	-- Closing the auction house halfway: no verdict on half the prices.
	ns.UI.lastVerdict = nil
	busListener:ReceiveEvent("shopping start", lists[ns.LIST_NAME])
	prices[1] = 10
	FireNow("AUCTION_HOUSE_CLOSED")
	RunTimers()
	check("plan check: dropped on closing", ns.PlanCheck.before, nil)
	check("plan check: no verdict", ns.UI.lastVerdict, nil)

	-- With no window open, chat says it.
	ns.UI.Hide()
	ns.db.ui.nextStep = false
	ns.UI.RefreshQueue()
	busListener:ReceiveEvent("full start") -- the bolts bought above are in the mail: the list is empty now
	busListener:ReceiveEvent("full done")
	RunTimers()
	check("plan check: chat when no window is up", ns.UI.lastVerdict, "Plan checked: still the cheapest way")
	ns.db.ui.nextStep = nil

	prices[1], prices[2], ns.db.ui.depthCheck, ns.db.depth = saved[1], saved[2], saved[3], saved[4]
	ns.Queue.Clear()
	RunTimers()
end

-- The Profit tab prices each recipe for the crafts its restock goal makes, down the listings read.
do
	local savedGoal, savedDepth, savedSmart = ns.db.restock.goals[2], ns.db.depth, ns.db.ui.smartRestock
	ns.db.restock.goals[2] = 5
	local price = ns.Prices.AH(1) or 10
	ns.db.depth = { [1] = { at = time(), { price, 2 }, { price * 10, 100 } } }
	ns.UI.Show("profit")
	ns.InvalidateProfit()
	local found
	for _, row in ipairs(ns.UI.windows.profit.rows) do
		if row.data and row.data.kind == "profit" and row.data.result.recipeID == 10 then found = row end
	end
	local result = found and found.data.result
	check("profit batch: restock goal's crafts", result and result.batch, 5)
	-- 5 crafts = 10 ore: 2 at the cheapest, 8 ten times dearer.
	check("profit batch: average down the listings", result and result.cost, (2 * price + 8 * price * 10) / 5)
	check("profit batch: one craft kept", result and result.oneCost, 2 * price)
	local tooltip = {}
	local realAddLine = GameTooltip.AddLine
	GameTooltip.AddLine = function(_, text) table.insert(tooltip, text) end
	if found then found.scripts.OnEnter(found) end
	GameTooltip.AddLine = realAddLine
	check("profit batch: tooltip says so", table.concat(tooltip, "\n"):find("Priced for 5 crafts", 1, true) ~= nil, true)
	-- A new goal is noticed on the next redraw, no invalidation needed.
	ns.db.restock.goals[2] = 1
	ns.UI.Refresh("profit")
	found = nil
	for _, row in ipairs(ns.UI.windows.profit.rows) do
		if row.data and row.data.kind == "profit" and row.data.result.recipeID == 10 then found = row end
	end
	check("profit batch: follows the goal", found and found.data.result.batch, 1)
	ns.db.restock.goals[2], ns.db.depth, ns.db.ui.smartRestock = savedGoal, savedDepth, savedSmart
	ns.InvalidateProfit()
end

-- Recipes mode: every recipe of the game against the characters, where each comes from, who still needs it.
do
	local Book = ns.RecipeBook
	check("recipe data loaded", next(ns.RecipeData) ~= nil, true)
	check("recipe data names its AllTheThings version", type(ns.RECIPE_DATA_VERSION), "string")
	local realData, realChars, realLists = ns.RecipeData, ns.db.chars, ns.db.recipeLists
	local me = ns.CharKey()
	local mine = realChars[me]
	local savedSkill, savedFaction = mine.skill, mine.faction
	local myProfession = ns.db.recipes[10].p
	ns.RecipeData = {
		[10] = { p = myProfession, s = 1, w = { { k = "t" } } },
		[900001] = { p = myProfession, s = 50, i = 4001, w = {
			{ k = "v", n = { 111 }, m = { 1429 }, c = { { "c", 3402, 45 } }, rep = { 2586, 9000 }, fa = 2 },
			{ k = "v", n = { 222 }, m = { 1411 }, fa = 1, l = 1 } } },
		[900002] = { p = myProfession, s = 300, i = 4002, b = 1, w = { { k = "i", inst = 239, n = { 333 } } } },
		[900003] = { p = myProfession, s = 75, w = { { k = "q", q = { 5000 }, n = { 444 }, m = { 1426 }, ev = "Lunar Festival" } } },
		[900004] = { p = 99999, s = 10, w = { { k = "t" } } },
	}
	mine.skill = { [myProfession] = { level = 100, max = 150 } }
	mine.faction = "Horde"
	-- The alt also has a profession this character doesn't.
	ns.db.recipes[900099] = { p = 99999, pn = "Testcraft", n = "Alt Thing" }
	ns.db.chars["Player-1-ALT"] = { name = "Alty", class = "Priest", recipes = { [900099] = true }, faction = "Horde",
		skill = { [myProfession] = { level = 310, max = 375 } } }
	ns.db.recipeLists = nil
	local npcs = { [222] = "Horde Vendor", [333] = "Big Boss", [444] = "Quest Giver" }
	C_TooltipInfo = { GetHyperlink = function(link)
		local id = tonumber(link:match("Creature%-0%-0%-0%-0%-(%d+)"))
		return npcs[id] and { lines = { { leftText = npcs[id] } } } or nil
	end }
	local realQuestLog = C_QuestLog
	C_QuestLog = { GetTitleForQuestID = function(id) return id == 5000 and "Lantern Run" or nil end }
	EJ_GetInstanceInfo = function(id) return id == 239 and "Uldaman" or nil end
	C_Spell = C_Spell or {}
	local realSpellName = C_Spell.GetSpellName
	C_Spell.GetSpellName = function(id)
		return ({ [900001] = "Bolt of Test", [900002] = "Robe of Test", [900003] = "Lantern Cloth", [10] = "Known One" })[id]
	end

	-- What the unlearned recipes would make: 900001 sells (2 x item 1 at 10 -> item 4 at 1000), 900002 binds.
	local realSchematic = C_TradeSkillUI.GetRecipeSchematic
	C_TradeSkillUI.GetRecipeSchematic = function(id)
		if id == 900001 then
			return { outputItemID = 4, quantityMin = 1, quantityMax = 1,
				reagentSlotSchematics = { { reagentType = 0, quantityRequired = 2, reagents = { { itemID = 1 } } } } }
		elseif id == 900002 then
			return { outputItemID = 5, quantityMin = 1, quantityMax = 1,
				reagentSlotSchematics = { { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 1 } } } } }
		end
		return realSchematic(id)
	end
	prices[4001] = 2000
	ns.db.recipePreview = nil
	local realCap = ns.db.ui.priceCap
	ns.db.ui.priceCap = false

	local profit = ns.UI.windows.profit
	ns.UI.Show("profit")
	ns.UI.SelectProfession("profit", myProfession)
	ns.db.ui.recipeWho, ns.db.ui.recipeLearned = nil, nil
	-- Recipes this character can learn and hasn't looked at light the Profit tab and the Recipes button.
	local profitTab = ns.UI.main.tabButtons[1]
	mine.learnableSeen = nil
	ns.db.ui.profitMode = "profit"
	ns.UI.Refresh("profit")
	ns.UI.RefreshTabs()
	check("recipes glow: profit tab is the first", profitTab.key, "profit")
	check("recipes glow: new learnable counted", ns.RecipeBook.NewCount(me), 2) -- 900001 (50) and 900003 (75)
	check("recipes glow: profit tab dot", profitTab.badge.shown, true)
	check("recipes glow: recipes button green", profit.modeButtons[3].text, "|cff55dd55Recipes|r")
	check("recipes glow: recipes button dot", profit.modeButtons[3].mode.badge.shown, true)
	check("recipes glow: other buttons plain", profit.modeButtons[2].text, "Skill up")
	profit.modeButtons[3].scripts.OnClick(profit.modeButtons[3])
	check("recipes glow: looking puts it out", ns.RecipeBook.NewCount(me), 0)
	check("recipes glow: profit tab dot gone", profitTab.badge.shown, false)
	check("recipes glow: first look marks nothing new", ns.RecipeBook.fresh[900001], nil)
	check("recipes mode saved", ns.db.ui.profitMode, "recipes")
	check("recipes mode lit", profit.modeButtons[3].text, "|cffffffffRecipes|r")
	check("recipes: who button shown", profit.whoButton:IsShown(), true)
	check("recipes: advertise hidden", profit.advertiseButton:IsShown(), false)
	check("recipes: headings", profit.list[1].columns, "recipes")
	local function Rows()
		local rows, order = {}, {}
		for _, data in ipairs(profit.list) do
			if data.kind == "recipe" then
				rows[data.row.recipeID] = data.row
				table.insert(order, data.row.recipeID)
			end
		end
		return rows, order
	end
	local rows, order = Rows()
	check("recipes: learned one left out", rows[10], nil)
	check("recipes: other profession left out", rows[900004], nil)
	check("recipes: sorted by skill", table.concat(order, ","), "900001,900003,900002")
	check("recipes: can learn now", rows[900001].status, "learn")
	check("recipes: needs more skill", rows[900002].status, "skill")
	check("recipes: other faction's vendor left out", rows[900001].source, "Vendor")
	check("recipes: only the Horde source", #rows[900001].sources, 1)
	check("recipes: holiday marked", rows[900003].source, "Quest*")
	check("recipes: bind on pickup", rows[900002].bound, true)
	-- Profit and when the recipe pays for itself.
	check("recipes: materials read for an unlearned recipe", ns.db.recipePreview[900001] and ns.db.recipePreview[900001].o, 4)
	local expectNet = ns.Prices.AH(4) * (1 - ns.AH_CUT) - 2 * ns.Planner.ItemCost(ns.NewContext(), 1)
	check("recipes: profit per craft", rows[900001].net, expectNet)
	check("recipes: pays back", rows[900001].payback, math.ceil(2000 / expectNet))
	check("recipes: what it makes binds", rows[900002].madeBound, true)
	check("recipes: no profit for a bound result", rows[900002].net, nil)
	check("recipes: no recipe price, no payback", rows[900003].payback, nil)
	do
		local shown
		for _, row in ipairs(profit.rows) do
			if row.data and row.data.kind == "recipe" and row.data.row.recipeID == 900001 then shown = row end
		end
		check("recipes: profit column", shown and shown.colAH.text:find(ns.Money(expectNet), 1, true) ~= nil, true)
		check("recipes: pays back column", shown and shown.profit.text, ns.Plural(math.ceil(2000 / expectNet), "craft", "crafts"))
		check("recipes: AH price column", shown and shown.colHave.text, ns.Money(2000))
		local headings = profit.rows[1].sortHeadings
		check("recipes: profit heading", headings.net.shown and headings.net.label.text, "Profit")
		check("recipes: pays back heading", headings.back.shown and headings.back.label.text, "Pays back")
		ns.UI.SortList("recipes", "net")
		local _, byProfit = Rows()
		check("recipes: sorted by profit", byProfit[1], 900001)
		ns.UI.SortList("recipes", "back")
		local _, byBack = Rows()
		check("recipes: sorted by pays back", byBack[1], 900001)
		ns.db.ui.recipeSort, ns.db.ui.recipeSortAsc = nil, nil
		ns.db.ui.priceCap = realCap
		C_TradeSkillUI.GetRecipeSchematic = realSchematic
		ns.UI.Refresh("profit")
	end
	local knownHere = 0
	for recipeID in pairs(mine.recipes) do
		if ns.db.recipes[recipeID] and ns.db.recipes[recipeID].p == myProfession then knownHere = knownHere + 1 end
	end
	check("recipes: learned counted", profit.list.info.learnedHidden, knownHere)
	check("recipes: status line", profit.status.text:find("3 recipes to find for", 1, true) ~= nil, true)

	-- Recipes to learn list: recipe items this character can learn now, lowest skill first, in its own list.
	do
		local Shopping = ns.Shopping
		local RL = ns.Shopping.RecipeListName(ns.Recipes.ProfessionName(myProfession))
		lists[RL] = nil
		lists[ns.RECIPE_LIST_NAME] = { "old" }
		ns.db.recipeShoppingLists = nil
		ns.RecipeData[900005] = { p = myProfession, s = 20, i = 4005, w = { { k = "v", n = { 222 } } } }
		names[4001], names[4005] = "Pattern: Bolt of Test", nil
		Shopping.SyncRecipes()
		check("recipe list: waits for names", lists[RL], nil)
		check("recipe list: loading counted", Shopping.recipeStatus.loading, 1)
		names[4005] = "Pattern: Early Thing"
		Shopping.SyncRecipes()
		local list = lists[RL] or {}
		check("recipe list: named after the profession", RL:match(" Shopping List$") ~= nil and RL ~= " Shopping List", true)
		check("recipe list: first version's list deleted", lists[ns.RECIPE_LIST_NAME], nil)
		-- 900003 has no recipe item (quest), 900002 needs more skill and binds, 10 is learned.
		check("recipe list: learnable recipe items only", #list, 2)
		check("recipe list: lowest skill first", list[1] and list[1]:find("Early Thing", 1, true) ~= nil, true)
		check("recipe list: then the next", list[2] and list[2]:find("Bolt of Test", 1, true) ~= nil, true)
		check("recipe list: no quantity", list[1] and list[1]:sub(-1), ";")
		-- Learning one deletes its row in place; no rewrite.
		local creates = createCalls
		mine.recipes[900005] = true
		Shopping.SyncRecipes()
		check("recipe list: learned one removed", #lists[RL], 1)
		check("recipe list: removed in place", createCalls, creates)
		Shopping.SyncRecipes()
		check("recipe list: unchanged, untouched", createCalls, creates)
		-- A skill-up that makes a new one learnable: rewritten in order (900002 binds, so add one that doesn't).
		ns.RecipeData[900006] = { p = myProfession, s = 30, i = 4006, w = { { k = "v", n = { 222 } } } }
		names[4006] = "Pattern: Middle Thing"
		Shopping.SyncRecipes()
		check("recipe list: new one in skill order", lists[RL][1]:find("Middle Thing", 1, true) ~= nil, true)
		check("recipe list: rewritten once", createCalls, creates + 1)
		-- Another character without this profession: its list goes.
		lists["Leatherworking Shopping List"] = { "x" }
		ns.db.recipeShoppingLists["Leatherworking Shopping List"] = true
		lists["My Own List"] = { "y" }
		Shopping.SyncRecipes()
		check("recipe list: stale profession list deleted", lists["Leatherworking Shopping List"], nil)
		check("recipe list: player's own list kept", lists["My Own List"] ~= nil, true)
		check("recipe list: this profession's kept", lists[RL] ~= nil, true)
		-- Turned off on the Options tab: the add-on's lists go and aren't made again; the player's own stays.
		ns.SetOption("recipeLists", false)
		Shopping.SyncRecipes()
		check("recipe list off: deleted", lists[RL], nil)
		check("recipe list off: player's own list kept", lists["My Own List"] ~= nil, true)
		Shopping.SyncRecipes()
		check("recipe list off: not made again", lists[RL], nil)
		ns.SetOption("recipeLists", true)
		Shopping.SyncRecipes()
		check("recipe list on: made again", lists[RL] ~= nil, true)
		lists["My Own List"] = nil
		mine.recipes[900005] = nil
		ns.RecipeData[900005], ns.RecipeData[900006] = nil, nil
		names[4001], names[4005], names[4006] = nil, nil, nil
		lists[RL] = nil
	end

	-- Skill goes up: the recipe that just became learnable lights it again, and says "new" once looked at.
	mine.skill[myProfession].level = 300
	ns.db.ui.profitMode = "profit"
	ns.UI.Refresh("profit")
	ns.UI.RefreshTabs()
	check("recipes glow: newly learnable", ns.RecipeBook.NewCount(me), 1)
	check("recipes glow: lit again", profitTab.badge.shown, true)
	profit.modeButtons[3].scripts.OnClick(profit.modeButtons[3])
	check("recipes glow: out again", profitTab.badge.shown, false)
	local robe
	for _, row in ipairs(profit.rows) do
		if row.data and row.data.kind == "recipe" and row.data.row.recipeID == 900002 then robe = row end
	end
	check("recipes glow: row says new", robe and robe.left.text:find("new", 1, true) ~= nil, true)
	mine.skill[myProfession].level = 100
	ns.UI.Refresh("profit")

	-- Source lines in words.
	local lines = Book.SourceLines(900001, me)
	check("recipes: vendor named", lines[1].text, "Vendor: Horde Vendor in Durotar")
	check("recipes: limited supply, own faction not said", lines[1].detail, "limited supply")
	local allianceLines = Book.SourceLines(900001, "nobody")
	check("recipes: no faction, both vendors", #allianceLines, 2)
	check("recipes: no faction, sides named", allianceLines[2].detail, "limited supply, Horde only")
	check("recipes: reputation and cost", allianceLines[1].detail:find("needs Honored with", 1, true) ~= nil
		and allianceLines[1].detail:find("costs 45", 1, true) ~= nil, true)
	check("recipes: dungeon drop", Book.SourceLines(900002, me)[1].text, "Dungeon drop: Uldaman, from Big Boss")
	local quest = Book.SourceLines(900003, me)[1]
	check("recipes: quest", quest.text, "Quest: Lantern Run from Quest Giver in Dun Morogh")
	check("recipes: quest during the holiday", quest.detail, "during Lunar Festival")
	check("recipes: npc name remembered", ns.db.npcNames[222], "Horde Vendor")

	-- Tooltip: where, and every character with the profession.
	local found
	for _, row in ipairs(profit.rows) do
		if row.data and row.data.kind == "recipe" and row.data.row.recipeID == 900002 then found = row end
	end
	local tooltip, doubles = {}, {}
	local realAddLine, realDouble = GameTooltip.AddLine, GameTooltip.AddDoubleLine
	GameTooltip.AddLine = function(_, text) table.insert(tooltip, text) end
	GameTooltip.AddDoubleLine = function(_, left, right) table.insert(doubles, left .. " = " .. right) end
	if found then found.scripts.OnEnter(found) end
	GameTooltip.AddLine, GameTooltip.AddDoubleLine = realAddLine, realDouble
	local text, who = table.concat(tooltip, "\n"), table.concat(doubles, "\n")
	check("recipes tooltip: where", text:find("Dungeon drop: Uldaman", 1, true) ~= nil, true)
	check("recipes tooltip: bind on pickup", text:find("can't be bought", 1, true) ~= nil, true)
	check("recipes tooltip: me first, short of skill", who:find("^Snic %(you%) = [^\n]*needs 300, has 100") ~= nil, true)
	check("recipes tooltip: alt can learn it", who:find("Alty = [^\n]*can learn it now %(310%)") ~= nil, true)

	-- All characters: the alt's name on the row, the best status of the two.
	profit.whoButton.scripts.OnClick(profit.whoButton)
	check("recipes: all characters saved", ns.db.ui.recipeWho, "all")
	check("recipes: who button says so", profit.whoButton.text, "All characters")
	rows = Rows()
	check("recipes all: best status", rows[900002].status, "learn")
	local robeRow
	for _, row in ipairs(profit.rows) do
		if row.data and row.data.kind == "recipe" and row.data.row.recipeID == 900002 then robeRow = row end
	end
	check("recipes all: alt named on the row", robeRow and robeRow.left.text:find("Alty", 1, true) ~= nil, true)
	check("recipes all: status line", profit.status.text:find("for your characters", 1, true) ~= nil, true)
	profit.whoButton.scripts.OnClick(profit.whoButton)
	check("recipes: back to this character", ns.db.ui.recipeWho, "me")

	-- Show learned.
	profit.showLearned.checked = true
	profit.showLearned.GetChecked = function(self) return self.checked end
	profit.showLearned.scripts.OnClick(profit.showLearned)
	rows = Rows()
	check("recipes: learned shown when asked", rows[10] and rows[10].status, "learned")
	profit.showLearned.checked = false
	profit.showLearned.scripts.OnClick(profit.showLearned)

	-- Hide BoP: only recipes whose craft can go on the auction house. Item 2 trades, item 5 binds on pickup.
	check("recipes: profession scan read an unlearned recipe's craft", ns.db.recipeOutputs and ns.db.recipeOutputs[40], 5)
	local savedOutputs = ns.db.recipeOutputs
	ns.db.recipeOutputs = { [900001] = 2, [900003] = 5 }
	profit.hideBound.checked = true
	profit.hideBound.GetChecked = function(self) return self.checked end
	profit.hideBound.scripts.OnClick(profit.hideBound)
	check("hide bop: saved", ns.db.ui.recipeHideBound, true)
	rows = Rows()
	check("hide bop: tradeable craft kept", rows[900001] ~= nil, true)
	check("hide bop: bind on pickup craft hidden", rows[900003], nil)
	check("hide bop: unknown craft kept", rows[900002] ~= nil, true)
	check("hide bop: counted", profit.list.info.boundHidden, 1)
	check("hide bop: unknown counted", profit.list.info.unchecked, 1)
	check("hide bop: status line", profit.status.text:find("1 bind on pickup hidden", 1, true) ~= nil, true)
	ns.db.recipeOutputs[900002] = 0 -- makes no item: nothing to post
	ns.UI.Refresh("profit")
	rows = Rows()
	check("hide bop: no item hidden", rows[900002], nil)
	local tip = {}
	local realDouble = GameTooltip.AddDoubleLine
	GameTooltip.AddDoubleLine = function(_, left, right) table.insert(tip, left .. " = " .. right) end
	for _, row in ipairs(profit.rows) do
		if row.data and row.data.kind == "recipe" and row.data.row.recipeID == 900001 then row.scripts.OnEnter(row) end
	end
	GameTooltip.AddDoubleLine = realDouble
	check("hide bop: tooltip says what it makes", table.concat(tip, "\n"):find("Makes " .. ns.Items.Name(2), 1, true) ~= nil, true)
	profit.hideBound.checked = false
	profit.hideBound.scripts.OnClick(profit.hideBound)
	rows = Rows()
	check("hide bop: off lists them again", rows[900003] ~= nil and rows[900002] ~= nil, true)
	ns.db.recipeOutputs = savedOutputs

	-- The game's own list: AllTheThings' recipes it lacks are left out, ones only the game has are added.
	ns.db.recipeLists = { [myProfession] = { at = 0, ids = { [10] = true, [900001] = true, [900003] = true, [777777] = true } } }
	ns.UI.Refresh("profit")
	rows = Rows()
	check("recipes: not in the game's list", rows[900002], nil)
	check("recipes: counted as not in this game", profit.list.info.notInGame, 1)
	check("recipes: game-only recipe added", rows[777777] ~= nil, true)
	check("recipes: game-only recipe, source unknown", rows[777777] and rows[777777].source, "Unknown")
	check("recipes: game-only recipe says why", Book.SourceLines(777777, me)[1].text:find("Not in AllTheThings", 1, true) ~= nil, true)
	ns.db.recipeLists = nil

	-- Sorting by name, then a search.
	ns.UI.SortList("recipes", "name")
	local _, byName = Rows()
	check("recipes: sorted by name", table.concat(byName, ","), "900001,900003,900002")
	ns.UI.SortList("recipes", "name")
	_, byName = Rows()
	check("recipes: name reversed", table.concat(byName, ","), "900002,900003,900001")
	ns.db.ui.recipeSort, ns.db.ui.recipeSortAsc = nil, nil
	profit.searchBox:SetText("lantern")
	profit.searchBox.scripts.OnTextChanged(profit.searchBox)
	_, order = Rows()
	check("recipes: search", table.concat(order, ","), "900003")
	profit.searchBox:SetText("")
	profit.searchBox.scripts.OnTextChanged(profit.searchBox)

	-- A profession this character doesn't have.
	ns.UI.SelectProfession("profit", 99999)
	rows = Rows()
	check("recipes: no profession, listed dimmed", rows[900004] and rows[900004].status, "none")
	check("recipes: no profession, says so", profit.status.text:find("doesn't have Testcraft", 1, true) ~= nil, true)

	ns.RecipeData, ns.db.recipeLists = realData, realLists
	ns.db.chars["Player-1-ALT"] = nil
	ns.db.recipes[900099] = nil
	mine.skill, mine.faction = savedSkill, savedFaction
	C_Spell.GetSpellName = realSpellName
	prices[4001] = nil
	C_TooltipInfo, EJ_GetInstanceInfo, C_QuestLog = nil, nil, realQuestLog
	ns.db.ui.profitMode = "profit"
	ns.UI.SelectProfession("profit", nil)
end

-- Usual prices: reading a price records today's low; three days make a usual price; a spike counts at it.
do
	local today = ns.DayNumber(time())
	ns.db.priceDays[4] = nil
	ns.Prices.NewRound()
	ns.Prices.AH(4)
	check("usual: today's low recorded", ns.db.priceDays[4] and ns.db.priceDays[4][today], prices[4])
	check("usual: not known with one day", ns.Prices.Normal(4), nil)
	ns.db.priceDays[4] = { [today - 3] = 400, [today - 2] = 500, [today - 1] = 450, [today] = 1000 }
	check("usual: median of the days", ns.Prices.Normal(4), 475)
	check("usual: share of usual", ns.Prices.OfNormal(4), prices[4] / 475)
	ns.SetOption("normalPrice", false)
	check("usual: option off", ns.Prices.Normal(4), nil)
	ns.SetOption("normalPrice", true)
	ns.db.priceDays[4] = nil
end

-- Bank alt mode: crafts in the bags are mailed to the bank alt by themselves at a mailbox, whole stacks, postage
-- counted; soulbound ones and a crafter's own materials beyond what the auction house lacks stay.
do
	local container, itemCount = C_Container, C_Item.GetItemCount
	local slots = { [0] = { { itemID = 4, stackCount = 3 }, { itemID = 2, stackCount = 4 }, { itemID = 5, stackCount = 1, isBound = true } } }
	local cursor
	local attached, sent = {}, {}
	C_Container = {
		GetContainerNumSlots = function(bag) return slots[bag] and #slots[bag] or 0 end,
		GetContainerItemInfo = function(bag, slot) return slots[bag] and slots[bag][slot] or nil end,
		PickupContainerItem = function(bag, slot) cursor = { bag = bag, slot = slot, count = slots[bag][slot].stackCount } end,
		SplitContainerItem = function(bag, slot, count) cursor = { bag = bag, slot = slot, count = count } end,
	}
	GetCursorInfo = function() return cursor and "item" or nil end
	ClearCursor = function() cursor = nil end
	ClickSendMailItemButton = function(index)
		local from = slots[cursor.bag][cursor.slot]
		attached[index] = { itemID = from.itemID, count = cursor.count }
		from.stackCount = from.stackCount - cursor.count
		if from.stackCount <= 0 then slots[cursor.bag][cursor.slot] = false end
		cursor = nil
	end
	GetSendMailItem = function(index)
		local item = attached[index]
		if item then return names[item.itemID], item.itemID, 1, item.count end
	end
	GetSendMailPrice = function()
		local count = 0
		for _ in pairs(attached) do count = count + 1 end
		return count * 30
	end
	ClearSendMail = function() attached = {} end
	SendMail = function(to, subject)
		table.insert(sent, { to = to, subject = subject, items = attached })
		attached = {}
		FireNow("MAIL_SEND_SUCCESS")
	end
	C_Item.GetItemCount = function(id)
		local count = 0
		for _, item in ipairs(slots[0]) do
			if item and item.itemID == id then count = count + item.stackCount end
		end
		return count
	end
	ns.Queue.Clear()
	ns.db.ui.bankAltMode, ns.db.ui.bankAltName = true, "Banky"
	ns.db.restock.goals[2] = 1
	ns.InvalidateProfit()
	ns.RequestPlan()
	RunTimers()
	local send = ns.plan.send
	check("bank alt: shirts to send", send and send.bags[4], 3)
	check("bank alt: soulbound robe stays", send and send.bags[5], nil)
	check("bank alt: campfire kit is a camp item", ns.Recipes.IsCampItem(279981), true)
	check("bank alt: shirt isn't a camp item", ns.Recipes.IsCampItem(4), false)
	local isCamp = ns.Recipes.IsCampItem
	ns.Recipes.IsCampItem = function(id) return id == 4 end -- pretend the shirt places a camp
	ns.RequestPlan()
	RunTimers()
	check("bank alt: camp items never mailed", ns.plan.send and ns.plan.send.bags[4], nil)
	ns.Recipes.IsCampItem = isCamp
	ns.RequestPlan()
	RunTimers()
	check("bank alt: shirts back on the list", ns.plan.send and ns.plan.send.bags[4], 3)
	check("bank alt: own material only as far as the AH lacks it", send and send.bags[2], 1)
	check("bank alt: postage off the shirt's profit", ns.Planner.Profit(ns.NewContext(), 20).postage ~= nil, true)
	check("bank alt: bank alt's alts left out", ns.Seller.IsName("banky-Realm"), true)
	local bar = ns.UI.windows.next
	check("bank alt: Next step bar up with an empty queue", bar and bar.frame:IsShown(), true)
	check("bank alt: bar on the mail step", bar and bar.mailing, true)
	check("bank alt: crafter posts nothing itself", ns.Posting.Rows()[1].toPost, 0)
	Fire("MAIL_CLOSED")
	check("bank alt: needs a mailbox", (ns.Seller.Run(false)), false)
	Fire("MAIL_SHOW")
	for _ = 1, 3 do RunTimers() end
	check("bank alt: one mail sent by itself", #sent, 1)
	check("bank alt: to the bank alt", sent[1] and sent[1].to, "Banky")
	local units = 0
	for _, item in pairs(sent[1] and sent[1].items or {}) do units = units + item.count end
	check("bank alt: shirts and one bolt", units, 4)
	check("bank alt: one bolt split off", slots[0][2] and slots[0][2].stackCount, 3)
	check("bank alt: on its way counted", ns.Seller.InTransit(4), 3)
	check("bank alt: job finished", ns.Seller.Busy(), false)
	check("bank alt: cursor empty", cursor, nil)
	RunTimers()
	check("bank alt: nothing left to send", ns.plan.send, nil)
	-- A refused mail stops the job, and nothing in it counts as on its way.
	slots[0][1] = { itemID = 4, stackCount = 2 }
	ns.RequestPlan()
	RunTimers()
	local sendMail, realTime = SendMail, GetTime
	SendMail = function() end
	GetTime = function() return 5000 end -- the stub's clock ticks per call: the server's answer must not time out
	check("bank alt: second batch started", (ns.Seller.Run(false)), true)
	RunTimers()
	check("bank alt: second mail waiting for the server", ns.Seller.Busy(), true)
	FireNow("MAIL_FAILED")
	check("bank alt: refused mail stops", ns.Seller.Busy(), false)
	check("bank alt: refused mail not on its way", ns.Seller.InTransit(4), 3)
	check("bank alt: refused mail's attachments cleared", next(attached), nil)
	SendMail, GetTime = sendMail, realTime
	Fire("MAIL_CLOSED")
	-- The name cleared in Options redraws before the plan does: the old plan's mail step must not break it.
	slots[0][1] = { itemID = 4, stackCount = 2 } -- the refused mail's attachments are back in the bags
	ns.RequestPlan()
	RunTimers()
	check("bank alt: crafts back to send", ns.plan.send ~= nil, true)
	ns.db.ui.bankAltName = nil
	check("bank alt: name cleared, redraw before the plan", pcall(ns.UI.RefreshQueue), true)
	ns.db.ui.bankAltName = "Banky"
	-- Farm It has no mail step, so crafts to mail alone don't keep an empty Next step bar up.
	ns.db.ui.farmMode = true
	ns.UI.RefreshQueue()
	check("bank alt: Farm It, no empty bar", bar.frame:IsShown(), false)
	ns.db.ui.farmMode = nil
	slots[0][1] = false
	ns.RequestPlan()
	RunTimers()
	-- On the bank alt itself: nothing to mail, and its mailbox shows what was on its way.
	ns.db.ui.bankAltName = "Snic"
	check("bank alt: on itself, it isn't a crafter", ns.Seller.Active(), false)
	-- A player's report: on the bank alt it still asked to mail everything to the bank alt. Names typed with an accent
	-- in another case, or a space before the realm, must still match.
	ns.db.ui.bankAltName = " snic - Some Realm "
	check("bank alt: realm with spaces", ns.Seller.IsMe(), true)
	ns.db.ui.bankAltName = "élise"
	check("bank alt: accented capital", ns.Seller.IsName("Élise"), true)
	check("bank alt: accented, another name", ns.Seller.IsName("Elise"), false)
	ns.db.ui.bankAltName = "ярослав"
	check("bank alt: Cyrillic capital", ns.Seller.IsName("Ярослав-Realm"), true)
	-- WoW Forever: every character has the account's first name plus its own surname, and no realm. UnitName gives
	-- both; the first name alone would make every character the bank alt (or none of them).
	local realUnitName = UnitName
	UnitName = function() return "Snic", "Bank" end
	RegionalUniqueNamesEnabled = function() return true end
	check("forever names: full name", ns.PlayerName(), "Snic Bank")
	ns.db.ui.bankAltName = "Snic Bank"
	check("forever names: on the bank alt", ns.Seller.IsMe(), true)
	check("forever names: not a crafter there", ns.Seller.Active(), false)
	ns.db.ui.bankAltName = "Snic Pal"
	check("forever names: another character crafts", ns.Seller.Active(), true)
	ns.db.ui.bankAltName = "snic bank"
	check("forever names: any case", ns.Seller.IsMe(), true)
	check("forever names: saved on the record", ns.CharRecord().name, "Snic Bank")
	UnitName, RegionalUniqueNamesEnabled = realUnitName, nil
	check("forever names: plain names elsewhere", ns.PlayerName(), "Snic")
	ns.CharRecord()
	ns.db.ui.bankAltName = "Snic"
	Fire("MAIL_SHOW")
	check("bank alt: seen on arrival", ns.Seller.InTransit(4), 0)
	Fire("MAIL_CLOSED")
	check("bank alt: the bank alt pays no postage", ns.Planner.Profit(ns.NewContext(), 20).postage, nil)
	ns.db.ui.bankAltMode, ns.db.ui.bankAltName, ns.db.restock.goals[2] = nil, nil, nil
	ns.InvalidateProfit()
	ns.RequestPlan()
	RunTimers()
	C_Container, C_Item.GetItemCount = container, itemCount
	GetCursorInfo, ClearCursor, ClickSendMailItemButton, GetSendMailItem, GetSendMailPrice, ClearSendMail, SendMail =
		nil, nil, nil, nil, nil, nil, nil
end

-- Characters left out on the Options tab (pull request #2): their recipes, bags, bank, mail and auctions count
-- nowhere; the character you're playing always counts.
do
	local alt = "Player-1-BBB"
	ns.db.recipes[901] = { n = "Alt Thing", o = 9011, qmin = 1, qmax = 1, p = 197, pn = "Tailoring", r = { { 1, 1 } } }
	ns.db.chars[alt] = { name = "Alt", realm = "Realm", class = "Mage", classFile = "MAGE", recipes = { [901] = true } }
	Syndicator = { API = {
		IsReady = function() return true end,
		GetCurrentCharacter = function() return "Snic-Realm" end,
		GetAllCharacters = function() return { "Snic-Realm", "Alt Surname-Realm" } end,
		GetByCharacterFullName = function(full)
			local name = full:match("^(.-)%-")
			return { details = { character = name, realm = "Realm", className = name == "Snic" and "PALADIN" or "MAGE" } }
		end,
		GetInventoryInfoByItemID = function(id)
			if id ~= 2 then return { characters = {} } end
			return { characters = {
				{ character = "Snic", realmNormalized = "Realm", bags = 50, bank = 50, mail = 1, auctions = 2 },
				{ character = "Alt Surname", realmNormalized = "Realm", bags = 3, bank = 1, mail = 2, auctions = 1 },
			} }
		end,
	} }
	check("leave out: alt's recipe known before", ns.Recipes.KnownMap()[9011] ~= nil, true)
	-- The alt's record was saved with its first name only (before surnames were read): its full name comes from
	-- Syndicator, everywhere names are shown or matched.
	check("full name: from Syndicator", ns.CharName(alt), "Alt Surname")
	check("full name: shown", ns.CharLabel(alt), "Alt Surname")
	check("full name: matches Syndicator's alt stock", ns.NewContext().charName(alt), "Alt Surname")
	ns.db.chars[alt].name = "Alt Surname"
	check("full name: saved one used as it is", ns.CharName(alt), "Alt Surname")
	ns.db.chars[alt].name = "Alt"
	check("leave out: alt's stock counted before", #ns.Stock.Alts(2), 1)
	local entries = ns.Stock.Characters()
	local altEntry, meEntry
	for _, entry in ipairs(entries) do
		if entry.key == "Alt Surname-Realm" then altEntry = entry end
		if entry.me then meEntry = entry end
	end
	check("leave out: Syndicator's alt matched to its record", altEntry and altEntry.guids[1], alt)
	check("leave out: the one you're playing marked", meEntry ~= nil, true)
	ns.Stock.SetLeftOut(altEntry, true)
	check("leave out: ticked", ns.Stock.IsLeftOut(altEntry), true)
	check("leave out: record excluded", ns.CharExcluded(alt), true)
	check("leave out: recipe gone", ns.Recipes.KnownMap()[9011], nil)
	check("leave out: never knows it", ns.Recipes.Knows(alt, 901), false)
	check("leave out: alt's bags and bank not offered", #ns.Stock.Alts(2), 0)
	local onAH, owned = ns.Stock.ForRestock(2)
	check("leave out: alt's auctions not counted", onAH, 2)
	check("leave out: alt's mail, bags, bank not counted", owned, 1)
	local rows = ns.RecipeBook.Rows({ who = "all", me = ns.CharKey(), professionID = 197, showLearned = true })
	local listed = false
	for _, row in ipairs(rows) do
		for _, char in ipairs(row.chars or {}) do
			if char.key == alt then listed = true end
		end
	end
	check("leave out: not in Recipes for all characters", listed, false)
	ns.Stock.SetLeftOut({ key = ns.CharKey() }, true)
	check("leave out: the one you're playing always counts", ns.CharExcluded(ns.CharKey()), false)
	ns.Stock.SetLeftOut(altEntry, false)
	ns.Stock.SetLeftOut({ key = ns.CharKey() }, false)
	check("leave out: all cleared", ns.db.ui.excludedChars, nil)
	check("leave out: recipe back", ns.Recipes.KnownMap()[9011] ~= nil, true)
	ns.db.chars[alt], ns.db.recipes[901], Syndicator = nil, nil, nil
end

do -- Writs and Crates tabs: held writs and crates are counted for the tab's flair
	local itemCount = C_Item.GetItemCount
	C_Item.GetItemCount = function() return 0 end
	check("held: no writs", ns.Writs.Held(), 0)
	check("held: no crates", ns.Crates.Held(), 0)
	C_Item.GetItemCount = function(id)
		return (id == 264011 and 2) or (id == 264153 and 1) or (id == 248682 and 3) or 0
	end
	check("held: writs summed", ns.Writs.Held(), 3)
	check("held: crates summed", ns.Crates.Held(), 3)
	ns.UI.RefreshTabs()
	C_Item.GetItemCount = function(id) return (id == 264011 or id == 248682) and 1 or 0 end
	check("held: one writ", ns.Writs.Held(), 1)
	local listed
	for _, row in ipairs(ns.Writs.Rows(3, true)) do
		if row.writ.id == 264011 then listed = row.held end
	end
	check("held: a held writ is listed past the level filter", listed, 1)
	listed = nil
	for _, row in ipairs(ns.Crates.Rows(4)) do
		if row.crate.id == 248682 then listed = row.held end
	end
	check("held: a held crate is listed past the level filter", listed, 1)
	ns.UI.RefreshAll()
	C_Item.GetItemCount = itemCount
end

-- Legacy talents: Working Overtime adds to the skill chance, Bartering comes off the seed vendor prices only.
do
	check("legacy: none without trees", ns.Legacy.VendorDiscount(), 0)
	local spells = { [1225451] = "Working Overtime", [777001] = "Bartering", [777002] = "Master Chef" }
	local nodes = { [11] = { spell = 1225451, rank = 5 }, [12] = { spell = 777001, rank = 2 }, [13] = { spell = 777002, rank = 3 } }
	_G.C_Traits = {
		GetConfigIDByTreeID = function(tree) return tree == 1 and 50 or nil end,
		GetTreeNodes = function(tree) return tree == 1 and { 11, 12, 13 } or {} end,
		GetNodeInfo = function(_, id) return { currentRank = nodes[id].rank, activeEntry = { entryID = id } } end,
		GetEntryInfo = function(_, id) return { definitionID = id } end,
		GetDefinitionInfo = function(id) return { spellID = nodes[id].spell } end,
	}
	_G.Constants = _G.Constants or {}
	_G.Constants.LegacyConsts = { LEGACY_TREE_PROFESSIONS_ID = 1, LEGACY_TREE_ADVENTURE_ID = 2, LEGACY_TREE_PROGRESSION_ID = 3 }
	local spellName = C_Spell.GetSpellName
	C_Spell.GetSpellName = function(id) return spells[id] end
	check("legacy: cached until forgotten", ns.Legacy.VendorDiscount(), 0)
	ns.Legacy.Forget()
	local bonus, rank = ns.Legacy.SkillBonus()
	check("legacy: Working Overtime rank", rank, 5)
	check("legacy: Working Overtime bonus", math.floor(bonus * 100 + 0.5), 20)
	check("legacy: Bartering 2/2 is 10%", ns.Legacy.VendorDiscount(), 0.1)
	check("legacy: seed price discounted", ns.Prices.Vendor(2320), 9)
	check("legacy: learned price as charged", ns.Prices.Vendor(3), 10)
	check("legacy: Master Chef on cooking", math.floor(ns.Legacy.ExtraYield({ p = 185 }) * 100 + 0.5), 30)
	check("legacy: Master Chef not on other recipes", ns.Legacy.ExtraYield({ p = 164 }), 0)
	check("legacy: diag", ns.Legacy.Diag(), "3 nodes, Working Overtime 5, Bartering 2, Master Chef 3")
	FireNow("PLAYER_ENTERING_WORLD")
	nodes[12].rank = 1
	check("legacy: re-read after a zone change", ns.Legacy.VendorDiscount(), 0.05)
	_G.C_Traits, _G.Constants.LegacyConsts, C_Spell.GetSpellName = nil, nil, spellName
	ns.Legacy.Forget()
end

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
