local addonName, ns = ...

-- A mana bar under the player frame's rage bar, for the forms that swap mana out.
--
-- In Bear or Cat Form the player frame's power bar shows rage or energy, and
-- the mana a druid needs to shift back out and heal is nowhere on screen.
-- This draws it only then: in caster form Blizzard's own bar already shows
-- mana, and a second copy beside it would be noise.

local ManaBar = {}
ns.ManaBar = ManaBar

ns.AddDefaults({
    manaBar = {
        show = true,
    },
})

-- Enum.PowerType.Mana, named in case the enum is missing.
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

-- Used only when there is no power bar to take a size from.
local WIDTH = 120
local HEIGHT = 12

-- Where the player frame's own power bar -- the one showing rage in Bear
-- Form -- lives: nested on the rebuilt 10.x frame, a field before that, and
-- a global before that. Tried in order.
local POWER_BAR_PATHS = {
    "PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar",
    "manabar",
    "ManaBar",
}

-- The fill the rebuilt player frame gives its own mana bar.
local MANA_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana"

-- The border: a thin rounded edge, dark like the player frame's own, hung
-- slightly outside the bar so the fill keeps its full size.
local BORDER_FILE = "Interface\\Tooltips\\UI-Tooltip-Border"
local BORDER_SIZE = 8
local BORDER_OUTSET = 3
local BORDER_GAP = BORDER_OUTSET + 1

local guarded = ns.Guarded

--- Whether the client has an atlas by this name. Asked rather than assumed:
-- a missing atlas draws nothing at all, which would leave an empty bar.
local function hasAtlas(name)
    return guarded(function()
        return C_Texture.GetAtlasInfo(name) ~= nil
    end, false)
end

--- Frame the bar the way the player frame frames its own. On a frame of its
-- own, a level up, so the edge draws over the fill rather than under it.
-- Skipped on a client without BackdropTemplate: a bar without a border beats
-- no bar.
local function addBorder(target)
    local ok, border = pcall(CreateFrame, "Frame", nil, target, "BackdropTemplate")
    if not ok or not border or not border.SetBackdrop then
        return
    end

    border:SetPoint("TOPLEFT", -BORDER_OUTSET, BORDER_OUTSET)
    border:SetPoint("BOTTOMRIGHT", BORDER_OUTSET, -BORDER_OUTSET)
    guarded(function()
        border:SetFrameLevel(target:GetFrameLevel() + 1)
    end)
    border:SetBackdrop({ edgeFile = BORDER_FILE, edgeSize = BORDER_SIZE })
    border:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    target.border = border
end

local bar

local function walk(root, path)
    local value = root
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return type(value) == "table" and value.GetObjectType and value or nil
end

local function powerBar()
    for _, path in ipairs(POWER_BAR_PATHS) do
        local found = walk(PlayerFrame, path)
        if found then
            return found
        end
    end
    local global = _G.PlayerFrameManaBar
    return type(global) == "table" and global.GetObjectType and global or nil
end

--- Whether the bar has anything to add right now: turned on, the player has
-- a mana pool at all, and the power bar on screen is showing something else.
-- Comparisons stay inside the guard -- see ns.Guarded -- and anything the
-- client will not answer hides the bar rather than guessing.
function ManaBar.Wanted()
    if not (ns.db and ns.db.manaBar.show) then
        return false
    end

    local hasMana = guarded(function()
        return UnitPowerMax("player", MANA) > 0
    end, false)
    if not hasMana then
        return false
    end

    return guarded(function()
        return UnitPowerType("player") ~= MANA
    end, false)
end

--- Fill the bar from the player's mana. Values go straight to the widgets,
-- which accept numbers the client keeps secret; only the text is guarded,
-- and on a client that refuses to format one it is simply left blank.
function ManaBar.Update()
    if not bar then
        return
    end

    if not ManaBar.Wanted() then
        bar:Hide()
        return
    end

    local current = UnitPower("player", MANA)
    local maximum = UnitPowerMax("player", MANA)

    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)

    local ok = guarded(function()
        bar.text:SetText(string.format("%d / %d", current, maximum))
        return true
    end, false)
    if not ok then
        bar.text:SetText("")
    end

    bar:Show()
end

--- Build the bar under the power bar. Once, at login, when PlayerFrame exists.
function ManaBar.Create()
    if bar or not PlayerFrame then
        return bar
    end

    -- Parented to the player frame so it moves and hides with it. Not a
    -- secure frame, so showing it mid-fight -- shifting into Bear Form is
    -- usually mid-fight -- is allowed.
    bar = CreateFrame("StatusBar", "ClickHealManaBar", PlayerFrame)
    if hasAtlas(MANA_ATLAS) then
        -- The player frame's own mana fill, shading and all, so it matches
        -- the bars above it rather than sitting under them as a flat block.
        bar:SetStatusBarTexture(MANA_ATLAS)
        bar:SetStatusBarColor(1, 1, 1)
    else
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        -- Blizzard's own mana blue, from PowerBarColor["MANA"].
        bar:SetStatusBarColor(0, 0, 1)
    end

    -- Straight under the rage bar and exactly as wide, so it reads as a
    -- third bar of the frame. Under the portrait it sat behind the level
    -- badge, which hid everything but the numbers. Far enough down that the
    -- border below does not overlap the rage bar.
    local anchor = powerBar()
    if anchor then
        -- Pulled in by the border's outset on both sides, so the border's
        -- outer edge lines up with the rage bar's rather than poking past it
        -- into the portrait's frame on the left.
        bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", BORDER_OUTSET, -BORDER_GAP)
        bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -BORDER_OUTSET, -BORDER_GAP)
        bar:SetHeight(guarded(function()
            local height = anchor:GetHeight()
            return height > 0 and height or HEIGHT
        end, HEIGHT))
        -- Above the frame's own art, which is drawn over its bars.
        guarded(function()
            bar:SetFrameLevel(anchor:GetFrameLevel() + 2)
        end)
    else
        bar:SetSize(WIDTH, HEIGHT)
        bar:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 0, 0)
    end

    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.background:SetColorTexture(0, 0, 0, 0.6)

    addBorder(bar)

    -- The same font object as the health and mana numbers on the unit frames,
    -- so it follows whatever has restyled those.
    -- On the border's frame, which sits a level up, so the edge cannot cover
    -- the numbers.
    bar.text = (bar.border or bar):CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.text:SetPoint("CENTER", bar, "CENTER")

    bar:Hide()
    return bar
end

function ManaBar.Frame()
    return bar
end

ns.RegisterSetting({
    store = "manaBar",
    key = "show",
    type = "checkbox",
    name = "Show my mana in Bear and Cat Form",
    tooltip = "A mana bar under your rage or energy bar while it shows something other than mana.",
    onChange = function()
        ManaBar.Update()
    end,
})

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("UNIT_DISPLAYPOWER")
watcher:RegisterEvent("UNIT_POWER_UPDATE")
watcher:RegisterEvent("UNIT_POWER_FREQUENT")
watcher:RegisterEvent("UNIT_MAXPOWER")
watcher:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        ManaBar.Create()
    elseif unit ~= "player" then
        return
    end
    ManaBar.Update()
end)
