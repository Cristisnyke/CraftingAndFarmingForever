-- Plain Lua 5.1 tests for Planner.lua: lua tests/planner_test.lua (from the repo root)

local Planner = dofile("Planner.lua")

local failures, checks = 0, 0
local function check(name, actual, expected)
	checks = checks + 1
	if actual ~= expected then
		failures = failures + 1
		print(("FAIL %s: expected %s, got %s"):format(name, tostring(expected), tostring(actual)))
	end
end

local ORE, BAR, THREAD, CLOTH, BOLT, SHIRT, GEM = 1, 2, 3, 4, 5, 6, 7

local function Context(over)
	over = over or {}
	return Planner.NewContext({
		recipes = over.recipes or {
			[100] = { o = BAR, qmin = 1, qmax = 1, r = { { 2, ORE } } },
			[200] = { o = BOLT, qmin = 1, qmax = 1, r = { { 2, CLOTH } } },
			[300] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 3, BOLT }, { 1, THREAD } } },
		},
		known = over.known or { [BAR] = { 100 }, [BOLT] = { 200 }, [SHIRT] = { 300 } },
		ahPrice = function(id) return (over.ah or { [ORE] = 10, [BAR] = 50, [CLOTH] = 10, [BOLT] = 100, [SHIRT] = 1000 })[id] end,
		vendorPrice = function(id) return (over.vendor or { [THREAD] = 5 })[id] end,
		ownStock = function(id) return (over.own or {})[id] or 0 end,
		altStock = function(id) return (over.alts or {})[id] or {} end,
		crafter = function() return "me" end,
	})
end

-- Crafting a material wins when cheaper: bolt costs 20 to craft vs 100 to buy.
local unit, kind, recipe = Planner.ItemCost(Context(), BOLT)
check("craft cheaper unit", unit, 20)
check("craft cheaper kind", kind, "craft")
check("craft cheaper recipe", recipe, 200)

-- Buying wins when cheaper.
unit, kind = Planner.ItemCost(Context({ ah = { [CLOTH] = 100, [BOLT] = 50 } }), BOLT)
check("buy cheaper unit", unit, 50)
check("buy cheaper kind", kind, "ah")

-- Vendor wins over a pricier AH listing.
unit, kind = Planner.ItemCost(Context({ ah = { [THREAD] = 50 } }), THREAD)
check("vendor unit", unit, 5)
check("vendor kind", kind, "vendor")

-- Profit: 3 bolts (20 each) + thread 5 = 65; sale 1000 less 5% = 950; net 885.
local profit = Planner.Profit(Context(), 300)
check("cost", profit.cost, 65)
check("net", profit.net, 885)

-- No sale price, or a material with no price at all: no net, never a made-up number.
check("no sale price", Planner.Profit(Context({ ah = { [ORE] = 10, [CLOTH] = 10 } }), 300).net, nil)
check("unpriced material", Planner.Profit(Context({ ah = { [SHIRT] = 1000, [BOLT] = 100 }, vendor = {} }), 300).net, nil)

-- Multi-yield recipes divide cost by the average yield.
local yieldCtx = Context({
	recipes = { [1] = { o = BAR, qmin = 2, qmax = 4, r = { { 3, ORE } } } },
	known = { [BAR] = { 1 } },
})
check("average yield", (Planner.ItemCost(yieldCtx, BAR)), 10)

-- Alternative reagents use the cheapest.
local altCtx = Context({
	recipes = { [1] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, ORE, CLOTH } } } },
	known = { [SHIRT] = { 1 } },
	ah = { [ORE] = 90, [CLOTH] = 30, [SHIRT] = 1000 },
})
check("cheapest alternative", (Planner.RecipeCost(altCtx, 1)), 30)

-- Cycles terminate and fall back to the buy price.
local cycleCtx = Context({
	recipes = {
		[1] = { o = ORE, qmin = 1, qmax = 1, r = { { 1, BAR } } },
		[2] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } },
	},
	known = { [ORE] = { 1 }, [BAR] = { 2 } },
	ah = { [ORE] = 10, [BAR] = 20 },
})
check("cycle cost", (Planner.ItemCost(cycleCtx, BAR)), 10)
local cyclePlan = Planner.BuildPlan(cycleCtx, { { recipeID = 2, qty = 1 } })
check("cycle plan buys", cyclePlan.buy[ORE], 1)

