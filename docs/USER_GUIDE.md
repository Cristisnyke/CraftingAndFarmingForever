# User guide

Crafting and Farming Forever is one window with eight tabs (**Profit**, **Queue**, **Restock**, **Sales**, **Writs**, **Crates**, **Options**, **Changelog**), plus a small **Next step** bar, a minimap button, a **Restocking** tab inside the auction house and an **Ad** box beside the chat.

The window opens with the profession window, on the tab you last used. Drag it anywhere: it stays put when other windows open or close, and it stays open if the profession window closes because you opened the auction house. The Options tab (or `/cff auto`) turns opening with the profession window off or on.

The minimap button opens or closes the window with a left-click and opens the Options tab with a right-click. Drag it round the minimap to move it. Minimap button collectors (such as MinimapButtonButton) and broker bars pick it up like any other button. The Options tab or `/cff minimap` hides or shows it.

Hover any row with an item icon to see the game's item tooltip followed by the add-on's own details. Hover a row of column headings to see what each column means.

Drag the window's bottom-right corner to resize it; right-click that corner for the default size. The window alone and the window with the queue beside Restock each keep their own width.

**Refresh** at the top re-reads recipes, item data, Auctionator's prices and your stock, and redraws everything; at the auction house it also re-reads your auctions and looks up every listing of the materials your queue would buy again, even ones read a minute ago, so the costs are as of now (see [What buying many really costs](#what-buying-many-really-costs)). It isn't a price scan: sale prices still come from Auctionator's scan.

## Before you start

- **Record recipes.** Open each profession once on each character. Only recipes your characters know are listed, and a character's recipes are only read while its profession window is open.
- **Fresh prices.** Prices come from Auctionator. If its data is more than 24 hours old, the add-on asks for a new scan: a popup at the auction house, a banner in the window, an orange line at the top of the Next step bar while farming, and one line in chat after you log in (or open a profession). Quoting an order with old prices warns you in chat every time, and the Quote tooltip says so too. In material tooltips, an auction house price that's a day or more old is marked in orange, such as `3d old`, even after a recent scan, since a scan can miss items that had no listings.
- **Auctionator and Syndicator are both needed.** Auctionator supplies every price and the shopping list; the add-on doesn't load without it. Syndicator counts your alts' bags and banks and sees what you have on the auction house. Without Syndicator only the logged-in character's bags and bank count (so it may tell you to buy what an alt already has), the Restock tab is turned off so it can't over-craft, and a reminder appears in chat at each login.
- **TradeSkillMaster (TSM)** support is coming in a future update.

## Profit

Every known recipe, ranked by profit per craft:

> profit = sale price after the 5% auction house cut − cost of materials by the cheapest path

- **Profession tabs** on the left: **All**, plus every profession any of your characters has. The tab follows whichever profession you open, until you click a tab yourself.
- **Columns:** **Sells** is the chance one sells within 24 hours, from your sales history: white is likely, orange under 50%, red under 20%, grey with `~` a rough guess from fewer than 5 units. **Profit** is per craft, for as many crafts as the item's restock goal makes (a goal of 5 prices 5 crafts; gear with a goal of 1 prices one). Materials whose listings the add-on has read count down those listings, so a recipe whose cheap materials run out after a craft or two shows the average over the batch. The tooltip says how many crafts it's priced for, what one craft would cost, and which materials' listings haven't been read yet (those count at their cheapest listing).
- **Sorting:** the headings **Recipe**, **Sells** and **Profit** are buttons: click one to sort by it, click again to reverse. The sorted one is underlined with a bright arrow; the others show a faint arrow. Recipes with no price or no sales data always go last. The order is remembered.
- **Hide unprofitable recipes** (top left) hides recipes that would lose money or only break even at current prices. Recipes with no price yet and bind-on-pickup crafts stay. The footer says how many are hidden.
- **Advertise**, under the profession tabs, advertises the selected profession (on the All tab, the open one). Hover it to see what it will post, or why it can't.
- **Search** box in the footer: matches the item or recipe name, within the selected tab. If a tab has no matches, it tells you how many the All tab has. Escape clears it.
- **+** queues one craft; **Shift + +** queues ten. **Right-click +** (or Ctrl-click) opens a box to type how many crafts to queue.
- **Bind-on-pickup results** can't be sold, so they're listed after the priced recipes with their **craft cost** instead of a profit. They can still be queued.
- Enchants that don't produce an item aren't listed.
- **Check price** (orange, with `!` before the profit): the item is listed for more than 400% of its material cost, which is usually one odd listing that won't sell. Profit still counts that listing, so check it. Recipes with a cooldown (Mooncloth, transmutes) are never flagged, since they really sell far above their materials. Search the item at the auction house before you craft it. The same mark shows on the Queue tab. The limit is on the Options tab.

### Skill up (levelling)

**Skill up** at the top of the Profit tab (beside **Profit**) switches the list to levelling: the selected profession's recipes that can still give a skill point, the cheapest expected cost per point first. On the All tab it uses the profession that's open.

- Recipes are **coloured as in the profession window**. **Orange** always gives a skill point. **Yellow** gives one about half the time, and **green** only sometimes; both are estimates, as the real chance drops as your skill rises and the game doesn't say exactly. Grey recipes can't give skill and aren't listed; the footer counts them.
- **Columns:** **Chance** of a point per craft (100%, ~50%, ~25%), **Craft** (what one craft really costs: materials at market prices by the cheapest path, less what selling what it makes gets back) and **Per point** (that cost divided by the chance, and by the points per craft for recipes worth more than one). A green **+** means the craft sells for more than its materials: you earn gold while levelling, and those recipes come first.
- **Selling on the AH** (top): unticked, what you make counts at what a vendor pays for it. Ticked, the auction house price after its 5% cut counts instead when it's more. Levelling usually means many of one thing, and the auction house may not take them all at that price, so tick it only if you'll really sell them there. Either way, a recipe's tooltip shows both prices; the one not counted is grey and says "(not counted)".
- **Sorting:** the list starts with the lowest cost per skill point. The headings are buttons, as on the Profit list: click **Recipe**, **Chance**, **Craft** or **Per point** to sort by it, and click again to reverse. Your choice is remembered separately from the Profit list's.
- The footer shows your skill, such as `Tailoring 87/150`.
- Colours are per character and are read whenever the profession window is open, so they update as you level. For an alt, open its profession on that alt first.
- **+** queues crafts as on the Profit list, and clicking a row opens the recipe.

