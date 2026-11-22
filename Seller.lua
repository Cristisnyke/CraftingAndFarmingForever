-- Crafting and Farming Forever :: Seller (bank alt mode)
-- With bank alt mode on and a name set in Options, one character (the bank alt) sells everything: the others craft
-- and mail what they make to it. At a mailbox their crafts are attached and sent by themselves (or with a click when
-- the game doesn't allow that), whole stacks, 12 to a mail; crafts in the bank are taken out on the bank step. The
-- postage is counted in the profit, and the bank alt's own bags and gold are left out of the crafters' plans.

local addonName, ns = ...
local Seller = {}
ns.Seller = Seller

local BAGS = { 0, 1, 2, 3, 4, 5 } -- backpack, four bags and the reagent bag
local TIMING = {
	STEP = 0.05,       -- between checks while an attachment or a mail is on its way
	ATTACH_WAIT = 2,   -- seconds one attachment gets to show up in the mail
	SEND_WAIT = 10,    -- seconds the server gets to say a mail went
	AUTO_DELAY = 1.5,  -- after the mailbox opens, before sending by itself
}
local TRANSIT_SECONDS = 30 * 24 * 3600 -- mail is deleted after 30 days

local open = false
local autoDone = false -- this mailbox visit has had its automatic send
-- job = { items = { { itemID, left } }, index, attached = { { itemID, count } }, pending, sending, auto,
--         mails, units, postage, stopped }
local job

local function Trim(text)
	return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- The bank alt's name as typed in Options, or nil.
function Seller.Name()
	local name = Trim(ns.db.ui.bankAltName)
	return name ~= "" and name or nil
end

function Seller.Enabled()
	return ns.db.ui.bankAltMode == true and Seller.Name() ~= nil
end

local function BaseName(name)
	return (name or ""):match("^([^%-]+)") or ""
end

-- Whether a character name is the bank alt's. Realm parts are left out of the comparison.
function Seller.IsName(name)
	local seller = Seller.Name()
	return seller ~= nil and name ~= nil and BaseName(name):lower() == BaseName(seller):lower()
end

function Seller.IsMe()
	return Seller.IsName(UnitName("player"))
end

-- This character crafts for the bank alt: what it makes gets mailed there, and it posts nothing itself.
function Seller.Active()
	return Seller.Enabled() and not Seller.IsMe()
end

-- Postage per unit a recipe makes, while the character crafting it isn't the bank alt. Nil when nothing is mailed.
function Seller.Postage(recipeID, itemID)
	if not Seller.Enabled() then return nil end
	local crafter = ns.Recipes.Crafter(recipeID)
	local char = crafter and ns.db.chars[crafter]
	if char and Seller.IsName(char.name) then return nil end
	return ns.Planner.PostagePerUnit(ns.Items.StackSize(itemID))
end

---------------------------------------------------------------------------
-- Crafts on their way: sent, but not yet seen in the bank alt's mailbox. They count as held for restocking until the
-- bank alt opens its mailbox, so the crafters don't make them again in the meantime.
-- db.sellerTransit[itemID] = { units, at }
---------------------------------------------------------------------------

function Seller.InTransit(itemID)
	local entry = ns.db and ns.db.sellerTransit and ns.db.sellerTransit[itemID]
	if not entry then return 0 end
	if time() - (entry.at or 0) > TRANSIT_SECONDS then
		ns.db.sellerTransit[itemID] = nil
		return 0
	end
	return entry.units or 0
end

local function NoteTransit(itemID, units)
	local entry = ns.db.sellerTransit[itemID] or { units = 0 }
	entry.units, entry.at = entry.units + units, time()
	ns.db.sellerTransit[itemID] = entry
end

---------------------------------------------------------------------------
-- What to send
---------------------------------------------------------------------------

-- Units of each item in the bags that can be mailed (not soulbound).
local function BagCounts()
	local counts = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isBound then
				counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
			end
		end
	end
	return counts
end

-- Materials of this character's own recipes: kept for crafting, only sent as far as the auction house lacks them.
local function OwnMaterials(ctx, me)
	local materials = {}
	local char = me and ns.db.chars[me]
	for recipeID in pairs(char and char.recipes or {}) do
		local recipe = ctx.recipes[recipeID]
		for _, slot in ipairs(recipe and recipe.r or {}) do
			for index = 2, #slot do materials[slot[index]] = true end
		end
	end
	return materials
end

-- The plan's "mail your crafts" part: { bags = { [itemID] = units }, bank = { ... }, units } or nil. Everything a
-- known recipe makes that can be sold, minus what the queue, a queued writ or crate, or a tool still needs.
function Seller.Plan(ctx, plan, wanted)
	if not Seller.Active() then return nil end
	local bags = BagCounts()
	local items = {}
	for itemID in pairs(ctx.known) do
		if ns.Items.CanSellOnAH(itemID) then
			local inBags, inBank = bags[itemID] or 0, ns.Stock.Bank(itemID)
			if inBags + inBank > 0 then items[itemID] = { bags = inBags, bank = inBank } end
		end
	end
	if next(items) == nil then return nil end
	local reserved = ns.Planner.ReservedMaterials(ctx, plan)
	for _, want in ipairs(wanted or {}) do
		for _, item in ipairs(want.items or {}) do
			if not item.buy then reserved[item[1]] = (reserved[item[1]] or 0) + item[2] * (want.qty or 1) end
		end
	end
	for itemID in pairs(plan.keep or {}) do reserved[itemID] = math.huge end
	local materials = OwnMaterials(ctx, ctx.me)
	return ns.Planner.SellerSend({
		items = items,
		reserved = reserved,
		limit = function(itemID)
			if not materials[itemID] then return nil end
			local onAH, owned = ns.Stock.ForRestock(itemID)
			return ns.Restock.FullGoal(itemID) - (onAH or 0) - (owned - ns.Stock.Own(itemID))
		end,
	})
end

-- What's in the bags to send right now.
function Seller.Pending()
	local send = ns.plan and ns.plan.send
	if not send or next(send.bags) == nil then return nil end
	return send.bags
end

function Seller.Busy()
	return job ~= nil
end

function Seller.IsOpen()
	return open
end

-- Mails sent and to send while a job runs, else nil.
function Seller.Progress()
	if job then return job.units, job.total end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function Changed()
	if ns.UI and ns.UI.SyncMailButton then ns.UI.SyncMailButton() end
	if Seller.SyncMailboxButton then Seller.SyncMailboxButton() end
end
Seller.Changed = Changed

local function MaxAttachments()
	return ATTACHMENTS_MAX_SEND or ns.Planner.MAIL_SLOTS
end

-- The first empty attachment slot of the mail being written, or nil when it's full.
local function FreeAttachment()
	for index = 1, MaxAttachments() do
		if not GetSendMailItem(index) then return index end
	end
end

local function AttachedCount()
	local count = 0
	for index = 1, MaxAttachments() do
		if GetSendMailItem(index) then count = count + 1 end
	end
	return count
end

local function Finish(stopped)
	local done = job
	job = nil
	if not done then return end
	if done.sending or #(done.attached or {}) > 0 then pcall(ClearSendMail) end
	if ClearCursor and GetCursorInfo() then ClearCursor() end
	local name = Seller.Name() or "your bank alt"
	if done.units > 0 then
		ns.Say("chatDone", ("Mail: sent %d to %s in %s, postage %s."):format(done.units, name,
			ns.Plural(done.mails, "mail", "mails"), ns.Money(done.postage)))
	end
	if stopped then
		ns.Say("chatWarnings", ("Mail to %s stopped: %s."):format(name, stopped))
	elseif done.units == 0 then
		ns.Say("chatDone", "Mail: nothing to send.")
	end
	ns.RequestPlan()
	Changed()
end

local Step

local function Later(delay)
	local this = job
	C_Timer.After(delay or TIMING.STEP, function()
		if job == this then Step() end
	end)
end

-- The stack to attach next: the biggest that fits in what's left to send, else the smallest, split.
local function Source(itemID, left)
	local whole, split
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID and not info.isLocked and not info.isBound
				and not job.used[bag .. ":" .. slot] then
				local found = { bag = bag, slot = slot, count = info.stackCount or 1 }
				if found.count <= left then
					if not whole or found.count > whole.count then whole = found end
				elseif not split or found.count < split.count then
					split = found
				end
			end
		end
	end
	return whole or split
end

local function Send()
	if #job.attached == 0 then return Finish() end
	local price = GetSendMailPrice and GetSendMailPrice() or (#job.attached * ns.Planner.POSTAGE)
	if price > GetMoney() then return Finish("not enough gold for the postage") end
	local units = 0
	for _, attached in ipairs(job.attached) do units = units + attached.count end
	local first = ns.Items.Name(job.attached[1].itemID) or "Crafts"
	local subject = #job.attached > 1 and ("%s and more (%d)"):format(first, units) or ("%s x%d"):format(first, units)
	job.sending = { at = GetTime(), price = price }
	SendMail(Seller.Name(), subject, "")
	Later()
end

Step = function()
	if not job then return end
	if not open then return Finish("the mailbox closed") end
	if InCombatLockdown() then return Finish("combat") end
	if job.sending then
		if GetTime() - job.sending.at > TIMING.SEND_WAIT then
			-- Sent by itself and never answered: the game likely only sends mail on a click, so the button it is.
			if job.auto then ns.db.ui.noAutoMail = true end
			return Finish(job.auto and "the game didn't send it by itself; press Send crafts at the mailbox from now on"
				or "no answer from the server")
		end
		return Later()
	end
	local pending = job.pending
	if pending then
		local name, itemID = GetSendMailItem(pending.index)
		if name or itemID then
			job.pending = nil
			table.insert(job.attached, { itemID = pending.itemID, count = pending.amount })
		elseif GetTime() - pending.at > TIMING.ATTACH_WAIT then
			if GetCursorInfo() then ClearCursor() end
			job.pending = nil
			job.items[pending.item].left = job.items[pending.item].left + pending.amount
		else
			return Later()
		end
	end
	local item = job.items[job.index]
	while item and item.left <= 0 do
		job.index = job.index + 1
		item = job.items[job.index]
	end
	local index = FreeAttachment()
	if not item or not index or #job.attached >= ns.Planner.MAIL_SLOTS then return Send() end
	local source = Source(item.itemID, item.left)
	if not source then
		item.left = 0
		return Later()
	end
	local amount = math.min(source.count, item.left)
	if amount < source.count then
		C_Container.SplitContainerItem(source.bag, source.slot, amount)
	else
		C_Container.PickupContainerItem(source.bag, source.slot)
	end
	ClickSendMailItemButton(index)
	job.used[source.bag .. ":" .. source.slot] = true
	item.left = item.left - amount
	job.pending = { index = index, item = job.index, itemID = item.itemID, amount = amount, at = GetTime() }
	Later()
end

-- Starts mailing the crafts in the bags to the bank alt. auto: started by the mailbox opening, not a click. Returns
-- false and why when it can't.
function Seller.Run(auto)
	if job then return false, "Already sending." end
	if not Seller.Active() then return false, "Bank alt mode is off, or this is the bank alt." end
	if not open then return false, "Open a mailbox first." end
	if InCombatLockdown() then return false, "Not in combat." end
	if GetCursorInfo() then return false, "Put down what's on your cursor first." end
	if AttachedCount() > 0 then return false, "Finish or clear the mail you're writing first." end
	local pending = Seller.Pending()
	if not pending then return false, "No crafts in your bags to send." end
	-- The attachments go on the Send Mail tab, which has to be the one showing.
	if SendMailFrame and not SendMailFrame:IsShown() and MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
	local items, total = {}, 0
	for itemID, units in pairs(pending) do
		table.insert(items, { itemID = itemID, left = units })
		total = total + units
	end
	table.sort(items, function(a, b) return a.itemID < b.itemID end)
	job = { items = items, index = 1, attached = {}, used = {}, auto = auto, mails = 0, units = 0, postage = 0,
		total = total }
	Changed()
	Step()
	return true
end

ns.On("MAIL_SEND_SUCCESS", function()
	if not (job and job.sending) then return end
	local price = job.sending.price
	local share = price / #job.attached
	for _, attached in ipairs(job.attached) do
		NoteTransit(attached.itemID, attached.count)
		ns.Sales.AddPostage(attached.itemID, share)
		job.units = job.units + attached.count
	end
	job.mails, job.postage = job.mails + 1, job.postage + price
	job.sending, job.attached, job.used = nil, {}, {}
	Changed()
	Later()
end)

ns.On("MAIL_FAILED", function()
	if job and job.sending then Finish("the mail was refused") end
end)

-- The game refusing an add-on's call: sending by itself isn't allowed, so from now on it waits for the button.
local function Blocked(addon)
	if addon ~= addonName or not job then return end
	local auto = job.auto
	Finish(auto and "the game doesn't let add-ons send mail by themselves" or "the game blocked it")
	if auto and not ns.db.ui.noAutoMail then
		ns.db.ui.noAutoMail = true
		ns.Say("chatWarnings", "From now on press Send crafts at the mailbox to mail your crafts to " .. (Seller.Name() or "your bank alt") .. ".")
	end
end
ns.On("ADDON_ACTION_BLOCKED", Blocked)
ns.On("ADDON_ACTION_FORBIDDEN", Blocked)

---------------------------------------------------------------------------
-- The mailbox
---------------------------------------------------------------------------

-- The button under the mailbox window.
local mailboxButton

function Seller.ButtonText()
	local name = Seller.Name() or "bank alt"
	local sent, total = Seller.Progress()
	if sent then return ("Sending to %s... %d / %d"):format(name, sent, total), false end
	local pending = Seller.Pending()
	if not open then return "Open a mailbox and this sends your crafts to " .. name, false end
	if not pending then return "No crafts to send to " .. name, false end
	local units, slots = 0, 0
	for itemID, count in pairs(pending) do
		units = units + count
		slots = slots + math.ceil(count / math.max(1, ns.Items.StackSize(itemID) or 1))
	end
	local _, postage = ns.Planner.MailCost(slots)
	return ("Send crafts to %s: %d, about %s postage"):format(name, units, ns.Money(postage)), true
end

function Seller.AddTooltipLines(tooltip)
	tooltip:AddLine(("Attaches the crafts in your bags, whole stacks, 12 to a mail, and sends them to %s. Postage is "
		.. "%dc per stack. What your queue still needs and your tools stay. It stops if the mailbox closes or a fight "
		.. "starts."):format(Seller.Name() or "your bank alt", ns.Planner.POSTAGE), 1, 1, 1, true)
	local pending = Seller.Pending()
	if pending then
		tooltip:AddLine(" ")
		local ids = {}
		for itemID in pairs(pending) do table.insert(ids, itemID) end
		table.sort(ids)
		for _, itemID in ipairs(ids) do
			tooltip:AddDoubleLine(ns.Items.Name(itemID) or "?", "x" .. pending[itemID], 1, 1, 1, 1, 1, 1)
		end
	end
end

function Seller.SyncMailboxButton()
	if not mailboxButton then
		if not open or not MailFrame or not (ns.UI and ns.UI.FlatButton) or not Seller.Active() then return end
		mailboxButton = ns.UI.FlatButton(MailFrame, "", 300, 24, true)
		mailboxButton:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 0, -4)
		mailboxButton:SetScript("OnClick", function()
			local ok, why = Seller.Run(false)
			if not ok and why then ns.Say("chatWarnings", why) end
		end)
		mailboxButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText("Bank alt mode")
			Seller.AddTooltipLines(GameTooltip)
			GameTooltip:Show()
		end)
		mailboxButton:SetScript("OnLeave", GameTooltip_Hide)
	end
	local shown = open and Seller.Active() and (job ~= nil or Seller.Pending() ~= nil)
	mailboxButton:SetShown(shown)
	if shown then
		local text, enabled = Seller.ButtonText()
		mailboxButton:SetText(text)
		mailboxButton:SetEnabled(enabled)
	end
