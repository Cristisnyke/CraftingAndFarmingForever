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
check("totals excludes unsellable and unpriced", totals.excluded, 2)
check("totals entry", totals.entries[1], 170)
check("totals no entry for unpriced", totals.entries[3], nil)

-- Restock arithmetic: AH, held and queued units all count towards the goal; batches round up.
check("restock none needed", Planner.RestockCrafts(10, 6, 4, 0, 1), 0)
check("restock over goal", Planner.RestockCrafts(1, 3, 0, 0, 1), 0)
check("restock missing", Planner.RestockCrafts(10, 2, 3, 1, 1), 4)
check("restock batches round up", Planner.RestockCrafts(10, 0, 0, 0, 3), 4)

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
check("undercut by 1c", (Planner.PostPrice({ lowest = 500 })), 499)
check("own listing kept", (Planner.PostPrice({ lowest = 500, lowestIsMine = true })), 500)
check("never below 1c", (Planner.PostPrice({ lowest = 1 })), 1)
check("scan price with no listing", (Planner.PostPrice({ scanned = 700 })), 700)
check("live price beats scan", (Planner.PostPrice({ lowest = 300, scanned = 700 })), 299)
check("nothing to go on", Planner.PostPrice({ breakEven = 100 }), nil)
local raisedPrice, raised = Planner.PostPrice({ lowest = 10, breakEven = 99.5 })
check("raised to break-even", raisedPrice, 100)
check("says it was raised", raised, true)
check("profitable not raised", select(2, Planner.PostPrice({ lowest = 500, breakEven = 100 })), nil)
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

print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
