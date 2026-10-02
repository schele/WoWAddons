local addonName, ns = ...

-- The question RankUp asks before it changes a button: which spells have an
-- older rank on the bars, and whether to put the highest there instead.
--
-- A frame of our own rather than a StaticPopup. Blizzard's popups are shared
-- with its own code, which makes them a known route for taint, and taint is
-- the failure this client already has around its action bars.

local Popup = {}
ns.Popup = Popup

local WIDTH = 340
local LINE_HEIGHT = 18
-- Above the first line: the border and the title. Below the last: the
-- buttons and the border.
local TOP = 44
local BOTTOM = 52

local frame

local function lineText(group)
    return string.format("%s: %s -> %s (%s)",
        group.name,
        group.fromRank or "older rank",
        group.toRank or "highest rank",
        ns.Buttons(#group.slots))
end

local function line(index)
    local made = frame.lines[index]
    if not made then
        made = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        made:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -TOP - (index - 1) * LINE_HEIGHT)
        made:SetWidth(WIDTH - 48)
        made:SetJustifyH("LEFT")
        frame.lines[index] = made
    end
    return made
end

local function button(text, x, onClick)
    local made = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    made:SetSize(110, 24)
    made:SetPoint("BOTTOM", frame, "BOTTOM", x, 18)
    made:SetText(text)
    made:SetScript("OnClick", onClick)
    return made
end

local function create()
    frame = CreateFrame("Frame", "RankUpPopup", UIParent, "BackdropTemplate")
    Popup.frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -18)
    frame.title:SetText("RankUp: higher ranks for your bars")

    frame.lines = {}

    frame.upgrade = button("Upgrade", -60, function()
        if ns.Swap.Run() then
            Popup.Hide()
        end
    end)
    frame.notNow = button("Not now", 60, function()
        Popup.Hide()
    end)

    -- Escape closes it, as it does the game's own dialogs: the same as Not now.
    table.insert(UISpecialFrames, "RankUpPopup")
    frame:Hide()
end

--- Show `groups`, from Ranks.Outdated, replacing whatever was listed.
function Popup.Show(groups)
    if not frame then
        create()
    end

    for index, group in ipairs(groups) do
        local made = line(index)
        made:SetText(lineText(group))
        made:Show()
    end
    for index = #groups + 1, #frame.lines do
        frame.lines[index]:Hide()
    end

    frame:SetSize(WIDTH, TOP + #groups * LINE_HEIGHT + BOTTOM)
    Popup.SetCombat(InCombatLockdown())
    frame:Show()
end

function Popup.Hide()
    if frame then
        frame:Hide()
    end
end

function Popup.IsShown()
    return frame ~= nil and frame:IsShown()
end

--- The client refuses placing an action in combat, so Upgrade goes grey.
function Popup.SetCombat(inCombat)
    if frame then
        frame.upgrade:SetEnabled(not inCombat)
    end
end
