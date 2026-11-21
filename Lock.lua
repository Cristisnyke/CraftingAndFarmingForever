-- Crafting and Farming Forever :: Lock
-- While the add-on reads listings at the auction house (Depth.lua's own check), the screen is locked: a see-through
-- sheet over everything takes every click and key, so no search or purchase of yours gets in the check's way. The
-- window stays on the tab you had open; a box at its bottom names the item being read, and the rows that need it are
-- outlined, so you can see what it's doing.
--
-- One lock covers the whole check. Reading a listing changes the plan, and the new plan can want more listings read:
-- the lock stays up through that (Lock.LINGER after each round) instead of dropping and coming back. It still can't
-- get stuck: it asks every frame whether it has a reason to be there, and goes when the check is over, the auction
-- house closes, a fight starts, nothing has been read for a while, it has simply been up too long, or you press Escape.

local _, ns = ...

local Lock = {}
ns.Lock = Lock

Lock.STALL = 15 -- seconds without a search being answered before the screen is given back
Lock.MAX = 120 -- seconds the screen stays locked at most, whatever happens
Lock.LINGER = 3 -- seconds it stays after a round of searches ends, for the plan to be worked out with what was read

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WIDTH, HEIGHT = 420, 64
local MARK = { 1, 0.82, 0 } -- the outline of rows that need the item being read

local frame
local since, progressAt, lastLeft -- GetTime() it went up and of the last answer; searches left then
local idleSince -- GetTime() the check had nothing left to read, while the lock lingers
local idleAt -- GetTime() a round of searches last ended, lock up or not
local released -- you (or a time-out) took the screen back: it stays yours until this check is over
local marks, marked = {}, {} -- outline frames; the row frames they're on
local users = {} -- [itemID] = { [recipeID] = true }: recipes that make or need it, directly or one step up
local stats = { shown = 0, escaped = 0, slow = 0 }

local function Mark(index)
	local mark = marks[index]
	if mark then return mark end
	mark = CreateFrame("Frame", nil, frame)
	local fill = mark:CreateTexture(nil, "ARTWORK")
	fill:SetAllPoints(mark)
	fill:SetColorTexture(MARK[1], MARK[2], MARK[3], 0.16)
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2 },
		{ "TOPLEFT", "BOTTOMLEFT", 2, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 2, 0 } }) do
		local edge = mark:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(MARK[1], MARK[2], MARK[3], 0.95)
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if side[3] > 0 then edge:SetWidth(side[3]) else edge:SetHeight(side[4]) end
	end
	marks[index] = mark
	return mark
end

local function Unmark()
	for _, mark in ipairs(marks) do mark:Hide() end
	wipe(marked)
end

local function Hide()
	idleSince = nil
	if frame and frame:IsShown() then
		Unmark()
		frame:Hide()
	end
end

-- Gives the screen back for the rest of this check, which goes on behind it.
local function Release(slow)
	released, idleAt = true, nil
	if slow then
		stats.slow = stats.slow + 1
		ns.Say("chatPlan", "Reading listings is taking long. The screen is yours again; it goes on in the background.")
	else
		stats.escaped = stats.escaped + 1
	end
	Hide()
end

local function AuctionHouseOpen()
	return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

-- Recipes an item is read for: those that make it or need it, and those that need what those make (ore: the bars
-- smelted from it and what the bars go into).
local function Users(itemID)
	if users[itemID] then return users[itemID] end
	local set, made = {}, {}
	local function Needs(recipe, wanted)
		for _, slot in ipairs(recipe.r or {}) do
			for i = 2, #slot do
				if wanted[slot[i]] then return true end
			end
		end
		return false
	end
	for recipeID, recipe in pairs(ns.db.recipes) do
		if recipe.o == itemID then set[recipeID] = true end
		if Needs(recipe, { [itemID] = true }) then
			set[recipeID] = true
			if recipe.o then made[recipe.o] = true end
		end
	end
	if next(made) then
		for recipeID, recipe in pairs(ns.db.recipes) do
			if Needs(recipe, made) then set[recipeID] = true end
		end
	end
	users[itemID] = set
	return set
