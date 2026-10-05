local helpers = require("helpers")

-- Feral Instinct x2, then Ferocity, then Thick Hide... all in Feral Combat.
local function savedPlan(extra)
    local saved = { chars = { ["Skyler-Aldira"] = {
        active = "Feral", plans = { Feral = { class = "DRUID", points = { { 2, 2 }, { 2, 2 }, { 2, 1 } } } },
    } } }
    for key, value in pairs(extra or {}) do saved[key] = value end
    return saved
end

--- Logged in, then the talent window loaded and shown on the Feral tab.
local function withTalentUI(saved, prepare, player)
    local ns, env = helpers.loggedIn(saved or savedPlan(), prepare)
    local frame = env.__makeTalentUI(player)
    helpers.fire(env, "ADDON_LOADED", "Blizzard_TalentUI")
    frame.selectedTab = 2
    env[player and "PlayerTalentFrame_Update" or "TalentFrame_Update"]()
    return ns, env, frame
end

local function overlay(ns, env, index, prefix)
    return ns.TalentFrame.Overlays()[env[(prefix or "TalentFrame") .. "Talent" .. index]]
end

describe("the talent window overlay", function()
    it("attaches when the game loads its talent window", function()
        local ns, env = withTalentUI()
        assertEqual("2 planned", overlay(ns, env, 2).label:GetText())
        assertTrue(overlay(ns, env, 2).label:IsShown())
        assertEqual("1 planned", overlay(ns, env, 1).label:GetText())
        assertFalse(overlay(ns, env, 3).label:IsShown(), "nothing planned on Thick Hide")
    end)

    it("attaches at login when the talent window is already loaded", function()
        local ns, env = helpers.loggedIn(savedPlan(), function(env)
            env.__makeTalentUI(false).selectedTab = 2
        end)
        assertEqual("2 planned", overlay(ns, env, 2).label:GetText())
    end)

    it("knows the talent window by its later name too", function()
        local ns, env = withTalentUI(nil, nil, true)
        assertEqual("2 planned", overlay(ns, env, 2, "PlayerTalentFrame").label:GetText())
    end)

    it("follows the tab shown", function()
        local ns, env, frame = withTalentUI()
        frame.selectedTab = 1
        env.TalentFrame_Update()
        assertFalse(overlay(ns, env, 2).label:IsShown(), "Nature's Grasp is not planned")
    end)

    it("takes the tab from PanelTemplates when the client has it", function()
        local ns, env, frame = withTalentUI(nil, function(env)
            env.PanelTemplates_GetSelectedTab = function(f) return f.panelTab end
        end)
        frame.panelTab = 2
        frame.selectedTab = 1
        env.TalentFrame_Update()
        assertTrue(overlay(ns, env, 2).label:IsShown())
    end)

    it("lights the next planned talent", function()
        local ns, env = withTalentUI()
        assertTrue(overlay(ns, env, 2).glow:IsShown())
        assertFalse(overlay(ns, env, 1).glow:IsShown())
    end)

    it("moves the light once the point is learned", function()
        local ns, env = withTalentUI()
        env.__ranks[2][2] = 2
        helpers.fire(env, "CHARACTER_POINTS_CHANGED", -1)
        assertFalse(overlay(ns, env, 2).glow:IsShown())
        assertTrue(overlay(ns, env, 1).glow:IsShown())
    end)

    it("marks a talent with more points than planned by now", function()
        local ns, env = withTalentUI(nil, function(env)
            env.__ranks[2][1] = 1
            env.__ranks[2][2] = 1
        end)
        env.TalentFrame_Update()
        assertTrue(overlay(ns, env, 1).edge:IsShown(), "Ferocity was planned third")
        assertFalse(overlay(ns, env, 2).edge:IsShown())
    end)

    it("redraws when the plan changes", function()
        local ns, env = withTalentUI()
        table.insert(ns.Plans.Active().points, { 2, 1 })
        ns.Changed()
        assertEqual("2 planned", overlay(ns, env, 1).label:GetText())
    end)

    it("hides with the setting off, and comes back with it on", function()
        local ns, env = withTalentUI()
        ns.SetSetting("overlay", false)
        assertFalse(overlay(ns, env, 2).label:IsShown())
        assertFalse(overlay(ns, env, 2).glow:IsShown())
        ns.SetSetting("overlay", true)
        assertTrue(overlay(ns, env, 2).label:IsShown())
    end)

    it("names the next talent on the window", function()
        local ns = withTalentUI()
        assertEqual("Next: Feral Instinct (1/5)", ns.TalentFrame.NextLabel():GetText())
    end)
end)

describe("Learn next on the talent window", function()
    it("is hidden while the setting is off", function()
        local ns = withTalentUI()
        assertFalse(ns.TalentFrame.LearnButton():IsShown())
    end)

    it("learns the next point with the setting on", function()
        local ns, env = withTalentUI(savedPlan({ learn = true }), function(env) env.__unspent = 1 end)
        local learn = ns.TalentFrame.LearnButton()
        assertTrue(learn:IsShown())
        learn:Click()
        assertEqual(1, env.__ranks[2][2])
    end)

    it("does nothing in combat", function()
        local ns, env = withTalentUI(savedPlan({ learn = true }), function(env) env.__unspent = 1 end)
        env.__inCombat = true
        ns.TalentFrame.LearnButton():Click()
        assertEqual(0, #env.__learned)
    end)

    it("shows when the setting is turned on", function()
        local ns = withTalentUI()
        ns.SetSetting("learn", true)
        assertTrue(ns.TalentFrame.LearnButton():IsShown())
    end)
end)
