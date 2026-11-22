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
		ahDepth = over.depth and function(id) return over.depth[id] end or nil,
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

-- Smart restock goals: recomputed from the history, oldest day first, starting at the default.
do
	local function Days(count, sold, expired)
		local days = {}
		for age = 0, count - 1 do days[#days + 1] = { age = age, s = sold, e = expired } end
		return days
	end
	local function Goal(input)
		input.margin = input.margin or 0.5 -- neutral: steps of one, a fifth expiring tolerated
		return Planner.SmartGoal(input)
	end
	local goal, info = Goal({ base = 10, days = {} })
	check("smart: no sales keeps the default", goal, 10)
	check("smart: no sales is learning", info.learning, true)
	check("smart: two results aren't enough", (Goal({ base = 1, days = Days(1, 2, 0), gap = 3 })), 1)
	check("smart: dagger default is a pair", (Goal({ base = 1, days = {}, pair = true })), 2)

	-- Sold out with no expiries: one step a day.
	goal, info = Goal({ base = 1, days = Days(1, 10, 0) })
	check("smart: a sold-out day raises the goal a step", goal, 2)
	check("smart: says it was raised", info.raised, 1)
	check("smart: three sold-out days, three steps", (Goal({ base = 1, days = Days(3, 10, 0) })), 4)
	check("smart: steps grow with the goal", (Goal({ base = 10, days = Days(1, 100, 0) })), 13)
	-- Bounded: never past what sold between two restocks, however many days sold out.
	check("smart: stops at what sold in a restock gap", (Goal({ base = 1, days = Days(20, 4, 0) })), 4)
	check("smart: a short gap between restocks needs less", (Goal({ base = 1, days = Days(20, 4, 0), gap = 0.5 })), 2)
	check("smart: a long gap needs more", (Goal({ base = 1, days = Days(20, 4, 0), gap = 2 })), 8)
	check("smart: the gap is limited", select(2, Goal({ base = 1, days = Days(3, 1, 0), gap = 40 })).gap, Planner.SMART.GAP_MAX)
	check("smart: few sold, all sold keeps the default", (Goal({ base = 10, days = Days(5, 3, 0) })), 10)
	check("smart: never over the most", (Goal({ base = 190, days = Days(30, 5000, 0) })), Planner.SMART.MAX)
	-- Auctions of today's are still up: today can't be called sold out yet.
	check("smart: not sold out while auctions run", (Goal({ base = 1, days = Days(1, 10, 0), unsettled = 0 })), 1)
	check("smart: earlier days still count then", (Goal({ base = 1, days = Days(2, 10, 0), unsettled = 0 })), 2)

	-- Expiries lower it, by the share that expired past what's tolerated.
	goal, info = Goal({ base = 10, days = { { age = 0, s = 1, e = 9 } } })
	check("smart: expiries lower the goal", goal, 3)
	check("smart: says it was lowered", info.lowered, 1)
	check("smart: a few expiring is fine", (Goal({ base = 10, days = { { age = 0, s = 9, e = 1 } } })), 10)
	check("smart: never under one", (Goal({ base = 1, days = Days(5, 0, 4) })), 1)
	-- The latest days decide: a seller that stopped selling drops at once, one that recovered climbs back.
	local stopped = { { age = 5, s = 10, e = 0 }, { age = 4, s = 10, e = 0 }, { age = 3, s = 10, e = 0 },
		{ age = 1, s = 1, e = 4 }, { age = 0, s = 0, e = 4 } }
	goal, info = Goal({ base = 1, days = stopped })
	check("smart: two bad days undo three good ones", goal, 1)
	check("smart: recent results in the info", info.recentExpired, 8)
	check("smart: old expiries, sold out since", (Goal({ base = 5, days = { { age = 6, s = 0, e = 5 },
		{ age = 2, s = 20, e = 0 }, { age = 1, s = 20, e = 0 }, { age = 0, s = 20, e = 0 } } })), 4)
	check("smart: results past the window don't count", (Goal({ base = 1, days = { { age = 40, s = 50, e = 0 } } })), 1)

	-- Profit against the deposit: a good margin steps up faster and shrugs off more expiries.
	check("smart: margin from profit and deposit", Planner.SmartMargin(900, 100), 0.9)
	check("smart: no profit, no margin", Planner.SmartMargin(-5, 100), 0)
	check("smart: deposit unknown", Planner.SmartMargin(900, nil), nil)
	local thin = Goal({ base = 1, days = Days(4, 20, 0), margin = 0.1 })
	local fat = Goal({ base = 1, days = Days(4, 20, 0), margin = 0.95 })
	check("smart: thin margin, small steps", thin, 3)
	check("smart: good margin, bigger steps", fat, 7)
	check("smart: good margin tolerates expiries", (Goal({ base = 10, days = { { age = 0, s = 7, e = 3 } }, margin = 0.95 })), 10)
	check("smart: thin margin doesn't", (Goal({ base = 10, days = { { age = 0, s = 7, e = 3 } }, margin = 0.1 })), 7)
	check("smart: unknown margin is a usual one", (Planner.SmartGoal({ base = 1, days = Days(4, 20, 0) })),
		(Planner.SmartGoal({ base = 1, days = Days(4, 20, 0), margin = Planner.SMART.MARGIN })))

	-- The slider: cautious to aggressive.
	local careful = Goal({ base = 1, days = Days(10, 10, 0), level = 0.1 })
	local normal = Goal({ base = 1, days = Days(10, 10, 0) })
	local eager = Goal({ base = 1, days = Days(10, 10, 0), level = 1 })
	check("smart: default level stocks what sold in a gap", normal, 10)
	check("smart: cautious stocks less", careful, 2)
	check("smart: aggressive stocks more", eager, 20)
	check("smart: level in the info", select(2, Goal({ base = 1, days = Days(3, 1, 0), level = 1 })).level, 1)
	check("smart: cautious drops harder", Goal({ base = 10, days = { { age = 0, s = 2, e = 8 } }, margin = 0.95, level = 0.25 })
		< Goal({ base = 10, days = { { age = 0, s = 2, e = 8 } }, margin = 0.95 }), true)

	-- It can't run away or swing: the same history always gives the same goal, and one more day moves it one step.
	local before = Goal({ base = 1, days = Days(6, 50, 0) })
	local after = Goal({ base = 1, days = Days(7, 50, 0) })
	check("smart: one more sold-out day is one more step", after - before <= math.max(1, 0.25 * before) + 1, true)
	check("smart: the same history, the same goal", Goal({ base = 1, days = Days(6, 50, 0) }), before)

	-- Gold: a quarter of 1200 buys 3 at 100 each. Nothing else in the goal looks at gold.
	goal, info = Goal({ base = 1, days = Days(20, 4, 0), unitCost = 100, gold = 1200 })
	check("smart: gold limits the goal", goal, 3)
	check("smart: says gold limited it", info.limited, "gold")
	check("smart: the goal without the gold limit is kept", info.full, 4)
	check("smart: gold-limited pair rounds down", (Goal({ base = 1, days = Days(20, 4, 0), unitCost = 100, gold = 1200,
		pair = true })), 2)
	check("smart: plenty of gold changes nothing", (Goal({ base = 1, days = Days(20, 4, 0), unitCost = 100, gold = 1e9 })), 4)
	check("smart: always at least one", (Goal({ base = 1, days = {}, unitCost = 100, gold = 0 })), 1)
	check("smart: odd goal", (Goal({ base = 1, days = Days(20, 3, 0) })), 3)
	check("smart: pairs go to the nearest pair", (Goal({ base = 1, days = Days(20, 3, 0), pair = true })), 4)
	check("smart: a pair is the least for daggers", (Goal({ base = 1, days = Days(5, 0, 4), pair = true })), 2)

	-- Deposits: expiries of cheap, short auctions move the goal less than dear, long ones.
	local short = Planner.SmartGoal({ base = 10, profit = 1000, days = { { age = 0, s = 5, e = 5, d = 5 * 20 } } })
	local long = Planner.SmartGoal({ base = 10, profit = 1000, days = { { age = 0, s = 5, e = 5, d = 5 * 600 } } })
	check("smart: cheap expiries cut little", short, 9)
	check("smart: dear expiries cut more", long, 8)
	check("smart: deposit unknown, the item's margin decides", (Planner.SmartGoal({ base = 10, profit = 1000, margin = 0.5,
		days = { { age = 0, s = 5, e = 5 } } })), (Goal({ base = 10, days = { { age = 0, s = 5, e = 5 } } })))

	-- Pausing: deposits lost lately outweigh what the sales earned. Tried again after 3 days, then 6, 12, 14.
	local function Lossy(...)
		local days = {}
		for _, age in ipairs({ ... }) do days[#days + 1] = { age = age, s = 0, e = 1, d = 300 } end
		return days
	end
	goal, info = Planner.SmartGoal({ base = 1, profit = 500, days = Lossy(2, 1, 0) })
	check("smart: losing money pauses the item", goal, 0)
	check("smart: says it's paused", info.paused, true)
	check("smart: tried again in three days", info.retryIn, 3)
	check("smart: what it lost", info.lost > info.earned, true)
	check("smart: two expiries aren't enough to pause", (Planner.SmartGoal({ base = 1, profit = 500, days = Lossy(1, 0),
		margin = 0.5 })), 1)
	check("smart: no pause without a known profit", (Planner.SmartGoal({ base = 1, days = Lossy(2, 1, 0) })), 1)
	check("smart: no pause while sales pay for the deposits", (Planner.SmartGoal({ base = 1, profit = 500,
		days = { { age = 2, s = 2, e = 1, d = 300 }, { age = 1, s = 0, e = 1, d = 300 }, { age = 0, s = 0, e = 1, d = 300 } } })), 1)
	check("smart: no pause when deposits aren't known", (Planner.SmartGoal({ base = 1, profit = 500,
		days = { { age = 2, s = 0, e = 1 }, { age = 1, s = 0, e = 1 }, { age = 0, s = 0, e = 1 } } })), 1)
	goal, info = Planner.SmartGoal({ base = 1, profit = 500, days = Lossy(5, 4, 3) })
	check("smart: three days on, one is tried", goal, 1)
	check("smart: says it's a try", info.retry, true)
	check("smart: a dagger try is a pair", (Planner.SmartGoal({ base = 1, profit = 500, days = Lossy(5, 4, 3), pair = true })), 2)
	goal, info = Planner.SmartGoal({ base = 1, profit = 500, days = Lossy(8, 7, 6, 2) })
	check("smart: a failed try pauses again", goal, 0)
	check("smart: for twice as long", info.retryIn, 6 - 2)
	check("smart: the wait stops growing", select(2, Planner.SmartGoal({ base = 1, profit = 500,
		days = Lossy(29, 28, 27, 23, 16, 3) })).retryIn, Planner.SMART.RETRY_MAX - 3)
	local recovered = Lossy(8, 7, 6)
	recovered[#recovered + 1] = { age = 2, s = 1, e = 0 }
	goal, info = Planner.SmartGoal({ base = 1, profit = 500, days = recovered })
	check("smart: a try that sells ends the pause", info.paused, nil)
	check("smart: and the goal is back", goal >= 1, true)
	recovered[#recovered + 1] = { age = 1, s = 3, e = 0 }
	check("smart: then it climbs as usual", (Planner.SmartGoal({ base = 1, profit = 500, days = recovered })), 3)
	check("smart: paused ignores gold and pairs", (Planner.SmartGoal({ base = 1, profit = 500, days = Lossy(2, 1, 0),
		pair = true, unitCost = 1, gold = 1e9 })), 0)

	-- The time between restocks: long gaps count most, time away doesn't count, too few gaps give nothing.
	local hour = 3600
	check("gap: too few restocks", Planner.RestockGap({ 0, 5 * hour, 10 * hour }), nil)
	check("gap: even restocks", Planner.RestockGap({ 0, 12 * hour, 24 * hour, 36 * hour }), 0.5)
	local uneven = Planner.RestockGap({ 0, 3 * hour, 6 * hour, 24 * hour })
	check("gap: long gaps count most", uneven > 8 / 24 and uneven < 18 / 24, true)
	check("gap: time away is left out", Planner.RestockGap({ 0, 12 * hour, 24 * hour, 36 * hour, 36 * hour + 10 * 86400 }), 0.5)
	check("gap: never under the least", Planner.RestockGap({ 0, hour, 2 * hour, 3 * hour }), Planner.SMART.GAP_MIN)
	check("gap: order doesn't matter", Planner.RestockGap({ 36 * hour, 0, 24 * hour, 12 * hour }), 0.5)
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

-- A restock already on the queue is committed: only what's still missing is asked for, it stays listed when it no
-- longer earns enough, and it's only cut back when the stock passes the goal without its gold limit.
do
	local function Rows(over)
		local opts = {
			isSellable = function() return true end,
			goal = function() return 10 end,
			stock = function() return 2, 3 end,
			queued = function() return 0 end,
			committed = function(id) if id == BAR then return 5, 5 end return 0, 0 end,
			minProfit = 100,
		}
		for key, value in pairs(over or {}) do opts[key] = value end
		for _, row in ipairs(Planner.RestockRows(restockCtx, opts)) do
			if row.itemID == BAR then return row end
		end
	end
	local row = Rows()
	check("committed: nothing more needed", row.crafts, 0)
	check("committed: crafts on the queue shown", row.queued, 5)
	check("committed: nothing to take off", row.trim, nil)
	check("committed: more needed is added on top", Rows({ goal = function() return 12 end }).crafts, 2)
	row = Rows({ goal = function() return 6 end, fullGoal = function() return 10 end })
	check("committed: a goal lowered by gold doesn't cut it", row.trim, nil)
	check("committed: and asks for nothing", row.crafts, 0)
	row = Rows({ stock = function() return 2, 6 end })
	check("committed: stock that came back cuts it", row.trim, 3)
	check("committed: never cut by more than is queued", Rows({ stock = function() return 20, 20 end }).trim, 5)
	row = Rows({ minProfit = 100000 })
	check("committed: stays listed when it earns too little", row and row.queued, 5)
	check("committed: but nothing new is asked for", row.crafts, 0)
	check("not committed, earns too little: not listed", Rows({ minProfit = 100000, committed = function() return 0, 0 end }), nil)
end

-- Fitting a restock to your gold: ore is 10 each. A (net 400 for 10 of ore) beats B (net 100 for 50 of ore).
do
	local function Budget(gold, over, queue)
		local ctx = Context({
			recipes = {
				[1] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } },
				[2] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 5, ORE } } },
			},
			known = { [BAR] = { 1 }, [SHIRT] = { 2 } },
			ah = { [ORE] = 10, [BAR] = 500, [SHIRT] = 200 },
			own = over,
		})
		local rows = {
			{ itemID = SHIRT, recipeID = 2, net = 100, crafts = 4 },
			{ itemID = BAR, recipeID = 1, net = 400, crafts = 6 },
			{ itemID = GEM, recipeID = 1, net = 1, crafts = 0 },
		}
		return rows, Planner.RestockBudget(ctx, rows, queue, gold)
	end
	local rows, info = Budget(1000)
	check("budget: enough gold, nothing cut", info.short, nil)
	check("budget: full cost", info.full, 260)
	check("budget: rows untouched", rows[1].crafts + rows[2].crafts, 10)
	check("budget: no wanted mark", rows[1].wanted, nil)

	rows, info = Budget(170)
	check("budget: short", info.short, true)
	check("budget: best earner kept whole", rows[2].crafts, 6)
	check("budget: the rest cut to what fits", rows[1].crafts, 2)
	check("budget: wanted kept", rows[1].wanted, 4)
	check("budget: spends within gold", info.cost, 160)
	check("budget: full cost still told", info.full, 260)

	rows, info = Budget(35)
	check("budget: best earner cut too", rows[2].crafts, 3)
	check("budget: nothing left for the other", rows[1].crafts, 0)
	check("budget: cost of three", info.cost, 30)

	-- Ore already held is free: 10 held cover the bars and four more ore.
	rows, info = Budget(60, { [ORE] = 10 })
	check("budget: held materials cost nothing", rows[2].crafts, 6)
	check("budget: held materials stretch the gold", rows[1].crafts, 2)
	check("budget: only bought materials count", info.cost, 60)

	-- The hand-queued bars are paid for first.
	rows, info = Budget(100, nil, { { recipeID = 1, qty = 5 } })
	check("budget: queue's cost told", info.queued, 50)
	check("budget: queue paid first", rows[2].crafts, 5)
	-- Deposits are kept back: 6 bars at 10 ore + 5 deposit each, shirts 50 + 20 each.
	local function WithDeposits(gold, holds)
		local ctx = Context({
			recipes = {
				[1] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } },
				[2] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 5, ORE } } },
			},
			known = { [BAR] = { 1 }, [SHIRT] = { 2 } },
			ah = { [ORE] = 10, [BAR] = 500, [SHIRT] = 200 },
		})
		local list = {
			{ itemID = SHIRT, recipeID = 2, net = 100, crafts = 4, deposit = 20, yield = 1 },
			{ itemID = BAR, recipeID = 1, net = 400, crafts = 6, deposit = 5, yield = 1, holds = holds },
		}
		return list, Planner.RestockBudget(ctx, list, nil, gold)
	end
	_, info = WithDeposits(370)
	check("deposits: enough for materials and posting", info.short, nil)
	check("deposits: told in full", info.fullDeposit, 110)
	rows, info = WithDeposits(300)
	check("deposits: materials alone would fit, posting doesn't", info.short, true)
	check("deposits: best earner whole", rows[2].crafts, 6)
	check("deposits: the rest cut to leave its posting gold", rows[1].crafts, 3)
	check("deposits: materials and deposits within gold", info.cost + info.deposit <= 300, true)
	check("deposits: kept back", info.deposit, 90)
	rows, info = WithDeposits(300, 10)
	check("deposits: held units are posted too", info.deposit, 50 + 30 + 40)
	check("deposits: held units leave less to craft with", rows[1].crafts, 2)
	-- Gold left alone: 20% of 370 is 74, so what fitted before no longer does.
	local function Kept(gold, keep)
		local ctx = Context({
			recipes = { [1] = { o = BAR, qmin = 1, qmax = 1, r = { { 1, ORE } } } },
			known = { [BAR] = { 1 } },
			ah = { [ORE] = 10, [BAR] = 500 },
		})
		local list = { { itemID = BAR, recipeID = 1, net = 400, crafts = 10, deposit = 5, yield = 1 } }
		return list, Planner.RestockBudget(ctx, list, nil, gold, keep)
	end
	_, info = Kept(150, 0)
	check("keep: nothing kept, all fits", info.short, nil)
	rows, info = Kept(150, 30)
	check("keep: kept gold cuts the restock", rows[1].crafts, 8)
	check("keep: told", info.keep, 30)
	check("keep: gold left after materials and posting", 150 - info.cost - info.deposit >= 30, true)
	rows, info = Kept(150, 1000)
	check("keep: never more than the gold", info.keep, 150)
	check("keep: nothing crafted", rows[1].crafts, 0)
	check("money: all three parts", Planner.ParseMoney("1g 50s 20c"), 15020)
	check("money: no spaces, capitals", Planner.ParseMoney("2G5c"), 20005)
	check("money: silver alone", Planner.ParseMoney("75s"), 7500)
	check("money: one copper", Planner.ParseMoney("1c"), 1)
	check("money: bare number is gold", Planner.ParseMoney(" 3 "), 30000)
	check("money: nonsense", Planner.ParseMoney("lots"), nil)
	check("money: a part twice", Planner.ParseMoney("1g 2g"), nil)
	check("money: empty", Planner.ParseMoney(""), nil)
	check("money text: all parts", Planner.MoneyText(15020), "1g 50s 20c")
	check("money text: zero parts left out", Planner.MoneyText(20005), "2g 5c")
	check("money text: nothing", Planner.MoneyText(0), "0c")
	check("money text: back again", Planner.ParseMoney(Planner.MoneyText(1234567)), 1234567)
	check("budget: nothing needed", select(2, (function()
		return nil, Planner.RestockBudget(Context(), { { itemID = BAR, recipeID = 100, net = 1, crafts = 0 } }, nil, 0)
	end)()), nil)