-- Materials you already hold are used before buying. Bars are cheaper on the AH (50) than smelted from AH ore
-- (2 x 10 + nothing), but with 4 ore in the bank the 2 bars cost nothing more to make. Seen 2026-11-08 with Tin Ore.
do
	local queue = { { recipeID = 300, qty = 1 } }
	local recipes = {
		[100] = { o = BAR, qmin = 1, qmax = 1, r = { { 2, ORE } } },
		[300] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 2, BAR } } },
	}
	local function StockContext(own, bank, ah)
		local ctx = Context({ recipes = recipes, known = { [BAR] = { 100 }, [SHIRT] = { 300 } }, own = own,
			ah = ah or { [ORE] = 30, [BAR] = 50, [SHIRT] = 1000 } })
		ctx.bankStock = function(id) return (bank or {})[id] or 0 end
		return ctx
	end
	local held = Planner.BuildPlan(StockContext({ [ORE] = 4 }, { [ORE] = 4 }), queue)
	check("held ore: bars not bought", held.buy[BAR], nil)
	check("held ore: ore not bought", held.buy[ORE], nil)
	check("held ore: smelts the bars", held.crafts[1].recipeID, 100)
	check("held ore: says to take it from the bank", held.bank[ORE], 4)
	check("held ore: spends nothing", held.cost, 0)

	-- Some ore held: it makes one bar for nothing, and the other is bought (50) rather than smelted from bought ore
	-- (2 x 30 = 60).
	local partial = Planner.BuildPlan(StockContext({ [ORE] = 2 }), queue)
	check("some ore: smelts one bar", partial.crafts[1].count, 1)
	check("some ore: buys the other bar", partial.buy[BAR], 1)
	check("some ore: buys no ore", partial.buy[ORE], nil)
	check("some ore: bags need no bank trip", next(partial.bank), nil)
	-- With cheap ore the other bar is smelted from bought ore: 2 x 20 = 40 < 50.
	local cheap = Planner.BuildPlan(StockContext({ [ORE] = 2 }, nil, { [ORE] = 20, [BAR] = 50, [SHIRT] = 1000 }), queue)
	check("cheap ore: smelts both", cheap.crafts[1].count, 2)
	check("cheap ore: buys the missing ore", cheap.buy[ORE], 2)
	check("cheap ore: no bars bought", cheap.buy[BAR], nil)
	-- With dear ore the held ore still makes its bar; the other is bought, not smelted from 2 x 80 ore.
	local dear = Planner.BuildPlan(StockContext({ [ORE] = 2 }, nil, { [ORE] = 80, [BAR] = 50, [SHIRT] = 1000 }), queue)
	check("dear ore: buys one bar", dear.buy[BAR], 1)
	check("dear ore: smelts the other", dear.crafts[1].count, 1)
	check("dear ore: cost is one bar", dear.cost, 50)

	-- Farming takes from the bags before the bank and lists only what the bank must supply.
	local farm = Planner.BuildPlan(StockContext({ [ORE] = 4 }, { [ORE] = 3 }), queue, true)
	check("farm: bank part listed", farm.bank[ORE], 3)
	check("farm: nothing to gather", next(farm.farm), nil)
end

-- Plan: empty stock. 2 shirts need 6 bolts (craft) = 12 cloth (buy) + 2 thread (vendor); sub-craft comes first.
local plan = Planner.BuildPlan(Context(), { { recipeID = 300, qty = 2, char = "me" } })
check("plan craft order first", plan.crafts[1].recipeID, 200)
check("plan sub-craft auto", plan.crafts[1].auto, true)
check("plan sub-craft count", plan.crafts[1].count, 6)
check("plan final craft", plan.crafts[2].recipeID, 300)
check("plan final not auto", plan.crafts[2].auto, false)
check("plan buys raw", plan.buy[CLOTH], 12)
check("plan no finished mat", plan.buy[BOLT], nil)
check("plan sub-craft subCount", plan.crafts[1].subCount, 6)
check("plan final subCount", plan.crafts[2].subCount, 0)

-- A recipe queued by hand and also needed for another queued craft: one craft of the combined count, with the
-- material part kept apart so it can still be listed as a sub-craft. Seen 2026-11-09: 20 Smelt Tin queued plus
-- bronze needing 10 more tin bars, Craft Next said x30 and the window showed only the 20.
do
	local merged = Planner.BuildPlan(Context(), {
		{ recipeID = 200, qty = 20, char = "me" },
		{ recipeID = 300, qty = 2, char = "me" },
	})
	check("merged: one bolt craft", merged.crafts[1].recipeID, 200)
	check("merged: combined count", merged.crafts[1].count, 26)
	check("merged: sub-craft part", merged.crafts[1].subCount, 6)
	check("merged: not only a sub-craft", merged.crafts[1].auto, false)
end
check("plan vendor", plan.vendor[THREAD], 2)

-- Own stock reduces purchases and sub-crafts at each level.
plan = Planner.BuildPlan(Context({ own = { [BOLT] = 2, [CLOTH] = 3, [THREAD] = 5 } }),
	{ { recipeID = 300, qty = 2, char = "me" } })
check("stock sub-craft count", plan.crafts[1].count, 4)
check("stock buys remainder", plan.buy[CLOTH], 5)
check("stock vendor covered", plan.vendor[THREAD], nil)

-- Alt stock is used after own stock and reported as a pickup.
plan = Planner.BuildPlan(Context({ own = { [CLOTH] = 2 }, alts = { [CLOTH] = { { name = "Alt", count = 4 } } } }),
	{ { recipeID = 200, qty = 5, char = "me" } })
