-- Crafting and Farming Forever :: Queue
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
		bankStock = ns.Stock.Bank,
		mailStock = ns.Stock.Mail,
		altStock = ns.Stock.Alts,
		crafter = Recipes.Crafter,
		-- The plan is for the logged-in character: other characters' queued crafts are theirs to do.
		me = ns.CharKey(),
		knows = Recipes.Knows,
		charName = function(key) return ns.db.chars[key] and ns.db.chars[key].name end,
		ahCut = ns.AH_CUT,
	})
end
ns.NewContext = NewContext

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------

ns.plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, bank = {}, mail = {}, farm = {}, smelt = {}, cost = 0, elsewhere = {} }
ns.farmPlan = ns.plan
ns.totals = { revenue = 0, cost = 0, net = 0, counted = 0, excluded = 0, entries = {}, bound = 0, boundCost = 0, boundEntries = {} }

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
	ns.UI.FarmModeChanged()
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

-- Sets an entry to an exact number of crafts, typed in its box. 0 removes it.
function Queue.Set(index, qty)
	local entry = ns.db.queue[index]
	if not entry then return end
	entry.qty = math.max(0, math.floor(qty))
	if entry.qty == 0 then table.remove(ns.db.queue, index) end
	ns.RequestPlan()
end

-- Removes every entry that would lose money at current prices. Worked out afresh, so it can't remove the wrong
-- entries if the queue changed since the window last drew. Returns how many went.
function Queue.RemoveLosing()
	local totals = ns.Planner.QueueTotals(NewContext(), ns.db.queue, ns.Items.CanSellOnAH)
	local removed = 0
	for index = #ns.db.queue, 1, -1 do
		local net = totals.entries[index]
		if net and net < 0 then
			table.remove(ns.db.queue, index)
			removed = removed + 1
		end
	end
	if removed > 0 then ns.RequestPlan() end
	return removed
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

Queue.QUOTE_MARGIN_MAX = 1000

-- The quote margin in percent, set in the Queue footer.
function Queue.QuoteMargin()
	return ns.db.ui.quoteMargin or 10
end

function Queue.SetQuoteMargin(percent)
	ns.db.ui.quoteMargin = math.max(0, math.min(Queue.QUOTE_MARGIN_MAX, math.floor(percent)))
end

-- What a craft is called in a whisper: a clickable link where the client has one, otherwise the name.
local function QuoteLabel(recipeID, recipe)
	if recipe.o then
		local name, link = C_Item.GetItemInfo(recipe.o)
		return link or name or recipe.n or "Item"
	end
	local link = C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(recipeID)
	return link or recipe.n or "Craft"
end

-- The price for the whole order: material cost of every craft at current prices, plus the margin, rounded to
-- whole copper. Also the material cost on its own. Nil if a material has no price.
function Queue.QuotePrice(recipeID, crafts)
	local cost = ns.Planner.RecipeCost(NewContext(), recipeID)
	if not cost then return nil end
	cost = cost * math.max(1, crafts or 1)
	return math.floor(cost * (1 + Queue.QuoteMargin() / 100) + 0.5), cost
end

-- "[Healing Potion] x20: 5g 20s" for the whole order. The count is items made, so a recipe that makes 5 queued
-- twice says x10. Nil if a material has no price.
function Queue.QuoteText(recipeID, crafts)
	local recipe = ns.db.recipes[recipeID]
	if not recipe then return nil end
	crafts = math.max(1, crafts or 1)
	local price = Queue.QuotePrice(recipeID, crafts)
	if not price then return nil end
	return ("%s x%d: %s"):format(QuoteLabel(recipeID, recipe), crafts * (recipe.qmin or 1), ns.Money(price))
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

Restock.DefaultGoal = DefaultGoal

-- True when the player set this item's goal; false when it follows the default for its kind.
function Restock.IsCustom(itemID)
	return ns.db.restock.goals[itemID] ~= nil
end

function Restock.ResetGoal(itemID)
	ns.db.restock.goals[itemID] = nil
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

