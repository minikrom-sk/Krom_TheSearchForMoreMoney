-- Krom The Search for More Money - the price graph panel and item tooltip line.
--
-- The panel docks to the right of the Auction House while it's open (same
-- height as the AH), and can also be opened on its own (/money or the minimap
-- button). It shows the focus item: whatever you last searched, or hover while
-- the AH is open.
--
-- Graph: lowest price over time (blue), the vendor sell price as a floor
-- (copper), a tick per day, and finer points per quarter of the day where we
-- have them. Underneath: how this item's price runs by time of day.

local ADDON, ns = ...
local opt, say, money = ns.opt, ns.say, ns.money

local W, H = 620, 640        -- panel size when not docked (docked: AH height + EXTRA_H)
local EXTRA_H = 130          -- docked: how far the panel hangs below the AH
local LEFT, RIGHT = 64, 46   -- graph area margins (right side holds the volume scale)
local TOP, BOTTOM = 100, 290 -- graph area: top offset, space kept below it
local RANGES = { 1, 3, 7, 14, 30, 90, 0 } -- 0 = all time
local BLUE = { 0.2, 0.8, 1 }
local COPPER = { 0.93, 0.55, 0.25 }
local VOLC = { 0.62, 0.5, 0.95 }    -- volume (listed) bars

local panel = CreateFrame("Frame", "Krom_TheSearchForMoreMoneyPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(W, H)
panel:SetPoint("CENTER")
panel:SetBackdrop({
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) if not self.docked then self:StartMoving() end end)
panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
panel:SetScript("OnSizeChanged", function() if ns.redraw then ns.redraw() end end)
panel:Hide()
ns.panel = panel

-- Views: the panel shows one at a time (Graph, Deals, ...), picked with tabs
-- under the panel. Each view is a frame covering the whole panel.
ns.views = {}
local tabs = {}
function ns.showView(name)
  if not ns.views[name] then name = "graph" end
  Krom_TheSearchForMoreMoneyDB.view = name
  for n, v in pairs(ns.views) do v.frame:SetShown(n == name) end
  for _, t in ipairs(tabs) do
    if t.view == name then t:LockHighlight(); t:SetAlpha(1) else t:UnlockHighlight(); t:SetAlpha(0.75) end
  end
  local v = ns.views[name]
  if v.onShow then v.onShow() end
end
function ns.addView(name, label, frame, onShow)
  ns.views[name] = { frame = frame, onShow = onShow }
  local t = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  t:SetSize(90, 22)
  t:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8 + #tabs * 94, 2)
  t:SetText(label)
  t.view = name
  t:SetScript("OnClick", function() ns.showView(name) end)
  tabs[#tabs + 1] = t
  frame:SetShown(false)
end
function ns.currentView()
  local v = opt("view", "graph")
  return ns.views[v] and v or "graph"
end

local gv = CreateFrame("Frame", nil, panel)
gv:SetAllPoints()

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)
close:SetScript("OnClick", function() panel:Hide(); panel.userClosed = true end)

-- Header: icon, name, lock button
local icon = gv:CreateTexture(nil, "ARTWORK")
icon:SetSize(32, 32)
icon:SetPoint("TOPLEFT", 14, -12)
local title = gv:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
title:SetPoint("RIGHT", -60, 0)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)
local subtitle = gv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
subtitle:SetPoint("RIGHT", -16, 0)
subtitle:SetJustifyH("LEFT")

local lock = CreateFrame("Button", nil, gv)
lock:SetSize(20, 20)
lock:SetPoint("RIGHT", close, "LEFT", 0, 0)
local lockTex = lock:CreateTexture(nil, "ARTWORK")
lockTex:SetAllPoints()
local function updateLock()
  lockTex:SetTexture(ns.focusLocked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
end
lock:SetScript("OnClick", function()
  ns.focusLocked = not ns.focusLocked
  updateLock()
end)
lock:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(ns.focusLocked and "Locked on this item" or "Following your searches")
  GameTooltip:AddLine("Click to " .. (ns.focusLocked and "follow searches and hovered items again." or "keep showing this item."), 1, 1, 1, true)
  GameTooltip:Show()
end)
lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
updateLock()

-- Graph area (stretches with the panel)
local area = CreateFrame("Frame", nil, gv)
area:SetPoint("TOPLEFT", LEFT, -TOP)
area:SetPoint("BOTTOMRIGHT", -RIGHT, BOTTOM)
local bg = area:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(1, 1, 1, 0.04)

local YSTEPS = 4
local hGrid, yLabels = {}, {}
for i = 0, YSTEPS do
  local t = area:CreateTexture(nil, "BORDER")
  t:SetColorTexture(1, 1, 1, i == 0 and 0.15 or 0.07)
  t:SetHeight(1)
  hGrid[i] = t
  local fs = gv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetJustifyH("RIGHT")
  yLabels[i] = fs