end

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

-- Levelling less what the results sell for: the vendor always, the auction house (after its cut) when ticked and more.
do
	local vendorSell = function(id) return ({ [BAR] = 4, [SHIRT] = 30 })[id] end
	local vendorOnly = Planner.SkillUpRows(Context(), {
		{ recipeID = 100, difficulty = 1, skillUps = 2 }, -- bar: 20 - 4 = 16, yellow, 2 points = 16 per point
		{ recipeID = 300, difficulty = 0 }, -- shirt: 65 - 30 = 35 per point
	}, { sellPrice = vendorSell })
	check("vendor resale: bar first", vendorOnly[1].recipeID, 100)
	check("vendor resale: back", vendorOnly[1].back, 4)
	check("vendor resale: kind", vendorOnly[1].backKind, "vendor")
	check("vendor resale: net", vendorOnly[1].net, 16)
	check("vendor resale: materials kept", vendorOnly[1].cost, 20)
	check("vendor resale: per point", vendorOnly[1].perPoint, 16)
	check("vendor resale: shirt", vendorOnly[2].perPoint, 35)
	local sellable = function(id) return id ~= BAR end
	local ah = Planner.SkillUpRows(Context(), {
		{ recipeID = 100, difficulty = 1, skillUps = 2 },
		{ recipeID = 300, difficulty = 0 }, -- shirt: 65 - 1000 x 0.95 = -885, earns
	}, { sellPrice = vendorSell, ahSellable = sellable })
	check("AH resale: earning craft first", ah[1].recipeID, 300)
	check("AH resale: back after cut", ah[1].back, 950)
	check("AH resale: kind", ah[1].backKind, "ah")
	check("AH resale: earns", ah[1].perPoint, -885)
	check("AH resale: unsellable result only vendors", ah[2].backKind, "vendor")
	local cheapAH = Planner.SkillUpRows(Context({ ah = { [ORE] = 10, [BAR] = 2 } }), {
		{ recipeID = 100, difficulty = 0 },
	}, { sellPrice = vendorSell, ahSellable = function() return true end })
	check("vendor beats a lower AH price", cheapAH[1].backKind, "vendor")
	local none = Planner.SkillUpRows(Context(), { { recipeID = 200, difficulty = 0 } }, { sellPrice = vendorSell })
	check("nothing to sell back", none[1].back, 0)
	check("nothing to sell back: per point is the cost", none[1].perPoint, 20)