-- Returns the next craft this character can do now, with its batch size; or nil, the reason why not, and the craft
-- that has to be finished first. Strictly in plan order: sub-crafts come before what they're for, and a craft that
-- can't be made right now is never skipped for a later one, so you finish one step before moving on.
function Queue.NextCraft()
	local plan = ns.ActivePlan()
	if #plan.crafts == 0 then
		local others = {}
		for char in pairs(plan.elsewhere or {}) do table.insert(others, ns.CharLabel(char)) end
		table.sort(others)
		if #others > 0 then return nil, nil, "Nothing left to craft here. Log in to " .. table.concat(others, " or ") .. "." end
		return nil, nil, "The queue is empty."
	end
	local me = ns.CharKey()
	local craft = plan.crafts[1]
	for _, candidate in ipairs(plan.crafts) do
		if candidate.char == me then
			craft = candidate
			break
		end
	end
	if craft.char ~= me then return nil, nil, "Next craft is on " .. ns.CharLabel(craft.char) .. ".", craft end
	local recipe = ns.db.recipes[craft.recipeID]
	local name = (recipe and recipe.n) or "the next craft"
	local left = ("%s (%d left)"):format(name, craft.count)
	if not Recipes.OpenRecipes()[craft.recipeID] then
		return nil, nil, ("Open %s to finish %s."):format((recipe and recipe.pn) or "the profession", left), craft
	end
	local available = C_TradeSkillUI.GetCraftableCount(craft.recipeID) or 0
	local unmet = Recipes.UnmetRequirements(craft.recipeID)
	if available > 0 and #unmet == 0 then return craft, math.min(craft.count, available) end
	local needs = {}
	if available <= 0 then table.insert(needs, "materials") end
	if #unmet > 0 then table.insert(needs, table.concat(unmet, ", ")) end
	return nil, nil, ("Finish %s first: needs %s."):format(left, table.concat(needs, " and ")), craft
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

---------------------------------------------------------------------------
-- Craft timing: how long the current recipe and all crafts still take
---------------------------------------------------------------------------

-- One craft = its cast plus the short pause before the next cast of a batch. Casts are measured on every craft
-- (they change with haste); until a recipe has been cast once, its spell's cast time stands in.
Queue.DEFAULT_CAST = 2
Queue.DEFAULT_GAP = 0.25
local MAX_GAP = 3 -- a longer pause between two casts isn't part of a batch

local cast    -- { recipeID, start, finish } in GetTime() seconds, while a recipe is being cast
local run     -- { recipeID, total, done }: the crafts of one recipe you're working through
local overall -- { total = seconds }: all crafts, from when you started, for the "all crafts" fill
local lastDone -- { recipeID, at }

local function SpellCastSeconds(recipeID)
	local ms
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(recipeID)
		ms = type(info) == "table" and info.castTime or nil
	elseif GetSpellInfo then
		ms = select(4, GetSpellInfo(recipeID))
	end
	if type(ms) == "number" and ms > 0 then return ms / 1000 end
end

function Queue.CraftSeconds(recipeID)
	local times = ns.db.craftTimes
	local castSeconds = (times and times[recipeID]) or SpellCastSeconds(recipeID) or Queue.DEFAULT_CAST
	return castSeconds + (ns.db.craftGap or Queue.DEFAULT_GAP)
end

-- This character's crafts of the recipe still in the plan, or nil.
local function PlanCount(recipeID)
	local me = ns.CharKey()
	for _, craft in ipairs(ns.ActivePlan().crafts) do
		if craft.recipeID == recipeID and craft.char == me then return craft.count end
	end
end

local function Changed()
	if ns.UI and ns.UI.UpdateCraftBars then ns.UI.UpdateCraftBars() end
end

local function IsCraft(unit, spellID)
	if unit ~= "player" then return false end
	if issecretvalue and issecretvalue(spellID) then return false end
	return ns.db and ns.db.recipes[spellID] ~= nil
end