end
local empty = area:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetPoint("LEFT", 10, 0)
empty:SetPoint("RIGHT", -10, 0)

local function BreakUpLargeNumbersSafe(n)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(math.floor(n))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Pools: day ticks / labels / day grid lines, price lines, dots
local pools = { tick = {}, xlabel = {}, vgrid = {}, line = {}, dot = {}, band = {}, vol = {}, faint = {}, sub = {} }
local function pooled(kind, i, make)
  local p = pools[kind]
  if not p[i] then p[i] = make() end
  return p[i]
end
local function hideAll()
  for _, p in pairs(pools) do for _, o in pairs(p) do if o then o:Hide() end end end
end
local function newTex(layer, r, g, b, a)
  return function() local t = area:CreateTexture(nil, layer); t:SetColorTexture(r, g, b, a); return t end
end
local function getLine(i)
  return pooled("line", i, function()
    if not area.CreateLine then return false end
    local l = area:CreateLine(nil, "ARTWORK")
    l:SetThickness(2)
    l:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], 0.9)
    return l
  end)
end
local function getDot(i)
  return pooled("dot", i, function()
    local b = CreateFrame("Button", nil, area)
    b:SetSize(12, 12)
    b:SetFrameLevel(area:GetFrameLevel() + 3)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetSize(5, 5)
    t:SetPoint("CENTER")
    t:SetColorTexture(1, 0.82, 0, 1)
    b.tex = t
    b:SetScript("OnEnter", function(self)
      self.tex:SetSize(8, 8)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.label)
      if self.market then
        GameTooltip:AddLine("Market value: " .. money(self.price), 1, 1, 1)
      else
        GameTooltip:AddLine("Lowest listing: " .. money(self.price), 1, 1, 1)
        GameTooltip:AddLine("(no market value for this day - imported or a quick search)", 0.6, 0.6, 0.6, true)
      end
      if self.vol then GameTooltip:AddLine("Listed that day: " .. BreakUpLargeNumbersSafe(self.vol), 0.8, 0.8, 0.9) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.tex:SetSize(5, 5); GameTooltip:Hide() end)
    return b
  end)
end

-- Volume scale on the right edge (in the volume colour)
local volAxis = {}
for i = 1, 2 do
  local fs = gv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetTextColor(VOLC[1], VOLC[2], VOLC[3])
  fs:SetJustifyH("LEFT")
  volAxis[i] = fs
end

-- Faint dots: the cheapest single listing that day, when it's under the line
local function getFaint(i)
  return pooled("faint", i, function()
    local b = CreateFrame("Button", nil, area)
    b:SetSize(10, 10)
    b:SetFrameLevel(area:GetFrameLevel() + 2)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(4, 4)
    t:SetPoint("CENTER")
    t:SetColorTexture(0.85, 0.85, 0.95, 0.45)
    b.tex = t
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.label)
      GameTooltip:AddLine("Cheapest single listing: " .. money(self.price), 1, 1, 1)
      GameTooltip:AddLine("A bargain someone posted - not what a real amount costs.", 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end)
end

-- Vendor price line (the floor)
local vendorLine = area:CreateTexture(nil, "ARTWORK")
vendorLine:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.85)
vendorLine:SetHeight(2)
local vendorLabel = area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
vendorLabel:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
vendorLabel:SetJustifyH("LEFT")

-- Stats line
local stats = gv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stats:SetPoint("TOPLEFT", area, "BOTTOMLEFT", -LEFT + 16, -24)
stats:SetPoint("RIGHT", -16, 0)
stats:SetJustifyH("LEFT")
stats:SetSpacing(3)

-- Pattern reports under the graph: day of week (7 columns) and time of day
-- (4). Each one leads with a plain sentence ("Cheapest: Tue - buy then"),
-- then a mini chart: bar UP (red) = pricier than usual, DOWN (green) = cheaper.
local ROW_H, BAR_H = 92, 13
local function makeRow(n, bottom)
  local row = CreateFrame("Frame", nil, gv)
  row:SetPoint("BOTTOMLEFT", 16, bottom)
  row:SetPoint("BOTTOMRIGHT", -16, bottom)
  row:SetHeight(ROW_H)
  row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.title:SetPoint("TOPLEFT")
  row.title:SetPoint("RIGHT")
  row.title:SetJustifyH("LEFT")
  row.headline = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.headline:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
  row.headline:SetPoint("RIGHT")
  row.headline:SetJustifyH("LEFT")
  row.mid = row:CreateTexture(nil, "BORDER")
  row.mid:SetColorTexture(1, 1, 1, 0.15)
  row.mid:SetHeight(1)
  row.mid:SetPoint("LEFT", row, "TOPLEFT", 0, -58)
  row.mid:SetPoint("RIGHT", row, "TOPRIGHT", 0, -58)
  row.cols = {}
  for i = 1, n do
    row.cols[i] = {
      name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      bar = row:CreateTexture(nil, "ARTWORK"),
      val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
    }
    row.cols[i].name:SetJustifyH("CENTER")
    row.cols[i].val:SetJustifyH("CENTER")
  end
  return row
