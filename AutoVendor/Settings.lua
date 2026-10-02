local addonName, ns = ...

-- AutoVendor's page in the game's options window: what it does, the switches
-- /av sell and /av repair flip, as checkboxes, and the keep list, each item
-- with a button that sells it again, the way /av unkeep does.

local PADDING = 16
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line below it.
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local ITEM_HEIGHT = 24
local PANEL_WIDTH = 400
local BUTTON_WIDTH = 90
-- The step from one box to the next: the boxes are 32 tall, so 2 of overlap
-- keeps them a ROW_HEIGHT apart.
local CHECK_STEP = 2
-- Under a section heading, before what it heads.
local LIST_GAP = 8

local Panel = {}
ns.SettingsPanel = Panel

-- One per kept item, made as the list first grows that long and kept after,
-- hidden when the list is shorter, so a refresh never leaves frames behind.
Panel.rows = {}

local panel, category, built

--- A checkbox hung under `above`, with its label beside it.
local function addCheckbox(text, above, x, y, onClick)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
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

--- The kept items, by name, so the page reads the same as /av list.
local function sortedKeep()
    local items = {}
    for itemID, name in pairs(ns.Keep.All()) do
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

local function addRow(index)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetSize(PANEL_WIDTH - PADDING * 2, ITEM_HEIGHT)
    frame:SetPoint("TOPLEFT", Panel.heading, "BOTTOMLEFT", 0, -LIST_GAP - (index - 1) * ITEM_HEIGHT)

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, 20)
    button:SetPoint("LEFT", frame, "LEFT", 0, 0)
    button:SetText("Sell again")

    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", button, "RIGHT", 8, 0)
    label:SetWidth(PANEL_WIDTH - PADDING * 2 - BUTTON_WIDTH - 8)
    label:SetJustifyH("LEFT")

    local row = { frame = frame, button = button, label = label }

    -- The row's item changes as the list does, so the click reads it then
    -- rather than holding the one it was made for.
    button:SetScript("OnClick", function()
        if row.itemID then
            ns.Keep.Remove(row.itemID)
        end
    end)

    Panel.rows[index] = row
    return row
end

--- Show what is saved. Safe to call before the page is built: Keep.lua calls
-- it on every change, from a command as much as from here.
function Panel.Refresh()
    if not built then
        return
    end

    Panel.sell:SetChecked(ns.db.sell)
    Panel.repair:SetChecked(ns.db.repair)

    local items = sortedKeep()
    for index, item in ipairs(items) do
        local row = Panel.rows[index] or addRow(index)
        row.itemID = item.itemID
        row.label:SetText(item.name)
        row.frame:Show()
    end
    for index = #items + 1, #Panel.rows do
        local row = Panel.rows[index]
        row.itemID = nil
        row.frame:Hide()
    end

    if #items == 0 then
        Panel.empty:Show()
    else
        Panel.empty:Hide()
    end
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- logo, not icon: icon.tga carries the square tile the AddOns list
    -- needs, which on a dark panel reads as a sticker pasted on. logo.tga is
    -- the same coins alone, on transparency.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\logo")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("AutoVendor")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    -- From here down, each part hangs from the one above it, so a
    -- description that wraps to another line pushes the rest down instead
    -- of running into it.
    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Open a merchant and your grey items are sold and your gear repaired, "
        .. "without a click. Nothing better than grey is ever sold, and nothing "
        .. "on the list below."
    )
    Panel.hint = hint

    -- The box's art has a few pixels of empty margin; pulled left by that
    -- much, the box itself lines up with the text above.
    Panel.sell = addCheckbox("Sell grey items", hint, 0, -16, function(value)
        ns.Vendor.SetSell(value)
    end)
    Panel.repair = addCheckbox("Repair my gear at merchants that can", Panel.sell, 0, CHECK_STEP, function(value)
        ns.Vendor.SetRepair(value)
    end)

    -- Back by the margin, and less of a gap than under the description: the
    -- box's empty margin below makes up the rest.
    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", Panel.repair, "BOTTOMLEFT", 0, -12)
    heading:SetText("Never sold")
    Panel.heading = heading

    -- In the first row's place, so the page has something there either way.
    local empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -LIST_GAP)
    empty:SetWidth(PANEL_WIDTH - PADDING * 2)
    empty:SetJustifyH("LEFT")
    empty:SetText("Nothing is kept. To keep an item, type /av keep and Shift-click it.")
    Panel.empty = empty

    Panel.Refresh()
end

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
