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
--   normalPrice(itemID)-> copper (optional): the item's usual price (Planner.NormalPrice). A result listed above it
--                        counts at it, so a short price spike can't make a craft look good that will sell for less
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

-- Batches: what `count` units cost when that many are bought or made, not count x the cheapest listing. Auction house
-- units are costed down the listings (ctx.ahDepth, Planner.DepthCost) where those were read; materials whose listings
-- were never read count at their cheapest listing and are noted. Held stock is not used: like ItemCost, this is what
-- things cost at market. Returns total (nil with no price), kind, recipeID, and a note { read = { [itemID] = true },
-- unread = { [itemID] = true } } of the auction house purchases it took.
local function Merge(into, from)
	for itemID in pairs(from.read) do into.read[itemID] = true end
	for itemID in pairs(from.unread) do into.unread[itemID] = true end
end

local function BatchMemo(ctx)
	ctx.batchMemo = ctx.batchMemo or {}
	return ctx.batchMemo
end

function Planner.ItemCostFor(ctx, itemID, count)
	local memo = BatchMemo(ctx)
	memo[itemID] = memo[itemID] or {}
	local found = memo[itemID][count]
	if found then return found.total, found.kind, found.recipeID, found.note end

	local hitsBefore = ctx.cycleHits
	local ah, vendor = Priced(ctx.ahPrice(itemID)), Priced(ctx.vendorPrice(itemID))
	local total, kind, recipeID
	local note = { read = {}, unread = {} }
	local depth = ah and ctx.ahDepth and ctx.ahDepth(itemID)
	if ah then
		if depth then
			total = Planner.DepthCost(depth, 0, count, vendor, ah)
			kind = "ah"
		else
			total, kind = ah * count, "ah"
		end
	end
	if vendor and (not total or vendor * count < total) then total, kind = vendor * count, "vendor" end
	if kind == "ah" then
		if depth then note.read[itemID] = true else note.unread[itemID] = true end
	end

	for _, candidate in ipairs(ctx.known[itemID] or {}) do
		if ctx.visiting[candidate] then
			ctx.cycleHits = ctx.cycleHits + 1
		else
			local recipe = ctx.recipes[candidate]
			if recipe then
				local craftTotal, _, craftNote = Planner.RecipeCostFor(ctx, candidate, count / AverageYield(recipe))
				if craftTotal and (not total or craftTotal < total) then
					total, kind, recipeID, note = craftTotal, "craft", candidate, craftNote
				end
			end
		end
	end

	if ctx.cycleHits == hitsBefore then
		memo[itemID][count] = { total = total, kind = kind, recipeID = recipeID, note = note }
	end
	return total, kind, recipeID, note
end

