-- Crafting and Farming Forever :: Lock
-- While the add-on reads listings at the auction house (Depth.lua's own check), the screen is locked: a see-through
-- sheet over everything takes every click and key, so no search or purchase of yours gets in the check's way. The
-- window stays on the tab you had open; a box at its bottom names the item being read, and the rows that need it are
-- outlined, so you can see what it's doing. A list scrolls to the row being read when it's out of view. Each item read
-- is then counted on its row: a gold sweep runs across it through the listings, cheapest first, up to the number you
-- buy, with ticks where the price steps up and the running average beside it. The searches don't wait for the show:
-- items read faster than they're shown are counted faster.
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
local SHOW = {
	SECONDS = 1.1, -- a sweep across a row, with nothing else waiting to be shown
	MIN = 0.3, -- the quickest sweep, with a backlog
	HOLD = 0.45, -- the result stays this long before the next item
	BACKLOG = 6, -- items waiting to be shown at most; older ones are skipped
	SCROLL_STEP = 0.03, -- seconds between scroll steps, as a list glides to the row
	BAND = 46, -- width of the searching shimmer
	SHORT = { 1, 0.3, 0.25 }, -- the part of the amount the listings don't cover
}

local frame
local since, progressAt, lastLeft -- GetTime() it went up and of the last answer; searches left then
local idleSince -- GetTime() the check had nothing left to read, while the lock lingers
local idleAt -- GetTime() a round of searches last ended, lock up or not
local released -- you (or a time-out) took the screen back: it stays yours until this check is over
local marks, marked = {}, {} -- outline frames; the row frames they're on
local users = {} -- [itemID] = { [recipeID] = true }: recipes that make or need it, directly or one step up
local stats = { shown = 0, escaped = 0, slow = 0 }
local shows = {} -- items just read, counted on their rows in turn: { itemID, t = seconds shown }
local clock, scrollWait = 0, 0 -- seconds the lock has been animating; till the next scroll step
local follow = {} -- [window] = { itemID, offset }: the scroll position a list glides to

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
	-- The counting sweep: the gold part counted so far, its bright leading edge, a tick where the price steps up,
	-- red for the part nobody lists.
	mark.sweep = mark:CreateTexture(nil, "ARTWORK", nil, 1)
	mark.sweep:SetPoint("TOPLEFT")
	mark.sweep:SetPoint("BOTTOMLEFT")
	mark.sweep:SetColorTexture(MARK[1], MARK[2], MARK[3], 0.45)
	mark.short = mark:CreateTexture(nil, "ARTWORK", nil, 1)
	mark.short:SetPoint("TOPRIGHT")
	mark.short:SetPoint("BOTTOMRIGHT")
	mark.short:SetColorTexture(SHOW.SHORT[1], SHOW.SHORT[2], SHOW.SHORT[3], 0.28)
	mark.lead = mark:CreateTexture(nil, "OVERLAY", nil, 2)
	mark.lead:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	mark.lead:SetBlendMode("ADD")
	mark.lead:SetSize(18, 40)
	mark.band = mark:CreateTexture(nil, "ARTWORK", nil, 2)
	mark.band:SetColorTexture(1, 0.9, 0.4, 0.22)
	mark.band:SetBlendMode("ADD")
	mark.band:SetPoint("TOP")
	mark.band:SetPoint("BOTTOM")
	mark.band:SetWidth(SHOW.BAND)
	mark.ticks = {}
	if index == 1 then
		-- What's being counted, above the first row: "Counting 87 / 192, avg 1g 23s".
		local badge = CreateFrame("Frame", nil, mark)
		badge:SetPoint("BOTTOMRIGHT", mark, "TOPRIGHT", 0, 1)
		badge:SetHeight(18)
		local back = badge:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints(badge)
		back:SetColorTexture(0.06, 0.05, 0.01, 0.92)
		local line = badge:CreateTexture(nil, "BORDER")
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		line:SetHeight(1)
		line:SetColorTexture(MARK[1], MARK[2], MARK[3], 0.95)
		badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		badge.text:SetPoint("CENTER", 0, 1)
		mark.badge = badge
	end
	marks[index] = mark
	return mark
end

local function Tick(mark, index)
	local tick = mark.ticks[index]
	if tick then return tick end
	tick = mark:CreateTexture(nil, "OVERLAY", nil, 1)
	tick:SetColorTexture(1, 0.95, 0.6, 0.9)
	tick:SetSize(1, 6)
	mark.ticks[index] = tick
	return tick
end

-- Units counted down an item's listings, cheapest first: what they cost and how many there were.
function Lock.Tally(record, units)
	local cost, got = 0, 0
	for _, tier in ipairs(record or {}) do
		local take = math.min(tier[2], units - got)
		if take <= 0 then break end
		cost, got = cost + take * tier[1], got + take
	end
	return cost, got
end

local function Unmark()
	for _, mark in ipairs(marks) do mark:Hide() end
	wipe(marked)
end

local function Hide()
	idleSince = nil
	wipe(shows)
	wipe(follow)
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

-- What the queue's crafts use of an item, every alternative of a slot counted (Planner.ReservedMaterials' rule).
function Lock.Used(plan, recipes, itemID)
	local used = 0
	for _, craft in ipairs(plan and plan.crafts or {}) do
		local recipe = recipes[craft.recipeID]
		for _, slot in ipairs(recipe and recipe.r or {}) do
			for i = 2, #slot do
				if slot[i] == itemID then used = used + (slot[1] or 1) * craft.count end
			end
		end
	end
	return used
