-- Krom The Search for More Money - Deals tab: things listed under vendor price.
--
-- Reads every listing from the last full scan (ns.lastScan, this session only)
-- and lists items you can buy for less than a vendor pays for them. Searching
-- an item again refreshes its listings, so bought-out deals drop off.
-- Click a row to pull that item up on the Auction House; buying is up to you.

local ADDON, ns = ...
local opt, money = ns.opt, ns.money
local panel = ns.panel

local ROW_H = 20
local STALE = 15 * 60

local view = CreateFrame("Frame", nil, panel)
view:SetAllPoints()

local function bigNum(n)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(math.floor(n))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Header
local icon = view:CreateTexture(nil, "ARTWORK")
icon:SetSize(32, 32)
icon:SetPoint("TOPLEFT", 14, -12)
icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
title:SetText("Under vendor price")
local subtitle = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
subtitle:SetPoint("RIGHT", -16, 0)
subtitle:SetJustifyH("LEFT")

local scanBtn = ns.makeScanButton(view)
scanBtn:SetPoint("TOPRIGHT", -16, -50)
local recheckBtn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
recheckBtn:SetSize(90, 20)
recheckBtn:SetPoint("TOP", scanBtn, "BOTTOM", 0, -4)
recheckBtn:SetText("Recheck")

-- Category filter buttons (built from what the scan found)
local catBtns = {}
local catBar = CreateFrame("Frame", nil, view)
catBar:SetPoint("TOPLEFT", 16, -50)
catBar:SetPoint("RIGHT", scanBtn, "LEFT", -8, 0)
-- (the Recheck button sits under Full scan, beside the second row of categories)
catBar:SetHeight(44)

-- Column headers
local COLS = { -- label, x within a row, width, justify
  { "Item", 24, 190, "LEFT" },
  { "Under", 218, 50, "RIGHT" },
  { "Price", 272, 66, "RIGHT" },
  { "Vendor", 342, 66, "RIGHT" },
  { "Profit", 412, 72, "RIGHT" },
}
local listTop = -100
for _, c in ipairs(COLS) do
  local fs = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 16 + c[2], listTop)
  fs:SetWidth(c[3])
  fs:SetJustifyH(c[4])
  fs:SetText(c[1])
end
local list = CreateFrame("Frame", nil, view)
list:SetPoint("TOPLEFT", 16, listTop - 16)
list:SetPoint("BOTTOMRIGHT", -16, 34)
list:EnableMouseWheel(true)
local listBg = list:CreateTexture(nil, "BACKGROUND")
listBg:SetAllPoints()
listBg:SetColorTexture(1, 1, 1, 0.03)

local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("LEFT", 16, 0)
empty:SetPoint("RIGHT", -16, 0)
empty:SetPoint("TOP", 0, -40)

local footer = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetPoint("BOTTOMLEFT", 18, 14)
footer:SetPoint("RIGHT", -16, 0)
footer:SetJustifyH("LEFT")

-- ---------------------------------------------------------------------------
-- Finding the deals
-- ---------------------------------------------------------------------------
local deals, pending, offset = {}, 0, 0
local category = nil -- classID or nil for all

