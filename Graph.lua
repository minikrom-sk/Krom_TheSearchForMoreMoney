-- Krom The Search for More Money - the price graph panel and item tooltip line.
--
-- The panel docks to the right of the Auction House while it's open, and can
-- also be opened on its own (/money or the minimap button). It shows the focus
-- item: whatever you last searched, or hover while the AH is open.

local ADDON, ns = ...
local opt, say, money = ns.opt, ns.say, ns.money

local W, H = 300, 250                 -- panel size
local GX, GY, GW, GH = 46, -78, 236, 120 -- graph area (left, top offset, width, height)
local RANGES = { 7, 14, 30, 90 }

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
panel:Hide()
ns.panel = panel

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)
close:SetScript("OnClick", function() panel:Hide(); panel.userClosed = true end)

-- Header: icon, name, lock button
local icon = panel:CreateTexture(nil, "ARTWORK")
icon:SetSize(28, 28)
icon:SetPoint("TOPLEFT", 12, -12)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

-- Graph area background + grid
local area = CreateFrame("Frame", nil, panel)
area:SetPoint("TOPLEFT", GX, GY)
area:SetSize(GW, GH)
local bg = area:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(1, 1, 1, 0.04)
local grid = {}
for i = 0, 3 do
  local t = area:CreateTexture(nil, "BORDER")
  t:SetColorTexture(1, 1, 1, 0.08)
  t:SetHeight(1)
  t:SetPoint("LEFT", area, "BOTTOMLEFT", 0, GH * i / 3)
  t:SetPoint("RIGHT", area, "BOTTOMRIGHT", 0, GH * i / 3)
  grid[i] = t
end
local yLabels = {}
for i = 0, 3 do
  local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetPoint("RIGHT", area, "BOTTOMLEFT", -4, GH * i / 3)
  fs:SetJustifyH("RIGHT")
  yLabels[i] = fs
end
local xLeft = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
xLeft:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 0, -3)
local xRight = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
xRight:SetPoint("TOPRIGHT", area, "BOTTOMRIGHT", 0, -3)
local empty = area:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetWidth(GW - 20)

-- Stats line
local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stats:SetPoint("TOPLEFT", area, "BOTTOMLEFT", -30, -20)
stats:SetPoint("RIGHT", -14, 0)
stats:SetJustifyH("LEFT")
stats:SetSpacing(2)

-- Range buttons
local rangeBtns = {}
for i, days in ipairs(RANGES) do
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(40, 18)
  b:SetPoint("TOPLEFT", GX - 30 + (i - 1) * 44, -48)
  b:SetText(days .. "d")
  b:SetScript("OnClick", function()
    Krom_TheSearchForMoreMoneyDB.range = days
    if ns.redraw then ns.redraw() end
  end)
  rangeBtns[i] = b
end

-- Pools for line segments and hover points
local lines, dots = {}, {}
local function getLine(i)
  if not lines[i] then
    if area.CreateLine then
      local l = area:CreateLine(nil, "ARTWORK")
      l:SetThickness(2)
      l:SetColorTexture(0.2, 0.8, 1, 0.9)
      lines[i] = l
    else
      lines[i] = false
    end
  end
  return lines[i]
end
local function getDot(i)
  if not dots[i] then
    local b = CreateFrame("Button", nil, area)
    b:SetSize(10, 10)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetSize(5, 5)
    t:SetPoint("CENTER")
    t:SetColorTexture(1, 0.82, 0, 1)
    b.tex = t
    b:SetScript("OnEnter", function(self)
      self.tex:SetSize(8, 8)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(ns.dayLabel(self.day) .. (self.day == ns.today() and " (today)" or ""))
      GameTooltip:AddLine("Lowest: " .. money(self.price), 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.tex:SetSize(5, 5); GameTooltip:Hide() end)
    dots[i] = b
  end
  return dots[i]
end

local function itemNameIcon(itemID)
  local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, name, link, quality, _, _, _, _, _, _, tex = pcall(GetInfo, itemID)
  if not ok then name, tex = nil, nil end
  return name, tex, link
end

function ns.redraw()
  if not panel:IsShown() then return end
  local itemID = ns.focusID
  local range = opt("range", 30)
  for i, b in ipairs(rangeBtns) do
    if RANGES[i] == range then b:LockHighlight() else b:UnlockHighlight() end
  end
  for _, l in ipairs(lines) do if l then l:Hide() end end
  for _, d in ipairs(dots) do d:Hide() end

  if not itemID then
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    title:SetText("Krom The Search for More Money")
    subtitle:SetText("Search the Auction House or hover an item.")
    empty:SetText("No item selected")
    empty:Show()
    stats:SetText("")
    for i = 0, 3 do yLabels[i]:SetText("") end
    xLeft:SetText(""); xRight:SetText("")
    return
  end

  local name, tex = itemNameIcon(itemID)
  icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
  title:SetText(name or ("Item " .. itemID))

  local today = ns.today()
  local first = today - range + 1
  local pts = ns.history(itemID, first)
  local all = ns.history(itemID)
  subtitle:SetText(("%d days of data, %d in this range"):format(#all, #pts))

  if #pts == 0 then
    empty:SetText(#all > 0 and "No prices in this range - try a longer one." or "No prices recorded yet.\nSearch for it in the Auction House.")
    empty:Show()
    stats:SetText("")
    for i = 0, 3 do yLabels[i]:SetText("") end
    xLeft:SetText(ns.dayLabel(first)); xRight:SetText("today")
    return
  end
  empty:Hide()

  local lo, hi, sum = math.huge, 0, 0
  for _, p in ipairs(pts) do
    lo = math.min(lo, p[2]); hi = math.max(hi, p[2]); sum = sum + p[2]
  end
  local pad = math.max((hi - lo) * 0.12, hi * 0.05, 1)
  local ymin, ymax = math.max(0, lo - pad), hi + pad
  for i = 0, 3 do yLabels[i]:SetText(money(ymin + (ymax - ymin) * i / 3)) end
  xLeft:SetText(ns.dayLabel(first)); xRight:SetText("today")

  local function pos(day, price)
    local x = (range > 1) and ((day - first) / (range - 1)) * GW or GW / 2
    local y = (price - ymin) / (ymax - ymin) * GH
    return x, y
  end
  local px, py
  for i, p in ipairs(pts) do
    local x, y = pos(p[1], p[2])
    local d = getDot(i)
    d:ClearAllPoints()
    d:SetPoint("CENTER", area, "BOTTOMLEFT", x, y)
    d.day, d.price = p[1], p[2]
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
  local age = today - latest[1]
  stats:SetText(("Latest: |cffffffff%s|r %s\nAverage: |cffffffff%s|r   Low: |cffffffff%s|r   High: |cffffffff%s|r%s"):format(
    money(latest[2]), age == 0 and "(today)" or ("(" .. age .. "d ago)"),
    money(avg), money(lo), money(hi), change))
end

-- Docking: sit beside the AH while it's open.
local function dock()
  local ah = ns.ahFrame()
  panel:ClearAllPoints()
  if ah and ah:IsShown() then
    panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
    panel.docked = true
  else
    panel:SetPoint("CENTER")
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