ns.On("UNIT_SPELLCAST_START", function(unit, _, spellID)
	if not IsCraft(unit, spellID) then return end
	local now = GetTime()
	local _, _, _, startMS, endMS = UnitCastingInfo("player")
	local start, finish = now, nil
	if type(startMS) == "number" and type(endMS) == "number" and endMS > startMS then
		start, finish = startMS / 1000, endMS / 1000
		ns.db.craftTimes = ns.db.craftTimes or {}
		ns.db.craftTimes[spellID] = finish - start
	end
	finish = finish or (start + Queue.CraftSeconds(spellID) - (ns.db.craftGap or Queue.DEFAULT_GAP))
	-- The pause after the last craft, when this cast carries on a batch: smoothed, one slow click barely moves it.
	if lastDone and start - lastDone.at >= 0 and start - lastDone.at < MAX_GAP then
		local gap = start - lastDone.at
		ns.db.craftGap = (ns.db.craftGap or Queue.DEFAULT_GAP) * 0.7 + gap * 0.3
	end
	cast = { recipeID = spellID, start = start, finish = finish }
	local planned = PlanCount(spellID)
	if not run or run.recipeID ~= spellID or run.done >= run.total then
		run = { recipeID = spellID, total = planned or 1, done = 0 }
	elseif planned and run.done + planned > run.total then
		run.total = run.done + planned -- more were queued meanwhile
	end
	Changed()
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if not IsCraft(unit, spellID) then return end
	if cast and cast.recipeID == spellID then cast = nil end
	if run and run.recipeID == spellID then run.done = run.done + 1 end
	lastDone = { recipeID = spellID, at = GetTime() }
	Changed()
end)

local function CastEnded(unit, _, spellID)
	if unit ~= "player" or not cast then return end
	if spellID and not (issecretvalue and issecretvalue(spellID)) and spellID ~= cast.recipeID then return end
	cast = nil
	Changed()
end
ns.On("UNIT_SPELLCAST_STOP", CastEnded)
ns.On("UNIT_SPELLCAST_FAILED", CastEnded)
ns.On("UNIT_SPELLCAST_INTERRUPTED", CastEnded)

-- Where the crafting stands, for the Craft Next bar:
--   casting      recipe being cast now, or nil;  castFraction 0..1
--   betweenCasts true for a moment after a craft of the recipe finished, when the batch's next cast is due
--   recipeID     the recipe being worked through (cast now, or paused in the middle of it), or nil
--   done, total  crafts of it finished / in all since you started on it
--   runSeconds   time left on that recipe, or nil
--   allSeconds, allCount   time and crafts left on everything this character crafts in the queue
--   allFraction  0..1 of all crafts done since you started crafting, or nil
function Queue.CraftProgress()
	local now = GetTime()
	local progress = {}
	local plan = ns.ActivePlan()
	if run then
		local planned = PlanCount(run.recipeID)
		local left = run.total - run.done
		-- The plan lags a moment behind each craft; a smaller plan count means it was finished another way.
		if planned and planned < left and not (cast and cast.recipeID == run.recipeID) then left = planned end
		if left <= 0 or (not planned and not cast) then
			run = nil
		else
			progress.recipeID, progress.done, progress.total = run.recipeID, run.total - left, run.total
		end
	end
	-- Just finished one of a batch: the next cast follows in a moment, so the bar shouldn't flicker to idle.
	progress.betweenCasts = not cast and progress.recipeID ~= nil and lastDone ~= nil
		and lastDone.recipeID == progress.recipeID and now - lastDone.at < 0.75
	local current
	if cast then
		local length = math.max(cast.finish - cast.start, 0.01)
		progress.casting = cast.recipeID
		progress.castFraction = math.min(math.max((now - cast.start) / length, 0), 1)
		local left = (run and run.recipeID == cast.recipeID) and (progress.total - progress.done) or 1
		current = { recipeID = cast.recipeID, left = math.max(left, 1), castLeft = cast.finish - now }
		if not progress.recipeID then progress.recipeID, progress.done, progress.total = cast.recipeID, 0, 1 end
	elseif progress.recipeID then
		current = { recipeID = progress.recipeID, left = progress.total - progress.done }
	end
	progress.runSeconds, progress.allSeconds, progress.allCount =
		ns.Planner.TimeLeft(plan.crafts, ns.CharKey(), Queue.CraftSeconds, current)
	-- The all-crafts fill starts with your first craft and ends when nothing's left; queuing more widens it
	-- without losing what's done.
	if progress.allCount == 0 then
		overall = nil
	elseif cast or overall then
		if not overall then
			overall = { total = progress.allSeconds, last = progress.allSeconds }
		elseif progress.allSeconds > overall.last + 0.5 then
			overall.total = overall.total + progress.allSeconds - overall.last
		end
		overall.last = progress.allSeconds
		progress.allFraction = math.min(math.max(1 - progress.allSeconds / math.max(overall.total, 0.01), 0), 1)
	end
	return progress
end
