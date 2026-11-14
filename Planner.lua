-- Crafting and Farming Forever :: Planner
-- Game-independent cost, profit and queue logic, so it can be tested outside the client.
--
-- A context supplies:
--   recipes[recipeID]  = { o, qmin, qmax, r = { { qty, itemID, altItemID, ... }, ... }, x = uses a currency }
--   known[itemID]      = { recipeID, ... }   learned recipes that make the item, on any character
--   ahPrice(itemID)    -> copper or nil
--   vendorPrice(itemID)-> copper or nil
--   ahCut              = 0.05
--   priceCap           = { max = 4, normal = 2 } (optional): a result listed above max x its material cost is
--                        counted at normal x that cost and flagged capped, as one odd listing can't be trusted
-- and, for planning:
--   ownStock(itemID)   -> count on the current character (bags + bank)
--   bankStock(itemID)  -> the part of ownStock that's in the bank (optional), so the plan can say to fetch it
--   mailStock(itemID)  -> count waiting in the current character's mailbox, on top of ownStock (optional)
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

-- A price of nothing is no price: it would make a material free or a result worthless.
local function Priced(copper)
	return copper and copper > 0 and copper or nil
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
	local ah, vendor = Priced(ctx.ahPrice(itemID)), Priced(ctx.vendorPrice(itemID))
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
	local saleUnit = Priced(ctx.ahPrice(recipe.o))
	local result = { recipeID = recipeID, itemID = recipe.o, yield = yield, cost = cost, parts = parts, saleUnit = saleUnit }
	-- A lone listing at many times the material cost (7s of materials posted for 20g) would show a huge profit that
	-- won't sell. Above the cap the sale counts at the normal mark-up instead, and the row is flagged to check.
	local cap = ctx.priceCap
	if cap and saleUnit and cost and cost > 0 then
		local unitCost = cost / yield
		if saleUnit > unitCost * cap.max then
			result.listedUnit = saleUnit
			result.capped = true
			saleUnit = unitCost * math.min(cap.normal, cap.max)
			result.saleUnit = saleUnit
		end
	end
	if cost and saleUnit then
		result.net = saleUnit * yield * (1 - ctx.ahCut) - cost
		result.margin = cost > 0 and result.net / cost or nil
	end
	return result
end

-- Craftsman's Writs: a tradable writ starts a daily quest that wants a crafted item and pays reputation and a coin
-- pouch. By level (1 Journeyman, 2 Expert, 3 Artisan): the reputation, and the pouch's average in copper as players
-- reported it, so the reward is an estimate.
Planner.WRIT_REP = { 75, 125, 200 }
Planner.WRIT_POUCH = { 1200, 3600, 7456 }

-- What handing in one writ costs: writ = { id, item, count, tier }. The item goes by the cheapest path, like any
-- material. total, net and perRep are nil until both the writ and the item have a price; perRep is the gold lost
-- per reputation point, 0 when the pouch pays for it all.
function Planner.Writ(ctx, writ)
	local count = writ.count or 1
	local row = { writ = writ, count = count, rep = Planner.WRIT_REP[writ.tier], reward = Planner.WRIT_POUCH[writ.tier] }
	row.writPrice = Priced(ctx.ahPrice(writ.id))
	if writ.item then
		row.craftable = (ctx.known[writ.item] or {})[1] ~= nil
		local unit, kind, recipeID = Planner.ItemCost(ctx, writ.item)
		if unit then
			row.itemCost, row.kind, row.recipeID = unit * count, kind, recipeID
			if recipeID then row.crafts = math.ceil(count / MinimumYield(ctx.recipes[recipeID])) end
		end
	end
	if row.writPrice and row.itemCost then
		row.total = row.writPrice + row.itemCost
		row.net = row.reward - row.total
		row.perRep = row.net < 0 and -row.net / row.rep or 0
	end
	return row
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
	local totals = { revenue = 0, cost = 0, net = 0, counted = 0, excluded = 0, entries = {}, bound = 0, boundCost = 0, boundEntries = {},
		capped = {} }
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
			if result.capped then totals.capped[index] = true end
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

