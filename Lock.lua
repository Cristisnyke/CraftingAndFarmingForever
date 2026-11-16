-- Crafting and Farming Forever :: Lock
-- While the add-on reads listings at the auction house (Depth.lua's own check), the screen is locked: a see-through
-- sheet over everything takes every click and key, so no search or purchase of yours gets in the check's way. The
-- window opens on the Queue tab and is blacked out, with the notice and the countdown in its middle; when the lock
-- lifts, the buy step is there with the real costs.
--
-- The lock can't get stuck. It asks every frame whether it still has a reason to be there, and goes when the check
-- ends or holds off, the auction house closes, a fight starts, nothing has been read for a while, it has simply been
-- up too long, or you press Escape.

local _, ns = ...

local Lock = {}
ns.Lock = Lock

Lock.STALL = 15 -- seconds without a search being answered before the screen is given back
Lock.MAX = 120 -- seconds the screen stays locked at most, whatever happens
Lock.HOLD = 1 -- the check holding off for longer than this (your search, a purchase) gives the screen back too

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WIDTH, HEIGHT = 380, 62

local frame
local since, progressAt, lastLeft -- GetTime() it went up and of the last answer; searches left then
local releasedRound -- the round of the check you (or a time-out) took the screen back in: it stays yours until the next
local stats = { shown = 0, escaped = 0, slow = 0 }

local function Hide()
	if frame and frame:IsShown() then frame:Hide() end
end

-- Gives the screen back for the rest of this check, which goes on behind it.
local function Release(slow)
	releasedRound = ns.Depth.round
	if slow then
		stats.slow = stats.slow + 1
		ns.Print("Reading listings is taking long. The screen is yours again; it goes on in the background.")
	else
		stats.escaped = stats.escaped + 1
	end
	Hide()
end

local function AuctionHouseOpen()
	return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

-- Whether the lock still has a reason to be up, checked every frame it is.
function Lock.Update()
	if not (frame and frame:IsShown()) then return end
	local left, total = ns.Depth.Status()
	local now = GetTime()
	if not left or not AuctionHouseOpen() or InCombatLockdown() or not ns.Option("depthCheck")
		or ns.Depth.Holding(now) > Lock.HOLD then
		return Hide()
	end
	if left ~= lastLeft then lastLeft, progressAt = left, now end
	if now - progressAt > Lock.STALL or now - since > Lock.MAX then return Release(true) end
	if frame.shownLeft ~= left then
		frame.shownLeft = left
		frame.note:SetText(("Reading listings, %d to go. Escape unlocks it."):format(left))
		frame.bar:SetMinMaxValues(0, math.max(total, 1))
		frame.bar:SetValue(math.max(total - left, 0))
	end
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

	local shade = frame:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints(frame)
	shade:SetColorTexture(0, 0, 0, 0.35)

	-- The window itself goes dark: what it shows is changing under the lock anyway.
	frame.cover = frame:CreateTexture(nil, "ARTWORK")
	frame.cover:SetColorTexture(0, 0, 0, 0.93)

	local box = CreateFrame("Frame", nil, frame)
	frame.box = box
	box:SetSize(WIDTH, HEIGHT)
	local edge = box:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints(box)
	edge:SetColorTexture(theme.primaryEdge[1], theme.primaryEdge[2], theme.primaryEdge[3], 1)
	local fill = box:CreateTexture(nil, "BORDER")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(theme.bg[1], theme.bg[2], theme.bg[3], 1)

	frame.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOP", 0, -9)
	frame.title:SetText("Screen locked: scanning your items")
	frame.note = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.note:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)

	local bar = CreateFrame("StatusBar", nil, box)
	frame.bar = bar
	bar:SetPoint("BOTTOMLEFT", 1, 1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetHeight(5)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(bar)
	track:SetColorTexture(theme.field[1], theme.field[2], theme.field[3], 1)
end

-- The window is blacked out, with the notice in its middle. No window (it can't be shown): the middle of the screen.
local function PlaceBox()
	local box, cover, window = frame.box, frame.cover, ns.UI.main and ns.UI.main.frame
	box:ClearAllPoints()
	cover:ClearAllPoints()
	if window and window:IsShown() then
		cover:SetAllPoints(window)
		cover:Show()
		box:SetPoint("CENTER", window, "CENTER", 0, 0)
	else
		cover:Hide()
		box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

function Lock.Shown()
	return frame ~= nil and frame:IsShown()
end

-- Called as the check sends a search of its own. Not for listings read from your searches: there's nothing to wait for.
function Lock.Start()
	if Lock.Shown() or releasedRound == ns.Depth.round then return end
	if InCombatLockdown() or not AuctionHouseOpen() or not ns.Depth.Status() then return end
	if not frame then Create() end
	ns.UI.Show("queue")
	PlaceBox()
	-- A box being typed in gets the keys before the lock does.
	local typing = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if typing then typing:ClearFocus() end
	since = GetTime()
	progressAt, lastLeft, frame.shownLeft = since, nil, nil
	stats.shown = stats.shown + 1
	frame:Show()
	Lock.Update()
end

function Lock.Diag()
	return ("%d times, %d ended with Escape, %d for taking too long%s"):format(stats.shown, stats.escaped, stats.slow,
		Lock.Shown() and ", up now" or "")
end

ns.On("PLAYER_REGEN_DISABLED", Hide)
ns.On("AUCTION_HOUSE_CLOSED", Hide)
