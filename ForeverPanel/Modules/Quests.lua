local addonName, ns = ...

-- Quest tracking: a box at the top of the quest log that untracks every quest,
-- keeping the tracker to the zone or dungeon you are in, and a switch for the
-- game's own automatic quest tracking, which WoW Forever's options lack.
--
-- WoW Forever only. Classic Era's quest log is another window, and its
-- C_QuestLog has none of the watch list calls used here, so on that client
-- nothing in this file is declared: no options, no commands, no frames.

if not (C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex and C_QuestLog.RemoveQuestWatch) then
    return
end

ns.AddDefaults({
    quests = {
        untrackBox = true,
        areaTrack = false,
    },
})

local Quests = {}
ns.Quests = Quests

--- "1 quest", "3 quests".
local function questCount(count)
    return string.format(count == 1 and "%d quest" or "%d quests", count)
end

--------------------------------------------------------------------------------
-- Untracking
--------------------------------------------------------------------------------

-- The tracker shows the quest watch list. Untracking a quest leaves it in the
-- quest log, as clearing its tick box there does.

--- How many quests are on the tracker.
function Quests.Count()
    return C_QuestLog.GetNumQuestWatches()
end

--- Whether the game lets the player untrack quests. Blizzard's quest log
-- asks the same before it clears a tick box: a character in the new player
-- experience may not.
function Quests.Allowed()
    if QuestUtil and QuestUtil.CanRemoveQuestWatch then
        return QuestUtil.CanRemoveQuestWatch() and true or false
    end
    return true
end

--- The tracked quests, read whole: the list closes up as quests leave it.
local function watchedQuests()
    local questIDs = {}
    for index = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        if questID then
            table.insert(questIDs, questID)
        end
    end
    return questIDs
end

--- Untrack every tracked quest. Returns how many were taken off.
function Quests.UntrackAll()
    if not Quests.Allowed() then
        return 0
    end
    local removed = 0
    for _, questID in ipairs(watchedQuests()) do
        if C_QuestLog.RemoveQuestWatch(questID) then
            removed = removed + 1
        end
    end
    return removed
end

--------------------------------------------------------------------------------
-- The untrack-all box
--------------------------------------------------------------------------------

-- A tick box at the top of the quest log, between the quest count and the
-- settings gear, drawn like the tick box on every quest below it. It is ticked
-- while any quest is tracked, and a click untracks them all.
--
-- That row is full, so the search box at its left gives up some width and the
-- quest count, anchored to it, moves left to make room. The quest log sizes
-- the search box itself each time it redraws (QuestLogQuests_ShowQuestCount,
-- Camelot's override), so it is narrowed again after every redraw.

local BOX_ART = "questlog-icon-ticksquare"
local TICK_ART = "questlog-icon-checkmark-yellow"
local BOX_SIZE = 14 -- the size of the quest log's own tick boxes
local NARROW_BY = 24 -- the box, and a gap each side
local GAP = 4 -- between the box and the gear

local narrowedTo -- the search box width this file last set
local hooked = false

local function searchBox()
    return QuestScrollFrame and QuestScrollFrame.SearchBox
end

--- Narrow the search box, once per width the quest log gives it.
local function narrowSearchBox()
    local box = searchBox()
    if not box or not (ns.db and ns.db.quests.untrackBox) then
        return
    end
    local width = box:GetWidth()
    if width == narrowedTo or width <= NARROW_BY then
        return
    end
    narrowedTo = width - NARROW_BY
    box:SetWidth(narrowedTo)
end

--- Give the search box back the width it was narrowed by.
local function widenSearchBox()
    local box = searchBox()
    if box and narrowedTo and box:GetWidth() == narrowedTo then
        box:SetWidth(narrowedTo + NARROW_BY)
    end
    narrowedTo = nil
end

local function showTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText("Untrack all quests", 1, 1, 1)
    local count = Quests.Count()
    if count == 0 then
        GameTooltip:AddLine("No quests are tracked.", nil, nil, nil, true)
    else
        local are = count == 1 and "is" or "are"
        GameTooltip:AddLine(string.format("%s %s tracked.", questCount(count), are), nil, nil, nil, true)
        GameTooltip:AddLine("Click to take them all off the tracker. They stay in your quest log.",
            nil, nil, nil, true)
    end
    GameTooltip:Show()
end

--- Tick the box while any quest is tracked; redraw the tooltip if it is up.
function Quests.RefreshBox()
    local button = Quests.box
    if not button then
        return
    end
    button.CheckMark:SetShown(Quests.Count() > 0)
    if GameTooltip:IsShown() and GameTooltip:GetOwner() == button then
        showTooltip(button)
    end
end

local function onClick()
    if Quests.Count() == 0 or not Quests.Allowed() then
        return
    end
    Quests.UntrackAll()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    Quests.RefreshBox()
end

--- Put the box in the quest log, once it exists.
local function attach()
    local scroll = QuestScrollFrame
    if Quests.box or not scroll or not scroll.SettingsDropdown then
        return
    end

    local button = CreateFrame("Button", nil, scroll)
    button:SetSize(BOX_SIZE, BOX_SIZE)
    button:SetHitRectInsets(-5, -5, -5, -5)
    button:SetPoint("RIGHT", scroll.SettingsDropdown, "LEFT", -GAP, 0)
    button:RegisterForClicks("LeftButtonUp")

    button.Box = button:CreateTexture(nil, "BACKGROUND")
    button.Box:SetAtlas(BOX_ART, true)
    button.Box:SetPoint("CENTER")

    button.CheckMark = button:CreateTexture(nil, "ARTWORK")
    button.CheckMark:SetAtlas(TICK_ART, true)
    button.CheckMark:SetPoint("CENTER", 1, 1)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas(BOX_ART, true)
    highlight:SetPoint("CENTER")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnShow", Quests.RefreshBox)
    button:SetScript("OnEvent", Quests.RefreshBox)
    button:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    Quests.box = button

    -- A hook on a global stays for the session, so it goes on once; with the
    -- box switched off it finds nothing to do.
    if not hooked and type(QuestLogQuests_ShowQuestCount) == "function" then
        hooked = true
        hooksecurefunc("QuestLogQuests_ShowQuestCount", narrowSearchBox)
    end
end

--- Show the box or take it away, as the setting says.
local function applyBox()
    if ns.db.quests.untrackBox then
        attach()
        if Quests.box then
            Quests.box:Show()
            Quests.RefreshBox()
        end
        narrowSearchBox()
    else
        if Quests.box then
            Quests.box:Hide()
        end
        widenSearchBox()
    end
end

--------------------------------------------------------------------------------
-- Tracking the quests of where you are
--------------------------------------------------------------------------------

-- On arriving in a zone or dungeon, the quests that belong there are tracked
-- and the rest untracked. After that the player's own ticks stand until the
-- next arrival, and a quest taken there is tracked too.
--
-- A quest belongs where the player is when:
--   - it sits under a quest log header with the zone's name (the log groups
--     quests by zone or dungeon: "Hillsbrad Foothills", "Gnomeregan"), or
--   - the game puts its objectives, or once done its turn-in, on the map the
--     player is on (GetQuestUiMapID): a Hillsbrad quest sending you to Arathi.
--
-- Not the quest log's own isOnMap: that follows whichever map the world map
-- last showed (QuestLogMixin:SyncQuestSystemWithCurrentMap), not the player.

