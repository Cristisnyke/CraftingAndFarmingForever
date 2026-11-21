-- Builds RecipeSources.lua, every crafting recipe in the game and where it's learned from, out of AllTheThings' data
-- (MIT licensed). Run it with Sources.lua (tools/refresh_att.sh does both); it only needs the add-on's files:
--   lua5.1 tools/gen_recipes.lua "<AddOns>/AllTheThings/db/Camelot" > RecipeSources.lua
-- Everything about AllTheThings' file format is in att_load.lua; this file only decides what a recipe's sources are.

local root = assert(arg[1], "usage: gen_recipes.lua <AllTheThings/db/Camelot>")
local here = arg[0]:match("^(.*)/") or "."
local ATT = dofile(here .. "/att_load.lua")

-- The game version, as AllTheThings numbers patches (16001 = 1.60.1): things added later or removed by then are left out.
local GAME
for line in io.lines(here .. "/../CraftingAndFarmingForever.toc") do
	GAME = GAME or tonumber(line:match("^## Interface:%s*(%d+)"))
end
assert(GAME, "no ## Interface in the toc")

-- Crafting professions (and the gathering ones with recipes: Mining's smelts, Fishing), by skill line.
local PROFESSIONS = {
	[164] = true, [165] = true, [171] = true, [185] = true, [186] = true, [197] = true, [202] = true, [333] = true,
	[129] = true, [356] = true, [755] = true, [773] = true,
}
-- AllTheThings' header IDs that say how something is had.
local HEADER = { PROFESSIONS = -44, VENDORS = -58, WORLD_DROPS = -698, ZONE_DROPS = -63, RARES = -46, HOLIDAYS = -36,
	COMMON_BOSS_DROPS = -19 }
-- Unobtainable reasons left out: 1 never implemented, 2 removed from the game.
local GONE = { [1] = true, [2] = true }
local LIMIT = { n = 6, m = 6, q = 4, o = 4 }

local data = ATT.Load(root, { "Character", "Craftables", "ExpansionFeatures", "Holidays", "Instances", "Professions",
	"PVP", "Promotions", "Secrets", "Unsorted", "WorldDrops", "Zones" })

local function Gone(fields)
	if type(fields.u) == "number" and GONE[fields.u] then return true end
	if type(fields.rwp) == "number" and fields.rwp <= GAME then return true end
	if type(fields.awp) == "number" and fields.awp > GAME then return true end
	return false
end

local function MapsOf(fields, list)
	for _, id in ipairs(type(fields.maps) == "table" and fields.maps or {}) do table.insert(list, id) end
	if type(fields.coords) == "table" then
		for id in pairs(fields.coords) do table.insert(list, id) end
	end
	return list
end

-- recipeID -> { info = { p, s, i, b, lv, d }, sources = { ... } }
local recipes = {}

local function SourceOf(node, trail)
	local fields = node.fields
	local source = { n = {}, m = {}, q = {}, o = {}, ev = trail.event, fa = fields.r or trail.faction }
	local nearMaps = MapsOf(fields, {})
	if trail.npcFields then MapsOf(trail.npcFields, nearMaps) end
	if #nearMaps == 0 and trail.map then nearMaps = { trail.map } end
	source.m = nearMaps
	if type(fields.minReputation) == "table" then source.rep = { fields.minReputation[1], fields.minReputation[2] } end
	if type(fields.cost) == "table" then
		for _, cost in ipairs(fields.cost) do
			if type(cost) == "table" and (cost[1] == "i" or cost[1] == "c") then source.c = source.c or {} table.insert(source.c, cost) end
		end
	elseif type(fields.cost) == "number" and fields.cost > 0 then
		source.c = { { "g", 0, fields.cost } }
	end
	if fields.isLimited then source.l = 1 end
	for _, id in ipairs(type(fields.crs) == "table" and fields.crs or {}) do table.insert(source.n, id) end

	if trail.trainer then
		source.k = "t"
		table.insert(source.n, trail.npc)
		source.inst = trail.inst
	elseif trail.header == HEADER.VENDORS or trail.vendor then
		source.k = "v"
		if trail.npc then table.insert(source.n, trail.npc) end
	elseif trail.quest then
		source.k = "q"
		table.insert(source.q, trail.quest)
		for _, id in ipairs(trail.questGivers or {}) do table.insert(source.n, id) end
		if #source.m == 0 and trail.questFields then source.m = MapsOf(trail.questFields, {}) end
	elseif trail.worldDrop then
		source.k = "w"
		source.m = {}
	elseif trail.inst then
		source.k = "i"
		source.inst = trail.inst
		source.im = trail.instMap
		if trail.npc and trail.npc > 0 then table.insert(source.n, trail.npc) end
		if trail.bossDrops then source.boss = 1 end
		source.m = {}
	elseif #source.n > 0 or trail.zoneDrop or trail.rare then
		source.k = "d"
		if trail.npc and trail.npc > 0 then table.insert(source.n, trail.npc) end
		if trail.rare then source.rare = 1 end
	elseif trail.object then
		source.k = "o"
		local name = data.objectNames[trail.object]
		if name then table.insert(source.o, name) end
	else
		source.k = "x"
		source.h = trail.headerName
	end
	if fields.description then source.d = fields.description end
	source.ci = trail.container
	return source
end

local function Visit(node, trail)
	if type(node) ~= "table" or not node.kind then return end
	local fields = node.fields
	if Gone(fields) then return end
	local t = {}
	for key, value in pairs(trail) do t[key] = value end
	if fields.r then t.faction = fields.r end
	local kind, id = node.kind, node.id
	if kind == "header" then
		t.header = id
		if id == HEADER.HOLIDAYS then
			t.holidays = true
		elseif trail.holidays and not trail.event then
			t.event = data.headerNames[id]
		end
		if id == HEADER.WORLD_DROPS then t.worldDrop = true end
		if id == HEADER.ZONE_DROPS then t.zoneDrop = true end
		if id == HEADER.RARES then t.rare = true end
		if id == HEADER.VENDORS then t.vendor = true end
		if id == HEADER.COMMON_BOSS_DROPS then t.bossDrops = true end
		t.headerName = data.headerNames[id] or trail.headerName
	elseif kind == "prof" then
		t.prof = id
	elseif kind == "npc" then
		t.npc, t.npcFields = id, fields
		-- A profession's NPCs listed straight under it are its trainers.
		t.trainer = trail.header == HEADER.PROFESSIONS and trail.prof ~= nil and not trail.quest
	elseif kind == "quest" then
		t.quest, t.questFields = id, fields
		t.questGivers = type(fields.qgs) == "table" and fields.qgs or nil
		t.trainer = false
	elseif kind == "map" then
		t.map = id
	elseif kind == "inst" then
		t.inst = id
		t.instMap = type(fields.maps) == "table" and fields.maps[1] or nil
	elseif kind == "object" then
		t.object = id
	elseif kind == "item" then
		t.container = id
	end

	if kind == "recipe" and PROFESSIONS[fields.requireSkill] then
		local record = recipes[id]
		if not record then
			record = { info = {}, sources = {} }
			recipes[id] = record
		end
		local info = record.info
		info.p = info.p or fields.requireSkill
		if type(fields.learnedAt) == "number" then info.s = math.max(info.s or 0, fields.learnedAt) end
		info.i = info.i or fields.itemID
		if fields.b == 1 then info.b = 1 end
		if type(fields.lvl) == "number" then info.lv = math.max(info.lv or 0, fields.lvl) end
		table.insert(record.sources, SourceOf(node, t))
	end
	for _, child in pairs(ATT.Children(node)) do
		if type(child) == "table" and child.kind then Visit(child, t) end
	end
end

for name, category in pairs(data.categories) do
	if type(category) == "table" and category.kind then Visit(category, { cat = name }) end
end

---------------------------------------------------------------------------
-- Merge each recipe's sources: one per kind (and vendor reputation, instance, event, faction)
---------------------------------------------------------------------------

local function Unique(list, limit)
	local out, seen = {}, {}
	for _, value in ipairs(list) do
		if not seen[value] then
			seen[value] = true
			table.insert(out, value)
		end
	end
	table.sort(out, function(a, b)
		if type(a) == type(b) then return a < b end
		return tostring(a) < tostring(b)
	end)
	if limit and #out > limit then
		local cut = {}
		for i = 1, limit do cut[i] = out[i] end
		return cut, true
	end
	return out
end

local KIND_ORDER = { t = 1, v = 2, q = 3, i = 4, d = 5, o = 6, w = 7, x = 8 }

local function Merged(sources)
	local groups, order = {}, {}
	for _, source in ipairs(sources) do
		if source.k == "t" then source.fa = nil end
		local key = table.concat({ source.k, tostring(source.inst), tostring(source.ev), tostring(source.fa),
			source.rep and (source.rep[1] .. ":" .. source.rep[2]) or "", tostring(source.rare), tostring(source.h),
			tostring(source.boss), tostring(source.ci) }, "|")
		local group = groups[key]
		if not group then
			group = { k = source.k, inst = source.inst, im = source.im, ev = source.ev, fa = source.fa, rep = source.rep,
				rare = source.rare, h = source.h, boss = source.boss, ci = source.ci, n = {}, m = {}, q = {}, o = {}, d = source.d,
				c = source.c, l = source.l }
			groups[key] = group
			table.insert(order, group)
		end
		for _, field in ipairs({ "n", "m", "q", "o" }) do
			for _, value in ipairs(source[field]) do table.insert(group[field], value) end
		end
		group.d = group.d or source.d
		group.c = group.c or source.c
		group.l = group.l or source.l
	end
	for _, group in ipairs(order) do
		for _, field in ipairs({ "n", "m", "q", "o" }) do
			local list, cut = Unique(group[field], LIMIT[field])
			group[field] = list
			if cut and field == "n" then group.more = 1 end
		end
		-- Trainers in the cities and towns all teach the same: any trainer of the profession will do, so no names.
		-- One in a dungeon (Annora in Uldaman) is named.
		if group.k == "t" and not group.inst then
			group.n, group.m, group.more = {}, {}, nil
		end
	end
	table.sort(order, function(a, b)
		if a.k ~= b.k then return KIND_ORDER[a.k] < KIND_ORDER[b.k] end
		return (a.inst or 0) < (b.inst or 0)
	end)
	return order
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local function Quote(text)
	return (string.format("%q", text):gsub("\\\n", "\\n"))
end

local function Value(value)
	if type(value) == "string" then return Quote(value) end
	if type(value) == "number" then return tostring(value) end
	local parts = {}
	for index, item in ipairs(value) do parts[index] = Value(item) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function Fields(record, names)
	local parts = {}
	for _, name in ipairs(names) do
		local value = record[name]
		if type(value) == "table" and #value == 0 then value = nil end
		if value ~= nil then table.insert(parts, name .. "=" .. Value(value)) end
	end
	return table.concat(parts, ",")
end

local SOURCE_FIELDS = { "k", "n", "m", "q", "o", "inst", "im", "ci", "c", "l", "rep", "fa", "ev", "rare", "boss", "h", "d" }

local ids = {}
for recipeID, record in pairs(recipes) do
	if record.info.p and #record.sources > 0 then table.insert(ids, recipeID) end
end
table.sort(ids)

print(([[-- Crafting and Farming Forever :: RecipeSources
-- GENERATED by tools/gen_recipes.lua from AllTheThings %s. Don't edit by hand: run tools/refresh_att.sh.
-- Every crafting recipe by its spell ID: p = profession (skill line), s = skill needed, i = recipe item, b = 1 when
-- AllTheThings marks it bind on pickup, lv = character level needed, w = where it's learned from, most usual first.
-- A source: k = t trainer | v vendor | q quest | i dungeon or raid | d drop | o object | w world drop | x other;
-- n = NPC IDs, m = map IDs, q = quest IDs, o = object names, inst = instance (journal) ID, im = its map, c = costs
-- ({ "i", item, count } or { "c", currency, count }), l = 1 limited supply, rep = { faction ID, reputation },
-- fa = 1 Horde | 2 Alliance only, ev = holiday, rare = 1 rare mob, boss = 1 any boss there, ci = the item it comes in
-- (a quest reward bag, a gift), h = AllTheThings' heading, d = AllTheThings' note. A trainer source with no NPCs means
-- any trainer of the profession.
--
-- Derived from the AllTheThings add-on's data, used under its MIT License:
-- Copyright (c) 2026 AllTheThings WoW Addon
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
-- documentation files (the "Software"), to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
-- to permit persons to whom the Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of
-- the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
-- THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local _, ns = ...
ns.RECIPE_DATA_VERSION = %s
ns.RecipeData = {]]):format(data.version, Quote(data.version)))
for _, recipeID in ipairs(ids) do
	local record = recipes[recipeID]
	local sources = {}
	for index, source in ipairs(Merged(record.sources)) do sources[index] = "{" .. Fields(source, SOURCE_FIELDS) .. "}" end
	local head = Fields(record.info, { "p", "s", "i", "b", "lv" })
	print(("[%d]={%s,w={%s}},"):format(recipeID, head, table.concat(sources, ",")))
end
print("}")
