local helpers = require("helpers")
local stub = require("wow_stub")

-- Quest tracking, WoW Forever only: the untrack-all box at the top of the
-- quest log, keeping the tracker to the zone or dungeon you are in, and the
-- game's own automatic quest tracking.

--- Loaded, `setup(env, ns)` run if given, then logged in. `options` go to
-- the stubbed client (questLog = false: the quest log is not built yet).
local function loggedIn(setup, options)
    local ns, env = helpers.loadAddon(nil, options)
    if setup then
        setup(env, ns)
    end
    helpers.login(ns, env)
    return ns, env
end

--- The player is tracking these quests, in this order.
local function track(env, ...)
    for index = 1, select("#", ...) do
        env.C_QuestLog.AddQuestWatch((select(index, ...)))
    end
end

--- Whether `questID` is on the tracker.
local function tracked(env, questID)
    for _, id in ipairs(env.__watched) do
        if id == questID then
            return true
        end
    end
    return false
end

--- Fill the quest log: each group is a header's title and the IDs of the
-- quests under it, titled "Quest <id>".
--   questLog(env, { "Hillsbrad Foothills", 101, 102 }, { "Gnomeregan", 201 })
local function questLog(env, ...)
    env.__log = {}
    for index = 1, select("#", ...) do
        local group = select(index, ...)
        table.insert(env.__log, { isHeader = true, title = group[1] })
        for position = 2, #group do
            table.insert(env.__log, { questID = group[position], title = "Quest " .. group[position] })
        end
    end
end

--- Add one quest to the end of the header named `header`'s group.
local function addQuest(env, header, questID)
    local at
    for index, entry in ipairs(env.__log) do
        if entry.isHeader and entry.title == header then
            at = index + 1
        elseif at and entry.isHeader then
            break
        elseif at then
            at = index + 1
        end
    end
    if not at then
        table.insert(env.__log, { isHeader = true, title = header })
        at = #env.__log + 1
    end
    table.insert(env.__log, at, { questID = questID, title = "Quest " .. questID })
end

--- The player arrives in `zone`, on map `mapID`, and a moment passes.
local function enter(env, zone, mapID)
    env.__zone = zone
    env.__playerMap = mapID
    helpers.fire(env, "ZONE_CHANGED_NEW_AREA")
end

--- The quest log redraws, as QuestLogQuests_Update does at its end.
local function redrawQuestLog(env)
    env.QuestLogQuests_ShowQuestCount()
end

local function printed(env)
    return table.concat(env.__printed, "\n")
end

