-- Crafting and Farming Forever :: Bank
-- The bank step done for you, with the bank open: puts away what the plan says to make room with, then takes out
-- what it needs. One stack at a time, through the cursor (pick up or split, then drop), which add-ons may do outside
-- combat; each move waits for the server before the next.

local _, ns = ...
local Bank = {}
ns.Bank = Bank

local BAGS = { 0, 1, 2, 3, 4 }
local REAGENT_BAG = 5
local TIMING = {
	STEP = 0.05, -- between checks while a move is on its way
	WAIT = 2,    -- seconds the server gets to answer one move
}

local open = false
-- job = { moves = { { itemID, left, deposit = true|nil, missing = n } }, index, pending, refused = { [bag] = true },
--         used = { ["bag:slot"] = true }, moved, total, full = "bank"|"bags"|nil }
local job

function Bank.IsOpen()
	return open
end

-- Units moved and to move while a job runs, else nil.
function Bank.Progress()
	if job then return job.moved, job.total end
end

-- The character's bank: Forever's bank tabs, or the old bank and its bags.
local function BankContainers()
	local list = {}
	local index = Enum and Enum.BagIndex
	if index and index.CharacterBankTab_1 then
		for tab = 1, 9 do
			local bag = index["CharacterBankTab_" .. tab]
			if bag then table.insert(list, bag) end
		end
	else
		table.insert(list, index and index.Bank or -1)
		local first = index and index.BankBag_1
		for bag = 0, 6 do
			if first then table.insert(list, first + bag) end
		end
	end
	return list
end

-- Bags an item may go in: the reagent bag first for crafting reagents, so normal slots stay free.
local function BagContainers(itemID)
	local list = {}
	if ns.Items.IsReagent(itemID) then table.insert(list, REAGENT_BAG) end
	for _, bag in ipairs(BAGS) do table.insert(list, bag) end
	return list
end

local function Slots(bag)
	local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
	return ok and count or 0
end

-- The stack to move next: the biggest that fits in what's left to move, else the smallest (split).
local function Source(containers, itemID, left)
	local whole, split
	for _, bag in ipairs(containers) do
		for slot = 1, Slots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID and not info.isLocked then
				local count = info.stackCount or 1
				local found = { bag = bag, slot = slot, count = count }
				if count <= left then
					if not whole or count > whole.count then whole = found end
				elseif not split or count < split.count then
					split = found
				end
			end
		end
	end
	return whole or split
end

-- Where amount units go: onto a stack of the same item with room for them, else an empty slot.
local function Destination(containers, itemID, amount)
	local stack = ns.Items.StackSize(itemID) or 1
	local empty
	for _, bag in ipairs(containers) do
		if not job.refused[bag] then
			for slot = 1, Slots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID == itemID and not info.isLocked and (info.stackCount or 1) + amount <= stack then
					return { bag = bag, slot = slot }
				elseif not info and not empty and not job.used[bag .. ":" .. slot] then
					empty = { bag = bag, slot = slot }
				end
			end
		end
	end
	return empty
end

local function Changed()
	if ns.UI and ns.UI.SyncBankButton then ns.UI.SyncBankButton() end
end

local function Finish(stopped)
	local done = job
	job = nil
	if not done then return end
	local missing = {}
	for _, move in ipairs(done.moves) do
		if (move.missing or 0) > 0 then
			table.insert(missing, ("%s x%d"):format(ns.Items.Name(move.itemID) or "?", move.missing))
		end
	end
	if stopped then
		ns.Say("chatDone", ("Bank: stopped (%s) after moving %d of %d."):format(stopped, done.moved, done.total))
	elseif done.full then
		ns.Say("chatDone", ("Bank: your %s %s full. Moved %d of %d."):format(done.full, done.full == "bank" and "is" or "are",
			done.moved, done.total))
	else
		ns.Say("chatDone", ("Bank: done, moved %d."):format(done.moved))
	end
	if #missing > 0 then ns.Say("chatDone", "Bank: not found: " .. table.concat(missing, ", ") .. ".") end
	ns.RequestPlan()
	Changed()
end

local Step

local function Later()
	local this = job
	C_Timer.After(TIMING.STEP, function()
		if job == this then Step() end
	end)
end

