local helpers = require("helpers")

--- Log in, the layout's chat box 430 by 120 at 32, 95 from the bottom left,
-- the main action bar under it, and Edit Mode closed. Saved is what an
-- earlier session left in the account's saved variables.
local function loggedIn(prepare, saved)
    local ns, env = helpers.loadAddon()
    env.ForeverPanelDB = saved
    env.xp, env.xpMax = 500, 1000
    helpers.login(ns, env)
    env.UIParent.left, env.UIParent.bottom = 0, 0
    env.ChatFrame1.left, env.ChatFrame1.right, env.ChatFrame1.bottom = 32, 462, 95
    env.ChatFrame1:SetSize(430, 120)
    local bar = env.MainActionBar
    bar.left, bar.right, bar.top, bar.shown = 20, 560, 50, true
    -- Forever's Edit Mode: open while its manager is shown.
    local manager = env.CreateFrame("Frame")
    manager.shown = false
    function manager:IsEditModeActive()
        return self.shown
    end
    env.EditModeManagerFrame = manager
    if prepare then
        prepare(ns, env)
    end
    helpers.fire(env, "PLAYER_ENTERING_WORLD")
    env.__runTimers()
    return ns, env
end

local function openEditMode(env)
    env.EditModeManagerFrame:Show()
    env.EventRegistry:TriggerEvent("EditMode.Enter")
    env.__runTimers()
end

--- The player drags the chat box's corner: the client sizes it, with no
-- SetSize call from the interface's code.
local function dragCorner(env, width, height)
    env.ChatFrame1.width, env.ChatFrame1.height = width, height
end

--- The player drags the chat box to a new place, and Edit Mode anchors it
-- where it was dropped.
local function dragChat(env, left, bottom)
    local frame = env.ChatFrame1
    frame.left, frame.right, frame.bottom = left, left + frame.width, bottom
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", left, bottom)
end

local function saveEditMode(env)
    env.EventRegistry:TriggerEvent("EditMode.SavedLayouts")
end

local function closeEditMode(env)
    env.EditModeManagerFrame:Hide()
    env.EventRegistry:TriggerEvent("EditMode.Exit")
    env.__runTimers()
end

--- Size the chat box in Edit Mode, save and leave.
local function resizeInEditMode(env, width, height)
    openEditMode(env)
    dragCorner(env, width, height)
    saveEditMode(env)
    closeEditMode(env)
end

--- Move the chat box in Edit Mode, save and leave.
local function moveInEditMode(env, left, bottom)
    openEditMode(env)
    dragChat(env, left, bottom)
    saveEditMode(env)
    closeEditMode(env)
end

--- The game putting the layout's place back.
local function layoutPlace(env, left, bottom)
    env.ChatFrame1:ClearAllPoints()
    env.ChatFrame1:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", left, bottom)
    env.__runTimers()
end

local function settingFor(ns, store, key)
    for _, setting in ipairs(ns.settings) do
        if setting.store == store and setting.key == key then
            return setting
        end
    end
end

