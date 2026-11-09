-- Crafting and Farming Forever :: Planner
-- Game-independent cost, profit and queue logic, so it can be tested outside the client.
--
-- A context supplies:
--   recipes[recipeID]  = { o, qmin, qmax, r = { { qty, itemID, altItemID, ... }, ... }, x = uses a currency }
--   known[itemID]      = { recipeID, ... }   learned recipes that make the item, on any character
--   ahPrice(itemID)    -> copper or nil
--   vendorPrice(itemID)-> copper or nil
--   ahCut              = 0.05
-- and, for planning:
--   ownStock(itemID)   -> count on the current character (bags + bank)
--   bankStock(itemID)  -> the part of ownStock that's in the bank (optional), so the plan can say to fetch it
--   altStock(itemID)   -> { { name = label, count = n }, ... }
--   crafter(recipeID, preferredChar) -> character key
--   smelting[itemID]   = { yield, { count, itemID }, ... }   only used by a farming plan

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
	-- A currency has no gold price, so the true cost is unknown rather than free.
	if recipe.x then total = nil end
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

-- Chance of a skill point per craft, by the recipe's colour (the client's relativeDifficulty: 0 orange, 1 yellow,
-- 2 green, 3 grey). Orange always gives one; yellow and green are estimates, since the real chance falls as skill rises
-- and the client doesn't report it.
Planner.SKILL_CHANCE = { [0] = 1, [1] = 0.5, [2] = 0.25 }

-- Levelling: entries are { recipeID, difficulty, skillUps } for one character's recipes. Returns the ones that can
-- still give skill, cheapest expected cost per skill point first, at market prices. A recipe with a material that has
-- no price goes last, as its cost is unknown.
function Planner.SkillUpRows(ctx, entries)
	local rows = {}
	for _, entry in ipairs(entries) do
		local chance = Planner.SKILL_CHANCE[entry.difficulty]
		local recipe = ctx.recipes[entry.recipeID]
		if chance and recipe then
			local cost, parts = Planner.RecipeCost(ctx, entry.recipeID)
			local points = math.max(1, entry.skillUps or 1)
			rows[#rows + 1] = {
				recipeID = entry.recipeID, itemID = recipe.o, difficulty = entry.difficulty, chance = chance,
				points = points, cost = cost, parts = parts, perPoint = cost and cost / (chance * points),
			}
		end
	end
	table.sort(rows, function(a, b)
		if (a.perPoint == nil) ~= (b.perPoint == nil) then return a.perPoint ~= nil end
		if a.perPoint and a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
		if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
		return a.recipeID < b.recipeID
	end)
	return rows
end

-- Expected result of selling everything in the queue, at the same prices as the profit list. isSellable(itemID)
-- returns false for results that can't go on the AH, nil while unknown. Those can't earn anything, so only their
-- material cost is reported, apart from the profit. Entries without a usable price are counted, not guessed.
function Planner.QueueTotals(ctx, queue, isSellable)
	local totals = { revenue = 0, cost = 0, net = 0, counted = 0, excluded = 0, entries = {}, bound = 0, boundCost = 0, boundEntries = {} }
	for index, queued in ipairs(queue) do
		local qty = queued.qty or 0
		local result = Planner.Profit(ctx, queued.recipeID)
		if qty > 0 and result and result.cost and isSellable(result.itemID) == false then
			totals.bound = totals.bound + 1
			totals.boundCost = totals.boundCost + result.cost * qty
			totals.boundEntries[index] = result.cost * qty
		elseif qty > 0 and result and result.net and isSellable(result.itemID) then
			totals.revenue = totals.revenue + result.saleUnit * result.yield * (1 - ctx.ahCut) * qty
			totals.cost = totals.cost + result.cost * qty
			totals.net = totals.net + result.net * qty
			totals.counted = totals.counted + 1
			totals.entries[index] = result.net * qty
		elseif qty > 0 then
			totals.excluded = totals.excluded + 1
		end
	end
	return totals
end

-- Crafts needed to reach a stock goal. Everything already on the AH, held or queued counts towards it.
function Planner.RestockCrafts(goal, onAH, owned, queued, yield)
	local missing = goal - onAH - owned - queued
	if missing <= 0 then return 0 end
	return math.ceil(missing / yield)
end

-- Units to post: what the goal still lacks on the AH, from what's in the bags and not needed by the queue.
function Planner.PostQuantity(goal, onAH, inBags, reserved)
	return math.max(0, math.min(goal - onAH, inBags - (reserved or 0)))
end

-- What one unit costs to craft by the cheapest known recipe. Nil when no recipe has a complete price.
function Planner.CraftUnitCost(ctx, itemID)
	local best
	for _, recipeID in ipairs(ctx.known[itemID] or {}) do
		local result = Planner.Profit(ctx, recipeID)
		if result and result.cost then
			local unit = result.cost / result.yield
			if not best or unit < best then best = unit end
		end
	end
	return best
