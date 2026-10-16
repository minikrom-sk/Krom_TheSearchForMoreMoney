-- Krom The Search for More Money - one-time import of Auctionator's price history.
--
-- Auctionator keeps its prices in its own saved variable,
-- AUCTIONATOR_PRICE_DATABASE, which is readable while Auctionator is loaded.
-- Layout (per realm):  [realm][itemKey] = { m = latest, h = {[day]=high}, l = {[day]=low}, ... }
-- Auctionator counts days from its own start date, so days are converted to ours.
-- The importer checks the shape first and refuses to guess if it looks different.

local ADDON, ns = ...
local say = ns.say

local function auctionatorDayZero()
  if Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0 then
    return Auctionator.Constants.SCAN_DAY_0
  end
  return time({ year = 2020, month = 1, day = 1, hour = 0 })
end

-- Which realm table(s) in Auctionator's database belong to this realm.
local function realmTables(db)
  local realm = (GetRealmName() or ""):lower()
  local faction = (UnitFactionGroup("player") or ""):lower()
  local exact, loose = {}, {}
  for key, t in pairs(db) do
    if type(key) == "string" and type(t) == "table" then
      local k = key:lower()
      if k == realm or k == realm .. " " .. faction or k == realm .. "_" .. faction or k == realm .. "-" .. faction then
        exact[#exact + 1] = { key, t }
      elseif k:find(realm, 1, true) then
        loose[#loose + 1] = { key, t }
      end
    end
  end
  return #exact > 0 and exact or loose
end

local function itemIDFromKey(key)
  if type(key) == "number" then return key end
  if type(key) == "string" then
    -- keys look like "12345" or "g:12345:..." / "12345:0:0..." depending on version
    return tonumber(key) or tonumber(key:match("^(%d+)")) or tonumber(key:match("^%a+:(%d+)"))
  end
end

function ns.importAuctionator(dryRun)
  local db = AUCTIONATOR_PRICE_DATABASE
  if type(db) ~= "table" then
    say("Auctionator's price data isn't loaded - is Auctionator enabled?")
    return
  end
  local realms = realmTables(db)
  if #realms == 0 then
    local keys = {}
    for k in pairs(db) do keys[#keys + 1] = tostring(k) end
    say("couldn't find this realm in Auctionator's data. Realms in it: " .. table.concat(keys, ", "))
    return
  end

  local dayZero = auctionatorDayZero()
  local offset = math.floor(dayZero / 86400) -- Auctionator day N -> our day N + offset
  local keepFrom = ns.today() - ns.opt("keepDays", 90)
  local items, prices, odd, sample = 0, 0, 0, nil

  for _, rt in ipairs(realms) do
    for key, entry in pairs(rt[2]) do
      local itemID = itemIDFromKey(key)
      if itemID and type(entry) == "table" then
        local lows = type(entry.l) == "table" and entry.l or (type(entry.h) == "table" and entry.h) or nil
        local got = false
        if lows then
          for aDay, price in pairs(lows) do
            local d = tonumber(aDay)
            if d and type(price) == "number" then
              -- Auctionator days are small numbers (days since 2020). Anything
              -- already huge is treated as a day count since 1970.
              local ourDay = (d < 10000) and (d + offset) or d
              if ourDay >= keepFrom and ourDay <= ns.today() then
                if not dryRun then ns.record(itemID, price, ourDay) end
                prices = prices + 1
                got = true
              end
            end
          end
        elseif type(entry.m) == "number" then
          -- no history, just a latest price: record it for today
          if not dryRun then ns.record(itemID, entry.m) end
          prices, got = prices + 1, true
        else
          odd = odd + 1
          sample = sample or key
        end
        if got then items = items + 1 end
      end
    end
  end

  if items == 0 then
    say("found Auctionator's data for this realm but couldn't read any prices from it - nothing was imported.")
    if sample then say("first unreadable entry: " .. tostring(sample) .. " (please screenshot this for Krom)") end
    return
  end
  if dryRun then
    say(("would import %d prices for %d items."):format(prices, items))
  else
    say(("imported %d prices for %d items from Auctionator (last %d days)."):format(prices, items, ns.opt("keepDays", 90)))
    Krom_TheSearchForMoreMoneyDB.importedAuctionator = ns.now()
    if ns.onNewData then ns.onNewData() end
  end
  if odd > 0 then say(("skipped %d entries in a format I don't recognise."):format(odd)) end
end