--- Click the way the player does.
local function click(widget)
    widget.scripts.OnClick(widget, "LeftButton")
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function toggle(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

local function box(ns)
    return ns.Quests.box
end

local function tooltipText(env)
    local lines = {}
    for _, line in ipairs(env.GameTooltip.lines) do
        table.insert(lines, line.text)
    end
    return table.concat(lines, "\n")
end

describe("untracking every quest", function()
    it("takes every tracked quest off the tracker", function()
        local ns, env = loggedIn()
        track(env, 101, 102, 103)
        ns.Quests.UntrackAll()
        assertEqual(0, #env.__watched)
    end)

    it("says how many it took off", function()
        local ns, env = loggedIn()
        track(env, 101, 102, 103)
        assertEqual(3, ns.Quests.UntrackAll())
    end)

    it("takes none off when none is tracked", function()
        local ns = loggedIn()
        assertEqual(0, ns.Quests.UntrackAll())
    end)

    it("leaves them tracked while the game forbids untracking", function()
        local ns, env = loggedIn()
        track(env, 101, 102)
        env.__npeRestricted = true
        assertEqual(0, ns.Quests.UntrackAll())
        assertEqual(2, #env.__watched)
    end)

    it("counts the quests on the tracker", function()
        local ns, env = loggedIn()
        track(env, 101, 102)
        assertEqual(2, ns.Quests.Count())
    end)
end)

describe("the untrack-all box in the quest log", function()
    it("sits just left of the settings gear", function()
        local ns, env = loggedIn()
        local point, relativeTo, relativePoint = table.unpack(box(ns).points[1])
        assertEqual("RIGHT", point)
        assertEqual(env.QuestScrollFrame.SettingsDropdown, relativeTo)
        assertEqual("LEFT", relativePoint)
    end)

    it("belongs to the quest list, so it shows and hides with it", function()
        local ns, env = loggedIn()
        assertEqual(env.QuestScrollFrame, box(ns).parent)
    end)

    it("is drawn with the quest log's own tick box", function()
        local ns = loggedIn()
        assertEqual("questlog-icon-ticksquare", box(ns).Box:GetAtlas())
        assertEqual("questlog-icon-checkmark-yellow", box(ns).CheckMark:GetAtlas())
    end)

    it("shows a tick while any quest is tracked", function()
        local ns = loggedIn(function(env) track(env, 101) end)
        assertTrue(box(ns).CheckMark:IsShown())
    end)

    it("shows an empty box while none is tracked", function()
        local ns = loggedIn()
        assertFalse(box(ns).CheckMark:IsShown())
    end)

    it("redraws when the tracked quests change", function()
        local ns, env = loggedIn()
        track(env, 101)
        helpers.fire(env, "QUEST_WATCH_LIST_CHANGED", 101, true)
        assertTrue(box(ns).CheckMark:IsShown())
    end)

    it("waits for the quest log when it is built after login", function()
        local ns, env = loggedIn(nil, { questLog = false })
        assertNil(box(ns))
        stub.buildQuestLog(env)
        helpers.fire(env, "ADDON_LOADED", "Blizzard_UIPanels_Game")
        assertEqual(env.QuestScrollFrame, box(ns).parent)
    end)
end)

describe("clicking the box", function()
    it("untracks every quest", function()
        local ns, env = loggedIn(function(env) track(env, 101, 102, 103) end)
        click(box(ns))
        assertEqual(0, #env.__watched)
    end)

    it("clicks like a quest's own tick box being cleared", function()
        local ns, env = loggedIn(function(env) track(env, 101) end)
        click(box(ns))
        assertEqual(env.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, env.__sounds[1])
    end)

    it("leaves the box empty", function()
        local ns = loggedIn(function(env) track(env, 101) end)
        click(box(ns))
        assertFalse(box(ns).CheckMark:IsShown())
    end)

    it("makes no sound when there is nothing to untrack", function()
        local ns, env = loggedIn()
        click(box(ns))
        assertEqual(0, #env.__sounds)
    end)
end)

describe("the box's tooltip", function()
    it("says what a click does, and how many quests are tracked", function()
        local ns, env = loggedIn(function(env) track(env, 101, 102) end)
        box(ns).scripts.OnEnter(box(ns))
        assertEqual(box(ns), env.GameTooltip.owner)
        assertEqual("Untrack all quests", env.GameTooltip.lines[1].text)
        assertMatch("2 quests are tracked%.", tooltipText(env))
    end)

    it("says one quest, not one quests", function()
        local ns, env = loggedIn(function(env) track(env, 101) end)
        box(ns).scripts.OnEnter(box(ns))
        assertMatch("1 quest is tracked%.", tooltipText(env))
    end)

    it("says when no quest is tracked", function()
        local ns, env = loggedIn()
        box(ns).scripts.OnEnter(box(ns))
        assertMatch("No quests are tracked%.", tooltipText(env))
    end)

    it("is redrawn after a click, while the pointer is still on the box", function()
        local ns, env = loggedIn(function(env) track(env, 101, 102) end)
        box(ns).scripts.OnEnter(box(ns))
        env.GameTooltip.shown = true
        click(box(ns))
        assertMatch("No quests are tracked%.", tooltipText(env))
    end)

    it("goes away when the pointer leaves", function()
        local ns, env = loggedIn()
        box(ns).scripts.OnEnter(box(ns))
        env.GameTooltip.shown = true
        box(ns).scripts.OnLeave(box(ns))
        assertFalse(env.GameTooltip:IsShown())
    end)
end)

describe("the search box beside it", function()
    it("is made narrower, so the quest count moves out of the box's way", function()
        local _, env = loggedIn()
        redrawQuestLog(env)
        assertEqual(176, env.QuestScrollFrame.SearchBox:GetWidth())
    end)

    it("is narrowed once per redraw, not again and again", function()
        local _, env = loggedIn()
        redrawQuestLog(env)
        redrawQuestLog(env)
        assertEqual(176, env.QuestScrollFrame.SearchBox:GetWidth())
    end)

    it("is not narrowed again by a redraw that leaves its width alone", function()
        local _, env = loggedIn(function(env)
            env.QuestLogQuests_ShowQuestCount = function() end
        end)
        redrawQuestLog(env)
        redrawQuestLog(env)
        assertEqual(301 - 24, env.QuestScrollFrame.SearchBox:GetWidth())
    end)

    it("is narrowed with the gamepad interface too", function()
        local _, env = loggedIn(function(env) env.__gamepad = true end)
        redrawQuestLog(env)
        assertEqual(166, env.QuestScrollFrame.SearchBox:GetWidth())
    end)

    it("is narrowed at login when the log already drew its count", function()
        local _, env = loggedIn(function(env) env.QuestLogQuests_ShowQuestCount() end)
        assertEqual(176, env.QuestScrollFrame.SearchBox:GetWidth())
    end)
end)

--- Logged in with tracking the quests of where you are switched on, in
-- Hillsbrad Foothills, with a quest log of three places.
local function arrived(setup)
    return loggedIn(function(env, ns)
        env.ForeverPanelDB = { quests = { areaTrack = true } }
        questLog(env,
            { "Hillsbrad Foothills", 101, 102 },
            { "Gnomeregan", 201 },
            { "Alterac Mountains", 301 })
        if setup then
            setup(env, ns)
        end
    end)
end

describe("tracking the quests of where you are", function()
    it("is off until it is turned on", function()
        local _, env = loggedIn(function(env)
            questLog(env, { "Hillsbrad Foothills", 101 }, { "Gnomeregan", 201 })
            track(env, 201)
        end)
        enter(env, "Hillsbrad Foothills", 25)
        assertFalse(tracked(env, 101))
        assertTrue(tracked(env, 201))
    end)

    it("tracks the quests under the zone's header when you enter it", function()
        local _, env = arrived()
        enter(env, "Hillsbrad Foothills", 25)
        assertTrue(tracked(env, 101))
        assertTrue(tracked(env, 102))
    end)

    it("untracks the quests of other places", function()
        local _, env = arrived(function(env) track(env, 201, 301) end)
        enter(env, "Hillsbrad Foothills", 25)
        assertFalse(tracked(env, 201))
        assertFalse(tracked(env, 301))
    end)

    it("tracks a dungeon's quests inside it, and not the zone outside", function()
        local _, env = arrived(function(env)
            addQuest(env, "Dun Morogh", 401)
        end)
        enter(env, "Gnomeregan", 226)
        assertTrue(tracked(env, 201))
        assertFalse(tracked(env, 401))
        assertFalse(tracked(env, 101))
    end)

    it("swaps the tracked quests over as you move on", function()
        local _, env = arrived()
        enter(env, "Hillsbrad Foothills", 25)
        enter(env, "Alterac Mountains", 22)
        assertEqual(1, #env.__watched)
        assertTrue(tracked(env, 301))
    end)

    it("matches a header to the zone whatever the case of its letters", function()
        local _, env = arrived()
        enter(env, "HILLSBRAD FOOTHILLS", 25)
        assertTrue(tracked(env, 101))
    end)

    it("counts the zone around a cave or building that has a map of its own", function()
        local _, env = arrived()
        enter(env, "Alterac Mountains", 1500)
        assertTrue(tracked(env, 301))
    end)

    it("tracks a quest whose objectives are here, though it sits under another zone", function()
        local _, env = arrived(function(env) env.__questMaps[102] = 14 end)
        enter(env, "Arathi Highlands", 14)
        assertTrue(tracked(env, 102))
        assertFalse(tracked(env, 101))
    end)

    it("tracks no more than the tracker holds", function()
        local _, env = arrived(function(env)
            env.__maxWatches = 1
        end)
        enter(env, "Hillsbrad Foothills", 25)
        assertEqual(1, #env.__watched)
    end)

    it("makes room before it tracks, so a full tracker of other places is swapped", function()
        local _, env = arrived(function(env)
            env.__maxWatches = 2
            track(env, 201, 301)
        end)
        enter(env, "Hillsbrad Foothills", 25)
        assertTrue(tracked(env, 101))
        assertTrue(tracked(env, 102))
    end)

    it("changes nothing while the game forbids untracking", function()
        local _, env = arrived(function(env)
            track(env, 201)
            env.__npeRestricted = true
        end)
        enter(env, "Hillsbrad Foothills", 25)
        assertTrue(tracked(env, 201))
        assertFalse(tracked(env, 101))
    end)

    it("leaves your own ticks alone while you stay", function()
        local _, env = arrived()
        enter(env, "Hillsbrad Foothills", 25)
        env.C_QuestLog.RemoveQuestWatch(101)
        env.C_QuestLog.AddQuestWatch(301)
        helpers.fire(env, "QUEST_WATCH_LIST_CHANGED")
        helpers.fire(env, "QUEST_LOG_UPDATE")
        assertFalse(tracked(env, 101))
        assertTrue(tracked(env, 301))
    end)
end)

describe("arriving in the world", function()
    it("tracks the quests of where you are once the quest log has loaded", function()
        local _, env = loggedIn(function(env)
            env.ForeverPanelDB = { quests = { areaTrack = true } }
            track(env, 201)
        end)
        helpers.fire(env, "PLAYER_ENTERING_WORLD", true, false)
        assertTrue(tracked(env, 201), "the log is still empty, so nothing is untracked yet")

        questLog(env, { "Hillsbrad Foothills", 101 }, { "Gnomeregan", 201 })
        helpers.fire(env, "QUEST_LOG_UPDATE")
        assertTrue(tracked(env, 101))
        assertFalse(tracked(env, 201))
    end)

    it("does it again on entering a dungeon through a loading screen", function()
        local _, env = arrived()
        env.__zone, env.__playerMap = "Gnomeregan", 226
        helpers.fire(env, "PLAYER_ENTERING_WORLD", false, false)
        assertTrue(tracked(env, 201))
    end)
end)

describe("taking a quest", function()
    it("tracks a quest you take for where you are", function()
        local _, env = arrived(function(env) env.__cvars.autoQuestWatch = "0" end)
        enter(env, "Hillsbrad Foothills", 25)
        addQuest(env, "Hillsbrad Foothills", 103)
        helpers.fire(env, "QUEST_ACCEPTED", 103)
        helpers.fire(env, "QUEST_LOG_UPDATE")
        assertTrue(tracked(env, 103))
    end)

    it("leaves a quest you take for somewhere else to the game", function()
        local _, env = arrived(function(env) env.__cvars.autoQuestWatch = "0" end)
        enter(env, "Hillsbrad Foothills", 25)
        addQuest(env, "Arathi Highlands", 501)
        helpers.fire(env, "QUEST_ACCEPTED", 501)
        helpers.fire(env, "QUEST_LOG_UPDATE")
        assertFalse(tracked(env, 501))
    end)

    it("does nothing while it is off", function()
        local _, env = loggedIn(function(env)
            env.__cvars.autoQuestWatch = "0"
            questLog(env, { "Hillsbrad Foothills", 101 })
        end)
        addQuest(env, "Hillsbrad Foothills", 103)
        helpers.fire(env, "QUEST_ACCEPTED", 103)
        helpers.fire(env, "QUEST_LOG_UPDATE")
        assertFalse(tracked(env, 103))
    end)
end)

--------------------------------------------------------------------------------
-- The settings page
--------------------------------------------------------------------------------

--- Logged in, with ForeverPanel's page built and showing what is saved.
local function opened(setup)
    local ns, env = loggedIn(setup)
    ns.Settings.EnsureBuilt()
    ns.Settings.Refresh()
    return ns, env
end

local function control(ns, key)
    for _, candidate in ipairs(ns.Settings.controls) do
        if candidate.setting.store == "quests" and candidate.setting.key == key then
            return candidate
        end
    end
end

local function placed(candidate)
    local point = { candidate.widget:GetPoint(1) }
    return point[#point - 1], point[#point]
end

describe("the quest options on ForeverPanel's page", function()
    it("are a group of their own in the right column, under the portrait options", function()
        local ns = opened()
        local portrait
        for _, candidate in ipairs(ns.Settings.controls) do
            if candidate.setting.key == "portraitBelowBar" then
                portrait = candidate
            end
        end
        local _, portraitY = placed(portrait)

        for _, key in ipairs({ "untrackBox", "areaTrack", "gameAutoTrack" }) do
            local x, y = placed(control(ns, key))
            assertEqual("quests", control(ns, key).setting.section, key .. " in the quests group")
            assertTrue(x >= 280, key .. " in the right column")
            assertTrue(y < portraitY, key .. " below the portrait options")
        end
    end)

    it("come in order: the box, where you are, then the game's own tracking", function()
        local ns = opened()
        local _, boxY = placed(control(ns, "untrackBox"))
        local _, areaY = placed(control(ns, "areaTrack"))
        local _, gameY = placed(control(ns, "gameAutoTrack"))
        assertTrue(boxY > areaY and areaY > gameY)
    end)

    it("are labelled with what each does", function()
        local ns = opened()
        assertEqual("Untrack-all box in the quest log", control(ns, "untrackBox").setting.name)
        assertEqual("Track only the quests where you are", control(ns, "areaTrack").setting.name)
        assertEqual("Automatic quest tracking", control(ns, "gameAutoTrack").setting.name)
    end)
end)

describe("the switch for the untrack-all box", function()
    it("is on at first", function()
        local ns = opened()
        assertTrue(control(ns, "untrackBox").widget:GetChecked())
    end)

    it("takes the box away, and gives the search box its width back", function()
        local ns, env = opened()
        redrawQuestLog(env)
        toggle(control(ns, "untrackBox").widget)
        assertFalse(ns.db.quests.untrackBox)
        assertFalse(box(ns):IsShown())
        assertEqual(200, env.QuestScrollFrame.SearchBox:GetWidth())
        redrawQuestLog(env)
        assertEqual(200, env.QuestScrollFrame.SearchBox:GetWidth(), "not narrowed by the next redraw")
    end)

    it("puts the box back", function()
        local ns, env = opened()
        toggle(control(ns, "untrackBox").widget)
        toggle(control(ns, "untrackBox").widget)
        redrawQuestLog(env)
        assertTrue(box(ns):IsShown())
        assertEqual(176, env.QuestScrollFrame.SearchBox:GetWidth())
    end)

    it("leaves the quest log as it was when it is off at login", function()
        local ns, env = loggedIn(function(env)
            env.ForeverPanelDB = { quests = { untrackBox = false } }
        end)
        redrawQuestLog(env)
        assertNil(box(ns))
        assertEqual(200, env.QuestScrollFrame.SearchBox:GetWidth())
    end)

    it("makes a box when turned on, if there was none", function()
        local ns, env = opened(function(env)
            env.ForeverPanelDB = { quests = { untrackBox = false } }
        end)
        toggle(control(ns, "untrackBox").widget)
        assertEqual(env.QuestScrollFrame, box(ns).parent)
        assertTrue(box(ns):IsShown())
    end)
end)

describe("the switch for tracking the quests of where you are", function()
    it("is off at first", function()
        local ns = opened()
        assertFalse(control(ns, "areaTrack").widget:GetChecked())
        assertFalse(ns.db.quests.areaTrack)
    end)

    it("shows what is saved", function()
        local ns = opened(function(env) env.ForeverPanelDB = { quests = { areaTrack = true } } end)
        assertTrue(control(ns, "areaTrack").widget:GetChecked())
    end)

    it("tracks the quests of where you are as soon as it is turned on", function()
        local ns, env = opened(function(env)
            questLog(env, { "Hillsbrad Foothills", 101 }, { "Gnomeregan", 201 })
            track(env, 201)
        end)
        toggle(control(ns, "areaTrack").widget)
        assertTrue(ns.db.quests.areaTrack)
        assertTrue(tracked(env, 101))
        assertFalse(tracked(env, 201))
    end)

    it("changes no quests when it is turned off", function()
        local ns, env = opened(function(env)
            env.ForeverPanelDB = { quests = { areaTrack = true } }
            questLog(env, { "Hillsbrad Foothills", 101 }, { "Gnomeregan", 201 })
            track(env, 201)
        end)
        toggle(control(ns, "areaTrack").widget)
        assertFalse(ns.db.quests.areaTrack)
        assertTrue(tracked(env, 201))
    end)
end)

describe("the automatic quest tracking switch", function()
    it("is ticked while the game tracks quests on its own", function()
        local ns = opened()
        assertTrue(control(ns, "gameAutoTrack").widget:GetChecked())
    end)

    it("shows the game's setting", function()
        local ns = opened(function(env) env.__cvars.autoQuestWatch = "0" end)
        assertFalse(control(ns, "gameAutoTrack").widget:GetChecked())
    end)

    it("turns the game's automatic quest tracking off and on", function()
        local ns, env = opened()
        toggle(control(ns, "gameAutoTrack").widget)
        assertEqual("0", env.__cvars.autoQuestWatch)
        toggle(control(ns, "gameAutoTrack").widget)
        assertEqual("1", env.__cvars.autoQuestWatch)
    end)

    it("shows a change made elsewhere when the page opens again", function()
        local ns, env = opened()
        env.__cvars.autoQuestWatch = "0"
        ns.Settings.Refresh()
        assertFalse(control(ns, "gameAutoTrack").widget:GetChecked())
    end)

    it("keeps nothing of its own: the game's setting is the only copy", function()
        local ns = opened()
        toggle(control(ns, "gameAutoTrack").widget)
        assertNil(ns.db.quests.gameAutoTrack)
    end)
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

describe("/fp untrack", function()
    it("untracks every quest and says how many", function()
        local _, env = loggedIn(function(env) track(env, 101, 102, 103) end)
        helpers.command(env, "untrack")
        assertEqual(0, #env.__watched)
        assertMatch("Untracked 3 quests%.", printed(env))
    end)

    it("says one quest, not one quests", function()
        local _, env = loggedIn(function(env) track(env, 101) end)
        helpers.command(env, "untrack")
        assertMatch("Untracked 1 quest%.", printed(env))
    end)

    it("says so when no quest was tracked", function()
        local _, env = loggedIn()
        helpers.command(env, "untrack")
        assertMatch("No quests were tracked%.", printed(env))
    end)

    it("says so when the game will not let quests be untracked", function()
        local _, env = loggedIn(function(env)
            track(env, 101)
            env.__npeRestricted = true
        end)
        helpers.command(env, "untrack")
        assertMatch("The game does not let you untrack quests yet%.", printed(env))
    end)

    it("is listed in the help", function()
        local _, env = loggedIn()
        helpers.command(env, "help")
        assertMatch("/fp untrack %- ", printed(env))
    end)
end)

describe("/fp quests", function()
    local function quests(setup)
        local _, env = arrived(setup)
        helpers.command(env, "quests")
        return printed(env)
    end

    it("says where you are, by the names it matches headers against", function()
        assertMatch("You are in: Hillsbrad Foothills %(map 25%)%.", quests())
    end)

    it("names the zone around a cave too", function()
        local text = quests(function(env) env.__zone, env.__playerMap = "Alterac Mountains", 1500 end)
        assertMatch("You are in: Alterac Mountains, Alterac Mountains Cave %(maps 1500, 22%)%.", text)
    end)

    it("lists the quests that belong here, and why", function()
        local text = quests(function(env) env.__questMaps[301] = 25 end)
        assertMatch("Quests here: Quest 101 %(header%), Quest 102 %(header%), Quest 301 %(objectives%)%.", text)
    end)

    it("says when none belongs here", function()
        local text = quests(function(env) env.__zone, env.__playerMap = "Arathi Highlands", 14 end)
        assertMatch("No quest in your log belongs here%.", text)
    end)

    it("lists the headers in the quest log, to compare with where you are", function()
        assertMatch("Headers in your quest log: Hillsbrad Foothills, Gnomeregan, Alterac Mountains%.", quests())
    end)

    it("says whether the switch is on", function()
        assertMatch("Track only the quests where you are: on%.", quests())
        local _, env = loggedIn()
        helpers.command(env, "quests")
        assertMatch("Track only the quests where you are: off%.", printed(env))
    end)

    it("is listed in the help", function()
        local _, env = loggedIn()
        helpers.command(env, "help")
        assertMatch("/fp quests %- ", printed(env))
    end)
end)

--------------------------------------------------------------------------------
-- Classic Era
--------------------------------------------------------------------------------

describe("on Classic Era", function()
    -- Its quest log is another window, and its C_QuestLog has none of the
    -- watch list calls.
    it("offers no quest options, commands or box", function()
        local ns = loggedIn(nil, { client = "classic" })
        assertNil(ns.Quests)
        assertNil(ns.commands.untrack)
        assertNil(ns.commands.quests)
        for _, setting in ipairs(ns.settings) do
            assertTrue(setting.store ~= "quests", setting.key .. " is not on the page")
        end
    end)
end)
