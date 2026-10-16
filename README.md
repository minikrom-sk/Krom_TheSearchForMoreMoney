# Krom The Search for More Money

*"Merchandising! Merchandising! Where the real money from the movie is made!"*

Auction House price history with graphs, shared with your crew.

- **Records prices automatically:** every Auction House search (yours or Auctionator's)
  stores each item's lowest price for the day. Full scans record everything at once.
- **Price graph** beside the Auction House: 7 / 14 / 30 / 90 days, hover a point for the
  date and price, lock it on one item. Also opens on its own with `/money`.
- **Tooltip line** on every item: latest price and 7-day average.
- **Crew sync:** add your friends' character names and the addon quietly swaps price data
  whenever two of you are online. Only names on your list are messaged or listened to.
  Share and receive can each be switched off.
- **Auctionator import:** pull in the price history Auctionator already collected.
- Works with both the modern and classic Auction House.

## Install (WowUp)

**Get Addons -> Install from URL**, paste this repo's link, install, restart the game.

## Commands

- `/money` toggle the price graph, `/money <item link>` graph a specific item
- `/money scan` full Auction House scan (AH open; allowed every 15 minutes)
- `/money add Name`, `/money remove Name`, `/money crew` manage your crew
- `/money sync` sync now, `/money import` import from Auctionator, `/money options`

Uses LibStub, CallbackHandler, LibDataBroker, LibDBIcon, AceComm-3.0 and LibDeflate (see `Libs/`).
