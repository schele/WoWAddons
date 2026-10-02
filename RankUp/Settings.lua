local addonName, ns = ...

-- RankUp's page in the game's options window. There is nothing to set: the
-- page says what RankUp does, and has the look /rankup makes as a button.

local PADDING = 16
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line below it.
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 400

local Panel = {}
ns.SettingsPanel = Panel

local panel, built

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- logo, not icon: icon.tga carries the square tile the AddOns list needs,
    -- which on a dark panel reads as a sticker pasted on. logo.tga is the
    -- glyph alone, on transparency.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\logo")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("RankUp")

    -- From the .toc, so the two cannot drift apart.
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))
    Panel.version = version

    local about = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    about:SetWidth(PANEL_WIDTH - PADDING * 2)
    about:SetJustifyH("LEFT")
    about:SetText(
        "When you train a new rank of a spell, the game leaves the old rank on "
        .. "your action bars. RankUp offers to put your highest rank on every "
        .. "button that still holds an older one: at login, a moment after a "
        .. "trainer teaches you a spell, and when you type /rankup. Never during "
        .. "combat: it waits for the fight to end."
    )
    Panel.about = about

    -- The same look as /rankup: it says so in chat when there is nothing to do.
    -- Hung from the paragraph rather than placed at a height, so however many
    -- lines it wraps to, the button stays clear of it.
    local check = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    check:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -16)
    check:SetSize(160, 22)
    check:SetText("Check my bars now")
    check:SetScript("OnClick", function()
        ns.Look(true)
    end)
    Panel.check = check
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "RankUp"
    Panel.panel = panel

    panel:SetScript("OnShow", ensureBuilt)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "RankUp")
    Settings.RegisterAddOnCategory(category)
end

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
