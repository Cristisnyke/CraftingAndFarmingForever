# Crafting and Farming Forever

**Know what's worth crafting, buy only what you're missing, gather the rest, and keep the auction house stocked, across all your characters.**

Crafting and Farming Forever is a profession add-on for **World of Warcraft: Forever**. It ranks every recipe your characters know by real profit at current auction house prices. It keeps one craft queue for all of them, and turns that queue into a shopping list that leaves out everything you already own. Anything you'd rather gather becomes a farming list.

> **Needs [Auctionator](https://www.curseforge.com/wow/addons/auctionator) and [Syndicator](https://www.curseforge.com/wow/addons/syndicator).** Crafting and Farming Forever won't work properly without both. Install them first.
>
> **Coming soon:** TradeSkillMaster (TSM) support.

## Features

### Profit list

- Every recipe any of your characters knows, ranked by profit after the auction house cut.
- Each material is costed the cheapest way: auction house, vendor, or crafting it yourself.
- Materials you already hold count as free, so ore in your bank means it smelts bars instead of buying them.
- A tab per profession, a search box, and sorting by name, sell chance or profit.
- Hide unprofitable recipes with one tick.
- **Skill up** mode for levelling: the cheapest recipes per skill point, coloured orange, yellow and green as in the game, with each colour's chance of a point.
- Bind-on-pickup crafts are listed with their crafting cost, so you can still plan them.

### One queue for every character

- Queue from the profit list, or with the **Queue** button on any recipe page.
- Sub-crafts like bars, bolts and leather are worked out for you, and shrink as your stock grows.
- **Total profit** for the whole queue, and **Still to buy** compared with the gold you're carrying.
- **Next step bar**: while anything is queued, a small bar at the top of the screen shows the next thing to do, with its own Craft Next when it's time to craft. Fold it to one line; it disappears when the queue is empty.
- **Craft Next** crafts the next thing this character can make. If it can't, it tells you why (the next craft is on your alt, say), and if the craft needs a different profession it opens that one for you. It's also a progress bar: while you craft it shows how far through the batch you are (8 / 20) and how long until that batch and all your crafts are done.
- After each scan, prices show what they were before: **was 1s 20c, now 1s 45c**, red when it hurts your profit and green when it helps.

### A shopping list that knows what you own

- One Auctionator shopping list, kept up to date as you craft, loot and buy. Find it in the auction house's **Shopping** tab (Auctionator), list **Crafting and Farming Forever Queue**.
- What you buy leaves the list the moment the purchase goes through, and the queue reminds you to collect it from your mailbox.
- It counts your bags and bank, and with Syndicator your alts' bags and banks too, so you never buy what's already sitting on an alt.
- Vendor materials are listed separately, so you don't search the auction house for thread.

### Farm It

- One click turns the queue into what to gather yourself: which veins, herbs and creatures, in which zones, and what to disenchant.
- The Next step bar at the top of the screen tells you everything to gather and where, grouped by mining, herbs, skinning and so on. It puts your current zone first and counts down as you gather.
- Where each material comes from is built from **[AllTheThings](https://www.curseforge.com/wow/addons/all-the-things)** data and ships with the add-on, so you don't need AllTheThings installed.

### Restock the auction house

- A goal for each item you sell: how many you want listed. Your auctions, bags, banks and mail count towards it.
- Clear columns for what's listed, what you hold and what to craft. Goals you set yourself stand out from the defaults, and one click puts them back.
- One button queues whatever is missing.
- A **Restocking** tab inside the auction house lists what you can post from your bags. It checks the live price, suggests the lowest listing's price (no undercutting), never below break-even, and posts with one click.
- It warns you before you post below what a vendor would pay.

### Sales history
- Money on its way: when an auction sells, you're told in chat how much is coming, and the Sales tab and the minimap button count down the hour until it reaches your mailbox. No trip to the auction house needed.

- Real profit, not just sales: what you received after the auction house cut, less what the materials cost. Bought materials count at the price you paid, ones you already had or gathered at the market price on the day you used them. Today, the last 7 days and the last 30, and per item.
- Lists only what you craft, or everything you sell with one tick.
- What sold and what expired today, this week, this month and all time, read from your auction house mail, including sales made while you were offline.
- Each item's chance of selling within 24 hours, which gets more accurate the more you sell.

### Advertise and quote

- A small **Ad** box beside the chat posts your profession link to Trade, Guild, Say or Yell in one click.
- **Quote** fills in a reply to your last whisper with one price for the whole order: material cost plus a margin you choose, from 0% up to 1000%.
- Word both messages your way, or turn advertising off, on the Options tab.

### Options

- One tab to switch things on or off: the suspicious-price limit, the minimap button, the Next step bar, the scan question and the chat reminders. Also opens with a right-click on the minimap button, and from the game's Options under AddOns.

### Suspicious prices

- A crafted item listed far above its material cost (over 400% by default) counts at 200% and is marked "check price", so one odd listing can't fake a big profit. Both limits are in Options.

### Stale-price warning

- If your auction house prices are more than a day old, it asks for a new scan.
- A Changelog tab lists what changed in each version. It lights up after an update; nothing pops up.

## Requirements

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**: required. All prices and the shopping list come from it; without it the add-on doesn't load.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)**: required to work properly. It counts your alts' bags and banks and what you have on the auction house. Without it only the logged-in character counts, so the add-on may tell you to buy what an alt already has, and the Restock tab is off. You'll get a reminder in chat at each login until it's installed.

TradeSkillMaster (TSM) support is coming in a future update.

## Getting started

1. Install the add-on along with Auctionator and Syndicator, and restart the game.
2. Open each profession once on each character so its recipes are recorded.
3. Run an auction house scan when it asks.
4. Queue something profitable, then search the **Crafting and Farming Forever Queue** list in Auctionator's Shopping tab.

## Commands

- `/cff` or `/craftfarm`: show or hide the window
- `/cff profit`, `/cff queue`, `/cff restock`, `/cff sales`, `/cff options`: open a tab
- `/cff next`: fold or unfold the Next step bar
- `/cff minimap`: hide or show the minimap button
- `/cff refresh`: re-read recipes, stock and prices
- `/cff clear`: empty the queue
- `/cff changelog`: open the Changelog tab
- `/cff auto`: toggle opening with the profession window
- `/cff diag`: diagnostics for bug reports

## Bugs and suggestions

Please report bugs in the comments, with the output of `/cff diag` and any Lua error text. The add-on is actively developed, and suggestions are welcome.

## Credits

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** by plusmouse and Borjamacare: prices, price history and the shopping list.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)** by plusmouse: stock across your characters.
- **[AllTheThings](https://github.com/ATTWoWAddon/AllTheThings)** by Crieve and the AllTheThings team: Farm It's data on where materials come from, used under the MIT License.

## License

All Rights Reserved. You're welcome to use the add-on and read its code, but please don't re-upload it or copy it into other projects without permission.

*World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. This add-on isn't affiliated with or endorsed by Blizzard Entertainment.*
