local addonName, ns = ...

-- AutoVendor's page in the game's options window: what it does, the switches
-- /av sell and /av repair flip, as checkboxes, the keep list, each item with
-- a button that sells it again, the way /av unkeep does, and the junk list,
-- each item with a button that stops selling it, the way /av unjunk does.

local PADDING = 16
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line below it.
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local ITEM_HEIGHT = 24
-- A listed item's icon, beside its name: as tall as the row's button.
local ITEM_ICON = 20
local PANEL_WIDTH = 400
local BUTTON_WIDTH = 90
-- The step from one box to the next: the boxes are 32 tall, so 2 of overlap
-- keeps them a ROW_HEIGHT apart.
local CHECK_STEP = 2
-- Under the description, before the first switch.
local SWITCH_GAP = 16
-- Under a section heading, before what it heads.
local LIST_GAP = 8
-- Above a section heading, after what came before it.
local SECTION_GAP = 12
-- The least profit slider, under the Vendor deals box and in from it: its
-- label, the slider, and the template's labels for its two ends below it.
local SLIDER_INDENT = 30
local SLIDER_WIDTH = 200
local SLIDER_ENDS = 14
local SLIDER_ROW = 52

local Panel = {}
ns.SettingsPanel = Panel

-- One per listed item, made as a list first grows that long and kept after,
-- hidden when the list is shorter, so a refresh never leaves frames behind.
Panel.rows = {}
Panel.junkRows = {}

-- `content` is what everything on the page is made on: the scroll frame's
-- child, or the panel itself on a client without the scroll template.
local panel, content, category, built

-- The keep list and the junk list, once built.
local keepList, junkList

--- A checkbox hung under `above`, with its label beside it.
local function addCheckbox(text, above, x, y, onClick)
    local button = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", above, "BOTTOMLEFT", x, y)

    -- The label belongs to the template on some clients and not others, so
    -- write our own rather than reaching for button.Text and finding nil.
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", 4, 0)
    label:SetText(text)

    button:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return button
end

-- While the slider is being set to the saved value, so that is not taken
-- for the player moving it.
local syncing = false

local function leastProfitText(copper)
    return "Least profit for a vendor deal: " .. ns.Money(copper)
end

--- Put the slider on the saved least profit, and name it.
function Panel.SyncSlider()
    if not Panel.minProfit then
        return
    end
    local least = ns.Deals.MinProfit()
    syncing = true
    Panel.minProfit:SetValue(ns.Deals.StepOf(least))
    syncing = false
    Panel.minProfitLabel:SetText(leastProfitText(least))
end

