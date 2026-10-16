-- Krom The Search for More Money - crew sync over hidden addon messages.
--
-- Only names on your whitelist are ever messaged or listened to.
-- Protocol (all compressed with LibDeflate, chunked/throttled by AceComm):
--   H|v1|realmKey|reply|day:count:hash,...   "hello" with a fingerprint per day
--   D|realmKey|day|itemID:price,itemID:price  all of a day's prices
-- On a hello, we send every day whose fingerprint differs from ours, and
-- reply with our own hello (once) so the other side sends theirs. Both sides
-- keep the lowest price per item per day, so everyone ends up with the same
-- data. People sync whenever two of them are online at the same time.

local ADDON, ns = ...
local opt, say = ns.opt, ns.say

local PREFIX = "KromMoreMoney"
local SYNC_DAYS = 30 -- only the last 30 days are compared/sent
local AceComm = LibStub and LibStub("AceComm-3.0", true)
local Deflate = LibStub and LibStub("LibDeflate", true)
local comm = {}
if AceComm then AceComm:Embed(comm) end

-- ---------------------------------------------------------------------------
-- Whitelist helpers
-- ---------------------------------------------------------------------------
local function short(name) return ((name or ""):match("^([^%-]+)") or ""):lower() end

local function myRealmTag() return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("%s", "") end

function ns.isWhitelisted(sender)
  if not sender then return false end
  local s = sender:lower()
  local sShort = short(sender)
  for _, n in ipairs(Krom_TheSearchForMoreMoneyDB.whitelist) do
    local l = n:lower()
    if l == s or (not l:find("-", 1, true) and l == sShort) then return true end
  end
  return false
end

