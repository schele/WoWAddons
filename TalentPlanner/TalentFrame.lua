local addonName, ns = ...

-- The plan in the game's own talent window: "x planned" over each talent, a
-- glow on the one the plan takes next, and a red edge on a talent holding
-- more points than the plan had by the time as many were spent. Beside them,
-- the next talent's name and, with the setting on, a Learn next button.
--
-- The window is Blizzard_TalentUI, loaded on demand: attached when it loads,
-- or at login when something loaded it first.

local TalentFrame = {}
ns.TalentFrame = TalentFrame

local TALENT_UI = "Blizzard_TalentUI"
-- The window's name on Classic, then on the clients after it.
local WINDOWS = { "TalentFrame", "PlayerTalentFrame" }
-- The game's functions that redraw the buttons, whichever this client has.
local UPDATES = { "TalentFrame_Update", "PlayerTalentFrame_Update", "PlayerTalentFrame_Refresh" }
local EDGE = 2

local window, overlays, nextLabel, learnButton
local buttons = {}

local function isLoaded(name)
    return ns.Guarded(function()
        if C_AddOns and C_AddOns.IsAddOnLoaded then
            return C_AddOns.IsAddOnLoaded(name) and true or false
        end
        return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
    end, false)
end

--- The tab the window shows: the game's own answer first, then the fields
-- its versions have kept it in.
local function selectedTab()
    local tab = ns.Guarded(function()
        return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(window)
    end)
    if type(tab) ~= "number" then
        tab = window.selectedTab or window.currentSelectedTab
    end
    return type(tab) == "number" and tab or 1
end

local function makeOverlay(talentButton)
    local made = CreateFrame("Frame", nil, talentButton)
    made:SetAllPoints(talentButton)

    made.label = made:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    made.label:SetPoint("BOTTOM", talentButton, "TOP", 0, 1)

    made.glow = made:CreateTexture(nil, "OVERLAY")
    made.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    made.glow:SetBlendMode("ADD")
    made.glow:SetVertexColor(0.3, 1, 0.3)
    made.glow:SetSize(68, 68)
    made.glow:SetPoint("CENTER", talentButton, "CENTER", 0, 0)

    -- Four thin red sides, one frame so they show and hide together.
    made.edge = CreateFrame("Frame", nil, made)
    made.edge:SetAllPoints(made)
    local sides = {
        { "TOPLEFT", "TOPRIGHT", nil, EDGE },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, EDGE },
        { "TOPLEFT", "BOTTOMLEFT", EDGE, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", EDGE, nil },
    }
    for _, side in ipairs(sides) do
        local texture = made.edge:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(1, 0.15, 0.15, 1)
        texture:SetPoint(side[1], made.edge, side[1], 0, 0)
        texture:SetPoint(side[2], made.edge, side[2], 0, 0)
        if side[3] then
            texture:SetWidth(side[3])
        else
            texture:SetHeight(side[4])
        end
    end
    return made
end

local function hideAll()
    for _, made in pairs(overlays or {}) do
        made.label:Hide()
        made.glow:Hide()
        made.edge:Hide()
    end
end

function TalentFrame.Refresh()
    if not window then
        return
    end
    learnButton:SetShown(ns.db.learn and type(LearnTalent) == "function")

    local trees = ns.db.overlay and ns.Trees.Read()
    if not trees then
        hideAll()
        nextLabel:Hide()
        return
    end

    local points = ns.Plans.Active().points
    local ranks = ns.Plan.RanksOf(trees)
    local over = ns.Plan.Over(points, ranks)
    local nextInfo = ns.Reminder.Next()
    local tab = selectedTab()

    for _, talentButton in ipairs(buttons) do
        local made = overlays[talentButton]
        local index = talentButton:GetID()
        local count = ns.Plan.Count(points, tab, index)
        made.label:SetText(count .. " planned")
        made.label:SetShown(count > 0)
        made.glow:SetShown(nextInfo ~= nil and nextInfo.tab == tab and nextInfo.index == index)
        made.edge:SetShown(over[tab] ~= nil and over[tab][index] == true)
    end

    if nextInfo then
        nextLabel:SetText("Next: " .. ns.Reminder.Describe(nextInfo))
        nextLabel:Show()
    else
        nextLabel:Hide()
    end
end

function TalentFrame.Attach()
    if window then
        return true
    end
    local name
    for _, candidate in ipairs(WINDOWS) do
        if _G[candidate] and _G[candidate .. "Talent1"] then
            name = candidate
            break
        end
    end
    if not name then
        return false
    end
    window = _G[name]
    overlays = {}

    local index = 1
    while _G[name .. "Talent" .. index] do
        local talentButton = _G[name .. "Talent" .. index]
        buttons[#buttons + 1] = talentButton
        overlays[talentButton] = makeOverlay(talentButton)
        index = index + 1
    end

    learnButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    learnButton:SetSize(90, 22)
    learnButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -44, -40)
    learnButton:SetText("Learn next")
    learnButton:SetScript("OnClick", function()
        local ok, why = ns.Reminder.LearnNext()
        if not ok then
            ns.Print(why)
        end
    end)

    nextLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nextLabel:SetPoint("RIGHT", learnButton, "LEFT", -6, 0)

    for _, update in ipairs(UPDATES) do
        if type(_G[update]) == "function" and hooksecurefunc then
            pcall(hooksecurefunc, update, TalentFrame.Refresh)
        end
    end
    if window.HookScript then
        window:HookScript("OnShow", TalentFrame.Refresh)
    end

    TalentFrame.Refresh()
    return true
end

function TalentFrame.Overlays()
    return overlays or {}
end

function TalentFrame.LearnButton()
    return learnButton
end

function TalentFrame.NextLabel()
    return nextLabel
end

ns.OnChange(TalentFrame.Refresh)

ns.OnLogin(function()
    if isLoaded(TALENT_UI) then
        TalentFrame.Attach()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == TALENT_UI and ns.db then
            TalentFrame.Attach()
        end
    else
        TalentFrame.Refresh()
    end
end)