end
local todRow = makeRow(4, 10)
local dowRow = makeRow(7, 10 + ROW_H + 12)

local function confidence(n, unit)
  local s = ("%d %s%s"):format(n, unit, n == 1 and "" or "s")
  if n < 3 then return "|cffff9933from " .. s .. " - early guess|r" end
  if n < 8 then return "|cffcccc66from " .. s .. " - getting there|r" end
  return "|cff66cc66from " .. s .. " - solid|r"
end

local function drawRow(row, head, names, short, pct, count, unit, waiting)
  local n = #names
  local w = (row:GetWidth() or 480) / n
  if not w or w <= 0 then w = 480 / n end
  local maxAbs, lo, hi = 1, nil, nil
  for i = 1, n do
    if pct[i] then
      maxAbs = math.max(maxAbs, math.abs(pct[i]))
      if not lo or pct[i] < pct[lo] then lo = i end
      if not hi or pct[i] > pct[hi] then hi = i end
    end
  end
  for i = 1, n do
    local c = row.cols[i]
    local cx = w * (i - 0.5)
    c.name:ClearAllPoints(); c.name:SetPoint("TOP", row, "TOPLEFT", cx, -32)
    c.val:ClearAllPoints(); c.val:SetPoint("TOP", row, "TOPLEFT", cx, -72)
    c.name:SetText(names[i])
    c.name:SetShown(count > 0)
    c.bar:ClearAllPoints()
    if count > 0 and pct[i] then
      local p = pct[i]
      local h = math.max(1, BAR_H * math.abs(p) / maxAbs)
      c.bar:SetSize(math.min(26, w * 0.4), h)
      if p > 0 then
        c.bar:SetPoint("BOTTOM", row, "TOPLEFT", cx, -58)
        c.bar:SetColorTexture(1, 0.45, 0.4, 0.9)
        c.val:SetText(("|cffff7766+%.0f%%|r"):format(p))
      else
        c.bar:SetPoint("TOP", row, "TOPLEFT", cx, -58)
        c.bar:SetColorTexture(0.4, 0.9, 0.4, 0.9)
        c.val:SetText(("|cff66ee66%.0f%%|r"):format(p))
      end
      c.bar:Show()
    else
      c.bar:Hide()
      c.val:SetText(count > 0 and "|cff666666no data|r" or "")
    end
  end
  row.mid:SetShown(count > 0)
  if count == 0 or not lo or lo == hi then
    row.title:SetText(head)
    row.headline:SetText("|cff999999" .. waiting .. "|r")
  else
    row.title:SetText(head .. "  " .. confidence(count, unit))
    row.headline:SetText(("Buy on |cff66ee66%s|r (%.0f%%), sell on |cffff7766%s|r (+%.0f%%)."):format(
      short[lo], pct[lo], short[hi], pct[hi]))
  end
end

-- Range buttons
local rangeBtns = {}
for i, days in ipairs(RANGES) do
  local b = CreateFrame("Button", nil, gv, "UIPanelButtonTemplate")
  b:SetSize(44, 20)
  b:SetPoint("TOPLEFT", 16 + (i - 1) * 48, -50)
  b:SetText(days == 0 and "All" or (days .. "d"))
  b:SetScript("OnClick", function()
    Krom_TheSearchForMoreMoneyDB.range = days
    if ns.redraw then ns.redraw() end
  end)
  rangeBtns[i] = b
end