local requested = {} -- itemID -> true once we've asked the game to load it
local waiting = {}   -- itemIDs we still need info for
local function itemInfo(itemID)
  local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, name, link, quality, _, _, _, _, _, _, tex, sellPrice, classID = pcall(GetInfo, itemID)
  if not ok or not name then
    waiting[itemID] = true
    if not requested[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
      requested[itemID] = true
      pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return nil
  end
  waiting[itemID] = nil
  return name, link, quality, tex, sellPrice or 0, classID
end

local function compute()
  wipe(deals)
  pending = 0
  local s = ns.lastScan
  if not s then return end
  for itemID, ladder in pairs(s.ladders) do
    local name, link, quality, tex, vendor, classID = itemInfo(itemID)
    if not name then
      pending = pending + 1
    elseif vendor > 0 then
      local qty, profit, cheapest = 0, 0, nil
      for _, e in ipairs(ladder) do
        if e[1] < vendor then
          qty = qty + e[2]
          profit = profit + (vendor - e[1]) * e[2]
          cheapest = math.min(cheapest or e[1], e[1])
        end
      end
      if qty > 0 and profit >= 1 then
        deals[#deals + 1] = { id = itemID, name = name, link = link, quality = quality, tex = tex,
          class = classID, qty = qty, price = cheapest, vendor = vendor, profit = profit }
      end
    end
  end
  -- ties broken by name so the list never shuffles between redraws
  table.sort(deals, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
end
ns.computeDeals = function() compute(); return deals, pending end

local CLASS_NAMES = { [0] = "Consumable", "Container", "Weapon", "Gem", "Armor", "Reagent", "Projectile",
  "Trade Goods", "Enhancement", "Recipe", nil, "Quiver", "Quest", "Key", nil, "Misc", "Glyph", "Battle Pet" }
local function className(classID)
  local get = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
  local ok, n = false, nil
  if get then ok, n = pcall(get, classID) end
  return (ok and n and n ~= "") and n or CLASS_NAMES[classID] or ("Type " .. tostring(classID))
end

-- ---------------------------------------------------------------------------
-- Pulling an item up on the AH
-- ---------------------------------------------------------------------------
function ns.searchAH(itemID, name)
  local ah = ns.ahFrame()
  if not (ah and ah:IsShown()) then ns.say("open the Auction House first."); return end
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    -- straight to the item's buy page if we can, else type it in the search bar
    local ok = pcall(function()
      local key = C_AuctionHouse.MakeItemKey(itemID)
      if AuctionHouseFrameDisplayMode and AuctionHouseFrame.SetDisplayMode then
        AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
      end
      AuctionHouseFrame:SelectBrowseResult({ itemKey = key, minPrice = 0, totalQuantity = 0 })
    end)
    if not ok and AuctionHouseFrame.SearchBar then
      pcall(function()
        AuctionHouseFrame.SearchBar:SetSearchText(name)
        AuctionHouseFrame.SearchBar:StartSearch()
      end)
    end
  elseif BrowseName and AuctionFrameBrowse_Search then
    if AuctionFrameTab1 then pcall(AuctionFrameTab1.Click, AuctionFrameTab1) end
    BrowseName:SetText(name)
    pcall(AuctionFrameBrowse_Search)
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local rows = {}
local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, list)
  r:SetHeight(ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetPoint("RIGHT")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  if i % 2 == 0 then
    local z = r:CreateTexture(nil, "BACKGROUND")
    z:SetAllPoints()
    z:SetColorTexture(1, 1, 1, 0.025)
  end
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 4, 0)
  r.cells = {}
  for c, col in ipairs(COLS) do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", col[2], 0)
    fs:SetWidth(col[3])
    fs:SetJustifyH(col[4])
    fs:SetWordWrap(false)
    r.cells[c] = fs
  end
  r:SetScript("OnEnter", function(self)
    if not self.deal then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.deal.link then GameTooltip:SetHyperlink(self.deal.link) else GameTooltip:SetItemByID(self.deal.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("%s listed under vendor price, cheapest %s each."):format(bigNum(self.deal.qty), money(self.deal.price)), 0.4, 0.9, 0.4, true)
    GameTooltip:AddLine("Click to look it up on the Auction House. Right-click: price graph.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    if not self.deal then return end
    if button == "RightButton" then ns.showPanel(self.deal.id) else ns.searchAH(self.deal.id, self.deal.name) end
  end)
  rows[i] = r
  return r
end

local function visibleRows()
  local h = list:GetHeight()
  if not h or h <= 0 then h = 300 end
  return math.max(1, math.floor(h / ROW_H))
end

local function filtered()
  if not category then return deals end
  local out = {}
  for _, d in ipairs(deals) do if d.class == category then out[#out + 1] = d end end
  return out
end

local redrawList
local function layoutCategories()
  local counts, order = {}, {}
  for _, d in ipairs(deals) do
    if d.class then
      if not counts[d.class] then order[#order + 1] = d.class; counts[d.class] = 0 end
      counts[d.class] = counts[d.class] + 1
    end
  end
  table.sort(order, function(a, b)
    if counts[a] ~= counts[b] then return counts[a] > counts[b] end
    return a < b
  end)
  if category and not counts[category] then category = nil end
  local entries = { { nil, "All (" .. #deals .. ")" } }
  for _, c in ipairs(order) do entries[#entries + 1] = { c, className(c) .. " (" .. counts[c] .. ")" } end
  local x, y = 0, 0
  local maxW = catBar:GetWidth()
  if not maxW or maxW <= 0 then maxW = 300 end
  for i, e in ipairs(entries) do
    local b = catBtns[i]
    if not b then
      b = CreateFrame("Button", nil, catBar, "UIPanelButtonTemplate")
      b:SetHeight(20)
      b:SetScript("OnClick", function(self) category = self.class; offset = 0; redrawList() end)
      catBtns[i] = b
    end
    b.class = e[1]
    b:SetText(e[2])
    local w = math.min(150, (b:GetFontString() and b:GetFontString():GetStringWidth() or 60) + 18)
    b:SetWidth(w)
    if x + w > maxW and x > 0 then x, y = 0, y + 22 end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, -y)
    x = x + w + 4
    if (category == e[1]) then b:LockHighlight() else b:UnlockHighlight() end
    b:SetShown(y < 44)
  end
  for i = #entries + 1, #catBtns do catBtns[i]:Hide() end
end

function redrawList()
  if not view:IsShown() then return end
  layoutCategories()
  local shown = filtered()
  local n = visibleRows()
  offset = math.max(0, math.min(offset, #shown - n))
  for i = 1, math.max(n, #rows) do
    local r = getRow(i)
    local d = (i <= n) and shown[offset + i] or nil
    r.deal = d
    if d then
      local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[d.quality or 1]
      r.icon:SetTexture(d.tex)
      r.cells[1]:SetText(d.name)
      if color then r.cells[1]:SetTextColor(color.r, color.g, color.b) else r.cells[1]:SetTextColor(1, 1, 1) end
      r.cells[2]:SetText(bigNum(d.qty))
      r.cells[3]:SetText(money(d.price))
      r.cells[4]:SetText(money(d.vendor))
      r.cells[5]:SetText("|cff60ff60" .. money(d.profit) .. "|r")
      r:Show()
    else
      r:Hide()
    end
  end

  local s = ns.lastScan
  if not s then
    subtitle:SetText("No full scan yet this session.")
    empty:SetText("Open the Auction House and hit Full scan.\nEvery listing gets checked against what a vendor would pay.")
    empty:Show()
    footer:SetText("")
    return
  end
  local age = ns.now() - s.when
  local ageText = age < 90 and "just now" or (math.floor(age / 60) .. " min ago")
  if age > STALE then ageText = "|cffff9933" .. ageText .. " - deals this old are probably gone|r" end
  local items = 0
  for _ in pairs(s.ladders) do items = items + 1 end
  local other = s.house ~= ns.realmKey() and "  |cffff9933(scanned at a different auction house)|r" or ""
  subtitle:SetText(("Full scan %s - %s items checked%s"):format(ageText, bigNum(items), other))
  if #shown == 0 then
    empty:SetText(pending > 0 and "Still loading item info..." or "Nothing listed under vendor price right now.\nSomebody beat you to it, or the market's behaving.")
    empty:Show()
  else
    empty:Hide()
  end
  local total = 0
  for _, d in ipairs(shown) do total = total + d.profit end
  footer:SetText(("%d deal%s, %s profit if you bought them all%s.%s"):format(#shown, #shown == 1 and "" or "s",
    money(total), pending > 0 and (" - loading info for " .. pending .. " items") or "",
    #shown > n and ("  Showing %d-%d, scroll for more."):format(offset + 1, math.min(#shown, offset + n)) or ""))
end

list:SetScript("OnMouseWheel", function(_, delta)
  offset = offset - delta * 3
  redrawList()
end)

-- ---------------------------------------------------------------------------
-- Recheck: re-search each deal on the list, one at a time, to see what's
-- still there. Plays by the AH's rules: one search in flight, only when the
-- game says the AH is ready for another (IsThrottledMessageSystemReady),
-- a short pause between searches, a cap on how many, and only when you
-- click the button. Buying is never automated.
-- ---------------------------------------------------------------------------
local RECHECK_MAX, GAP, TIMEOUT = 40, 0.4, 5
local queue, qi, waitingFor, sentAt, lastDone, checkedCount = {}, 0, nil, 0, 0, 0
local runner = CreateFrame("Frame")
runner:Hide()

local function stopRecheck(msg)
  runner:Hide()
  ns.rechecking = false
  waitingFor = nil
  recheckBtn:SetText("Recheck")
  if msg then ns.say(msg) end
  if ns.onScanUpdated then ns.onScanUpdated() end
end

local function canSearch()
  if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery) then return false end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then return false end
  return true
end

runner:SetScript("OnUpdate", function()
  local now = GetTime()
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return stopRecheck("recheck stopped - the Auction House closed.") end
  if waitingFor then
    if now - sentAt < TIMEOUT then return end
    waitingFor = nil -- no answer; move on
  end
  if now - lastDone < GAP or not canSearch() then return end
  qi = qi + 1
  local d = queue[qi]
  if not d then
    return stopRecheck(("rechecked %d item%s."):format(checkedCount, checkedCount == 1 and "" or "s"))
  end
  recheckBtn:SetText(("Stop %d/%d"):format(qi, #queue))
  local ok = pcall(function()
    local key = C_AuctionHouse.MakeItemKey(d.id)
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    C_AuctionHouse.SendSearchQuery(key, sorts, true)
  end)
  if ok then waitingFor, sentAt = d.id, now else lastDone = now end
end)

ns.onSearchResult = function(itemID)
  if ns.rechecking and itemID == waitingFor then
    waitingFor = nil
    lastDone = GetTime()
    checkedCount = checkedCount + 1
  end
end

local function startRecheck()
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    ns.say(AuctionFrame and AuctionFrame:IsShown() and "recheck needs the modern Auction House." or "open the Auction House first.")
    return
  end
  wipe(queue)
  for _, dl in ipairs(filtered()) do
    if #queue >= RECHECK_MAX then break end
    queue[#queue + 1] = dl
  end
  if #queue == 0 then ns.say("nothing to recheck."); return end
  qi, waitingFor, lastDone, checkedCount = 0, nil, 0, 0
  ns.rechecking = true
  runner:Show()
end

recheckBtn:SetScript("OnClick", function()
  if ns.rechecking then stopRecheck("recheck stopped.") else startRecheck() end
end)
recheckBtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Recheck")
  GameTooltip:AddLine(("Searches each deal shown (top %d) again, one at a time at the pace the Auction House allows, and drops the ones that are gone. Click again to stop."):format(RECHECK_MAX), 1, 1, 1, true)
  GameTooltip:Show()
end)
recheckBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
view:SetScript("OnHide", function() if ns.rechecking then stopRecheck() end end)

local function refresh()
  compute()
  offset = 0
  redrawList()
end

-- New scan / refreshed item: recompute (throttled), item info arriving too.
local queued = false
local function soon()
  if queued then return end
  queued = true
  C_Timer.After(0.5, function()
    queued = false
    if view:IsShown() then compute(); redrawList() end
  end)
end
ns.onScanUpdated = soon
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
-- only items we're actually waiting on trigger a refresh (the game fires
-- this event for everything, constantly)
ev:SetScript("OnEvent", function(_, _, itemID)
  if itemID and waiting[itemID] then waiting[itemID] = nil; soon() end
end)
view:SetScript("OnSizeChanged", function() redrawList() end)

ns.addView("deals", "Deals", view, refresh)