end

-- The price to suggest for one unit, and whether it was raised to stop a post losing money. opts supplies:
--   lowest, lowestIsMine   the cheapest listing right now, if any. Your own isn't undercut.
--   scanned                the last scanned price, used with no listing to go on
--   breakEven              the price that just covers materials and the AH cut, if known
--   wholeSilver            the price can't contain copper. Rounds down to undercut, and up to cover the break-even.
-- Nil when there's nothing to base a price on, for the user to decide.
function Planner.PostPrice(opts)
	local step = opts.wholeSilver and 100 or 1
	local price = opts.scanned
	if opts.lowest then
		price = opts.lowestIsMine and opts.lowest or (opts.lowest - 1)
	end
	if not price then return nil end
	price = math.max(step, math.floor(price / step) * step)
	if opts.breakEven and price < opts.breakEven then
		-- The margin stops floating point noise in the break-even costing a whole extra silver.
		return math.ceil(opts.breakEven / step - 1e-9) * step, true
	end
	return price
end

-- True when a vendor pays more for one than this price earns after the AH cut.
function Planner.BelowVendor(price, sellPrice, ahCut)
	return (sellPrice or 0) > 0 and sellPrice > math.floor(price * (1 - ahCut))
end

-- Materials the crafts in a plan still use, by item. Every alternative of a slot counts, since any of them may be used.
function Planner.ReservedMaterials(ctx, plan)
	local reserved = {}
	for _, craft in ipairs(plan.crafts) do
		local recipe = ctx.recipes[craft.recipeID]
		for _, slot in ipairs(recipe and recipe.r or {}) do
			for i = 2, #slot do
				reserved[slot[i]] = (reserved[slot[i]] or 0) + (slot[1] or 1) * craft.count
			end
		end
	end
	return reserved
end

