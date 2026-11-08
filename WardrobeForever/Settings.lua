local addonName, ns = ...

-- WardrobeForever's page in the game's options window. There is nothing to
-- set: the page is there so the addon shows in the AddOns list, and says
-- what hovering a slot does. It loads apart from WardrobeForever.lua, so the
-- page is there even on a client where the hovering has nothing to work with.

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
    title:SetText("WardrobeForever")

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
        "Hover a slot on the character sheet to see everything else you could "
        .. "wear there, and click one to put it on. It is the game's own list, "
        .. "the one Alt opens, opened by resting the mouse on a slot that has "
        .. "something to change to. It closes once the mouse has left the slot "
        .. "and the list. Alt, and the arrows that pin a list open, work as "
        .. "they always did."
    )
    Panel.about = about
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "WardrobeForever"
    Panel.panel = panel

    panel:SetScript("OnShow", ensureBuilt)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "WardrobeForever")
    Settings.RegisterAddOnCategory(category)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
