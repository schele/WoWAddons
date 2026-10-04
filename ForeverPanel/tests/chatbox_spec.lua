local helpers = require("helpers")

--- Put a frame on screen: shown, its left, right and top edges at scale 1.
local function bar(frame, left, right, top)
    frame.left, frame.right, frame.top = left, right, top
    frame.shown = true
end

local function loggedIn(prepare)
    local ns, env = helpers.loadAddon()
    env.xp, env.xpMax = 500, 1000
    helpers.login(ns, env)
    env.UIParent.left, env.UIParent.bottom = 0, 0
    env.ChatFrame1.left, env.ChatFrame1.right, env.ChatFrame1.bottom = 32, 462, 95
    env.ChatFrame1:SetSize(430, 120)
    bar(env.MainActionBar, 20, 560, 50)
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
    assertEqual(1, #env.ChatFrame1.points, "one point, so nothing pulls it elsewhere")
    local point, relative, relativePoint, x, y = env.ChatFrame1:GetPoint(1)
    assertEqual("BOTTOMLEFT", point)
    assertEqual(env.UIParent, relative)
    assertEqual("BOTTOMLEFT", relativePoint)
    return x, y
end

describe("the chat box above the action bars", function()
    it("sits a few pixels over the main bar, where you put it left and right", function()
        local _, env = loggedIn()

        local x, y = placed(env)
        assertEqual(32, x)
        assertEqual(54, y)
    end)

    it("sits over the druid's form bar when that is the highest under it", function()
        local _, env = loggedIn(function(_, e) bar(e.StanceBar, 30, 200, 90) end)

        local _, y = placed(env)
        assertEqual(94, y)
    end)

    it("moves up when the form bar appears, and down when it goes", function()
        local _, env = loggedIn()
        bar(env.StanceBar, 30, 200, 90)
        env.StanceBar.shown = false
        env.StanceBar:Show()
        env.__runTimers()
        assertEqual(94, select(2, placed(env)))

        env.StanceBar:Hide()
        env.__runTimers()
        assertEqual(54, select(2, placed(env)))
    end)

    it("keeps the box you type in, under the chat box, clear of the bars too", function()
        local _, env = loggedIn(function(_, e)
            bar(e.StanceBar, 30, 200, 90)
            e.ChatFrame1EditBox = e.CreateFrame("EditBox", nil, e.ChatFrame1)
            e.ChatFrame1EditBox.bottom = 65 -- 30 under the chat box
        end)

        local _, y = placed(env)
        assertEqual(90 + 4 + 30, y, "the typing box's bottom the gap over the form bar")
    end)

    it("keeps room for the button that lands a flight, so a flight does not move it", function()
        local _, env = loggedIn(function(_, e)
            bar(e.StanceBar, 30, 200, 90)
            bar(e.MainMenuBarVehicleLeaveButton, 30, 62, 126)
            e.MainMenuBarVehicleLeaveButton.shown = false
        end)
        assertEqual(130, select(2, placed(env)), "clear of it while it is hidden")

        env.MainMenuBarVehicleLeaveButton:Show()
        env.__runTimers()
        assertEqual(130, select(2, placed(env)), "and still there when a flight shows it")
    end)

    it("makes room for the flight's button when it shows, if it had no place while hidden", function()
        local _, env = loggedIn()
        assertEqual(54, select(2, placed(env)))

        bar(env.MainMenuBarVehicleLeaveButton, 30, 62, 126)
        env.MainMenuBarVehicleLeaveButton.shown = false
        env.MainMenuBarVehicleLeaveButton:Show()
        env.__runTimers()
        assertEqual(130, select(2, placed(env)))
    end)

    it("pays no attention to a bar that is not under it", function()
        local _, env = loggedIn(function(_, e) bar(e.MultiBarBottomLeft, 600, 1000, 140) end)

        assertEqual(54, select(2, placed(env)))
    end)

    it("keeps its size: the height is yours", function()
        local _, env = loggedIn()

        assertEqual(430, env.ChatFrame1:GetWidth())
        assertEqual(120, env.ChatFrame1:GetHeight())
    end)

    it("works in the chat box's own scale", function()
        local _, env = loggedIn(function(_, e)
            e.ChatFrame1.scale = 0.8
            e.ChatFrame1.left = 40 -- 32 on screen
        end)

        local x, y = placed(env)
        assertEqual(40, x)
        assertEqual(54 / 0.8, y)
    end)

    it("goes back over the bars when the game puts the account's place back", function()
        local _, env = loggedIn()

        env.ChatFrame1:ClearAllPoints()
        env.ChatFrame1:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 32, 400)
        env.__runTimers()

        assertEqual(54, select(2, placed(env)))
    end)

    it("is left alone while Edit Mode is open, so it can be dragged", function()
        local _, env = loggedIn(function(_, e)
            e.EditModeManagerFrame = { IsEditModeActive = function() return true end }
        end)

        assertEqual(95, select(2, placed(env)))
    end)

    it("follows the gap setting", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "chatGap"), 10)

        assertEqual(60, select(2, placed(env)))
    end)

    it("gives the game its own place back when turned off", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "chatAboveBars"), false)

        local x, y = placed(env)
        assertEqual(32, x)
        assertEqual(95, y)
    end)
end)
