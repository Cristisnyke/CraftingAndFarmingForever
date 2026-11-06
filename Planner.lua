-- CraftLedger :: Planner
-- Game-independent cost, profit and queue logic, so it can be tested outside the client.
--
-- A context supplies:
--   recipes[recipeID]  = { o, qmin, qmax, r = { { qty, itemID, altItemID, ... }, ... } }
--   known[itemID]      = { recipeID, ... }   learned recipes that make the item, on any character
--   ahPrice(itemID)    -> copper or nil
--   vendorPrice(itemID)-> copper or nil
--   ahCut              = 0.05
-- and, for planning:
--   ownStock(itemID)   -> count on the current character (bags + bank)
--   altStock(itemID)   -> { { name = label, count = n }, ... }
--   crafter(recipeID, preferredChar) -> character key

local _, ns = ...
ns = ns or {}
local Planner = {}
ns.Planner = Planner

local function AverageYield(recipe)
	local qmin = recipe.qmin or 1
	local qmax = recipe.qmax or qmin
	local avg = (qmin + qmax) / 2
	return avg > 0 and avg or 1
end

local function MinimumYield(recipe)
	local qmin = recipe.qmin or 1
	return qmin > 0 and qmin or 1
end

function Planner.NewContext(ctx)
	ctx.ahCut = ctx.ahCut or 0.05
	ctx.costMemo = {}
	ctx.visiting = {}
	ctx.cycleHits = 0
	return ctx
end

-- Cheapest way to get one unit of an item: unit price, "ah" | "vendor" | "craft", recipeID when crafted.
function Planner.ItemCost(ctx, itemID)
	local memo = ctx.costMemo[itemID]
	if memo then return memo.unit, memo.kind, memo.recipeID end

	local hitsBefore = ctx.cycleHits
	local ah, vendor = ctx.ahPrice(itemID), ctx.vendorPrice(itemID)
	local unit, kind, recipeID
	if ah then unit, kind = ah, "ah" end
	if vendor and (not unit or vendor < unit) then unit, kind = vendor, "vendor" end

	for _, candidate in ipairs(ctx.known[itemID] or {}) do
		if ctx.visiting[candidate] then
			ctx.cycleHits = ctx.cycleHits + 1
		else
			local recipe = ctx.recipes[candidate]
			local total = recipe and Planner.RecipeCost(ctx, candidate)
			if total then
				local craftUnit = total / AverageYield(recipe)
				if not unit or craftUnit < unit then
					unit, kind, recipeID = craftUnit, "craft", candidate
				end
			end
		end
	end

	-- A result found while a recipe chain was cut short by a cycle is only valid inside that chain.
	if ctx.cycleHits == hitsBefore then
		ctx.costMemo[itemID] = { unit = unit, kind = kind, recipeID = recipeID }
	end
	return unit, kind, recipeID
end

