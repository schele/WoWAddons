local addonName, ns = ...

-- The Vendor deals tab on the auction house window, after Buy, Sell and
-- Auctions: a Scan button, and the deals Deals.lua found, the biggest
-- profit first. Clicking one looks it up in the Buy tab, so it is bought
-- with the game's own Buy Now and its confirmation; nothing here spends gold.
--
-- The tab is the game's own tab template, so it looks and behaves like the
-- others. Its display mode shows none of the game's parts, so choosing it
-- clears the window, and a hook on SetDisplayMode shows our page in their
-- place and hides it again when another tab is chosen.

local DealsTab = {}
ns.DealsTab = DealsTab

ns.AddDefaults({
    deals = true,
})

local TITLE = "Vendor deals"
local ROWS = 17
-- A line of the list, as tall as the game's own (AuctionHouseItemListLine).
local ROW_HEIGHT = 20
-- From the page's top: Scan and the slider, then the line saying how the
-- scan went (room for two), then the list. Each with clear space above it.
local SCAN_Y = -6
local SLIDER_Y = -9
local STATUS_Y = -46
local LIST_Y = -82
-- Inside the list, as the game's: a strip of column headings, the rows
-- under it, and the background starting under the strip.
local HEADER_HEIGHT = 19
local ROWS_Y = -(HEADER_HEIGHT + 6)
local SLIDER_WIDTH = 180
local PROGRESS_WIDTH = 420
local PROGRESS_HEIGHT = 18
local WHEEL_STEP = 3
local ICON = 18
-- Where each money column's right edge sits, from the row's left.
local BUYOUT_RIGHT, VALUE_RIGHT, PROFIT_RIGHT = 560, 680, 770
local GAIN = { 0.25, 1, 0.25 }
-- How far right of the page's left edge the top row starts, clear of the
-- portrait (the page itself sits 8 in from the window's edge).
local PORTRAIT_CLEAR = 56

-- A display mode of our own: a list of the window's parts to show, none.
local MODE = {}
DealsTab.MODE = MODE
DealsTab.ROWS = ROWS
DealsTab.offset = 0
DealsTab.rows = {}
DealsTab.headers = {}

local tab, panel, tabIndex

local function money(copper)
    return ns.Money(copper)
end

--- How long ago, in words: "just now", "7 min ago", "2 h ago"; "earlier"
-- when it is not known.
local function ago(scannedAt)
    if type(scannedAt) ~= "number" then
        return "earlier"
    end
    local seconds = math.max(0, time() - scannedAt)
    if seconds < 60 then
        return "just now"
    elseif seconds < 3600 then
        return string.format("%d min ago", math.floor(seconds / 60))
    end
    return string.format("%d h ago", math.floor(seconds / 3600))
end

--- When the next full scan should be allowed, as a time of day, or nil
-- when that is not known or has passed.
local function nextScan()
    local at = ns.Deals.NextScanAt()
    if not at or at <= time() then
        return nil
    end
    return date("%H:%M", at)
end

--- What the deals found come to: "2 sell to a merchant for at least 50c
-- more than their buyout, 1s 13c in all."
local function summary(deals, least)
    if #deals == 0 then
        return string.format("none sells to a merchant for at least %s more than its buyout.", least)
    end
    local total = 0
    for _, deal in ipairs(deals) do
        total = total + deal.profit
    end
    local sell = #deals == 1 and "sells to a merchant for at least %s more than its buyout"
        or "sell to a merchant for at least %s more than their buyout"
    return string.format("%d %s, %s in all.", #deals, sell:format(least), money(total))
end

local function statusText(current)
    local least = money(ns.Deals.MinProfit())
    if current.state == "scanning" then
        return string.format("Waiting for the auction house: %d s...",
            math.max(0, time() - (current.askedAt or time())))
    elseif current.state == "reading" then
        -- The progress bar says it; the line is hidden meanwhile.
        return ""
    elseif current.state == "stopped" then
        return string.format("Stopped after %d of %d auctions: %s", current.read, current.auctions,
            summary(current.deals, least))
    elseif current.state == "nothing" then
        local at = nextScan()
        if at then
            return "The auction house sent nothing back. It allows one full scan every 15 minutes: try again at "
                .. at .. "."
        end
        return "The auction house sent nothing back. It may allow one full scan every 15 minutes: "
            .. "try again in a few minutes."
    elseif current.state ~= "done" then
        return string.format("Scan the auction house for items a merchant pays at least %s more for than their buyout.",
            least)
    end

    -- The list the game kept, when no new one came: say so, and when.
    local before = ""
    if current.stale then
        local at = nextScan()
        before = "No new list came: the auction house allows one full scan every 15 minutes"
            .. (at and (", the next at " .. at) or "") .. ". "
    end

    local scanned = string.format("%d %s scanned %s", current.auctions,
        current.auctions == 1 and "auction" or "auctions", ago(current.scannedAt))
    return string.format("%s%s: %s", before, scanned, summary(current.deals, least))
end

--- Seconds until the auction house allows the next full scan; 0 when it
-- does now, or when it has never answered one.
local function untilNextScan()
    local at = ns.Deals.NextScanAt()
    if not at then
        return 0
    end
    return math.max(0, at - time())
end

--- Stop while a scan waits or is read. Otherwise Scan, or while the
-- auction house would ignore one, greyed out and counting down to when it
-- will not: "Scan in 14:59".
function DealsTab.UpdateScanButton()
    local scan = DealsTab.scan
    if not scan then
        return
    end
    if ns.Deals.Busy() then
        scan:SetText("Stop")
        scan:SetEnabled(true)
        return
    end
    local left = untilNextScan()
    if left > 0 then
        scan:SetText(string.format("Scan in %d:%02d", math.floor(left / 60), left % 60))
        scan:SetEnabled(false)
    else
        scan:SetText("Scan")
        scan:SetEnabled(true)
    end
end

--- The progress bar while the auctions are read, in place of the line.
local function showProgress(current)
    local reading = current.state == "reading"
    DealsTab.progress:SetShown(reading)
    DealsTab.status:SetShown(not reading)
    if not reading then
        return
    end
    local total = math.max(1, current.auctions)
    DealsTab.progress:SetMinMaxValues(0, total)
    DealsTab.progress:SetValue(current.read)
    DealsTab.progressText:SetText(string.format("Reading the auctions: %d%%",
        math.floor(current.read / total * 100)))
end

--- Look a deal up in the Buy tab, by the item's own name: a name with a
-- suffix ("of Arcane Protection") is listed under the plain one there.
function DealsTab.Look(deal)
    local frame = AuctionHouseFrame
    if not (frame and frame.SearchBar) then
        return
    end
    if AuctionHouseFrameDisplayMode then
        frame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
    end
    frame.SearchBar:SetSearchText(ns.ItemName(deal.itemID) or deal.name)
    frame.SearchBar:StartSearch()
end

local function drawRow(row, deal)
    row.deal = deal
    row.icon:SetTexture(deal.icon)
    local name = ns.Deals.NameOf(deal)
    row.name:SetText(deal.count > 1 and string.format("%s x%d", name, deal.count) or name)
    local color = ns.ItemColor(deal.itemID)
    row.name:SetTextColor(color[1], color[2], color[3])
    row.buyout:SetText(money(deal.buyout))
    row.value:SetText(money(deal.value))
    row.profit:SetText(money(deal.profit))
    row:Show()
end

function DealsTab.Refresh()
    if not (panel and panel:IsShown()) then
        return
    end
    local current = ns.Deals.Current()
    local deals = current.deals
    DealsTab.offset = math.max(0, math.min(DealsTab.offset, #deals - ROWS))

    DealsTab.status:SetText(statusText(current))
    showProgress(current)
    DealsTab.UpdateScanButton()
    DealsTab.SyncSlider()

    for index = 1, ROWS do
        local deal = deals[DealsTab.offset + index]
        if deal then
            drawRow(DealsTab.rows[index], deal)
        else
            DealsTab.rows[index].deal = nil
            DealsTab.rows[index]:Hide()
        end
    end

    if #deals > ROWS then
        DealsTab.footer:SetText(string.format("%d-%d of %d. Scroll for more.",
            DealsTab.offset + 1, math.min(#deals, DealsTab.offset + ROWS), #deals))
    else
        DealsTab.footer:SetText("")
    end
end

--- A line of the list, striped by turns and lit under the mouse with the
-- game's own art for its lists.
local function makeRow(index)
    local list = DealsTab.list
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 4, ROWS_Y - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT", -4, 0)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(row)
    row.stripe:SetAtlas(index % 2 == 1 and "auctionhouse-rowstripe-1" or "auctionhouse-rowstripe-2")
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetAtlas("auctionhouse-ui-row-highlight")
    row.highlight:SetBlendMode("ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(BUYOUT_RIGHT - 160 - ICON)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    local function column(right)
        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("RIGHT", row, "LEFT", right, 0)
        text:SetJustifyH("RIGHT")
        return text
    end
    row.buyout = column(BUYOUT_RIGHT)
    row.value = column(VALUE_RIGHT)
    row.profit = column(PROFIT_RIGHT)
    row.profit:SetTextColor(GAIN[1], GAIN[2], GAIN[3])

    row:SetScript("OnClick", function(self)
        if self.deal then
            DealsTab.Look(self.deal)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local deal = self.deal
        if not (deal and GameTooltip) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if deal.link and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink(deal.link)
        elseif GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(deal.itemID)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", ns.HideItemTooltip)

    row:Hide()
    return row
end

local LIST_ART = "auctionhouse-background-index"
local LIST_ART_CLASSIC = "Interface\\FrameGeneral\\UI-Background-Marble"

local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

--- The list, drawn as the game draws its Auctions tab's list
-- (AuctionHouseBackgroundTemplate with the index art): that background
-- under a strip for the headings, in the inset border. The parts are put
-- together here rather than through the template, which reads its art the
-- moment it is made, before it could be told which. A client without the
-- art gets the classic marble the template falls back to.
local function buildList()
    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", -4, LIST_Y)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 3, 0)

    local background = list:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -HEADER_HEIGHT - 3)
    background:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -3, 3)
    if hasAtlas(LIST_ART) then
        background:SetAtlas(LIST_ART)
    else
        background:SetTexture(LIST_ART_CLASSIC)
    end
    list.Background = background

    local ok, border = pcall(CreateFrame, "Frame", nil, list, "NineSlicePanelTemplate")
    if ok and border then
        border:SetAllPoints(list)
        if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
            pcall(NineSliceUtil.ApplyLayoutByName, border, "InsetFrameTemplate")
        end
        list.NineSlice = border
    end

    DealsTab.list = list
    return list
end

--- A column heading in the list's strip, from `left` to `right` along it:
-- the game's own heading box where it has one, else the words alone.
local function heading(text, left, right)
    local list = DealsTab.list
    local ok, box = pcall(CreateFrame, "Button", nil, list, "ColumnDisplayButtonShortTemplate")
    if ok and box then
        box:SetSize(right - left, HEADER_HEIGHT)
        box:SetPoint("TOPLEFT", list, "TOPLEFT", 4 + left, -1)
        box:SetText(text)
        box:EnableMouse(false)
    else
        box = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        box:SetPoint("LEFT", list, "TOPLEFT", 10 + left, -HEADER_HEIGHT / 2)
        box:SetText(text)
    end
    table.insert(DealsTab.headers, box)
    return box
end

-- While the slider is being set to the saved value, so that is not taken
-- for the player moving it.
local syncing = false

--- Put the slider on the saved least profit, and name it.
function DealsTab.SyncSlider()
    local slider = DealsTab.minProfit
    if not slider then
        return
    end
    local least = ns.Deals.MinProfit()
    syncing = true
    slider:SetValue(ns.Deals.StepOf(least))
    syncing = false
    DealsTab.minProfitLabel:SetText("Least profit: " .. money(least))
end

--- The least profit, as a slider in steps from any profit up to a gold.
-- Moving it filters the deals found at once; no new scan.
local function buildSlider()
    local steps = ns.Deals.STEPS
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetWidth(SLIDER_WIDTH)
    slider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, SLIDER_Y)
    slider:SetMinMaxValues(1, #steps)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    -- The template's own labels: its ends as money, and no name above it,
    -- since the label to its left says what it is.
    if slider.Low and slider.Low.SetText then
        slider.Low:SetText(money(steps[1]))
    end
    if slider.High and slider.High.SetText then
        slider.High:SetText(money(steps[#steps]))
    end
    if slider.Text and slider.Text.SetText then
        slider.Text:SetText("")
    end

    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("RIGHT", slider, "LEFT", -14, 0)
    label:SetJustifyH("RIGHT")
    DealsTab.minProfitLabel = label

    slider:SetScript("OnValueChanged", function(_, value)
        if syncing then
            return
        end
        local copper = steps[math.max(1, math.min(#steps, math.floor(value + 0.5)))]
        label:SetText("Least profit: " .. money(copper))
        if copper ~= ns.Deals.MinProfit() then
            ns.Deals.SetMinProfit(copper)
        end
    end)
    DealsTab.minProfit = slider
end

local function buildPanel(frame)
    panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 30)
    panel:Hide()
    DealsTab.panel = panel

    -- Right of the window's portrait, which fills its top-left corner: the
    -- game's own tabs start their top row there too.
    local scan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scan:SetSize(124, 22) -- room for "Scan in 14:59"
    scan:SetPoint("TOPLEFT", panel, "TOPLEFT", PORTRAIT_CLEAR, SCAN_Y)
    scan:SetText("Scan")
    scan:SetScript("OnClick", function()
        if ns.Deals.Busy() then
            ns.Deals.Stop()
            return
        end
        local ok, why = ns.Deals.Scan()
        if not ok then
            ns.Print(why)
        end
    end)
    DealsTab.scan = scan

    buildSlider()

    -- On a line of its own under Scan: what the scan found can run long.
    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", PORTRAIT_CLEAR, STATUS_Y)
    status:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)
    DealsTab.status = status

    -- How far reading the auctions has got, where the line goes.
    local progress = CreateFrame("StatusBar", nil, panel)
    progress:SetSize(PROGRESS_WIDTH, PROGRESS_HEIGHT)
    progress:SetPoint("TOPLEFT", panel, "TOPLEFT", PORTRAIT_CLEAR, STATUS_Y)
    progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progress:SetStatusBarColor(0.9, 0.7, 0.1)
    progress:SetMinMaxValues(0, 1)
    progress:SetValue(0)
    local back = progress:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(progress)
    back:SetColorTexture(0, 0, 0, 0.6)
    local progressText = progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("CENTER", progress, "CENTER", 0, 0)
    progress:Hide()
    DealsTab.progress = progress
    DealsTab.progressText = progressText

    buildList()
    -- Each heading spans its column, the money ones ending where their
    -- amounts do.
    local COLUMN = 130
    heading("Item", 0, BUYOUT_RIGHT - COLUMN)
    heading("Buyout", BUYOUT_RIGHT - COLUMN, BUYOUT_RIGHT + 8)
    heading("Merchant pays", BUYOUT_RIGHT + 8, VALUE_RIGHT + 8)
    heading("Profit", VALUE_RIGHT + 8, PROFIT_RIGHT + 8)

    for index = 1, ROWS do
        DealsTab.rows[index] = makeRow(index)
    end

    -- Under the list, beside the window's money.
    local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    footer:SetPoint("TOPRIGHT", DealsTab.list, "BOTTOMRIGHT", -8, -8)
    footer:SetText("")
    DealsTab.footer = footer

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        DealsTab.offset = DealsTab.offset - delta * WHEEL_STEP
        local most = math.max(0, #ns.Deals.Current().deals - ROWS)
        DealsTab.offset = math.max(0, math.min(DealsTab.offset, most))
        DealsTab.Refresh()
    end)
    panel:SetScript("OnShow", DealsTab.Refresh)

    -- The countdown on the Scan button, a few times a second while the
    -- page is up: only the button, not the list.
    local sinceTick = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        sinceTick = sinceTick + (elapsed or 0)
        if sinceTick >= 0.25 then
            sinceTick = 0
            DealsTab.UpdateScanButton()
        end
    end)
end

-- Our mode: our page in the window's place, our tab picked, our title.
-- Any other: our page away.
local function onDisplayMode(frame, mode)
    local ours = mode == MODE
    panel:SetShown(ours)
    if ours then
        PanelTemplates_SetTab(frame, tabIndex)
        if frame.SetTitle then
            frame:SetTitle(TITLE)
        end
    end
end

--- Show the tab or hide it, as the switch says. Hidden while its page is
-- up, the window goes back to the Buy tab.
local function applySwitch()
    if not (tab and ns.db) then
        return
    end
    tab:SetShown(ns.db.deals and true or false)
    if not ns.db.deals and AuctionHouseFrame.displayMode == MODE and AuctionHouseFrameDisplayMode then
        AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
    end
end

local function create()
    local frame = AuctionHouseFrame
    if tab or not (frame and frame.Tabs and frame.SetDisplayMode and ns.Deals.Available()) then
        return
    end

    local last = frame.Tabs[#frame.Tabs]
    tab = CreateFrame("Button", "AuctionHouseFrameAutoVendorDealsTab", frame, "AuctionHouseFrameDisplayModeTabTemplate")
    tab.displayMode = MODE
    tab:SetText(TITLE)
    tab:SetPoint("LEFT", last, "RIGHT", -15, 0)
    tabIndex = #frame.Tabs
    PanelTemplates_SetNumTabs(frame, #frame.Tabs)
    DealsTab.tab = tab

    buildPanel(frame)
    hooksecurefunc(frame, "SetDisplayMode", onDisplayMode)
    applySwitch()
end

--- Have the tab at the auction house, or not; remembered.
function DealsTab.SetEnabled(value)
    ns.db.deals = value and true or false
    applySwitch()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

ns.Deals.OnChange(DealsTab.Refresh)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_AuctionHouseUI" then
        create()
    end
end)

-- After a /reload at the auctioneer, the client brings the auction house UI
-- back before this file runs, so its load event has already come and gone.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    create()
end

ns.OnLogin(applySwitch)

ns.RegisterCommand("deals", "a Vendor deals tab at the auction house, on or off", function()
    DealsTab.SetEnabled(not ns.db.deals)
    ns.Print("Vendor deals tab at the auction house: " .. (ns.db.deals and "on" or "off") .. ".")
end)
