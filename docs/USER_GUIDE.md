# User guide

Crafting and Farming Forever is one window with five tabs (**Profit**, **Queue**, **Restock**, **Sales**, **Changelog**), plus a small **Farm** list, a **Restocking** tab inside the auction house and an **Ad** box beside the chat.

The window opens with the profession window, on the tab you last used. Drag it anywhere: it stays put when other windows open or close, and it stays open if the profession window closes because you opened the auction house. `/cff auto` turns opening with the profession window off or on.

Hover any row with an item icon to see the game's item tooltip followed by the add-on's own details. Hover a row of column headings to see what each column means.

Drag the window's bottom-right corner to resize it; right-click that corner for the default size. The window alone and the window with the queue beside Restock each keep their own width.

**Refresh** at the top re-reads recipes, item data, Auctionator's prices and your stock, and redraws everything; at the auction house it also re-reads your auctions. It doesn't scan the auction house.

## Before you start

- **Record recipes.** Open each profession once on each character. Only recipes your characters know are listed, and a character's recipes are only read while its profession window is open.
- **Fresh prices.** Prices come from Auctionator. If its data is more than 24 hours old, the add-on asks for a new scan: a popup at the auction house, a banner in the window, an orange line at the top of the Next step bar while farming, and one line in chat after you log in (or open a profession). Quoting an order with old prices warns you in chat every time, and the Quote tooltip says so too. In material tooltips, an auction house price that's a day or more old is marked in orange, such as `3d old`, even after a recent scan, since a scan can miss items that had no listings.
- **Auctionator and Syndicator are both needed.** Auctionator supplies every price and the shopping list; the add-on doesn't load without it. Syndicator counts your alts' bags and banks and sees what you have on the auction house. Without Syndicator only the logged-in character's bags and bank count (so it may tell you to buy what an alt already has), the Restock tab is turned off so it can't over-craft, and a reminder appears in chat at each login.
- **TradeSkillMaster (TSM)** support is coming in a future update.

## Profit

Every known recipe, ranked by profit per craft:

> profit = sale price after the 5% auction house cut − cost of materials by the cheapest path

- **Profession tabs** on the left: **All**, plus every profession any of your characters has. The tab follows whichever profession you open, until you click a tab yourself.
- **Columns:** **Sells** is the chance one sells within 24 hours, from your sales history: white is likely, orange under 50%, red under 20%, grey with `~` a rough guess from fewer than 5 units. **Profit** is per craft.
- **Sorting:** the headings **Recipe**, **Sells** and **Profit** are buttons: click one to sort by it, click again to reverse. The sorted one is underlined with a bright arrow; the others show a faint arrow. Recipes with no price or no sales data always go last. The order is remembered.
- **Hide unprofitable recipes** (top left) hides recipes that would lose money or only break even at current prices. Recipes with no price yet and bind-on-pickup crafts stay. The footer says how many are hidden.
- **Advertise**, under the profession tabs, advertises the selected profession (on the All tab, the open one). Hover it to see what it will post, or why it can't.
- **Search** box in the footer: matches the item or recipe name, within the selected tab. If a tab has no matches, it tells you how many the All tab has. Escape clears it.
- **+** queues one craft; **Shift + +** queues ten. **Right-click +** (or Ctrl-click) opens a box to type how many crafts to queue.
- **Bind-on-pickup results** can't be sold, so they're listed after the priced recipes with their **craft cost** instead of a profit. They can still be queued.
- Enchants that don't produce an item aren't listed.

### Skill up (levelling)

**Skill up** at the top of the Profit tab (beside **Profit**) switches the list to levelling: the selected profession's recipes that can still give a skill point, the cheapest expected cost per point first. On the All tab it uses the profession that's open.

- Recipes are **coloured as in the profession window**. **Orange** always gives a skill point. **Yellow** gives one about half the time, and **green** only sometimes; both are estimates, as the real chance drops as your skill rises and the game doesn't say exactly. Grey recipes can't give skill and aren't listed; the footer counts them.
- **Columns:** **Chance** of a point per craft (100%, ~50%, ~25%), **Craft** (materials for one craft at market prices, by the cheapest path) and **Per point** (craft cost divided by the chance, and by the points per craft for recipes worth more than one).
- **Sorting:** the list starts with the lowest cost per skill point. The headings are buttons, as on the Profit list: click **Recipe**, **Chance**, **Craft** or **Per point** to sort by it, and click again to reverse. Your choice is remembered separately from the Profit list's.
- The footer shows your skill, such as `Tailoring 87/150`.
- Colours are per character and are read whenever the profession window is open, so they update as you level. For an alt, open its profession on that alt first.
- **+** queues crafts as on the Profit list, and clicking a row opens the recipe.

