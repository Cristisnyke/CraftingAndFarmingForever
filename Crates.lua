-- Crafting and Farming Forever :: Crates
-- Waylaid Crates: what each one costs to fill (the crate plus its cheapest bundle of materials) against the
-- Merchant's Favor it pays. + on a crate queues it (Queue.Want), and the plan then gets the crate and its bundle
-- like any material.

local _, ns = ...

local Crates = {}
ns.Crates = Crates

Crates.TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan" }

-- { crate item, level, wants crafted materials, { { item, count }, ... } }: any one bundle fills the crate. From
-- Wowhead's Forever data, 2026-11-14. The unlabelled Waylaid Crate (248549) is left out: it only turns into one of
-- these.
local DATA = {
	{ 248682, 1, false, { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } }, -- Apprentice Herbs
	{ 248683, 1, false, { { 2770, 20 }, { 2771, 20 } } }, -- Apprentice Ore
	{ 248684, 1, false, { { 2589, 40 }, { 2318, 20 } } }, -- Apprentice Textiles
	{ 248685, 1, false, { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } }, -- Apprentice Curiosities
	{ 248686, 2, false, { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } }, -- Journeyman Herbs
	{ 248687, 2, false, { { 2775, 10 }, { 2772, 20 } } }, -- Journeyman Ore
	{ 248688, 2, false, { { 2592, 20 }, { 4306, 40 }, { 2319, 20 } } }, -- Journeyman Textiles
	{ 248689, 2, false, { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } }, -- Journeyman Curiosities
	{ 248690, 3, false, { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } }, -- Earthly Expert Herbs
	{ 248691, 3, false, { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } }, -- Flowering Expert Herbs
	{ 248692, 3, false, { { 2776, 10 }, { 3858, 20 } } }, -- Expert Ore
	{ 248693, 3, false, { { 4338, 40 }, { 4234, 20 } } }, -- Expert Textiles
	{ 248694, 3, false, { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } }, -- Expert Curiosities
	{ 248695, 4, false, { { 13464, 10 }, { 8838, 20 }, { 8839, 10 }, { 8845, 10 }, { 8846, 10 } } }, -- Earthly Artisan Herbs
	{ 248696, 4, false, { { 13463, 20 }, { 13465, 20 }, { 13466, 20 }, { 13467, 20 } } }, -- Flowering Artisan Herbs
	{ 248697, 4, false, { { 7911, 10 }, { 10620, 20 }, { 11370, 20 } } }, -- Artisan Ore
	{ 248698, 4, false, { { 14047, 40 }, { 4304, 20 }, { 8170, 20 } } }, -- Artisan Textiles
	{ 248699, 4, false, { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } }, -- Artisan Curiosities
	{ 248702, 1, true, { { 4231, 2 }, { 2996, 20 } } }, -- Apprentice Fabrics
	{ 248703, 1, true, { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } }, -- Apprentice Ingots
	{ 248704, 1, true, { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } }, -- Apprentice Parts
	{ 248705, 2, true, { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } }, -- Journeyman Fabrics
	{ 248706, 2, true, { { 2842, 10 }, { 3575, 20 } } }, -- Journeyman Ingots
	{ 248707, 2, true, { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } }, -- Journeyman Parts
	{ 248708, 3, true, { { 4339, 8 }, { 4236, 2 } } }, -- Expert Fabrics
	{ 248709, 3, true, { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } }, -- Expert Ingots
	{ 248710, 3, true, { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } }, -- Expert Parts
	{ 248711, 4, true, { { 14048, 8 }, { 8172, 2 } } }, -- Artisan Fabrics
	{ 248712, 4, true, { { 11371, 2 }, { 6037, 10 }, { 12359, 20 } } }, -- Artisan Ingots
	{ 248713, 4, true, { { 15994, 5 }, { 18631, 5 }, { 16000, 2 } } }, -- Artisan Parts
}

Crates.list = {}
for _, entry in ipairs(DATA) do
	local bundles = {}
	for index, bundle in ipairs(entry[4]) do bundles[index] = { item = bundle[1], count = bundle[2] } end
	table.insert(Crates.list, { id = entry[1], tier = entry[2], made = entry[3], bundles = bundles })
end

local byID = {}
for _, crate in ipairs(Crates.list) do byID[crate.id] = crate end
function Crates.ByID(crateID) return byID[crateID] end

-- The bundle to fill count of a crate with: one you already hold enough of, else the cheapest at today's prices,
-- else the first on its label.
function Crates.Fill(ctx, crate, count)
	for _, bundle in ipairs(crate.bundles) do
		if ns.Stock.Own(bundle.item) >= bundle.count * (count or 1) then return bundle end
	end
	return ns.Planner.Crate(ctx, crate).best or crate.bundles[1]
end

-- The crate's name without "Waylaid Crate: ".
function Crates.Name(crate)
	local name = ns.Items.Name(crate.id)
	return name and (name:match(":%s*(.+)$") or name) or nil
end

-- Every crate with its costs, for the level (nil = all). The second value is the row with the cheapest Merchant's
-- Favor, nil while nothing has a price.
function Crates.Rows(tier)
	local ctx = ns.NewContext()
	local rows, best = {}, nil
	for _, crate in ipairs(Crates.list) do
		if not tier or crate.tier == tier then
			local row = ns.Planner.Crate(ctx, crate)
			row.queued = ns.Queue.WantedCount("crate", crate.id)
			row.haveCrate = ns.Stock.Own(crate.id) > 0
			if row.best then row.haveFill = ns.Stock.Own(row.best.item) >= row.best.count end
			if row.perToken and (not best or row.perToken < best.perToken) then best = row end
			table.insert(rows, row)
		end
	end
	if best then best.cheapest = true end
	return rows, best
end