-- Cost of one craft. Returns total, parts; total is nil when a required material has no price.
function Planner.RecipeCost(ctx, recipeID)
	local recipe = ctx.recipes[recipeID]
	if not recipe then return nil, {} end
	ctx.visiting[recipeID] = true
	local total, parts = 0, {}
	for _, slot in ipairs(recipe.r or {}) do
		local qty = slot[1] or 1
		local bestUnit, bestKind, bestID, bestRecipe
		for i = 2, #slot do
			local unit, kind, subRecipe = Planner.ItemCost(ctx, slot[i])
			if unit and (not bestUnit or unit < bestUnit) then
				bestUnit, bestKind, bestID, bestRecipe = unit, kind, slot[i], subRecipe
			end
		end
		parts[#parts + 1] = { itemID = bestID or slot[2], qty = qty, unit = bestUnit, kind = bestKind, recipeID = bestRecipe }
		if bestUnit then
			if total then total = total + bestUnit * qty end
		else
			total = nil
		end
	end
	ctx.visiting[recipeID] = nil
	return total, parts
end

-- Economics of selling the result of a recipe on the auction house.
function Planner.Profit(ctx, recipeID)
	local recipe = ctx.recipes[recipeID]
	if not recipe or not recipe.o then return nil end
	local cost, parts = Planner.RecipeCost(ctx, recipeID)
	local yield = AverageYield(recipe)
	local saleUnit = ctx.ahPrice(recipe.o)
	local result = { recipeID = recipeID, itemID = recipe.o, yield = yield, cost = cost, parts = parts, saleUnit = saleUnit }
	if cost and saleUnit then
		result.net = saleUnit * yield * (1 - ctx.ahCut) - cost
		result.margin = cost > 0 and result.net / cost or nil
	end
	return result
end

-- Turns the queue into crafts (materials before the items that need them), purchases and alt pickups.
function Planner.BuildPlan(ctx, queue)
	local plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, cost = 0 }
	local own, alts = {}, {}
	local craftIndex = {}
	local active = {}

	local function OwnLeft(itemID)
		if own[itemID] == nil then own[itemID] = ctx.ownStock(itemID) or 0 end
		return own[itemID]
	end

	local function AltsLeft(itemID)
		if alts[itemID] == nil then
			alts[itemID] = {}
			for _, alt in ipairs(ctx.altStock(itemID) or {}) do
				table.insert(alts[itemID], { name = alt.name, count = alt.count })
			end
		end
		return alts[itemID]
	end

	-- Takes up to count of an item from stock, own first. Returns how many are still missing.
	local function TakeFromStock(itemID, count)
		local fromOwn = math.min(OwnLeft(itemID), count)
		own[itemID] = own[itemID] - fromOwn
		count = count - fromOwn
		for _, alt in ipairs(AltsLeft(itemID)) do
			if count <= 0 then break end
			local take = math.min(alt.count, count)
			if take > 0 then
				alt.count = alt.count - take
				count = count - take
				plan.fetch[alt.name] = plan.fetch[alt.name] or {}
				plan.fetch[alt.name][itemID] = (plan.fetch[alt.name][itemID] or 0) + take
			end
		end
		return count
	end

	local Require

	local function Acquire(itemID, count)
		local unit, kind, recipeID = Planner.ItemCost(ctx, itemID)
		if kind == "craft" and not active[recipeID] then
			local yield = MinimumYield(ctx.recipes[recipeID])
			local crafts = math.ceil(count / yield)
			Require(recipeID, crafts, nil, true)
			own[itemID] = OwnLeft(itemID) + crafts * yield - count
		elseif kind == "vendor" then
			plan.vendor[itemID] = (plan.vendor[itemID] or 0) + count
			plan.cost = plan.cost + unit * count
		else
			plan.buy[itemID] = (plan.buy[itemID] or 0) + count
			if kind == "ah" then
				plan.cost = plan.cost + unit * count
			else
				-- Cycle fallback or no price at all: still bought on the AH, at the known price if any.
				local ah = ctx.ahPrice(itemID)
				if ah then plan.cost = plan.cost + ah * count else plan.unpriced = true end
			end
		end
	end

	Require = function(recipeID, count, preferredChar, isAuto)
		local recipe = ctx.recipes[recipeID]
		if not recipe then return end
		active[recipeID] = (active[recipeID] or 0) + 1
		for _, slot in ipairs(recipe.r or {}) do
			local missing = (slot[1] or 1) * count
			for i = 2, #slot do
				if missing <= 0 then break end
				missing = TakeFromStock(slot[i], missing)
			end
			if missing > 0 then
				local bestID, bestUnit = slot[2], nil
				for i = 2, #slot do
					local unit = Planner.ItemCost(ctx, slot[i])
					if unit and (not bestUnit or unit < bestUnit) then bestID, bestUnit = slot[i], unit end
				end
				Acquire(bestID, missing)
			end
		end
		active[recipeID] = active[recipeID] - 1
		if active[recipeID] == 0 then active[recipeID] = nil end

		local char = ctx.crafter(recipeID, preferredChar)
		local key = tostring(recipeID) .. "|" .. tostring(char)
		local entry = craftIndex[key]
		if entry then
			entry.count = entry.count + count
			entry.auto = entry.auto and isAuto
		else
			entry = { recipeID = recipeID, count = count, char = char, auto = isAuto }
			craftIndex[key] = entry
			table.insert(plan.crafts, entry)
		end
	end

	for _, queued in ipairs(queue) do
		if (queued.qty or 0) > 0 then Require(queued.recipeID, queued.qty, queued.char, false) end
	end
	return plan
end

return Planner