### Cheapest path

For each material, the add-on picks the cheapest of:

- buying it on the auction house (Auctionator's price),
- buying it from a vendor,
- crafting it from its own materials, if one of your characters knows the recipe.

Materials you already hold count as free when it decides whether crafting a material beats buying it. So 6 Tin Ore in your bank means it plans to smelt Tin Bars rather than buy them.

## Queue

One queue shared by all your characters.

The tab is a numbered to-do list in the order you'd work through it, so you reach the forge or the tanning rack with everything on you:

1. **Get from** an alt: log in there and mail the materials over.
2. **Collect from your mailbox**: what you bought, or mailed over, waiting there.
3. **Take from your bank**.
4. **Buy at auction house** (in Auctionator's Shopping tab, see [The shopping list](#the-shopping-list)), then **Buy from vendor**. With Farm It: what to gather, then what to smelt.
5. **Sub-crafts**: materials you make yourself (smelting bars for a recipe, say).
6. **Craft your queue**: the crafts this character makes.
7. **Log in to** another character: one step per alt with crafts in the queue, listing them.

The list is for the character you're logged in on. Crafts another character makes, such as your tailor's shirts while you're on your blacksmith, are only listed under **Log in to**: nothing is bought, gathered or made for them here. Log in to that character and its own list shows what to get, buy and craft there. What an alt holds for its own crafts isn't asked for by your other characters, and a sub-craft only an alt knows is bought instead (or gathered, with Farm It). This also goes for **Queue restock** on the All tab, the Auctionator shopping list, Still to buy and the Next step bar.

Steps with nothing to do are left out and the rest renumbered.

- **Adding:** **+** on the Profit tab, or **Queue** on a recipe's page (under the favourite star), which queues the number in the craft-count box.
- **Columns:** **Materials** and **Profit** are for the whole entry, every queued craft. **Crafts** is the number queued. When another character has to craft an entry, their name follows the recipe in blue.
- **Changing:** type the number of crafts in the row's box and press Enter (0 removes the entry), or use **-** and **+** (Shift for 10; Shift **-** stops at one). The red cross at the end of the row removes the entry.
- **Clear** empties the queue after asking. `/cff clear` empties it without asking.
- **Losing entries** (ones that would now sell for less than their materials) are shaded red. **Remove losing (N)** appears when there are any, and removes them after asking.
- **Buy It** / **Farm It** picks how materials are planned. The lit one is the current mode; see [Farm It](#farm-it).
- **Sub-crafts** (smelting bars for a recipe, say) aren't stored in the queue. They're worked out from it each time and shrink as your stock grows.
- **Craft Next** crafts the next thing this character can make now. If it can't, it says why: the next craft is on another character, or you need to open a profession.
- **Total profit**: sale prices after the auction house cut, minus materials at market price. Bind-on-pickup crafts show their cost and aren't counted.
- **Still to buy**: what you'll actually spend after what you own, compared with the gold you're carrying.
- **Take from your bank**: materials the plan uses that are in your bank, not your bags.
- **Buy from a vendor**: vendor materials. They're shown here only, never on the Auctionator list.
- **Quote** on each row fills in a whisper to the last person who whispered you, with one price for the whole queued amount: the material cost of every craft plus your margin, for example `[Healing Potion] x20: 5g 20s`. The count is the number of items made, so a recipe that makes 5 queued twice says x10. Hover **Quote** to see the material cost and the quote before sending. Press Enter to send it.
- **Quote margin %** at the bottom right sets the margin: 10% by default, anything from 0 to 1000%. Type a number and press Enter; it's remembered.

### Next step bar

While anything is in the queue, a small bar at the top of the screen shows the first step of the Queue tab's to-do list: what to get from an alt, take from the bank, buy, gather (in Farm It mode), sub-craft or craft. When that step is done it moves on to the next; "1 of 4" says how many steps are left. On a crafting step it has its own **Craft Next** button, or says why it can't craft yet.

- The **-** button folds it to a single line that still names the step; **+** opens it again. It remembers which you chose.
- Drag it anywhere; it remembers the place.
- It opens by itself when you queue something and disappears when the queue is empty. `/cff next` folds or unfolds it.
- It hides in combat and in dungeons, raids, battlegrounds and arenas, and comes back when you leave.
- In Farm It mode all gathering (mining, herbs, skinning, drops) is one step, each kind under its own heading, since you gather whatever you come across.

### Price changes

Each material and sale price shows what it was before the latest scan: **was X, now Y**. Red means worse for your profit (a material got dearer or the sale price dropped). Green means better. Nothing is removed from the queue automatically; you decide.

A new comparison starts when you scan the whole shopping list or run a full scan. Searching a single item updates its price but keeps the comparison.

### The shopping list

The add-on keeps one Auctionator shopping list, **Crafting and Farming Forever Queue**, and edits it in place as the queue and your stock change. It holds every material you still need to buy, after your bags, bank, mailbox and (with Syndicator) your alts' bags and banks. What you're going to craft isn't on it.

**Where to find it:** go to an auction house, click the **Shopping** tab at the bottom of the auction house window (Auctionator adds it), then click the list **Crafting and Farming Forever Queue**. The Queue tab and the Next step bar say this under the buying step (hover it for the steps), and a line in chat repeats it when you open the auction house with something to buy.

**What you buy leaves the list at once.** Auction house purchases go to your mailbox, so the add-on counts them as waiting in the mail as soon as the purchase goes through, and the queue gets a **Collect from your mailbox** step. When you open the mailbox, what's really there replaces that count; take the items out and they count as being in your bags.

Guild bank, warband bank, mail on other characters and your own auctions don't count as stock. Quantities aren't capped, because a cap would hide dearer listings you might still want.

## Farm It

**Farm It** at the top of the Queue tab turns the plan into what to gather yourself, and closes the window. The [Next step bar](#next-step-bar) at the top of the screen then shows everything to gather at once, grouped:

- **Mine**, **Pick herbs**, **Skin creatures**, **Fish**: which veins, herbs or creatures, and in which zones.
- **Kill for drops**: which creatures drop it.
- **Disenchant**, and **Other sources** for anything else.

Your current zone comes first. Hover a row to see everything known about where the item comes from. Errands (alts, bank, vendor) come before gathering, and smelting after it. The bar counts down as you gather and moves on to smelting and crafting when everything is gathered. While farming, the bar has a **Buy It** button that switches back to buying and reopens the queue; the Queue tab's **Buy It** does the same. The Auctionator list is the same in both modes.

## Restock

Keeps a number of each item you craft listed on the auction house.

- **Columns:** **Sells** (chance to sell within 24 hours), **AH** (how many you have listed), **Have** (held in bags, banks and mail across your characters), **Craft** (crafts Queue restock would add; `skip` when the goal is 0) and **Goal**.
- **Goals:** each profitable item gets one. The defaults are in the boxes at the bottom: **Default goal: stackable** 10 and **single** 1. Change one item's goal by typing it in the box on its row, or with **+** and **-** (Shift for 10). A goal of 0 skips the item.
- **Default or your own:** a grey goal follows the defaults, so it changes when you change them. A white goal is one you set for that item, and has an arrow button beside it that puts it back on the default. Setting a goal equal to the default also makes it follow the default again.
- **Min profit (s):** items earning less than this per craft are skipped. The default is 1 silver.
- **Counted towards the goal:** what's on the auction house (from Syndicator) and what all your characters hold in bags, banks and mail.
- **Queue restock: N item(s)** queues the difference for the selected profession tab. It replaces that profession's earlier restock entries and keeps anything you queued by hand, which also counts towards the goal. It never queues by itself. **Fully stocked** means there's nothing to do.
- **Show Queue** opens the queue beside the Restock tab.

Syndicator only refreshes your auctions while you're at the auction house, so an item that sold since your last visit still counts as listed until you go back.

## Restocking (at the auction house)

A **Restocking** tab beside Auctionator's tabs at the bottom of the auction house. It lists items in your bags that one of your recipes makes, with the amount your goals want on the auction house first.

Select an item and it searches the live listings:

- **Quantity** suggested: the goal minus what's already listed, up to what's in your bags and not needed by the queue.
- **Price each** suggested: just under the lowest listing, or the lowest itself if that listing is yours. With no listings it uses the last scan; with nothing to go on it stays blank.
- It never suggests a price below break-even (material cost after the cut).
- Stackable goods are priced to the copper and undercut by 1 copper. Gear and bags only accept whole silver, so they undercut by 1 silver.
- If a vendor would pay more than the price earns after the cut, it warns you and asks before posting, but leaves the price as you set it.
- **Duration** chooses the auction length.

**Post** lists it and moves to the next item. **Next item** skips. Items posted this visit count as listed straight away, before Syndicator recounts.

## Sales

Sold and expired auctions per item, for **Today**, **Last 7 days**, **Last 30 days** and **All time**, plus each item's chance of selling within 24 hours.

- Results are read from auction house mail, so they appear when that character opens the mailbox, including sales made while you were offline.
- Time on the auction house comes from your posts.
- The chance uses all history: `1 − exp(−sold ÷ (unit-days listed + 1))` per unit listed. With fewer than 5 units of history it's shown grey with `~`, as a rough guess.
- Items are matched by name, because sold mail doesn't say which item ID it was.

## Advertising

A small **Ad** box beside the main chat window. Click it to pick where to post (**Trade**, **Guild**, **Say** or **Yell**) and one button per crafting profession of the logged-in character. One click posts that profession's link with a short offer (your materials, or a price based on material cost), and the box closes.

- Gathering professions (Herbalism, Mining, Skinning, Fishing) aren't offered.
- Each destination can be used once every 60 seconds.
- The box can't open or close in combat.
- The **Advertise** button on the Profit tab and `/cff advertise` fill in the chat box instead, for you to press Enter. This is a game restriction: only the Ad box's buttons can send directly.

## Commands

| Command | What it does |
| --- | --- |
| `/cff` or `/craftfarm` | Show or hide the window |
| `/cff profit`, `queue`, `restock`, `sales` | Open that tab, or close the window if that tab is already showing |
| `/cff next` | Fold or unfold the Next step bar |
| `/cff refresh` | Re-read recipes, stock and prices (the Refresh button) |
| `/cff advertise` | Advertise the selected profession in the chosen channel |
| `/cff clear` | Empty the queue |
| `/cff auto` | Toggle opening with the profession window |
| `/cff changelog` (or `/cff new`) | Open the Changelog tab |
| `/cff diag` | Print diagnostics and save them for troubleshooting |

## Changelog

The last tab lists what changed in each version, newest first, in plain words, followed by the add-ons it needs and what's coming. After an update the tab turns green with a dot until you open it, and the versions you haven't seen yet are marked **new** for the rest of that session. Nothing pops up. A first install doesn't light it.

## Troubleshooting

**A character's recipes are missing.** Open that profession on that character. Recipes are only recorded while the profession window is open.

**Profit shows no price for something.** Auctionator has never seen it listed. Search it at the auction house, or run a full scan.

**A red chat line says Syndicator isn't installed or is turned off.** Install Syndicator, make sure it's ticked in the AddOns list at character select, and restart the game.

**Stock from alts isn't counted.** Install Syndicator and log in to each alt once so it records their bags and banks. Visit the bank on each alt too.

**The queue or recipes vanished after a restart.** Run `/cff diag`, then `/reload`, and report the output. Saved data is only written on `/reload` or logout, so a crash loses changes since then.

**Reporting a bug.** Run `/cff diag`, then `/reload` so it's saved, and include the `lastDiag` lines from `WTF/Account/<account>/SavedVariables/CraftingAndFarmingForever.lua`, plus any error from BugSack.

## Upgrading from CraftLedger

The add-on used to be called CraftLedger. To keep your queue, recipes, goals and sales history:

1. Quit the game. It rewrites saved data on logout and would undo the move.
2. Run `tools/migrate-name.sh "/path/to/World of Warcraft/_forever_"` from this repository.

It copies each account's `CraftLedger.lua` saved data to `CraftingAndFarmingForever.lua` (the old file is left as it was), installs the add-on under its new folder name and removes the old `CraftLedger` folder so the two never load together.

The old Auctionator list **CraftLedger Queue** is no longer used. Delete it in Auctionator's Shopping tab.