end

-- A recipe pays for itself after enough crafts' profit.
check("payback rounds up", Planner.Payback(1000, 300), 4)
check("payback exact", Planner.Payback(900, 300), 3)
check("no profit never pays back", Planner.Payback(1000, 0), false)
check("loss never pays back", Planner.Payback(1000, -5), false)
check("no recipe price", Planner.Payback(nil, 300), nil)
check("no profit known", Planner.Payback(1000, nil), nil)
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

-- Restock crafting time: 2 new shirts + 1 queued (9 bolts, 3 held, so 6 woven); a bar row trimmed to nothing.
do
	local ctx = Context({ own = { [BOLT] = 3 } })
	local rows = {
		{ itemID = SHIRT, recipeID = 300, crafts = 2, queued = 1 },
		{ itemID = BAR, recipeID = 100, crafts = 0, queued = 2, trim = 2 },
	}
	local function secondsOf(id) return id == 300 and 5 or 2 end
	local seconds, direct, count = Planner.RestockTime(ctx, rows, secondsOf)
	check("restock time: shirts and the bolts they need", seconds, 3 * 5 + 6 * 2)
	check("restock time: row crafts", direct, 3)
	check("restock time: all crafts", count, 9)
	check("restock time: nothing to craft", Planner.RestockTime(ctx, { rows[2] }, secondsOf), 0)
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