local SETTLE = 1 -- seconds after arriving, for the zone's name and map to settle

--- Where the player is: the names a quest log header could carry
-- (`names`, lowercased, and `order` as given), and the maps (`maps`) from
-- the most detailed outward. A cave or building has a map of its own, so the
-- zone around it counts too; a dungeon or zone is as far as it goes.
function Quests.Here()
    local here = { names = {}, order = {}, maps = {} }
    local function addName(name)
        if type(name) == "string" and name ~= "" and not here.names[name:lower()] then
            here.names[name:lower()] = true
            table.insert(here.order, name)
        end
    end
    addName(GetRealZoneText())
    addName(GetZoneText())

    local mapID = C_Map.GetBestMapForUnit("player")
    local seen = {}
    while mapID and not seen[mapID] do
        seen[mapID] = true
        local info = C_Map.GetMapInfo(mapID)
        if not info then
            break
        end
        addName(info.name)
        table.insert(here.maps, mapID)
        if info.mapType ~= Enum.UIMapType.Micro then
            break
        end
        mapID = info.parentMapID
    end
    return here
end

local function questMap(questID)
    if type(GetQuestUiMapID) ~= "function" then
        return nil
    end
    return GetQuestUiMapID(questID)
end

--- The quests in the log that belong where the player is, in log order:
-- { questID, title, why = "header" or "objectives" }.
function Quests.QuestsHere(here)
    here = here or Quests.Here()
    local mapsHere = {}
    for _, mapID in ipairs(here.maps) do
        mapsHere[mapID] = true
    end

    local quests = {}
    local underHeaderHere = false
    for index = 1, (C_QuestLog.GetNumQuestLogEntries()) do
        local info = C_QuestLog.GetInfo(index)
        if info and info.isHeader then
            underHeaderHere = type(info.title) == "string" and here.names[info.title:lower()] or false
        elseif info and info.questID and info.questID ~= 0 then
            local why
            if underHeaderHere then
                why = "header"
            elseif mapsHere[questMap(info.questID)] then
                why = "objectives"
            end
            if why then
                table.insert(quests, { questID = info.questID, title = info.title, why = why })
            end
        end
    end
    return quests
end

local function isTracked(questID)
    return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

--- Track the quests that belong where the player is, and untrack the rest.
-- Does nothing while switched off, or while the game forbids untracking.
function Quests.SyncArea()
    if not ns.db.quests.areaTrack or not Quests.Allowed() then
        return
    end
    local quests = Quests.QuestsHere()
    local belongs = {}
    for _, quest in ipairs(quests) do
        belongs[quest.questID] = true
    end

    -- Untrack first: the tracker holds only so many.
    for _, questID in ipairs(watchedQuests()) do
        if not belongs[questID] then
            C_QuestLog.RemoveQuestWatch(questID)
        end
    end
    for _, quest in ipairs(quests) do
        if not isTracked(quest.questID) then
            C_QuestLog.AddQuestWatch(quest.questID)
        end
    end