local function placed(env)
    assertEqual(1, #env.ChatFrame1.points, "one point, so nothing pulls it elsewhere")
    local point, relative, relativePoint, x, y = env.ChatFrame1:GetPoint(1)
    assertEqual("BOTTOMLEFT", point)
    assertEqual(env.UIParent, relative)
    assertEqual("BOTTOMLEFT", relativePoint)
    return x, y
end

describe("the chat box's place and size on each screen", function()
    --- A session on the 4K screen after one where it was sized 430 by 481
    -- there, the layout since sized 120 high on another screen.
    local function sizedBefore(prepare)
        local _, first = loggedIn()
        resizeInEditMode(first, 430, 481)
        return loggedIn(prepare, first.ForeverPanelDB)
    end

    --- A session on the 4K screen after one where it was put at 40, 300
    -- there, the layout since moved on another screen.
    local function placedBefore(prepare)
        local _, first = loggedIn()
        moveInEditMode(first, 40, 300)
        return loggedIn(prepare, first.ForeverPanelDB)
    end

    it("stays where the layout put it, at its size, before you place it", function()
        local _, env = loggedIn()

        local x, y = placed(env)
        assertEqual(32, x)
        assertEqual(95, y)
        assertEqual(430, env.ChatFrame1:GetWidth())
        assertEqual(120, env.ChatFrame1:GetHeight())
    end)

    it("comes back where you put it in Edit Mode on this screen", function()
        local _, env = placedBefore()

        local x, y = placed(env)
        assertEqual(40, x)
        assertEqual(300, y)
    end)

    it("stays where the layout put it on a screen you have not put it on", function()
        local _, env = placedBefore(function(_, e) e.__screen = { 2560, 1600 } end)

        local x, y = placed(env)
        assertEqual(32, x)
        assertEqual(95, y)
    end)

    it("goes back where you put it when the game puts the layout's place back", function()
        local _, env = placedBefore()

        layoutPlace(env, 32, 400)

        assertEqual(300, select(2, placed(env)))
    end)

    it("leaves the layout's place after a save that moved nothing", function()
        local _, first = loggedIn()
        openEditMode(first)
        saveEditMode(first)
        closeEditMode(first)

        local _, env = loggedIn(nil, first.ForeverPanelDB)

        assertEqual(95, select(2, placed(env)))
    end)

    it("gives the layout's place back when turned off", function()
        local ns, env = placedBefore()

        ns.SetSettingValue(settingFor(ns, "ui", "chatPerScreen"), false)

        local x, y = placed(env)
        assertEqual(32, x)
        assertEqual(95, y)
    end)

    it("gives back the layout's latest place when turned off, not the one it had at login", function()
        local ns, env = placedBefore()
        layoutPlace(env, 32, 400)

        ns.SetSettingValue(settingFor(ns, "ui", "chatPerScreen"), false)

        assertEqual(400, select(2, placed(env)))
    end)

    it("comes back at the size you gave it in Edit Mode on this screen", function()
        local _, env = sizedBefore()

        assertEqual(430, env.ChatFrame1:GetWidth())
        assertEqual(481, env.ChatFrame1:GetHeight())
    end)

    it("keeps the layout's size on a screen you have not sized it on", function()
        local _, env = sizedBefore(function(_, e) e.__screen = { 2560, 1600 } end)

        assertEqual(120, env.ChatFrame1:GetHeight())
    end)

    it("puts its size back when the game puts the layout's back", function()
        local _, env = sizedBefore()

        env.ChatFrame1:SetSize(430, 120)
        env.__runTimers()

        assertEqual(481, env.ChatFrame1:GetHeight())
    end)

    it("keeps its size when Edit Mode is left without saving", function()
        local _, env = sizedBefore()

        openEditMode(env)
        dragCorner(env, 430, 300)
        env.ChatFrame1:SetSize(430, 120) -- leaving unsaved puts the layout back
        closeEditMode(env)

        assertEqual(481, env.ChatFrame1:GetHeight())
    end)

    it("keeps its size when Edit Mode saves something else", function()
        local _, env = sizedBefore()

        openEditMode(env)
        saveEditMode(env)
        closeEditMode(env)
        local _, after = loggedIn(nil, env.ForeverPanelDB)

        assertEqual(481, after.ChatFrame1:GetHeight())
    end)

    it("is left alone while Edit Mode is open, and sized when it closes", function()
        local _, env = sizedBefore(function(_, e) e.EditModeManagerFrame.shown = true end)
        assertEqual(120, env.ChatFrame1:GetHeight())

        closeEditMode(env)
        assertEqual(481, env.ChatFrame1:GetHeight())
    end)

    it("takes the layout's size when the game moves to a screen it has none for", function()
        local _, env = sizedBefore()

        env.__screen = { 2560, 1600 }
        helpers.fire(env, "DISPLAY_SIZE_CHANGED")

        assertEqual(120, env.ChatFrame1:GetHeight())
    end)

    it("gives the layout's size back when turned off", function()
        local ns, env = sizedBefore()

        ns.SetSettingValue(settingFor(ns, "ui", "chatPerScreen"), false)

        assertEqual(120, env.ChatFrame1:GetHeight())
    end)
end)