check("alt pickup", plan.fetch.Alt[CLOTH], 4)
check("alt remainder bought", plan.buy[CLOTH], 4)

-- Stock is shared across entries, not counted twice.
plan = Planner.BuildPlan(Context({ own = { [CLOTH] = 3 } }),
	{ { recipeID = 200, qty = 1 }, { recipeID = 200, qty = 1 } })
check("stock not double counted", plan.buy[CLOTH], 1)
check("same recipe merged", #plan.crafts, 1)
check("merged count", plan.crafts[1].count, 2)

-- A multi-yield sub-craft leaves surplus for the next entry.
local surplusCtx = Context({
	recipes = {
		[1] = { o = BAR, qmin = 5, qmax = 5, r = { { 1, ORE } } },
		[2] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 3, BAR } } },
		[3] = { o = GEM, qmin = 1, qmax = 1, r = { { 2, BAR } } },
	},
	known = { [BAR] = { 1 }, [SHIRT] = { 2 }, [GEM] = { 3 } },
	ah = { [ORE] = 1, [BAR] = 100, [SHIRT] = 1000, [GEM] = 1000 },
})
plan = Planner.BuildPlan(surplusCtx, { { recipeID = 2, qty = 1 }, { recipeID = 3, qty = 1 } })
check("surplus used", plan.buy[ORE], 1)

-- Held materials count however deep they're used. Wool makes cloth makes bolt; the shirt's bolt is dearer to craft
-- at market (2 cloth x 10 = 20 vs 18 on the AH), but with wool in the bags it costs nothing: craft all the way down.
do
	local WOOL = 9
	local recipes = {
		[10] = { o = CLOTH, qmin = 1, qmax = 1, r = { { 2, WOOL } } },
		[20] = { o = BOLT, qmin = 1, qmax = 1, r = { { 2, CLOTH } } },
		[30] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, BOLT } } },
	}
	local known = { [CLOTH] = { 10 }, [BOLT] = { 20 }, [SHIRT] = { 30 } }
	local ah = { [WOOL] = 8, [CLOTH] = 10, [BOLT] = 18, [SHIRT] = 100 }
	local bare = Planner.BuildPlan(Context({ recipes = recipes, known = known, ah = ah }), { { recipeID = 30, qty = 1 } })
	check("no wool: buys the bolt", bare.buy[BOLT], 1)
	local deep = Planner.BuildPlan(Context({ recipes = recipes, known = known, ah = ah, own = { [WOOL] = 4 } }),
		{ { recipeID = 30, qty = 1 } })
	check("held wool: no bolt bought", deep.buy[BOLT], nil)
	check("held wool: nothing bought", next(deep.buy), nil)
	check("held wool: makes the cloth", deep.crafts[1].recipeID, 10)
	check("held wool: two cloth", deep.crafts[1].count, 2)
	check("held wool: then the bolt", deep.crafts[2].recipeID, 20)
	check("held wool: spends nothing", deep.cost, 0)

	-- Two bolts, 4 wool: the second bolt's wool can't be counted again. With cheap wool (4 more at 4 = 16 < a bolt
	-- at 18) both bolts are crafted and the wool bought.
	local cheapWool = { [WOOL] = 4, [CLOTH] = 10, [BOLT] = 18, [SHIRT] = 100 }
	local shared = Planner.BuildPlan(Context({ recipes = recipes, known = known, ah = cheapWool, own = { [WOOL] = 4 } }),
		{ { recipeID = 30, qty = 2 } })
	check("shared wool: no bolt bought", shared.buy[BOLT], nil)
	check("shared wool: buys the missing wool", shared.buy[WOOL], 4)
	check("shared wool: both bolts crafted", shared.crafts[2].count, 2)
	-- With wool at 8 (32 for the missing wool, more than a bolt) the held wool still makes one bolt for nothing,
	-- and only the other is bought: 18, not 32 or 36.
	local part = Planner.BuildPlan(Context({ recipes = recipes, known = known, ah = ah, own = { [WOOL] = 4 } }),
		{ { recipeID = 30, qty = 2 } })
	check("part wool: one bolt bought", part.buy[BOLT], 1)
	check("part wool: no wool bought", part.buy[WOOL], nil)
	check("part wool: one bolt crafted", part.crafts[2].count, 1)
	check("part wool: cost is one bolt", part.cost, 18)
	-- Smelting with 6 ore held when ore is dearer than bars: smelt 6, buy 4 bars, not 10 bars.
	local ore = Planner.BuildPlan(Context({
		recipes = { [1] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } }, [2] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 10, BAR } } } },
		known = { [BAR] = { 1 }, [SHIRT] = { 2 } }, ah = { [ORE] = 200, [BAR] = 50, [SHIRT] = 5000 }, own = { [ORE] = 6 },
	}), { { recipeID = 2, qty = 1 } })
	check("held ore, dear ore: smelts the six", ore.crafts[1].count, 6)
	check("held ore, dear ore: buys four bars", ore.buy[BAR], 4)
	check("held ore, dear ore: buys no ore", ore.buy[ORE], nil)