--- The least profit a vendor deal must make, as on the auction house tab:
-- in steps from any profit up to a gold. Hung under the Vendor deals box.
local function buildSlider()
    local steps = ns.Deals.STEPS
    local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", Panel.deals, "BOTTOMLEFT", SLIDER_INDENT, -2)
    Panel.minProfitLabel = label

    local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    slider:SetWidth(SLIDER_WIDTH)
    slider:SetMinMaxValues(1, #steps)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    if slider.Low and slider.Low.SetText then
        slider.Low:SetText(ns.Money(steps[1]))
    end
    if slider.High and slider.High.SetText then
        slider.High:SetText(ns.Money(steps[#steps]))
    end
    if slider.Text and slider.Text.SetText then
        slider.Text:SetText("")
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if syncing then
            return
        end
        local copper = steps[math.max(1, math.min(#steps, math.floor(value + 0.5)))]
        label:SetText(leastProfitText(copper))
        if copper ~= ns.Deals.MinProfit() then
            ns.Deals.SetMinProfit(copper)
        end
    end)
    Panel.minProfit = slider
end

--- A list's items, by name, so the page reads the same as /av list.
local function sorted(list)
    local items = {}
    for itemID, name in pairs(list) do
        items[#items + 1] = { itemID = itemID, name = name }
    end
    table.sort(items, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.itemID < b.itemID
    end)
    return items
end

--- A list on the page: its heading, the words shown while it is empty, and
-- a row per item with a button that takes the item off (`remove`).
local function makeList(headingText, emptyText, buttonText, remove, rows)
    local list = { rows = rows, buttonText = buttonText, remove = remove }

    list.heading = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    list.heading:SetText(headingText)

    -- In the first row's place, so the page has something there either way.
    list.empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    list.empty:SetPoint("TOPLEFT", list.heading, "BOTTOMLEFT", 0, -LIST_GAP)
    list.empty:SetWidth(PANEL_WIDTH - PADDING * 2)
    list.empty:SetJustifyH("LEFT")
    list.empty:SetText(emptyText)
    return list
end

local function addRow(list, index)
    local frame = CreateFrame("Frame", nil, content)
    frame:SetSize(PANEL_WIDTH - PADDING * 2, ITEM_HEIGHT)
    frame:SetPoint("TOPLEFT", list.heading, "BOTTOMLEFT", 0, -LIST_GAP - (index - 1) * ITEM_HEIGHT)

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, 20)
    button:SetPoint("LEFT", frame, "LEFT", 0, 0)
    button:SetText(list.buttonText)

    -- The item as the bags show it, its icon and its name in its quality's
    -- colour, with its tooltip under the mouse.
    local itemWidth = PANEL_WIDTH - PADDING * 2 - BUTTON_WIDTH - 8
    local item = CreateFrame("Button", nil, frame)
    item:SetSize(itemWidth, ITEM_HEIGHT)
    item:SetPoint("LEFT", button, "RIGHT", 8, 0)
    item:SetScript("OnEnter", ns.ShowItemTooltip)
    item.UpdateTooltip = ns.ShowItemTooltip
    item:SetScript("OnLeave", ns.HideItemTooltip)

    local icon = item:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ITEM_ICON, ITEM_ICON)
    icon:SetPoint("LEFT", item, "LEFT", 0, 0)

    local label = item:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetWidth(itemWidth - ITEM_ICON - 6)
    label:SetJustifyH("LEFT")

    local row = { frame = frame, button = button, item = item, icon = icon, label = label }

    -- The row's item changes as the list does, so the click reads it then
    -- rather than holding the one it was made for.
    button:SetScript("OnClick", function()
        if row.itemID then
            list.remove(row.itemID)
        end
    end)

    list.rows[index] = row
    return row
end

--- Show a list's items, or that it is empty. Remembers how many it shows,
-- for what hangs below it.
local function fillList(list, saved)
    local items = sorted(saved)
    for index, entry in ipairs(items) do
        local row = list.rows[index] or addRow(list, index)
        row.itemID = entry.itemID
        row.item.itemID = entry.itemID
        row.icon:SetTexture(ns.ItemIcon(entry.itemID))
        row.label:SetText(entry.name)
        -- Every time: a reused row still wears the last item's colour.
        local color = ns.ItemColor(entry.itemID)
        row.label:SetTextColor(color[1], color[2], color[3])
        row.frame:Show()
    end
    for index = #items + 1, #list.rows do
        local row = list.rows[index]
        row.itemID = nil
        row.item.itemID = nil
        row.frame:Hide()
    end

    list.shown = #items
    if #items == 0 then
        list.empty:Show()
    else
        list.empty:Hide()
    end
end

--- The last thing a list shows: its bottom row, or its empty line.
local function lastOf(list)
    if list.shown > 0 then
        return list.rows[list.shown].frame
    end
    return list.empty
end

--- How tall a list stands, from the gap above its heading to its last line.
local function listHeight(list)
    local below = list.shown > 0 and list.shown * ITEM_HEIGHT or list.empty:GetStringHeight()
    return SECTION_GAP + list.heading:GetStringHeight() + LIST_GAP + below
end

--- The last thing on the page so far, for more to hang below.
function Panel.Bottom()
    return lastOf(junkList)
end

--- The page's full height, so the scroll frame knows how far it goes.
-- `gridHeight` is how tall the bag grid stands.
local function pageHeight(gridHeight)
    local top = PADDING + ROW_HEIGHT + Panel.hint:GetStringHeight()
    local switches = SWITCH_GAP + 4 * ROW_HEIGHT + CHECK_STEP + SLIDER_ROW
    local bags = SECTION_GAP + Panel.bagsHeading:GetStringHeight() + LIST_GAP + gridHeight
    return top + switches + listHeight(keepList) + listHeight(junkList) + bags + PADDING
end

--- Show what is saved. Safe to call before the page is built: the lists call
-- it on every change, from a command as much as from here.
function Panel.Refresh()
    if not built then
        return
    end

    -- A click in the bag grid lengthens the junk list above it, which would
    -- slide the grid down under the mouse. While the mouse is there, only
    -- grey out what was picked, and catch up once it leaves.
    if ns.Picker.Hovered() then
        Panel.waiting = true
        ns.Picker.MarkTaken()
        return
    end
    Panel.waiting = false

    Panel.sell:SetChecked(ns.db.sell)
    Panel.repair:SetChecked(ns.db.repair)
    Panel.undercut:SetChecked(ns.db.undercut)
    Panel.deals:SetChecked(ns.db.deals)
    Panel.SyncSlider()

    fillList(keepList, ns.Keep.All())
    fillList(junkList, ns.Junk.All())

    -- The junk list starts wherever the keep list ends, and the bags
    -- wherever the junk list ends.
    junkList.heading:ClearAllPoints()
    junkList.heading:SetPoint("TOPLEFT", lastOf(keepList), "BOTTOMLEFT", 0, -SECTION_GAP)
    Panel.bagsHeading:ClearAllPoints()
    Panel.bagsHeading:SetPoint("TOPLEFT", Panel.Bottom(), "BOTTOMLEFT", 0, -SECTION_GAP)

    content:SetHeight(pageHeight(ns.Picker.Refresh()))
end

--- The page scrolls: with both lists it can outgrow the options window. As
-- ForeverPanel's page does.
local function buildScroll()
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    if not (ok and scroll and scroll.SetScrollChild) then
        content = panel
        return
    end
    -- Room on the right for the template's scroll bar.
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
    -- The bar only while there is more than fits. The template's own
    -- scrollBarHideable is not honoured on every client, so this runs after
    -- its handler, which shows the bar greyed out.
    local function fitScrollBar()
        local bar = scroll.ScrollBar
        if bar and scroll.GetVerticalScrollRange then
            local needed = (scroll:GetVerticalScrollRange() or 0) > 0
            bar:SetShown(needed)
            if not needed and scroll.SetVerticalScroll then
                scroll:SetVerticalScroll(0)
            end
        end
    end
    scroll:HookScript("OnScrollRangeChanged", fitScrollBar)
    scroll:HookScript("OnShow", fitScrollBar)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_WIDTH, 1)
    scroll:SetScrollChild(content)
    Panel.scroll = scroll
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    buildScroll()
    Panel.content = content

    -- logo, not icon: icon.tga carries the square tile the AddOns list
    -- needs, which on a dark panel reads as a sticker pasted on. logo.tga is
    -- the same coins alone, on transparency.
    local logo = content:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\logo")
    Panel.logo = logo

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("AutoVendor")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    -- From here down, each part hangs from the one above it, so a
    -- description that wraps to another line pushes the rest down instead
    -- of running into it.
    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Open a merchant and your grey items, and anything on your junk list, "
        .. "are sold and your gear repaired, without a click. Nothing on the "
        .. "keep list is ever sold. At the auction house, a new auction asks "
        .. "one copper under the cheapest listing, and the Vendor deals tab "
        .. "finds auctions a merchant would pay more for than their buyout."
    )
    Panel.hint = hint

    -- The box's art has a few pixels of empty margin; pulled left by that
    -- much, the box itself lines up with the text above.
    Panel.sell = addCheckbox("Sell grey items and my junk list", hint, 0, -SWITCH_GAP, function(value)
        ns.Vendor.SetSell(value)
    end)
    Panel.repair = addCheckbox("Repair my gear at merchants that can", Panel.sell, 0, CHECK_STEP, function(value)
        ns.Vendor.SetRepair(value)
    end)
    Panel.undercut = addCheckbox("Post auctions one copper under the cheapest", Panel.repair, 0, CHECK_STEP, function(value)
        ns.Auction.SetUndercut(value)
    end)
    Panel.deals = addCheckbox("A Vendor deals tab at the auction house", Panel.undercut, 0, CHECK_STEP, function(value)
        ns.DealsTab.SetEnabled(value)
    end)
    buildSlider()

    keepList = makeList("Never sold",
        "Nothing is kept. To keep an item, type /av keep and Shift-click it.",
        "Sell again", function(itemID)
            ns.Keep.Remove(itemID)
        end, Panel.rows)
    -- Back by the margin, and less of a gap than under the description: the
    -- box's empty margin below makes up the rest.
    keepList.heading:SetPoint("TOPLEFT", Panel.minProfit, "BOTTOMLEFT", -SLIDER_INDENT, -SECTION_GAP - SLIDER_ENDS)
    Panel.heading = keepList.heading
    Panel.empty = keepList.empty

    junkList = makeList("Always sold",
        "Nothing is always sold. Click an item in your bags below to add it.",
        "Stop selling", function(itemID)
            ns.Junk.Remove(itemID)
        end, Panel.junkRows)
    Panel.junkHeading = junkList.heading
    Panel.junkEmpty = junkList.empty

    -- The bags, to pick more from.
    local bagsHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bagsHeading:SetText("In your bags (click to always sell)")
    Panel.bagsHeading = bagsHeading
    ns.Picker.Build(content, PANEL_WIDTH - PADDING * 2)
    ns.Picker.frame:SetPoint("TOPLEFT", bagsHeading, "BOTTOMLEFT", 0, -LIST_GAP)
    ns.Picker.OnLeft = function()
        if Panel.waiting then
            Panel.Refresh()
        end
    end

    Panel.Refresh()
end

-- Whether the page is on screen. IsVisible, not IsShown: the options window
-- leaves the page it showed last shown when it closes, inside itself.
local function onScreen()
    return built and panel ~= nil and panel:IsVisible()
end

-- An item's name and price come from the server the first time it is asked
-- about, and the answer arrives on its own, often many at once after a
-- login. One redraw for the lot, a moment after the first.
local redrawQueued = false
local function redrawSoon()
    if redrawQueued then
        return
    end
    redrawQueued = true
    C_Timer.After(0.1, function()
        redrawQueued = false
        if onScreen() then
            Panel.Refresh()
        end
    end)
end

-- The bag grid follows the bags and the item answers, but only while the
-- page is there to see it: reading every slot on every loot would be work
-- for nobody.
local bagWatcher = CreateFrame("Frame")
bagWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
bagWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
bagWatcher:SetScript("OnEvent", function(_, event)
    if not onScreen() then
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        redrawSoon()
    else
        Panel.Refresh()
    end
end)

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "AutoVendor"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "AutoVendor")
    Settings.RegisterAddOnCategory(category)
end

-- Whether the page on screen was opened from here rather than through the
-- game menu. Decides where closing it should leave the player.
local openedByUs = false

-- Armed while the client is closing a page we opened, so the game menu it
-- puts up on the way out can be turned away at the door.
local suppressGameMenu = false
local closeHooked = false

local function dismissGameMenu(frame)
    suppressGameMenu = false
    if HideUIPanel then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
end

local function watchForClose()
    if closeHooked or not SettingsPanel or not SettingsPanel.HookScript then
        return
    end
    closeHooked = true

    SettingsPanel:HookScript("OnHide", function()
        -- Opening the page from a command leaves the client queued to fall
        -- back to the game menu, which is not where the player came from.
        if not openedByUs then
            return
        end
        openedByUs = false
        suppressGameMenu = true

        -- Backstop, in case the menu is already up or has no OnShow to catch.
        C_Timer.After(0, function()
            if suppressGameMenu then
                if GameMenuFrame and GameMenuFrame:IsShown() then
                    dismissGameMenu(GameMenuFrame)
                end
                suppressGameMenu = false
            end
        end)
    end)

    -- Caught as it shows, so it never reaches the screen.
    if GameMenuFrame and GameMenuFrame.HookScript then
        GameMenuFrame:HookScript("OnShow", function(self)
            if suppressGameMenu then
                dismissGameMenu(self)
            end
        end)
    end
end

--- Open the page in the game's options window.
function ns.OpenSettings()
    if not category then
        ns.Print("This client has no settings panel. Use /av for commands.")
        return
    end

    watchForClose()
    openedByUs = true

    -- Build before showing, in case the client opens the category without
    -- firing OnShow on our canvas.
    ensureBuilt()

    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

ns.RegisterCommand("settings", "open the settings page", function()
    ns.OpenSettings()
end)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
