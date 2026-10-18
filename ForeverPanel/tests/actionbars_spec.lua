local helpers = require("helpers")

-- Each action bar as Forever's Edit Mode has it: a frame that knows its
-- system and its place in the layout, whose SetPoint and ClearAllPoints are
-- Edit Mode's wrappers that keep its books (snapped frames and the like),
-- with the frame's own kept as SetPointBase and ClearAllPointsBase.
local ACTION_BAR = 0

local BAR8_PLACE = {
    point = "BOTTOMRIGHT", relativeTo = "MultiBarBottomRight", relativePoint = "TOPRIGHT",
    offsetX = 0, offsetY = 4,
}
local BAR6_PLACE = {
    point = "RIGHT", relativeTo = "UIParent", relativePoint = "RIGHT",
    offsetX = -5, offsetY = -77,
}
local BAR2_PLACE = {
    point = "BOTTOMLEFT", relativeTo = "MainActionBar", relativePoint = "TOPLEFT",
    offsetX = 0, offsetY = 4,
}
-- Where another screen put a bar.
local LAPTOP_PLACE = {
    point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM",
    offsetX = 300, offsetY = 200,
}
-- Where the player puts one in Edit Mode on this screen.
local DESK_PLACE = {
    point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
    offsetX = 40, offsetY = 320,
}

local function copy(anchor)
    local result = {}
    for key, value in pairs(anchor) do
        result[key] = value
    end
    return result
end

local function editModeBar(env, name, systemIndex, isDefault, anchor)
    local bar = env.CreateFrame("Frame", name, env.UIParent)
    bar.system, bar.systemIndex = ACTION_BAR, systemIndex
    bar.systemInfo = { isInDefaultPosition = isDefault, anchorInfo = copy(anchor) }
    local setPoint = bar.SetPoint
    -- The client refuses an anchor that would loop, as one can when this
    -- screen's place hangs off a bar the layout now hangs off this one.
    function bar:SetPointBase(point, ...)
        if point == self.refusedPoint then
            error("Cannot anchor to a region dependent on it")
        end
        return setPoint(self, point, ...)
    end
    bar.ClearAllPointsBase = bar.ClearAllPoints
    bar.bookkeeping = 0
    function bar:SetPoint(...)
        self:SetPointBase(...)
        self.bookkeeping = self.bookkeeping + 1
    end
    function bar:ClearAllPoints()
        self:ClearAllPointsBase()
        self.bookkeeping = self.bookkeeping + 1
    end
    function bar:GetScale()
        return self.scale
    end
    table.insert(env.EditModeManagerFrame.registeredSystemFrames, bar)
    return bar
end

--- Where the stack along the bottom puts a bar in it.
local STACK_POINT = { "BOTTOMLEFT", "UIParent", "BOTTOM", -270, 60 }

--- The game placing a bar where the layout has it, through Edit Mode's
-- wrappers, as it does.
local function gamePlaces(env, bar)
    local info = bar.systemInfo
    bar:ClearAllPoints()
    if info.isInDefaultPosition and bar == env.MultiBarBottomLeft then
        bar:SetPoint(table.unpack(STACK_POINT))
    else
        local anchor = info.anchorInfo
        local scale = bar:GetScale()
        bar:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.offsetX / scale, anchor.offsetY / scale)
    end
end

--- The layout as it reaches this screen: changed on another one, maybe.
local function layoutHas(env, bar, isDefault, anchor)
    bar.systemInfo = { isInDefaultPosition = isDefault, anchorInfo = copy(anchor) }
end

--- Log in on the 4K desktop under the "Skyler" layout: bar 8 above bar 3,
-- bar 6 in its own default place and bar 2 in the stack along the bottom.
-- Prepare can change the layout or screen before the game lays it out.
-- Saved is what an earlier session left in the account's saved variables.
local function loggedIn(prepare, saved)
    local ns, env = helpers.loadAddon()
    env.ForeverPanelDB = saved
    helpers.login(ns, env)

    env.Enum = { EditModeSystem = { ActionBar = ACTION_BAR, ChatFrame = 8 } }
    local manager = env.CreateFrame("Frame")
    manager.shown = false
    manager.registeredSystemFrames = {}
    manager.layoutName = "Skyler"
    function manager:IsEditModeActive()
        return self.shown
    end
    function manager:GetActiveLayoutInfo()
        return { layoutName = self.layoutName }
    end
    env.EditModeManagerFrame = manager
    env.EditModeUtil = {}
    function env.EditModeUtil:IsBottomAnchoredActionBar(frame)
        return frame == env.MultiBarBottomLeft
    end
    function env.EditModeUtil:IsRightAnchoredActionBar()
        return false
    end

    editModeBar(env, "MultiBar7", 8, false, BAR8_PLACE)
    editModeBar(env, "MultiBar5", 6, true, BAR6_PLACE)
    editModeBar(env, "MultiBarBottomLeft", 2, true, BAR2_PLACE)
    -- Not an action bar: left alone.
    local chat = editModeBar(env, "EditModeChat", 0, false, LAPTOP_PLACE)
    chat.system = 8

    if prepare then
        prepare(ns, env)
    end
    for _, bar in ipairs(manager.registeredSystemFrames) do
        gamePlaces(env, bar)
    end
    helpers.fire(env, "PLAYER_ENTERING_WORLD")
    helpers.fire(env, "EDIT_MODE_LAYOUTS_UPDATED")
    env.__runTimers()
    return ns, env