end

-- A price of zero is no price, not a free material or a worthless result.
do
	local zero = Context({ ah = { [ORE] = 0, [BAR] = 50, [CLOTH] = 10, [BOLT] = 100, [SHIRT] = 0 } })
	local bar = Planner.Profit(zero, 100)
	check("zero material price: no cost", bar.cost, nil)
	check("zero sale price: no sale", Planner.Profit(zero, 300).saleUnit, nil)
end

-- Whole-batch crafting that costs more than buying the small amount needed: buy instead.
local batchCtx = Context({
	recipes = {
		[1] = { o = BAR, qmin = 5, qmax = 5, r = { { 5, ORE } } },
		[2] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, BAR } } },
	},
	known = { [BAR] = { 1 }, [SHIRT] = { 2 } },
	ah = { [ORE] = 5, [BAR] = 10, [SHIRT] = 1000 },
})
plan = Planner.BuildPlan(batchCtx, { { recipeID = 2, qty = 1 } })
check("small need buys", plan.buy[BAR], 1)
check("small need no batch", plan.buy[ORE], nil)
plan = Planner.BuildPlan(batchCtx, { { recipeID = 2, qty = 5 } })
check("full batch crafts", plan.buy[ORE], 5)
check("full batch skips buying", plan.buy[BAR], nil)

-- A recipe that also costs a currency has an unknown cost, not a free slot.
local currencyCtx = Context({
	recipes = { [1] = { o = SHIRT, qmin = 1, qmax = 1, x = true, r = { { 1, ORE } } } },
	known = { [SHIRT] = { 1 } },
})
check("currency cost unknown", Planner.Profit(currencyCtx, 1).net, nil)

-- Cycle fallback still prefers a vendor over the AH.
local vendorCycle = Context({
	recipes = {
		[1] = { o = ORE, qmin = 1, qmax = 1, r = { { 1, BAR } } },
		[2] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } },
	},
	known = { [ORE] = { 1 }, [BAR] = { 2 } },
	ah = {},
	vendor = { [ORE] = 4 },
})
plan = Planner.BuildPlan(vendorCycle, { { recipeID = 2, qty = 1 } })
check("cycle vendor", plan.vendor[ORE], 1)
check("cycle not on AH", plan.buy[ORE], nil)

-- Queue totals: profit of everything queued, unsellable or unpriced entries counted separately.
local totalsCtx = Context({
	recipes = {
		[1] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, ORE } } },
		[2] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } },
		[3] = { o = GEM, qmin = 1, qmax = 1, r = { { 1, ORE } } },
	},
	known = {},
	ah = { [ORE] = 10, [SHIRT] = 100, [BAR] = 500 },
})
local totals = Planner.QueueTotals(totalsCtx, {
	{ recipeID = 1, qty = 2 },
	{ recipeID = 2, qty = 1 },
	{ recipeID = 3, qty = 1 },
}, function(id) return id ~= BAR end)
check("totals net", totals.net, 2 * (95 - 10))
check("totals revenue", totals.revenue, 190)
check("totals cost", totals.cost, 20)
check("totals excludes unsellable and unpriced", totals.excluded, 1)
check("totals entry", totals.entries[1], 170)
check("totals no entry for unpriced", totals.entries[3], nil)
check("unsellable counted apart", totals.bound, 1)
check("unsellable cost", totals.boundCost, 10)
check("unsellable entry", totals.boundEntries[2], 10)
check("unsellable has no profit entry", totals.entries[2], nil)
local unknown = Planner.QueueTotals(totalsCtx, { { recipeID = 2, qty = 1 } }, function() return nil end)
check("still loading isn't called unsellable", unknown.bound, 0)
check("still loading is unpriced", unknown.excluded, 1)

-- Restock arithmetic: AH, held and queued units all count towards the goal; batches round up.
check("restock none needed", Planner.RestockCrafts(10, 6, 4, 0, 1), 0)
check("restock over goal", Planner.RestockCrafts(1, 3, 0, 0, 1), 0)
check("restock missing", Planner.RestockCrafts(10, 2, 3, 1, 1), 4)
check("restock batches round up", Planner.RestockCrafts(10, 0, 0, 0, 3), 4)