-- One row per profitable item the characters can make, using its most profitable recipe. opts supplies:
--   isSellable(itemID) -> true when it can go on the AH (false or nil leaves it out)
--   goal(itemID)       -> stock goal, nil while unknown
--   stock(itemID)      -> onAH, owned (onAH nil when auctions can't be seen)
--   queued(itemID)     -> units already planned by queue entries the user added
--   minProfit          -> minimum profit per craft, in copper
function Planner.RestockRows(ctx, opts)
	local rows = {}
	for itemID, recipeIDs in pairs(ctx.known) do
		if opts.isSellable(itemID) then
			local best
			for _, recipeID in ipairs(recipeIDs) do
				local result = Planner.Profit(ctx, recipeID)
				if result and result.net and (not best or result.net > best.net) then best = result end
			end
			local goal = opts.goal(itemID)
			if best and goal and best.net > 0 and best.net >= (opts.minProfit or 0) then
				local onAH, owned = opts.stock(itemID)
				local yield = MinimumYield(ctx.recipes[best.recipeID])
				rows[#rows + 1] = {
					itemID = itemID, recipeID = best.recipeID, net = best.net, goal = goal, onAH = onAH, owned = owned,
					crafts = Planner.RestockCrafts(goal, onAH or 0, owned, opts.queued(itemID), yield),
				}
			end
		end
	end
	table.sort(rows, function(a, b)
		if (a.crafts > 0) ~= (b.crafts > 0) then return a.crafts > 0 end
		if a.net ~= b.net then return a.net > b.net end
		return a.itemID < b.itemID
	end)
	return rows
end

-- Turns the queue into crafts (materials before the items that need them), purchases and alt pickups. With farming
-- set nothing comes from the AH: anything that can be made gets made, what a vendor sells is bought there as it can't
-- be farmed anyway, and the rest goes on plan.farm. Bars with no known recipe go on plan.smelt.
-- Materials already held are used first in both plans; what has to come out of the bank goes on plan.bank.
function Planner.BuildPlan(ctx, queue, farming)
	local plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, bank = {}, farm = {}, smelt = {}, cost = 0 }
	local bags, bank, alts = {}, {}, {}
	local craftIndex = {}
	local active = {}

	local function Load(itemID)
		if bags[itemID] ~= nil then return end
		local total = ctx.ownStock(itemID) or 0
		local inBank = math.min(ctx.bankStock and ctx.bankStock(itemID) or 0, total)
		bags[itemID], bank[itemID] = total - inBank, inBank
	end

	local function OwnLeft(itemID)
		Load(itemID)
		return bags[itemID] + bank[itemID]
	end

	-- Crafted leftovers end up in the bags.
	local function AddToBags(itemID, count)
		Load(itemID)
		bags[itemID] = bags[itemID] + count
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
		Load(itemID)
		local fromBags = math.min(bags[itemID], count)
		bags[itemID] = bags[itemID] - fromBags
		count = count - fromBags
		local fromBank = math.min(bank[itemID], count)
		if fromBank > 0 then
			bank[itemID] = bank[itemID] - fromBank
			count = count - fromBank
			plan.bank[itemID] = (plan.bank[itemID] or 0) + fromBank
		end
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

	local Require, Acquire

	-- How many of an item can still be had from bags, bank and alts, without taking them.
	local function Available(itemID)
		local count = OwnLeft(itemID)
		for _, alt in ipairs(AltsLeft(itemID)) do count = count + alt.count end
		return count
	end

	-- Gold actually spent to make count of an item with this recipe: materials already held cost nothing, the rest
	-- at the cheapest market price. Nil when a material still to get has no price.
	local function CraftSpend(recipeID, crafts)
		local recipe = ctx.recipes[recipeID]
		local spend = 0
		for _, slot in ipairs(recipe.r or {}) do
			local missing = (slot[1] or 1) * crafts
			for i = 2, #slot do missing = missing - math.min(missing, Available(slot[i])) end
			if missing > 0 then
				local bestUnit
				for i = 2, #slot do
					local unit = Planner.ItemCost(ctx, slot[i])
					if unit and (not bestUnit or unit < bestUnit) then bestUnit = unit end
				end
				if not bestUnit then return nil end
				spend = spend + bestUnit * missing
			end
		end
		return spend
	end

	-- The known recipe to farm for, the cheapest when prices can tell. Nil when none can be used right now.
	local function FarmRecipe(itemID)
		local _, kind, cheapest = Planner.ItemCost(ctx, itemID)
		if kind == "craft" and not active[cheapest] then return cheapest end
		for _, candidate in ipairs(ctx.known[itemID] or {}) do
			local recipe = ctx.recipes[candidate]
			if recipe and not recipe.x and not active[candidate] then return candidate end
		end
		return nil
	end

	local function AcquireByFarming(itemID, count)
		local recipeID = FarmRecipe(itemID)
		if recipeID then
			local yield = MinimumYield(ctx.recipes[recipeID])
			local crafts = math.ceil(count / yield)
			Require(recipeID, crafts, nil, true)
			AddToBags(itemID, crafts * yield - count)
			return
		end
		local smelt = ctx.smelting and ctx.smelting[itemID]
		if smelt then
			local smelts = math.ceil(count / smelt.yield)
			plan.smelt[itemID] = (plan.smelt[itemID] or 0) + smelts * smelt.yield
			for _, material in ipairs(smelt) do
				local missing = TakeFromStock(material[2], material[1] * smelts)
				if missing > 0 then Acquire(material[2], missing) end
			end
			AddToBags(itemID, smelts * smelt.yield - count)
			return
		end
		local vendor = ctx.vendorPrice(itemID)
		if vendor then
			plan.vendor[itemID] = (plan.vendor[itemID] or 0) + count
			plan.cost = plan.cost + vendor * count
		else
			plan.farm[itemID] = (plan.farm[itemID] or 0) + count
		end
	end

	Acquire = function(itemID, count)
		if farming then return AcquireByFarming(itemID, count) end
		local ah, vendor = ctx.ahPrice(itemID), ctx.vendorPrice(itemID)
		local useVendor = vendor and (not ah or vendor < ah)
		local buyUnit = useVendor and vendor or ah

		-- Crafting comes in whole batches, so a small need can cost more than buying even when the unit cost is
		-- lower, and materials you already hold cost nothing more. Compare what each way would actually spend.
		local bestRecipe, bestCrafts, bestSpend
		for _, candidate in ipairs(ctx.known[itemID] or {}) do
			local recipe = ctx.recipes[candidate]
			if recipe and not recipe.x and not active[candidate] then
				local crafts = math.ceil(count / MinimumYield(recipe))
				local spend = CraftSpend(candidate, crafts)
				if spend and (not bestSpend or spend < bestSpend) then
					bestRecipe, bestCrafts, bestSpend = candidate, crafts, spend
				end
			end
		end
		if bestRecipe and (not buyUnit or bestSpend < buyUnit * count) then
			Require(bestRecipe, bestCrafts, nil, true)
			AddToBags(itemID, bestCrafts * MinimumYield(ctx.recipes[bestRecipe]) - count)
			return
		end

		if useVendor then
			plan.vendor[itemID] = (plan.vendor[itemID] or 0) + count
		else
			plan.buy[itemID] = (plan.buy[itemID] or 0) + count
		end
		if buyUnit then plan.cost = plan.cost + buyUnit * count else plan.unpriced = true end
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
		-- A recipe that is both queued and needed for another craft is one craft of the combined count. subCount is
		-- the part only needed as a material, so the Queue window can still list it as a sub-craft.
		local sub = isAuto and count or 0
		if entry then
			entry.count = entry.count + count
			entry.subCount = entry.subCount + sub
			entry.auto = entry.auto and isAuto
		else
			entry = { recipeID = recipeID, count = count, subCount = sub, char = char, auto = isAuto }
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
