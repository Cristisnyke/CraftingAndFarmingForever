-- CraftLedger :: Queue
-- The shared craft queue, the plan derived from it and the Craft Next action.

local _, ns = ...

local Queue = {}
ns.Queue = Queue
local Recipes = ns.Recipes

local function NewContext()
	return ns.Planner.NewContext({
		recipes = ns.db.recipes,
		known = Recipes.KnownMap(),
		ahPrice = ns.Prices.AH,
		vendorPrice = ns.Prices.Vendor,
		ownStock = ns.Stock.Own,
		altStock = ns.Stock.Alts,
		crafter = Recipes.Crafter,
		ahCut = ns.AH_CUT,
	})
end
ns.NewContext = NewContext

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------

ns.plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, farm = {}, smelt = {}, cost = 0 }
ns.farmPlan = ns.plan
ns.totals = { revenue = 0, cost = 0, net = 0, counted = 0, excluded = 0, entries = {} }

local function RebuildPlan()
	local ctx = NewContext()
	ns.plan = ns.Planner.BuildPlan(ctx, ns.db.queue)
	ctx.smelting = ns.Farm.Smelting
	ns.farmPlan = ns.Planner.BuildPlan(ctx, ns.db.queue, true)
	ns.totals = ns.Planner.QueueTotals(ctx, ns.db.queue, ns.Items.CanSellOnAH)
	if ns.Shopping then ns.Shopping.Sync() end
	if ns.UI then ns.UI.RefreshQueue() end
end

-- The Refresh button: re-reads recipes, item data, prices and stock, rebuilds the plan and the shopping list and
-- redraws the windows. Your auctions can only be re-read at the auction house. Doesn't start a price scan, which
-- takes a while and is limited by the server, so that stays a separate choice.
function ns.RefreshEverything()
	ns.Items.Retry()
	Recipes.Rescan()
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse.IsThrottledMessageSystemReady() then
		C_AuctionHouse.QueryOwnedAuctions({})
	end
	ns.InvalidateProfit()
	RebuildPlan()
	ns.UI.RefreshAll()
end

-- The plan the Queue window and Craft Next follow. The shopping list always uses the buying plan.
function ns.ActivePlan()
	return ns.db.ui.farmMode and ns.farmPlan or ns.plan
end

function ns.ToggleFarmMode()
	ns.db.ui.farmMode = not ns.db.ui.farmMode or nil
	ns.UI.RefreshQueue()
end

function ns.RequestPlan()
	ns.Debounce("plan", 0.2, RebuildPlan)
end

function ns.OnDataChanged()
	ns.InvalidateProfit()
	ns.RequestPlan()
end

ns.On("BAG_UPDATE_DELAYED", ns.RequestPlan)
ns.On("BANKFRAME_OPENED", ns.RequestPlan)
ns.On("PLAYERBANKSLOTS_CHANGED", ns.RequestPlan)
ns.On("PLAYER_LOGIN", function()
	ns.CharRecord()
	-- Prices change when a scan finishes; stock on alts and auctions change when Syndicator refreshes its caches.
	Auctionator.API.v1.RegisterForDBUpdate(ns.name, function()
		ns.InvalidateProfit()
		ns.RequestPlan()
	end)
	local registry = _G.Syndicator and _G.Syndicator.CallbackRegistry
	if registry and registry.RegisterCallback then
		for _, event in ipairs({ "BagCacheUpdate", "MailCacheUpdate", "AuctionsCacheUpdate" }) do
			pcall(registry.RegisterCallback, registry, event, ns.RequestPlan, ns)
		end
	end
	ns.RequestPlan()
end)

---------------------------------------------------------------------------
-- Queue operations
---------------------------------------------------------------------------

-- Stores the recipe if it was not read yet, so a craft queued right after learning it still plans correctly.
local function EnsureRecipe(recipeID)
	if ns.db.recipes[recipeID] then return true end
	local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
	return Recipes.Read(recipeID, info, Recipes.OpenProfession()) ~= nil
end

function Queue.Add(recipeID, qty)
	qty = math.max(1, math.floor(qty or 1))
	if not EnsureRecipe(recipeID) then
		ns.Print("That recipe's data is not available yet. Open its profession and try again.")
		return
	end
	local me = ns.CharKey()
	local char = Recipes.Knows(me, recipeID) and me or Recipes.Crafter(recipeID, me)
	for _, entry in ipairs(ns.db.queue) do
		if entry.recipeID == recipeID and entry.char == char and not entry.restock then
			entry.qty = entry.qty + qty
			ns.RequestPlan()
			return
		end
	end
	table.insert(ns.db.queue, { recipeID = recipeID, qty = qty, char = char })
	ns.RequestPlan()
end

function Queue.Change(index, delta)
	local entry = ns.db.queue[index]
	if not entry then return end
	entry.qty = entry.qty + delta
	if entry.qty <= 0 then table.remove(ns.db.queue, index) end
	ns.RequestPlan()
end

function Queue.Remove(index)
	table.remove(ns.db.queue, index)
	ns.RequestPlan()
end

function Queue.Clear()
	wipe(ns.db.queue)
	ns.RequestPlan()
end

---------------------------------------------------------------------------
-- Price quotes
---------------------------------------------------------------------------

local QUOTE_CUT = 0.10