-- Smart restock goals.
do
	local function Days(count, sold, expired)
		local days = {}
		for age = 0, count - 1 do days[#days + 1] = { age = age, s = sold, e = expired } end
		return days
	end
	local goal, info = Planner.SmartGoal({ base = 10, days = {}, coverDays = 1 })
	check("smart: no sales keeps the default", goal, 10)
	check("smart: no sales is learning", info.learning, true)
	check("smart: two results aren't enough", (Planner.SmartGoal({ base = 1, days = Days(1, 2, 0), span = 1 })), 1)
	check("smart: dagger default is a pair", (Planner.SmartGoal({ base = 1, days = {}, pair = true })), 2)

	-- Two a day, all sold, two-day auctions: 2 x 2 x 1.5.
	goal, info = Planner.SmartGoal({ base = 1, days = Days(14, 2, 0), span = 14, coverDays = 2 })
	check("smart: good seller gets more", goal, 6)
	check("smart: rate per day", math.floor(info.perDay * 100 + 0.5), 200)
	check("smart: all sold", info.soldShare, 1)
	check("smart: half expiring gets no extra", (Planner.SmartGoal({ base = 1, days = Days(14, 2, 2), span = 14, coverDays = 2 })), 4)

	-- Mostly expiring: under the default. Selling everything you listed, however little: never under it.
	check("smart: expiries lower the goal", (Planner.SmartGoal({ base = 10, days = { { age = 0, s = 1, e = 9 } }, span = 1 })), 1)
	check("smart: few listed, all sold keeps the default", (Planner.SmartGoal({ base = 10, days = { { age = 0, s = 3, e = 0 } }, span = 1 })), 10)

	-- Old sales fade.
	local recent = Planner.SmartGoal({ base = 1, days = { { age = 0, s = 20, e = 0 } }, span = 29 })
	local old = Planner.SmartGoal({ base = 1, days = { { age = 28, s = 20, e = 0 } }, span = 29 })
	check("smart: recent sales count more", recent > old, true)
	check("smart: results past the window don't count", (Planner.SmartGoal({ base = 1, days = { { age = 40, s = 50, e = 0 } }, span = 41 })), 1)

	-- Gold: a quarter of 1200 buys 3 at 100 each.
	goal, info = Planner.SmartGoal({ base = 1, days = Days(14, 2, 0), span = 14, coverDays = 2, unitCost = 100, gold = 1200 })
	check("smart: gold limits the goal", goal, 3)
	check("smart: says gold limited it", info.limited, "gold")
	check("smart: gold-limited pair rounds down", (Planner.SmartGoal({ base = 1, days = Days(14, 2, 0), span = 14,
		coverDays = 2, unitCost = 100, gold = 1200, pair = true })), 2)
	check("smart: always at least one", (Planner.SmartGoal({ base = 1, days = {}, unitCost = 100, gold = 0 })), 1)
	check("smart: pairs round up", (Planner.SmartGoal({ base = 1, days = Days(14, 1, 0), span = 14, coverDays = 2 })), 3)
	check("smart: pairs round up to even", (Planner.SmartGoal({ base = 1, days = Days(14, 1, 0), span = 14, coverDays = 2,
		pair = true })), 4)
end

-- Restock rows: only sellable, profitable items above the minimum, best recipe per item, needed items first.
local restockCtx = Context({
	recipes = {
		[1] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, ORE } } },
		[2] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 5, ORE } } },
		[3] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } },
		[4] = { o = BOLT, qmin = 1, qmax = 1, r = { { 1, ORE } } },
		[5] = { o = GEM, qmin = 1, qmax = 1, r = { { 1, ORE } } },
		[6] = { o = CLOTH, qmin = 1, qmax = 1, r = { { 1, ORE } } },
	},
	known = { [SHIRT] = { 1, 2 }, [BAR] = { 3 }, [BOLT] = { 4 }, [GEM] = { 5 }, [CLOTH] = { 6 } },
	ah = { [ORE] = 10, [SHIRT] = 1000, [BAR] = 500, [BOLT] = 5, [GEM] = 2000, [CLOTH] = 12 },
})
local restockRows = Planner.RestockRows(restockCtx, {
	isSellable = function(id) return id ~= GEM end,
	goal = function(id) return id == BAR and 10 or 1 end,
	stock = function(id) if id == SHIRT then return 1, 0 end return 2, 3 end,
	queued = function(id) return id == BAR and 1 or 0 end,
	minProfit = 100,
})
check("restock row count", #restockRows, 2)
check("restock needed first", restockRows[1].itemID, BAR)
check("restock counts AH, held, queued", restockRows[1].crafts, 4)
check("restock stocked row last", restockRows[2].itemID, SHIRT)
check("restock stocked needs none", restockRows[2].crafts, 0)
check("restock best recipe", restockRows[2].recipeID, 1)

-- Zero-quantity entries are ignored; empty queue gives an empty plan.
-- Per character: on the paladin (blacksmith and miner) the plan holds only the paladin's crafts and purchases. The
-- tailor alt's shirt is only noted for later; its bolts in the tailor's bags are kept for it, and the paladin's own
-- recipe needing bolts buys them, since only the tailor can make bolts.
do
	local knows = { pal = { [100] = true, [400] = true }, tai = { [200] = true, [300] = true } }
	local function Split(over)
		local ctx = Context(over)
		ctx.recipes[400] = { o = GEM, qmin = 1, qmax = 1, r = { { 2, BOLT } } }
		ctx.known[GEM] = { 400 }
		ctx.me = "pal"
		ctx.knows = function(char, recipeID) return knows[char] ~= nil and knows[char][recipeID] == true end
		ctx.charName = function(char) return ({ pal = "Pal", tai = "Tai" })[char] end
		ctx.crafter = function(recipeID, preferred)
			if ctx.knows("pal", recipeID) then return "pal" end
			if ctx.knows(preferred, recipeID) then return preferred end
			return "tai"
		end
		return ctx
	end
	local queue = { { recipeID = 100, qty = 2, char = "pal" }, { recipeID = 300, qty = 1, char = "tai" } }
	local split = Planner.BuildPlan(Split(), queue)
	check("only own crafts planned", #split.crafts, 1)
	check("own craft kept", split.crafts[1].recipeID, 100)
	check("own materials bought", split.buy[ORE], 4)
	check("alt's cloth not bought here", split.buy[CLOTH], nil)
	check("alt's bolts not bought here", split.buy[BOLT], nil)
	check("alt's thread not bought here", split.vendor[THREAD], nil)
	check("alt's crafts noted", split.elsewhere.tai, 1)
	check("cost is only this character's", split.cost, 40)

	local reserve = Planner.BuildPlan(Split({ alts = { [BOLT] = { { name = "Tai", count = 3 } } } }),
		{ { recipeID = 300, qty = 1, char = "tai" }, { recipeID = 400, qty = 1, char = "pal" } })
	check("alt's bolts kept for its shirt", reserve.fetch.Tai, nil)
	check("bolts the alt makes are bought here", reserve.buy[BOLT], 2)
	check("no bolt crafting on the paladin", #reserve.crafts, 1)

	local spare = Planner.BuildPlan(Split({ alts = { [BOLT] = { { name = "Tai", count = 5 } } } }),
		{ { recipeID = 300, qty = 1, char = "tai" }, { recipeID = 400, qty = 1, char = "pal" } })
	check("alt's spare bolts can be mailed", spare.fetch.Tai and spare.fetch.Tai[BOLT], 2)
	check("nothing to buy then", spare.buy[BOLT], nil)

	local farmed = Planner.BuildPlan(Split(), queue, true)
	check("farming: alt's cloth not gathered here", farmed.farm[CLOTH], nil)
	check("farming: own ore gathered", farmed.farm[ORE], 4)
end

-- Bought items waiting in the mailbox count as owned: taken after the bags, before the bank, and never bought again.
do
	local ctx = Context({ own = { [CLOTH] = 1 } })
	ctx.mailStock = function(id) return ({ [CLOTH] = 2 })[id] or 0 end
	ctx.bankStock = function() return 0 end
	local mailed = Planner.BuildPlan(ctx, { { recipeID = 200, qty = 2 } })
	check("mail used after bags", mailed.mail[CLOTH], 2)
	check("only the rest bought", mailed.buy[CLOTH], 1)
	ctx = Context({ own = { [CLOTH] = 4 } })
	ctx.bankStock = function(id) return ({ [CLOTH] = 4 })[id] or 0 end
	ctx.mailStock = function(id) return ({ [CLOTH] = 3 })[id] or 0 end
	local order = Planner.BuildPlan(ctx, { { recipeID = 200, qty = 2 } })
	check("mailbox before the bank", order.mail[CLOTH], 3)
	check("bank for the rest", order.bank[CLOTH], 1)
end

check("empty plan", #Planner.BuildPlan(Context(), {}).crafts, 0)
check("zero qty", #Planner.BuildPlan(Context(), { { recipeID = 300, qty = 0 } }).crafts, 0)

-- Farming: nothing from the AH, makes what it can, vendor items stay on the vendor list.
do
	local recipes = {
		[100] = { o = BAR, qmin = 1, qmax = 1, r = { { 2, ORE } } },
		[300] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 2, BAR }, { 1, THREAD }, { 3, CLOTH } } },
	}
	local function FarmContext(over)
		over = over or {}
		return Planner.NewContext({
			recipes = recipes,
			known = over.known or { [BAR] = { 100 }, [SHIRT] = { 300 } },
			ahPrice = function(id) return ({ [ORE] = 1, [BAR] = 1, [CLOTH] = 5 })[id] end,
			vendorPrice = function(id) return id == THREAD and 10 or nil end,
			ownStock = function(id) return (over.own or {})[id] or 0 end,
			altStock = function() return {} end,
			crafter = function() return "me" end,
			smelting = over.smelting,
		})
	end
	local queue = { { recipeID = 300, qty = 2 } }

	local plan = Planner.BuildPlan(FarmContext(), queue, true)
	check("farm: nothing to buy at AH", next(plan.buy), nil)
	check("farm: crafts bar even when buying is cheaper", plan.crafts[1].recipeID, 100)
	check("farm: bar quantity", plan.crafts[1].count, 4)
	check("farm: raw ore listed", plan.farm[ORE], 8)
	check("farm: cloth listed", plan.farm[CLOTH], 6)
	check("farm: vendor item stays vendor", plan.vendor[THREAD], 2)
	check("farm: only vendor costs gold", plan.cost, 20)
	check("buy plan unchanged by the option", Planner.BuildPlan(FarmContext(), queue).buy[CLOTH], 6)

	plan = Planner.BuildPlan(FarmContext({ own = { [CLOTH] = 4, [ORE] = 3 } }), queue, true)
	check("farm: owned materials not farmed", plan.farm[CLOTH], 2)
	check("farm: owned ore not farmed", plan.farm[ORE], 5)

	-- A bar with no known recipe is smelted from ore, in whole smelts.
	local smelting = { [BAR] = { yield = 2, { 3, ORE } } }
	plan = Planner.BuildPlan(FarmContext({ known = { [SHIRT] = { 300 } }, smelting = smelting }), { { recipeID = 300, qty = 1 } }, true)
	check("smelt: bars listed", plan.smelt[BAR], 2)
	check("smelt: ore from the formula", plan.farm[ORE], 3)
	plan = Planner.BuildPlan(FarmContext({ known = { [SHIRT] = { 300 } }, smelting = smelting }), { { recipeID = 300, qty = 3 } }, true)
	check("smelt: rounds up to whole smelts", plan.smelt[BAR], 6)

	-- Two recipes that make each other's material must not loop.
	local cycle = {
		[1] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, GEM } } },
		[2] = { o = GEM, qmin = 1, qmax = 1, r = { { 1, BAR } } },
	}
	local ctx = FarmContext({ known = { [BAR] = { 1 }, [GEM] = { 2 } } })
	ctx.recipes = cycle
	plan = Planner.BuildPlan(ctx, { { recipeID = 1, qty = 1 } }, true)
	check("farm: cycle ends in a farm entry", plan.farm[BAR], 1)
