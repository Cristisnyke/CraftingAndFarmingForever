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

ns.plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, cost = 0 }

local function RebuildPlan()
	ns.plan = ns.Planner.BuildPlan(NewContext(), ns.db.queue)
	if ns.Shopping then ns.Shopping.Sync() end
	if ns.UI then ns.UI.RefreshQueue() end
end

function ns.RequestPlan()
	ns.Debounce("plan", 0.5, RebuildPlan)
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
	-- Prices change when a scan finishes; stock on alts changes when Syndicator refreshes its cache.
	Auctionator.API.v1.RegisterForDBUpdate(ns.name, function()
		ns.InvalidateProfit()
		ns.RequestPlan()
	end)
	local registry = _G.Syndicator and _G.Syndicator.CallbackRegistry
	if registry and registry.RegisterCallback then
		pcall(registry.RegisterCallback, registry, "BagCacheUpdate", ns.RequestPlan, ns)
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
	local base = Recipes.ProfessionInfo()
	return Recipes.Read(recipeID, info, base and base.professionID, base and base.professionName) ~= nil
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
		if entry.recipeID == recipeID and entry.char == char then
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
	if #ns.plan.crafts == 0 then return nil, nil, "The queue is empty." end
	local me = ns.CharKey()
	local openProfession = Recipes.OpenProfession()
	local reason
	for _, craft in ipairs(ns.plan.crafts) do
		local recipe = ns.db.recipes[craft.recipeID]
		if craft.char ~= me then
			reason = reason or ("Next craft is on " .. ns.CharLabel(craft.char) .. ".")
		elseif openProfession ~= recipe.p then
			reason = reason or ("Open " .. (recipe.pn or "the profession") .. " to continue.")
		else
			local available = C_TradeSkillUI.GetCraftableCount(craft.recipeID) or 0
			if available > 0 then
				return craft, math.min(craft.count, available)
			end
			reason = reason or "Materials are missing. See the lists below."
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