end

local function SetOpen(state)
	if open == state then return end
	open = state
	if not open then
		autoDone = false
		if job then Finish("the mailbox closed") end
	end
	Changed()
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh("next") end
end

-- Opening the mailbox: the bank alt's mail now shows what was on its way; a crafter sends its crafts by itself.
local function MailboxOpened()
	SetOpen(true)
	if Seller.IsMe() and ns.db.sellerTransit and next(ns.db.sellerTransit) then
		wipe(ns.db.sellerTransit)
		ns.RequestPlan()
	end
	if autoDone or not Seller.Active() or ns.db.ui.noAutoMail then return end
	autoDone = true
	C_Timer.After(TIMING.AUTO_DELAY, function()
		if open and not job and Seller.Pending() then Seller.Run(true) end
	end)
end

ns.On("MAIL_SHOW", MailboxOpened)
ns.On("MAIL_CLOSED", function() SetOpen(false) end)
ns.On("BAG_UPDATE_DELAYED", function()
	if open then Changed() end
end)
local function IsMailbox(kind)
	local types = Enum and Enum.PlayerInteractionType
	return types and types.MailInfo ~= nil and kind == types.MailInfo
end
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
	if IsMailbox(kind) then MailboxOpened() end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
	if IsMailbox(kind) then SetOpen(false) end
end)
