local helpers = require("helpers")

-- A screen: UIParent's top edge, where the bar's bottom is, and where the
-- game's layout left the portrait's left edge, all in screen pixels at scale 1.
local function screen(env, uiTop, barBottom, portraitLeft)
    env.UIParent.top, env.UIParent.left = uiTop, 0
    env.ForeverBar.bottom = barBottom
    env.PlayerFrame.left = portraitLeft
end

local function loggedIn(prepare)
    local ns, env = helpers.loadAddon()
    env.xp, env.xpMax = 500, 1000
    helpers.login(ns, env)
    screen(env, 976, 976, 40)
    if prepare then
        prepare(ns, env)
    end
    helpers.fire(env, "PLAYER_ENTERING_WORLD")
    env.__runTimers()
    return ns, env
end

local function settingFor(ns, store, key)
    for _, setting in ipairs(ns.settings) do
        if setting.store == store and setting.key == key then
            return setting
        end
    end
end

local function placed(env)
    assertEqual(1, #env.PlayerFrame.points, "one point, so nothing pulls it elsewhere")
    return env.PlayerFrame:GetPoint(1)
end

describe("the portrait under the bar", function()
    it("sits a few pixels under the bar and from the left edge", function()
        local _, env = loggedIn()

        local point, relative, relativePoint, x, y = placed(env)
        assertEqual("TOPLEFT", point)
        assertEqual(env.UIParent, relative)
        assertEqual("TOPLEFT", relativePoint)
        assertEqual(4, x)
        assertEqual(-4, y)
    end)

    it("keeps to the left edge wherever the game's layout put it, as on a wider screen", function()
        local _, env = loggedIn(function(_, e) e.PlayerFrame.left = 905 end)

        local _, _, _, x = placed(env)
        assertEqual(4, x)
    end)

    it("follows the left gap setting", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "portraitLeftGap"), 20)

        local _, _, _, x = placed(env)
        assertEqual(20, x)
    end)

    it("leaves left and right where the game's layout had them, with the left edge turned off", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "portraitAtLeft"), false)

        local _, _, _, x, y = placed(env)
        assertEqual(40, x)
        assertEqual(-4, y)
    end)

    it("is the same distance under the bar on a taller screen", function()
        local _, env = loggedIn(function(_, e) screen(e, 1416, 1416, 40) end)

        local _, _, _, _, y = placed(env)
        assertEqual(-4, y)
    end)

    it("measures from the bar, not UIParent, when the UI is not pushed down", function()
        local _, env = loggedIn(function(_, e) screen(e, 1000, 976, 40) end)

        local _, _, _, _, y = placed(env)
        assertEqual(-28, y, "the bar's 24 and the gap of 4")
    end)

    it("works in the portrait's own scale when Edit Mode has resized it", function()
        local _, env = loggedIn(function(_, e)
            e.PlayerFrame.scale = 1.25
            e.PlayerFrame.left = 32 -- 40 screen pixels, in its own scale
        end)

        local _, _, _, x, y = placed(env)
        assertNear(4 / 1.25, x, 0.001, "4 screen pixels from the edge, in its own scale")
        assertEqual(-4 / 1.25, y)
    end)

    it("goes back under the bar when the game moves it again", function()
        local _, env = loggedIn()

        env.PlayerFrame:ClearAllPoints()
        env.PlayerFrame:SetPoint("CENTER", env.UIParent, "CENTER", -300, 200)
        env.__runTimers()

        local point, _, _, _, y = placed(env)
        assertEqual("TOPLEFT", point)
        assertEqual(-4, y)
    end)

    it("waits for a fight to end, when the game will not let it move", function()
        local _, env = loggedIn(function(_, e) e.__inCombat = true end)

        local point = placed(env)
        assertEqual("TOPLEFT", point)
        local _, _, _, x = env.PlayerFrame:GetPoint(1)
        assertEqual(-19, x, "still where the game put it")

        env.__inCombat = false
        helpers.fire(env, "PLAYER_REGEN_ENABLED")

        local _, _, _, movedX, movedY = placed(env)
        assertEqual(4, movedX, "at the left edge")
        assertEqual(-4, movedY)
    end)

    it("leaves it alone while Edit Mode is open, so it can be dragged", function()
        local _, env = loggedIn(function(_, e)
            e.EditModeManagerFrame = { IsEditModeActive = function() return true end }
        end)

        local _, _, _, x = placed(env)
        assertEqual(-19, x)
    end)

    it("follows the gap setting", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "portraitGap"), 10)

        local _, _, _, _, y = placed(env)
        assertEqual(-10, y)
    end)

    it("gives the game its own place back when turned off", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "portraitBelowBar"), false)

        local point, relative, relativePoint, x, y = placed(env)
        assertEqual("TOPLEFT", point)
        assertEqual(env.UIParent, relative)
        assertEqual("TOPLEFT", relativePoint)
        assertEqual(-19, x)
        assertEqual(-4, y)
    end)

    it("does nothing on a client without a player frame", function()
        local _, env = loggedIn(function(_, e) e.PlayerFrame = nil end)
        assertNil(env.PlayerFrame)
    end)
end)