end

-- Whether a row is about the item: the item itself (a row to buy it), else a recipe that makes or needs it.
local function Direct(data, itemID)
	return data.kind == "item" and data.itemID == itemID
end

local function Related(data, set)
	local recipeID = (data.kind == "restock" and data.row and data.row.recipeID)
		or (data.kind == "queue" and data.entry and data.entry.recipeID)
		or (data.kind == "auto" and data.craft and data.craft.recipeID)
	return recipeID ~= nil and set[recipeID] == true
end

-- Outlines the rows of every open list that are about the item: in each list the row to buy it, or when it has none
-- (the Restock tab) the crafts that need it.
local function MarkRows(itemID)
	local found = {}
	if itemID then
		local set = Users(itemID)
		for _, window in pairs(ns.UI.windows) do
			if window.rows and window.frame and window.frame:IsVisible() then
				local direct, related = {}, {}
				for _, row in ipairs(window.rows) do
					local data = row.data
					if data and row:IsShown() then
						if Direct(data, itemID) then
							direct[#direct + 1] = row
						elseif Related(data, set) then
							related[#related + 1] = row
						end
					end
				end
				for _, row in ipairs(#direct > 0 and direct or related) do found[#found + 1] = row end
			end
		end
	end
	local same = #found == #marked
	for index, row in ipairs(found) do
		if marked[index] ~= row then same = false end
	end
	if same then return end
	Unmark()
	for index, row in ipairs(found) do
		local mark = Mark(index)
		mark:ClearAllPoints()
		mark:SetAllPoints(row)
		mark:Show()
		marked[index] = row
	end
end

local function Describe(left, total, itemID, waiting)
	local key = (left or "-") .. ":" .. (itemID or "-") .. ":" .. tostring(waiting)
	if frame.described == key then return end
	frame.described = key
	if not left then
		frame.item:SetText("Done reading. Working out the plan with the new prices...")
		frame.bar:SetMinMaxValues(0, 1)
		frame.bar:SetValue(1)
		return
	end
	local name = itemID and ns.Items.Name(itemID)
	local icon = itemID and ("|T%s:16:16:0:0|t "):format(ns.Items.Icon(itemID)) or ""
	if waiting then
		frame.item:SetText(("Waiting for another search to finish. %d to go."):format(left))
	elseif name then
		frame.item:SetText(("Reading %s%s: %d of %d"):format(icon, name, total - left + 1, total))
	else
		frame.item:SetText(("Reading listings: %d of %d"):format(total - left + 1, total))
	end
	frame.bar:SetMinMaxValues(0, math.max(total, 1))
	frame.bar:SetValue(math.max(total - left, 0))
end

-- Whether the lock still has a reason to be up, checked every frame it is.
function Lock.Update()
	if not (frame and frame:IsShown()) then return end
	if not AuctionHouseOpen() or InCombatLockdown() or not ns.Option("depthCheck") then return Hide() end
	local now = GetTime()
	local left, total = ns.Depth.Status()
	if not left then
		-- Between rounds: the plan is being worked out again, and may want more read.
		idleSince = idleSince or now
		if now - idleSince > Lock.LINGER then return Hide() end
		progressAt = now
		Describe(nil)
		MarkRows(nil)
		return
	end
	idleSince = nil
	-- Holding off for someone else's search: that isn't the check being stuck.
	local waiting = ns.Depth.Holding(now) > 0
	if left ~= lastLeft or waiting then lastLeft, progressAt = left, now end
	if now - progressAt > Lock.STALL or now - since > Lock.MAX then return Release(true) end
	local itemID = ns.Depth.Current()
	Describe(left, total, itemID, waiting)
	MarkRows(itemID)
end

local function Create()
	frame = CreateFrame("Frame", "CFFListingsLock", UIParent)
	Lock.frame = frame
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("TOOLTIP") -- over every window, popup and menu
	frame:Hide()
	local theme = ns.UI.THEME

	-- Everything under it is out of reach: clicks, the wheel and every key stop here.
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function() end)
	frame:EnableKeyboard(true)
	frame:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then Release(false) end
	end)
	frame:SetScript("OnUpdate", Lock.Update)

	-- Dimmed, not blacked out: the window's rows stay readable, with the ones being read outlined.
	local shade = frame:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints(frame)
	shade:SetColorTexture(0, 0, 0, 0.35)

	local box = CreateFrame("Frame", nil, frame)
	frame.box = box
	box:SetSize(WIDTH, HEIGHT)
	box:SetFrameLevel((frame:GetFrameLevel() or 0) + 10) -- over the outlines
	local edge = box:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints(box)
	edge:SetColorTexture(theme.primaryEdge[1], theme.primaryEdge[2], theme.primaryEdge[3], 1)
	local fill = box:CreateTexture(nil, "BORDER")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(theme.bg[1], theme.bg[2], theme.bg[3], 1)

	frame.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", 0, -7)
	frame.title:SetText("Screen locked: checking what your queue's materials cost")
	frame.item = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.item:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)
	frame.note = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.note:SetPoint("TOP", frame.item, "BOTTOM", 0, -3)
	frame.note:SetText("Outlined: the rows that need it. Escape unlocks the screen.")

	local bar = CreateFrame("StatusBar", nil, box)
	frame.bar = bar
	bar:SetPoint("BOTTOMLEFT", 1, 1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetHeight(4)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(bar)
	track:SetColorTexture(theme.field[1], theme.field[2], theme.field[3], 1)
end

-- The box sits on the window's footer (its buttons can't be used meanwhile anyway), so the rows stay in view.
-- No window (it can't be shown): the middle of the screen.
local function PlaceBox()
	local box, window = frame.box, ns.UI.main and ns.UI.main.frame
	box:ClearAllPoints()
	if window and window:IsShown() then
		box:SetPoint("BOTTOM", window, "BOTTOM", 0, 6)
	else
		box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

function Lock.Shown()
	return frame ~= nil and frame:IsShown()
end

-- The row frames outlined now.
function Lock.Marked()
	return marked
end

-- Called as the check sends a search of its own. Not for listings read from your searches: there's nothing to wait for.
function Lock.Start()
	if Lock.Shown() then
		idleSince = nil -- another round under the same lock
		return
	end
	if released then
		-- Still the check you took the screen back from, unless it ended a while ago.
		if not (idleAt and GetTime() - idleAt > Lock.LINGER) then return end
		released = nil
	end
	if InCombatLockdown() or not AuctionHouseOpen() or not ns.Depth.Status() then return end
	if not frame then Create() end
	-- Stays on the tab you're on; a closed window opens on the queue, whose materials these are.
	if not ns.UI.IsOpen() then ns.UI.Show("queue") end
	PlaceBox()
	-- A box being typed in gets the keys before the lock does.
	local typing = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if typing then typing:ClearFocus() end
	since = GetTime()
	progressAt, lastLeft, idleSince, frame.described = since, nil, nil, nil
	wipe(users) -- recipes may have been learned since
	stats.shown = stats.shown + 1
	frame:Show()
	Lock.Update()
end

-- A round of searches ended (Depth.lua). The lock lingers a moment in case the new plan wants more read.
function Lock.Stopped()
	idleAt = GetTime()
	Lock.Update()
end

function Lock.Diag()
	return ("%d times, %d ended with Escape, %d for taking too long%s"):format(stats.shown, stats.escaped, stats.slow,
		Lock.Shown() and ", up now" or "")
end

ns.On("PLAYER_REGEN_DISABLED", Hide)
ns.On("AUCTION_HOUSE_CLOSED", function()
	released, idleAt = nil, nil
	Hide()
end)
