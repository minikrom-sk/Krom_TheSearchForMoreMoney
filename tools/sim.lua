-- Offline simulation of the addon: two/three clients whispering (crew sync, neutral AH,
-- whitelist), graph redraws for every range, market value math, Deals + Recheck.
-- Run with Lua 5.1 from the repo root:  lua5.1 tools/sim.lua .
local DIR = arg[1]
local network = {}
local DAY = 20500

local function noop() end
local function newFrame()
  local f = { shown = false, scripts = {} }
  return setmetatable(f, { __index = function(t, k)
    if k == "SetScript" then return function(self, e, fn) rawget(self, "scripts")[e] = fn end end
    if k == "GetScript" then return function(self, e) return rawget(self, "scripts")[e] end end
    if k == "Show" then return function(self) rawset(self, "shown", true) end end
    if k == "Hide" then return function(self) rawset(self, "shown", false) end end
    if k == "IsShown" then return function(self) return rawget(self, "shown") end end
    if k == "SetShown" then return function(self, v) rawset(self, "shown", v and true or false) end end
    if k == "CreateFontString" or k == "CreateTexture" or k == "CreateLine" then return function() return newFrame() end end
    if k == "GetStringHeight" or k == "GetWidth" or k == "GetHeight" or k == "GetFrameLevel" then return function() return 100 end end
    if k == "RegisterEvent" then return function(self, e) rawget(self, "events")[e] = true end end
    return noop
  end, __newindex = rawset })
end

local function newClient(name, faction)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.print = function(s) print("[" .. name .. "] " .. tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  env.frames = {}
  env.CreateFrame = function() local f = newFrame(); rawset(f, "events", {}); table.insert(env.frames, f); return f end
  env.UIParent = newFrame()
  env.GameTooltip = newFrame()
  env.C_Timer = { After = function(_, fn) fn() end, NewTicker = noop }
  env.GetServerTime = function() return DAY * 86400 + 3600 end
  env.time = function(t) if t then return os.time(t) end return DAY * 86400 end
  env.GetTime = function() return os.clock() * 1000 end
  env.GetRealmName = function() return "Testrealm" end
  env.npcFaction = "Alliance"
  env.UnitFactionGroup = function(u) if u == "npc" then return env.npcFaction end return faction or "Alliance" end
  env.UnitGUID = function(u) return "Creature-0-1-2-3-" .. (env.npcFaction and 1000 or 2000) .. "-0" end
  env.strsplit = function(sep, s) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do t[#t+1] = p end return unpack(t) end
  env.UnitName = function() return name end
  env.InCombatLockdown = function() return false end
  env.IsInInstance = function() return false, "none" end
  env.GetItemInfo = function(id) return "Item" .. id, "|Hitem:" .. id .. "|h", 1, 1, 1, "", "", 1, "", 134400, 50, 7 end
  env.GetItemClassInfo = function(c) return "Trade Goods" end
  env.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } }
  env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  env.ChatFrame_AddMessageEventFilter = noop
  env.SlashCmdList = {}
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.date = os.date
  -- LibStub + real LibDeflate, fake AceComm that delivers over our "network"
  local function load(path)
    local chunk = assert(loadfile(DIR .. "/" .. path))
    setfenv(chunk, env)
    return chunk
  end
  load("Libs/LibStub/LibStub.lua")()
  load("Libs/LibDeflate/LibDeflate.lua")()
  local AceComm = env.LibStub:NewLibrary("AceComm-3.0", 1)
  function AceComm:Embed(t)
    t.RegisterComm = function(_, prefix, fn) network[name] = { prefix = prefix, fn = fn } end
    t.SendCommMessage = function(_, prefix, msg, dist, target)
      network.sent = (network.sent or 0) + 1
      local peer = network[target]
      if peer and peer.prefix == prefix then
        table.insert(network.queue, function() peer.fn(prefix, msg, dist, name) end)
      end
    end
  end
  local ns = {}
  for _, f in ipairs({ "Core.lua", "Graph.lua", "Deals.lua", "Sync.lua", "Import.lua", "Options.lua" }) do
    load(f)("Krom_TheSearchForMoreMoney", ns)
  end
  -- fire ADDON_LOADED + PLAYER_LOGIN on the event frame
  local ev = ns.events
  ev.scripts.OnEvent(ev, "ADDON_LOADED", "Krom_TheSearchForMoreMoney")
  ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
  return env, ns
end