-- Cost of `crafts` crafts of a recipe (see ItemCostFor). Returns total, parts (as RecipeCost's, unit = the average
-- per unit over the batch, deep = true when listings were read for it), note.
function Planner.RecipeCostFor(ctx, recipeID, crafts)
	local recipe = ctx.recipes[recipeID]
	local note = { read = {}, unread = {} }
	if not recipe then return nil, {}, note end
	ctx.visiting[recipeID] = true
	local total, parts = 0, {}
	for _, slot in ipairs(recipe.r or {}) do
		local qty = slot[1] or 1
		local need = qty * crafts
		local best, bestKind, bestID, bestRecipe, bestNote
		for i = 2, #slot do
			local cost, kind, subRecipe, subNote = Planner.ItemCostFor(ctx, slot[i], need)
			if cost and (not best or cost < best) then
				best, bestKind, bestID, bestRecipe, bestNote = cost, kind, slot[i], subRecipe, subNote
			end
		end
		local part = { itemID = bestID or slot[2], qty = qty, kind = bestKind, recipeID = bestRecipe }
		if best then
			part.unit = need > 0 and best / need or 0
			part.deep = next(bestNote.read) ~= nil or nil
			Merge(note, bestNote)
			if total then total = total + best end
		else
			total = nil
		end
		parts[#parts + 1] = part
	end
	ctx.visiting[recipeID] = nil
	if recipe.x then total = nil end
	return total, parts, note
end

-- What `units` of an item cost to craft by its cheapest known recipe, in a batch that size (nil with no price).
function Planner.CraftCostFor(ctx, itemID, units)
	local best
	for _, recipeID in ipairs(ctx.known[itemID] or {}) do
		local recipe = ctx.recipes[recipeID]
		local total = recipe and Planner.RecipeCostFor(ctx, recipeID, units / AverageYield(recipe))
		if total and (not best or total < best) then best = total end
	end
	return best
end

-- Economics of selling the result of a recipe on the auction house. With crafts (and ctx.ahDepth) the materials are
-- priced for that many crafts and cost is the average per craft: result.batch = crafts, result.oneCost = one craft at
-- the cheapest listings, result.unread = { itemID, ... } materials bought at the auction house whose listings were
-- never read (counted at their cheapest), result.deep = true when some were read.
function Planner.Profit(ctx, recipeID, crafts)
	local recipe = ctx.recipes[recipeID]
	if not recipe or not recipe.o then return nil end
	local cost, parts = Planner.RecipeCost(ctx, recipeID)
	local yield = AverageYield(recipe)
	local saleUnit = Priced(ctx.ahPrice(recipe.o))
	local result = { recipeID = recipeID, itemID = recipe.o, yield = yield, cost = cost, parts = parts, saleUnit = saleUnit }
	if crafts and crafts > 0 and ctx.ahDepth then
		local total, batchParts, note = Planner.RecipeCostFor(ctx, recipeID, crafts)
		result.batch, result.oneCost = crafts, cost
		result.cost, result.parts = total and total / crafts, batchParts
		result.deep = next(note.read) ~= nil or nil
		result.unread = {}
		for itemID in pairs(note.unread) do result.unread[#result.unread + 1] = itemID end
		table.sort(result.unread)
		cost = result.cost
	end
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
	-- During a spike the materials and the result may both be dear: the materials are paid now, the result sells
	-- later, likely at its usual price. So the sale counts at no more than that.
	local normal = ctx.normalPrice and Priced(ctx.normalPrice(recipe.o))
	if normal and result.saleUnit then
		local listed = result.listedUnit or result.saleUnit
		result.normalUnit = normal
		result.ofNormal = listed / normal
		result.spiked = result.ofNormal >= Planner.NORMAL.HIGH or nil
		if saleUnit > normal then
			result.listedUnit = listed
			result.atNormal = true
			saleUnit = normal
			result.saleUnit = saleUnit
		end
	end
	if cost and saleUnit then
		result.net = saleUnit * yield * (1 - ctx.ahCut) - cost
		result.margin = cost > 0 and result.net / cost or nil
	end
	return result
end

-- Usual prices: the lowest price seen each day (days = { [day number] = copper }), and the median of the last DAYS
-- days is what the item normally sells for. Fewer than MIN_DAYS days say nothing. HIGH = a price this many times
-- the usual one is a spike, LOW (its inverse) unusually cheap.
Planner.NORMAL = { DAYS = 14, MIN_DAYS = 3, HIGH = 1.3 }
Planner.NORMAL.LOW = 1 / Planner.NORMAL.HIGH

function Planner.NormalPrice(days, today)
	if not days then return nil end
	local values = {}
	for day, copper in pairs(days) do
		if day > today - Planner.NORMAL.DAYS and day <= today and copper > 0 then values[#values + 1] = copper end
	end
	if #values < Planner.NORMAL.MIN_DAYS then return nil end
	table.sort(values)
	local middle = (#values + 1) / 2
	return (values[math.floor(middle)] + values[math.ceil(middle)]) / 2
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

-- Waylaid Crates: a tradable crate is filled with any one of its bundles of materials and handed in for Merchant's
-- Favor and a little coin. By level (1 Apprentice to 4 Artisan), for crates of gathered materials and of crafted
-- ones. Players reported Journeyman and Expert; Apprentice's coin and all of Artisan follow their pattern.
Planner.CRATE_TOKENS = { gathered = { 5, 10, 15, 20 }, made = { 10, 20, 30, 40 } }
Planner.CRATE_COIN = { gathered = { 250, 500, 750, 1000 }, made = { 500, 1000, 1500, 2000 } }
Planner.CRATE_GUESS_TIER = 4

-- What filling one crate costs: crate = { id, tier, made, bundles = { { item, count }, ... } }. Each bundle goes by
-- the cheapest path, like any material; best is the cheapest bundle with a price. total, net and perToken are nil
-- until both the crate and a bundle have a price; perToken is the gold spent per Merchant's Favor after the coin
-- reward, 0 when the coin pays for it all.
function Planner.Crate(ctx, crate)
	local kind = crate.made and "made" or "gathered"
	local row = {
		crate = crate, tokens = Planner.CRATE_TOKENS[kind][crate.tier], reward = Planner.CRATE_COIN[kind][crate.tier],
		rough = crate.tier >= Planner.CRATE_GUESS_TIER, bundles = {},
	}
	row.cratePrice = Priced(ctx.ahPrice(crate.id))
	for index, bundle in ipairs(crate.bundles) do
		local fill = { item = bundle.item, count = bundle.count }
		local unit, how, recipeID = Planner.ItemCost(ctx, bundle.item)
		if unit then
			fill.cost, fill.kind, fill.recipeID = unit * bundle.count, how, recipeID
			if recipeID then fill.crafts = math.ceil(bundle.count / MinimumYield(ctx.recipes[recipeID])) end
			if not row.best or fill.cost < row.best.cost then row.best = fill end
		end
		row.bundles[index] = fill
	end
	if row.best then row.fillCost = row.best.cost end
	if row.cratePrice and row.fillCost then
		row.total = row.cratePrice + row.fillCost
		row.net = row.total - row.reward
		row.perToken = row.net > 0 and row.net / row.tokens or 0
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
		capped = {}, spiked = {} }
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
			if result.spiked and not result.capped then totals.spiked[index] = result.ofNormal end
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

-- Smart restock goals move by sell-through: a day that sold everything raises the goal a step, expiries cut it.
--   WINDOW       days of results that count; MIN_SAMPLES results are needed before the default is left
--   STEP         a step up, as a share of the goal (never under one unit before the profit scaling)
--   CUT          how much of a day's expired share, past what's tolerated, comes off the goal
--   TOLERATE     the expired share that's fine at a margin of 1: some unsold stock is the price of not running out
--   MARGIN       the margin assumed until an item's deposit has been seen
--   RECENT       days the tooltip's "lately" covers
--   LEVEL        the Options slider, cautious to aggressive; at LEVEL the goal can rise to what sold between two
--                restocks on a sold-out day, at twice LEVEL to twice that
--   PAUSE_MIN    expired units needed before an item can be paused; PAUSE_HALF = days after which a result
--                counts half towards that; RETRY = days until a paused item is tried again, doubling up to RETRY_MAX
--   GAP_*        limits on the time between restocks, in days, and the gaps needed to trust a measured one
--   SESSION      posts closer together than this many seconds are one restock
--   GOLD_SHARE   the most of your gold one item's whole stock may cost to make
Planner.SMART = { WINDOW = 30, MIN_SAMPLES = 3, GOLD_SHARE = 0.25, MAX = 200, LEVEL = 0.5, LEVEL_MIN = 0.1, LEVEL_MAX = 2,
	STEP = 0.25, CUT = 1, TOLERATE = 0.4, MARGIN = 0.75, RECENT = 3, GAP_MIN = 0.25, GAP_MAX = 3, GAP_SAMPLES = 3, SESSION = 30 * 60, TRIPS = 20,
	PAUSE_MIN = 3, PAUSE_HALF = 7, RETRY = 3, RETRY_MAX = 14 }

-- The time your stock has to last: days between restocks, from the times (seconds) restocks were posted. Long gaps
-- count for more, as a buyer is more likely to arrive during one (the mean weighted by length). Gaps over GAP_MAX
-- are time away and don't count. Nil with under GAP_SAMPLES gaps.
function Planner.RestockGap(times)
	local smart = Planner.SMART
	local sorted = {}
	for index, at in ipairs(times or {}) do sorted[index] = at end
	table.sort(sorted)
	local sum, squares, count = 0, 0, 0
	for index = 2, #sorted do
		local gap = (sorted[index] - sorted[index - 1]) / 86400
		if gap > 0 and gap <= smart.GAP_MAX then
			sum, squares, count = sum + gap, squares + gap * gap, count + 1
		end
	end
	if count < smart.GAP_SAMPLES then return nil end
	return math.max(smart.GAP_MIN, math.min(smart.GAP_MAX, squares / sum))
end

-- How much a sale earns against what an unsold unit costs, from 0 (nothing to gain) to 1 (nothing to lose): the
-- profit's share of profit plus deposit. Nil when the deposit isn't known.
function Planner.SmartMargin(profit, deposit)
	if not (profit and deposit) then return nil end
	if profit <= 0 then return 0 end
	return profit / (profit + math.max(0, deposit))
end

-- A stock goal from an item's own sales. input:
--   base      the default goal: where it starts, and what's used until there are MIN_SAMPLES results
--   days      { { age = days ago, s = sold, e = expired, d = copper of deposits lost on the expired ones (nil when
--             unknown) }, ... }, one per day, within WINDOW
--   profit    copper one sale earns (nil = unknown: nothing is weighed by deposit and nothing gets paused)
--   gap       days your stock has to last between restocks (default 1), gapKnown = true when measured
--   margin    Planner.SmartMargin (nil = unknown: SMART.MARGIN)
--   unsettled age of the newest day that still has auctions running: up to it nothing counts as sold out
--   unitCost  copper to make one, gold = copper held (both optional: without them gold is no limit)
--   costOf    function(n) -> copper to make n in one go, down the listings (optional: else n x unitCost)
--   pair      true for things bought two at a time
--   level     cautious to aggressive (default SMART.LEVEL)
-- The goal is recomputed from the history each time, oldest day first, starting at the default:
--   a day with expiries takes CUT x the expired share off it, past the share the margin tolerates (a smaller cut
--   with a good margin, a bigger one when cautious);
--   a day that sold with nothing expiring raises it a step (bigger with a good margin or when aggressive), as long as what sold in one
--   restock gap that day says there's room: never past sold x gap x (level / LEVEL) x (0.5 + margin).
-- A day's expiries are judged by the deposit they really lost (profit against d per expired unit), so auctions posted
-- for a short time, which cost little, move the goal less than long ones.
-- Pausing: when the deposits lost lately (results fade, PAUSE_HALF) are more than the sales earned, the goal is 0
-- and info.paused is set, with info.retryIn days to go. RETRY days after the last result one is tried again
-- (info.retry, goal 1); a try that earns more than it loses ends the pause, one that doesn't doubles the wait.
-- So it only goes under the default through expiries, and only over it by selling out. "Sold out" is an estimate:
-- the units listed on a past day aren't on record, only that all that came back that day had sold.
-- Returns the goal and { samples, learning, level, gap, gapKnown, margin, raised and lowered (days that moved it),
-- recentSold and recentExpired (the last RECENT days), lost and earned (copper, behind a pause), paused, retryIn,
-- retry, limited = "gold" when gold lowered it (full = the goal without that), pair }.
function Planner.SmartGoal(input)
	local smart = Planner.SMART
	local info = { pair = input.pair or nil, level = input.level or smart.LEVEL, gapKnown = input.gapKnown or nil,
		margin = input.margin, raised = 0, lowered = 0, recentSold = 0, recentExpired = 0 }
	info.gap = math.max(smart.GAP_MIN, math.min(smart.GAP_MAX, input.gap or 1))
	local days, samples = {}, 0
	for _, day in ipairs(input.days or {}) do
		if day.age >= 0 and day.age < smart.WINDOW and day.s + day.e > 0 then
			days[#days + 1] = day
			samples = samples + day.s + day.e
			if day.age < smart.RECENT then
				info.recentSold, info.recentExpired = info.recentSold + day.s, info.recentExpired + day.e
			end
		end
	end
	info.samples = samples
	local goal = input.base
	if samples < smart.MIN_SAMPLES then
		info.learning = true
	else
		table.sort(days, function(a, b) return a.age > b.age end)
		local eager = info.level / smart.LEVEL
		local margin = input.margin or smart.MARGIN
		local tolerated = smart.TOLERATE * margin
		local up = 0.5 + margin
		local pace = math.max(0.5, math.min(2, eager))
		local cut = math.max(0.1, math.min(1, smart.CUT * (1.5 - margin) / eager))
		local level = input.base
		local profit = input.profit
		local lost, earned, expired, lastAge = 0, 0, 0, nil
		local pausedAt, wait
		for _, day in ipairs(days) do
			if day.e > 0 then
				-- By what these expiries really cost, when that's on record.
				local dayMargin = profit and day.d and Planner.SmartMargin(profit, day.d / day.e)
				local dayCut, dayTolerated = cut, tolerated
				if dayMargin then
					dayCut = math.max(0.1, math.min(1, smart.CUT * (1.5 - dayMargin) / eager))
					dayTolerated = smart.TOLERATE * dayMargin
				end
				local excess = day.e / (day.s + day.e) - dayTolerated
				if excess > 0 then
					level = math.max(1, level * (1 - dayCut * excess))
					info.lowered = info.lowered + 1
				end
			end
			if profit then
				local dayLost, dayEarned = day.d or 0, day.s * profit
				if pausedAt then
					-- A result while paused is a try.
					if day.s > 0 and dayEarned >= dayLost then
						pausedAt, wait = nil, nil
						lost, earned, expired = dayLost, dayEarned, day.e
					elseif day.e > 0 then
						pausedAt, wait = day.age, math.min(wait * 2, smart.RETRY_MAX)
					end
				else
					local fade = lastAge and 0.5 ^ ((lastAge - day.age) / smart.PAUSE_HALF) or 1
					lost, earned, expired = lost * fade + dayLost, earned * fade + dayEarned, expired + day.e
					if day.e > 0 and expired >= smart.PAUSE_MIN and lost > earned then
						pausedAt, wait = day.age, smart.RETRY
					end
				end
				lastAge = day.age
			end
			if day.e == 0 and not (input.unsettled and day.age <= input.unsettled) then
				local room = day.s * info.gap * eager * up
				if room > level then
					level = math.min(level + math.max(1, smart.STEP * level) * up * pace, room)
					info.raised = info.raised + 1
				end
			end
		end
		-- To the nearest whole one, or the nearest pair.
		local unit = input.pair and 2 or 1
		goal = math.max(1, math.min(math.floor(level / unit + 0.5) * unit, smart.MAX))
		if pausedAt then
			info.lost, info.earned = lost, earned
			if pausedAt >= wait then
				info.retry = true
				goal = 1
			else
				info.paused, info.retryIn = true, wait - pausedAt
				return 0, info
			end
		end
	end
	if input.unitCost and input.unitCost > 0 and input.gold then
		-- What n cost to make: down the listings when costOf knows (buying more costs more per unit), else n x unitCost.
		local budget, deposit = input.gold * smart.GOLD_SHARE, input.deposit or 0
		local function Fits(n)
			local cost = input.costOf and input.costOf(n) or input.unitCost * n
			return cost + n * deposit <= budget
		end
		local afford = goal
		if not Fits(goal) then
			local low, high = 1, goal - 1 -- the most that fits is in low..high, or none (then 1)
			while low < high do
				local mid = math.floor((low + high + 1) / 2)
				if Fits(mid) then low = mid else high = mid - 1 end
			end
			afford = low
		end
		if afford < goal then
			info.full = input.pair and math.max(2, goal + goal % 2) or goal
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

-- Rows with something to craft first, then those already queued, then by profit.
local function RestockOrder(a, b)
	if (a.crafts > 0) ~= (b.crafts > 0) then return a.crafts > 0 end
	if ((a.queued or 0) > 0) ~= ((b.queued or 0) > 0) then return (a.queued or 0) > 0 end
	if a.net ~= b.net then return a.net > b.net end
	return a.itemID < b.itemID
end

-- One row per profitable item the characters can make, using its most profitable recipe. opts supplies:
--   isSellable(itemID) -> true when it can go on the AH (false or nil leaves it out)
--   goal(itemID)       -> stock goal, nil while unknown
--   stock(itemID)      -> onAH, owned (onAH nil when auctions can't be seen)
--   queued(itemID)     -> units already planned by queue entries the user added
--   committed(itemID)  -> units and crafts of an earlier restock still on the queue (optional)
--   fullGoal(itemID)   -> the goal with no gold limit on it (optional; the goal when left out)
--   minProfit          -> minimum profit per craft, in copper
-- An earlier restock on the queue is committed: its materials may be bought already. So a row's crafts are only what
-- the goal lacks beyond it (row.queued = the crafts already there), and its item stays listed even when a price
-- moved and it no longer earns enough. It is only cut back (row.trim, in crafts) when the stock itself says so: more
-- on the AH, held and queued than the goal without its gold limit, as when expired auctions came back. Gold running
-- low after shopping never cuts it.
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
			local units, queued = 0, 0
			if opts.committed then units, queued = opts.committed(itemID) end
			local earns = best and best.net > 0 and best.net >= (opts.minProfit or 0)
			if best and goal and (earns or queued > 0) then
				local onAH, owned = opts.stock(itemID)
				local yield = MinimumYield(ctx.recipes[best.recipeID])
				local planned = opts.queued(itemID) + units
				local row = {
					itemID = itemID, recipeID = best.recipeID, net = best.net, goal = goal, onAH = onAH, owned = owned,
					crafts = earns and Planner.RestockCrafts(goal, onAH or 0, owned, planned, yield) or 0,
					yield = yield,
				}
				-- Units held or queued already that will go on the AH: their deposits have to be paid too.
				local wholeGoal = math.max(goal, opts.fullGoal and opts.fullGoal(itemID) or goal)
				row.holds = math.max(0, math.min(owned + planned, wholeGoal - (onAH or 0)))
				if queued > 0 then
					row.queued = queued
					local full = math.max(goal, opts.fullGoal and opts.fullGoal(itemID) or goal)
					local excess = (onAH or 0) + owned + planned - full
					local trim = math.min(queued, math.floor(excess / yield))
					if trim > 0 then row.trim = trim end
				end
				rows[#rows + 1] = row
			end
		end
	end
	table.sort(rows, RestockOrder)
	return rows
end

-- Decides a queued restock again at what its materials really cost. New restock crafts are picked at each material's
-- cheapest listing (no searching needed); once queued, the auction house reads every listing of what the queue buys
-- (ctx.ahDepth, see Planner.DepthCost), and the queue's buying goes further down them than the first craft does. So
-- the whole queue is planned, every material it buys counts at the average it really pays, and a restock entry
-- (entry.restock) earning less than minProfit a craft at those prices is cut to the most crafts that still earn it:
-- the worst first, as each cut leaves cheaper listings for the rest. Entries queued by hand are never cut, but their
-- buying counts. Materials whose listings weren't read stay at the cheapest listing; with none read nothing is cut.
-- Returns the cuts: { { index = in queue, recipeID, from = crafts, to = crafts, net = profit a craft at the averages
-- before the cut }, ... } in queue order.
function Planner.RestockTrim(ctx, queue, minProfit)
	minProfit = minProfit or 0
	local entries, wanted = {}, {}
	for index, entry in ipairs(queue or {}) do
		local copy = { recipeID = entry.recipeID, qty = entry.qty, char = entry.char }
		entries[#entries + 1] = copy
		if entry.restock and (entry.qty or 0) > 0 then
			wanted[#wanted + 1] = { index = index, entry = copy, from = entry.qty }
		end
	end
	if #wanted == 0 then return {} end

	-- Profit per craft of a recipe with every material at the average the plan pays (nil when no listing says
	-- anything the scan didn't).
	local function Averaged()
		local plan = Planner.BuildPlan(ctx, entries)
		local average
		for itemID, count in pairs(plan.buy) do
			if plan.deep[itemID] and plan.paid[itemID] and count > 0 then
				local unit = plan.paid[itemID] / count
				if unit ~= ctx.ahPrice(itemID) then
					average = average or {}
					average[itemID] = unit
				end
			end
		end
		if not average then return nil end
		local priced = {}
		for key, value in pairs(ctx) do priced[key] = value end
		priced.ahPrice = function(itemID) return average[itemID] or ctx.ahPrice(itemID) end
		Planner.NewContext(priced)
		return function(recipeID)
			local result = Planner.Profit(priced, recipeID)
			return result and result.net
		end
	end
	local function Earns(net)
		return net == nil or (net > 0 and net >= minProfit)
	end

	local nets = {}
	for _ = 1, #wanted + 1 do
		local Net = Averaged()
		if not Net then break end
		local worst, worstNet
		for _, item in ipairs(wanted) do
			local net = item.entry.qty > 0 and Net(item.entry.recipeID)
			if net and not Earns(net) and (not worst or net < worstNet) then worst, worstNet = item, net end
		end
		if not worst then break end
		nets[worst] = nets[worst] or worstNet
		-- The most crafts of it that still earn enough: its materials only get dearer with the count.
		local entry = worst.entry
		local low, high = 0, entry.qty - 1
		while low < high do
			local middle = math.ceil((low + high) / 2)
			entry.qty = middle
			local At = Averaged()
			if Earns(At and At(entry.recipeID)) then low = middle else high = middle - 1 end
		end
		entry.qty = low
	end

	local cuts = {}
	for _, item in ipairs(wanted) do
		if item.entry.qty < item.from then
			cuts[#cuts + 1] = { index = item.index, recipeID = item.entry.recipeID, from = item.from,
				to = item.entry.qty, net = nets[item] }
		end
	end
	return cuts
end

function Planner.SortRestock(rows)
	table.sort(rows, RestockOrder)
end

-- Fits a restock to your gold. rows are RestockRows; queue holds the entries queued by hand, whose materials are paid
-- for first. When the materials for every row cost more than the gold left, the rows giving the most profit for
-- their material cost are kept and the rest cut down: row.wanted is then what the goal asks and row.crafts what the
-- gold covers. Costs are what a plan would really spend, so materials already held are free.
-- Gold to post everything is kept back: a row with deposit (copper per unit) has it set aside for the units it
-- already holds or has queued (row.holds) and for each new craft (row.yield units), so a restock never leaves you
-- with items and no gold to list them. Returns nil when nothing needs crafting, else { gold, queued = cost of the
-- hand-queued entries, full = material cost of the whole restock, fullDeposit = deposits to post all of it, cost =
-- material cost of what's kept, deposit = deposits kept back for what's kept and held, short = true when it was cut,
-- keep }. keep (copper, optional) is gold the restock leaves alone on top of the deposits: buying usually costs more
-- than the last scan said, since only the cheapest listing is known.
Planner.RESTOCK_KEEP = 10000 -- copper, until the player sets their own

-- An amount typed as "1g 50s 20c" (any part alone, any order, spaces optional), in copper; a bare number is gold.
-- nil when it isn't an amount.
function Planner.ParseMoney(text)
	text = (text or ""):lower():gsub("%s+", "")
	if text == "" then return nil end
	if text:match("^%d+$") then return tonumber(text) * 10000 end
	local total, seen = 0, {}
	local rest = text:gsub("(%d+)([gsc])", function(number, unit)
		if seen[unit] then seen.bad = true end
		seen[unit] = true
		total = total + tonumber(number) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
		return ""
	end)
	if rest ~= "" or seen.bad then return nil end
	return total
end

-- Copper as "1g 50s 20c", leaving out the parts that are zero ("0c" for nothing).
function Planner.MoneyText(copper)
	copper = math.max(0, math.floor((copper or 0) + 0.5))
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end
function Planner.RestockBudget(ctx, rows, queue, gold, keep)
	keep = math.max(0, math.min(gold, math.floor(keep or 0)))
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
	-- Deposits: for what's held or queued whatever is crafted, and per craft of a row.
	local reserve, perCraft, newDeposits = 0, {}, 0
	for _, row in ipairs(rows) do
		local deposit = row.deposit or 0
		reserve = reserve + deposit * (row.holds or 0)
		perCraft[row.recipeID] = deposit * (row.yield or 1)
		if row.crafts > 0 then newDeposits = newDeposits + perCraft[row.recipeID] * row.crafts end
	end
	reserve, newDeposits = math.ceil(reserve), math.ceil(newDeposits)
	local info = { gold = gold, queued = base, full = Cost() - base, fullDeposit = reserve + newDeposits, keep = keep }
	local budget = math.max(0, gold - keep - base - reserve)
	if info.full + newDeposits <= budget then
		info.cost, info.deposit = info.full, info.fullDeposit
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
		local per = perCraft[row.recipeID]
		local function Price() return Cost() - base + math.ceil(alone.qty * per) end
		local fit = Fit(alone, row.crafts, left, Price)
		if fit < row.crafts then row.wanted, row.crafts = row.crafts, fit end
		if fit > 0 then
			left = left - Price()
			kept[#kept + 1] = { recipeID = row.recipeID, qty = fit, row = row }
		end
	end

	-- Then all of them together, cutting from the least valuable end until the real cost fits.
	for index, entry in ipairs(kept) do entries[first + index - 1] = entry end
	local function Fees()
		local fees = 0
		for _, entry in ipairs(kept) do fees = fees + entry.qty * perCraft[entry.recipeID] end
		return math.ceil(fees)
	end
	local function Price() return Cost() - base + Fees() end
	local spent = Price()
	for index = #kept, 1, -1 do
		if spent <= budget then break end
		local entry = kept[index]
		local row = entry.row
		local fit = Fit(entry, entry.qty - 1, budget, Price)
		row.wanted, row.crafts = row.wanted or (row.crafts), fit
		spent = Price()
	end
	info.cost, info.deposit, info.short = Cost() - base, reserve + Fees(), true
	return info
end

-- Listing depth. A scan only knows an item's cheapest listing, but buying fifty takes the dearer ones after it too.
-- depth = { { price, units }, ... }, cheapest first: the listings a search of that item showed (depth.more = true
-- when there are more listings than it holds). Returns what `count` units cost after the first `taken`, which are
-- spoken for: the cost (nil with nothing to price by), units bought at the auction house, units bought from the
-- vendor, and units past the last listing known.
--   ceiling   the vendor's price, if one sells it: listings at or above it are left alone and the vendor sells the rest
--   fallback  the price to count units past the last listing at, when there are no listings at all
-- Units past the last listing count at the dearest one.
function Planner.DepthCost(depth, taken, count, ceiling, fallback)
	local cost, listed, left, last = 0, 0, count, nil
	for _, tier in ipairs(depth) do
		if left <= 0 then break end
		local price, units = tier[1], tier[2]
		if ceiling and price >= ceiling then break end
		last = price
		local skipped = math.min(taken, units)
		taken = taken - skipped
		local use = math.min(units - skipped, left)
		cost, listed, left = cost + use * price, listed + use, left - use
	end
	if left <= 0 then return cost, listed, 0, 0 end
	if ceiling then return cost + left * ceiling, listed, left, 0 end
	local unit = last or fallback
	if not unit then return nil, count, 0, left end
	return cost + left * unit, count, 0, left
end

-- Camp stations a recipe needs as one key ("Fermenter", "Loom+Spinning Wheel"), nil for none.
function Planner.StationKey(recipe)
	if not recipe or not recipe.f or #recipe.f == 0 then return nil end
	local names = {}
	for _, name in ipairs(recipe.f) do table.insert(names, name) end
	table.sort(names)
	return table.concat(names, "+")
end

-- The crafts in an order that keeps every station's crafts one after another, as a station placed at a campfire
-- stands only for a while and the next can't be placed for an hour. Materials are still made before what needs
-- them (a craft can only wait for crafts listed before it, the plan's own order); crafts needing no station come
-- first, so a station's group isn't split by a material made halfway through.
function Planner.GroupByStation(ctx, crafts)
	local keys, any = {}, false
	for i, craft in ipairs(crafts) do
		keys[i] = Planner.StationKey(ctx.recipes[craft.recipeID])
		any = any or keys[i] ~= nil
	end
	if not any then return crafts end
	local makers = {}
	for i, craft in ipairs(crafts) do
		local recipe = ctx.recipes[craft.recipeID]
		if recipe and recipe.o then
			makers[recipe.o] = makers[recipe.o] or {}
			table.insert(makers[recipe.o], i)
		end
	end
	local needs = {}
	for i, craft in ipairs(crafts) do
		needs[i] = {}
		local recipe = ctx.recipes[craft.recipeID]
		for _, slot in ipairs(recipe and recipe.r or {}) do
			for s = 2, #slot do
				for _, j in ipairs(makers[slot[s]] or {}) do
					if j < i then needs[i][j] = true end
				end
			end
		end
	end
	local done, order, last = {}, {}, nil
	for _ = 1, #crafts do
		local same, plain, other
		for i = 1, #crafts do
			if not done[i] then
				local ready = true
				for j in pairs(needs[i]) do
					if not done[j] then
						ready = false
						break
					end
				end
				if ready then
					if last and keys[i] == last then
						same = i
						break
					end
					if keys[i] == nil then plain = plain or i else other = other or i end
				end
			end
		end
		local pick = same or plain or other
		done[pick] = true
		table.insert(order, crafts[pick])
		last = keys[pick]
	end
	return order
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
-- With ctx.ahDepth(itemID) (see Planner.DepthCost; nil for an item never searched) buying is costed down the
-- listings, each purchase after the ones the plan already makes of that item, so plan.cost is what the whole
-- shopping trip costs and a craft is weighed against what buying that many really costs. plan.paid[itemID] = copper
-- for the units bought at the auction house, plan.deep[itemID] = true when that came from listings, and
-- plan.thin[itemID] = units wanted beyond everything listed.
function Planner.BuildPlan(ctx, queue, farming, wanted)
	local plan = { crafts = {}, buy = {}, vendor = {}, fetch = {}, bank = {}, mail = {}, farm = {}, smelt = {}, cost = 0,
		elsewhere = {}, paid = {}, deep = {}, thin = {} }
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

	-- What buying count of an item costs: at the auction house or from a vendor, whichever is cheaper, and down the
	-- listings when they're known, after the units the plan already buys there plus `ahead` (units an estimate in
	-- progress buys). Returns the cost (nil without a price), the units from the auction house, the units from the
	-- vendor, the units past every listing, and true when listings priced it.
	local function Quote(itemID, count, ahead)
		local ah, vendor = Priced(ctx.ahPrice(itemID)), Priced(ctx.vendorPrice(itemID))
		local depth = ctx.ahDepth and ctx.ahDepth(itemID)
		if not depth then
			local useVendor = vendor and (not ah or vendor < ah)
			local unit = useVendor and vendor or ah
			return unit and unit * count, useVendor and 0 or count, useVendor and count or 0, 0, false
		end
		local cost, fromAH, fromVendor, beyond =
			Planner.DepthCost(depth, (plan.buy[itemID] or 0) + (ahead or 0), count, vendor, ah)
		return cost, fromAH, fromVendor, depth.more and 0 or beyond, true
	end

	local function Purchase(itemID, count)
		local cost, fromAH, fromVendor, beyond, deep = Quote(itemID, count)
		if fromVendor > 0 then plan.vendor[itemID] = (plan.vendor[itemID] or 0) + fromVendor end
		if fromAH > 0 then
			plan.buy[itemID] = (plan.buy[itemID] or 0) + fromAH
			if deep then plan.deep[itemID] = true end
			if beyond > 0 then plan.thin[itemID] = (plan.thin[itemID] or 0) + beyond end
		end
		if cost then
			plan.cost = plan.cost + cost
			if fromAH > 0 then
				local vendor = fromVendor > 0 and Priced(ctx.vendorPrice(itemID)) or 0
				plan.paid[itemID] = (plan.paid[itemID] or 0) + cost - fromVendor * vendor
			end
		else
			plan.unpriced = true
		end
	end

	-- Gold actually spent to get count of an item, the cheapest way this character has: what's held (bags, mail,
	-- bank, alts) costs nothing, the rest is bought or crafted, whichever spends less, with a craft's own materials
	-- costed the same way. So wool in the bank makes the cloth that makes the bolt for nothing, two steps down.
	-- taken[itemID] = stock an estimate in progress already counts on, so it isn't counted twice by two materials
	-- that need the same thing; each branch works on its own copy, as a branch not chosen takes nothing.
	-- taken[-itemID] = units the estimate already buys at the auction house, so the next ones cost what the listings
	-- after those ask. Crafting part and buying the rest is weighed too, as the cheap listings of the ore can make the
	-- first bars and the bars' own listings the rest. Returns the spend (nil when something still to get has no
	-- price), the recipe to craft with and its crafts
	-- (nil: buy all), and the taken table after it.
	local SPEND_DEPTH = 8
	local Spend

	-- plan.compare = items whose listings decide a buy-or-craft choice: the material and what a recipe makes it from,
	-- so the auction house check can read both sides and buying 50 isn't weighed at the cheapest one's price.
	plan.compare = {}
	local function NoteChoice(itemID, recipeID)
		if Priced(ctx.ahPrice(itemID)) then plan.compare[itemID] = true end
		for _, slot in ipairs(ctx.recipes[recipeID].r or {}) do
			for i = 2, #slot do
				if Priced(ctx.ahPrice(slot[i])) then plan.compare[slot[i]] = true end
			end
		end
	end

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
		local buy, buyAH = Quote(itemID, count, taken[-itemID])
		local best, bestRecipe, bestCrafts, bestTaken = buy, nil, nil, taken
		-- Noted only once every recipe has had its copy of taken: a branch that crafts doesn't buy these.
		local function Bought()
			if buy and not bestRecipe then taken[-itemID] = (taken[-itemID] or 0) + buyAH end
		end
		if depth >= SPEND_DEPTH then
			Bought()
			return best, nil, nil, taken
		end
		local function Consider(spend, recipeID, crafts, after)
			if spend and (not best or spend < best) then best, bestRecipe, bestCrafts, bestTaken = spend, recipeID, crafts, after end
		end
		for _, candidate in ipairs(ctx.known[itemID] or {}) do
			if Usable(candidate, char) then
				NoteChoice(itemID, candidate)
				local yield = MinimumYield(ctx.recipes[candidate])
				local crafts = math.ceil(count / yield)
				local function Estimate(n)
					active[candidate] = (active[candidate] or 0) + 1
					local spend, after = CraftSpend(candidate, n, char, CopyTaken(taken), depth)
					active[candidate] = active[candidate] - 1
					if active[candidate] == 0 then active[candidate] = nil end
					return spend, after
				end
				if not buy then
					local spend, after = Estimate(crafts)
					Consider(spend, candidate, crafts, after)
				else
					-- Make some and buy the rest. The first crafts use what's held and the cheapest materials, the
					-- first purchases the cheapest listings, and each side only gets dearer the more it does: so the
					-- best mix is where one more craft stops saving, found by halving. Equal spends buy, fewer steps.
					local mixes = {}
					local function Mixed(n)
						local mix = mixes[n]
						if not mix then
							local part, after = Estimate(n)
							local rest = math.max(0, count - n * yield)
							if part and rest > 0 then
								local cost, fromAH = Quote(itemID, rest, after[-itemID])
								if cost then
									after[-itemID] = (after[-itemID] or 0) + fromAH
									part = part + cost
								else
									part = nil
								end
							end
							mix = { part, after }
							mixes[n] = mix
						end
						return mix[1], mix[2]
					end
					local low, high = 0, crafts
					while low < high do
						local mid = math.floor((low + high) / 2)
						local now, more = Mixed(mid), Mixed(mid + 1)
						if more and (not now or more < now) then low = mid + 1 else high = mid end
					end
					if low > 0 then
						local spend, after = Mixed(low)
						Consider(spend, candidate, low, after)
					end
				end
			end
		end
		Bought()
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

		-- Materials you already hold cost nothing more, however deep down they're used: compare what buying and
		-- each usable recipe would actually spend, for the whole need or for the best mix of crafting part and
		-- buying the rest. Equal spends buy, which is fewer steps.
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
		Purchase(itemID, count)
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

	-- Queued writs and crates: things to have, not to craft. wanted[i] = { qty, items = { { itemID, count,
	-- buy = true for what only the auction house has (the writ or crate itself) }, ... } }. Each item comes from
	-- stock first; the rest is bought, or crafted by this character when that spends less.
	for _, want in ipairs(wanted or {}) do
		for _, item in ipairs(want.items) do
			local missing = TakeFromStock(item[1], item[2] * want.qty)
			if missing > 0 and item.buy then
				Purchase(item[1], missing)
			elseif missing > 0 then
				Acquire(item[1], missing, ctx.me)
			end
		end
	end

	-- Tools: a craft that needs a Blacksmith Hammer won't start without one in the bags, and it's easily left in the
	-- bank. One of each tool your crafts need goes on the step where it is: mailbox, bank, an alt, else a vendor.
	-- What's left in the bags after the materials are taken counts, so a rod used up as a material doesn't.
	-- plan.tools[itemID] = { name, recipeID } for what a step gets as a tool; plan.keep[itemID] = tools never to be
	-- banked for room; plan.noTool = { { name, recipeID, unknown = true when no item for it is known } }.
	plan.tools, plan.keep, plan.noTool = {}, {}, {}
	local function NeedTool(name, recipeID)
		local items = ctx.toolItems and ctx.toolItems(name) or {}
		if #items == 0 then
			table.insert(plan.noTool, { name = name, recipeID = recipeID, unknown = true })
			return
		end
		for _, itemID in ipairs(items) do
			plan.keep[itemID] = true
			Load(itemID)
		end
		for _, itemID in ipairs(items) do
			if bags[itemID] > 0 then return end
		end
		local function Get(itemID, where)
			where[itemID] = (where[itemID] or 0) + 1
			plan.tools[itemID] = { name = name, recipeID = recipeID }
		end
		for _, pool in ipairs({ { mail, plan.mail }, { bank, plan.bank } }) do
			for _, itemID in ipairs(items) do
				if pool[1][itemID] > 0 then
					pool[1][itemID] = pool[1][itemID] - 1
					return Get(itemID, pool[2])
				end
			end
		end
		for _, itemID in ipairs(items) do
			for _, alt in ipairs(AltsLeft(itemID)) do
				if alt.count > 0 then
					alt.count = alt.count - 1
					plan.fetch[alt.name] = plan.fetch[alt.name] or {}
					return Get(itemID, plan.fetch[alt.name])
				end
			end
		end
		for _, itemID in ipairs(items) do
			local price = Priced(ctx.vendorPrice(itemID))
			if price then
				plan.cost = plan.cost + price
				return Get(itemID, plan.vendor)
			end
		end
		table.insert(plan.noTool, { name = name, recipeID = recipeID })
	end
	-- Camp stations: a craft that needs a Fermenter (or a Loom...) is made beside one placed at a campfire, and placing
	-- it uses the item up. One of each station your own crafts need, plus a campfire kit for it, comes from stock
	-- first, else is bought or crafted, whichever spends less, and counts in plan.cost. Before the tools, so the
	-- campfire kit's own tool (Flint and Tinder) is on the list when the kit is crafted.
	-- plan.camp = { { name, itemID (nil: no way to get one), fire = kit itemID or nil, crafts = { plan craft, ... } } }
	-- in the order the crafts come; plan.campItems[itemID] = station name, or "Campfire" for a kit.
	plan.camp, plan.campItems = {}, {}
	if ctx.stationItems then
		local byName = {}
		for _, craft in ipairs(plan.crafts) do
			local recipe = ctx.recipes[craft.recipeID]
			if recipe and (not ctx.me or craft.char == ctx.me) then
				for _, name in ipairs(recipe.f or {}) do
					if not byName[name] then
						byName[name] = { name = name, crafts = {} }
						table.insert(plan.camp, byName[name])
					end
					table.insert(byName[name].crafts, craft)
				end
			end
		end
		-- One of these items, from stock, else the cheapest to buy or craft; nil when there's no way to get one.
		local function GetOne(items, label)
			for _, itemID in ipairs(items) do plan.keep[itemID] = true end
			for _, itemID in ipairs(items) do
				if Available(itemID) > 0 then
					TakeFromStock(itemID, 1)
					plan.campItems[itemID] = label
					return itemID
				end
			end
			local best, bestCost
			for _, itemID in ipairs(items) do
				local cost = Spend(itemID, 1, ctx.me, {}, 0)
				if cost and (not bestCost or cost < bestCost) then best, bestCost = itemID, cost end
			end
			if not best then
				-- No price to weigh it by, but a recipe makes it: farming its materials still gets one.
				for _, itemID in ipairs(items) do
					for _, recipeID in ipairs(ctx.known[itemID] or {}) do
						if not best and Usable(recipeID, ctx.me) then best = itemID end
					end
				end
			end
			if not best then return nil end
			Acquire(best, 1, ctx.me)
			plan.campItems[best] = label
			return best
		end
		for _, station in ipairs(plan.camp) do
			station.itemID = GetOne(ctx.stationItems(station.name), station.name)
			if station.itemID and ctx.campfireItems then station.fire = GetOne(ctx.campfireItems(), "Campfire") end
		end
	end
	local needed = {}
	for _, craft in ipairs(plan.crafts) do
		local recipe = ctx.recipes[craft.recipeID]
		if recipe and (not ctx.me or craft.char == ctx.me) then
			for _, name in ipairs(recipe.t or {}) do
				if not needed[name] then
					needed[name] = true
					NeedTool(name, craft.recipeID)
				end
			end
		end
	end
	if #plan.camp > 0 then plan.crafts = Planner.GroupByStation(ctx, plan.crafts) end
	return plan
end

---------------------------------------------------------------------------
-- Bag space: crafting runs that fit in the bags
---------------------------------------------------------------------------

-- A big queue can need more materials than the bags hold. Then the plan says what to put in the bank first, and when
-- that still isn't enough, only part of the queue is planned: a run, the most it can do with the room there is, made
-- of the crafts that use up the most bag room first. Once the run is crafted, the next one is planned.
--
-- space = {
--   slots        = slots in the backpack and bags, not the reagent bag
--   reagentSlots = slots in the reagent bag (0 without one)
--   usedOther    = slots taken by things the reagent bag doesn't take
--   usedReagent  = slots taken by crafting reagents, in any bag
--   bags[itemID] = units in the bags;  itemSlots[itemID] = slots they take now
--   stack(itemID) -> stack size, nil while unknown;  isReagent(itemID) -> true when the reagent bag takes it
-- }
Planner.BAG = {
	RESERVE = 1,       -- slots kept free, before and after every craft: the game wants one for the result
	DEFAULT_STACK = 20, -- stack size of an item whose data hasn't loaded
}

local function StackSlots(space, itemID, count)
	if count <= 0 then return 0 end
	return math.ceil(count / math.max(space.stack(itemID) or Planner.BAG.DEFAULT_STACK, 1))
end

-- Walks the plan as you'd do it: everything to fetch and buy goes into the bags, then each craft takes its materials
-- and adds its result. Returns the most slots it's short at any point (0 or less: it fits) and, per item already in
-- the bags, the fewest units held at any point: what the plan never touches, so it can go to the bank.
local function BagWalk(ctx, plan, space)
	local counts, low = {}, {}
	local other, reagent = space.usedOther, space.usedReagent
	local function Short()
		return other + math.max(0, reagent - space.reagentSlots) + Planner.BAG.RESERVE - space.slots
	end
	local function Count(itemID)
		if counts[itemID] == nil then
			counts[itemID] = space.bags[itemID] or 0
			low[itemID] = counts[itemID]
		end
		return counts[itemID]
	end
	local function Add(itemID, units)
		local old = Count(itemID)
		local new = old + units
		local slots = StackSlots(space, itemID, new) - StackSlots(space, itemID, old)
		if space.isReagent(itemID) then reagent = reagent + slots else other = other + slots end
		counts[itemID] = new
		if new < low[itemID] then low[itemID] = new end
	end
	-- Bags as full as they are now are only a problem once something has to go in.
	local worst, busy = -math.huge, false
	for _, group in ipairs({ plan.bank, plan.mail, plan.buy, plan.vendor }) do
		for itemID, units in pairs(group) do Add(itemID, units) busy = true end
	end
	for _, items in pairs(plan.fetch) do
		for itemID, units in pairs(items) do Add(itemID, units) busy = true end
	end
	if busy then worst = Short() end
	for _, craft in ipairs(plan.crafts) do
		local recipe = ctx.recipes[craft.recipeID]
		if recipe and (not ctx.me or craft.char == ctx.me) then
			-- The game won't start a craft without a free slot for its result, even one that frees slots.
			worst = math.max(worst, Short())
			for _, slot in ipairs(recipe.r or {}) do
				local need = (slot[1] or 1) * craft.count
				for i = 2, #slot do
					local take = math.min(Count(slot[i]), need)
					if take > 0 then
						Add(slot[i], -take)
						need = need - take
					end
				end
			end
			if recipe.o then Add(recipe.o, craft.count * MinimumYield(recipe)) end
			worst = math.max(worst, Short())
		end
	end
	if worst == -math.huge then worst = 0 end
	return worst, low
end

-- Items the add-on may tell you to bank: materials and results of known recipes. Anything else in the bags is yours
-- to decide about.
local function CraftItems(ctx)
	if ctx.craftItems then return ctx.craftItems end
	local items = {}
	for _, recipe in pairs(ctx.recipes) do
		if recipe.o then items[recipe.o] = true end
		for _, slot in ipairs(recipe.r or {}) do
			for i = 2, #slot do items[slot[i]] = true end
		end
	end
	ctx.craftItems = items
	return items
end

-- What to put in the bank so the plan fits, biggest bag hogs first, only as much as it takes. protected[itemID] =
-- never suggested (queued writs and crates, which you hand in). Returns { [itemID] = units } and the slots still
-- missing after it (0: it fits).
function Planner.MakeRoom(ctx, plan, space, protected)
	local short, low = BagWalk(ctx, plan, space)
	local bank = {}
	if short <= 0 then return bank, 0 end
	local ours = CraftItems(ctx)
	local candidates = {}
	for itemID, count in pairs(space.bags) do
		local units = math.min(low[itemID] or count, count)
		if units > 0 and ours[itemID] and not (protected and protected[itemID]) and not (plan.keep and plan.keep[itemID]) then
			local slots
			if units == count then
				slots = space.itemSlots and space.itemSlots[itemID] or StackSlots(space, itemID, count)
			else
				slots = StackSlots(space, itemID, count) - StackSlots(space, itemID, count - units)
			end
			if slots > 0 then table.insert(candidates, { itemID = itemID, units = units, slots = slots }) end
		end
	end
	table.sort(candidates, function(a, b)
		if a.slots ~= b.slots then return a.slots > b.slots end
		return a.itemID < b.itemID
	end)
	local after = {}
	for key, value in pairs(space) do after[key] = value end
	after.bags = {}
	for itemID, count in pairs(space.bags) do after.bags[itemID] = count end
	after.itemSlots = nil
	for _, candidate in ipairs(candidates) do
		if short <= 0 then break end
		local itemID = candidate.itemID
		local field = space.isReagent(itemID) and "usedReagent" or "usedOther"
		after.bags[itemID] = after.bags[itemID] - candidate.units
		after[field] = after[field] - candidate.slots
		local better = BagWalk(ctx, plan, after)
		if better < short then
			bank[itemID], short = candidate.units, better
		else
			after.bags[itemID] = after.bags[itemID] + candidate.units
			after[field] = after[field] + candidate.slots
		end
	end
	return bank, math.max(short, 0)
end

-- Bag slots one craft frees: its materials' share of a stack, less its result's. Crafts that free the most go first.
local function CraftWeight(ctx, space, recipeID)
	local recipe = ctx.recipes[recipeID]
	if not recipe then return 0 end
	local weight = 0
	for _, slot in ipairs(recipe.r or {}) do
		if slot[2] then weight = weight + (slot[1] or 1) / (space.stack(slot[2]) or Planner.BAG.DEFAULT_STACK) end
	end
	if recipe.o then weight = weight - MinimumYield(recipe) / (space.stack(recipe.o) or Planner.BAG.DEFAULT_STACK) end
	return weight
end

-- This character's queued crafts, one per recipe and crafter, and everyone else's entries as they are.
local function SplitQueue(ctx, queue)
	local own, byKey, others = {}, {}, {}
	for _, queued in ipairs(queue) do
		if (queued.qty or 0) > 0 then
			local char = ctx.crafter(queued.recipeID, queued.char)
			if not ctx.me or char == ctx.me then
				local key = Planner.RunKey(queued.recipeID, char)
				local item = byKey[key]
				if not item then
					item = { key = key, recipeID = queued.recipeID, char = char, qty = 0, order = #own + 1 }
					byKey[key] = item
					table.insert(own, item)
				end
				item.qty = item.qty + queued.qty
			else
				table.insert(others, queued)
			end
		end
	end
	return own, others
end

function Planner.RunKey(recipeID, char)
	return tostring(recipeID) .. "|" .. tostring(char)
end

-- A queue for BuildPlan: the others' entries, then this character's, in own order, each with runQty[key] crafts.
local function RunQueue(own, others, runQty)
	local queue = {}
	for _, queued in ipairs(others) do table.insert(queue, queued) end
	for _, item in ipairs(own) do
		local qty = runQty and runQty[item.key] or item.qty
		if qty > 0 then table.insert(queue, { recipeID = item.recipeID, qty = qty, char = item.char }) end
	end
	return queue
end

-- The first `crafts` crafts of own, in order.
local function FirstCrafts(own, crafts)
	local runQty = {}
	for _, item in ipairs(own) do
		local take = math.min(item.qty, crafts)
		runQty[item.key] = take
		crafts = crafts - take
	end
	return runQty
end

-- A committed run still to finish: the crafts left of it per key, or nil when it's done or no longer fits the queue
-- (an entry added or raised since). committed[key] = { start = crafts queued then, target = crafts left after it }.
local function CommittedRun(own, committed)
	if not committed then return nil end
	local runQty, left = {}, 0
	for _, item in ipairs(own) do
		local entry = committed[item.key]
		if not entry or item.qty > entry.start then return nil end
		runQty[item.key] = math.max(0, item.qty - entry.target)
		left = left + runQty[item.key]
	end
	if left == 0 then return nil end
	return runQty
end

-- Builds the buying plan with bag space in mind. Without space (bags unknown) it's BuildPlan's. When everything fits,
-- that plan as it is. Otherwise, crafts that free the most bag room come first, and:
--   plan.room = { bank = { [itemID] = units } to put in the bank first, short = slots still missing }
--   plan.run  = { qty = { [RunKey] = crafts this run }, crafts = this run's, later = crafts left for later runs }
--              when the whole queue can't fit even after the bank: the run is as big as fits, at least one craft.
-- committed = the run being worked through (returned by an earlier call; saved by the caller): kept until its crafts
-- are done, so the plan doesn't change under you halfway through. Returns the plan and the run to save (nil: none).
function Planner.SpacePlan(ctx, queue, wanted, space, committed)
	local full = Planner.BuildPlan(ctx, queue, false, wanted)
	if not space then return full, nil end
	local protected = {}
	for _, want in ipairs(wanted or {}) do
		for _, item in ipairs(want.items) do protected[item[1]] = true end
	end
	local own, others = SplitQueue(ctx, queue)
	local weights = {}
	for _, item in ipairs(own) do weights[item.key] = CraftWeight(ctx, space, item.recipeID) end
	table.sort(own, function(a, b)
		if weights[a.key] ~= weights[b.key] then return weights[a.key] > weights[b.key] end
		return a.order < b.order
	end)
	local total = 0
	for _, item in ipairs(own) do total = total + item.qty end

	local function Planned(runQty)
		local plan = Planner.BuildPlan(ctx, RunQueue(own, others, runQty), false, wanted)
		local bank, short = Planner.MakeRoom(ctx, plan, space, protected)
		plan.room = { bank = bank, short = short }
		return plan, short
	end
	local function AsRun(plan, runQty)
		local crafts = 0
		for _, qty in pairs(runQty) do crafts = crafts + qty end
		plan.run = { qty = runQty, crafts = crafts, later = total - crafts }
		return plan
	end

	local runQty = CommittedRun(own, committed)
	if BagWalk(ctx, full, space) <= 0 then return full, nil end
	if runQty then return AsRun(Planned(runQty), runQty), committed end

	local plan, short = Planned(nil)
	if short <= 0 or total <= 1 then return plan, nil end
	-- The biggest first part of the queue that fits; more crafts never need less room, so halving finds it.
	local low, high = 1, total - 1
	local best, bestQty
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local qty = FirstCrafts(own, mid)
		local tried, missing = Planned(qty)
		if missing <= 0 then
			best, bestQty, low = tried, qty, mid + 1
		else
			high = mid - 1
		end
	end
	if not best then
		bestQty = FirstCrafts(own, 1)
		best = Planned(bestQty)
	end
	local commit = {}
	for _, item in ipairs(own) do commit[item.key] = { start = item.qty, target = item.qty - bestQty[item.key] } end
	return AsRun(best, bestQty), commit
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

-- How long crafting a restock takes: each row's crafts (row.crafts new + row.queued already on the queue - row.trim
-- to come off), planned like the queue, so the sub-crafts its materials need (bars smelted, cloth woven) count too,
-- and materials held already don't. ctx without me plans every character's part. secondsOf(recipeID) = one craft,
-- as in Planner.TimeLeft. Returns seconds, crafts of the rows, crafts in all (sub-crafts included).
function Planner.RestockTime(ctx, rows, secondsOf)
	local entries, direct = {}, 0
	for _, row in ipairs(rows) do
		local qty = (row.crafts or 0) + (row.queued or 0) - (row.trim or 0)
		if qty > 0 then
			entries[#entries + 1] = { recipeID = row.recipeID, qty = qty }
			direct = direct + qty
		end
	end
	if #entries == 0 then return 0, 0, 0 end
	local seconds, count = 0, 0
	for _, craft in ipairs(Planner.BuildPlan(ctx, entries).crafts) do
		if craft.count > 0 then
			seconds, count = seconds + craft.count * secondsOf(craft.recipeID), count + craft.count
		end
	end
	return seconds, direct, count
end

return Planner
