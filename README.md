# Crafting and Farming Forever

A crafting add-on for **World of Warcraft: Forever**. It shows what's worth crafting, keeps one craft queue for all your characters, works out what you still need to buy or gather, and helps you keep the auction house stocked.

- **Profit:** every recipe any of your characters knows, ranked by profit at current Auctionator prices, with a search box and a tab per profession.
- **Cheapest path:** each material is costed as the cheapest of the auction house, a vendor, or crafting it yourself. Materials you already hold count as free.
- **Queue:** one queue shared by all your characters, with total profit, what's still to buy, what to take from the bank, and a **Craft Next** button.
- **Live shopping list:** one Auctionator list, `Crafting and Farming Forever Queue`, holding only what you still need after your bags, bank and (with Syndicator) your alts' bags and banks. It's edited in place as things change.
- **Farm It:** turns the queue into a gathering list: which vein or herb, which zones, which creatures, what to disenchant. It stays on screen and counts down as you gather.
- **Restock:** a goal per item for how many you want on the auction house. One button queues the difference.
- **Restocking at the auction house:** a tab beside Auctionator's that lists what you can post from your bags, suggests a price just under the lowest listing, and posts it.
- **Sales:** what sold and what expired, read from your auction house mail, with each item's chance of selling within 24 hours.
- **Advertise and quote:** post a profession link to Trade, Guild, Say or Yell in one click, and reply to a whisper with a price for the whole order, at a margin you set.

## Requirements

| Add-on | |
| --- | --- |
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | Required. Prices and the shopping list. |
| [Syndicator](https://www.curseforge.com/wow/addons/syndicator) | Optional. Alts' bags and banks, and what's on the auction house. The Restock tab needs it. |

## Installation

1. Copy the `CraftingAndFarmingForever` folder into `World of Warcraft/_forever_/Interface/AddOns/`. Only the `.toc` and `.lua` files are needed.
2. Restart the game client. A newly added add-on isn't picked up by `/reload`.
3. Log in to each character with a profession and open that profession once, so its recipes are recorded.

Upgrading from **CraftLedger**, the add-on's old name? With the game closed, run `tools/migrate-name.sh` to carry your saved data over and remove the old folder. See [the user guide](docs/USER_GUIDE.md#upgrading-from-craftledger).

## Quick start

1. Open a profession. The window opens beside it on the **Profit** tab.
2. If prices are more than a day old, it asks for a new auction house scan. Say yes when you're at the auction house.
3. Pick something profitable and press **+** on its row (Shift for 10), or **Queue** under the favourite star on the recipe page, which queues the amount in the craft-count box.
4. At the auction house, open Auctionator's Shopping tab and search the `Crafting and Farming Forever Queue` list. It only holds what you still need.
5. Back at the profession window, press **Craft Next** until the queue is empty.
6. At the auction house, open the **Restocking** tab and post what you made.

## Commands

| Command | What it does |
| --- | --- |
| `/cff` or `/craftfarm` | Show or hide the window |
| `/cff profit`, `queue`, `restock`, `sales` | Open that tab, or close the window if that tab is already showing |
| `/cff refresh` | Re-read recipes, stock and prices (the Refresh button) |
| `/cff advertise` | Advertise the selected profession in the chosen channel |
| `/cff clear` | Empty the queue |
| `/cff auto` | Toggle opening with the profession window |
| `/cff diag` | Print diagnostics and save them for troubleshooting |

## Documentation

- [User guide](docs/USER_GUIDE.md): every tab and button, how prices and stock are worked out, and troubleshooting.
- [Development](docs/DEVELOPMENT.md): code layout, tests, deployment, regenerating the source data, and releases.

## Credits

- Where materials come from (Farm It) is generated from [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) data, under its MIT License. The notice is in `Sources.lua`.
- Vendor reagent seed prices come from CraftProfit by Vystery (MIT).
- Prices and the shopping list come from Auctionator through its public API. No Auctionator code is included.

## License

Not chosen yet. Until one is, all rights are reserved by the author.