-- Legend: its own row above the graph. Swatch + label; "Cheapest" and
-- "Listed" are click-to-toggle.
local legendItems = {}
local function legendItem(color, label, kind, key, tip)
  local b = CreateFrame("Button", nil, gv)
  b:SetHeight(16)
  local sw = b:CreateTexture(nil, "ARTWORK")
  sw:SetPoint("LEFT")
  if kind == "line" then sw:SetSize(14, 2) elseif kind == "dot" then sw:SetSize(5, 5) else sw:SetSize(8, 10) end
  sw:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", sw, "RIGHT", 4, 0)
  fs:SetText(label)
  b.sw, b.fs, b.key = sw, fs, key
  b:SetWidth(18 + (fs:GetStringWidth() or 60))
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(label)
    GameTooltip:AddLine(tip, 1, 1, 1, true)
    if key then GameTooltip:AddLine("Click to show/hide.", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if key then
    b:SetScript("OnClick", function()
      Krom_TheSearchForMoreMoneyDB[key] = not opt(key, true)
      if ns.redraw then ns.redraw() end
    end)
  end
  local prev = legendItems[#legendItems]
  if prev then b:SetPoint("LEFT", prev, "RIGHT", 14, 0) else b:SetPoint("TOPLEFT", 16, -78) end
  legendItems[#legendItems + 1] = b
  return b
end
legendItem(BLUE, "Market value", "line", nil, "What a real amount costs: the cheapest 15-30% of everything listed, bargain outliers ignored.")
legendItem({ 0.85, 0.85, 0.95, 0.6 }, "Cheapest listing", "dot", "showCheapest", "The single cheapest listing that day, when it was under the market value. Usually a bargain that got sniped.")
legendItem(COPPER, "Vendor price", "line", "showVendor", "What a vendor pays. The floor - selling on the AH below this is throwing money away.")
legendItem({ VOLC[1], VOLC[2], VOLC[3], 0.6 }, "Listed (volume)", "bar", "showVolume", "How many were up for sale that day (most seen). Scale on the right edge. Hover a bar for the count.")
local function updateLegend()
  for _, b in ipairs(legendItems) do
    if b.key then b:SetAlpha(opt(b.key, true) and 1 or 0.35) end
  end
end

-- Full scan button (lives on the panel because opening Options closes the AH).
-- A builder, so every view can have one; they share the cooldown.
local SCAN_COOLDOWN = 15 * 60
local function scanLeft()
  return ns.lastFullScan and math.max(0, SCAN_COOLDOWN - (GetTime() - ns.lastFullScan)) or 0
end
function ns.makeScanButton(parent)
  local scanBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  scanBtn:SetSize(90, 20)
  scanBtn:SetText("Full scan")
  local function updateScanBtn()
    local ah = ns.ahFrame() and ns.ahFrame():IsShown()
    local left = scanLeft()
    if left > 0 then
      scanBtn:SetText(("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60)))
    else
      scanBtn:SetText("Full scan")
    end
    scanBtn:SetEnabled(ah and left == 0 and true or false)
  end
  local tick = 0
  scanBtn:SetScript("OnUpdate", function(_, e)
    tick = tick + e
    if tick >= 0.5 then tick = 0; updateScanBtn() end
  end)
  scanBtn:SetScript("OnClick", function()
    if ns.startFullScan() then ns.lastFullScan = GetTime() end
    updateScanBtn()
  end)
  scanBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Full scan")
    GameTooltip:AddLine("Records every listing on the Auction House. The game allows one every 15 minutes.", 1, 1, 1, true)
    if scanLeft() > 0 then GameTooltip:AddLine("Ready again when the timer runs out.", 1, 0.8, 0.2, true) end
    if not (ns.ahFrame() and ns.ahFrame():IsShown()) then GameTooltip:AddLine("Open the Auction House first.", 1, 0.3, 0.3, true) end
    GameTooltip:Show()
  end)
  scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return scanBtn
end
local scanBtn = ns.makeScanButton(gv)
scanBtn:SetPoint("TOPRIGHT", -16, -50)

local function itemInfo(itemID)
  local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, name, link, quality, _, _, _, _, _, _, tex, sellPrice = pcall(GetInfo, itemID)
  if not ok then return nil end
  return name, tex, link, sellPrice
end

-- Round the price axis to steps that read well (1c, 2c, 5c, 10c, 25c...).
local function niceAxis(lo, hi)
  local span = math.max(hi - lo, 1)
  local raw = span / YSTEPS
  local mag = 10 ^ math.floor(math.log10(raw))
  local step
  for _, m in ipairs({ 1, 2, 2.5, 3, 4, 5, 6, 8, 10 }) do
    step = m * mag
    if step >= raw then break end
  end
  step = math.max(1, math.floor(step + 0.5))
  local ymin = math.floor(lo / step) * step
  while ymin + step * YSTEPS < hi do step = step * 2; ymin = math.floor(lo / step) * step end
  return ymin, ymin + step * YSTEPS
end

-- Average of (price / its group's average - 1) per position, over groups
-- (days or weeks) that have at least two positions filled.
-- entries: { group, position, price }. Returns pct[position], groups used.
local function pattern(entries, n)
  local groups = {}
  for _, e in ipairs(entries) do
    groups[e[1]] = groups[e[1]] or {}
    local g = groups[e[1]]
    if not g[e[2]] or e[3] < g[e[2]] then g[e[2]] = e[3] end
  end
  local sum, cnt, used = {}, {}, 0
  for i = 1, n do sum[i], cnt[i] = 0, 0 end
  for _, g in pairs(groups) do
    local tot, c = 0, 0
    for _, p in pairs(g) do tot = tot + p; c = c + 1 end
    if c >= 2 then
      used = used + 1
      local avg = tot / c
      for i, p in pairs(g) do sum[i] = sum[i] + (p / avg - 1); cnt[i] = cnt[i] + 1 end
    end
  end
  local out = {}
  for i = 1, n do out[i] = cnt[i] > 0 and (sum[i] / cnt[i] * 100) or nil end
  return out, used
end
ns.pattern = pattern

local TOD_NAMES = { "Night |cff7777770-6|r", "Morning |cff7777776-12|r", "Afternoon |cff77777712-18|r", "Evening |cff77777718-24|r" }
local TOD_SHORT = { "nights", "mornings", "afternoons", "evenings" }
local DOW_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local DOW_SHORT = { "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays" }

local function drawPatterns(itemID)
  -- time of day: every quarter-day price we've kept (30 days)
  local e = {}
  for _, s in ipairs(ns.slotHistory(itemID)) do e[#e + 1] = { math.floor(s[1] / 4), s[1] % 4 + 1, s[2] } end
  local pct, used = pattern(e, 4)
  drawRow(todRow, "Time of day |cff999999(your clock, vs that day's average)|r", TOD_NAMES, TOD_SHORT, pct, used, "day",
    "Collecting... needs this item seen at two different times of the same day.")
  -- day of week: daily prices, grouped into Monday-to-Sunday weeks
  e = {}
  for _, p in ipairs(ns.history(itemID)) do
    if not p[4] then -- skip weekly averages from long ago: they have no weekday
      local wd = (ns.weekday(p[1]) + 5) % 7 + 1 -- Mon=1 .. Sun=7
      e[#e + 1] = { math.floor((p[1] + 3) / 7), wd, p[2] }
    end
  end
  pct, used = pattern(e, 7)
  drawRow(dowRow, "Weekly report |cff999999(vs that week's average)|r", DOW_NAMES, DOW_SHORT, pct, used, "week",
    "Collecting... needs prices on two different days of the same week.")
end

function ns.redraw()
  if not panel:IsShown() or not gv:IsShown() then return end
  local itemID = ns.focusID
  local range = opt("range", 30)
  for i, b in ipairs(rangeBtns) do
    if RANGES[i] == range then b:LockHighlight() else b:UnlockHighlight() end
  end
  hideAll()
  updateLegend()
  vendorLine:Hide(); vendorLabel:Hide()
  for _, fs in ipairs(volAxis) do fs:SetText("") end
  local GW, GH = area:GetWidth(), area:GetHeight()
  if not GW or GW <= 0 or not GH or GH <= 0 then GW, GH = W - LEFT - RIGHT, H - TOP - BOTTOM end
  for i = 0, YSTEPS do
    local y = GH * i / YSTEPS
    hGrid[i]:ClearAllPoints()
    hGrid[i]:SetPoint("LEFT", area, "BOTTOMLEFT", 0, y)
    hGrid[i]:SetPoint("RIGHT", area, "BOTTOMRIGHT", 0, y)
    yLabels[i]:ClearAllPoints()
    yLabels[i]:SetPoint("RIGHT", area, "BOTTOMLEFT", -6, y)
    yLabels[i]:SetText("")
  end

  if not itemID then
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    title:SetText("Krom The Search for More Money")
    subtitle:SetText("Search the Auction House or hover an item.")
    empty:SetText("No item selected")
    empty:Show()
    stats:SetText("")
    todRow:Hide(); dowRow:Hide()
    return
  end
  todRow:Show(); dowRow:Show()

  local name, tex, _, vendor = itemInfo(itemID)
  icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
  title:SetText(name or ("Item " .. itemID))
  if vendor and vendor <= 0 then vendor = nil end
  local vendorPrice = vendor          -- for the stats line
  if not opt("showVendor", true) then vendor = nil end

  local today = ns.today()
  local all = ns.history(itemID)
  local span = range
  if range == 0 then -- all time: from the first thing we know (at least a week)
    span = math.max(7, all[1] and (today - all[1][1] + 1) or 7)
  end
  local first = today - span + 1
  local pts = ns.history(itemID, first)
  subtitle:SetText(("%s%d days of data, %d in this range"):format(ns.house == "neutral" and "|cffff9933Neutral AH|r - " or "", #all, #pts))

  -- x axis: fractional days from `first` to the end of today
  local function xOf(dayf) return (dayf - first) / span * GW end

  -- Day backdrop: alternating light bands per day (per week on 90d), a
  -- brighter line where each week starts (Monday), a tick per day.
  local dayW = GW / span
  local weekly = span > 30
  local li = 0
  for d = first, today do
    local i = d - first + 1
    local x = xOf(d)
    local week = math.floor((d + 3) / 7)
    if (weekly and week % 2 == 0) or (not weekly and d % 2 == 0) then
      local band = pooled("band", i, newTex("BACKGROUND", 1, 1, 1, 0.035))
      band:ClearAllPoints()
      band:SetPoint("TOPLEFT", area, "TOPLEFT", x, 0)
      band:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", x, 0)
      band:SetWidth(math.max(1, dayW))
      band:Show()
    end
    local t = pooled("tick", i, newTex("BORDER", 1, 1, 1, 0.3))
    t:ClearAllPoints(); t:SetSize(1, 4); t:SetPoint("TOP", area, "BOTTOMLEFT", x, 0); t:Show()
    local monday = ns.weekday(d) == 2
    if monday and d > first then
      local wl = pooled("vgrid", i, newTex("BORDER", 1, 1, 1, 0.16))
      wl:ClearAllPoints(); wl:SetWidth(1)
      wl:SetPoint("TOP", area, "TOPLEFT", x, 0); wl:SetPoint("BOTTOM", area, "BOTTOMLEFT", x, 0); wl:Show()
    end
    -- labels: every day (<=7d), every 2nd day (14d), Mondays (30d),
    -- every 2nd Monday (90d), the 1st of each month (longer)
    local text, at
    if span <= 7 then
      text, at = (d == today and "today" or ns.dayLabel(d)), xOf(d + 0.5)
    elseif span <= 14 then
      if (today - d) % 2 == 0 then text, at = (d == today and "today" or ns.dayLabel(d)), xOf(d + 0.5) end
    elseif span <= 90 then
      if monday and (span <= 30 or week % 2 == 0) and (today - d) * dayW > 34 then
        text, at = ns.dayLabel(d), x
      elseif d == today then
        text, at = "today", xOf(d + 0.5)
      end
    elseif date("!*t", d * 86400).day == 1 and (today - d) * dayW > 30 then
      text, at = ns.dayLabel(d):match("^%a+"), x
    elseif d == today then
      text, at = "today", xOf(d + 0.5)
    end
    if text then
      li = li + 1
      local fs = pooled("xlabel", li, function() return gv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end)
      fs:ClearAllPoints()
      fs:SetPoint("TOP", area, "BOTTOMLEFT", at, -6)
      fs:SetText(text)
      fs:Show()
    end
  end

  -- 1d / 3d: faint lines every 6 hours, labelled in your local time
  if span <= 3 then
    local si = 0
    for q = 1, span * 4 - 1 do
      if q % 4 ~= 0 then
        local df = first + q / 4
        si = si + 1
        local l = pooled("sub", si, newTex("BORDER", 1, 1, 1, 0.06))
        l:ClearAllPoints(); l:SetWidth(1)
        l:SetPoint("TOP", area, "TOPLEFT", xOf(df), 0); l:SetPoint("BOTTOM", area, "BOTTOMLEFT", xOf(df), 0); l:Show()
        if span == 1 then
          li = li + 1
          local fs = pooled("xlabel", li, function() return gv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end)
          fs:ClearAllPoints()
          fs:SetPoint("TOP", area, "BOTTOMLEFT", xOf(df), -6)
          fs:SetText(date("%H:%M", math.floor(df * 86400)))
          fs:Show()
        end
      end
    end
  end

  -- Volume: bars along the bottom (up to 30% of the height), scaled to the
  -- busiest day shown, with their own scale on the right. Toggle in the legend.
  local vmax, vols = 0, {}
  for d = first, today do
    local v = ns.volume(itemID, d)
    if v then vols[d] = v; vmax = math.max(vmax, v) end
  end
  if opt("showVolume", true) and vmax > 0 then
    local VH = GH * 0.3
    for d, v in pairs(vols) do
      local i = d - first + 1
      local bar = pooled("vol", i, function()
        local b = CreateFrame("Frame", nil, area)
        b:SetFrameLevel(area:GetFrameLevel() + 1)
        b.tex = b:CreateTexture(nil, "BORDER")
        b.tex:SetAllPoints()
        b.tex:SetColorTexture(VOLC[1], VOLC[2], VOLC[3], 0.28)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
          self.tex:SetColorTexture(VOLC[1], VOLC[2], VOLC[3], 0.5)
          GameTooltip:SetOwner(self, "ANCHOR_TOP")
          GameTooltip:AddLine(self.label)
          GameTooltip:AddLine(BreakUpLargeNumbersSafe(self.v) .. " listed (most seen that day)", VOLC[1], VOLC[2], VOLC[3])
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
          self.tex:SetColorTexture(VOLC[1], VOLC[2], VOLC[3], 0.28)
          GameTooltip:Hide()
        end)
        return b
      end)
      bar.label, bar.v = ns.dayLabel(d), v
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOM", area, "BOTTOMLEFT", xOf(d + 0.5), 0)
      bar:SetSize(math.max(2, dayW * 0.7), math.max(1, v / vmax * VH))
      bar:Show()
    end
    volAxis[1]:ClearAllPoints(); volAxis[1]:SetPoint("LEFT", area, "BOTTOMRIGHT", 5, VH)
    volAxis[1]:SetText(BreakUpLargeNumbersSafe(vmax))
    volAxis[2]:ClearAllPoints(); volAxis[2]:SetPoint("LEFT", area, "BOTTOMRIGHT", 5, VH / 2)
    volAxis[2]:SetText(BreakUpLargeNumbersSafe(math.floor(vmax / 2)))
  end

  drawPatterns(itemID)

  if #pts == 0 then
    empty:SetText(#all > 0 and "No prices in this range - try a longer one." or "No prices recorded yet.\nSearch for it in the Auction House.")
    empty:Show()
    stats:SetText("")
    return
  end
  empty:Hide()

  -- Points: quarter-of-day points where we have them, else one per day.
  local slots = ns.slotHistory(itemID, first)
  local haveSlotDay = {}
  local plot = {}
  for _, s in ipairs(slots) do
    local df = ns.slotDay(s[1])
    haveSlotDay[math.floor(df)] = true
    plot[#plot + 1] = { df, s[2], ns.dayLabel(math.floor(df)) .. " " .. ns.QUARTERS[s[1] % 4]:lower(), true }
  end
  for _, p in ipairs(pts) do
    if not haveSlotDay[p[1]] then
      plot[#plot + 1] = { p[1] + 0.5, p[2], ns.dayLabel(p[1]) .. (p[1] == today and " (today)" or ""), p[3] }
    end
  end
  table.sort(plot, function(a, b) return a[1] < b[1] end)

  local lo, hi, sum = math.huge, 0, 0
  for _, p in ipairs(pts) do
    lo = math.min(lo, p[2]); hi = math.max(hi, p[2]); sum = sum + p[2]
  end
  for _, p in ipairs(plot) do lo = math.min(lo, p[2]); hi = math.max(hi, p[2]) end
  -- Cheapest single listings (faint dots). They join the scale unless they're
  -- wild (under half the line's low); those sit on the bottom edge instead.
  local lows = ns.lowestHistory(itemID, first)
  local glo, ghi = lo, hi
  for _, r in ipairs(lows) do if r[2] >= lo * 0.5 then glo = math.min(glo, r[2]) end end
  if vendor then glo = math.min(glo, vendor); ghi = math.max(ghi, vendor) end
  local pad = math.max((ghi - glo) * 0.08, 1)
  local ymin, ymax = niceAxis(math.max(0, glo - pad), ghi + pad)
  for i = 0, YSTEPS do yLabels[i]:SetText(money(ymin + (ymax - ymin) * i / YSTEPS)) end
  local function yOf(price) return (price - ymin) / (ymax - ymin) * GH end

  if vendor then
    local y = yOf(vendor)
    vendorLine:ClearAllPoints()
    vendorLine:SetPoint("LEFT", area, "BOTTOMLEFT", 0, y)
    vendorLine:SetPoint("RIGHT", area, "BOTTOMRIGHT", 0, y)
    vendorLine:Show()
    vendorLabel:ClearAllPoints()
    vendorLabel:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 4, y + 3)
    vendorLabel:SetText("vendor " .. money(vendor))
    vendorLabel:Show()
  end

  local lineAt = {}
  for _, p in ipairs(pts) do lineAt[p[1]] = p[2] end
  for i, r in ipairs(opt("showCheapest", true) and lows or {}) do
    if not lineAt[r[1]] or r[2] < lineAt[r[1]] * 0.97 then
      local f = getFaint(i)
      f:ClearAllPoints()
      f:SetPoint("CENTER", area, "BOTTOMLEFT", xOf(r[1] + 0.5), math.max(2, yOf(r[2])))
      f.label, f.price = ns.dayLabel(r[1]), r[2]
      f:Show()
    end
  end

  local px, py, pm
  for i, p in ipairs(plot) do
    local x, y = xOf(p[1]), yOf(p[2])
    local d = getDot(i)
    d:ClearAllPoints()
    d:SetPoint("CENTER", area, "BOTTOMLEFT", x, y)
    d.label, d.price, d.vol, d.market = p[3], p[2], vols[math.floor(p[1])], p[4]
    d.tex:SetColorTexture(1, 0.82, 0, p[4] and 1 or 0.5)
    d:Show()
    if px then
      local l = getLine(i - 1)
      if l then
        l:SetStartPoint("BOTTOMLEFT", area, px, py)
        l:SetEndPoint("BOTTOMLEFT", area, x, y)
        -- solid where both ends are market values, dim where we only had the lowest listing
        l:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], (pm and p[4]) and 0.95 or 0.4)
        l:Show()
      end
    end
    px, py, pm = x, y, p[4]
  end

  local latest = all[#all]
  local avg = sum / #pts
  local change = ""
  if #pts >= 2 then
    local pct = (pts[#pts][2] - pts[1][2]) / pts[1][2] * 100
    local col = pct > 0.5 and "|cffff6060" or pct < -0.5 and "|cff60ff60" or "|cffcccccc"
    change = ("   %s%+.0f%%|r over %s"):format(col, pct, range == 0 and "all time" or (range .. "d"))
  end
  local vend = ""
  if vendorPrice then
    vend = ("   Vendor: |cffffffff%s|r"):format(money(vendorPrice))
    if latest[2] < vendorPrice * 1.15 then vend = vend .. " |cffff9933(AH barely beats vendor)|r" end
  end
  local rawToday = ns.realmData().items[itemID] and ns.realmData().items[itemID][today]
  if rawToday and latest[1] == today and latest[3] and rawToday < latest[2] * 0.9 then
    vend = vend .. ("   |cffbbbbccCheapest listing: %s|r"):format(money(rawToday))
  end
  local vNow = ns.volume(itemID, today)
  if vNow then vend = vend .. ("   Listed today: |cffffffff%s|r"):format(BreakUpLargeNumbersSafe(vNow)) end
  local age = today - latest[1]
  stats:SetText(((latest[3] and "Market value" or "Lowest listing") .. ": |cffffffff%s|r %s%s\nAverage: |cffffffff%s|r   Low: |cffffffff%s|r   High: |cffffffff%s|r%s"):format(
    money(latest[2]), age == 0 and "(today)" or ("(" .. age .. "d ago)"), vend,
    money(avg), money(lo), money(hi), change))
end

-- Docking: sit beside the AH while it's open.
local function dock()
  local ah = ns.ahFrame()
  panel:ClearAllPoints()
  if ah and ah:IsShown() then
    panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
    panel:SetSize(W, math.max(480, math.floor(ah:GetHeight() or H) + EXTRA_H))
    panel.docked = true
  else
    panel:SetPoint("CENTER")
    panel:SetSize(W, H)
    panel.docked = false
  end
end

function ns.showPanel(itemID)
  if itemID then ns.focus(itemID, "manual") end
  dock()
  panel.userClosed = false
  panel:Show()
  ns.showView(itemID and "graph" or ns.currentView())
end

ns.onFocus = function() ns.redraw() end
ns.onNewData = function() ns.redraw() end
table.insert(ns.listeners, function(itemID) if itemID == ns.focusID then ns.redraw() end end)

ns.onAHShow = function()
  if opt("showWithAH", true) then
    dock()
    panel:Show()
    ns.showView(ns.currentView())
  end
end
ns.onAHHide = function()
  if panel.docked then panel:Hide() end
end

-- ---------------------------------------------------------------------------
-- Tooltips: a price line on every item; hovering with the AH open focuses it.
-- ---------------------------------------------------------------------------
ns.addView("graph", "Price graph", gv, function() ns.redraw() end)

local function onTooltip(tt)
  if not tt or not tt.GetItem then return end
  local ok, _, link = pcall(tt.GetItem, tt)
  if not ok or type(link) ~= "string" then return end
  local itemID = tonumber(link:match("item:(%d+)"))
  if not itemID then return end
  local ah = ns.ahFrame()
  if ah and ah:IsShown() and panel:IsShown() and opt("followHover", true) and tt == GameTooltip then
    if itemID ~= ns.focusID then ns.focus(itemID, "hover") end
  end
  if not opt("tooltip", true) then return end
  local s = ns.stats(itemID, 7)
  if not s then return end
  local age = ns.today() - s.day
  local when = age == 0 and "today" or (age == 1 and "yesterday" or (age .. "d ago"))
  local line = ("|cff33ccffMoreMoney:|r %s |cff999999(%s)|r"):format(money(s.price), when)
  if s.avg and s.points >= 2 then
    line = line .. ("  |cff999999- 7d avg|r %s"):format(money(s.avg))
  end
  tt:AddLine(line, 1, 1, 1)
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
else
  GameTooltip:HookScript("OnTooltipSetItem", onTooltip)
  if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", onTooltip) end
end