end

-- An arrival not yet acted on. At login the watch list can be there before
-- the quest log is: with an empty log every tracked quest would look out of
-- place, so it waits for the log.
local pending = false
-- Quests just taken, waiting for the log to list them.
local accepted = {}

local function trySync()
    if not pending then
        return
    end
    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    if numQuests == 0 then
        return
    end
    pending = false
    Quests.SyncArea()
end

local function trackAccepted()
    if not next(accepted) then
        return
    end
    local belongs
    for questID in pairs(accepted) do
        if C_QuestLog.GetLogIndexForQuestID(questID) then
            accepted[questID] = nil
            if not belongs then
                belongs = {}
                for _, quest in ipairs(Quests.QuestsHere()) do
                    belongs[quest.questID] = true
                end
            end
            if belongs[questID] and not isTracked(questID) then
                C_QuestLog.AddQuestWatch(questID)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The game's automatic quest tracking
--------------------------------------------------------------------------------

-- While it is on, Blizzard's quest log and objective tracker track a quest
-- when it is taken (QUEST_ACCEPTED) and when an objective moves
-- (QUEST_WATCH_UPDATE), so untracked quests come back. It is a console
-- variable with no switch in WoW Forever's options; the game keeps it, so the
-- setting reads and writes it there rather than keeping a copy.
local AUTO_TRACK_CVAR = "autoQuestWatch"

--------------------------------------------------------------------------------
-- Settings and commands
--------------------------------------------------------------------------------

ns.RegisterSetting({
    store = "quests",
    key = "untrackBox",
    type = "checkbox",
    section = "quests",
    column = 2,
    name = "Untrack-all box in the quest log",
    tooltip = "A tick box between the quest count and the settings gear; one click untracks every quest.",
    onChange = applyBox,
})

ns.RegisterSetting({
    store = "quests",
    key = "areaTrack",
    type = "checkbox",
    section = "quests",
    column = 2,
    name = "Track only the quests where you are",
    tooltip = "Each time you arrive in a zone or dungeon, its quests are tracked and the rest untracked.",
    onChange = function(on)
        if on then
            Quests.SyncArea()
        end
    end,
})

ns.RegisterSetting({
    store = "quests",
    key = "gameAutoTrack",
    type = "checkbox",
    section = "quests",
    column = 2,
    name = "Automatic quest tracking",
    tooltip = "The game tracks each quest you take, and each one you make progress on.",
    get = function()
        return GetCVar(AUTO_TRACK_CVAR) == "1"
    end,
    set = function(value)
        pcall(SetCVar, AUTO_TRACK_CVAR, value and "1" or "0")
    end,
})

ns.RegisterCommand("untrack", "Untrack every quest", function()
    if not Quests.Allowed() then
        ns.Print("The game does not let you untrack quests yet.")
        return
    end
    local removed = Quests.UntrackAll()
    if removed == 0 then
        ns.Print("No quests were tracked.")
    else
        ns.Print(string.format("Untracked %s.", questCount(removed)))
    end
end)

local function joined(list)
    return table.concat(list, ", ")
end

ns.RegisterCommand("quests", "Say where you are, and which quests in your log belong here", function()
    local here = Quests.Here()
    local maps
    if #here.maps == 0 then
        maps = "no map"
    else
        maps = string.format(#here.maps == 1 and "map %s" or "maps %s", joined(here.maps))
    end
    ns.Print(string.format("You are in: %s (%s).", joined(here.order), maps))

    local quests = {}
    for _, quest in ipairs(Quests.QuestsHere(here)) do
        table.insert(quests, string.format("%s (%s)", quest.title, quest.why))
    end
    if #quests == 0 then
        ns.Print("No quest in your log belongs here.")
    else
        ns.Print(string.format("Quests here: %s.", joined(quests)))
    end

    local headers = {}
    for index = 1, (C_QuestLog.GetNumQuestLogEntries()) do
        local info = C_QuestLog.GetInfo(index)
        if info and info.isHeader then
            table.insert(headers, info.title)
        end
    end
    if #headers == 0 then
        ns.Print("Your quest log is empty.")
    else
        ns.Print(string.format("Headers in your quest log: %s.", joined(headers)))
    end

    ns.Print(string.format("Track only the quests where you are: %s.", ns.db.quests.areaTrack and "on" or "off"))
end)

--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
-- The quest log comes with Blizzard_UIPanels_Game, which loads before any
-- addon; should it ever come later, the box goes in when it does.
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_ACCEPTED")
events:SetScript("OnEvent", function(_, event, arg1)
    if not ns.db then
        return
    end
    if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        if ns.db.quests.untrackBox and not Quests.box then
            applyBox()
        end
        return
    end

    if not ns.db.quests.areaTrack then
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        pending = true
        C_Timer.After(SETTLE, trySync)
    elseif event == "QUEST_ACCEPTED" then
        accepted[arg1] = true
    elseif event == "QUEST_LOG_UPDATE" then
        trySync()
        trackAccepted()
    end
end)