end

-- Posting: how many, at what price, and what the queue still needs.
check("post what the goal lacks", Planner.PostQuantity(10, 3, 20, 0), 7)
check("post no more than held", Planner.PostQuantity(10, 3, 4, 0), 4)
check("queue's share stays", Planner.PostQuantity(10, 3, 4, 3), 1)
check("goal met posts none", Planner.PostQuantity(10, 12, 4, 0), 0)
check("queue needs them all", Planner.PostQuantity(10, 0, 4, 9), 0)
check("matches the lowest", (Planner.PostPrice({ lowest = 500 })), 500)
check("never below 1c", (Planner.PostPrice({ lowest = 1 })), 1)
check("scan price with no listing", (Planner.PostPrice({ scanned = 700 })), 700)
check("live price beats scan", (Planner.PostPrice({ lowest = 300, scanned = 700 })), 300)
check("nothing to go on", Planner.PostPrice({ breakEven = 100 }), nil)
local raisedPrice, raised = Planner.PostPrice({ lowest = 10, breakEven = 99.5 })
check("raised to break-even", raisedPrice, 100)
check("says it was raised", raised, true)
check("profitable not raised", select(2, Planner.PostPrice({ lowest = 500, breakEven = 100 })), nil)
check("vendor pays more", Planner.BelowVendor(300, 286, 0.05), true)
check("same as the vendor is fine", Planner.BelowVendor(300, 285, 0.05), false)
check("no vendor price", Planner.BelowVendor(300, 0, 0.05), false)
check("vendor price not loaded", Planner.BelowVendor(300, nil, 0.05), false)
check("whole silver matches the lowest", (Planner.PostPrice({ lowest = 500, wholeSilver = true })), 500)
check("whole silver rounds an odd lowest down", (Planner.PostPrice({ lowest = 367, wholeSilver = true })), 300)
check("whole silver scan rounds down", (Planner.PostPrice({ scanned = 750, wholeSilver = true })), 700)
check("whole silver at least 1s", (Planner.PostPrice({ lowest = 100, wholeSilver = true })), 100)