network.queue = {}
local function pump() while #network.queue > 0 do table.remove(network.queue, 1)() end end

local A_env, A = newClient("Krom")
local B_env, B = newClient("Bob")

-- A saw items 1,2 today and yesterday; B saw item 2 cheaper today and item 3.
A.record(1, 500, DAY); A.record(2, 900, DAY); A.record(1, 450, DAY - 1)
B.record(2, 700, DAY); B.record(3, 300, DAY); B.record(3, 350, DAY - 2)

A.addFriend("Bob"); B.addFriend("Krom")
A.syncNow(false)
pump()

local function dump(label, ns)
  local items = ns.realmData().items
  local out = {}
  for id, h in pairs(items) do
    local days = {}
    for d, p in pairs(h) do days[#days + 1] = (d - DAY) .. "=" .. p end
    table.sort(days)
    out[#out + 1] = id .. ":{" .. table.concat(days, ",") .. "}"
  end
  table.sort(out)
  print(label, table.concat(out, "  "))
  return table.concat(out, "|")
end
local a, b = dump("A:", A), dump("B:", B)
print("converged:", a == b, "messages sent:", network.sent)

-- stranger ignored
network["Mallory"] = nil
local before = dump("B before stranger:", B)
local M_env, M = newClient("Mallory")
M.record(1, 1, DAY); M.addFriend("Bob"); M.syncNow(true); pump()
print("stranger ignored:", dump("B after stranger:", B) == before)


-- neutral AH: Krom (Alliance) and Hordie (Horde) both shop at the goblin
local H_env, H = newClient("Hordie", "Horde")
network.queue = {}
local function ah(env, ns, neutral)
  env.npcFaction = (not neutral) and (ns.realmKey("faction"):match("Horde") and "Horde" or "Alliance") or nil
  ns.events.scripts.OnEvent(ns.events, "AUCTION_HOUSE_SHOW")
end
ah(A_env, A, true); A.record(50, 111, DAY); A.events.scripts.OnEvent(A.events, "AUCTION_HOUSE_CLOSED")
ah(H_env, H, true); H.record(51, 222, DAY); H.events.scripts.OnEvent(H.events, "AUCTION_HOUSE_CLOSED")
ah(H_env, H, false); H.record(52, 333, DAY); H.events.scripts.OnEvent(H.events, "AUCTION_HOUSE_CLOSED")
print("A neutral key:", A.realmKey("neutral"), "A faction item50?", A.realmData(A.realmKey("faction")).items[50] ~= nil)
A.addFriend("Hordie"); H.addFriend("Krom"); A.syncNow(true); pump()
local an = A.realmData(A.realmKey("neutral")).items
local hn = H.realmData(H.realmKey("neutral")).items
print("neutral shared both ways:", an[51] ~= nil and hn[50] ~= nil)
print("horde faction data stayed out of A:", A.realmData(A.realmKey("faction")).items[52] == nil and an[52] == nil)
-- override
ah(A_env, A, true); A.setHouseOverride("faction"); print("override ->", A.house); A.setHouseOverride(nil); print("auto ->", A.house); A.events.scripts.OnEvent(A.events, "AUCTION_HOUSE_CLOSED")

-- graph + tooltip smoke test
A.record(1, 480); A.record(1, 470); A.focusID = 1
A.panel:Show()
local ok, err = pcall(A.redraw)
print("graph redraw ok:", ok, err)
print("stats item 2:", A.stats(2, 7).price)
print("slots item1:", #A.slotHistory(1, DAY-7))
for _, r in ipairs({7,14,30,90}) do Krom_TheSearchForMoreMoneyDB = nil end
local rd = A.realmData()
local base = A.slotNow()
rd.slots = rd.slots or {}; rd.slots[1] = rd.slots[1] or {}
for i = 0, 40 do rd.slots[1][base - i] = 400 + (i % 4) * 20 end
for d = 0, 60 do A.recordVolume(1, 100 + d * 10, DAY - d); A.record(1, 500 + (d % 7) * 15, DAY - d) end
print("pattern dow:", (function() local e={} for _,p in ipairs(A.history(1)) do e[#e+1]={math.floor((p[1]+3)/7),(A.weekday(p[1])+5)%7+1,p[2]} end local pc,u=A.pattern(e,7) local o={} for i=1,7 do o[#o+1]=string.format("%.1f",pc[i] or 0) end return table.concat(o," ").." weeks="..u end)())
for _, r in ipairs({7,14,30,90}) do
  A_env.Krom_TheSearchForMoreMoneyDB.range = r
  local ok, err = pcall(A.redraw); print("range", r, ok, err)
end
-- market value
local function mv(l) return A.marketValue(l) end
print("linen:", mv({{5,1},{20,1916},{21,2049},{22,1082},{23,901},{24,2181},{30,303},{1020,7}}))
print("thin (5,20,20):", mv({{5,1},{20,2}}))
print("single:", mv({{77,1}}))
print("gear 3 listings:", mv({{5000,1},{5200,1},{9000,1}}))
print("two big stacks:", mv({{10,200},{11,200},{50,5}}))
A.recordLadder(900, {{5,1},{20,1916},{21,2049}})
print("item900 raw/market:", A.realmData().items[900][DAY], A.realmData().market[900][DAY])
-- market syncs to Hordie? (different faction -> no). sync A<->B instead
network.queue = {}
B.syncNow(true); pump()
print("B got market 900:", B.realmData().market and B.realmData().market[900] and B.realmData().market[900][DAY])
A.focusID = 900; A_env.Krom_TheSearchForMoreMoneyDB.range = 7
print("redraw 900:", pcall(A.redraw))
A.setLastScan({ [2589] = {{3,12},{20,1900}}, [700] = {{60,5}}, [701] = {{10,2},{49,1}} })
local deals, pending = A.computeDeals()
for _, d in ipairs(deals) do print("deal", d.id, d.qty, d.price, d.vendor, d.profit) end
A.showView("deals"); print("deals view ok", pcall(A.showView, "deals"))
print("graph view ok", pcall(A.showView, "graph"))

-- recheck simulation
local sent = {}
A_env.Enum = { AuctionHouseSortOrder = { Price = 0 } }
A_env.AuctionHouseFrame = A_env.CreateFrame(); A_env.AuctionHouseFrame:Show()
local ready = true
A_env.C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return ready end,
  MakeItemKey = function(id) return { itemID = id } end,
  SendSearchQuery = function(key) table.insert(sent, key.itemID) end,
  GetNumCommoditySearchResults = function() return 0 end,
  GetCommoditySearchResultInfo = function() return nil end,
  GetBrowseResults = function() return {} end,
}
A.setLastScan({ [2589] = {{3,12},{20,1900}}, [701] = {{10,2},{49,1}} })
A.showView("deals")
-- find runner frame: last-created frames with OnUpdate
local runner
for _, f in ipairs(A_env.frames) do if f.scripts.OnUpdate and not f.scripts.OnClick then runner = f end end
local t = 0
A_env.GetTime = function() return t end
-- press recheck: find the button whose OnEnter mentions Recheck - simpler: call through frames with OnClick + text
for _, f in ipairs(A_env.frames) do
  if f.scripts.OnClick and f.scripts.OnEnter and not f.scripts.OnUpdate then
    -- try clicking each candidate until rechecking starts
    if not A.rechecking then pcall(f.scripts.OnClick, f) end
  end
end
print("rechecking started:", A.rechecking)
for step = 1, 40 do
  t = t + 0.25
  runner.scripts.OnUpdate(runner, 0.25)
  -- answer the search immediately: commodity with zero results => gone
  if #sent > 0 and sent.answered ~= #sent then
    sent.answered = #sent
    A.events.scripts.OnEvent(A.events, "COMMODITY_SEARCH_RESULTS_UPDATED", sent[#sent])
  end
end
print("searches sent:", table.concat(sent, ","), "rechecking now:", A.rechecking)
local deals = A.computeDeals()
print("deals left after recheck:", #deals)
-- weekly rollup + all-time range
local rd2 = A.realmData()
for d = 100, 200 do A.record(77, 1000 + d, DAY - d); A.recordMarket(77, 900 + d, DAY - d) end
A.prune()
local wk = rd2.weekly[77]; local nweeks = 0 for _ in pairs(wk) do nweeks = nweeks + 1 end
print("weekly weeks kept:", nweeks, "daily left:", (function() local n=0 for _ in pairs(rd2.items[77] or {}) do n=n+1 end return n end)())
A.record(77, 1500, DAY); A.focusID = 77
for _, r in ipairs({0, 1, 3}) do A_env.Krom_TheSearchForMoreMoneyDB.range = r; print("range", r, pcall(A.redraw)) end
local h = A.history(77); print("history points:", #h, "first weekly:", h[1][4], h[1][2])
