-- Builds Sources.lua, the table of where crafting materials come from, out of AllTheThings' data (MIT licensed).
-- Run with lua5.1 when AllTheThings gets a meaningful update. It only needs the add-on's files, not the game:
--   lua5.1 tools/gen_sources.lua "<AddOns>/AllTheThings/db/Camelot" > Sources.lua
-- Forever loads the Camelot data set, which is what the awp=16001 entries in it show.

local root = assert(arg[1], "usage: gen_sources.lua <AllTheThings/db/Camelot>")

local PROFESSION_KIND = { [186] = "mine", [182] = "herb", [393] = "skin", [356] = "fish" }
local KIND_OF_CONSTRUCTOR = {
	CreateItem = "item", CreateItemSource = "itemsource", CreateNPC = "npc", CreateObject = "object", CreateMap = "map",
	CreateProfession = "prof", CreateQuest = "quest", CreateInstance = "inst", CreateSpell = "spell",
	CreateRecipe = "recipe", CreateAchievement = "ach", CreateHeader = "header", CreateCustomHeader = "header",
}

local function Node(kind)
	return function(id, a, b)
		local fields = a
		if kind == "itemsource" then
			kind, id, fields = "item", a, b
		end
		return { kind = kind, id = id, fields = type(fields) == "table" and fields or {} }
	end
end

local app = setmetatable({}, { __index = function(t, key)
	local value
	if KIND_OF_CONSTRUCTOR[key] then
		value = Node(KIND_OF_CONSTRUCTOR[key])
	elseif type(key) == "string" and key:find("^Create") then
		value = Node("other")
	else
		value = setmetatable({}, { __index = function() return "" end, __call = function() return {} end })
	end
	rawset(t, key, value)
	return value
end })

local handlers = {}
app.AddEventHandler = function(_, handler) table.insert(handlers, handler) end