-- Craftsman's Writs: the writ plus the wanted item by the cheapest path, against the pouch and the reputation.
do
	local WRIT = 900
	local function Prices(writPrice)
		return { [ORE] = 10, [BAR] = 50, [CLOTH] = 10, [BOLT] = 100, [SHIRT] = 1000, [WRIT] = writPrice }
	end
	-- The shirt is crafted for 65. A 5s writ: 5s 65c in all, the 12s pouch covers it.
	local cheap = Planner.Writ(Context({ ah = Prices(500) }), { id = WRIT, item = SHIRT, count = 1, tier = 1 })
	check("writ item crafted", cheap.kind, "craft")
	check("writ item cost", cheap.itemCost, 65)
	check("writ total", cheap.total, 565)
	check("writ pays for itself", cheap.net, 1200 - 565)
	check("free reputation", cheap.perRep, 0)
	check("craftable", cheap.craftable, true)
	-- A 50s writ: 38s 65c lost for 75 reputation.
	local dear = Planner.Writ(Context({ ah = Prices(5000) }), { id = WRIT, item = SHIRT, count = 1, tier = 1 })
	check("writ loses gold", dear.net, 1200 - 5065)
	check("gold per reputation", dear.perRep, 3865 / 75)
	-- No writ price: the item still has a cost, the rest is unknown rather than made up.
	local unpriced = Planner.Writ(Context({ ah = Prices(nil) }), { id = WRIT, item = SHIRT, count = 1, tier = 2 })
	check("unpriced writ keeps the item cost", unpriced.itemCost, 65)
	check("unpriced writ has no net", unpriced.net, nil)
	check("expert reputation", unpriced.rep, 125)
	-- Several of the item, and an item nobody crafts.
	local many = Planner.Writ(Context({ ah = Prices(500) }), { id = WRIT, item = BOLT, count = 3, tier = 3 })
	check("count multiplies the item", many.itemCost, 60)
	check("crafts for the count", many.crafts, 3)
	local bought = Planner.Writ(Context({ ah = Prices(500) }), { id = WRIT, item = CLOTH, count = 1, tier = 1 })
	check("bought item", bought.kind, "ah")
	check("not craftable", bought.craftable, false)
	-- A writ whose item isn't known here.
	check("no item, no total", Planner.Writ(Context({ ah = Prices(500) }), { id = WRIT, count = 1, tier = 3 }).total, nil)
end

-- Waylaid Crates: the crate plus its cheapest bundle, less the coin, per Merchant's Favor.
do
	local CRATE = 901
	local function Prices(cratePrice)
		return { [ORE] = 10, [BAR] = 50, [CLOTH] = 10, [BOLT] = 100, [CRATE] = cratePrice }
	end
	local bundles = { { item = BOLT, count = 10 }, { item = BAR, count = 20 } }
	-- Bolts are crafted for 20 each (200), bars smelted for less than 50 each: the cheaper bundle wins.
	local row = Planner.Crate(Context({ ah = Prices(1000) }), { id = CRATE, tier = 2, made = true, bundles = bundles })
	check("crate bundles all costed", row.bundles[1].cost, 200)
	check("crate takes the cheapest bundle", row.best, row.bundles[row.bundles[1].cost <= row.bundles[2].cost and 1 or 2])
	check("crafted crate pays 20 Favor", row.tokens, 20)
	check("crate total", row.total, 1000 + row.fillCost)
	check("gold per Favor after the coin", row.perToken, (1000 + row.fillCost - 1000) / 20)
	check("bundle crafts", row.bundles[1].crafts, 10)
	-- Gathered crate of the same level: half the Favor and coin.
	local raw = Planner.Crate(Context({ ah = Prices(1000) }), { id = CRATE, tier = 2, made = false, bundles = { { item = CLOTH, count = 40 } } })
	check("gathered crate pays 10 Favor", raw.tokens, 10)
	check("gathered per Favor", raw.perToken, (1000 + 400 - 500) / 10)
	check("journeyman is reported, not a guess", raw.rough, false)
	-- A crate cheaper than its coin costs nothing per Favor; no crate price leaves it unknown.
	local free = Planner.Crate(Context({ ah = Prices(50) }), { id = CRATE, tier = 4, made = false, bundles = { { item = ORE, count = 20 } } })
	check("coin covers it", free.perToken, 0)
	check("artisan is a guess", free.rough, true)
	local unpriced = Planner.Crate(Context({ ah = Prices(nil) }), { id = CRATE, tier = 1, made = false, bundles = { { item = ORE, count = 20 } } })
	check("unpriced crate keeps the fill", unpriced.fillCost, 200)
	check("unpriced crate has no per Favor", unpriced.perToken, nil)
	-- Queued crates and writs in the plan: the crate itself is bought, its bundle comes from stock, then the cheapest way.
	local ctx = Context({ ah = Prices(1000), own = { [CLOTH] = 30 } })
	local plan = Planner.BuildPlan(ctx, {}, false, { { qty = 2, items = { { CRATE, 1, buy = true }, { CLOTH, 40 } } } })
	check("wanted crates bought", plan.buy[CRATE], 2)
	check("wanted fill less what's held", plan.buy[CLOTH], 50)
	check("wanted cost", plan.cost, 2000 + 500)
	local crafted = Planner.BuildPlan(Context({ ah = Prices(1000) }), {}, false, { { qty = 1, items = { { CRATE, 1, buy = true }, { BOLT, 10 } } } })
	check("wanted item crafted when cheaper", crafted.crafts[1] and crafted.crafts[1].count, 10)
	check("crafted wanted item isn't bought", crafted.buy[BOLT], nil)
	local farmed = Planner.BuildPlan(Context({ ah = Prices(1000) }), {}, true, { { qty = 1, items = { { CRATE, 1, buy = true }, { ORE, 20 } } } })
	check("farming still buys the crate", farmed.buy[CRATE], 1)
	check("farming gathers the fill", farmed.farm[ORE], 20)
	local empty = Planner.Crate(Context({ ah = { [CRATE] = 500 } }), { id = CRATE, tier = 1, made = false, bundles = { { item = ORE, count = 20 } } })
	check("no bundle price, no best", empty.best, nil)
end


