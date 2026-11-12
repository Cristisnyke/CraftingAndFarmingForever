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
		if key == "professionID" or key == "data" or key == "target" then return nil end -- add-on data on a frame, not a method
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
function GetInboxNumItems() return #inbox end
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
Enum = { CraftingReagentType = { Basic = 0 } }
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
	FullScan = { Events = { ScanStart = "full start" } },
	IncrementalScan = { Events = { ScanStart = "incremental start" } },
	SavedState = { TimeOfLastBrowseScan = os.time() - 90000 },
	State = {},
	Config = { Options = { REPLICATE_SCAN = "r" }, Get = function() return false end },
	Shopping = { ListManager = listManager, Tab = { Events = { SearchStart = "shopping start" } } },
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

-- Still to buy against the gold carried: 90c AH + 20c vendor = 1s 10c.
check("plan cost", ns.plan.cost, 110)
playerMoney = 200
check("enough gold", ns.UI.StillToBuyText(), "Still to buy: 1s 10c. |cff55dd55You have 2s 00c.|r")
playerMoney = 50
check("not enough gold", ns.UI.StillToBuyText(), "Still to buy: 1s 10c. |cffff6655You have 50c, 60c short.|r")
Fire("PLAYER_MONEY")
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
ChatEdit_GetLastTellTarget = nil

