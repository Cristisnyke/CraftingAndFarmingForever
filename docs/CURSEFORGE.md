# Crafting and Farming Forever

**Know what's worth crafting, buy only what you're missing, gather the rest, and keep the auction house stocked, across all your characters.**

Crafting and Farming Forever is a profession add-on for **World of Warcraft: Forever**. It ranks every recipe your characters know by real profit at current auction house prices. It keeps one craft queue for all of them, and turns that queue into a shopping list that leaves out everything you already own. Anything you'd rather gather becomes a farming list.

## Features

### Profit list

- Every recipe any of your characters knows, ranked by profit after the auction house cut.
- Each material is costed the cheapest way: auction house, vendor, or crafting it yourself.
- Materials you already hold count as free, so ore in your bank means it smelts bars instead of buying them.
- A tab per profession and a search box.
- Bind-on-pickup crafts are listed with their crafting cost, so you can still plan them.

### One queue for every character

- Queue from the profit list, or with the **Queue** button on any recipe page.
- Sub-crafts like bars, bolts and leather are worked out for you, and shrink as your stock grows.
- **Total profit** for the whole queue, and **Still to buy** compared with the gold you're carrying.
- **Craft Next** crafts the next thing this character can make. If it can't, it tells you why (the next craft is on your alt, or you need to open a profession).
- After each scan, prices show what they were before: **was 1s 20c, now 1s 45c**, red when it hurts your profit and green when it helps.

### A shopping list that knows what you own

- One Auctionator shopping list, kept up to date as you craft, loot and buy.
- It counts your bags and bank, and with Syndicator your alts' bags and banks too, so you never buy what's already sitting on an alt.
- Vendor materials are listed separately, so you don't search the auction house for thread.

### Farm It

- One click turns the queue into what to gather yourself: which veins, herbs and creatures, in which zones, and what to disenchant.
- A small list you can leave on screen while you farm. It puts your current zone first and counts down as you gather.

### Restock the auction house

- A goal for each item you sell: how many you want listed. Your auctions, bags, banks and mail count towards it.
- One button queues whatever is missing.
- A **Restocking** tab inside the auction house lists what you can post from your bags. It checks the live price, suggests just under the lowest listing, never below break-even, and posts with one click.
- It warns you before you post below what a vendor would pay.

### Sales history

- What sold and what expired today, this week, this month and all time, read from your auction house mail, including sales made while you were offline.
- Each item's chance of selling within 24 hours, which gets more accurate the more you sell.

### Advertise and quote

- A small **Ad** box beside the chat posts your profession link to Trade, Guild, Say or Yell in one click.
- **Quote** fills in a reply to your last whisper with one price for the whole order: material cost plus a margin you choose, from 0% up to 1000%.

### Stale-price warning

- If your auction house prices are more than a day old, it asks for a new scan.

## Requirements

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**: required.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)**: optional. Needed for alts' stock and for Restock goals.

## Getting started

1. Install the add-on along with Auctionator, and restart the game.
2. Open each profession once on each character so its recipes are recorded.
3. Run an auction house scan when it asks.
4. Queue something profitable, then search the **Crafting and Farming Forever Queue** list in Auctionator's Shopping tab.

## Commands

- `/cff` or `/craftfarm`: show or hide the window
- `/cff profit`, `/cff queue`, `/cff restock`, `/cff sales`: open a tab
- `/cff refresh`: re-read recipes, stock and prices
- `/cff clear`: empty the queue
- `/cff auto`: toggle opening with the profession window
- `/cff diag`: diagnostics for bug reports

## Bugs and suggestions

Please report bugs in the comments, with the output of `/cff diag` and any Lua error text. The add-on is actively developed, and suggestions are welcome.

## Credits

- **Auctionator** by plusmouse and Borjamacare: prices, price history and the shopping list.
- **Syndicator** by plusmouse: stock across your characters.
- **AllTheThings** by Crieve and the AllTheThings team: where materials come from, used under the MIT License.

*World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. This add-on isn't affiliated with or endorsed by Blizzard Entertainment.*
