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

-- Plan: empty stock. 2 shirts need 6 bolts (craft) = 12 cloth (buy) + 2 thread (vendor); sub-craft comes first.
local plan = Planner.BuildPlan(Context(), { { recipeID = 300, qty = 2, char = "me" } })
check("plan craft order first", plan.crafts[1].recipeID, 200)
check("plan sub-craft auto", plan.crafts[1].auto, true)
check("plan sub-craft count", plan.crafts[1].count, 6)
check("plan final craft", plan.crafts[2].recipeID, 300)
check("plan final not auto", plan.crafts[2].auto, false)
check("plan buys raw", plan.buy[CLOTH], 12)
check("plan no finished mat", plan.buy[BOLT], nil)
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

-- Zero-quantity entries are ignored; empty queue gives an empty plan.
check("empty plan", #Planner.BuildPlan(Context(), {}).crafts, 0)
check("zero qty", #Planner.BuildPlan(Context(), { { recipeID = 300, qty = 0 } }).crafts, 0)

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