end

-- The amount the count runs to: what you buy of the item, as its row says, else what the plan buys. An item read
-- only to weigh buying against crafting (no row to buy it) runs to what the queue's crafts use of it; never to
-- everything listed.
local function Needed(itemID)
	for _, window in pairs(ns.UI.windows) do
		for _, data in ipairs(window.list or {}) do
			if Direct(data, itemID) and data.count and data.count > 0 then return data.count end
		end
	end
	local buy = ns.plan and ns.plan.buy and ns.plan.buy[itemID]
	if buy and buy > 0 then return buy end
	return math.max(Lock.Used(ns.plan, ns.db.recipes, itemID), 1)
end

-- The first entry of a list about the item: its row to buy it, else a craft that needs it.
local function IndexIn(window, itemID)
	local set, related = Users(itemID), nil
	for index, data in ipairs(window.list) do
		if Direct(data, itemID) then return index end
		if not related and Related(data, set) then related = index end
	end
	return related
end

-- Glides each open list to the item's row when it's out of view, so it lands a third of the way down.
local function Follow(itemID, elapsed)
	scrollWait = scrollWait - elapsed
	if not itemID or scrollWait > 0 then return end
	scrollWait = SHOW.SCROLL_STEP
	for _, window in pairs(ns.UI.windows) do
		if window.list and window.container and not window.mini and window.frame and window.frame:IsVisible() then
			local offset, visible, maxOffset = ns.UI.ListView(window)
			local goal = follow[window]
			if not goal or goal.itemID ~= itemID then
				local index = IndexIn(window, itemID)
				goal = nil
				if index and visible > 0 and (index <= offset or index > offset + visible) then
					goal = { itemID = itemID, offset = math.min(math.max(index - 1 - math.floor(visible / 3), 0), maxOffset) }
				end
				follow[window] = goal
			end
			if goal then
				local gap = goal.offset - offset
				if gap == 0 then
					follow[window] = { itemID = itemID, offset = offset, reached = true }
				elseif not goal.reached then
					local step = math.max(1, math.floor(math.abs(gap) / 4))
					ns.UI.SetListOffset(window, offset + (gap > 0 and step or -step))
				end
			end
		end
	end
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