-- What a craft is called in a whisper: a clickable link where the client has one, otherwise the name.
local function QuoteLabel(recipeID, recipe)
	if recipe.o then
		local name, link = C_Item.GetItemInfo(recipe.o)
		return link or name or recipe.n or "Item"
	end
	local link = C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(recipeID)
	return link or recipe.n or "Craft"
end

-- "[Bronze Bar]: materials 5s 10c + 10% = 5s 61c", at current prices. Nil if a material has no price.
function Queue.QuoteText(recipeID)
	local recipe = ns.db.recipes[recipeID]
	if not recipe then return nil end
	local cost = ns.Planner.RecipeCost(NewContext(), recipeID)
	if not cost then return nil end
	local yield = (recipe.qmin or 1) > 1 and (" (makes " .. recipe.qmin .. ")") or ""
	return ("%s%s: materials %s + %d%% = %s"):format(QuoteLabel(recipeID, recipe), yield, ns.Money(cost),
		QUOTE_CUT * 100, ns.Money(cost * (1 + QUOTE_CUT)))
end

---------------------------------------------------------------------------
-- Restock
---------------------------------------------------------------------------

local Restock = {}
ns.Restock = Restock

local function DefaultGoal(itemID)
	local stackable = ns.Items.IsStackable(itemID)
	if stackable == nil then return nil end
	return stackable and ns.db.restock.stackGoal or ns.db.restock.singleGoal
end

function Restock.Goal(itemID)
	return ns.db.restock.goals[itemID] or DefaultGoal(itemID)
end

-- Stores a goal for one item. Matching the default clears it, so the item keeps following the default.
function Restock.SetGoal(itemID, goal)
	goal = math.max(0, goal)
	ns.db.restock.goals[itemID] = goal ~= DefaultGoal(itemID) and goal or nil
end

-- Units already planned by entries the user queued by hand. Earlier restock entries don't count: they get replaced.
local function ManualQueued()
	local queued = {}
	for _, entry in ipairs(ns.db.queue) do
		local recipe = ns.db.recipes[entry.recipeID]
		if not entry.restock and recipe and recipe.o then
			queued[recipe.o] = (queued[recipe.o] or 0) + entry.qty * (recipe.qmin or 1)
		end
	end
	return queued
end

function Restock.Rows()
	local queued = ManualQueued()
	return ns.Planner.RestockRows(NewContext(), {
		isSellable = ns.Items.CanSellOnAH,
		goal = Restock.Goal,
		stock = ns.Stock.ForRestock,
		queued = function(itemID) return queued[itemID] or 0 end,
		minProfit = ns.db.restock.minProfitSilver * 100,
	})
end

-- Replaces the previous restock entries of a profession (nil for all) with what these rows need now. Other
-- professions' restock entries and hand-queued entries aren't touched.
function Restock.Apply(rows, profession)
	local queue = ns.db.queue
	for index = #queue, 1, -1 do
		local recipe = ns.db.recipes[queue[index].recipeID]
		if queue[index].restock and (not profession or (recipe and recipe.p == profession)) then
			table.remove(queue, index)
		end
	end
	local added = 0
	for _, row in ipairs(rows) do
		if row.crafts > 0 then
			table.insert(queue, {
				recipeID = row.recipeID,
				qty = row.crafts,
				char = Recipes.Crafter(row.recipeID, ns.CharKey()),
				restock = true,
			})
			added = added + 1
		end
	end
	ns.RequestPlan()
	return added
end

-- Every finished craft counts down its queue entry, wherever it was started from.
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" then return end
	if issecretvalue and issecretvalue(spellID) then return end
	local me = ns.CharKey()
	local fallback
	for index, entry in ipairs(ns.db.queue) do
		if entry.recipeID == spellID then
			if entry.char == me then
				Queue.Change(index, -1)
				return
			end
			fallback = fallback or index
		end
	end
	if fallback then Queue.Change(fallback, -1) end
end)

---------------------------------------------------------------------------
-- Craft Next
---------------------------------------------------------------------------

-- Returns the next craft this character can do now, with its batch size; or nil and the reason why not.
function Queue.NextCraft()
	local plan = ns.ActivePlan()
	if #plan.crafts == 0 then return nil, nil, "The queue is empty." end
	local me = ns.CharKey()
	local openRecipes = Recipes.OpenRecipes()
	local reason
	for _, craft in ipairs(plan.crafts) do
		local recipe = ns.db.recipes[craft.recipeID]
		if craft.char ~= me then
			reason = reason or ("Next craft is on " .. ns.CharLabel(craft.char) .. ".")
		elseif not openRecipes[craft.recipeID] then
			reason = reason or ("Open " .. (recipe.pn or "the profession") .. " to continue.")
		else
			local available = C_TradeSkillUI.GetCraftableCount(craft.recipeID) or 0
			local unmet = Recipes.UnmetRequirements(craft.recipeID)
			if available > 0 and #unmet == 0 then
				return craft, math.min(craft.count, available)
			end
			local needs = {}
			if available <= 0 then table.insert(needs, "materials") end
			if #unmet > 0 then table.insert(needs, table.concat(unmet, ", ")) end
			reason = reason or ((recipe.n or "Next craft") .. " needs: " .. table.concat(needs, " and ") .. ".")
		end
	end
	return nil, nil, reason
end

function Queue.CraftNext()
	if UnitCastingInfo("player") then return end
	local craft, count, reason = Queue.NextCraft()
	if not craft then
		ns.Print(reason)
		return
	end
	C_TradeSkillUI.CraftRecipe(craft.recipeID, count)
end
