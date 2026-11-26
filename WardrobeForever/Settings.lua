local addonName, ns = ...

-- WardrobeForever's page in the game's options window: what hovering a slot
-- does, and a set to wear in each form. It loads apart from
-- WardrobeForever.lua, so the page is there even on a client where the
-- hovering has nothing to work with.

local PADDING = 16
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line below it.
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 400
-- Clear space between the description and the first row under it.
local HINT_GAP = 16
local LABEL_WIDTH = 140
local DROPDOWN_WIDTH = 200
local NONE = "Leave gear alone"

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
        .. "they always did.\n\n"
        .. "Pick a set for a form below, and shifting into the form puts it on; "
        .. "shifting out puts back what you had on. Make sets on the character "
        .. "sheet: the arrow at its top right, then the Equipment Manager tab. "
        .. "The game lets no addon change gear in a fight, so a shift in combat "
        .. "is worn when the fight ends; but click the stance bar to shift, and "
        .. "the set's weapons swap in the same click, even in a fight."
    )
    Panel.about = about

    local noForms = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    noForms:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -HINT_GAP)
    noForms:SetText("This character has no forms or stances.")
    Panel.noForms = noForms
end

-- One row per form: its name, and a dropdown of this character's sets.
-- Rows are kept and reused; the page fills them each time it opens, since
-- forms are learned and sets made while the game runs.
local rows = {}

local function formRow(index)
    if rows[index] then
        return rows[index]
    end
    local row = {}

    local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(DROPDOWN_WIDTH)
    dropdown:SetPoint("TOPLEFT", Panel.about, "BOTTOMLEFT", LABEL_WIDTH, -HINT_GAP - (index - 1) * ROW_HEIGHT)
    row.dropdown = dropdown

    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", dropdown, "LEFT", -LABEL_WIDTH, 0)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    row.label = label

    local function isSelected(setID)
        return (ns.Forms.GetSet(row.spellID) or false) == setID
    end
    local function setSelected(setID)
        ns.Forms.SetSet(row.spellID, setID or nil)
    end
    dropdown:SetupMenu(function(_, root)
        root:CreateRadio(NONE, isSelected, setSelected, false)
        for _, set in ipairs(ns.Forms.Sets()) do
            root:CreateRadio(set.name, isSelected, setSelected, set.setID)
        end
    end)

    rows[index] = row
    return row
end

local function refreshForms()
    local forms = ns.Forms and ns.Forms.List() or {}
    Panel.forms = {}
    for index, form in ipairs(forms) do
        local row = formRow(index)
        row.spellID = form.spellID
        row.label:SetText(form.name)
        row.label:Show()
        row.dropdown:Show()
        row.dropdown:GenerateMenu() -- the set picked may have changed elsewhere
        Panel.forms[index] = row
    end
    for index = #forms + 1, #rows do
        rows[index].label:Hide()
        rows[index].dropdown:Hide()
    end
    if #forms == 0 then
        Panel.noForms:Show()
    else
        Panel.noForms:Hide()
    end
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

    panel:SetScript("OnShow", function()
        ensureBuilt()
        refreshForms()
    end)

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