end

local function openEditMode(env)
    env.EditModeManagerFrame:Show()
    env.EventRegistry:TriggerEvent("EditMode.Enter")
    env.__runTimers()
end

--- The player drags a bar and Edit Mode notes its new place, changing the
-- layout's own anchor table rather than making a new one.
local function dragBar(env, bar, anchor)
    local info = bar.systemInfo
    info.isInDefaultPosition = false
    for key, value in pairs(anchor) do
        info.anchorInfo[key] = value
    end
    gamePlaces(env, bar)
end

local function saveEditMode(env)
    env.EventRegistry:TriggerEvent("EditMode.SavedLayouts")
end

local function closeEditMode(env)
    env.EditModeManagerFrame:Hide()
    env.EventRegistry:TriggerEvent("EditMode.Exit")
    env.__runTimers()
end

local function moveInEditMode(env, bar, anchor)
    openEditMode(env)
    dragBar(env, bar, anchor)
    saveEditMode(env)
    closeEditMode(env)
end

local function settingFor(ns, store, key)
    for _, setting in ipairs(ns.settings) do
        if setting.store == store and setting.key == key then
            return setting
        end
    end
end

--- Asserts the bar has the one anchor, offsets in its own scale.
local function at(bar, anchor, scale)
    scale = scale or 1
    assertEqual(1, #bar.points, bar:GetName() .. " has one point, so nothing pulls it elsewhere")
    local point, relativeTo, relativePoint, x, y = bar:GetPoint(1)
    assertEqual(anchor.point, point, "point")
    assertEqual(anchor.relativeTo, relativeTo, "relative to")
    assertEqual(anchor.relativePoint, relativePoint, "relative point")
    assertNear(anchor.offsetX / scale, x, 0.001, "x")
    assertNear(anchor.offsetY / scale, y, 0.001, "y")
end

--- The laptop has since moved bar 8 and saved the layout.
local function laptopMovedBar8(_, env)
    layoutHas(env, env.MultiBar7, false, LAPTOP_PLACE)
end

describe("the action bars' places on each screen", function()
    --- A session on the 4K desktop after an earlier one there.
    local function seenBefore(prepare, during)
        local ns, first = loggedIn()
        if during then
            during(ns, first)
        end
        return loggedIn(prepare, first.ForeverPanelDB)
    end

    --- A session on the 4K desktop after one where bar 8 was put at
    -- DESK_PLACE in Edit Mode, the layout since saved on the laptop.
    local function placedBefore(prepare)
        return seenBefore(function(ns, env)
            laptopMovedBar8(ns, env)
            if prepare then
                prepare(ns, env)
            end
        end, function(_, env)
            moveInEditMode(env, env.MultiBar7, DESK_PLACE)
        end)
    end

    it("stays where the layout put it on a screen seen for the first time", function()
        local _, env = loggedIn()

        at(env.MultiBar7, BAR8_PLACE)
    end)

    it("keeps the place this screen first saw after another screen moves it", function()
        local _, env = seenBefore(laptopMovedBar8)

        at(env.MultiBar7, BAR8_PLACE)
    end)

    it("comes back where you put it in Edit Mode on this screen", function()
        local _, env = placedBefore()

        at(env.MultiBar7, DESK_PLACE)
    end)

    it("takes the layout's place on a screen not seen before", function()
        local _, env = seenBefore(function(ns, e)
            laptopMovedBar8(ns, e)
            e.__screen = { 2560, 1600 }
        end)

        at(env.MultiBar7, LAPTOP_PLACE)
    end)

    it("goes back to this screen's place when the game puts the layout's back", function()
        local _, env = placedBefore()

        gamePlaces(env, env.MultiBar7)
        env.__runTimers()

        at(env.MultiBar7, DESK_PLACE)
    end)

    -- Edit Mode's wrappers write its own tables; run from an addon they
    -- would taint them, and with them the bars in combat.
    it("moves a bar without Edit Mode's wrappers", function()
        local ns, env = placedBefore()
        env.MultiBar7.bookkeeping = 0

        ns.ApplyActionBars()

        at(env.MultiBar7, DESK_PLACE)
        assertEqual(0, env.MultiBar7.bookkeeping)
    end)

    it("waits for the fight to end to move a bar", function()
        local _, env = placedBefore()
        env.__inCombat = true

        gamePlaces(env, env.MultiBar7)
        env.__runTimers()
        at(env.MultiBar7, LAPTOP_PLACE)

        env.__inCombat = false
        helpers.fire(env, "PLAYER_REGEN_ENABLED")
        at(env.MultiBar7, DESK_PLACE)
    end)

    it("is left alone while Edit Mode is open, and placed when it closes", function()
        local _, env = placedBefore(function(_, e) e.EditModeManagerFrame.shown = true end)
        at(env.MultiBar7, LAPTOP_PLACE)

        closeEditMode(env)

        at(env.MultiBar7, DESK_PLACE)
    end)

    it("keeps this screen's place after a save that moved nothing", function()
        local _, env = placedBefore()
        openEditMode(env)
        saveEditMode(env)
        closeEditMode(env)

        local _, after = loggedIn(laptopMovedBar8, env.ForeverPanelDB)

        at(after.MultiBar7, DESK_PLACE)
    end)

    -- Leaving unsaved, Edit Mode gives each bar a fresh copy of its saved
    -- place and lays it out again.
    it("keeps this screen's place when Edit Mode is left without saving", function()
        local _, env = loggedIn()
        openEditMode(env)
        dragBar(env, env.MultiBar7, DESK_PLACE)
        layoutHas(env, env.MultiBar7, false, BAR8_PLACE)
        gamePlaces(env, env.MultiBar7)
        closeEditMode(env)

        local _, after = loggedIn(laptopMovedBar8, env.ForeverPanelDB)

        at(after.MultiBar7, BAR8_PLACE)
    end)

    it("gives the layout's place back when turned off", function()
        local ns, env = placedBefore()

        ns.SetSettingValue(settingFor(ns, "ui", "barsPerScreen"), false)

        at(env.MultiBar7, LAPTOP_PLACE)
    end)

    it("gives back the layout's latest place when turned off, not the one it had at login", function()
        local ns, env = placedBefore()
        layoutHas(env, env.MultiBar7, false, BAR6_PLACE)
        gamePlaces(env, env.MultiBar7)
        env.__runTimers()

        ns.SetSettingValue(settingFor(ns, "ui", "barsPerScreen"), false)

        at(env.MultiBar7, BAR6_PLACE)
    end)

    it("comes back when turned on again", function()
        local ns, env = placedBefore()
        local setting = settingFor(ns, "ui", "barsPerScreen")
        ns.SetSettingValue(setting, false)

        ns.SetSettingValue(setting, true)

        at(env.MultiBar7, DESK_PLACE)
    end)

    it("keeps each Edit Mode layout's places apart", function()
        local _, env = seenBefore(function(ns, e)
            laptopMovedBar8(ns, e)
            e.EditModeManagerFrame.layoutName = "Raid"
        end)

        at(env.MultiBar7, LAPTOP_PLACE)
    end)

    it("takes the layout's places when the game moves to a screen not seen before", function()
        local _, env = placedBefore()

        env.__screen = { 2560, 1600 }
        helpers.fire(env, "DISPLAY_SIZE_CHANGED")

        at(env.MultiBar7, LAPTOP_PLACE)
    end)

    it("stays where the layout put it when the client refuses this screen's place", function()
        local _, env = placedBefore(function(_, e) e.MultiBar7.refusedPoint = DESK_PLACE.point end)

        at(env.MultiBar7, LAPTOP_PLACE)
    end)

    it("anchors in the bar's own scale, as Edit Mode does", function()
        local _, env = placedBefore(function(_, e) e.MultiBar7.scale = 0.5 end)

        at(env.MultiBar7, DESK_PLACE, 0.5)
    end)

    it("puts a bar this screen keeps in its own default place back there", function()
        local _, env = seenBefore(function(_, e)
            layoutHas(e, e.MultiBar5, false, LAPTOP_PLACE)
        end)

        at(env.MultiBar5, BAR6_PLACE)
    end)

    -- Only the game can put a bar back in the stack along the bottom, so a
    -- bar moved out of it on another screen stays out.
    it("leaves a bar this screen keeps in the bottom stack where the layout has it", function()
        local _, env = seenBefore(function(_, e)
            layoutHas(e, e.MultiBarBottomLeft, false, LAPTOP_PLACE)
        end)

        at(env.MultiBarBottomLeft, LAPTOP_PLACE)
    end)

    it("leaves frames that are not action bars alone", function()
        local _, env = seenBefore(function(_, e)
            layoutHas(e, e.EditModeChat, false, DESK_PLACE)
        end)

        at(env.EditModeChat, DESK_PLACE)
    end)
end)
