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
		if key == "professionID" or key == "data" then return nil end -- add-on data on a frame, not a method
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
function IsShiftKeyDown() return false end
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
	GetRecipeInfo = function(id) return { recipeID = id, learned = id ~= 40, name = "Recipe" .. id } end,
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
ProfessionsFrame.GetProfessionInfo = function() return { professionID = 197, professionName = "Tailoring" } end
ProfessionsFrame.CraftingPage = page
AuctionHouseFrame = NewFrame()

---------------------------------------------------------------------------
-- Load the add-on
---------------------------------------------------------------------------

local ns = {}
for line in io.lines("CraftLedger.toc") do
	if line:match("%.lua$") then
		local chunk = assert(loadfile(line))
		chunk("CraftLedger", ns)
	end
end

local function Fire(event, ...)
	for frame in pairs(eventFrames) do
		if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
	end
	RunTimers()
end

---------------------------------------------------------------------------
-- Flow
---------------------------------------------------------------------------

Fire("ADDON_LOADED", "CraftLedger")
Fire("PLAYER_LOGIN")
check("no list before anything is queued", lists[ns.LIST_NAME], nil)

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
check("list has the material and the queued item", #lists[ns.LIST_NAME], 2)
check("queued item listed with no quantity", lists[ns.LIST_NAME][2], '"Linen Shirt";;;;;;;;;;;#;;')
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
		if row.data and row.data.kind == "queue" then return row.right.text end
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
check("sale drop is red", entryText:find("sells " .. RED .. "was 10s 00c, now 2s 00c|r", 1, true) ~= nil, true)
Rescan({ [4] = 300 })
check("sale rise is green", QueueEntryText():find("sells " .. GREEN, 1, true) ~= nil, true)
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

-- Totals: 2 shirts sell for 1000 each less 5%; each costs 3 bolts at 20 (crafted) + thread 10 = 70.
check("queue total profit", ns.totals.net, 2 * (950 - 70))
check("queue total revenue", ns.totals.revenue, 1900)
check("per-entry profit", ns.totals.entries[1], 1760)

-- Quote: material cost of one craft plus 10%, filled into a reply, never sent. 3 bolts at 20c + thread 10c = 70c.
check("quote text", ns.Queue.QuoteText(20), "link: materials 70c + 10% = 77c")
local function QueueRow()
	for _, row in ipairs(ns.UI.windows.queue.rows) do
		if row.data and row.data.kind == "queue" then return row end
	end
end
ns.UI.Refresh("queue")
check("material cost on the row", QueueRow().right.text:find("mats 70c", 1, true) ~= nil, true)
check("quote button shown", QueueRow().quote:IsShown(), true)
local chatBefore = #sentChat
function ChatEdit_GetLastTellTarget() return "Customer-Realm" end
QueueRow().quote.scripts.OnClick(QueueRow().quote)
check("quote fills a whisper to the last sender", chatBoxText, "/w Customer-Realm link: materials 70c + 10% = 77c")
check("quote isn't sent", #sentChat, chatBefore)
ChatEdit_GetLastTellTarget = function() return nil end
QueueRow().quote.scripts.OnClick(QueueRow().quote)
check("quote with no known sender uses reply", chatBoxText, "/r link: materials 70c + 10% = 77c")
ChatEdit_GetLastTellTarget = nil

-- A recipe with no item, such as an enchant, can still be quoted; a missing price isn't.
ns.db.recipes[600] = { n = "Enchant Boots", qmin = 1, qmax = 1, r = { { 1, 1 } } }
check("no-item recipe quote", ns.Queue.QuoteText(600), "Enchant Boots: materials 10c + 10% = 11c")
ns.db.recipes[601] = { n = "Unpriced", qmin = 1, qmax = 1, r = { { 1, 77777 } } }
check("no price no quote", ns.Queue.QuoteText(601), nil)
ns.db.recipes[602] = { n = "Batch", qmin = 5, qmax = 5, r = { { 1, 1 } } }
check("batch recipe says how many", ns.Queue.QuoteText(602), "Batch (makes 5): materials 10c + 10% = 11c")
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
local _, _, reason = nil, nil, nil
C_TradeSkillUI.GetCraftableCount = function() return 0 end
_, _, reason = ns.Queue.NextCraft()
check("no materials reason", reason, "Recipe10 needs: materials.")
C_TradeSkillUI.GetRecipeRequirements = function() return { { name = "Anvil", met = false } } end
_, _, reason = ns.Queue.NextCraft()
check("station reason", reason, "Recipe10 needs: materials and Anvil.")
C_TradeSkillUI.GetCraftableCount = function(id) return id == 10 and 5 or 0 end
_, _, reason = ns.Queue.NextCraft()
check("station blocks craft", reason, "Recipe10 needs: Anvil.")
ProfessionsFrame.GetProfessionInfo = realInfo
C_TradeSkillUI.GetRecipeRequirements = nil

-- A recipe that isn't in the open window does ask for its profession.
local realIDs = C_TradeSkillUI.GetAllRecipeIDs
C_TradeSkillUI.GetAllRecipeIDs = function() return { 40 } end
_, _, reason = ns.Queue.NextCraft()
check("other profession reason", reason, "Open Tailoring to continue.")
C_TradeSkillUI.GetAllRecipeIDs = realIDs

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
check("tab filters to its profession", #list, 1)
check("tab shows its item", list[1].result.recipeID, 500)
tabs[1].scripts.OnClick(tabs[1])
check("All tab shows everything", #ns.UI.windows.profit.list > 1, true)
Fire("TRADE_SKILL_LIST_UPDATE")
check("clicked tab stays selected", #ns.UI.windows.profit.list > 1, true)

-- Profit search: the real box fires OnTextChanged on any text change, including its own SetText.
do
	local window = ns.UI.windows.profit
	local box = window.searchBox
	local function Search(text)
		box:SetText(text)
		box.scripts.OnTextChanged(box)
	end
	local everything = #window.list
	window.offset = 5
	Search("  BRONZE b ")
	check("search ignores case and outer spaces", #window.list, 1)
	check("search finds the item", window.list[1].result.recipeID, 500)
	check("search scrolls back to the top", window.offset, 0)
	Search("no such recipe at all")
	check("search can find nothing", #window.list, 0)
	Search("[")
	check("search text is not a pattern", #window.list, 0)
	ns.UI.SelectProfession("profit", 197)
	Search("bronze")
	check("search stays within the tab", #window.list, 0)
	check("empty tab points to the All tab", window.status.text, "No matches on this tab, 1 on the All tab.")
	ns.UI.SelectProfession("profit", 186)
	check("search survives a tab change", #window.list, 1)
	check("search reports its matches", window.status.text, "1 recipe matches your search.")
	ns.InvalidateProfit()
	check("search survives a price refresh", #window.list, 1)
	ns.UI.SelectProfession("profit", nil)
	box.scripts.OnEscapePressed(box)
	box.scripts.OnTextChanged(box)
	check("escape empties the box", box:GetText(), "")
	check("clearing shows everything again", #window.list, everything)
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
	check("profit row shows craft cost", profitRow.right.text, "craft cost " .. ns.Money(cost))
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
	check("queue row shows cost", queueRow.right.text:find("cost " .. ns.Money(cost), 1, true) ~= nil, true)
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
local s30, e30, g30 = ns.Sales.Counts(sword, 30)
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
check("best seller first", ns.UI.windows.sales.list[1].item.name, "Test Sword")
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

-- The button's name follows the tab.
ns.UI.Show("profit")
ns.UI.SelectProfession("profit", 197)
check("button named for profession", ns.UI.windows.profit.advertiseButton.text, "Advertise Tailoring")

-- Stale prompt at the AH.
AuctionHouseFrame:Show()
Fire("AUCTION_HOUSE_SHOW")
check("stale scan prompts", ns_popup, "CRAFTLEDGER_SCAN")

-- Slash commands.
for _, command in ipairs({ "", "", "queue", "profit", "restock", "sales", "refresh", "advertise", "auto", "auto", "clear", "diag", "bogus" }) do
	SlashCmdList.CRAFTLEDGER(command)
end
RunTimers()

-- Late saved data: the session's queue is merged into the table the client hands over.
ns.Queue.Add(10, 1)
CraftLedgerDB = { queue = { { recipeID = 30, qty = 1, char = me } }, recipes = {}, chars = {}, ui = {},
	sales = { seen = { someone = { { key = "sold|Copper Axe|2|500", expires = 1 }, { key = "sold|Copper Axe|500", expires = 1 } } } } }
RunTimers()
Fire("PLAYER_LOGOUT")
check("late data adopted", ns.db, CraftLedgerDB)
check("old mail record loses its count", ns.db.sales.seen.someone[1].key, "sold|Copper Axe|500")
check("new mail record left alone", ns.db.sales.seen.someone[2].key, "sold|Copper Axe|500")
ns.db.sales.seen.someone = nil
check("session queue merged", #ns.db.queue, 2)

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
group, line = ns.Farm.Describe(2770)
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
	ns.ToggleFarmMode()
	check("toggle uses the farm plan", ns.ActivePlan(), ns.farmPlan)
	check("toggle keeps the buy plan", ns.plan.buy[1], buyList)
	check("farm plan buys nothing at AH", next(ns.farmPlan.buy), nil)
	check("farm plan lists what to gather", next(ns.farmPlan.farm) ~= nil, true)

	local farm, queue = ns.UI.windows.farm, ns.UI.windows.queue
	check("main window makes way", ns.UI.IsOpen(), false)
	check("small list opens", farm.frame:IsShown(), true)
	local count = 0
	for _ in pairs(ns.farmPlan.farm) do count = count + 1 end
	check("each item says how to get it", #Rows("farm", "how"), count)
	check("small list has no price rows", #Rows("farm", "header"), 0)
	check("small list height follows it", farm.frame:GetHeight() < 200, true)
	check("small list is narrow", farm.frame:GetWidth() < ns.UI.main.frame:GetWidth() / 2, true)
	for _, row in ipairs(farm.rows) do
		if row.data and row.data.kind == "how" then row.scripts.OnEnter(row) break end
	end
	check("farm choice is remembered", ns.db.ui.farmMode, true)

	-- The profession window can bring the full Queue back while farming, for Craft Next.
	ns.UI.Show("queue")
	check("full list also follows the farm plan", #Rows("queue", "how"), count)
	ns.UI.Hide()

	ns.ToggleFarmMode()
	check("Back returns to buying", ns.ActivePlan(), ns.plan)
	check("Back closes the small list", farm.frame:IsShown(), false)
	check("Back reopens the Queue", queue.frame:IsVisible(), true)
	check("how rows gone when buying", #Rows("queue", "how"), 0)

	ns.ToggleFarmMode()
	farm.close.scripts.OnClick(farm.close)
	check("closing leaves farm mode", ns.ActivePlan(), ns.plan)
	check("closing hides the small list", farm.frame:IsShown(), false)
	ns.UI.ToggleMain()
	ns.UI.Show("farm")
	ns.UI.ToggleMain()
	check("hide-all leaves the small list alone", farm.frame:IsShown(), true)
	farm.frame:Hide()

	ns.Queue.Clear()
	RunTimers()
	ns.db.ui.farmMode = true
	ns.UI.Show("farm")
	check("empty queue says so", Rows("farm", "note")[1].text, "The queue is empty.")
	farm.close.scripts.OnClick(farm.close)
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

-- The small Farm list includes smelting, so it can't say all gathered while bars are still to make.
do
	ns.db.ui.farmMode = true
	local realPlan = ns.farmPlan
	ns.farmPlan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, farm = {}, smelt = { [2840] = 4 }, cost = 0 }
	ns.UI.Show("farm")
	local kinds = {}
	for _, data in ipairs(ns.UI.windows.farm.list) do kinds[data.kind] = (kinds[data.kind] or 0) + 1 end
	check("smelting listed", ns.UI.windows.farm.list[1].itemID, 2840)
	check("says how", ns.UI.windows.farm.list[2].text, "Smelt with Mining")
	ns.UI.windows.farm.frame:Hide()
	ns.farmPlan = realPlan
	ns.db.ui.farmMode = nil
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

	-- Someone else sells at 500: an item can't have copper, so 1s under. Below break-even raises it instead.
	listings[shirt] = { { buyoutAmount = 700, containsOwnerItem = false }, { buyoutAmount = 500, containsOwnerItem = false } }
	Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = shirt })
	local posted = #posts
	ns.Posting.PostSelected()
	check("posted", #posts, posted + 1)
	local last = posts[#posts]
	check("item undercut by 1s", last.price, 400)
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
	check("own listing isn't undercut", posts[#posts].price, 400)
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
		check("commodity undercut by 1c", posts[commodityPosts + 1].price, 499)
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
		check("below vendor asks first", ns_popup, "CRAFTLEDGER_BELOW_VENDOR")
		check("below vendor not posted yet", #posts, count)
		local dialog = StaticPopupDialogs.CRAFTLEDGER_BELOW_VENDOR
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

	-- The log keeps requests with what the server said after them, and can't break a post.
	check("posts are logged", (function()
		for _, line in ipairs(ns.db.auctionLog) do
			if line:find("PostItem(2,", 1, true) then return true end
		end
		return false
	end)(), true)
	check("searches are logged", (function()
		for _, line in ipairs(ns.db.auctionLog) do
			if line:find("SendSellSearchQuery(item", 1, true) then return true end
		end
		return false
	end)(), true)
	check("log stays short", #ns.db.auctionLog <= 60, true)

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

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
