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

local W, H = 520, 440        -- panel size when not docked (docked: AH height)
local LEFT, RIGHT = 64, 20   -- graph area margins
local TOP, BOTTOM = 80, 150  -- graph area: top offset, space kept below it
local RANGES = { 7, 14, 30, 90 }
local BLUE = { 0.2, 0.8, 1 }
local COPPER = { 0.93, 0.55, 0.25 }

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

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)
close:SetScript("OnClick", function() panel:Hide(); panel.userClosed = true end)

-- Header: icon, name, lock button
local icon = panel:CreateTexture(nil, "ARTWORK")
icon:SetSize(32, 32)
icon:SetPoint("TOPLEFT", 14, -12)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
title:SetPoint("RIGHT", -60, 0)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)
local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
subtitle:SetPoint("RIGHT", -16, 0)
subtitle:SetJustifyH("LEFT")

local lock = CreateFrame("Button", nil, panel)
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
local area = CreateFrame("Frame", nil, panel)
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
  local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetJustifyH("RIGHT")
  yLabels[i] = fs
end
local empty = area:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetPoint("LEFT", 10, 0)
empty:SetPoint("RIGHT", -10, 0)

-- Pools: day ticks / labels / day grid lines, price lines, dots
local pools = { tick = {}, xlabel = {}, vgrid = {}, line = {}, dot = {} }
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
      GameTooltip:AddLine("Lowest: " .. money(self.price), 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.tex:SetSize(5, 5); GameTooltip:Hide() end)
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
local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stats:SetPoint("TOPLEFT", area, "BOTTOMLEFT", -LEFT + 16, -24)
stats:SetPoint("RIGHT", -16, 0)
stats:SetJustifyH("LEFT")
stats:SetSpacing(3)

-- Time of day: four bars, each quarter's price vs that day's average
local tod = CreateFrame("Frame", nil, panel)
tod:SetPoint("BOTTOMLEFT", 16, 12)
tod:SetPoint("BOTTOMRIGHT", -16, 12)
tod:SetHeight(64)
local todTitle = tod:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
todTitle:SetPoint("TOPLEFT")
todTitle:SetPoint("RIGHT")
todTitle:SetJustifyH("LEFT")
local todNote = tod:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
todNote:SetPoint("TOPLEFT", todTitle, "BOTTOMLEFT", 0, -10)
todNote:SetPoint("RIGHT")
todNote:SetJustifyH("LEFT")
local todCols = {}
for q = 0, 3 do
  local col = {}
  col.name = tod:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  col.bar = tod:CreateTexture(nil, "ARTWORK")
  col.val = tod:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  todCols[q] = col
end
local function layoutTod()
  local w = (tod:GetWidth() or 480) / 4
  for q = 0, 3 do
    local c = todCols[q]
    c.name:ClearAllPoints(); c.name:SetPoint("TOPLEFT", tod, "TOPLEFT", w * q, -18)
    c.bar:ClearAllPoints(); c.bar:SetPoint("TOPLEFT", tod, "TOPLEFT", w * q, -34)
    c.val:ClearAllPoints(); c.val:SetPoint("TOPLEFT", tod, "TOPLEFT", w * q, -46)
  end
  return w
end

-- Range buttons
local rangeBtns = {}
for i, days in ipairs(RANGES) do
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(44, 20)
  b:SetPoint("TOPLEFT", 16 + (i - 1) * 48, -50)
  b:SetText(days .. "d")
  b:SetScript("OnClick", function()
    Krom_TheSearchForMoreMoneyDB.range = days
    if ns.redraw then ns.redraw() end
  end)
  rangeBtns[i] = b
end

