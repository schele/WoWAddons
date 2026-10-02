local addonName, ns = ...

-- FishScale's page in the game's options window: the switches /fs has, as
-- checkboxes, and the fishing key as a button that takes the next key pressed.

local PADDING = 16
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line below it.
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 400
local INDENT = PADDING + 30 -- under a checkbox's label, not its box

local Panel = {}
ns.SettingsPanel = Panel

local panel, category, built

-- True while the key button is waiting for a key.
local capturing = false

--- Let keys we are not interested in carry on to the rest of the UI. A frame
-- with an OnKeyDown script eats every key unless it says otherwise, and one
-- left eating them leaves the player unable to move or press Escape.
local function passKeysThrough(frame, pass)
    if frame.SetPropagateKeyboardInput then
        frame:SetPropagateKeyboardInput(pass and true or false)
    end
end

--- The binding a key press makes with the modifiers held, in the order WoW
-- writes them. Nil for a key that is not a binding by itself: Escape, or a
-- modifier pressed on its own while the player reaches for the rest. A bare
-- key is fine here, unlike on ForeverPanel's chat keys: F is the default.
local function combination(key)
    if not key or key == "ESCAPE" or key == "UNKNOWN" then
        return nil
    end
    if key:match("^[LR]CTRL$") or key:match("^[LR]SHIFT$") or key:match("^[LR]ALT$") then
        return nil
    end

    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end
    return prefix .. key
end

local function stopCapture()
    if not capturing then
        return
    end
    capturing = false
    Panel.key:EnableKeyboard(false)
    passKeysThrough(Panel.key, true)
    Panel.key:SetText(ns.db.fishing.key)
end

local function addKeyButton(y)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", INDENT, y - 4)
    label:SetText("Fishing key")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", INDENT + 90, y)
    button:SetSize(120, 22)
    button:EnableKeyboard(false)
    passKeysThrough(button, true)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", button, "RIGHT", 8, 0)
    hint:SetText("Click, then press the key.")

    button:SetScript("OnClick", function(self)
        capturing = true
        self:SetText("Press a key")
        self:EnableKeyboard(true)
        passKeysThrough(self, false)
    end)

    button:SetScript("OnKeyDown", function(self, key)
        if not capturing then
            passKeysThrough(self, true)
            return
        end
        if key == "ESCAPE" then
            stopCapture()
            return
        end
        local binding = combination(key)
        if not binding then
            return -- a modifier on its own: keep waiting for the rest
        end
        stopCapture()
        ns.Fishing.SetKey(binding)
    end)

    return button
end

local function addCheckbox(text, y, indent, onClick)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", indent, y)

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

--- Show what is saved. Safe to call before the page is built: every setter
-- in Fishing.lua calls it, from a command as much as from here.
function Panel.Refresh()
    if not built then
        return
    end
    local db = ns.db.fishing
    Panel.enabled:SetChecked(db.enabled)
    Panel.withoutPole:SetChecked(db.withoutPole)
    Panel.autoLoot:SetChecked(db.autoLoot)
    Panel.minimap:SetChecked(not ns.db.minimap.hide)
    if not capturing then
        Panel.key:SetText(db.key)
    end
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- The minimap icon, not the AddOns list one: that carries a square tile,
    -- which on a dark panel reads as a sticker pasted on.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\minimap")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("FishScale")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "One key for the whole fishing loop: it casts, picks up the bobber, and "
        .. "waits while you loot. Never in combat: when a fight starts, the key "
        .. "goes back to its usual job."
    )

    local y = -PADDING - ROW_HEIGHT * 2 - 12

    Panel.enabled = addCheckbox("Take the fishing key while a pole is equipped", y, PADDING, function(value)
        ns.Fishing.SetEnabled(value)
    end)
    y = y - ROW_HEIGHT

    Panel.key = addKeyButton(y)
    y = y - ROW_HEIGHT

    Panel.withoutPole = addCheckbox("Take it without a fishing pole too", y, PADDING, function(value)
        ns.Fishing.SetWithoutPole(value)
    end)
    y = y - ROW_HEIGHT

    Panel.autoLoot = addCheckbox("Turn auto loot on while fishing", y, PADDING, function(value)
        ns.Fishing.SetAutoLoot(value)
    end)
    y = y - ROW_HEIGHT

    -- Stored as "hide", shown as "Show": the box is ticked while it shows.
    Panel.minimap = addCheckbox("Show the minimap button", y, PADDING, function(value)
        ns.MinimapButton.SetHidden(not value)
    end)

    Panel.Refresh()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "FishScale"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)
    -- A key button left listening would keep the keyboard after the page is
    -- gone.
    panel:SetScript("OnHide", stopCapture)

    category = Settings.RegisterCanvasLayoutCategory(panel, "FishScale")
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
        ns.Print("This client has no settings panel. Use /fs for commands.")
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

--- Close the options window if it is showing this page; otherwise open it
-- here, which also turns it over from another addon's page. Both shown is the
-- test: the window keeps this frame hidden while any other page is up.
function ns.ToggleSettings()
    if panel and panel:IsShown() and SettingsPanel and SettingsPanel:IsShown() then
        if HideUIPanel then
            HideUIPanel(SettingsPanel)
        else
            SettingsPanel:Hide()
        end
        return
    end
    ns.OpenSettings()
end

ns.RegisterCommand("settings", "Open the settings page", function()
    ns.OpenSettings()
end)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
