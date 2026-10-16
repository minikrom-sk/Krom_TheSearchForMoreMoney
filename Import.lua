-- Krom The Search for More Money - one-time import of Auctionator's price history.
--
-- Auctionator keeps its prices in AUCTIONATOR_PRICE_DATABASE, readable while
-- Auctionator is loaded. Since its database version 8 each realm is one
-- CBOR-encoded string; decoded it is
--   [itemKey] = { m = latest, l = {[day]=low}, h = {[day]=high}, a = {[day]=qty} }
-- Older versions stored the same thing as plain tables; both are handled.
-- Auctionator counts days from 2020-01-01, so days are converted to ours.

local ADDON, ns = ...
local say = ns.say

local byte, sub = string.byte, string.sub
local function cborDecode(s)
  local pos = 1
  local item
  local function uint(info)
    if info < 24 then return info end
    local n = info == 24 and 1 or info == 25 and 2 or info == 26 and 4 or info == 27 and 8 or error("bad length")
    local v = 0
    for i = 0, n - 1 do v = v * 256 + byte(s, pos + i) end
    pos = pos + n
    return v
  end
  function item()
    local ib = byte(s, pos); if not ib then error("truncated") end
    pos = pos + 1
    local major, info = math.floor(ib / 32), ib % 32
    if major == 0 then return uint(info)
    elseif major == 1 then return -1 - uint(info)
    elseif major == 2 or major == 3 then
      local n = uint(info); local v = sub(s, pos, pos + n - 1); pos = pos + n; return v
    elseif major == 4 then
      local n, t = uint(info), {}
      for i = 1, n do t[i] = item() end
      return t
    elseif major == 5 then
      local n, t = uint(info), {}
      for _ = 1, n do local k = item(); t[k] = item() end
      return t
    elseif major == 6 then uint(info); return item()
    else
      if info == 20 then return false elseif info == 21 then return true
      elseif info == 22 or info == 23 then return nil
      elseif info == 25 then -- half float
        local h = byte(s,pos)*256+byte(s,pos+1); pos=pos+2
        local e, m = math.floor(h/1024)%32, h%1024
        local v = e==0 and m*2^-24 or e==31 and math.huge or (1024+m)*2^(e-25)
        return h >= 32768 and -v or v
      elseif info == 26 or info == 27 then
        local n = info == 26 and 4 or 8
        local b = {byte(s, pos, pos+n-1)}; pos = pos + n
        local sign = b[1] >= 128 and -1 or 1
        if n == 4 then
          local e = (b[1]%128)*2 + math.floor(b[2]/128)
          local m = ((b[2]%128)*256 + b[3])*256 + b[4]
          if e == 0 then return sign*m*2^-149 end
          return sign*(1 + m/2^23)*2^(e-127)
        else
          local e = (b[1]%128)*16 + math.floor(b[2]/16)
          local m = b[2]%16
          for i=3,8 do m = m*256 + b[i] end
          if e == 0 then return sign*m*2^-1074 end
          return sign*(1 + m/2^52)*2^(e-1023)
        end
      end
      error("unsupported simple " .. info)
    end
  end
  local v = item()
  return v, pos
end

-- Realm data: a table (old Auctionator) or a CBOR string (new). Prefer the
-- game's own decoder when the client has one, fall back to ours.
local function realmTable(v)
  if type(v) == "table" then return v end
  if type(v) ~= "string" then return nil end
  if C_EncodingUtil and C_EncodingUtil.DeserializeCBOR then
    local ok, t = pcall(C_EncodingUtil.DeserializeCBOR, v)
    if ok and type(t) == "table" then return t end
  end
  local ok, t = pcall(cborDecode, v)
  if ok and type(t) == "table" then return t end
end

local function auctionatorDayZero()
  if Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0 then
    return Auctionator.Constants.SCAN_DAY_0
  end
  return time({ year = 2020, month = 1, day = 1, hour = 0 })
end