-- Levelling: cheapest expected cost per skill point first; grey and unknown colours left out.
do
	local ctx = Context()
	local rows = Planner.SkillUpRows(ctx, {
		{ recipeID = 300, difficulty = 0 }, -- shirt: 3 bolts (20 each crafted) + thread 5 = 65 per point
		{ recipeID = 200, difficulty = 2 }, -- bolt: 20, green 25% = 80 per point
		{ recipeID = 100, difficulty = 1, skillUps = 2 }, -- bar: 20, yellow 50%, 2 points = 20 per point
		{ recipeID = 999, difficulty = 0 }, -- unknown recipe
	})
	check("skill rows", #rows, 3)
	check("cheapest per point first", rows[1].recipeID, 100)
	check("per point uses chance and points", rows[1].perPoint, 20)
	check("orange next", rows[2].recipeID, 300)
	check("orange per point is the cost", rows[2].perPoint, 65)
	check("green last", rows[3].recipeID, 200)
	check("green per point", rows[3].perPoint, 80)
	check("grey gives nothing", #Planner.SkillUpRows(ctx, { { recipeID = 100, difficulty = 3 } }), 0)
	check("no colour, not listed", #Planner.SkillUpRows(ctx, { { recipeID = 100 } }), 0)
	local unpriced = Planner.SkillUpRows(Context({ ah = { [ORE] = 10 } }), {
		{ recipeID = 200, difficulty = 0 }, { recipeID = 100, difficulty = 2 },
	})
	check("no price goes last", unpriced[2].perPoint, nil)
end
do
	local price, wasRaised = Planner.PostPrice({ lowest = 300, breakEven = 391, wholeSilver = true })
	check("whole silver break-even rounds up", price, 400)
	check("whole silver says it was raised", wasRaised, true)
	check("exact break-even keeps its silver", (Planner.PostPrice({ lowest = 300, breakEven = 400.00000000000006, wholeSilver = true })), 400)
end
do
	local ctx = Context()
	check("craft cost per unit", Planner.CraftUnitCost(ctx, SHIRT), (3 * 20 + 5))
	check("no recipe, no cost", Planner.CraftUnitCost(ctx, ORE), nil)
	local reserved = Planner.ReservedMaterials(ctx, { crafts = { { recipeID = 300, count = 2 }, { recipeID = 200, count = 6 } } })
	check("direct material", reserved[BOLT], 6)
	check("sub-craft material", reserved[CLOTH], 12)
	check("vendor material", reserved[THREAD], 2)
	check("result not reserved", reserved[SHIRT], nil)
end

-- Craft time left: own crafts only, the casting recipe from its live count and cast.
do
	local crafts = {
		{ recipeID = 100, count = 5, char = "me" },
		{ recipeID = 200, count = 20, char = "me" },
		{ recipeID = 300, count = 4, char = "alt" },
	}
	local function secondsOf(id) return id == 100 and 2 or 3 end
	local run, all, count = Planner.TimeLeft(crafts, "me", secondsOf)
	check("idle: no run", run, nil)
	check("idle: all seconds", all, 5 * 2 + 20 * 3)
	check("idle: all crafts, alt's left out", count, 25)
	-- Crafting the 20: 13 to go including the one being cast, 1.5 s left on it; the plan still says 14.
	crafts[2].count = 14
	run, all, count = Planner.TimeLeft(crafts, "me", secondsOf, { recipeID = 200, left = 13, castLeft = 1.5 })
	check("run seconds", run, 1.5 + 12 * 3)
	check("all includes run", all, 10 + 1.5 + 12 * 3)
	check("all count uses live count", count, 18)
	-- Paused between batches: no cast.
	run = Planner.TimeLeft(crafts, "me", secondsOf, { recipeID = 200, left = 13 })
	check("paused run seconds", run, 39)
	-- Casting something not in the plan.
	run, all = Planner.TimeLeft(crafts, "me", secondsOf, { recipeID = 900, left = 1, castLeft = 2 })
	check("unplanned cast", run, 2)
	check("unplanned cast in all", all, 5 * 2 + 14 * 3 + 2)
	check("duration seconds", Planner.FormatDuration(44.6), "45s")
	check("duration minutes", Planner.FormatDuration(187), "3:07")
	check("duration hours", Planner.FormatDuration(3725), "1:02:05")
end

-- Price cap: shirt materials 65, listed at 1000 (over 400%): counted at 200% = 130, flagged to check.
do
	local ctx = Context()
	ctx.priceCap = { max = 4, normal = 2 }
	local capped = Planner.Profit(ctx, 300)
	check("capped flag", capped.capped, true)
	check("capped listed price kept", capped.listedUnit, 1000)
	check("capped sale at normal", capped.saleUnit, 130)
	check("capped net", capped.net, 130 * 0.95 - 65)
	-- At or under the limit nothing changes: 260 = exactly 400%.
	local fair = Context({ ah = { [ORE] = 10, [BAR] = 50, [CLOTH] = 10, [BOLT] = 100, [SHIRT] = 260 } })
	fair.priceCap = { max = 4, normal = 2 }
	local result = Planner.Profit(fair, 300)
	check("price at the limit not capped", result.capped, nil)
	check("price at the limit kept", result.saleUnit, 260)
	-- Without a cap (option off) the listing is used as it is.
	check("no cap, no flag", Planner.Profit(Context(), 300).capped, nil)
	-- Yield counts: 2 bars from 2 ore (20) = 10 a bar; 50 is 500% -> 20 a bar.
	local yieldCtx = Context({ recipes = { [100] = { o = BAR, qmin = 2, qmax = 2, r = { { 2, ORE } } } }, known = { [BAR] = { 100 } } })
	yieldCtx.priceCap = { max = 4, normal = 2 }
	check("cap per unit with yield", Planner.Profit(yieldCtx, 100).saleUnit, 20)
	-- Queue totals mark the capped entry.
	local totals = Planner.QueueTotals(ctx, { { recipeID = 300, qty = 2 } }, function() return true end)
	check("queue totals flag capped", totals.capped[1], true)
	check("queue totals use capped price", totals.net, (130 * 0.95 - 65) * 2)
end

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