-- Bag space: room to bank, runs that fit, crafts freeing the most room first, a committed run kept until done.
do
	local KIT, SHIRT2, DAGGER = 40, 41, 42
	local function SpaceContext(own)
		return Planner.NewContext({
			recipes = {
				[100] = { o = BAR, qmin = 1, qmax = 1, r = { { 2, ORE } } },
				[400] = { o = KIT, qmin = 1, qmax = 1, r = { { 20, ORE } } },  -- a whole stack in, a twentieth out
				[500] = { o = SHIRT2, qmin = 1, qmax = 1, r = { { 2, CLOTH } } },
				[600] = { o = DAGGER, qmin = 1, qmax = 1, r = { { 20, ORE }, { 20, CLOTH } } }, -- two stacks in, one out
			},
			known = { [BAR] = { 100 }, [KIT] = { 400 }, [SHIRT2] = { 500 }, [DAGGER] = { 600 } },
			ahPrice = function(id) return ({ [ORE] = 10, [CLOTH] = 10, [BAR] = 500, [KIT] = 1000, [SHIRT2] = 100 })[id] end,
			vendorPrice = function() return nil end,
			ownStock = function(id) return (own or {})[id] or 0 end,
			altStock = function() return {} end,
			crafter = function() return "me" end,
			me = "me",
		})
	end
	local function Space(bags, junkSlots)
		local space = { slots = 10, reagentSlots = 0, usedOther = junkSlots or 0, usedReagent = 0, bags = {}, itemSlots = {},
			stack = function() return 20 end, isReagent = function() return false end }
		for itemID, count in pairs(bags or {}) do
			space.bags[itemID] = count
			space.itemSlots[itemID] = math.ceil(count / 20)
			space.usedOther = space.usedOther + space.itemSlots[itemID]
		end
		return space
	end
	local KEY = Planner.RunKey(400, "me")

	local fits, commit = Planner.SpacePlan(SpaceContext(), { { recipeID = 400, qty = 2 } }, nil, Space())
	check("space: fits, no run", fits.run, nil)
	check("space: fits, no room step", fits.room, nil)
	check("space: fits, nothing to commit", commit, nil)
	check("space: no space known = plain plan", (Planner.SpacePlan(SpaceContext(), { { recipeID = 400, qty = 2 } })).buy[ORE], 40)

	local empty = Planner.SpacePlan(SpaceContext(), {}, nil, Space({}, 10))
	check("space: full bags, empty queue, nothing to do", empty.room, nil)

	-- 80 cloth (4 slots) and 200 ore (10 slots) don't fit in 10 slots with one kept free.
	local queue = { { recipeID = 500, qty = 40 }, { recipeID = 400, qty = 10 } }
	local run
	run, commit = Planner.SpacePlan(SpaceContext(), queue, nil, Space())
	check("space: run planned", run.run ~= nil, true)
	check("space: run is as big as fits", run.run and run.run.crafts, 9)
	check("space: rest waits", run.run and run.run.later, 41)
	check("space: run buys only its ore", run.buy[ORE], 180)
	check("space: run buys no cloth yet", run.buy[CLOTH], nil)
	check("space: heaviest craft first", run.crafts[1] and run.crafts[1].recipeID, 400)
	check("space: commit target", commit and commit[KEY] and commit[KEY].target, 1)
	check("space: commit for the waiting entry", commit and commit[Planner.RunKey(500, "me")].target, 40)

	-- Four crafted: 100 ore and 4 kits in the bags. The run carries on with what's held, nothing new to buy.
	queue = { { recipeID = 500, qty = 40 }, { recipeID = 400, qty = 6 } }
	local again, kept = Planner.SpacePlan(SpaceContext({ [ORE] = 100, [KIT] = 4 }), queue, nil,
		Space({ [ORE] = 100, [KIT] = 4 }), commit)
	check("space: committed run kept", kept, commit)
	check("space: committed run: crafts left", again.run and again.run.crafts, 5)
	check("space: committed run: nothing to buy", again.buy[ORE], nil)

	-- Raising an entry drops the commitment and plans afresh.
	local _, fresh = Planner.SpacePlan(SpaceContext({ [ORE] = 100 }), { { recipeID = 500, qty = 40 }, { recipeID = 400, qty = 12 } },
		nil, Space({ [ORE] = 100 }), commit)
	check("space: raised entry, new run", fresh ~= commit, true)

	-- Run done (one kit left, as planned): the rest fits now, so no run.
	local after, none = Planner.SpacePlan(SpaceContext({ [KIT] = 9 }), { { recipeID = 500, qty = 40 }, { recipeID = 400, qty = 1 } },
		nil, Space({ [KIT] = 9 }), commit)
	check("space: done run, rest fits", after.run, nil)
	check("space: done run, nothing kept", none, nil)
	check("space: done run, cloth bought now", after.buy[CLOTH], 80)

	-- Nine slots of cloth the queue doesn't use: bank them, no run needed.
	local room = Planner.SpacePlan(SpaceContext(), { { recipeID = 400, qty = 1 } }, nil, Space({ [CLOTH] = 180 }))
	check("space: bank unused material", room.room and room.room.bank[CLOTH], 180)
	check("space: banking is enough", room.room and room.room.short, 0)
	check("space: banking is enough, no run", room.run, nil)

	-- Junk isn't the add-on's to move: still a slot short.
	local stuck = Planner.SpacePlan(SpaceContext(), { { recipeID = 400, qty = 1 } }, nil, Space({}, 9))
	check("space: junk not banked", stuck.room and next(stuck.room.bank), nil)
	check("space: short a slot", stuck.room and stuck.room.short, 1)

	-- Bags full, the craft would free a slot, but the game wants one free before it starts: bank something first.
	local full = Planner.SpacePlan(SpaceContext({ [ORE] = 20, [CLOTH] = 20, [BAR] = 20 }), { { recipeID = 600, qty = 1 } },
		nil, Space({ [ORE] = 20, [CLOTH] = 20, [BAR] = 20 }, 7))
	check("space: full bags, craft that frees a slot still needs one", full.room and full.room.bank[BAR], 20)
	check("space: full bags, banking one stack is enough", full.room and full.room.short, 0)
	local blocked = Planner.SpacePlan(SpaceContext({ [ORE] = 20, [CLOTH] = 20 }), { { recipeID = 600, qty = 1 } },
		nil, Space({ [ORE] = 20, [CLOTH] = 20 }, 8))
	check("space: full bags, nothing to bank, a slot short", blocked.room and blocked.room.short, 1)

	-- A queued writ's items are never sent to the bank.
	local wanted = { { qty = 1, items = { { CLOTH, 2 } } } }
	local writ = Planner.SpacePlan(SpaceContext({ [CLOTH] = 180 }), { { recipeID = 400, qty = 1 } }, wanted, Space({ [CLOTH] = 180 }))
	check("space: wanted item kept", writ.room and writ.room.bank[CLOTH], nil)
end

-- Listing depth: buying many goes down the listings, not all at the cheapest one.
do
	local ladder = { { 5, 5 }, { 10, 10 } }
	local function Cost(...) return (Planner.DepthCost(...)) end
	check("depth: 15 units", Cost(ladder, 0, 15), 125)
	check("depth: after 5 taken", Cost(ladder, 5, 5), 50)
	check("depth: across a tier", Cost(ladder, 3, 4), 2 * 5 + 2 * 10)
	local cost, fromAH, _, beyond = Planner.DepthCost(ladder, 0, 20)
	check("depth: past the last listing, at the dearest", cost, 175)
	check("depth: past the last listing, all from the AH", fromAH, 20)
	check("depth: past the last listing, units beyond", beyond, 5)
	local fromVendor
	cost, fromAH, fromVendor, beyond = Planner.DepthCost(ladder, 0, 15, 8)
	check("depth: vendor ceiling cost", cost, 25 + 10 * 8)
	check("depth: vendor ceiling, cheap ones from the AH", fromAH, 5)
	check("depth: vendor ceiling, rest from the vendor", fromVendor, 10)
	check("depth: vendor ceiling, nothing beyond", beyond, 0)
	check("depth: no listings, last scan price", Cost({}, 0, 3, nil, 7), 21)
	check("depth: no listings, no price", Cost({}, 0, 3), nil)

	-- One craft of 15 ore: 5 at 5 and 10 at 10, not 15 at 5.
	local recipes = {
		[1] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 15, ORE } } },
		[2] = { o = GEM, qmin = 1, qmax = 1, r = { { 5, ORE } } },
		[3] = { o = BOLT, qmin = 1, qmax = 1, r = { { 10, ORE } } },
	}
	local known = { [SHIRT] = { 1 }, [GEM] = { 2 }, [BOLT] = { 3 } }
	local function Ctx(depth) return Context({ recipes = recipes, known = known, ah = { [ORE] = 5 }, depth = depth }) end
	local flat = Planner.BuildPlan(Ctx(), { { recipeID = 1, qty = 1 } })
	check("depth: no listings known, cheapest price for all", flat.cost, 75)
	check("depth: no listings known, not marked", flat.deep[ORE], nil)
	local deep = Planner.BuildPlan(Ctx({ [ORE] = ladder }), { { recipeID = 1, qty = 1 } })
	check("depth: plan cost down the listings", deep.cost, 125)
	check("depth: plan buys them all", deep.buy[ORE], 15)
	check("depth: paid per item", deep.paid[ORE], 125)
	check("depth: marked", deep.deep[ORE], true)
	check("depth: nothing beyond the listings", deep.thin[ORE], nil)

	-- Two crafts wanting the same ore share the listings: the second starts where the first stopped.
	local shared = Planner.BuildPlan(Ctx({ [ORE] = ladder }), { { recipeID = 2, qty = 1 }, { recipeID = 3, qty = 1 } })
	check("depth: shared listings", shared.cost, 125)

	-- More wanted than is listed: the rest at the dearest listing, and noted; not when there are more listings.
	local thin = Planner.BuildPlan(Ctx({ [ORE] = ladder }), { { recipeID = 1, qty = 1 }, { recipeID = 2, qty = 1 } })
	check("depth: thin cost", thin.cost, 175)
	check("depth: thin units", thin.thin[ORE], 5)
	local more = Planner.BuildPlan(Ctx({ [ORE] = { { 5, 5 }, { 10, 10 }, more = true } }),
		{ { recipeID = 1, qty = 1 }, { recipeID = 2, qty = 1 } })
	check("depth: more listings than known, not thin", more.thin[ORE], nil)

	-- Bars are cheaper to buy than to smelt (15 against 20) but only two are listed at that: ten are smelted.
	local bars = { recipes = {
		[100] = { o = BAR, qmin = 1, qmax = 1, r = { { 2, ORE } } },
		[9] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, BAR } } },
	}, known = { [BAR] = { 100 }, [SHIRT] = { 9 } }, ah = { [ORE] = 10, [BAR] = 15 }, depth = { [BAR] = { { 15, 2 }, { 100, 50 } } } }
	local few = Planner.BuildPlan(Context(bars), { { recipeID = 9, qty = 2 } })
	check("depth: two bars bought", few.buy[BAR], 2)
	check("depth: two bars cost", few.cost, 30)
	local many = Planner.BuildPlan(Context(bars), { { recipeID = 9, qty = 10 } })
	-- Ten: the two cheap bars are still bought and the other eight smelted (30 + 160 = 190, not 200 for all ten).
	check("depth: ten bars, the cheap two bought", many.buy[BAR], 2)
	check("depth: ore for eight bars", many.buy[ORE], 16)
	check("depth: eight bars smelted", many.crafts[1].recipeID == 100 and many.crafts[1].count, 8)
	check("depth: smelting cost", many.cost, 190)

	-- The ore gets dear: 5 at 5, then 100 at 40. Bars sell at 30 apiece in plenty. Smelt what the cheap ore makes
	-- (2 bars from 4 ore, a 5th ore would start a bar at 45) and buy the other bars: 20 + 8 x 30 = 260.
	local dearOre = { recipes = bars.recipes, known = bars.known, ah = { [ORE] = 5, [BAR] = 30 },
		depth = { [ORE] = { { 5, 5 }, { 40, 100 } }, [BAR] = { { 30, 100 } } } }
	local mix = Planner.BuildPlan(Context(dearOre), { { recipeID = 9, qty = 10 } })
	check("split: bars smelted from the cheap ore", mix.crafts[1].recipeID == 100 and mix.crafts[1].count, 2)
	check("split: cheap ore only", mix.buy[ORE], 4)
	check("split: the rest bought", mix.buy[BAR], 8)
	check("split: cost", mix.cost, 260)
	check("split: both sides to read at the AH", mix.compare[ORE] and mix.compare[BAR], true)
	-- The plan doesn't hold the bars yet either: compare lists what would decide it before anything is bought.
	local plain = Planner.BuildPlan(Context(), { { recipeID = 300, qty = 1 } })
	check("compare: bolt and cloth", plain.compare[BOLT] and plain.compare[CLOTH], true)
	check("compare: not the queued result", plain.compare[SHIRT], nil)

	-- Same price either way: bought, one step fewer.
	local even = Planner.BuildPlan(Context({ recipes = bars.recipes, known = bars.known, ah = { [ORE] = 10, [BAR] = 20 } }),
		{ { recipeID = 9, qty = 4 } })
	check("even: bars bought", even.buy[BAR], 4)
	check("even: nothing smelted", #even.crafts, 1)

	-- A vendor item listed under the vendor's price: the cheap listings, then the vendor.
	local thread = Planner.BuildPlan(Context({
		recipes = { [1] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 6, THREAD } } } }, known = { [SHIRT] = { 1 } },
		ah = { [THREAD] = 3 }, depth = { [THREAD] = { { 3, 2 }, { 9, 10 } } },
	}), { { recipeID = 1, qty = 1 } })
	check("depth: vendor split, AH", thread.buy[THREAD], 2)
	check("depth: vendor split, vendor", thread.vendor[THREAD], 4)
	check("depth: vendor split, cost", thread.cost, 6 + 20)
	check("depth: vendor split, paid at the AH", thread.paid[THREAD], 6)
