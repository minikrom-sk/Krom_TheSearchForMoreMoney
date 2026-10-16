local DIR, REALM = arg[1], arg[2]
local DAY = 20742
_G.time = os.time
-- usage: lua5.1 tools/import_test.lua . "<realm name>" "<Auctionator realm key>" <path to Auctionator.lua SavedVariables>
dofile(arg[4] or "Auctionator.lua")
local ns, said = {}, {}
_G.GetServerTime = function() return DAY*86400+3600 end
_G.GetRealmName = function() return REALM end
_G.Auctionator = os.getenv("AUC") and { State = { CurrentRealm = os.getenv("AUC") } } or nil
_G.GetAutoCompleteRealms = function() if arg[3] then return { arg[3] } end return {} end
_G.UnitFactionGroup = function() return "Alliance" end
_G.Krom_TheSearchForMoreMoneyDB = { realms = {} }
ns.realmKey = function() return "R-Alliance" end
ns.recordVolume = function() end
ns.say = function(s) print("SAY:", s) end
ns.opt = function(k, d) return d end
ns.today = function() return DAY end
ns.now = function() return DAY*86400 end
local rec, n = {}, 0
ns.record = function(id, p, d) n = n + 1; rec[id] = rec[id] or {}; rec[id][d] = p end
local chunk = assert(loadfile(DIR .. "/Import.lua")); chunk("x", ns)
local t0 = os.clock(); ns.importAuctionator(false); print("secs", os.clock()-t0, "records", n)
if not next(rec) then return end local id = next(rec); local ds = {} for d,p in pairs(rec[id]) do ds[#ds+1]=(d-DAY)..":"..p end table.sort(ds); print("sample", id, table.concat(ds," "))
local ds = {} for d,p in pairs(rec[2589] or {}) do ds[#ds+1]=os.date("!%m/%d",d*86400)..":"..p end table.sort(ds) print("linen", table.concat(ds," "))
