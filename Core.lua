-- Krom The Search for More Money - core: settings, storage, and recording prices from the AH.
--
-- Prices are stored per realm+faction, per item, per day, as the LOWEST
-- per-unit buyout seen that day:
--   Krom_TheSearchForMoreMoneyDB.realms[realmKey].items[itemID][day] = copper
-- "day" = whole days since 1970 in server time, so the whole crew buckets alike.
--
-- Prices you see live are also kept per quarter of YOUR day (night 0-6,
-- morning 6-12, afternoon 12-18, evening 18-24), for 30 days:
--   ...realms[realmKey].slots[itemID][slot] = copper
-- "slot" = 6-hour blocks since 1970 in your local time.
--
-- Volume (how many are listed) per item per day, the most seen that day:
--   ...realms[realmKey].vol[itemID][day] = count That's what the
-- time-of-day chart and the finer graph points are made from.
--
-- Works with both Auction House systems: the modern one (C_AuctionHouse) and
-- the classic one (QueryAuctionItems). Anything that searches the AH - you,
-- Auctionator, a full scan - gets recorded.

local ADDON, ns = ...

ns.PREFIX = "|cff33ccffMore Money:|r "
function ns.say(msg) print(ns.PREFIX .. msg) end
local say = ns.say

function ns.opt(key, default)
  local db = Krom_TheSearchForMoreMoneyDB
  if not db or db[key] == nil then return default end
  return db[key]
end
local opt = ns.opt

-- ---------------------------------------------------------------------------
-- Time, realm, money
-- ---------------------------------------------------------------------------
function ns.now() return (GetServerTime and GetServerTime()) or time() end
function ns.today() return math.floor(ns.now() / 86400) end
-- Seconds your clock is ahead of UTC (for local time-of-day slots).
local function tzOffset()
  local t = time()
  local l, u = date("*t", t), date("!*t", t)
  u.isdst = l.isdst
  return time(l) - time(u)
end
ns.tzOffset = tzOffset
function ns.slotNow() return math.floor((ns.now() + tzOffset()) / 21600) end
-- A slot's middle as a fractional (UTC) day, for placing it on the graph.
function ns.slotDay(slot) return (slot * 21600 + 10800 - tzOffset()) / 86400 end
ns.QUARTERS = { [0] = "Night", "Morning", "Afternoon", "Evening" }

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
ns.WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
-- "Oct 13"
function ns.dayLabel(day)
  local d = date("!*t", day * 86400)
  return MONTHS[d.month] .. " " .. d.day
end
-- 1 = Sunday ... 7 = Saturday
function ns.weekday(day) return date("!*t", day * 86400).wday end

-- Which auction house prices belong to. Your faction's AH and the neutral
-- (goblin) AHs are separate markets, so they're stored separately:
--   "Realm-Alliance" / "Realm-Horde" / "Realm-Neutral"
-- ns.house is "neutral" only while a neutral AH is open.
ns.house = "faction"
function ns.realmKey(house)
  house = house or ns.house
  local side = house == "neutral" and "Neutral" or (UnitFactionGroup("player") or "?")
  return (GetRealmName() or "?") .. "-" .. side
end
function ns.allKeys() return { ns.realmKey("faction"), ns.realmKey("neutral") } end

-- Decide which AH we're standing at, from the auctioneer we're talking to.
-- Goblin (neutral) auctioneers have no faction. A per-auctioneer override
-- (/money house neutral|faction) wins, for any odd one the game mislabels.
local function npcID()
  local guid = UnitGUID and UnitGUID("npc")
  return guid and tonumber((select(6, strsplit("-", guid))))
end
function ns.detectHouse()
  local id = npcID()
  local over = id and Krom_TheSearchForMoreMoneyDB.houseOverride[id]
  if over then return over, id, true end
  local f = UnitFactionGroup and UnitFactionGroup("npc")
  return (f == "Alliance" or f == "Horde") and "faction" or "neutral", id, false
end
function ns.setHouseOverride(house)
  local id = npcID()
  if not id then return false end
  Krom_TheSearchForMoreMoneyDB.houseOverride[id] = house -- nil = automatic
  ns.house = ns.detectHouse()
  return true
end