-- What the sweep shows: show = the item being counted (nil: the search is still out, a shimmer runs instead).
local function View(itemID, show)
	if not show then return nil end
	local record = ns.Depth.Of(itemID)
	if not record then return nil end
	local needed = Needed(itemID)
	local duration = math.max(SHOW.MIN, SHOW.SECONDS / #shows)
	local t = math.min(show.t / duration, 1)
	local eased = 1 - (1 - t) * (1 - t) -- quick start, settles at the end
	local _, available = Lock.Tally(record, needed)
	local units = math.floor(eased * available + 0.5)
	local cost = Lock.Tally(record, units)
	return { record = record, needed = needed, available = available, units = units, cost = cost,
		done = t >= 1, after = math.max(show.t - duration, 0) }
end

local function ViewText(view)
	if not view then
		return ("Searching the auction house" .. ("."):rep(math.floor(clock * 3) % 4))
	end
	local average = view.units > 0 and ("avg " .. ns.Money(view.cost / view.units)) or ""
	if view.done and view.available < view.needed then
		return ("|cffff6b5bonly %d of %d listed|r, %s"):format(view.available, view.needed, average)
	end
	return ("%s %d / %d, %s"):format(view.done and "Counted" or "Counting", view.units, view.needed, average)
end

local function Paint(mark, view)
	local width = mark:GetWidth() or 0
	mark.band:SetShown(view == nil and width > SHOW.BAND)
	if not view then
		mark.sweep:Hide()
		mark.short:Hide()
		mark.lead:Hide()
		for _, tick in ipairs(mark.ticks) do tick:Hide() end
		mark.band:ClearAllPoints()
		mark.band:SetPoint("TOP")
		mark.band:SetPoint("BOTTOM")
		mark.band:SetPoint("LEFT", mark, "LEFT", (math.sin(clock * 3) + 1) / 2 * (width - SHOW.BAND), 0)
		return
	end
	local reach = view.available / view.needed
	local at = width * math.min(view.units / view.needed, 1)
	mark.sweep:SetShown(at >= 1)
	mark.sweep:SetWidth(math.max(at, 1))
	-- A flash as the count ends, fading over the hold.
	mark.sweep:SetAlpha(view.done and 0.6 + 0.4 * math.max(0, 1 - view.after / SHOW.HOLD) or 0.6)
	mark.lead:SetShown(not view.done and at >= 1)
	mark.lead:ClearAllPoints()
	mark.lead:SetPoint("CENTER", mark, "LEFT", at, 0)
	mark.short:SetShown(view.done and reach < 1)
	mark.short:SetWidth(math.max(width * (1 - reach), 1))
	-- A tick wherever the price steps up, as the sweep passes it.
	local index, counted = 0, 0
	for _, tier in ipairs(view.record) do
		counted = counted + tier[2]
		if counted >= view.needed then break end
		local x = width * counted / view.needed
		if x > at then break end
		index = index + 1
		local tick = Tick(mark, index)
		tick:ClearAllPoints()
		tick:SetPoint("BOTTOM", mark, "BOTTOMLEFT", x, 0)
		tick:Show()
	end
	for i = index + 1, #mark.ticks do mark.ticks[i]:Hide() end
end

local function PaintAll(view)
	local text = ViewText(view)
	for index, mark in ipairs(marks) do
		if mark:IsShown() then
			Paint(mark, view)
			if index == 1 and mark.badge then
				mark.badge.text:SetText(text)
				mark.badge:SetWidth((mark.badge.text:GetStringWidth() or 0) + 14)
			end
		end
	end
	-- Also on the box, for the rows not on screen.
	frame.note:SetText(text .. "|cff808080   Escape unlocks the screen.|r")
end

-- The item being shown: moves on once its count has been on screen long enough.
local function Advance(elapsed)
	local show = shows[1]
	while show do
		local duration = math.max(SHOW.MIN, SHOW.SECONDS / #shows)
		show.t = show.t + elapsed
		elapsed = 0
		if show.t < duration + SHOW.HOLD and ns.Depth.Of(show.itemID) then return show end
		table.remove(shows, 1)
		show = shows[1]
	end
	return nil
end

-- Our search for the item was answered (Depth.lua): its count goes on screen in turn.
function Lock.Read(itemID)
	if not Lock.Shown() then return end
	shows[#shows + 1] = { itemID = itemID, t = 0 }
	while #shows > SHOW.BACKLOG do table.remove(shows, 1) end
end

local function Describe(left, total, itemID, waiting)
	local key = (left or "-") .. ":" .. (itemID or "-") .. ":" .. tostring(waiting)
	if frame.described == key then return end
	frame.described = key
	if not left then
		frame.item:SetText("Done reading. Working out the plan with the new prices...")
		frame.bar.target = 1
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
	frame.bar.target = math.max(total - left, 0) / math.max(total, 1)
end

-- Whether the lock still has a reason to be up, checked every frame it is.
function Lock.Update(_, elapsed)
	if not (frame and frame:IsShown()) then return end
	if not AuctionHouseOpen() or InCombatLockdown() or not ns.Option("depthCheck") then return Hide() end
	elapsed = elapsed or 0
	clock = clock + elapsed
	local now = GetTime()
	local left, total = ns.Depth.Status()
	local show = Advance(elapsed)
	-- The progress bar glides to where the check is.
	local bar = frame.bar
	bar.value = (bar.value or 0) + ((bar.target or 0) - (bar.value or 0)) * math.min(1, elapsed * 8)
	bar:SetValue(bar.value)
	if not left then
		-- Between rounds: the plan is being worked out again, and may want more read.
		Describe(nil)
		progressAt = now
		if not show then
			idleSince = idleSince or now
			if now - idleSince > Lock.LINGER then return Hide() end
			MarkRows(nil)
			frame.note:SetText(frame.note.idle)
			return
		end
	else
		-- Holding off for someone else's search: that isn't the check being stuck.
		local waiting = ns.Depth.Holding(now) > 0
		if left ~= lastLeft or waiting then lastLeft, progressAt = left, now end
		if now - progressAt > Lock.STALL or now - since > Lock.MAX then return Release(true) end
		Describe(left, total, ns.Depth.Current(), waiting)
	end
	idleSince = nil
	local itemID = show and show.itemID or ns.Depth.Current()
	Follow(itemID, elapsed)
	MarkRows(itemID)
	PaintAll(View(itemID, show))
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
	frame.note.idle = "Outlined: the rows that need it. Escape unlocks the screen."
	frame.note:SetText(frame.note.idle)

	local bar = CreateFrame("StatusBar", nil, box)
	frame.bar = bar
	bar:SetPoint("BOTTOMLEFT", 1, 1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetHeight(4)
	bar:SetMinMaxValues(0, 1)
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
	frame.bar.value, frame.bar.target = 0, 0
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