-- Smart restock goals. Recent days weigh more (a day SMART.HALF_LIFE days back counts half), so a goal follows what
-- sells now. GOLD_SHARE is the most of your gold one item's whole stock may cost to make.
-- LEVEL is how much of a day's sales to keep in stock (the Options slider), as a fraction.
Planner.SMART = { HALF_LIFE = 7, WINDOW = 30, MIN_SPAN = 3, MIN_SAMPLES = 3, GOLD_SHARE = 0.25, MAX = 200, LEVEL = 0.5,
	LEVEL_MIN = 0.1, LEVEL_MAX = 2 }

-- A stock goal from an item's own sales. input:
--   base      the default goal, used until there are MIN_SAMPLES results
--   days      { { age = days ago, s = sold, e = expired }, ... } within WINDOW
--   span      days since the first result, today included
--   coverDays how long a stock should last (the auction's length)
--   unitCost  copper to make one, gold = copper held (both optional: without them gold is no limit)
--   pair      true for things bought two at a time
--   level     how much of that to stock, 1 = all of it (default SMART.LEVEL)
-- The goal is what sells in coverDays x the share of listed units that sold x level. It only goes under the default
-- because of expiries, never because little was listed. Returns the goal and
-- { perDay, soldShare, samples, level, limited = "gold" when gold lowered it, pair, learning }.
function Planner.SmartGoal(input)
	local smart = Planner.SMART
	local info = { pair = input.pair or nil }
	local goal = input.base
	local sold, expired, samples = 0, 0, 0
	for _, day in ipairs(input.days or {}) do
		if day.age >= 0 and day.age < smart.WINDOW then
			local weight = 0.5 ^ (day.age / smart.HALF_LIFE)
			sold, expired = sold + day.s * weight, expired + day.e * weight
			samples = samples + day.s + day.e
		end
	end
	info.samples = samples
	if samples < smart.MIN_SAMPLES or sold + expired <= 0 then
		info.learning = true
	else
		local span = math.max(smart.MIN_SPAN, math.min(smart.WINDOW, input.span or smart.WINDOW))
		local weights = 0
		for age = 0, span - 1 do weights = weights + 0.5 ^ (age / smart.HALF_LIFE) end
		info.perDay = sold / weights
		info.soldShare = sold / (sold + expired)
		info.level = input.level or smart.LEVEL
		goal = math.ceil(info.perDay * (input.coverDays or 1) * info.soldShare * info.level - 1e-9)
		if goal < input.base then goal = math.max(goal, math.ceil(input.base * info.soldShare - 1e-9)) end
		goal = math.max(1, math.min(goal, smart.MAX))
	end
	if input.unitCost and input.unitCost > 0 and input.gold then
		local afford = math.max(1, math.floor(input.gold * smart.GOLD_SHARE / input.unitCost))
		if afford < goal then
			goal = afford
			info.limited = "gold"
		end
	end
	-- A whole pair: one more, or one fewer when gold is what holds it back.
	if input.pair then goal = math.max(2, info.limited and goal - goal % 2 or goal + goal % 2) end
	return goal, info
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
--   lowest                 the cheapest listing right now, if any. Matched, not undercut (the user's choice).
--   scanned                the last scanned price, used with no listing to go on
--   breakEven              the price that just covers materials and the AH cut, if known
--   wholeSilver            the price can't contain copper. Rounds down, and up to cover the break-even.
-- Nil when there's nothing to base a price on, for the user to decide.
function Planner.PostPrice(opts)
	local step = opts.wholeSilver and 100 or 1
	local price = opts.scanned
	if opts.lowest then price = opts.lowest end
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

-- Fits a restock to your gold. rows are RestockRows; queue holds the entries queued by hand, whose materials are paid
-- for first. When the materials for every row cost more than the gold left, the rows giving the most profit for
-- their material cost are kept and the rest cut down: row.wanted is then what the goal asks and row.crafts what the
-- gold covers. Costs are what a plan would really spend, so materials already held are free. Returns nil when
-- nothing needs crafting, else { gold, queued = cost of the hand-queued entries, full = cost of the whole restock,
-- cost = cost of what's kept, short = true when it was cut }.
function Planner.RestockBudget(ctx, rows, queue, gold)
	local entries = {}
	for _, entry in ipairs(queue or {}) do entries[#entries + 1] = entry end
	local first = #entries + 1
	local function Cost() return Planner.BuildPlan(ctx, entries).cost end
	local base = first > 1 and Cost() or 0

	local wanted = {}
	for _, row in ipairs(rows) do
		row.wanted = nil
		if row.crafts > 0 then
			wanted[#wanted + 1] = row
			entries[#entries + 1] = { recipeID = row.recipeID, qty = row.crafts }
		end
	end
	if #wanted == 0 then return nil end
	local info = { gold = gold, queued = base, full = Cost() - base }
	local budget = math.max(0, gold - base)
	if info.full <= budget then
		info.cost = info.full
		return info
	end

	-- Most profit per copper of materials first; free ones before all.
	for index = #entries, first, -1 do entries[index] = nil end
	local value = {}
	for index, row in ipairs(wanted) do
		local result = Planner.Profit(ctx, row.recipeID)
		local cost = result and result.cost or 0
		value[row] = { cost > 0 and row.net / cost or math.huge, index }
	end
	table.sort(wanted, function(a, b)
		if value[a][1] ~= value[b][1] then return value[a][1] > value[b][1] end
		return value[a][2] < value[b][2]
	end)
	-- The most crafts of an entry that fit `room`, by Price(): cost only grows with the count.
	local function Fit(entry, most, room, Price)
		local low, high = 0, most
		while low < high do
			local middle = math.ceil((low + high) / 2)
			entry.qty = middle
			if Price() <= room then low = middle else high = middle - 1 end
		end
		entry.qty = low
		return low
	end

	-- First each row on its own beside the hand-queued entries: small plans, so this stays quick with many rows.
	-- Held materials two rows both want are counted free twice here, which the check below puts right.
	local kept, left = {}, budget
	local alone = { recipeID = 0, qty = 0 }
	entries[first] = alone
	for _, row in ipairs(wanted) do
		alone.recipeID = row.recipeID
		local fit = Fit(alone, row.crafts, left, function() return Cost() - base end)
		if fit < row.crafts then row.wanted, row.crafts = row.crafts, fit end
		if fit > 0 then
			left = left - (Cost() - base)
			kept[#kept + 1] = { recipeID = row.recipeID, qty = fit, row = row }
		end
	end

	-- Then all of them together, cutting from the least valuable end until the real cost fits.
	for index, entry in ipairs(kept) do entries[first + index - 1] = entry end
	local spent = Cost() - base
	for index = #kept, 1, -1 do
		if spent <= budget then break end
		local entry = kept[index]
		local row = entry.row
		local fit = Fit(entry, entry.qty - 1, budget, function() return Cost() - base end)
		row.wanted, row.crafts = row.wanted or (row.crafts), fit
		spent = Cost() - base
	end
	info.cost, info.short = spent, true
	return info
end

-- Turns the queue into crafts (materials before the items that need them), purchases and alt pickups. With farming
-- set nothing comes from the AH: anything that can be made gets made, what a vendor sells is bought there as it can't
-- be farmed anyway, and the rest goes on plan.farm. Bars with no known recipe go on plan.smelt.
-- Materials already held are used first in both plans; what has to come out of the bank goes on plan.bank.
-- The to-do list for the logged-in character (ctx.me): their own queued crafts, the sub-crafts and materials those
-- need, and where to get them. Queued crafts another character makes are only noted in plan.elsewhere (crafts per
-- character): their materials are bought, gathered and made on that character, when you log in there. Sub-crafts are
-- made by the character who needs them, so a material only an alt can make is bought (or gathered) instead. Without
-- ctx.me every entry is planned here, as before.
function Planner.BuildPlan(ctx, queue, farming)
	local plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, bank = {}, mail = {}, farm = {}, smelt = {}, cost = 0,
		elsewhere = {} }
	local bags, bank, mail, alts = {}, {}, {}, {}
	local craftIndex = {}
	local active = {}

	-- A recipe this character can use for a material right now.
	local function Usable(recipeID, char)
		local recipe = ctx.recipes[recipeID]
		if not recipe or recipe.x or active[recipeID] then return false end
		return not (ctx.knows and char) or ctx.knows(char, recipeID)
	end

	local function Load(itemID)
		if bags[itemID] ~= nil then return end
		local total = ctx.ownStock(itemID) or 0
		local inBank = math.min(ctx.bankStock and ctx.bankStock(itemID) or 0, total)
		bags[itemID], bank[itemID] = total - inBank, inBank
		mail[itemID] = ctx.mailStock and ctx.mailStock(itemID) or 0
	end

	local function OwnLeft(itemID)
		Load(itemID)
		return bags[itemID] + mail[itemID] + bank[itemID]
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

	-- Takes up to count of an item from stock: bags, mailbox (what you just bought waits there), bank, then alts.
	-- Returns how many are still missing.
	local function TakeFromStock(itemID, count)
		Load(itemID)
		local fromBags = math.min(bags[itemID], count)
		bags[itemID] = bags[itemID] - fromBags
		count = count - fromBags
		local fromMail = math.min(mail[itemID], count)
		if fromMail > 0 then
			mail[itemID] = mail[itemID] - fromMail
			count = count - fromMail
			plan.mail[itemID] = (plan.mail[itemID] or 0) + fromMail
		end
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

	-- Gold actually spent to get count of an item, the cheapest way this character has: what's held (bags, mail,
	-- bank, alts) costs nothing, the rest is bought or crafted, whichever spends less, with a craft's own materials
	-- costed the same way. So wool in the bank makes the cloth that makes the bolt for nothing, two steps down.
	-- taken[itemID] = stock an estimate in progress already counts on, so it isn't counted twice by two materials
	-- that need the same thing; each branch works on its own copy, as a branch not chosen takes nothing. Returns the
	-- spend (nil when something still to get has no price), the recipe to craft with and its crafts (nil: buy), and
	-- the taken table after it.
	local SPEND_DEPTH = 8
	local Spend

	local function CopyTaken(taken)
		local copy = {}
		for itemID, count in pairs(taken) do copy[itemID] = count end
		return copy
	end

	local function CraftSpend(recipeID, crafts, char, taken, depth)
		local recipe = ctx.recipes[recipeID]
		local spend = 0
		for _, slot in ipairs(recipe.r or {}) do
			local missing = (slot[1] or 1) * crafts
			for i = 2, #slot do
				local have = Available(slot[i]) - (taken[slot[i]] or 0)
				local use = math.min(math.max(have, 0), missing)
				taken[slot[i]] = (taken[slot[i]] or 0) + use
				missing = missing - use
			end
			if missing > 0 then
				local bestSpend, bestTaken
				for i = 2, #slot do
					local cost, _, _, after = Spend(slot[i], missing, char, CopyTaken(taken), depth + 1)
					if cost and (not bestSpend or cost < bestSpend) then bestSpend, bestTaken = cost, after end
				end
				if not bestSpend then return nil end
				spend, taken = spend + bestSpend, bestTaken
			end
		end
		return spend, taken
	end

	Spend = function(itemID, count, char, taken, depth)
		local have = Available(itemID) - (taken[itemID] or 0)
		local use = math.min(math.max(have, 0), count)
		taken[itemID] = (taken[itemID] or 0) + use
		count = count - use
		if count <= 0 then return 0, nil, nil, taken end
		local ah, vendor = Priced(ctx.ahPrice(itemID)), Priced(ctx.vendorPrice(itemID))
		local buyUnit = vendor and (not ah or vendor < ah) and vendor or ah
		local best, bestRecipe, bestCrafts, bestTaken = buyUnit and buyUnit * count, nil, nil, taken
		if depth >= SPEND_DEPTH then return best, nil, nil, taken end
		local function Consider(spend, recipeID, crafts, after)
			if spend and (not best or spend < best) then best, bestRecipe, bestCrafts, bestTaken = spend, recipeID, crafts, after end
		end
		for _, candidate in ipairs(ctx.known[itemID] or {}) do
			if Usable(candidate, char) then
				local yield = MinimumYield(ctx.recipes[candidate])
				local crafts = math.ceil(count / yield)
				local function Estimate(n)
					active[candidate] = (active[candidate] or 0) + 1
					local spend, after = CraftSpend(candidate, n, char, CopyTaken(taken), depth)
					active[candidate] = active[candidate] - 1
					if active[candidate] == 0 then active[candidate] = nil end
					return spend, after
				end
				-- Crafting comes in whole batches, so a small need can cost more than buying even when the unit cost
				-- is lower.
				local spend, after = Estimate(crafts)
				Consider(spend, candidate, crafts, after)
				-- When the batch isn't free, what's held may still cover part of it: make that part and buy the rest,
				-- if that spends less. The largest free batch is found by halving, as spends only grow with crafts.
				if buyUnit and spend and spend > 0 and crafts > 1 then
					local low, high = 0, crafts - 1
					while low < high do
						local mid = math.ceil((low + high) / 2)
						if Estimate(mid) == 0 then low = mid else high = mid - 1 end
					end
					if low > 0 then
						local part, partTaken = Estimate(low)
						Consider(part + buyUnit * (count - low * yield), candidate, low, partTaken)
					end
				end
			end
		end
		return best, bestRecipe, bestCrafts, bestTaken
	end

	-- The known recipe to farm for, the cheapest when prices can tell. Nil when none can be used right now.
	local function FarmRecipe(itemID, char)
		local _, kind, cheapest = Planner.ItemCost(ctx, itemID)
		if kind == "craft" and Usable(cheapest, char) then return cheapest end
		for _, candidate in ipairs(ctx.known[itemID] or {}) do
			if Usable(candidate, char) then return candidate end
		end
		return nil
	end

	local function AcquireByFarming(itemID, count, char)
		local recipeID = FarmRecipe(itemID, char)
		if recipeID then
			local yield = MinimumYield(ctx.recipes[recipeID])
			local crafts = math.ceil(count / yield)
			Require(recipeID, crafts, char, true)
			AddToBags(itemID, crafts * yield - count)
			return
		end
		local smelt = ctx.smelting and ctx.smelting[itemID]
		if smelt then
			local smelts = math.ceil(count / smelt.yield)
			plan.smelt[itemID] = (plan.smelt[itemID] or 0) + smelts * smelt.yield
			for _, material in ipairs(smelt) do
				local missing = TakeFromStock(material[2], material[1] * smelts)
				if missing > 0 then Acquire(material[2], missing, char) end
			end
			AddToBags(itemID, smelts * smelt.yield - count)
			return
		end
		local vendor = Priced(ctx.vendorPrice(itemID))
		if vendor then
			plan.vendor[itemID] = (plan.vendor[itemID] or 0) + count
			plan.cost = plan.cost + vendor * count
		else
			plan.farm[itemID] = (plan.farm[itemID] or 0) + count
		end
	end

	Acquire = function(itemID, count, char)
		if farming then return AcquireByFarming(itemID, count, char) end
		local ah, vendor = Priced(ctx.ahPrice(itemID)), Priced(ctx.vendorPrice(itemID))
		local useVendor = vendor and (not ah or vendor < ah)
		local buyUnit = useVendor and vendor or ah

		-- Materials you already hold cost nothing more, however deep down they're used: compare what buying and
		-- each usable recipe would actually spend, for the whole need or for the part what's held covers. Equal
		-- spends buy, which is fewer steps.
		local _, bestRecipe, bestCrafts = Spend(itemID, count, char, {}, 0)
		if bestRecipe then
			Require(bestRecipe, bestCrafts, char, true)
			local made = bestCrafts * MinimumYield(ctx.recipes[bestRecipe])
			if made >= count then
				AddToBags(itemID, made - count)
				return
			end
			count = count - made -- the part held materials didn't cover is bought
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
		-- A sub-craft stays with the character who needs it (Usable checked they know it).
		local char = (isAuto and ctx.knows and preferredChar) or ctx.crafter(recipeID, preferredChar)
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
				Acquire(bestID, missing, char)
			end
		end
		active[recipeID] = active[recipeID] - 1
		if active[recipeID] == 0 then active[recipeID] = nil end

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

	-- Other characters' crafts first, only to set aside what they hold for them: what's in an alt's bags for its own
	-- crafts isn't offered to this character. The rest of their planning happens when you log in there.
	local mine = {}
	for _, queued in ipairs(queue) do
		if (queued.qty or 0) > 0 then
			local char = ctx.crafter(queued.recipeID, queued.char)
			if not ctx.me or char == ctx.me then
				table.insert(mine, queued)
			else
				plan.elsewhere[char] = (plan.elsewhere[char] or 0) + queued.qty
				local name = ctx.charName and ctx.charName(char)
				local recipe = ctx.recipes[queued.recipeID]
				for _, slot in ipairs(name and recipe and recipe.r or {}) do
					local need = (slot[1] or 1) * queued.qty
					for i = 2, #slot do
						for _, alt in ipairs(AltsLeft(slot[i])) do
							if alt.name == name and need > 0 then
								local take = math.min(alt.count, need)
								alt.count, need = alt.count - take, need - take
							end
						end
					end
				end
			end
		end
	end
	for _, queued in ipairs(mine) do Require(queued.recipeID, queued.qty, queued.char, false) end
	return plan
end

-- Time left on the crafting this character can do. crafts = the plan's crafts ({ recipeID, count, char }); only
-- those with char == me count. secondsOf(recipeID) = one craft, cast plus the pause before the next.
-- current (optional) = { recipeID, left = crafts of it still to make including the one being cast, castLeft =
-- seconds until that cast finishes, or nil when not casting }: its time replaces the plan's count for that recipe,
-- which lags a moment behind each finished craft. Returns this recipe's seconds, all seconds, all crafts.
function Planner.TimeLeft(crafts, me, secondsOf, current)
	local function Seconds(recipeID, left, castLeft)
		if left <= 0 then return 0 end
		if castLeft then return math.max(castLeft, 0) + (left - 1) * secondsOf(recipeID) end
		return left * secondsOf(recipeID)
	end
	local total, count, runSeconds, seenCurrent = 0, 0, nil, false
	for _, craft in ipairs(crafts) do
		if craft.char == me and craft.count > 0 then
			if current and craft.recipeID == current.recipeID and not seenCurrent then
				seenCurrent = true
				local left = math.min(current.left, craft.count)
				runSeconds = Seconds(craft.recipeID, left, current.castLeft)
				total, count = total + runSeconds, count + left
			else
				total, count = total + Seconds(craft.recipeID, craft.count), count + craft.count
			end
		end
	end
	-- Casting something the plan doesn't have (not queued, or already crossed off): just this cast.
	if current and not seenCurrent then
		runSeconds = Seconds(current.recipeID, current.left, current.castLeft)
		total, count = total + runSeconds, count + current.left
	end
	return runSeconds, total, count
end

-- "45s", "3:07", "1:02:05".
function Planner.FormatDuration(seconds)
	seconds = math.max(0, math.floor((seconds or 0) + 0.5))
	if seconds < 60 then return seconds .. "s" end
	local hours, minutes, secs = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if hours > 0 then return ("%d:%02d:%02d"):format(hours, minutes, secs) end
	return ("%d:%02d"):format(minutes, secs)
end

return Planner
