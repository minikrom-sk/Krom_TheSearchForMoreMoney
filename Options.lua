-- Krom The Search for More Money - options panel, minimap button, slash commands.

local ADDON, ns = ...
local opt, say = ns.opt, ns.say

local function version()
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return getMeta and getMeta(ADDON, "Version") or "?"
end
ns.version = version

local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local ICON = "Interface\\Icons\\INV_Misc_Coin_02"

-- ---------------------------------------------------------------------------
-- Options panel
-- ---------------------------------------------------------------------------
local optionsCategory, optionsPanel
local refreshers = {}

local function buildOptions()
  local container = CreateFrame("Frame")
  container.name = "Krom The Search for More Money"
  local sf = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 0, -4)
  sf:SetPoint("BOTTOMRIGHT", -28, 4)
  local panel = CreateFrame("Frame", nil, sf)
  panel:SetSize(600, 900)
  sf:SetScrollChild(panel)

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Krom The Search for More Money")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("Version " .. version() .. " - Auction House price history, shared with your crew.")

  local y = -58
  local function heading(text)
    y = y - 14
    local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", 16, y)
    h:SetText(text)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("LEFT", h, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    y = y - 24
  end
  local function check(label, key, default, onChange)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 24, y)
    y = y - 28
    local txt = cb.Text or cb.text
    if type(txt) ~= "table" then
      txt = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      txt:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    end
    txt:SetText(label)
    cb:SetScript("OnClick", function(self)
      Krom_TheSearchForMoreMoneyDB[key] = self:GetChecked() and true or false
      if onChange then onChange() end
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(opt(key, default)) end
  end
  local function button(text, width, x, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end

  -- ---------------- Display ----------------
  heading("Display")
  check("Show the price graph beside the Auction House", "showWithAH", true)
  check("Graph follows items you hover while the Auction House is open", "followHover", true)
  check("Add a price line to item tooltips", "tooltip", true)

  -- ---------------- Data ----------------
  heading("Price data")
  local info = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", 28, y)
  info:SetJustifyH("LEFT")
  refreshers[#refreshers + 1] = function()
    local n, pts = ns.countItems(ns.realmKey("faction"))
    local nn, np = ns.countItems(ns.realmKey("neutral"))
    info:SetText(("%s: %d items, %d daily prices. Neutral AH: %d items, %d prices. Kept for %d days."):format(ns.realmKey("faction"), n, pts, nn, np, opt("keepDays", 90)))
  end
  y = y - 22
  button("Full scan now (AH open)", 190, 28, function() ns.startFullScan() end)
  button("Import from Auctionator", 190, 228, function() if ns.importAuctionator then ns.importAuctionator() end end)
  y = y - 34

  -- ---------------- Crew sync ----------------
  heading("Crew sync")
  check("Share my prices with my crew", "share", true)
  check("Accept prices from my crew", "receive", true)
  check("Chat message when crew prices arrive", "syncMessages", false)

  local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 28, y - 2)
  note:SetWidth(540)
  note:SetJustifyH("LEFT")
  note:SetText("Your crew: character names to sync with (add each alt too). Only these names are ever messaged or listened to. Everyone needs the addon and each other on their lists.")
  y = y - 36

  local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  box:SetSize(180, 22)
  box:SetPoint("TOPLEFT", 34, y)
  box:SetAutoFocus(false)
  local function addFromBox()
    local name = box:GetText()
    if ns.addFriend(name) then say(name .. " added to your crew.") end
    box:SetText("")
    box:ClearFocus()
    for _, f in ipairs(refreshers) do f() end
  end
  box:SetScript("OnEnterPressed", addFromBox)
  local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  addBtn:SetSize(70, 22)
  addBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)
  addBtn:SetText("Add")
  addBtn:SetScript("OnClick", addFromBox)
  local syncBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  syncBtn:SetSize(90, 22)
  syncBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
  syncBtn:SetText("Sync now")
  syncBtn:SetScript("OnClick", function() ns.syncNow(false) end)
  y = y - 30

  -- crew list: one row per name with a remove button
  local listTop = y
  local rows = {}
  local listHolder = CreateFrame("Frame", nil, panel)
  listHolder:SetPoint("TOPLEFT", 34, listTop)
  listHolder:SetSize(400, 20)
  local emptyTxt = listHolder:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  emptyTxt:SetPoint("TOPLEFT")
  emptyTxt:SetText("(nobody yet)")
  refreshers[#refreshers + 1] = function()
    local wl = Krom_TheSearchForMoreMoneyDB.whitelist
    for i, name in ipairs(wl) do
      local r = rows[i]
      if not r then
        r = CreateFrame("Frame", nil, listHolder)
        r:SetSize(260, 20)
        r.txt = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.txt:SetPoint("LEFT", 26, 0)
        r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
        r.del:SetSize(20, 20)
        r.del:SetPoint("LEFT")
        rows[i] = r
      end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
      r.txt:SetText(name)
      r.del:SetScript("OnClick", function()
        ns.removeFriend(name)
        for _, f in ipairs(refreshers) do f() end
      end)
      r:Show()
    end
    for i = #wl + 1, #rows do rows[i]:Hide() end
    emptyTxt:SetShown(#wl == 0)
    listHolder:SetHeight(math.max(20, #wl * 20))
  end
  y = y - 20 * 8 - 10 -- room for 8 names; the page scrolls if you have more

  -- ---------------- Help ----------------
  heading("Help")
  local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", 28, y)
  help:SetWidth(540)
  help:SetJustifyH("LEFT")
  help:SetSpacing(3)
  help:SetText("|cffffd100How it works|r  Every Auction House search you (or Auctionator) make records each item's\n" ..
               "lowest price for the day. Full scans record everything at once.\n\n" ..
               "|cffffd100Graph|r  Opens beside the Auction House. It follows what you search or hover; the lock\n" ..
               "keeps it on one item. Hover a point for the date and price.\n\n" ..
               "|cffffd100Commands|r  /money  /money <item link>  /money scan  /money sync  /money add Name  /money remove Name\n" ..
               "/money crew  /money import  /money options")
  y = y - 140

  panel:SetHeight(-y + 20)
  container:SetScript("OnSizeChanged", function(self) panel:SetWidth(math.max(400, (self:GetWidth() or 600) - 32)) end)
  container:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    optionsCategory = Settings.RegisterCanvasLayoutCategory(container, container.name)
    Settings.RegisterAddOnCategory(optionsCategory)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(container)
  end
  optionsPanel = container
end

local function openOptions()
  if optionsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(optionsCategory:GetID())
  elseif optionsPanel and InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(optionsPanel)
  end
end
ns.openOptions = openOptions

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------
local function buildMinimap()
  if not (LDB and DBIcon) then return end
  local launcher = LDB:NewDataObject(ADDON, {
    type = "launcher",
    text = "Krom The Search for More Money",
    icon = ICON,
    OnClick = function(_, button)
      if button == "RightButton" then openOptions()
      elseif ns.panel:IsShown() then ns.panel:Hide()
      else ns.showPanel() end
    end,
    OnTooltipShow = function(tt)
      local n, pts = ns.countItems()
      tt:AddLine("Krom The Search for More Money |cff999999" .. version() .. "|r")
      tt:AddLine(("%d items, %d daily prices"):format(n, pts), 1, 1, 1)
      tt:AddLine(" ")
      tt:AddLine("|cffffd100Left-click|r price graph", 0.8, 0.8, 0.8)
      tt:AddLine("|cffffd100Right-click|r options", 0.8, 0.8, 0.8)
    end,
  })
  DBIcon:Register(ADDON, launcher, Krom_TheSearchForMoreMoneyDB.minimap)
end

ns.onLogin = ns.onLogin or {}
table.insert(ns.onLogin, 1, function()
  local ok, err = pcall(buildOptions)
  if not ok then say("options error: " .. tostring(err)) end
  ok, err = pcall(buildMinimap)
  if not ok then say("minimap error: " .. tostring(err)) end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_KROMMOREMONEY1 = "/money"
SLASH_KROMMOREMONEY2 = "/moremoney"
SlashCmdList.KROMMOREMONEY = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  local link = msg:match("|Hitem:(%d+)")
  if link then
    ns.showPanel(tonumber(link))
  elseif cmd == "" then
    if ns.panel:IsShown() then ns.panel:Hide() else ns.showPanel() end
  elseif cmd == "scan" then
    ns.startFullScan()
  elseif cmd == "sync" then
    ns.syncNow(false)
  elseif cmd == "add" then
    if ns.addFriend(rest) then say(rest .. " added to your crew.") else say("usage: /money add Name (not already on the list)") end
  elseif cmd == "remove" then
    if ns.removeFriend(rest) then say(rest .. " removed.") else say(rest .. " isn't on your list.") end
  elseif cmd == "crew" then
    local wl = Krom_TheSearchForMoreMoneyDB.whitelist
    say(#wl > 0 and ("crew: " .. table.concat(wl, ", ")) or "your crew list is empty.")
    say(("this session: sent %d prices, received %d new."):format(ns.syncStats.sent, ns.syncStats.got))
  elseif cmd == "house" then
    local arg = rest:lower()
    if arg == "neutral" or arg == "faction" or arg == "auto" then
      if ns.setHouseOverride(arg ~= "auto" and arg or nil) then
        say(("this auctioneer now counts as %s. New prices go there."):format(ns.house == "neutral" and "a NEUTRAL auction house" or "your faction's auction house"))
        ns.redraw()
      else
        say("talk to an auctioneer first (open the AH), then /money house neutral|faction|auto.")
      end
    else
      local house, id, forced = ns.detectHouse()
      if id then
        say(("%s (%d) is %s%s. Change: /money house neutral|faction|auto"):format(UnitName("npc") or "this auctioneer", id,
          house == "neutral" and "a NEUTRAL auction house" or "your faction's auction house", forced and " (set by you)" or ""))
      else
        say("open the AH, then /money house to see which market it is.")
      end
    end
  elseif cmd == "import" then
    if ns.importAuctionator then ns.importAuctionator() end
  elseif cmd == "options" or cmd == "config" then
    openOptions()
  elseif tonumber(cmd) then
    ns.showPanel(tonumber(cmd))
  else
    say("commands: /money (graph), /money <item link>, /money scan, /money sync, /money add Name, /money remove Name, /money crew, /money import, /money house, /money options")
  end
end