-- Waits for the last move: done when its source stack has changed and isn't locked any more. A drop that didn't
-- land (a bank tab that won't take it) is put back after a while and that container isn't used again.
local function Settled()
	local pending = job.pending
	local info = C_Container.GetContainerItemInfo(pending.bag, pending.slot)
	local count = info and info.itemID == pending.itemID and (info.stackCount or 1) or 0
	if count ~= pending.before and not (info and info.isLocked) then
		job.pending = nil
		local move = job.moves[job.index]
		move.left = move.left - pending.amount
		job.moved = job.moved + pending.amount
		Changed()
		return true
	end
	if GetTime() - pending.at > TIMING.WAIT then
		if GetCursorInfo() then ClearCursor() end
		job.refused[pending.target] = true
		job.used[pending.target .. ":" .. pending.targetSlot] = nil
		job.pending = nil
		return true
	end
	return false
end

Step = function()
	if not job then return end
	if not open then return Finish("the bank closed") end
	if InCombatLockdown() then return Finish("combat") end
	if job.pending and not Settled() then return Later() end
	local move = job.moves[job.index]
	while move and move.left <= 0 do
		job.index = job.index + 1
		move = job.moves[job.index]
	end
	if not move then return Finish() end
	local from = move.deposit and { REAGENT_BAG, 0, 1, 2, 3, 4 } or BankContainers()
	local source = Source(from, move.itemID, move.left)
	if not source then
		move.missing, move.left = move.left, 0
		return Later()
	end
	local amount = math.min(source.count, move.left)
	local target = Destination(move.deposit and BankContainers() or BagContainers(move.itemID), move.itemID, amount)
	if not target then
		job.full = move.deposit and "bank" or "bags"
		return Finish()
	end
	if amount < source.count then
		C_Container.SplitContainerItem(source.bag, source.slot, amount)
	else
		C_Container.PickupContainerItem(source.bag, source.slot)
	end
	C_Container.PickupContainerItem(target.bag, target.slot)
	job.used[target.bag .. ":" .. target.slot] = true
	job.pending = { bag = source.bag, slot = source.slot, itemID = move.itemID, before = source.count, amount = amount,
		at = GetTime(), target = target.bag, targetSlot = target.slot }
	Later()
end

-- What the bank step would move now: { deposit = { [itemID] = units }, take = { [itemID] = units } }, from the plan
-- the Queue tab shows. Nil when there's nothing.
function Bank.Pending()
	local plan = ns.ActivePlan()
	local deposit = plan.room and plan.room.bank or {}
	local take = plan.bank or {}
	-- Bank alt mode: crafts in the bank come out too, to be mailed to the bank alt.
	local send = ns.plan.send and ns.plan.send.bank
	if send and next(send) then
		local merged = {}
		for itemID, units in pairs(take) do merged[itemID] = units end
		for itemID, units in pairs(send) do merged[itemID] = (merged[itemID] or 0) + units end
		take = merged
	end
	if next(deposit) == nil and next(take) == nil then return nil end
	return { deposit = deposit, take = take }
end

-- Starts the bank step: put away first, which makes the room, then take out. Returns false and why when it can't.
function Bank.Run()
	if job then return false, "already moving" end
	if not open then return false, "Open your bank first." end
	if InCombatLockdown() then return false, "Not in combat." end
	if GetCursorInfo() then return false, "Put down what's on your cursor first." end
	local pending = Bank.Pending()
	if not pending then return false, "Nothing to move." end
	local moves, total = {}, 0
	local function Add(items, deposit)
		local ids = {}
		for itemID in pairs(items) do table.insert(ids, itemID) end
		table.sort(ids)
		for _, itemID in ipairs(ids) do
			if items[itemID] > 0 then
				table.insert(moves, { itemID = itemID, left = items[itemID], deposit = deposit })
				total = total + items[itemID]
			end
		end
	end
	Add(pending.deposit, true)
	Add(pending.take, nil)
	job = { moves = moves, index = 1, refused = {}, used = {}, moved = 0, total = total }
	Changed()
	Step()
	return true
end

local function SetOpen(state)
	open = state
	if not open and job then Finish("the bank closed") end
	Changed()
	-- The Next step bar jumps to the bank step while you're at the bank.
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh("next") end
end

ns.On("BANKFRAME_OPENED", function() SetOpen(true) end)
ns.On("BANKFRAME_CLOSED", function() SetOpen(false) end)
-- The newer bank opens through the interaction manager; either way counts.
local function IsBanker(kind)
	local types = Enum and Enum.PlayerInteractionType
	return types and types.Banker ~= nil and kind == types.Banker
end
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
	if IsBanker(kind) then SetOpen(true) end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
	if IsBanker(kind) then SetOpen(false) end
end)