function ns.money(copper)
  copper = math.floor((copper or 0) + 0.5)
  if GetCoinTextureString then
    local ok, s = pcall(GetCoinTextureString, copper)
    if ok and s then return s end
  end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return ("%dg %02ds"):format(g, s) end
  if s > 0 then return ("%ds %02dc"):format(s, c) end
  return ("%dc"):format(c)
end

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
function ns.realmData(key)
  local db = Krom_TheSearchForMoreMoneyDB
  key = key or ns.realmKey()
  db.realms[key] = db.realms[key] or { items = {} }
  return db.realms[key]
end

ns.listeners = {} -- called with (itemID) when new data lands; graph/tooltips listen
local function notify(itemID)
  for _, fn in ipairs(ns.listeners) do pcall(fn, itemID) end
end

-- Record one observation. Returns true if it lowered/added the day's price.
function ns.record(itemID, unitPrice, day, key)
  itemID, unitPrice = tonumber(itemID), tonumber(unitPrice)
  if not itemID or not unitPrice or unitPrice <= 0 then return false end
  unitPrice = math.floor(unitPrice + 0.5)
  local live = day == nil
  day = day or ns.today()
  local realm = ns.realmData(key)
  if live then
    -- seen right now: also file it under this quarter of the day
    realm.slots = realm.slots or {}
    local s = realm.slots[itemID]
    if not s then s = {}; realm.slots[itemID] = s end
    local slot = ns.slotNow()
    if not s[slot] or unitPrice < s[slot] then s[slot] = unitPrice end
  end
  local items = realm.items
  local hist = items[itemID]
  if not hist then hist = {}; items[itemID] = hist end
  local old = hist[day]
  if old and old <= unitPrice then return false end
  hist[day] = unitPrice
  return true
end

-- History for an item as a sorted list of { day, price }, optionally since a day.
function ns.history(itemID, sinceDay, key)
  local hist = ns.realmData(key).items[itemID]
  local out = {}
  if not hist then return out end
  for day, price in pairs(hist) do
    if not sinceDay or day >= sinceDay then out[#out + 1] = { day, price } end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- How many were up for sale. Keeps the day's highest count (a full scan sees
-- everything; a single search can see less).
function ns.recordVolume(itemID, qty, day, key)
  itemID, qty = tonumber(itemID), tonumber(qty)
  if not itemID or not qty or qty <= 0 then return end
  day = day or ns.today()
  local realm = ns.realmData(key)
  realm.vol = realm.vol or {}
  local v = realm.vol[itemID]
  if not v then v = {}; realm.vol[itemID] = v end
  if not v[day] or qty > v[day] then v[day] = math.floor(qty) end
end
function ns.volume(itemID, day, key)
  local realm = ns.realmData(key)
  local v = realm.vol and realm.vol[itemID]
  return v and v[day]
end