-- Which realm table(s) in Auctionator's database belong to this realm.
-- Auctionator files prices under its own name for your connected realms
-- (Auctionator.State.CurrentRealm), which on Forever isn't your realm's name.
-- Fallback when that isn't available: connected realms, then the realm name.
local function norm(s) return (tostring(s or ""):lower():gsub("[%s%-']", "")) end
local function realmTables(db)
  -- Best answer: ask Auctionator which realm it's using right now.
  local current = Auctionator and Auctionator.State and Auctionator.State.CurrentRealm
  if current and db[current] then return { { current, db[current] } } end
  local wanted = {}
  local connected = GetAutoCompleteRealms and GetAutoCompleteRealms() or {}
  if type(connected) == "table" then for _, r in ipairs(connected) do wanted[#wanted + 1] = norm(r) end end
  wanted[#wanted + 1] = norm(GetRealmName())
  local faction = norm(UnitFactionGroup("player"))
  for _, want in ipairs(wanted) do
    for key, t in pairs(db) do
      if type(key) == "string" and key:sub(1, 2) ~= "__" and (type(t) == "table" or type(t) == "string") then
        local k = norm(key)
        if k == want or k == want .. faction or k == want .. "_" .. faction then
          return { { key, t } }
        end
      end
    end
  end
  return {}
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
    for k in pairs(db) do if tostring(k):sub(1, 2) ~= "__" then keys[#keys + 1] = tostring(k) end end
    say("couldn't find this realm in Auctionator's data. Realms in it: " .. table.concat(keys, ", "))
    return
  end

  local dayZero = auctionatorDayZero()
  local offset = math.floor((dayZero + 43200) / 86400) -- Auctionator day N -> our day N + offset (rounded: SCAN_DAY_0 is local midnight)
  local keepFrom = ns.today() - ns.opt("keepDays", 90)
  local items, prices, odd, sample = 0, 0, 0, nil

  local unreadable = 0
  for _, rt in ipairs(realms) do
    local data = realmTable(rt[2])
    if not data then unreadable = unreadable + 1 end
    for key, entry in pairs(data or {}) do
      local itemID = itemIDFromKey(key)
      if itemID and type(entry) == "table" then
        -- per day: the lower of Auctionator's day-low and day-high
        local byDay = {}
        for _, f in ipairs({ "l", "h" }) do
          if type(entry[f]) == "table" then
            for aDay, price in pairs(entry[f]) do
              local d, p = tonumber(aDay), tonumber(price)
              if d and p and p > 0 and (not byDay[d] or p < byDay[d]) then byDay[d] = p end
            end
          end
        end
        local got = false
        if next(byDay) then
          for d, price in pairs(byDay) do
            -- Auctionator days are small numbers (days since 2020). Anything
            -- already huge is treated as a day count since 1970.
            local ourDay = (d < 10000) and (d + offset) or d
            if ourDay >= keepFrom and ourDay <= ns.today() then
              if not dryRun then ns.record(itemID, price, ourDay, ns.realmKey("faction")) end
              prices = prices + 1
              got = true
            end
          end
        elseif type(entry.m) == "number" then
          -- no history, just a latest price: record it for today
          if not dryRun then ns.record(itemID, entry.m, nil, ns.realmKey("faction")) end
          prices, got = prices + 1, true
        else
          odd = odd + 1
          sample = sample or key
        end
        if got then items = items + 1 end
      end
    end
  end

  if items == 0 and unreadable > 0 then
    say("found Auctionator's data for this realm but couldn't decode it - nothing was imported.")
    return
  end
  if items == 0 then
    say("found Auctionator's data for this realm but couldn't read any prices from it - nothing was imported.")
    if sample then say("first unreadable entry: " .. tostring(sample) .. " (please screenshot this for Krom)") end
    return
  end
  if dryRun then
    say(("would import %d prices for %d items."):format(prices, items))
  else
    say(("imported %d prices for %d items from Auctionator's \"%s\" data (last %d days)."):format(prices, items, realms[1][1], ns.opt("keepDays", 90)))
    Krom_TheSearchForMoreMoneyDB.importedAuctionator = ns.now()
    if ns.onNewData then ns.onNewData() end
  end
  if odd > 0 then say(("skipped %d entries in a format I don't recognise."):format(odd)) end
end