function ns.addFriend(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return false end
  name = name:sub(1, 1):upper() .. name:sub(2)
  for _, n in ipairs(Krom_TheSearchForMoreMoneyDB.whitelist) do
    if n:lower() == name:lower() then return false end
  end
  table.insert(Krom_TheSearchForMoreMoneyDB.whitelist, name)
  table.sort(Krom_TheSearchForMoreMoneyDB.whitelist)
  return true
end

function ns.removeFriend(name)
  for i, n in ipairs(Krom_TheSearchForMoreMoneyDB.whitelist) do
    if n:lower() == (name or ""):lower() then table.remove(Krom_TheSearchForMoreMoneyDB.whitelist, i); return true end
  end
  return false
end

-- Whispering someone who's offline prints "No player named X is currently
-- playing." Hide that message for names on our list.
local function hideOfflineSpam(_, _, msg)
  if not ERR_CHAT_PLAYER_NOT_FOUND_S or type(msg) ~= "string" then return false end
  local pattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("%%s", "(.-)"):gsub("%.", "%%.") .. "$"
  local who = msg:match(pattern)
  if who and ns.isWhitelisted(who) then return true end
  return false
end
local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if AddFilter then AddFilter("CHAT_MSG_SYSTEM", hideOfflineSpam) end

-- ---------------------------------------------------------------------------
-- Encoding
-- ---------------------------------------------------------------------------
local function encode(str)
  if not Deflate then return str end
  return Deflate:EncodeForWoWAddonChannel(Deflate:CompressDeflate(str))
end
local function decode(str)
  if not Deflate then return str end
  local raw = Deflate:DecodeForWoWAddonChannel(str)
  return raw and Deflate:DecompressDeflate(raw)
end

-- Fingerprint of one day's prices: count + order-independent checksum.
local function dayDigest(items, day)
  local count, hash = 0, 0
  for itemID, hist in pairs(items) do
    local p = hist[day]
    if p then
      count = count + 1
      hash = (hash + (itemID * 7919 + p) % 2147483647) % 2147483647
    end
  end
  return count, hash
end

local function digests()
  local items = ns.realmData().items
  local today, out = ns.today(), {}
  for day = today - SYNC_DAYS + 1, today do
    local c, h = dayDigest(items, day)
    if c > 0 then out[day] = { c, h } end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
local stats = { sent = 0, got = 0 }
ns.syncStats = stats

local function canSync()
  if not AceComm or not opt("share", true) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  local inInstance, kind = IsInInstance()
  if inInstance and (kind == "raid" or kind == "party" or kind == "pvp" or kind == "arena") then return false end
  return true
end

local function send(target, payload)
  comm:SendCommMessage(PREFIX, encode(payload), "WHISPER", target, "BULK")
end

local function sendHello(target, isReply)
  local parts = {}
  for day, d in pairs(digests()) do parts[#parts + 1] = ("%d:%d:%d"):format(day, d[1], d[2]) end
  send(target, ("H|1|%s|%d|%s"):format(ns.realmKey(), isReply and 1 or 0, table.concat(parts, ",")))
end

local function sendDay(target, day)
  local items = ns.realmData().items
  local parts = {}
  for itemID, hist in pairs(items) do
    if hist[day] then parts[#parts + 1] = itemID .. ":" .. hist[day] end
  end
  if #parts == 0 then return end
  send(target, ("D|%s|%d|%s"):format(ns.realmKey(), day, table.concat(parts, ",")))
  stats.sent = stats.sent + #parts
end

-- Say hello to everyone on the list (offline ones just don't answer).
function ns.syncNow(quiet)
  if not canSync() then
    if not quiet then say("sync is off, or you're in combat / an instance.") end
    return
  end
  local me = UnitName("player")
  local n = 0
  for _, name in ipairs(Krom_TheSearchForMoreMoneyDB.whitelist) do
    if short(name) ~= short(me) then sendHello(name, false); n = n + 1 end
  end
  if not quiet then say(n > 0 and ("asking %d crew member(s) for new prices..."):format(n) or "your crew list is empty - add names in Options or with /money add Name.") end
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
local replied = {} -- sender -> time we last replied with our own hello

local function onHello(sender, realm, isReply, list)
  if realm ~= ns.realmKey() then return end -- different realm/faction AH: not comparable
  local theirs = {}
  for day, c, h in list:gmatch("(%d+):(%d+):(%d+)") do theirs[tonumber(day)] = { tonumber(c), tonumber(h) } end
  local mine = digests()
  if opt("share", true) then
    for day, d in pairs(mine) do
      local t = theirs[day]
      if not t or t[1] ~= d[1] or t[2] ~= d[2] then sendDay(sender, day) end
    end
  end
  -- Ask them for theirs by replying with our hello (at most once a minute each).
  if not isReply then
    local now = GetTime()
    if not replied[sender] or now - replied[sender] > 60 then
      replied[sender] = now
      if opt("share", true) then sendHello(sender, true) end
    end
  end
end

local function onDay(sender, realm, day, list)
  if realm ~= ns.realmKey() or not opt("receive", true) then return end
  day = tonumber(day)
  if not day or day < ns.today() - opt("keepDays", 90) then return end
  local changed = 0
  for itemID, price in list:gmatch("(%d+):(%d+)") do
    if ns.record(itemID, price, day) then changed = changed + 1 end
  end
  stats.got = stats.got + changed
  if changed > 0 then
    if opt("syncMessages", false) then say(("got %d new prices from %s."):format(changed, short(sender))) end
    if ns.onNewData then ns.onNewData() end
  end
end

local function onComm(prefix, message, channel, sender)
  if prefix ~= PREFIX or not ns.isWhitelisted(sender) then return end
  local ok, data = pcall(decode, message)
  if not ok or type(data) ~= "string" then return end
  local kind = data:sub(1, 1)
  if kind == "H" then
    local _, ver, realm, reply, list = data:match("^(H)|(%d+)|([^|]*)|(%d)|(.*)$")
    if ver then onHello(sender, realm, reply == "1", list) end
  elseif kind == "D" then
    local realm, day, list = data:match("^D|([^|]*)|(%d+)|(.*)$")
    if realm then onDay(sender, realm, day, list) end
  end
end

if AceComm then comm:RegisterComm(PREFIX, onComm) end

-- Sync shortly after login, then every 15 minutes, and after a full scan.
ns.onLogin = ns.onLogin or {}
table.insert(ns.onLogin, function()
  C_Timer.After(20, function() ns.syncNow(true) end)
  if C_Timer.NewTicker then C_Timer.NewTicker(900, function() ns.syncNow(true) end) end
end)
