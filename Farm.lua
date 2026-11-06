-- CraftLedger :: Farm
-- Turns the source table into instructions for getting an item yourself. The table is generated from AllTheThings'
-- data, see Sources.lua. Zone names come from the client so they follow the game's language.

local _, ns = ...

local Farm = {}
ns.Farm = Farm

-- Smelting isn't part of the crafting professions the add-on records, so bars are worked out from this.
-- yield is bars per smelt, then { count, itemID } per material.
Farm.Smelting = {
	[2840] = { yield = 1, { 1, 2770 } }, -- Copper Bar: Copper Ore
	[3576] = { yield = 1, { 1, 2771 } }, -- Tin Bar: Tin Ore
	[2841] = { yield = 2, { 1, 2840 }, { 1, 3576 } }, -- Bronze Bar: Copper Bar, Tin Bar
	[2842] = { yield = 1, { 1, 2775 } }, -- Silver Bar: Silver Ore
	[3575] = { yield = 1, { 1, 2772 } }, -- Iron Bar: Iron Ore
	[3577] = { yield = 1, { 1, 2776 } }, -- Gold Bar: Gold Ore
	[3859] = { yield = 1, { 1, 3575 }, { 1, 3857 } }, -- Steel Bar: Iron Bar, Coal
	[3860] = { yield = 1, { 1, 3858 } }, -- Mithril Bar: Mithril Ore
	[6037] = { yield = 1, { 1, 7911 } }, -- Truesilver Bar: Truesilver Ore
	[12359] = { yield = 1, { 1, 10620 } }, -- Thorium Bar: Thorium Ore
	[11371] = { yield = 1, { 8, 11370 } }, -- Dark Iron Bar: Dark Iron Ore
}

Farm.GROUPS = {
	{ key = "mine", title = "Mine" },
	{ key = "herb", title = "Pick herbs" },
	{ key = "skin", title = "Skin" },
	{ key = "fish", title = "Fish" },
	{ key = "disenchant", title = "Disenchant" },
	{ key = "drop", title = "Kill for drops" },
	{ key = "other", title = "Other sources" },
	{ key = "unknown", title = "No source on record" },
}

local ACTION = { mine = "Mine", herb = "Pick", skin = "Skin creatures", fish = "Fish" }
local ZONES_SHOWN = 4

-- True when the player stands in this map or anywhere inside it.
local function PlayerIsIn(mapID)
	local current = C_Map.GetBestMapForUnit("player")
	for _ = 1, 6 do
		if not current then return false end
		if current == mapID then return true end
		local info = C_Map.GetMapInfo(current)
		current = info and info.parentMapID
	end
	return false
end

-- Zone names sorted by name, the player's own zone first. Second value: whether the player is in one of them.
local function ZoneNames(maps)
	local names, seen, here = {}, {}, nil
	for _, mapID in ipairs(maps or {}) do
		local info = C_Map.GetMapInfo(mapID)
		local name = info and info.name
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			if not here and PlayerIsIn(mapID) then
				here = name
			else
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	if here then table.insert(names, 1, here) end
	return names, here ~= nil
end

-- NPC names aren't in the source data. QuestieDB can name them when it's installed.
local function NpcNames(ids)
	local names, seen = {}, {}
	local db = _G.NpcDB
	if not db or not db.name then return names end
	for _, id in ipairs(ids or {}) do
		local ok, name = pcall(db.name, id)
		if ok and name and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	return names
end

local function GroupOf(source)
	if not source then return "unknown" end
	if source.k then return source.k end
	local text = source.d and source.d:lower() or ""
	if text:find("disenchant", 1, true) then return "disenchant" end
	if source.n or text:find("drop", 1, true) then return "drop" end
	if source.m and not source.d then return "drop" end
	return "other"
end

-- Where to get an item: group key, one line for the list, and every detail for the tooltip.
function Farm.Describe(itemID)
	local source = ns.SourceData and ns.SourceData[itemID]
	local group = GroupOf(source)
	if not source then
		return group, "Not in the source data. Look it up, or buy it.", {}
	end

	local zones, inZone = ZoneNames(source.m)
	local npcs = NpcNames(source.n)
	local details = {}
	if source.d then table.insert(details, source.d) end

	local what
	if source.o then
		what = (ACTION[group] or "Find") .. " " .. table.concat(source.o, " or ")
		table.insert(details, what)
	elseif ACTION[group] then
		what = ACTION[group]
	elseif #npcs > 0 then
		what = "Kill " .. table.concat(npcs, ", ", 1, math.min(#npcs, 3))
		table.insert(details, "Kill " .. table.concat(npcs, ", "))
	else
		what = source.d or (group == "drop" and "Creature drop" or "")
	end

	local line = what
	if #zones > 0 then
		local shown = {}
		for index = 1, math.min(#zones, ZONES_SHOWN) do shown[index] = zones[index] end
		local where = table.concat(shown, ", ")
		if #zones > ZONES_SHOWN then where = where .. (", +%d more"):format(#zones - ZONES_SHOWN) end
		line = (what ~= "" and (what .. ": ") or "") .. where
		if inZone then line = line .. " (you are here)" end
		table.insert(details, "Zones: " .. table.concat(zones, ", "))
	end
	return group, line, details
end