end

-- A queued restock decided again at listing depth: a restock entry is cut to the crafts that still earn enough at
-- what the materials average.
do
	local recipes = {
		[1] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, ORE } } },
		[2] = { o = GEM, qmin = 1, qmax = 1, r = { { 1, ORE } } },
	}
	local function Ctx(depth)
		return Context({ recipes = recipes, known = { [SHIRT] = { 1 }, [GEM] = { 2 } },
			ah = { [ORE] = 5, [SHIRT] = 30, [GEM] = 100 }, depth = depth })
	end
	local ladder = { [ORE] = { { 5, 5 }, { 25, 100 } } }
	local function Shirts(qty) return { recipeID = 1, qty = qty or 10, restock = true } end
	local function Round(value) return value and math.floor(value * 100 + 0.5) / 100 end

	-- 10 shirts: ore averages 15, so 13.5 a craft. Fine for a minimum of 10.
	check("restock trim: still earns, not cut", #Planner.RestockTrim(Ctx(ladder), { Shirts() }, 10), 0)

	-- Minimum 15: ore may average 13.5 at most, which 8 crafts do (12.5) and 9 don't (13.89).
	local queue = { Shirts() }
	local cuts = Planner.RestockTrim(Ctx(ladder), queue, 15)
	check("restock trim: cut to what earns", cuts[1] and cuts[1].to, 8)
	check("restock trim: crafts before the cut", cuts[1] and cuts[1].from, 10)
	check("restock trim: which entry", cuts[1] and cuts[1].index == 1 and cuts[1].recipeID, 1)
	check("restock trim: profit at the averages before the cut", cuts[1] and Round(cuts[1].net), 13.5)
	check("restock trim: the queue itself is left alone", queue[1].qty, 10)

	-- Five gems want the same ore: they earn plenty and stay, the shirts get what's left of the cheap ore.
	cuts = Planner.RestockTrim(Ctx(ladder), { { recipeID = 2, qty = 5, restock = true }, Shirts() }, 15)
	check("restock trim: shared, only the weak entry cut", #cuts == 1 and cuts[1].index, 2)
	check("restock trim: shared, weak entry cut", cuts[1] and cuts[1].to, 3)

	-- The same five gems queued by hand count too, and are never cut themselves.
	cuts = Planner.RestockTrim(Ctx({ [ORE] = { { 5, 5 }, { 500, 100 } } }), { { recipeID = 2, qty = 5 }, Shirts() }, 15)
	check("restock trim: hand-queued entry kept", #cuts == 1 and cuts[1].index, 2)
	check("restock trim: dear ore, shirts dropped", cuts[1] and cuts[1].to, 0)

	-- No listings known: nothing changes.
	check("restock trim: no listings, untouched", #Planner.RestockTrim(Ctx(), { Shirts() }, 15), 0)
	check("restock trim: nothing queued for restock", #Planner.RestockTrim(Ctx(ladder), { { recipeID = 1, qty = 10 } }, 15), 0)
end

-- Tools: a craft needing a Blacksmith Hammer won't start without one in the bags. One goes on the step where it is.
do
	local HAMMER, SPANNER, BELT, HAMMER_RECIPE = 50, 51, 52, 800
	local function ToolContext(over)
		return Planner.NewContext({
			recipes = {
				[700] = { o = BELT, qmin = 1, qmax = 1, r = { { 2, BAR } }, t = { "Blacksmith Hammer" } },
				[701] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, BAR } }, t = { "Blacksmith Hammer", "Strange Tool" } },
				[HAMMER_RECIPE] = { o = HAMMER, qmin = 1, qmax = 1, r = { { 20, ORE } } },
			},
			known = {},
			ahPrice = function(id) return ({ [BAR] = 50, [ORE] = 10 })[id] end,
			vendorPrice = function(id) return (over.vendor or {})[id] end,
			ownStock = function(id) return (over.own or {})[id] or 0 end,
			bankStock = function(id) return (over.bank or {})[id] or 0 end,
			mailStock = function(id) return (over.mail or {})[id] or 0 end,
			altStock = function(id) return (over.alts or {})[id] or {} end,
			toolItems = function(name)
				if name == "Blacksmith Hammer" then return { SPANNER + 100, HAMMER } end
				return {}
			end,
			crafter = function(_, char) return char or "me" end,
			me = "me",
		})
	end
	local queue = { { recipeID = 700, qty = 3, char = "me" } }

	local held = Planner.BuildPlan(ToolContext({ own = { [HAMMER] = 1 } }), queue)
	check("tool in bags: nothing to fetch", next(held.tools), nil)
	check("tool in bags: no note", #held.noTool, 0)
	check("tool in bags: kept", held.keep[HAMMER], true)

	local banked = Planner.BuildPlan(ToolContext({ own = { [HAMMER] = 1 }, bank = { [HAMMER] = 1 } }), queue)
	check("tool in bank: take one", banked.bank[HAMMER], 1)
	check("tool in bank: marked as the tool", banked.tools[HAMMER].name, "Blacksmith Hammer")
	check("tool in bank: for the belt", banked.tools[HAMMER].recipeID, 700)

	local mailed = Planner.BuildPlan(ToolContext({ own = {}, mail = { [HAMMER] = 1 }, bank = {} }), queue)
	check("tool in mail: collect it", mailed.mail[HAMMER], 1)

	local onAlt = Planner.BuildPlan(ToolContext({ alts = { [HAMMER] = { { name = "Alt", count = 1 } } } }), queue)
	check("tool on an alt: mail it over", onAlt.fetch.Alt and onAlt.fetch.Alt[HAMMER], 1)

	local bare = Planner.BuildPlan(ToolContext({ vendor = { [HAMMER] = 16 } }), queue)
	check("no tool, vendor sells it: buy one", bare.vendor[HAMMER], 1)
	check("no tool: its price is spent", bare.cost, 3 * 2 * 50 + 16)

	local none = Planner.BuildPlan(ToolContext({}), queue)
	check("no tool anywhere: a note", none.noTool[1] and none.noTool[1].name, "Blacksmith Hammer")
	check("no tool anywhere: a known tool", none.noTool[1] and none.noTool[1].unknown, nil)

	local two = Planner.BuildPlan(ToolContext({ bank = { [HAMMER] = 2 }, own = { [HAMMER] = 2 } }),
		{ { recipeID = 700, qty = 1, char = "me" }, { recipeID = 701, qty = 1, char = "me" } })
	check("two crafts, one hammer", two.bank[HAMMER], 1)
	check("a tool this add-on can't look for: reminder", two.noTool[1] and two.noTool[1].unknown, true)
	check("a tool this add-on can't look for: its name", two.noTool[1] and two.noTool[1].name, "Strange Tool")

	local alts = Planner.BuildPlan(ToolContext({ bank = { [HAMMER] = 1 }, own = { [HAMMER] = 1 } }),
		{ { recipeID = 700, qty = 1, char = "alt" } })
	check("another character's craft: no tool here", alts.bank[HAMMER], nil)

	-- Bags short of room: the hammer is never put away to make it, even though a recipe makes it.
	local space = { slots = 3, reagentSlots = 0, usedOther = 2, usedReagent = 0, bags = { [HAMMER] = 1 },
		itemSlots = { [HAMMER] = 1 }, stack = function() return 20 end, isReagent = function() return false end }
	local tight = Planner.SpacePlan(ToolContext({ own = { [HAMMER] = 1 } }), queue, nil, space)
	check("tight bags: hammer stays in the bags", tight.room and tight.room.bank[HAMMER], nil)
end

-- Profit for a batch: materials priced down the listings for that many crafts (the Profit tab, at the restock goal).
do
	local cloth = { [CLOTH] = { { 10, 4 }, { 30, 100 } } }
	local plain = Planner.Profit(Context({ depth = cloth }), 300)
	check("batch: no crafts, cheapest as before", plain.cost, 65)
	check("batch: no crafts, no batch", plain.batch, nil)
	local two = Planner.Profit(Context({ depth = cloth }), 300, 2)
	-- 2 shirts = 6 bolts = 12 cloth: 4 at 10 + 8 at 30 = 280, thread 2 x 5.
	check("batch: average per craft", two.cost, 145)
	check("batch: one craft at the cheapest", two.oneCost, 65)
	check("batch: net per craft", two.net, 1000 * 0.95 - 145)
	check("batch: listings read", two.deep, true)
	check("batch: nothing unread", #two.unread, 0)
	check("batch: part unit is the average", two.parts[1].unit, 280 / 6)
	check("batch: part marked deep", two.parts[1].deep, true)
	check("batch: thread part not deep", two.parts[2].deep, nil)
	local one = Planner.Profit(Context({ depth = cloth }), 300, 1)
	check("batch: one craft still walks the listings", one.cost, 4 * 10 + 2 * 30 + 5)
	local unread = Planner.Profit(Context({ depth = {} }), 300, 2)
	check("batch: unread at the cheapest", unread.cost, 65)
	check("batch: unread noted", unread.unread[1], CLOTH)
	check("batch: unread not deep", unread.deep, nil)
	local dear = Planner.Profit(Context({ depth = { [CLOTH] = { { 10, 4 }, { 200, 100 } } } }), 300, 2)
	check("batch: buying wins once cloth runs dear", dear.cost, (6 * 100 + 2 * 5) / 2)
	check("batch: bought bolts unread", dear.unread[1], BOLT)
	check("batch: no depth source, no batch", Planner.Profit(Context(), 300, 5).cost, 65)
	check("batch: craft cost for 2 shirts", Planner.CraftCostFor(Context({ depth = cloth }), SHIRT, 2), 290)
	check("batch: craft cost, unknown item", Planner.CraftCostFor(Context(), GEM, 2), nil)
end

-- The smart goal's gold limit counts what n really cost to make when costOf is given.
do
	local function CostOf(n) return n <= 5 and n * 100 or 500 + (n - 5) * 300 end
	local goal, info = Planner.SmartGoal({ base = 10, unitCost = 100, gold = 4000 })
	check("gold cap: flat cost fits", goal, 10)
	check("gold cap: flat not limited", info.limited, nil)
	goal, info = Planner.SmartGoal({ base = 10, unitCost = 100, gold = 4000, costOf = CostOf })
	check("gold cap: listings make it 6", goal, 6)
	check("gold cap: listings limit", info.limited, "gold")
	check("gold cap: full goal kept", info.full, 10)
	goal = Planner.SmartGoal({ base = 10, unitCost = 100, gold = 100, costOf = CostOf })
	check("gold cap: at least one", goal, 1)
	goal = Planner.SmartGoal({ base = 10, unitCost = 100, gold = 4000, costOf = function() return nil end })
	check("gold cap: unknown cost, flat", goal, 10)
end

-- Camp stations: a craft needing a Fermenter gets one (held, bought or crafted) plus a campfire kit, counted in the
-- cost, and the crafts needing a station come one after another.
do
	local OIL, POTION, FERMENTER, KIT, WOOD, VIAL, WHEEL, THREAD2 = 60, 61, 70, 71, 72, 73, 74, 75
	local function CampContext(over)
		return Planner.NewContext({
			recipes = {
				[900] = { o = OIL, qmin = 1, qmax = 1, r = { { 1, VIAL } }, f = { "Fermenter" } },
				[901] = { o = POTION, qmin = 1, qmax = 1, r = { { 1, VIAL } } },
				[902] = { o = SHIRT, qmin = 1, qmax = 1, r = { { 1, OIL } } },
				[903] = { o = THREAD2, qmin = 1, qmax = 1, r = { { 1, VIAL } }, f = { "Spinning Wheel" } },
				[910] = { o = FERMENTER, qmin = 1, qmax = 1, r = { { 4, VIAL } } },
				[911] = { o = KIT, qmin = 1, qmax = 1, r = { { 1, WOOD } }, t = { "Flint and Tinder" } },
			},
			known = over.known or {},
			ahPrice = function(id) return (over.ah or { [VIAL] = 10, [FERMENTER] = 500, [KIT] = 30, [WHEEL] = 900 })[id] end,
			vendorPrice = function(id) return ({ [WOOD] = 5 })[id] end,
			ownStock = function(id) return (over.own or {})[id] or 0 end,
			bankStock = function(id) return (over.bank or {})[id] or 0 end,
			mailStock = function() return 0 end,
			altStock = function() return {} end,
			toolItems = function() return {} end,
			stationItems = function(name)
				if name == "Fermenter" then return { FERMENTER } end
				if name == "Spinning Wheel" then return { WHEEL } end
				return {}
			end,
			campfireItems = function() return { KIT } end,
			campPlaced = function(items)
				for _, itemID in ipairs(items) do
					if (over.placed or {})[itemID] then return itemID end
				end
			end,
			crafter = function(_, char) return char or "me" end,
			me = "me",
		})
	end
	local queue = { { recipeID = 900, qty = 5, char = "me" } }

	local bought = Planner.BuildPlan(CampContext({}), queue)
	check("camp: one station", #bought.camp, 1)
	check("camp: its name", bought.camp[1].name, "Fermenter")
	check("camp: fermenter bought", bought.buy[FERMENTER], 1)
	check("camp: kit bought", bought.buy[KIT], 1)
	check("camp: cost counted", bought.cost, 5 * 10 + 500 + 30)
	check("camp: marked", bought.campItems[FERMENTER], "Fermenter")
	check("camp: kit marked", bought.campItems[KIT], "Campfire")
	check("camp: kept out of the bank", bought.keep[FERMENTER], true)
	check("camp: the crafts", bought.camp[1].crafts[1].recipeID, 900)

	local held = Planner.BuildPlan(CampContext({ own = { [FERMENTER] = 2, [KIT] = 1 } }), queue)
	check("camp: held fermenter, nothing to buy", held.buy[FERMENTER], nil)
	check("camp: held kit, nothing to buy", held.buy[KIT], nil)
	check("camp: held, no cost", held.cost, 50)

	local banked = Planner.BuildPlan(CampContext({ own = { [FERMENTER] = 1 }, bank = { [FERMENTER] = 1 } }), queue)
	check("camp: banked fermenter taken out", banked.bank[FERMENTER], 1)

	local crafted = Planner.BuildPlan(CampContext({ known = { [FERMENTER] = { 910 }, [KIT] = { 911 } } }), queue)
	check("camp: cheaper to craft the fermenter", crafted.buy[FERMENTER], nil)
	check("camp: kit crafted from wood", crafted.vendor[WOOD], 1)
	check("camp: cost of crafting", crafted.cost, 5 * 10 + 4 * 10 + 5)

	local none = Planner.BuildPlan(CampContext({ ah = { [VIAL] = 10 } }), queue)
	check("camp: no way to get one", none.camp[1].itemID, nil)
	check("camp: no kit for nothing", none.camp[1].fire, nil)

	local mixed = Planner.BuildPlan(CampContext({}), {
		{ recipeID = 900, qty = 1, char = "me" }, { recipeID = 901, qty = 1, char = "me" },
		{ recipeID = 903, qty = 1, char = "me" }, { recipeID = 900, qty = 2, char = "me" },
	})
	local order = {}
	for _, craft in ipairs(mixed.crafts) do table.insert(order, craft.recipeID) end
	check("camp: no station first, then each station's crafts together", table.concat(order, ","), "901,900,903")
	check("camp: two stations", #mixed.camp, 2)

	local chain = Planner.BuildPlan(CampContext({ known = { [OIL] = { 900 } } }), {
		{ recipeID = 902, qty = 2, char = "me" }, { recipeID = 901, qty = 1, char = "me" },
	})
	order = {}
	for _, craft in ipairs(chain.crafts) do table.insert(order, craft.recipeID) end
	check("camp: the oil still before what needs it", table.concat(order, ","), "901,900,902")

	local plain = Planner.BuildPlan(CampContext({}), { { recipeID = 901, qty = 1, char = "me" } })
	check("camp: none needed", #plain.camp, 0)
	check("camp: no kit", plain.buy[KIT], nil)
	check("camp: alt's craft, nothing here", #Planner.BuildPlan(CampContext({}), { { recipeID = 900, qty = 1, char = "alt" } }).camp, 0)
	-- The player's report: placing the kit used it up, and the plan asked for another one from the bank.
	local lit = Planner.BuildPlan(CampContext({ placed = { [KIT] = true }, bank = { [KIT] = 1 } }), queue)
	check("camp: placed fire, nothing from the bank", lit.bank[KIT], nil)
	check("camp: placed fire, nothing bought", lit.buy[KIT], nil)
	check("camp: placed fire said", lit.camp[1].firePlaced, true)
	check("camp: placed fire costs nothing", lit.cost, 5 * 10 + 500)
	check("camp: station still wanted", lit.buy[FERMENTER], 1)
	local standing = Planner.BuildPlan(CampContext({ placed = { [KIT] = true, [FERMENTER] = true } }), queue)
	check("camp: placed station, nothing bought", standing.buy[FERMENTER], nil)
	check("camp: placed station said", standing.camp[1].placed, true)
	check("camp: placed, only the crafts cost", standing.cost, 5 * 10)
	-- One campfire for every station.
	local twoStations = Planner.BuildPlan(CampContext({}), {
		{ recipeID = 900, qty = 1, char = "me" }, { recipeID = 903, qty = 1, char = "me" },
	})
	check("camp: one kit for two stations", twoStations.buy[KIT], 1)
	check("camp: both stations at that fire", twoStations.camp[2].fire, KIT)
	local order2 = Planner.GroupByStation(CampContext({}), { { recipeID = 901 }, { recipeID = 902 } })
	check("camp: order untouched without stations", order2[1].recipeID, 901)
end

-- Usual prices: median of the daily lows of the last 14 days, needs 3 days.
do
	check("normal: no days", Planner.NormalPrice(nil, 100), nil)
	check("normal: two days say nothing", Planner.NormalPrice({ [99] = 50, [100] = 60 }, 100), nil)
	check("normal: odd count median", Planner.NormalPrice({ [98] = 50, [99] = 200, [100] = 60 }, 100), 60)
	check("normal: even count median", Planner.NormalPrice({ [97] = 40, [98] = 50, [99] = 200, [100] = 60 }, 100), 55)
	check("normal: older than 14 days left out", Planner.NormalPrice({ [86] = 999, [98] = 50, [99] = 60 }, 100), nil)
	check("normal: day 87 still counts", Planner.NormalPrice({ [87] = 70, [98] = 50, [99] = 60 }, 100), 60)
	-- The player's case: crafted for 1g, listed at 1g40 during a spike, usually 60s. Profit counts 60s: a loss.
	local ctx = Context()
	ctx.normalPrice = function(id) return ({ [SHIRT] = 600 })[id] end
	local result = Planner.Profit(ctx, 300)
	check("spike: flagged", result.spiked, true)
	check("spike: listed kept", result.listedUnit, 1000)
	check("spike: counted at normal", result.saleUnit, 600)
	check("spike: ratio", math.floor(result.ofNormal * 100 + 0.5), 167)
	check("spike: net at normal", result.net, 600 * 0.95 - 65)
	-- 10% above normal: counted at normal, not flagged.
	local mild = Context()
	mild.normalPrice = function(id) return ({ [SHIRT] = 910 })[id] end
	result = Planner.Profit(mild, 300)
	check("mild: not flagged", result.spiked, nil)
	check("mild: counted at normal", result.saleUnit, 910)
	-- Below normal: the current price counts.
	local cheap = Context()
	cheap.normalPrice = function(id) return ({ [SHIRT] = 2000 })[id] end
	result = Planner.Profit(cheap, 300)
	check("below normal: current price", result.saleUnit, 1000)
	check("below normal: no flag", result.atNormal, nil)
	-- No usual price yet: unchanged.
	local none = Context()
	none.normalPrice = function() return nil end
	check("no normal: unchanged", Planner.Profit(none, 300).saleUnit, 1000)
	-- With the cap too: whichever is lower counts; a capped row isn't also marked as a spike in the queue.
	local both = Context()
	both.priceCap = { max = 4, normal = 2 }
	both.normalPrice = function(id) return ({ [SHIRT] = 500 })[id] end
	result = Planner.Profit(both, 300)
	check("cap + normal: lower counts", result.saleUnit, 130)
	check("cap + normal: listed is the AH price", result.listedUnit, 1000)
	check("cap + normal: ratio from the listing", result.ofNormal, 2)
	local totals = Planner.QueueTotals(ctx, { { recipeID = 300, qty = 1 } }, function() return true end)
	check("queue totals: spike ratio", totals.spiked[1] ~= nil, true)
	check("queue totals: capped not spiked", Planner.QueueTotals(both, { { recipeID = 300, qty = 1 } }, function() return true end).spiked[1], nil)
end

-- Bank alt mode: postage comes off the profit; what's mailed keeps what the queue needs and a crafter's own materials.
do
	local ctx = Context()
	ctx.postage = function(recipeID) return recipeID == 300 and Planner.PostagePerUnit(1) or nil end
	local result = Planner.Profit(ctx, 300)
	check("postage: per craft", result.postage, 30)
	check("postage: off the profit", result.net, 885 - 30)
	check("postage: stack of 20", Planner.PostagePerUnit(20), 1.5)
	check("postage: none without bank alt", Planner.Profit(Context(), 300).postage, nil)
	local mails, cost = Planner.MailCost(13)
	check("mail cost: 13 stacks = 2 mails", mails, 2)
	check("mail cost: postage", cost, 390)

	local send = Planner.SellerSend({
		items = { [SHIRT] = { bags = 5, bank = 2 }, [BOLT] = { bags = 4, bank = 10 }, [BAR] = { bags = 3, bank = 0 } },
		reserved = { [BOLT] = 6, [BAR] = math.huge },
		limit = function(id) return id == BOLT and 5 or nil end,
	})
	check("send: all shirts from the bags", send.bags[SHIRT], 5)
	check("send: shirts from the bank", send.bank[SHIRT], 2)
	check("send: queue's bolts kept, bags first", send.bags[BOLT], nil)
	check("send: own material only as far as the AH lacks", send.bank[BOLT], 5)
	check("send: tool kept", send.bags[BAR], nil)
	check("send: units", send.units, 12)
	check("send: nothing", Planner.SellerSend({ items = { [SHIRT] = { bags = 1 } }, reserved = { [SHIRT] = 1 } }), nil)
	check("send: limit below zero", Planner.SellerSend({ items = { [BOLT] = { bags = 3 } }, reserved = {},
		limit = function() return -4 end }), nil)
end

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