-- The margin box in the Queue footer changes the quote and is saved.
do
	local box = ns.UI.windows.queue.marginBox
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
check("restock replaced", #ns.db.queue, 2)
check("manual entry kept", ns.db.queue[1], manual)
check("restock quantity", ns.db.queue[2].qty, 1)
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

-- Restock on one tab leaves the other profession's restock entries alone.
ns.db.queue[1] = { recipeID = 500, qty = 2, char = "Player-2-ALT", restock = true }
ns.db.queue[2] = { recipeID = 20, qty = 2, char = me, restock = true }
ns.Restock.Apply({ { recipeID = 10, crafts = 1 } }, 197)
check("other profession's restock kept", ns.db.queue[1].recipeID, 500)
check("this profession's restock replaced", ns.db.queue[2].recipeID, 10)
check("restock entry count", #ns.db.queue, 2)
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

-- Mail: sold and expired are counted, other mail and pending sales aren't. Quantities come from subject or attachment.
ns.db.sales.lots[1].at = os.time() - 3600 * 6
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
check("expired item ID from attachment", bolt.itemID, 2)

-- The same mail seen again doesn't count again, and a slightly different expiry is still the same mail.
inbox[1].daysLeft = 29.999
Fire("MAIL_INBOX_UPDATE")
Fire("MAIL_INBOX_UPDATE")
check("rescan doesn't double count", ns.Sales.Item("Bolt of Linen").sold, 8)
table.remove(inbox, 1)
Fire("MAIL_INBOX_UPDATE")
check("collected mail doesn't change totals", ns.Sales.Item("Bolt of Linen").sold, 8)

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
	ns.UI.SortProfit("name")
	check("sorted by name", ns.db.ui.profitSort, "name")
	check("names A to Z", Ordered(Name, true), true)
	ns.UI.SortProfit("name")
	check("second click reverses", ns.db.ui.profitSortAsc, false)
	check("names Z to A", Ordered(Name, false), true)
	ns.UI.SortProfit("profit")
	check("profit highest first", Ordered(Net, false), true)
	ns.UI.SortProfit("profit")
	check("profit lowest first", Ordered(Net, true), true)
	local seenUnpriced, pricedAfter = false, false
	for _, result in ipairs(Results()) do
		if result.net == nil then seenUnpriced = true elseif seenUnpriced then pricedAfter = true end
	end
	check("no price stays last when reversed", pricedAfter, false)
	ns.UI.SortProfit("chance")
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
	check("default width", frame.width, 680)
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
	check("never narrower than the tabs", frame.width, 680)
	check("never shorter than the minimum", frame.height, 460)
	ns.UI.main.grip.scripts.OnClick(ns.UI.main.grip)
	check("reset width", frame.width, 680)
	check("reset height", frame.height, 560)
	check("reset clears saved size", ns.db.ui.width, nil)
	UIParent.height = 400
end

-- Stale prompt at the AH.
AuctionHouseFrame:Show()
Fire("AUCTION_HOUSE_SHOW")
check("stale scan prompts", ns_popup, "CFF_SCAN")

-- Slash commands.
for _, command in ipairs({ "", "", "queue", "profit", "restock", "sales", "refresh", "advertise", "auto", "auto", "clear", "changelog", "diag", "bogus" }) do
	SlashCmdList.CFF(command)
end
RunTimers()

-- Late saved data: the session's queue is merged into the table the client hands over.
ns.Queue.Add(10, 1)
CraftingAndFarmingForeverDB = { queue = { { recipeID = 30, qty = 1, char = me } }, recipes = {}, chars = {},
	ui = { hideLosing = true, manualChat = {}, positions = { main = { x = 1, y = 2 }, next = { x = 3, y = 4 }, farm = { x = 5, y = 6 } } },
	auctionLog = { "old" },
	sales = { seen = { someone = { { key = "sold|Copper Axe|2|500", expires = 1 }, { key = "sold|Copper Axe|500", expires = 1 } } } } }
RunTimers()
Fire("PLAYER_LOGOUT")
check("late data adopted", ns.db, CraftingAndFarmingForeverDB)
check("old mail record loses its count", ns.db.sales.seen.someone[1].key, "sold|Copper Axe|500")
check("new mail record left alone", ns.db.sales.seen.someone[2].key, "sold|Copper Axe|500")
ns.db.sales.seen.someone = nil
check("old auction log dropped", ns.db.auctionLog, nil)
check("old options dropped", ns.db.ui.hideLosing == nil and ns.db.ui.manualChat == nil, true)
check("old window positions dropped", ns.db.ui.positions.farm, nil)
check("main position kept", ns.db.ui.positions.main.y, 2)
check("next position kept", ns.db.ui.positions.next.x, 3)
check("session queue merged", #ns.db.queue, 2)

-- Changelog tab.
do
	local W = ns.WhatsNew
	local tab = ns.UI.main.tabButtons[5]
	check("Changelog is the tab after Sales", tab.key, "changelog")
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
	C_AuctionHouse.PostCommodity({ itemID = 1 }, 2, 3)
	time = function() return realTime() + 120 end
	C_AuctionHouse.PostCommodity({ itemID = 3 }, 2, 5)
	C_AuctionHouse.PostItem({ itemID = 1 }, 2, 1)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")
	check("failed post dropped", ns.db.sales.lots[1].itemID, 3)
	check("its quantity", ns.db.sales.lots[1].qty, 5)
	Fire("AUCTION_HOUSE_AUCTION_CREATED")
	check("second post matched", ns.db.sales.lots[2].itemID, 1)
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
		GetContainerNumSlots = function(bag) return bag == 0 and #bags or 0 end,
		GetContainerItemInfo = function(_, slot) return bags[slot] end,
	}
	ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot, itemID = bags[slot].itemID } end }
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
	check("search sent", searches >= 1, true)
	check("items sort by buyout", lastSearch.sort, 4)
	check("items use the plain search", lastSearch.kind, "plain")

	-- Someone else sells at 500: posted at the same price, no undercut. Below break-even raises it instead.
	listings[shirt] = { { buyoutAmount = 700, containsOwnerItem = false }, { buyoutAmount = 500, containsOwnerItem = false } }
	Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = shirt })
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
	Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Test Sword.")
	local list, onItsWay, waiting, nextDue, rough = ns.Sales.Incoming()
	check("sold message noted", #list, 1)
	check("amount is the posted price after the cut", list[1].amount, 9500)
	check("posted item price is exact", rough, false)
	check("on its way", onItsWay, 9500)
	check("nothing waiting yet", waiting, 0)
	check("due in an hour", nextDue, base + 3600)
	check("sale said in chat", (said[1] or ""):find("Sold: Test Sword", 1, true) ~= nil, true)
	check("the post is left for the mail to match", #ns.db.sales.lots, 2)
	Fire("CHAT_MSG_SYSTEM", "You have learned a new spell.")
	check("other system messages ignored", #ns.Sales.Incoming(), 1)

	-- Stackable goods: the message doesn't say how many sold, so one unit, marked as an estimate.
	Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Test Ore.")
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
	Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Test Sword.")
	Fire("MAIL_SHOW")
	check("not yet due: kept", #ns.Sales.Incoming(), 1)

	ns.db.sales.incoming = {}
	ns.db.sales.lots = {}
	time, ns.Print = realTime, realPrint
end

-- Sales profit: what was paid for materials follows them through the craft to the sale.
do
	ns.db.sales.items, ns.db.sales.lots, ns.db.costs, ns.db.costsSeeded = {}, {}, {}, 1
	Fire("COMMODITY_PRICE_UPDATED", 100, 1000)
	C_AuctionHouse.ConfirmCommoditiesPurchase(901, 10)
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	check("purchase recorded at the price paid", ns.db.costs[901].c, 1000)
	check("purchase units recorded", ns.db.costs[901].q, 10)

	-- 4 bought units and 2 gathered ones make one item.
	ns.db.recipes[9001] = { n = "Crafted Thing", o = 902, qmin = 1, qmax = 1, r = { { 4, 901 }, { 2, 903 } } }
	ns.db.chars[me].recipes[9001] = true
	ns.Sales.ForgetCraftInfo()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 9001)
	check("craft takes its materials' cost", ns.db.costs[901].c, 600)
	check("craft result carries the cost", ns.db.costs[902].c, 400)

	local now = os.time()
	ns.Sales.Record("sold", "Crafted Thing", 1, 950, now, me, 902)
	local thing = ns.Sales.Item("crafted thing")
	local profit, rough, sold, _, gold = ns.Sales.Profit(thing, 1)
	check("profit is the sale less what was paid", profit, 550)
	check("known cost isn't an estimate", rough, false)
	check("sale still counted", sold == 1 and gold == 950, true)
	check("sold unit leaves the cost record", ns.db.costs[902], nil)

	-- Something that isn't crafted: listed only when everything is asked for, and all profit when gathered.
	ns.Sales.Record("sold", "Spare Ore", 1, 100, now, me, 903)
	check("only crafts by default", #ns.Sales.AllItems(false), 1)
	check("everything on request", #ns.Sales.AllItems(true), 2)
	check("totals: crafts only", select(4, ns.Sales.Totals(1, false)), 550)
	check("totals: everything", select(4, ns.Sales.Totals(1, true)), 650)

	-- Money on its way counts before its mail is read, at the cost on record.
	ns.Sales.AddCost(902, 1, 400)
	table.insert(ns.db.sales.incoming, { name = "Crafted Thing", itemID = 902, char = me, at = now, due = now + 3600, amount = 950 })
	table.insert(ns.db.sales.incoming, { name = "New Thing", itemID = 905, char = me, at = now, due = now + 3600, amount = 70 })
	check("money on its way is in the item's profit", (ns.Sales.Profit(thing, 1)), 1100)
	check("money on its way is in the totals", select(4, ns.Sales.Totals(1, true)), 1270)
	check("sale on its way doesn't use up the cost", ns.db.costs[902].c, 400)
	ns.db.sales.incoming = {}
	ns.db.costs[902] = nil

	-- Results from before profit was counted stay out of it, and out of the list.
	ns.Sales.Record("sold", "Old Thing", 3, 900, now, me, 904)
	for _, day in pairs(ns.Sales.Item("old thing").days) do day.x = true end
	check("earlier sales not listed", #ns.Sales.AllItems(true), 2)
	check("earlier sales not in the profit", select(4, ns.Sales.Totals(nil, true)), 650)
	check("earlier sales kept for the history", ns.Sales.Item("old thing").sold, 3)
	ns.db.sales.items["old thing"] = nil

	-- A crafted item sold with no cost on record is marked as an estimate.
	ns.Sales.Record("sold", "Crafted Thing", 1, 950, now, me, 902)
	check("no cost on record: estimate", select(2, ns.Sales.Profit(thing, 1)), true)

	ns.UI.Show("sales")
	local window = ns.UI.windows.sales
	check("sales list: header and the crafted item", #window.list, 2)
	window.everything.GetChecked = function() return true end
	window.everything.scripts.OnClick(window.everything)
	check("box ticked: everything listed", #window.list, 3)
	ns.db.ui.salesEverything = nil
	ns.UI.Hide()

	ns.db.recipes[9001], ns.db.chars[me].recipes[9001] = nil, nil
	ns.db.sales.items, ns.db.costs = {}, {}
	ns.Sales.ForgetCraftInfo()
	RunTimers()
end

-- Minimap button: without the broker libraries it's the add-on's own button, under the name collectors look for.
do
	local mini = ns.MinimapButton
	check("own minimap button without the libraries", mini.Kind(), "own")
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

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
