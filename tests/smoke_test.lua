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
		if key == "professionID" then return nil end -- add-on data on a frame, not a method
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
			GetHeight = function(self) return self.height end,
			GetLeft = function() return 100 end,
			GetRight = function() return 480 end,
			GetTop = function() return 900 end,
			SetText = function(self, text) self.text = text end,
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
function StaticPopup_Show(name) ns_popup = name end
function StaticPopup_Hide() end
SlashCmdList = {}
Enum = { CraftingReagentType = { Basic = 0 } }
print = print

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
		return { InsertItem = function(_, s) table.insert(lists[name], s) end }
	end,
}
Auctionator = {
	SavedState = { TimeOfLastBrowseScan = os.time() - 90000 },
	State = {},
	Config = { Options = { REPLICATE_SCAN = "r" }, Get = function() return false end },
	Shopping = { ListManager = listManager },
	API = { v1 = {
		GetAuctionPriceByItemID = function(_, id) return prices[id] end,
		GetVendorPriceByItemID = function(_, id) return id == 3 and 10 or nil end,
		GetAuctionAgeByItemID = function() return 0 end,
		RegisterForDBUpdate = function() end,
		ConvertToSearchString = function(_, t) return ('"%s";;;;;;;;;;;#;;%d'):format(t.searchString, t.quantity) end,
		GetShoppingListItems = function(_, name) return lists[name] end,
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
check("list has one AH item", #lists[ns.LIST_NAME], 1)
check("list search string", lists[ns.LIST_NAME][1], '"Linen Cloth";;;;;;;;;;;#;;9')

-- Bought 4 cloth: same row is altered, list isn't recreated.
C_Item.GetItemCount = function(id) return id == 1 and 7 or 0 end
Fire("BAG_UPDATE_DELAYED")
check("no recreate on update", createCalls, 1)
check("quantity updated in place", lists[ns.LIST_NAME][1], '"Linen Cloth";;;;;;;;;;;#;;5')

-- Panel, profit: bind-on-pickup results are hidden, sale items ranked.
ns.UI.Show("profit")
ns.InvalidateProfit()
local sellable = {}
for _, result in ipairs(ns.UI.ComputeProfit()) do sellable[result.recipeID] = result end
check("bind-on-pickup result hidden", sellable[30], nil)
check("sellable result listed", sellable[20] ~= nil, true)
check("sub-craft cost used in profit", sellable[20].cost, 3 * 20 + 10)

-- Tabs and craft button.
ns.UI.Show("queue")
check("windows are separate", ns.UI.windows.profit.frame ~= ns.UI.windows.queue.frame, true)
check("both open", ns.UI.windows.profit.frame:IsShown() and ns.UI.windows.queue.frame:IsShown(), true)
ns.UI.windows.queue.frame.scripts.OnDragStop(ns.UI.windows.queue.frame)
check("moved window keeps its position", ns.db.ui.positions.queue.x, 100)
check("other window not moved", ns.db.ui.positions.profit, nil)
ns.UI.Toggle("profit")
check("closing profit leaves queue open", ns.UI.windows.queue.frame:IsShown(), true)
ns.UI.Toggle("profit")

-- Totals: 2 shirts sell for 1000 each less 5%; each costs 3 bolts at 20 (crafted) + thread 10 = 70.
check("queue total profit", ns.totals.net, 2 * (950 - 70))
check("queue total revenue", ns.totals.revenue, 1900)
check("per-entry profit", ns.totals.entries[1], 1760)

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
check("restock window opens", ns.UI.windows.restock.frame:IsShown(), true)
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

-- Refresh: picks up changed prices, stock and recipes right away, without being asked to wait for an event.
ns.Queue.Add(10, 1)
RunTimers()
prices[2] = 777
ns.db.recipes[10].n = "Stale name"
C_Item.GetItemCount = function() return 0 end
local queriedAuctions = 0
C_AuctionHouse = {
	IsThrottledMessageSystemReady = function() return true end,
	QueryOwnedAuctions = function() queriedAuctions = queriedAuctions + 1 end,
}
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

-- Stale prompt at the AH.
AuctionHouseFrame:Show()
Fire("AUCTION_HOUSE_SHOW")
check("stale scan prompts", ns_popup, "CRAFTLEDGER_SCAN")

-- Slash commands.
for _, command in ipairs({ "", "", "queue", "profit", "restock", "refresh", "auto", "auto", "clear", "diag", "bogus" }) do
	SlashCmdList.CRAFTLEDGER(command)
end
RunTimers()

-- Late saved data: the session's queue is merged into the table the client hands over.
ns.Queue.Add(10, 1)
CraftLedgerDB = { queue = { { recipeID = 30, qty = 1, char = me } }, recipes = {}, chars = {}, ui = {} }
RunTimers()
Fire("PLAYER_LOGOUT")
check("late data adopted", ns.db, CraftLedgerDB)
check("session queue merged", #ns.db.queue, 2)

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
