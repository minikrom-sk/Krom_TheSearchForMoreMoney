# Krom The Search for More Money (Krom_TheSearchForMoreMoney)

WoW addon for **WoW Forever** (Blizzard's Classic+; modern client, modern
C_AuctionHouse) that also loads on Classic Era. Built for Krom and a 3-4 person
crew. Auction House price history with graphs, a Deals scanner, and crew sync.

## The person
- Former military, Director in film/TV/games. Not a programmer: keep answers short,
  plain-English, dry humour welcome. He tests in game and sends screenshots.
- He installs/updates via **WowUp** ("Install from URL" with the GitHub repo URL,
  Forever client selected). Crew does the same.

## Shipping (how every change goes out)
1. Edit code, run the offline tests (below).
2. Bump `VERSION` (semver, e.g. 0.6.0 -> 0.6.1) and push to `main`.
3. `.github/workflows/release.yml` tags `vX` and runs `package.yml`
   (BigWigsMods/packager@v2) -> GitHub release with zip + release.json for WowUp.
   Pushing tags directly from a Claude session is blocked (403) - that's why the
   workflow tags. Check with `gh api repos/minikrom-sk/Krom_TheSearchForMoreMoney/releases/tags/vX`
   (gh GraphQL is blocked; use REST).
4. Commit as: `git -c user.name="minikrom-sk" -c user.email="minikrom-sk@users.noreply.github.com" commit ...`
- `.pkgmeta`: package-as Krom_TheSearchForMoreMoney; ignores README.md, VERSION, CLAUDE.md, tools.

## Naming
- Display "Krom The Search for More Money"; folders/files/zips/repos `Krom_TheSearchForMoreMoney`.
- Slash: `/money` (alias `/moremoney`). Chat prefix "More Money:". Comm prefix `KromMoreMoney`.
- TOCs: `.toc`, `_Vanilla.toc` (Interface 11509), `_Camelot.toc` (Interface 16001 = Forever).
  Load order: Libs (LibStub, CallbackHandler, LibDataBroker, LibDBIcon, AceComm-3.0 + ChatThrottleLib,
  LibDeflate), Core, Graph, Deals, TooltipGraph, Sync, Import, Options.

## Files
- **Core.lua** - settings (`ns.opt`), time helpers (`ns.today()` = floor(GetServerTime/86400),
  `ns.dayLabel` "Oct 13", local-time quarter slots `ns.slotNow()`), storage, AH event handlers
  (modern browse/commodity/item search/ReplicateItems full scan; classic list + getAll),
  `ns.marketValue` (TSM-style), `ns.lastScan` (full-scan listings, session only),
  neutral AH detection, `ns.startFullScan`.
- **Graph.lua** - the panel (docks right of the AH, top-aligned, AH height + 130, 620 wide; ranges 1/3/7/14/30/90/All), the view/tab system
  (`ns.addView`, `ns.showView`), price graph view, `ns.makeScanButton`, tooltip line.
- **Deals.lua** - "Under vendor price" tab: listings below vendor sell price from the last full
  scan, category filters, click = open on AH, right-click = graph, throttled Recheck sweep.
- **Sync.lua** - whitelist-only crew sync over WHISPER via AceComm + LibDeflate.
- **Import.lua** - one-time import of Auctionator history (CBOR string per realm, own decoder).
- **TooltipGraph.lua** - mini 7-day graph hanging off item tooltips (market line, vendor line, volume, "Nx vendor" verdict); options tipGraph + tipGraphPos (auto/below/above/right/left).
- **Options.lua** - Blizzard options panel, minimap button (LibDBIcon), slash commands.

## Data (SavedVariables `Krom_TheSearchForMoreMoneyDB`, account-wide)
`realms[realmKey]` where realmKey = `GetRealmName().."-"..(faction or "Neutral")`:
- `items[itemID][day]` = lowest single listing seen that day (faint dots; fallback line).
- `market[itemID][day]` = lowest market value that day (the graph line).
- `slots[itemID][slot]` = market value per local quarter-day (6h), kept 30 days (time-of-day chart).
- `vol[itemID][day]` = most units seen listed that day (volume bars).
- `weekly[itemID][week]` (+ `weeklyN`) = average price per Monday-Sunday week, rolled up from days
  as they pass `keepDays` (90) and kept forever (the "All" range). week = floor((day+3)/7).
- Daily data pruned after `keepDays` (90). Also: `whitelist`, `houseOverride[npcID]`, `range`, `view`, `minimap`, options.

Market value: cheapest 15% of quantity, extend to 30% while each step <= +20%, drop >1.5 sd
outliers, quantity-weighted mean. Lowest-wins everywhere, so merges/sync are order-free.

## Behaviour notes / decisions
- Neutral (goblin) auctioneers have no faction -> separate "Neutral" bucket; `/money house
  neutral|faction|auto` overrides per auctioneer.
- Crew sync: whitelist only, both online, skipped in combat/instances, hello with per-day
  fingerprints for last 30 days, then D (lowest) / M (market) day messages. Neutral data shares
  across factions. Offline "No player named" spam is filtered for crew names.
- Auctionator import: use `Auctionator.State.CurrentRealm` (Forever files "Classic Beta PvE 2"
  under "PvE"). Its days count from 2020-01-01. Only imports lowest + volume (no ladders).
- Full scan = once per 15 min (game limit). Recheck = one search at a time, only when
  `C_AuctionHouse.IsThrottledMessageSystemReady()`, 0.4s gap, max 40, user-clicked. Never
  automate buying (needs a hardware click anyway). Stay within Blizzard's rules.

## Testing offline
Needs Lua 5.1 (`apt install lua5.1` or any 5.1 binary). From repo root:
- `lua5.1 tools/sim.lua .` - multi-client sync, neutral AH, graph all ranges, market value, Deals, Recheck.
- `AUC=PvE lua5.1 tools/import_test.lua . "Classic Beta PvE 2" PvE <path>/Auctionator.lua`
- Syntax: `for f in *.lua; do lua5.1 -e "assert(loadfile('$f'))"; done`
The fake frames don't model parenting/layout - layout bugs only show in game, so ask for a screenshot.

## User's WoW install (when the desktop link is available)
`F:\World of Warcraft\_classic_beta_\` - SavedVariables in
`WTF\Account\1331739#1\SavedVariables\`, addons in `Interface\AddOns\`. Read-only; never edit his files.

## Ideas parked for later
- Sync time-of-day slots and volume to the crew.
- More Deals views: "below market value" (30%+ under), shopping/watch list.
- Guild/party trust for sync (whitelist only for now).