### Recipes (what to learn next)

**Recipes**, the third button at the top of the Profit tab, lists every recipe in the game that you haven't learned yet, for the profession tab you pick (on **All**, every profession your character has), sorted by the skill needed to learn it.

- **Colours:** **green** can be learned now, **white** needs more skill (the Skill column turns red), **grey** is learned (shown with **Show learned** ticked), dim means the character doesn't have that profession.
- **Columns:** **Skill** needed to learn it, **Source** (Trainer, Vendor, Quest, Dungeon, Drop, Treasure, World drop; `+1` means it also comes from one more kind of place, `*` means only during a holiday), **AH price** of the recipe item when it's traded (**BoP** when it binds on pickup and can't be bought), **Profit** per craft if you learned it (as on the Profit list; **BoP** when what it makes binds on pickup, **-** when it makes no item, **?** until its materials are known) and **Pays back**: how many crafts' profit pays for the recipe at its auction house price (**never** when a craft doesn't make a profit; blank for learned recipes and recipes with no auction house price, such as trainer recipes and drops).
- **Profit for recipes you don't know:** the add-on reads their materials from the profession window, which lists unlearned recipes too, so open each profession once on any character. Sub-crafts only use recipes one of your characters already knows. Hover a recipe for its materials, what it sells for and when it pays back. Sort by **Profit** or **Pays back** to find the recipes worth buying.
- **Hover a recipe** for where to get it: the vendor, zone, price (gold, tokens, Merchant's Favor) and reputation needed, limited supply; the quest and who gives it; the dungeon and boss; the mobs that drop it. Vendors and quests of the other faction are left out. Below that, every one of your characters with that profession and whether they've learned it, can learn it now, or how much skill they're short.
- **This character / All characters** (bottom left, where Advertise is in the other modes) switches whose recipes you see. With **All characters**, a recipe is listed while any character with that profession is missing it, and those characters are named in blue on the row.
- **New to learn:** when this character can learn recipes it couldn't the last time you opened Recipes (usually after a skill-up), the **Profit** tab and the **Recipes** button turn green with a dot, as the Changelog tab does for new notes. Opening Recipes puts it out; those recipes say **new** for the rest of the session. The first time, everything learnable counts as new. Only characters whose profession skill has been read count (open the profession once).
- **Show learned** (top) lists learned recipes too, in grey.
- **Hide BoP** (top) lists only recipes whose craft you can post on the auction house: recipes that make something binding on pickup, or no item at all (most enchants), are left out. The tooltip's **Makes** line shows the crafted item and what it sells for. What an unlearned recipe makes is read from the profession window, so open each profession once; until then those recipes stay listed and the footer counts them as "not checked yet".
- **Recipes shopping list:** Each profession gets its own Auctionator shopping list, such as **Tailoring Shopping List**, with the recipe items (patterns, plans, formulas...) the character you're playing can learn right now, lowest skill first. Recipes that come only from a trainer, or bind on pickup, aren't on it. Open it in Auctionator's **Shopping** tab to search them all. It follows the character you're logged in on and updates when you learn a recipe (its row goes) or your skill goes up. Only professions whose window you've opened on that character count; lists for professions this character doesn't have are removed (the add-on only removes lists it made). Don't want them? Untick **Recipe shopping lists** on the Options tab: the lists the add-on made are deleted and stay gone until you tick it again.
- **Click** a recipe for its Wowhead link, selected in a box: press Ctrl+C and paste it in your browser. It goes to the page of the item that teaches the recipe (who sells it, what drops it), or to the recipe itself when no item teaches it.
- **Shift-click** a recipe to link it in chat, for asking in Trade.
- Sorting and search work as on the Profit list. The list starts with the lowest skill needed.
- Where recipes come from is built from **AllTheThings** data and ships with the add-on; you don't need AllTheThings installed. Recipes new to Forever that AllTheThings doesn't have yet show with source "Unknown" once the profession window has listed them. When you open a profession, the game's own list of its recipes is remembered, and recipes AllTheThings has that this game doesn't are left out (the footer counts them).
- A character's skill is read when its profession window is open. Until then the tooltip says "skill not read".

### Cheapest path

For each material, the add-on picks the cheapest of:

- buying it on the auction house (Auctionator's price),
- buying it from a vendor,
- crafting it from its own materials, if one of your characters knows the recipe.

Materials you already hold count as free when it decides whether crafting a material beats buying it, however deep down they're used: Wool in your bags makes the Bolt of Woolen Cloth your recipe needs by way of the cloth. So 6 Tin Ore in your bank means it plans to smelt 6 Tin Bars rather than buy them, and when you need 10, the other 4 are smelted from bought ore or bought as bars, whichever costs less.

### What buying many really costs

A price scan only knows each material's cheapest listing. If 5 Iron Ore are listed at 5s and the next 10 at 10s, buying 15 costs 1g 25s, not 75s. So at the auction house the add-on reads every listing of the materials your queue would buy, and of the materials they could be made from. The Restock tab doesn't read any: it picks crafts at the cheapest listing, and a restock is checked once it's on your queue (see Restock).

- It starts a second after you open the auction house and takes a few seconds, one material at a time. It waits for your own searches and other add-ons', and pauses while you browse, scan or buy. The Queue tab's auction house step says "reading listings, 4 to go" meanwhile.
- While it reads, the screen is locked once, for the whole check: the screen dims, the window stays on the tab you have open (it opens on the Queue tab if it was closed), and a box at the bottom of the window names the material being read ("Reading Copper Bar: 3 of 12") with a progress bar. The rows that need it are outlined in gold: the row to buy it on the Queue tab and the Next step bar, or the crafts that use it on the Restock tab. Clicks and keys do nothing meanwhile, so a search or a purchase can't get in the way. When the reading is done it says "Working out the plan with the new prices" for a moment (the new plan can want one more material read, which happens under the same lock), then unlocks. It also unlocks when you close the auction house, a fight starts, the auction house hasn't answered for 15 seconds, or after 2 minutes whatever happens; when another add-on's search is running it says it's waiting instead. **Escape** unlocks it at once; the reading then goes on in the background. Listings read from the items you open yourself never lock the screen.
- You can watch it work: when the material being read is off screen, the list scrolls to it. Once its listings are in, a gold bar runs across its row, counting through the listings from the cheapest up to the amount you buy (**Counting 87 of 192**), with a tick where the price steps up. At the end the bar pulses **green** when the average is at or below the item's usual price, **red** when it's above, gold when there's no usual price yet; red at the right end means fewer are listed than you need. The average itself is in the box at the bottom.
- Every item you open to buy is read too, so the costs follow the market while you shop.
- **Still to buy**, the restock's gold check and the choice between buying a material and crafting it then use the real cost of the amount you need. Your own auctions aren't counted: you can't buy those.
- **Sub-crafts stop where they stop paying.** For a material you can make, both sides are read: the ore and the bars. The add-on smelts bars only while that's cheaper than buying them and buys the rest, so when the cheap ore runs out halfway, half the bars are smelted and half bought, whichever mix costs least in total. When smelting and buying cost the same, it buys.
- In the Queue tab, a row says **avg** with the average price when the cheapest listing doesn't cover it all, and its total is what all of them cost. "30 listed" in orange means fewer are listed than you need; the rest count at the dearest listing.
- Listings are kept for a day. A material whose listings were never read still counts at its cheapest listing times the amount, as before. The Profit tab uses the listings read for the crafts each item's restock goal makes (see Profit), and a smart goal's quarter-of-your-gold limit counts what that many really cost to make.

**The plan checks itself.** When a search of the queue's shopping list, a price scan or this listings check finishes, the plan is worked out again with the new prices. Rows whose buying or sub-crafting changed pulse gold, and a note on the window says how many changed. When nothing changed, the window pulses green with "Plan checked: still the cheapest way". The note shows on the main window and above the Next step bar, whichever are open, or in chat when neither is. Buying what the list says isn't a change (purchases waiting in the mail count as bought). Closing the auction house before a search finishes gives no verdict.

**Read listings at the auction house** on the Options tab turns the add-on's own lookups off; it then only learns from the items you open yourself.

## Queue

One queue shared by all your characters.

The tab is a numbered to-do list in the order you'd work through it, so you reach the forge or the tanning rack with everything on you:

With Farm It, gathering comes first (step 0 below), so the trip to town covers only what you didn't find; smelting comes after the vendor.

0. With Farm It: what to **gather**, every group (Mine, Pick herbs, Skin, ...) at once.
1. **Get from** an alt: log in there and mail the materials over.
2. **Make room** and **Take from your bank** (only when your bags would fill up, see [Bag space](#bag-space)).
3. **Buy at auction house** (in Auctionator's Shopping tab, see [The shopping list](#the-shopping-list)).
4. **Collect from your mailbox**: what you bought, or had mailed over. It comes once the whole shopping list is bought, and the mailbox is right beside the auction house.
5. **Buy from vendor**. With Farm It, then what to smelt.
6. **Get your tools**: only when a craft needs a tool you have nowhere (see Tools below).
7. **Sub-crafts**: materials you make yourself (smelting bars for a recipe, say).
8. **Craft your queue**: the crafts this character makes. When your bags can't hold the whole queue: **Craft this run**, then **Next run** with what's left.
9. **Log in to** another character: one step per alt with crafts in the queue, listing them.

The list is for the character you're logged in on. Crafts another character makes, such as your tailor's shirts while you're on your blacksmith, are only listed under **Log in to**: nothing is bought, gathered or made for them here. Log in to that character and its own list shows what to get, buy and craft there. What an alt holds for its own crafts isn't asked for by your other characters, and a sub-craft only an alt knows is bought instead (or gathered, with Farm It). This also goes for **Queue restock** on the All tab, the Auctionator shopping list, Still to buy and the Next step bar.

Steps with nothing to do are left out and the rest renumbered.

- **Adding:** **+** on the Profit tab, or **Queue** on a recipe's page (under the favourite star), which queues the number in the craft-count box.
- **Columns:** **Materials** and **Profit** are for the whole entry, every queued craft. **Crafts** is the number queued. When another character has to craft an entry, their name follows the recipe in blue.
- **Changing:** type the number of crafts in the row's box and press Enter (0 removes the entry), or use **-** and **+** (Shift for 10; Shift **-** stops at one). The red cross at the end of the row removes the entry.
- **Clear** empties the queue after asking. `/cff clear` empties it without asking.
- **Losing entries** (ones that would now sell for less than their materials) are shaded red. **Remove losing (N)** appears when there are any, and removes them after asking.
- **Buy It** / **Farm It** picks how materials are planned. The lit one is the current mode; see [Farm It](#farm-it).
- **Difficulty**: queued crafts and sub-crafts are named in the profession window's colours for the character who makes them (orange: a skill point every craft, yellow: about every other craft, green: now and then, grey: none). Hover one to read it. The colour is the one from the last time that character had the profession open; until then the name is white.
- **Sub-crafts** (smelting bars for a recipe, say) aren't stored in the queue. They're worked out from it each time and shrink as your stock grows.
- **Craft Next** crafts the next thing on the list, strictly in order: sub-crafts first, then your queue. It never skips ahead to a later craft. If the craft belongs to a profession that isn't open, the button says so (**Open Mining: Smelt Bronze x12**); clicking opens that profession, switching from the one you have open, and starts crafting once it has loaded. If the game ever stops an add-on from crafting right after opening a profession, a chat line says so and from then on the first click opens and the second crafts. The profession window stays open while you craft: the game only crafts from an open profession. While the current one can't be made (missing materials, no anvil nearby), the button says what to finish and how many are left, for example **Finish Smelt Bronze: 8 left**, and the line above it says why.
- The **Craft Next** button is also a progress bar. Before you start, it glows blue and its second line says how long the batch takes and how long all your crafts take ("x12 takes 36s   all crafts 3:10 (45)"). While you craft it fills through that recipe's crafts ("Smelt Bronze 8 / 20") and counts down the time until they're all done, and a thin light-blue line along its bottom fills as you work through everything you're crafting on this character. Stop halfway and it remembers where you were ("7 / 20 done"). Hover it for the time each remaining recipe takes. Times come from your own casts, including the short pause between crafts; a recipe you haven't cast yet uses its spell's cast time. Crafts on other characters aren't counted. When your bags can't hold the whole queue, it's split into runs: the bar then shows this run and all runs ("this run 3:10 (45)  all runs 9:30 (135)"), and the queue's headers give the time of this run and of the runs after it.
- While you craft, the bar comes alive: a light runs along it, each craft flashes it and floats the item up with what that craft earns at today's price, a counter above the middle of the bar shows your **streak** and what this session's crafts have earned, and a finished batch bursts into sparks with a **Batch complete!** banner.
- **Total profit**: sale prices after the auction house cut, minus materials at market price. Bind-on-pickup crafts show their cost and aren't counted.
- **Still to buy**: what you'll actually spend after what you own, compared with the gold you're carrying.
- **Take from your bank**: materials the plan uses that are in your bank, not your bags.
- **Tools**: some crafts need a tool in your bags, such as a Blacksmith Hammer, an Arclight Spanner or a Runed Copper Rod. When one isn't in your bags, it goes on the step where it is, marked "(tool)": **Take from your bank**, **Collect from your mailbox**, **Get from** an alt, or **Buy from vendor** when you have none and you've seen a vendor sell it. When you have none and no vendor price is known, **Get your tools** says so. Only one of each tool is listed, and **Make room** never puts a tool your queue needs in the bank. A tool the add-on doesn't know gets a reminder under **Craft your queue** instead. The add-on learns which tools a recipe needs when you open its profession.
- **Camp stations**: some crafts can only be made beside a camp station, such as a Fermenter (alchemy oils), a Spinning Wheel, a Tanning Rack, a Loom, a Master Forge, an Iron Oven (cooking) or an Anarchist's Workbench (engineering). Placing a station uses it up and needs a campfire nearby, so the queue gets the station your crafts need and a campfire kit, marked "(camp)": from your bags, bank, mailbox or an alt when you have one, else bought or crafted, whichever costs less, counted in the total. A placed station stands only **15 minutes**, and placing one puts **every** station on a **1 hour cooldown** (a Master Forge puts the Fermenter on cooldown too). So the to-do list does every other craft first, sub-crafts for the station's crafts included, and then has a step of its own, **Camp: place a Fermenter and craft beside it**, listing only the crafts made there, one after another (Craft Next follows the same order). That step says how many crafts fit the 15 minutes, how long your placed station still stands, or how long the cooldown still runs, and warns when your queue needs two different stations (craft one station's list now, the other an hour later). Once you've placed a kit or a station, the add-on remembers it while you stay in that zone (a station for 15 minutes, a campfire for an hour): the line says **your campfire is lit** or **your Fermenter is placed**, and nothing more is asked for. **Restock** uses one station at most: the one whose crafts earn the most once the station itself (and a campfire kit) is paid for, assuming nobody else's station is there. Items needing another station get no crafts ("0/4" in the Craft column, the tooltip says why), only as many station crafts as fit the 15 minutes are queued ("12/20"), and while the cooldown runs no station crafts are added. A station nobody sells and none of your characters can make gets an orange line instead. Station crafts restock in **batches**: nothing while you have the item's goal, and once you're under it, the goal times **Camp batch** (Options, default 3) in one go, so one station pays for itself; what isn't posted waits in your bags. Anvils aren't counted, as every town has one. The add-on learns which recipes need a station when you open their profession.
- **Buy from a vendor**: vendor materials. They're shown here only, never on the Auctionator list.
- **Quote** on each row fills in a whisper to the last person who whispered you, with one price for the whole queued amount: the material cost of every craft plus your margin, for example `[Healing Potion] x20: 5g 20s`. The count is the number of items made, so a recipe that makes 5 queued twice says x10. Hover **Quote** to see the material cost and the quote before sending. Press Enter to send it.
- The margin is set on the **Options** tab: 10% by default, anything from 0 to 1000%. You can also write your own quote message there.

### Bag space

Buying the materials for a big queue can fill your bags before you've crafted anything. So the plan follows your bags (backpack, bags and reagent bag) through the list: everything you take out of the bank, buy and collect, then each craft taking its materials and adding what it makes. One slot is always kept free before and after every craft, because the game won't start a craft with full bags, even one that would free room. While all of it fits, nothing changes.

When it doesn't fit:

1. **Make room: put these in your bank**. Only materials and crafted items of your known recipes that the plan doesn't need right now, the ones taking the most slots first, and only as many as it takes. It's on the same bank trip as **Take from your bank**. Anything else in your bags is yours to decide about: when even that isn't enough, an orange line says how many slots are still missing.
2. If banking still isn't enough, the queue is crafted in **runs**. A run is as much of the queue as your bags hold, starting with the crafts that use up the most room (a craft that turns a stack of ore into one item before one that turns two bolts into a shirt). The list then shows **Craft this run: N crafts**, each row says **this run: 7** when only part of it is in the run, and the rest is listed under **Next run**. The shopping list, Still to buy and the Next step bar follow the run, so you only buy what this run needs.
3. Once the run is crafted, the list starts over: bank what you made if there's no room, then buy for the next run. A run stays as it is until it's crafted, so the list doesn't change halfway through; adding to the queue plans a new run.

On the Next step bar, a **Make room** or **Take from your bank** step has a **Bank it** button. Open your bank and click it: it puts away everything the step lists, then takes out what the queue needs from the bank, one stack at a time, splitting stacks when only part is needed (crafting reagents go to the reagent bag first). It says in chat when it's done, if your bank or bags filled up, or if something wasn't found. It stops when the bank closes or a fight starts, and won't start while you hold something on the cursor.

At a vendor, a **Buy for your queue** button shows the price of what the **Buy from vendor** step needs from that vendor. It's under the vendor window and on the Next step bar (whatever step the bar is on, so you can grab thread on the way to the auction house). Click it to buy exactly that, even when the vendor lists an item in bundles (vials in fives), like a shift-click. Hover it for the list, including what this vendor doesn't sell. It only appears when the vendor has something your queue needs, buys nothing you didn't click for, and stops if you close the vendor, your bags fill up or your gold runs out.

The bank's own free space isn't checked before planning; **Bank it** stops and says so when it's full. Turn it all off with **Plan around bag space** on the Options tab. Farm It plans don't use runs: you gather what you come across.

### Next step bar

While anything is in the queue, a small bar at the top of the screen shows the first step of the Queue tab's to-do list: what to get from an alt, take from the bank, buy, gather (in Farm It mode), sub-craft or craft. When that step is done it moves on to the next; "1 of 4" says how many steps are left. On a crafting step it has its own **Craft Next** button, or says why it can't craft yet.

- **It follows you.** When you're standing where a later step is done, it shows that step instead: at a vendor that sells something for your queue, the **Buy from vendor** step; at your bank, the bank step; at a mailbox, collecting (or mailing your crafts to your bank alt); at the auction house, the buying step. It says **Here: 3 of 5** meanwhile, and goes back to the first step once that one is done or you walk away.
- The **-** button folds it to a single line that still names the step; **+** opens it again. It remembers which you chose.
- Drag it anywhere; it remembers the place.
- It opens by itself when you queue something and disappears when the queue is empty. `/cff next` folds or unfolds it.
- It hides in combat and in dungeons, raids, battlegrounds and arenas, and comes back when you leave.
- In Farm It mode all gathering (mining, herbs, skinning, drops) is one step, each kind under its own heading, since you gather whatever you come across.

### Price changes

Each material and sale price shows what it was before the latest scan: **was X, now Y**. Red means worse for your profit (a material got dearer or the sale price dropped). Green means better. Nothing is removed from the queue automatically; you decide.

A new comparison starts when you scan the whole shopping list or run a full scan. Searching a single item updates its price but keeps the comparison.

### Usual prices and spikes

Prices jump for a day or two now and then: materials and the item you'd make both get dearer, the add-on shows a fine profit, you craft, and by the time you post the price is back to normal and you sell at a loss. To catch that, the add-on notes each item's lowest price every day you scan, for the last 7 days. Once it has 3 days, the middle of them (the median) is the item's **usual price**.

- A crafted item listed at 400% of its usual price or more counts at the usual price in Profit, Queue and Restock. Below that, today's price counts.
- At 130% of usual or more, its row says so in orange, for example **167% of usual**, with **!** before the profit. The tooltip shows the listed price, the usual price and how far apart they are. Below the profit, **Profit at today's price** shows what it would make if it sells at today's listing.
- Material lines in tooltips add **% of usual** when a material is unusually dear (orange) or cheap (green). Materials always count at what they cost now, since that's what you pay.
- A price that holds is no spike. When the last 3 days you scanned were all 130% or more of the days before (or all well below them), that's the new usual price.
- Your own sales count too. When you sold 3 or more in the last 7 days for more than the usual price, what they fetched (before the AH cut) is the usual price, since that price clearly sells.
- It needs a few days of scans before it shows anything. Days you don't scan simply aren't counted.
- Switch it off with **Count price spikes at the usual price** in Options.

### The shopping list

The add-on keeps one Auctionator shopping list, **Crafting and Farming Forever Queue**, and edits it in place as the queue and your stock change. It holds every material you still need to buy, after your bags, bank, mailbox and (with Syndicator) your alts' bags and banks. What you're going to craft isn't on it.

**Where to find it:** go to an auction house, click the **Shopping** tab at the bottom of the auction house window (Auctionator adds it), then click the list **Crafting and Farming Forever Queue**. The Queue tab and the Next step bar say this under the buying step (hover it for the steps), and a line in chat repeats it when you open the auction house with something to buy.

**What you buy leaves the list at once.** Auction house purchases go to your mailbox, so the add-on counts them as waiting in the mail as soon as the purchase goes through, and once everything is bought the queue tells you to **Collect from your mailbox**. When you open the mailbox, what's really there replaces that count; take the items out and they count as being in your bags.

Guild bank, warband bank, mail on other characters and your own auctions don't count as stock. Quantities aren't capped, because a cap would hide dearer listings you might still want.

## Farm It

**Farm It** at the top of the Queue tab turns the plan into what to gather yourself, and closes the window. The [Next step bar](#next-step-bar) at the top of the screen then shows everything to gather at once, grouped:

- **Mine**, **Pick herbs**, **Skin creatures**, **Fish**: which veins, herbs or creatures, and in which zones.
- **Kill for drops**: which creatures drop it.
- **Disenchant**, and **Other sources** for anything else.

When your character has Mining, Herbalism, Skinning or Fishing, a material it can gather is listed as itself: a skinner is sent to skin Medium Leather, not to skin Light Leather and turn it into Medium Leather. The same goes for ore and herbs. Without that profession, Farm It still lists the lower tier to convert when you know a recipe for it.

Your current zone comes first. Hover a row to see everything known about where the item comes from. Gathering comes first; errands (alts, bank, auction house, mailbox, vendor) after it, then smelting. The bar counts down as you gather and moves on to the errands, smelting and crafting when everything is gathered. While farming, the bar has a **Buy It** button that switches back to buying and reopens the queue; the Queue tab's **Buy It** does the same. The Auctionator list is the same in both modes.

## Restock

Keeps a number of each item you craft listed on the auction house.

- **Columns:** **Sells** (chance to sell within 24 hours), **AH** (how many you have listed), **Have** (held in bags, banks and mail across your characters), **Craft** (crafts Queue restock would add; `5q` in blue means 5 crafts are already on your queue from an earlier restock, `+2` that 2 more are needed on top, a red `-3` that 3 queued crafts aren't needed any more; `skip` when the goal is 0) and **Goal**.
- **Goals:** each profitable item gets one. The defaults are in the boxes at the bottom: **Default goal: stackable** 10 and **single** 1. The **Profit** column shows what one craft earns after the AH cut. Change one item's goal by typing it in the box on its row, or with **+** and **-** (Shift for 10). A goal of 0 skips the item. The **X** at the end of a row skips it only until you `/reload` or log out, keeping its goal; click it again to restock it.
- **Default or your own:** a grey goal follows the defaults, so it changes when you change them. A white goal is one you set for that item, and has an arrow button beside it that puts it back on the default. Setting a goal equal to the default also makes it follow the default again.
- **Min profit (s):** items earning less than this per craft are skipped. The default is 1 silver.
- **Smart goals** (on by default; **Smart restock goals** on the Options tab turns them off): once an item has at least 3 sales or expiries in the last 30 days, its goal moves with them instead of staying at the default. It starts at the default and is worked out again from your history every time, oldest day first. A day when everything you listed sold, with nothing expiring, raises it a step: you probably ran out. A day with expiries lowers it by the share that came back, so a seller that stops selling drops within a day or two. It never rises past what sold between two of your restocks: the add-on notes when you post (long breaks such as overnight count most) and uses one auction's length until a few restocks are on record. Profit matters too: an unsold item only costs its deposit, so an item that earns a lot next to its deposit gets bigger steps up and tolerates a few expiries, while a thin-margin item rises slowly and drops fast. The deposit is learned the first time you post the item; until then a usual profit is assumed. The **Stock level** slider at the bottom of the Restock tab, also on the Options tab (10% to 200%, 50% to start with) goes from cautious to aggressive: at 50% a goal can rise to what sold between two restocks, at 100% to twice that. Drag it and the list updates as you move it: a goal or craft count that goes up flashes green, one that goes down flashes red. On the right of the slider, **Crafting time** is about how long the restock takes to craft: the crafts listed (new ones and the ones already on your queue) plus the sub-crafts their materials need, at each recipe's cast time as learned from your crafting. Shopping and walking aren't counted. It only drops under the default because of expiries, never because you listed little. An expiry is weighed by the deposit it really lost, so a short auction that expires moves the goal less than a long one (for auctions posted before this was recorded, the item's last deposit is used). **Paused:** when the deposits an item's expired auctions lost lately are more than its sales earned (and at least 3 expired), its goal becomes 0, the Craft column says **paused** and the tooltip gives the numbers. Three days after its last result one is stocked again as a try: if it sells, the goal grows as usual; if it expires, the pause returns for twice as long, up to 2 weeks. The Restocking tab doesn't suggest posting a paused item either. A goal of your own overrides a pause. "Sold out" is an estimate: past days only say that everything that came back had sold, not how many you had listed. One item's whole stock never costs more than a quarter of your gold to make, counted down the listings read, so a bigger stock that buys dearer materials costs what it really would; nothing else in the goal looks at your gold. Daggers are stocked in pairs, since buyers usually want one for each hand. A smart goal that differs from the default is blue, and the row's tooltip says what it's based on. A goal you set yourself always wins.
- **Cooldowns** (transmutes and other recipes with a cooldown): a restock asks for one craft at a time, shown as "1/10". While the recipe is on cooldown for the character who crafts it, the Craft column says **cooldown** and the tooltip says when it's ready again. Another recipe for the same item that's ready is used first, and the queue's plan buys a material instead of crafting it while its recipe is on cooldown. Cooldowns are read when the character opens the profession and when they craft the recipe.
- **Not enough gold:** with smart goals on, a restock whose materials cost more than the gold you carry is cut down for you. Items that earn the most profit for their material cost come first; the rest are reduced or left out. Materials you already hold are free, and what you queued by hand is paid for first. The note at the bottom says what a full restock would cost, **Craft** shows what fits out of what's needed (3/8), and the button becomes **Queue partial restock**. It follows your gold, so it grows back as sales come in. **Gold for posting is kept back:** the deposits for listing everything the restock makes, and the units you already hold or have queued, count against your gold along with the materials, so a restock never leaves you with items you can't afford to post. The deposit is what your last post of the item cost; for an item you never posted it's estimated from its vendor price and your auction length. On top of that a restock leaves an amount of gold alone, 1 gold unless you type your own in the **Gold kept** box on the Options tab (as gold, silver and copper, like `1g 50s 20c`; any part alone works, and a bare number is gold): buying materials usually costs more than the last scan said, because only the cheapest listing's price is known, and auctions that expire need a deposit again.
- **Where it stops paying:** the Restock tab picks crafts at each material's cheapest listing, without searching anything, so it's quick. A whole restock buys further down the listings, though (see [What buying many really costs](#what-buying-many-really-costs)). So once the restock is on your queue, the auction house reads every listing of what the queue buys, and the restock is decided again: a restock craft that would earn less than your minimum profit at what its materials really average is cut to the number that still pays, or taken off the queue. Chat says what was cut ("Copper Bracers 10 -> 6"). For an hour after that the Restock tab doesn't offer the cut crafts again: **Craft** shows 0/4, and the tooltip says why. Crafts you queued by hand are never cut.
- **Counted towards the goal:** what's on the auction house (from Syndicator) and what all your characters hold in bags, banks and mail.
- **Queue restock: N item(s)** queues what's missing. Anything you queued by hand is kept and counts towards the goal. It never queues by itself. **Fully stocked** means there's nothing to do.
- **A queued restock is committed.** Once it's on your queue it stays as it is while you shop and craft: spending gold on its materials, or prices moving after you bought, never swaps it for other items, and the Restock tab then says **Restock is on your queue**. If more sells meanwhile, **Add to restock** queues only the extra. If stock came back (expired auctions, a lower goal of your own), **Update restock** takes the crafts you no longer need off the queue. To drop a restock yourself, remove its entries on the Queue tab. New crafts are queued grouped by profession, so one visit to a station does them all.
- The quarter-of-your-gold limit on smart goals only decides what to craft. What you already made is posted by the goal without it.
- **Show Queue** opens the queue beside the Restock tab.

Syndicator only refreshes your auctions while you're at the auction house, so an item that sold since your last visit still counts as listed until you go back.

### Bank alt mode

One character sells everything, the others craft for it. Tick **Bank alt mode** in Options and type the bank alt's full name beside **Bank alt**, both names as you'd write them on a mail (such as `Snic Bank`: the first name alone is shared by all your characters). On every other character:

- **Your crafts get mailed.** Everything a recipe of yours makes that can be sold goes to the bank alt, last on your to-do list: **Take your crafts out of the bank** (the bank step's **Bank it** button takes them out too), then **Mail your crafts to ...**.
- **At a mailbox it sends them by itself**: whole stacks, 12 to a mail, the subject naming what's inside. If the game won't let an add-on send mail on its own, the add-on says so once and from then on waits for the **Send crafts** button, under the mailbox window or on the Next step bar. Ticking Bank alt mode again gives sending by itself another try.
- **What stays:** what your queue still needs (materials of crafts not done yet, a queued writ's or crate's item), tools, campfire kits and camp stations (always, even when you craft them), and soulbound items. Materials your character crafts with itself (bars, bolts, leather) only go as far as the auction house is short of them, by your Restock goals; the rest stays for crafting.
- **Postage**, 30 copper per stack, comes off the profit of crafts made by any character but the bank alt (Profit, Queue and Restock; the tooltip shows it), and joins what the item cost you on the Sales tab once it's sent.
- **Restocking:** a crafter's Restocking tab stops suggesting posts (you can still post by hand). The bank alt's tab suggests everything your goals want listed.
- **Kept apart:** the bank alt's bags and bank aren't used for the crafters' materials, and its gold isn't theirs: send gold over when a crafter needs it.
- **On its way:** crafts you sent count as held for restocking until the bank alt opens its mailbox, so they aren't crafted again in the meantime.

## Restocking (at the auction house)

A **Restocking** tab beside Auctionator's tabs at the bottom of the auction house. It lists items in your bags that one of your recipes makes, with the amount your goals want on the auction house first.

Select an item and it searches the live listings:

- **Quantity** suggested: the goal minus what's already listed, up to what's in your bags and not needed by the queue.
- **Price each** suggested: the same as the lowest listing (no undercutting). With no listings it uses the last scan; with nothing to go on it stays blank.
- It never suggests a price below break-even (material cost after the cut).
- Stackable goods are priced to the copper. Gear and bags only accept whole silver, so their price is rounded down to the silver.
- If a vendor would pay more than the price earns after the cut, it warns you and asks before posting, but leaves the price as you set it.
- **Duration** chooses the auction length.

Each row shows the profit for one item at the last scanned AH price; click it for the profit at the live price. **Post** lists it and moves to the next item below. **Next item** skips. Items posted this visit count as listed straight away, before Syndicator recounts.

## Sales

Your profit from what you craft and sell, with sold and expired auctions per item and each item's chance of selling within 24 hours. Four boxes along the top sum it up: the money on its way, and your profit today, in the last 7 days and in the last 30, with the sales total underneath.

**Profit** is the money you received, after the auction house cut, less what the sold items cost you:

- Materials bought at the auction house count at the price you paid. Materials a vendor sells count at the vendor's price. Materials with no purchase on record (ones you already had, gathered, looted or were given) count at the market price on the day you craft with them: you could have sold them for that.
- The cost follows the materials through every craft, sub-crafts included, to the item you sell. All your characters share one record, since mail moves things between them.
- Profit starts from zero with the version that added this: earlier sales aren't in the boxes or the list, though they still feed the chance to sell and the item tooltips' history. Items crafted before then count at the cost to craft one when they sold (fixed from then on), and their profit is marked **~**.
- **Reset profit** (top right) starts profit again from zero, from now, after asking you to confirm. Sales so far leave the boxes and the list but still feed the chance to sell and the tooltips' history. It can't be undone.
- A sale counts as soon as the buyer is found, while its money is still on its way.
- Deposits lost on expired auctions aren't counted.

**Only your crafts.** The list and the boxes cover the items your characters know a recipe for. Tick **Show everything I sell, not only my crafts** to include spare materials, drops and anything else you auction.

**Money on its way.** The game mails a sale's money an hour after the item sells. When one of your auctions sells while you're online, anywhere in the world, the add-on says so in chat with the amount, lists it at the top of the Sales tab with the time left, and says again when the money has reached your mailbox. The minimap button's tooltip (and a broker bar, if you use one) shows the total on its way and when the next arrives. Opening the mailbox clears what has arrived.

- The amount is the price you posted the item for, less the auction house cut. An amount marked **~** is an estimate: the game only says which item sold, so stackable goods count as one unit, and items posted before this version use the market price. The mail always has the real amount.
- Sales made while that character is offline aren't seen until you open the mailbox, as before.

- Results are read from auction house mail, so they appear when that character opens the mailbox, including sales made while you were offline.
- Time on the auction house comes from your posts.
- The chance uses all history: `1 − exp(−sold ÷ (unit-days listed + 1))` per unit listed. With fewer than 5 units of history it's shown grey with `~`, as a rough guess.
- Items are matched by name, because sold mail doesn't say which item ID it was.

## Writs

Craftsman's Writs are tradable items that start a daily quest: hand in the writ with one crafted item (200 for Crafted Solid Shot) and you get reputation with the Azeroth Commerce Authority or Durotar Supply and Logistics, plus a Coin Pouch. The Writs tab (`/cff writs`) shows what each one costs you.

While this character holds writs (bags or bank), the **Writs** tab turns gold, pulses and shows how many, e.g. **Writs (2)**; hover it to see which ones. Inside, those rows are tinted gold, start with "You have 1:" and come first, even when a filter would hide them.

- **Item wanted**: the item, the writ's level and where it's handed in. A zone with `?` is a guess from the pattern of the other writs; no zone means nobody has reported it yet (the quest marks it on your map). "done today" means this character already handed it in.
- **Writ**: the writ's auction house price. Green when you hold the writ.
- **Item**: the wanted item by the cheapest way. Blue means one of your characters crafts it; white is bought.
- **Net**: the coin pouch less the writ and the item. The pouch is an average players reported (about 12s Journeyman, 36s Expert, 75s Artisan), so the gold is rough.
- **Per rep**: gold lost per reputation point (75 Journeyman, 125 Expert, 200 Artisan). The list starts with the cheapest reputation; click a heading to sort.
- **Filter by zone** (button beside the level buttons): shows only the writs handed in at the zones you tick. The list it opens gives each zone with how many writs it has at the level picked; click zones to tick or untick them, as many as you like (the list stays open; click the button again to close it). **Zone not known** covers the writs whose zone isn't known yet, **All zones** clears the ticks. The button names the zone, or how many are picked.
- **Zone** (heading beside Item wanted): sorts by where the writ is handed in, A to Z, so one zone's writs come together for one trip; within a zone the cheapest reputation comes first. Zones marked ? are guesses; writs with no known zone come last.
- The list starts with only the writs whose item one of your characters can craft. Tick **Show all writs, not only what I can craft** to see every writ. **All / Journeyman / Expert / Artisan** show one level.
- **+** puts the writ on your queue. The Queue tab lists it at the very end under "Writs: hand in when you're there": it isn't a step, so the Next step bar leaves it out and hides once only held writs are left. The queue's shopping list gets the writ and the item it wants, less what you hold; when crafting the item yourself is cheaper, its materials are bought and the craft is planned instead. The writ comes off the queue when you hand it in.

## Crates

Waylaid Crates drop from monsters and sell on the auction house. A labelled crate ("Waylaid Crate: Journeyman Ore") is filled with any one bundle from its list of materials, and the sealed crate is handed to your faction's trade representative for Merchant's Favor and a little coin. Anyone can fill them: no profession is needed. The Crates tab (`/cff crates`) shows which crate gives the cheapest Merchant's Favor. The unlabelled "Waylaid Crate" isn't listed.

While this character holds crates (bags or bank), the **Crates** tab turns gold, pulses and shows how many; hover it to see which ones. Inside, those rows are tinted gold, start with "You have 1:" and come first, whatever level is picked.

- **Crate**: the crate, and its cheapest bundle ("20 Iron Ore"). The row with the cheapest Merchant's Favor says **best buy**, and the bottom line names it.
- **Price**: the crate's auction house price. Green when you hold it.
- **Fill**: what the cheapest bundle costs. Blue means one of your characters crafts it for less than buying. Hover the row to see every bundle with its cost.
- **Favor**: the Merchant's Favor a filled crate pays. Crates of gathered materials pay 5, 10 and 15 (Apprentice, Journeyman, Expert); crates of crafted materials (Fabrics, Ingots, Parts) pay 10, 20 and 30. Artisan crates show `~`: nobody has reported their reward yet, so 20 and 40 follow the pattern.
- **Per Favor**: the crate and its fill, less the coin the hand-in pays, for each Merchant's Favor. The list starts with the cheapest.
- **All / Apprentice / Journeyman / Expert / Artisan** show one level.
- **+** puts one crate on your queue (Shift: five). The Queue tab lists it under "Fill crates" with an amount box, and the queue's shopping list gets the crates and their cheapest bundle, less what you hold; a bundle you already hold in full is used first. A crate comes off the queue when you fill it.

## Options

The **Options** tab sits before Changelog. Right-clicking the minimap button, `/cff options`, and the game's own Options (AddOns, Crafting and Farming Forever) open the same settings. Changes are saved as you make them.

| Option | What it does |
| --- | --- |
| Open with the profession window | The window opens and closes with your profession window |
| Characters | A list of your characters (from Syndicator, plus any you've opened a profession on). Click one to cross it out: the add-on then ignores it completely. Its recipes don't show on Profit or in Recipes, it's never picked to craft, and its bags, bank, mail and auctions count for nothing (queue, shopping list, restocking). **Count every character** clears them all. The character you're playing always counts |
| Show the minimap button | Hides or shows the button on the minimap |
| Craft alert | Off by default. A menu: **Play a sound before crafting stops** plays a sound a few seconds before the game finishes the batch it's crafting, but only when you have more crafts queued after it, so you can be in another window and come back in time to press Craft Next. Pick the **sound** (Raid warning, Ready check, Alarm clock, Queue ready, Whisper, Level up) and the **channel** it plays on (Master, Effects, Music, Ambience, Dialog: each follows its own volume slider in the game's Sound options); clicking one plays it. **Warn** sets how many seconds early (default 3). **Game sound while in another window** is the game's own Sound in Background setting: without it you won't hear anything while alt-tabbed. An orange line says when the channel is muted or at volume 0 |
| Show the Next step bar | Off: no bar; the Queue tab is your list, also when farming |
| Ask to scan at the auction house when prices are old | The Yes or No box offering a new scan. The orange note in the window stays |
| Recipe shopping lists | On: an Auctionator shopping list per profession with the recipes the character you're playing can learn. Off: the lists the add-on made are deleted and not made again |
| Chat messages | A menu with a tick box for each kind of chat line: Reminders (old prices, where the shopping list is), Sales (sold, money in the mailbox), Plan news (the plan checked again, a restock cut), What buttons did (Bank it, Buy for your queue, restock updated, profit reset) and Warnings (refused posts, old prices on a quote, why a button can't do something). Commands you type, like `/cff diag`, always answer |
| Read listings at the auction house | On by default. The add-on looks up every listing of what your queue would buy, so buying many counts at the real cost (see [What buying many really costs](#what-buying-many-really-costs)). The screen is locked for the few seconds it reads. Off: only the items you open yourself are read, and the screen is never locked |
| Plan around bag space | On by default. When the queue's materials won't fit in your bags, says what to bank and splits the queue into runs (see [Bag space](#bag-space)) |
| Flag suspicious sale prices | On by default. A crafted item listed above this % of its material cost (400) says **check price** with `!` before its profit, which still counts the listing (never for recipes with a cooldown). Off: no flag |
| Count price spikes at the usual price | On by default. A crafted item listed above its usual price (the middle of its last 7 days) counts at the usual price, and items at 130% or more say so (see [Usual prices and spikes](#usual-prices-and-spikes)). Off: today's listing is used as it is |
| Smart restock goals | On by default. Restock goals follow your sales (see Restock). Off: every item without its own goal uses the default goals |
| Bank alt mode | Off by default. With a name in the **Bank alt** box beside it, that character sells everything and your others mail it their crafts (see [Bank alt mode](#bank-alt-mode)) |
| Camp batch | 3 by default. Crafts that need a camp station restock to their goal times this once you're under the goal, so one station pays for itself; 1 turns batches off |
| Stock level | How eagerly smart goals stock up, from cautious to aggressive: 10% to 200%, default 50% (a goal can rise to what sold between two of your restocks; 100% allows twice that) |
| Advertise my professions | Off removes the Ad box beside the chat and the Advertise button on the Profit tab |
| Post to | Trade, Guild, Say or Yell, the same choice as the Ad box's picker |
| Advertising message | Your own wording. Write `{profession}` where your profession link should go |
| Quote margin % | Added to the material cost when you press Quote, 0 to 1000 |
| Quote message | Your own wording. `{item}` is the item's link, `{count}` how many you'd make, `{price}` the price for all of them |

Type a message and press Enter to save it; the line under the box shows what will be sent. **Default** puts the add-on's own wording back.

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
| `/cff profit`, `queue`, `restock`, `sales`, `writs`, `crates` | Open that tab, or close the window if that tab is already showing |
| `/cff next` | Fold or unfold the Next step bar |
| `/cff minimap` | Hide or show the minimap button |
| `/cff refresh` | Re-read recipes, stock and prices (the Refresh button) |
| `/cff advertise` | Advertise the selected profession in the chosen channel |
| `/cff clear` | Empty the queue |
| `/cff auto` | Toggle opening with the profession window |
| `/cff options` | Open the Options tab |
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