-- Time-of-day points for an item: sorted list of { slot, price } since a day.
function ns.slotHistory(itemID, sinceDay, key)
  local realm = ns.realmData(key)
  local s = realm.slots and realm.slots[itemID]
  local out = {}
  if not s then return out end
  for slot, price in pairs(s) do
    if not sinceDay or ns.slotDay(slot) >= sinceDay then out[#out + 1] = { slot, price } end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- Quick stats for tooltips: latest price + its day, average over N days.
function ns.stats(itemID, days)
  local h = ns.history(itemID, ns.today() - (days or 7) + 1)
  local all = ns.history(itemID)
  local latest = all[#all]
  if not latest then return nil end
  local sum = 0
  for _, p in ipairs(h) do sum = sum + p[2] end
  return { price = latest[2], day = latest[1], avg = #h > 0 and sum / #h or nil, points = #h }
end

function ns.prune()
  local cutoff = ns.today() - opt("keepDays", 90)
  local removed = 0
  for _, realm in pairs(Krom_TheSearchForMoreMoneyDB.realms) do
    for itemID, hist in pairs(realm.items) do
      for day in pairs(hist) do
        if day < cutoff then hist[day] = nil; removed = removed + 1 end
      end
      if next(hist) == nil then realm.items[itemID] = nil end
    end
    for itemID, v in pairs(realm.vol or {}) do
      for day in pairs(v) do if day < cutoff then v[day] = nil end end
      if next(v) == nil then realm.vol[itemID] = nil end
    end
    local slotCutoff = ns.slotNow() - opt("keepSlotDays", 30) * 4
    for itemID, s in pairs(realm.slots or {}) do
      for slot in pairs(s) do
        if slot < slotCutoff then s[slot] = nil end
      end
      if next(s) == nil then realm.slots[itemID] = nil end
    end
  end
  return removed
end

function ns.countItems(key)
  local n, points = 0, 0
  for _, hist in pairs(ns.realmData(key).items) do
    n = n + 1
    for _ in pairs(hist) do points = points + 1 end
  end
  return n, points
end

-- ---------------------------------------------------------------------------
-- Auction House: which system is this client using?
-- ---------------------------------------------------------------------------
local function modernAH() return C_AuctionHouse ~= nil and C_AuctionHouse.GetBrowseResults ~= nil end
ns.modernAH = modernAH

function ns.ahFrame()
  return (AuctionHouseFrame and AuctionHouseFrame) or AuctionFrame
end

local recorded = 0
local function batchDone(label)
  if recorded > 0 then
    if label then say(("%s: recorded %d prices."):format(label, recorded)) end
    if ns.onNewData then ns.onNewData() end
  end
  recorded = 0
end

-- Modern AH: browse results, commodity and item searches.
local function onBrowse()
  local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
  if not ok or not results then return end
  local any
  for _, r in ipairs(results) do
    if r.itemKey and r.minPrice and ns.record(r.itemKey.itemID, r.minPrice) then
      recorded = recorded + 1; any = r.itemKey.itemID
    end
    if r.itemKey and r.totalQuantity then ns.recordVolume(r.itemKey.itemID, r.totalQuantity) end
  end
  if any then notify(any) end
  batchDone()
end

local function onCommodity(itemID)
  if not itemID then return end
  local ok, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
  if ok and info and info.unitPrice and ns.record(itemID, info.unitPrice) then
    recorded = recorded + 1
  end
  if C_AuctionHouse.GetCommoditySearchResultsQuantity then
    local okq, q = pcall(C_AuctionHouse.GetCommoditySearchResultsQuantity, itemID)
    if okq then ns.recordVolume(itemID, q) end
  end
  ns.focus(itemID, "search")
  notify(itemID)
  batchDone()
end

local function onItemSearch(itemKey)
  if type(itemKey) ~= "table" then return end
  local n = C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetNumItemSearchResults(itemKey) or 1
  local best, qty = nil, 0
  for i = 1, n or 1 do
    local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
    if ok and info then qty = qty + (info.quantity or 1) end
    if i <= 50 and ok and info and info.buyoutAmount and info.buyoutAmount > 0 then
      local unit = info.buyoutAmount / math.max(1, info.quantity or 1)
      if not best or unit < best then best = unit end
    end
  end
  if best and ns.record(itemKey.itemID, best) then recorded = recorded + 1 end
  ns.recordVolume(itemKey.itemID, qty)
  ns.focus(itemKey.itemID, "search")
  notify(itemKey.itemID)
  batchDone()
end

-- Classic AH: the "list" page (normal searches, and full "getAll" scans).
local fullScan = { active = false }
ns.fullScan = fullScan

local function processClassicList(isFull)
  local n = GetNumAuctionItems and GetNumAuctionItems("list") or 0
  if n == 0 then return end
  local i, counts = 1, {}
  local function slice()
    local stop = math.min(n, i + 499)
    for j = i, stop do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", j)
      if itemID then counts[itemID] = (counts[itemID] or 0) + (count or 1) end
      if itemID and buyout and buyout > 0 and ns.record(itemID, buyout / math.max(1, count or 1)) then
        recorded = recorded + 1
      end
    end
    i = stop + 1
    if i <= n then C_Timer.After(0, slice) else
      -- only a full scan sees everything; one search page would undercount
      if isFull then for id, q in pairs(counts) do ns.recordVolume(id, q) end end
      batchDone(isFull and "Full scan" or nil)
    end
  end
  slice()
end

local function onClassicList()
  if fullScan.active and fullScan.kind == "classic" then
    fullScan.active = false
    processClassicList(true)
  else
    processClassicList(false)
  end
end

-- Modern full scan: ReplicateItems, then read the replicate list in slices.
local function processReplicate()
  local n = C_AuctionHouse.GetNumReplicateItems() or 0
  local i, counts = 0, {}
  local function slice()
    local stop = math.min(n - 1, i + 499)
    for j = i, stop do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(j)
      if itemID then counts[itemID] = (counts[itemID] or 0) + (count or 1) end
      if itemID and buyout and buyout > 0 and ns.record(itemID, buyout / math.max(1, count or 1)) then
        recorded = recorded + 1
      end
    end
    i = stop + 1
    if i < n then C_Timer.After(0, slice) else
      for id, q in pairs(counts) do ns.recordVolume(id, q) end
      batchDone("Full scan")
    end
  end
  if n > 0 then slice() end
end

local function onReplicate()
  -- Auctionator's own full scans land here too, so we record whoever started it.
  -- The event can fire more than once per scan; handle each scan once.
  local t = GetTime()
  if fullScan.lastReplicate and t - fullScan.lastReplicate < 60 then return end
  fullScan.lastReplicate = t
  fullScan.active = false
  C_Timer.After(1, processReplicate) -- give the client a moment to finish filling the list
end

-- Start a full scan (the AH only allows one every 15 minutes).
function ns.startFullScan()
  if not (ns.ahFrame() and ns.ahFrame():IsShown()) then say("open the Auction House first."); return false end
  if modernAH() and C_AuctionHouse.ReplicateItems then
    fullScan.active, fullScan.kind, fullScan.lastReplicate = true, "modern", nil
    C_AuctionHouse.ReplicateItems()
    say("full scan started - this can take a moment.")
    return true
  elseif QueryAuctionItems then
    local _, canAll = CanSendAuctionQuery()
    if not canAll then say("the Auction House only allows a full scan every 15 minutes."); return false end
    fullScan.active, fullScan.kind = true, "classic"
    QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
    say("full scan started - the game may freeze for a few seconds while it loads.")
    return true
  else
    say("couldn't find a way to scan the Auction House on this client.")
    return false
  end
end

-- ---------------------------------------------------------------------------
-- Focus item: the item the graph shows (last searched, or hovered with the AH open)
-- ---------------------------------------------------------------------------
ns.focusID = nil
function ns.focus(itemID, why)
  itemID = tonumber(itemID)
  if not itemID then return end
  if ns.focusLocked and why ~= "manual" then return end
  ns.focusID = itemID
  if ns.onFocus then ns.onFocus(itemID) end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.events = ev
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE",
                     "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                     "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
                     "REPLICATE_ITEM_LIST_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    Krom_TheSearchForMoreMoneyDB = Krom_TheSearchForMoreMoneyDB or {}
    local db = Krom_TheSearchForMoreMoneyDB
    db.realms = db.realms or {}
    db.whitelist = db.whitelist or {}
    db.minimap = db.minimap or {}
    db.houseOverride = db.houseOverride or {}
  elseif event == "PLAYER_LOGIN" then
    ns.prune()
    for _, fn in ipairs(ns.onLogin or {}) do pcall(fn) end
  elseif event == "AUCTION_HOUSE_SHOW" then
    local house, id = ns.detectHouse()
    ns.house = house
    if house == "neutral" and not ns.toldNeutral then
      ns.toldNeutral = true
      say(("neutral auction house (%s) - its prices are kept separate from your faction's. Wrong? /money house faction"):format(UnitName("npc") or "auctioneer"))
    end
    -- Picking a row in the modern AH's browse list: graph that item.
    if AuctionHouseFrame and AuctionHouseFrame.SelectBrowseResult and not ns.hookedSelect then
      ns.hookedSelect = true
      hooksecurefunc(AuctionHouseFrame, "SelectBrowseResult", function(_, r)
        if type(r) == "table" and r.itemKey then ns.focus(r.itemKey.itemID, "search") end
      end)
    end
    if ns.onAHShow then ns.onAHShow() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ns.house = "faction"
    if ns.onAHHide then ns.onAHHide() end
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    onClassicList()
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    onBrowse()
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    onCommodity(arg1)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    onItemSearch(arg1)
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    onReplicate()
  end
end)