local function ReadFile(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return (text:gsub("^\239\187\191", ""))
end

local function Run(path)
	assert(loadstring(ReadFile(path), path))("AllTheThings", app)
end

-- Object names sit in one table of the localization file, which needs far more of the add-on to run.
local objectNames = {}
do
	local text = ReadFile(root .. "/LocalizationDB.lua")
	local body = text:match("ObjectNames%s*=%s*(%b{})")
	if body then
		-- A few names are looked up from the client when the add-on loads. Those come out empty here and are left out.
		local unknown
		unknown = setmetatable({}, { __index = function() return unknown end, __call = function() return nil end })
		local chunk = assert(loadstring("return " .. body))
		setfenv(chunk, setmetatable({}, { __index = function() return unknown end }))
		objectNames = chunk()
	end
end

for _, file in ipairs({ "Craftables", "WorldDrops", "Zones", "Instances" }) do
	Run(root .. "/Categories/" .. file .. ".lua")
end
local categories = {}
for _, handler in ipairs(handlers) do handler(categories) end

local sources = {}

local function Children(node)
	local fields = node.fields
	if type(fields.g) == "table" then return fields.g end
	return fields
end

local function Merge(itemID, entry)
	sources[itemID] = sources[itemID] or {}
	table.insert(sources[itemID], entry)
end

local function Maps(fields)
	local maps, seen = {}, {}
	local function Add(id)
		if type(id) == "number" and not seen[id] then
			seen[id] = true
			table.insert(maps, id)
		end
	end
	for _, id in ipairs(fields.maps_disp or {}) do Add(id) end
	for _, id in ipairs(fields.maps or {}) do Add(id) end
	if type(fields.coords) == "table" then
		for id in pairs(fields.coords) do Add(id) end
	end
	table.sort(maps)
	return maps
end

local function Visit(node, trail)
	if type(node) ~= "table" or not node.kind then return end
	local next = { kind = trail.kind, quest = trail.quest, map = trail.map, npc = trail.npc, inst = trail.inst, cat = trail.cat }
	if node.kind == "prof" then next.kind = PROFESSION_KIND[node.id] or next.kind end
	if node.kind == "spell" and node.id == 8613 then next.kind = "skin" end
	if node.kind == "quest" or node.kind == "ach" then next.quest = true end
	if node.kind == "map" then next.map = node.id end
	if node.kind == "inst" then next.inst = node.id end
	if node.kind == "npc" and node.id > 0 then next.npc = node.id end

	if node.kind == "item" and not trail.quest then
		local fields = node.fields
		local entry = { kind = trail.kind, cat = trail.cat, desc = fields.description, maps = Maps(fields) }
		if trail.map and #entry.maps == 0 then entry.maps = { trail.map } end
		local objects, seen = {}, {}
		for _, provider in ipairs(fields.providers or {}) do
			local name = provider[1] == "o" and objectNames[provider[2]]
			if name and not seen[name] then
				seen[name] = true
				table.insert(objects, name)
			end
		end
		table.sort(objects)
		if #objects > 0 then entry.objects = objects end
		local npcs = {}
		for _, id in ipairs(fields.crs or {}) do table.insert(npcs, id) end
		if trail.npc then table.insert(npcs, trail.npc) end
		if #npcs > 0 then entry.npcs = npcs end
		entry.inst = trail.inst
		entry.filter = fields.f
		if entry.kind or entry.desc or #entry.maps > 0 or entry.objects or entry.npcs or entry.inst then
			Merge(node.id, entry)
		end
	end
	for _, child in pairs(Children(node)) do
		if type(child) == "table" and child.kind then Visit(child, next) end
	end
end

for name, category in pairs(categories) do
	if type(category) == "table" and category.kind then Visit(category, { cat = name }) end
end

---------------------------------------------------------------------------
-- One record per item, from its best kind of information
---------------------------------------------------------------------------

local function Tier(entry)
	if entry.kind then return 1 end
	if entry.cat == "Craftables" and entry.desc then return 2 end
	if entry.cat == "WorldDrops" then return 3 end
	if entry.cat == "Zones" then return 4 end
	return 5
end

local function AddUnique(list, seen, value)
	if not seen[value] then
		seen[value] = true
		table.insert(list, value)
	end
end

local records = {}
for itemID, entries in pairs(sources) do
	local best
	for _, entry in ipairs(entries) do
		-- A filter marks gear, recipes and the like, which are never crafting materials.
		if not entry.filter and (not best or Tier(entry) < best) then best = Tier(entry) end
	end
	if best then
		local record = { maps = {}, objects = {}, npcs = {} }
		local seenMaps, seenObjects, seenNpcs = {}, {}, {}
		for _, entry in ipairs(entries) do
			if not entry.filter and Tier(entry) == best then
				record.kind = record.kind or entry.kind
				record.desc = record.desc or entry.desc
				record.inst = record.inst or entry.inst
				for _, id in ipairs(entry.maps) do AddUnique(record.maps, seenMaps, id) end
				for _, name in ipairs(entry.objects or {}) do AddUnique(record.objects, seenObjects, name) end
				for _, id in ipairs(entry.npcs or {}) do AddUnique(record.npcs, seenNpcs, id) end
			end
		end
		table.sort(record.maps)
		table.sort(record.objects)
		table.sort(record.npcs)
		records[itemID] = record
	end
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local function Quote(text)
	return string.format("%q", text):gsub("\\\n", "\\n")
end

local function NumberList(list, limit)
	local parts = {}
	for index, value in ipairs(list) do
		if limit and index > limit then break end
		parts[index] = tostring(value)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local ids = {}
for itemID in pairs(records) do table.insert(ids, itemID) end
table.sort(ids)

print([[-- CraftLedger :: Sources
-- GENERATED by tools/gen_sources.lua. Don't edit by hand.
-- Where items come from: k = mine | herb | skin | fish, d = description, m = map IDs, o = object names, n = NPC IDs.
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
ns.SourceData = {]])
for _, itemID in ipairs(ids) do
	local record = records[itemID]
	local parts = {}
	if record.kind then table.insert(parts, "k=" .. Quote(record.kind)) end
	if record.desc then table.insert(parts, "d=" .. Quote(record.desc)) end
	if #record.maps > 0 then table.insert(parts, "m=" .. NumberList(record.maps)) end
	if #record.objects > 0 then
		local names = {}
		for index, name in ipairs(record.objects) do names[index] = Quote(name) end
		table.insert(parts, "o={" .. table.concat(names, ",") .. "}")
	end
	if #record.npcs > 0 then table.insert(parts, "n=" .. NumberList(record.npcs, 8)) end
	print(("[%d]={%s},"):format(itemID, table.concat(parts, ",")))
end
print("}")