-- Legend
local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
legend:SetPoint("LEFT", rangeBtns[#rangeBtns], "RIGHT", 14, 0)
legend:SetText(("|cff%02x%02x%02xlowest price|r    |cff%02x%02x%02xvendor price|r"):format(
  BLUE[1] * 255, BLUE[2] * 255, BLUE[3] * 255, COPPER[1] * 255, COPPER[2] * 255, COPPER[3] * 255))

-- Full scan button (lives here because opening Options closes the AH)
local SCAN_COOLDOWN = 15 * 60
local scanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
scanBtn:SetSize(90, 20)
scanBtn:SetPoint("TOPRIGHT", -16, -50)
scanBtn:SetText("Full scan")
local function scanLeft()
  return ns.lastFullScan and math.max(0, SCAN_COOLDOWN - (GetTime() - ns.lastFullScan)) or 0
end
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
  GameTooltip:AddLine("Records the lowest price of everything on the Auction House. The game allows one every 15 minutes.", 1, 1, 1, true)
  if scanLeft() > 0 then GameTooltip:AddLine("Ready again when the timer runs out.", 1, 0.8, 0.2, true) end
  if not (ns.ahFrame() and ns.ahFrame():IsShown()) then GameTooltip:AddLine("Open the Auction House first.", 1, 0.3, 0.3, true) end
  GameTooltip:Show()
end)
scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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

-- Time-of-day summary: how each quarter's price compares with its day's
-- average, over days where we saw the item in at least two quarters.
local function timeOfDay(slots)
  local byDay = {}
  for _, s in ipairs(slots) do
    local d = math.floor(s[1] / 4)
    byDay[d] = byDay[d] or {}
    byDay[d][s[1] % 4] = s[2]
  end
  local sum, n, days = { [0] = 0, 0, 0, 0 }, { [0] = 0, 0, 0, 0 }, 0
  for _, qs in pairs(byDay) do
    local tot, c = 0, 0
    for _, p in pairs(qs) do tot = tot + p; c = c + 1 end
    if c >= 2 then
      days = days + 1
      local avg = tot / c
      for q, p in pairs(qs) do sum[q] = sum[q] + (p / avg - 1); n[q] = n[q] + 1 end
    end
  end
  local out = {}
  for q = 0, 3 do out[q] = n[q] > 0 and (sum[q] / n[q] * 100) or nil end
  return out, days
end

local function drawTimeOfDay(itemID, first, range)
  local w = layoutTod()
  local slots = ns.slotHistory(itemID, first)
  local pct, days = timeOfDay(slots)
  local head = ("Time of day  |cff999999(your clock, last %d days)|r"):format(range)
  todTitle:SetText(head)
  local maxAbs = 1
  for q = 0, 3 do if pct[q] then maxAbs = math.max(maxAbs, math.abs(pct[q])) end end
  for q = 0, 3 do
    local c = todCols[q]
    c.name:SetText(ns.QUARTERS[q] .. " |cff777777" .. ({ [0] = "0-6", "6-12", "12-18", "18-24" })[q] .. "|r")
    if days > 0 and pct[q] then
      local p = pct[q]
      c.bar:SetSize(math.max(2, (w - 24) * math.abs(p) / maxAbs), 8)
      if p <= 0 then c.bar:SetColorTexture(0.4, 0.9, 0.4, 0.9) else c.bar:SetColorTexture(1, 0.45, 0.4, 0.9) end
      c.bar:Show()
      c.val:SetText(("%+.1f%%"):format(p))
      c.val:Show()
    else
      c.bar:Hide()
      c.val:SetText(days > 0 and "|cff777777no data|r" or "")
    end
    c.name:SetShown(days > 0)
  end
  if days == 0 then
    todNote:SetText("Collecting... once this item has been seen at two different times of the same day, this shows when it runs cheap (green = cheaper than that day's average, red = pricier).")
    todNote:Show()
  else
    todNote:SetText("")
    todNote:Hide()
    todTitle:SetText(head .. ("  |cff999999- %d day%s compared. Green = cheaper.|r"):format(days, days == 1 and "" or "s"))
  end
end

function ns.redraw()
  if not panel:IsShown() then return end
  local itemID = ns.focusID
  local range = opt("range", 30)
  for i, b in ipairs(rangeBtns) do
    if RANGES[i] == range then b:LockHighlight() else b:UnlockHighlight() end
  end
  hideAll()
  vendorLine:Hide(); vendorLabel:Hide()
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
    tod:Hide()
    return
  end
  tod:Show()

  local name, tex, _, vendor = itemInfo(itemID)
  icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
  title:SetText(name or ("Item " .. itemID))
  if vendor and vendor <= 0 then vendor = nil end

  local today = ns.today()
  local first = today - range + 1
  local pts = ns.history(itemID, first)
  local all = ns.history(itemID)
  subtitle:SetText(("%s%d days of data, %d in this range"):format(ns.house == "neutral" and "|cffff9933Neutral AH|r - " or "", #all, #pts))

  -- x axis: fractional days from `first` to the end of today
  local span = range
  local function xOf(dayf) return (dayf - first) / span * GW end

  -- day ticks + labels
  local every = range <= 7 and 1 or range <= 14 and 2 or range <= 30 and 5 or 15
  local li = 0
  for d = first, today do
    local i = d - first + 1
    local x = xOf(d)
    local t = pooled("tick", i, newTex("BORDER", 1, 1, 1, 0.3))
    t:ClearAllPoints(); t:SetSize(1, 4); t:SetPoint("TOP", area, "BOTTOMLEFT", x, 0); t:Show()
    local labeled = (today - d) % every == 0
    if labeled then
      local g = pooled("vgrid", i, newTex("BORDER", 1, 1, 1, 0.05))
      g:ClearAllPoints(); g:SetWidth(1)
      g:SetPoint("TOP", area, "TOPLEFT", x, 0); g:SetPoint("BOTTOM", area, "BOTTOMLEFT", x, 0); g:Show()
      li = li + 1
      local fs = pooled("xlabel", li, function() return panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end)
      fs:ClearAllPoints()
      fs:SetPoint("TOP", area, "BOTTOMLEFT", every == 1 and xOf(d + 0.5) or x, -6)
      fs:SetText(d == today and "today" or ns.dayLabel(d))
      fs:Show()
    end
  end

  drawTimeOfDay(itemID, first, range)

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
    plot[#plot + 1] = { df, s[2], ns.dayLabel(math.floor(df)) .. " " .. ns.QUARTERS[s[1] % 4]:lower() }
  end
  for _, p in ipairs(pts) do
    if not haveSlotDay[p[1]] then
      plot[#plot + 1] = { p[1] + 0.5, p[2], ns.dayLabel(p[1]) .. (p[1] == today and " (today)" or "") }
    end
  end
  table.sort(plot, function(a, b) return a[1] < b[1] end)

  local lo, hi, sum = math.huge, 0, 0
  for _, p in ipairs(pts) do
    lo = math.min(lo, p[2]); hi = math.max(hi, p[2]); sum = sum + p[2]
  end
  for _, p in ipairs(plot) do lo = math.min(lo, p[2]); hi = math.max(hi, p[2]) end
  local glo, ghi = lo, hi
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

  local px, py
  for i, p in ipairs(plot) do
    local x, y = xOf(p[1]), yOf(p[2])
    local d = getDot(i)
    d:ClearAllPoints()
    d:SetPoint("CENTER", area, "BOTTOMLEFT", x, y)
    d.label, d.price = p[3], p[2]
    d:Show()
    if px then
      local l = getLine(i - 1)
      if l then
        l:SetStartPoint("BOTTOMLEFT", area, px, py)
        l:SetEndPoint("BOTTOMLEFT", area, x, y)
        l:Show()
      end
    end
    px, py = x, y
  end

  local latest = all[#all]
  local avg = sum / #pts
  local change = ""
  if #pts >= 2 then
    local pct = (pts[#pts][2] - pts[1][2]) / pts[1][2] * 100
    local col = pct > 0.5 and "|cffff6060" or pct < -0.5 and "|cff60ff60" or "|cffcccccc"
    change = ("   %s%+.0f%%|r over %dd"):format(col, pct, range)
  end
  local vend = ""
  if vendor then
    vend = ("   Vendor: |cffffffff%s|r"):format(money(vendor))
    if latest[2] < vendor * 1.15 then vend = vend .. " |cffff9933(AH barely beats vendor)|r" end
  end
  local age = today - latest[1]
  stats:SetText(("Latest: |cffffffff%s|r %s%s\nAverage: |cffffffff%s|r   Low: |cffffffff%s|r   High: |cffffffff%s|r%s"):format(
    money(latest[2]), age == 0 and "(today)" or ("(" .. age .. "d ago)"), vend,
    money(avg), money(lo), money(hi), change))
end

-- Docking: sit beside the AH while it's open.
local function dock()
  local ah = ns.ahFrame()
  panel:ClearAllPoints()
  if ah and ah:IsShown() then
    panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
    panel:SetSize(W, math.max(H, math.floor(ah:GetHeight() or H)))
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
  ns.redraw()
end

ns.onFocus = function() ns.redraw() end
ns.onNewData = function() ns.redraw() end
table.insert(ns.listeners, function(itemID) if itemID == ns.focusID then ns.redraw() end end)

ns.onAHShow = function()
  if opt("showWithAH", true) then
    dock()
    panel:Show()
    ns.redraw()
  end
end
ns.onAHHide = function()
  if panel.docked then panel:Hide() end
end

-- ---------------------------------------------------------------------------
-- Tooltips: a price line on every item; hovering with the AH open focuses it.
-- ---------------------------------------------------------------------------
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
