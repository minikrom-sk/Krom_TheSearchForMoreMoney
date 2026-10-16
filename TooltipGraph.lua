-- Krom The Search for More Money - mini price graph attached to item tooltips.
--
-- Hover any item (bags, bank, chat links...) and a small panel hangs off the
-- tooltip: the last 7 days of market value, the vendor price as a copper
-- floor, and listed volume as faint bars. Headline: today's price and how
-- many times the vendor price it is - the "is this worth posting?" glance.
-- Options: on/off, and where it sits (auto = below, or above if no room).

local ADDON, ns = ...
local opt, money = ns.opt, ns.money

local DAYS, W_MIN, H = 7, 220, 106
local GX, GTOP, GBOT = 8, 36, 18 -- graph inset: left/right, top, bottom
local BLUE = { 0.2, 0.8, 1 }
local COPPER = { 0.93, 0.55, 0.25 }
local VOLC = { 0.62, 0.5, 0.95 }

local f = CreateFrame("Frame", "Krom_TheSearchForMoreMoneyTipGraph", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(W_MIN, H)
f:SetFrameStrata("TOOLTIP")
f:SetBackdrop({
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 14,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
f:SetBackdropColor(0.03, 0.03, 0.05, 0.92)
f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
f:Hide()
ns.tipGraph = f

local head = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
head:SetPoint("TOPLEFT", 8, -7)
head:SetJustifyH("LEFT")
local ratioText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ratioText:SetPoint("TOPRIGHT", -8, -7)
ratioText:SetJustifyH("RIGHT")
-- the verdict gets its own line so long ones never collide
local verdict = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
verdict:SetPoint("TOPLEFT", 8, -20)
verdict:SetPoint("RIGHT", -8, 0)
verdict:SetJustifyH("LEFT")
verdict:SetWordWrap(false)
local footL = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footL:SetPoint("BOTTOMLEFT", 8, 5)
local footR = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footR:SetPoint("BOTTOMRIGHT", -8, 5)

local area = CreateFrame("Frame", nil, f)
area:SetPoint("TOPLEFT", GX, -GTOP)
area:SetPoint("BOTTOMRIGHT", -GX, GBOT)

local vendorLine = area:CreateTexture(nil, "ARTWORK")
vendorLine:SetColorTexture(COPPER[1], COPPER[2], COPPER[3], 0.9)
vendorLine:SetHeight(1.5)

local lines, dots, bars = {}, {}, {}
local function getLine(i)
  if lines[i] == nil then
    if area.CreateLine then
      local l = area:CreateLine(nil, "OVERLAY")
      l:SetThickness(2)
      lines[i] = l
    else
      lines[i] = false
    end
  end
  return lines[i]
end
local function getDot(i)
  if not dots[i] then
    local t = area:CreateTexture(nil, "OVERLAY")
    t:SetSize(4, 4)
    t:SetColorTexture(1, 0.82, 0, 1)
    dots[i] = t
  end
  return dots[i]
end
local function getBar(i)
  if not bars[i] then
    local t = area:CreateTexture(nil, "BORDER")
    t:SetColorTexture(VOLC[1], VOLC[2], VOLC[3], 0.3)
    bars[i] = t
  end
  return bars[i]
end

local function vendorPrice(itemID)
  local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(GetInfo, itemID)
  return ok and sell and sell > 0 and sell or nil
end

local function bigNum(n)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  return tostring(n)
end

local function draw(itemID)
  local today = ns.today()
  local first = today - DAYS + 1
  local pts = ns.history(itemID, first)
  if #pts == 0 then return false end
  local vendor = vendorPrice(itemID)

  for _, l in pairs(lines) do if l then l:Hide() end end
  for _, d in pairs(dots) do d:Hide() end
  for _, b in pairs(bars) do b:Hide() end
  vendorLine:Hide()

  local w, h = area:GetWidth(), area:GetHeight()
  if not w or w <= 0 then w, h = W_MIN - 2 * GX, H - GTOP - GBOT end

  local lo, hi = math.huge, 0
  for _, p in ipairs(pts) do lo = math.min(lo, p[2]); hi = math.max(hi, p[2]) end
  if vendor then lo = math.min(lo, vendor); hi = math.max(hi, vendor) end
  local pad = math.max((hi - lo) * 0.12, 1)
  local ymin, ymax = math.max(0, lo - pad), hi + pad
  local function xOf(dayf) return (dayf - first) / DAYS * w end
  local function yOf(p) return (p - ymin) / (ymax - ymin) * h end

  -- volume bars (bottom 35%)
  local vmax, vols = 0, {}
  for d = first, today do
    local v = ns.volume(itemID, d)
    if v then vols[d] = v; vmax = math.max(vmax, v) end
  end
  local bi = 0
  for d, v in pairs(vols) do
    bi = bi + 1
    local b = getBar(bi)
    b:ClearAllPoints()
    b:SetPoint("BOTTOM", area, "BOTTOMLEFT", xOf(d + 0.5), 0)
    b:SetSize(math.max(2, w / DAYS * 0.6), math.max(1, v / vmax * h * 0.35))
    b:Show()
  end

  if vendor then
    vendorLine:ClearAllPoints()
    vendorLine:SetPoint("LEFT", area, "BOTTOMLEFT", 0, yOf(vendor))
    vendorLine:SetPoint("RIGHT", area, "BOTTOMRIGHT", 0, yOf(vendor))
    vendorLine:Show()
  end

  local px, py, pm
  for i, p in ipairs(pts) do
    local x, y = xOf(p[1] + 0.5), yOf(p[2])
    local d = getDot(i)
    d:ClearAllPoints()
    d:SetPoint("CENTER", area, "BOTTOMLEFT", x, y)
    d:Show()
    if px then
      local l = getLine(i - 1)
      if l then
        l:SetStartPoint("BOTTOMLEFT", area, px, py)
        l:SetEndPoint("BOTTOMLEFT", area, x, y)
        l:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], (pm and p[3]) and 0.95 or 0.45)
        l:Show()
      end
    end
    px, py, pm = x, y, p[3]
  end

  -- words: latest price, how it compares with vendor, volume today
  local latest = pts[#pts]
  local age = today - latest[1]
  local ratio = ""
  if vendor then
    local x = latest[2] / vendor
    ratio = ("|cffcccccc%sx vendor|r"):format(x >= 10 and ("%d"):format(x) or ("%.1f"):format(x))
  end
  ratioText:SetText(ratio)
  head:SetText(("|cff33ccff%s|r %s"):format(money(latest[2]), age == 0 and "today" or (age .. "d ago")))
  local col, word = ns.verdict(latest[2], vendor, itemID)
  verdict:SetText(col and (col .. word .. "|r") or "|cff999999no vendor price|r")
  footL:SetText(ns.dayLabel(first))
  local vNow = ns.volume(itemID, latest[1])
  footR:SetText((vNow and ("|cff9d80f2" .. bigNum(vNow) .. " listed|r  ") or "") .. "today")
  return true
end

-- Placement relative to the tooltip: auto / below / above / left / right.
local POSITIONS = { "auto", "below", "above", "right", "left" }
ns.TIP_POSITIONS = POSITIONS
local function place(tt)
  local pos = opt("tipGraphPos", "auto")
  f:ClearAllPoints()
  if pos == "auto" then
    local bottom = tt:GetBottom()
    pos = (bottom and bottom - H < 10) and "above" or "below"
  end
  if pos == "above" then
    f:SetPoint("BOTTOMLEFT", tt, "TOPLEFT", 0, 2)
  elseif pos == "right" then
    f:SetPoint("TOPLEFT", tt, "TOPRIGHT", 2, 0)
  elseif pos == "left" then
    f:SetPoint("TOPRIGHT", tt, "TOPLEFT", -2, 0)
  else
    f:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -2)
  end
end

-- Match the tooltip's width (it can grow as other addons add lines).
f:SetScript("OnUpdate", function(self)
  local tt = self.owner
  if not tt or not tt:IsShown() then self:Hide(); return end
  local pos = opt("tipGraphPos", "auto")
  local want = (pos == "left" or pos == "right") and W_MIN or math.max(W_MIN, tt:GetWidth() or W_MIN)
  if math.abs((self:GetWidth() or 0) - want) > 1 then
    self:SetWidth(want)
    if self.itemID then draw(self.itemID) end
  end
end)

function ns.onItemTooltip(tt, itemID)
  if tt ~= GameTooltip or not opt("tipGraph", true) then return end
  f.owner, f.itemID = tt, itemID
  place(tt)
  if draw(itemID) then f:Show() else f:Hide() end
end

GameTooltip:HookScript("OnHide", function() f:Hide(); f.itemID = nil end)
