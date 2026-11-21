local helpers = require("helpers")

local PARTY = {
    { "party1", "Brann", "ROGUE" },
    { "party2", "Celia", "MAGE" },
    { "party3", "Dorn", "PRIEST" },
}

local function frame(ns)
    return ns.Window.frame
end

local function row(ns, index)
    return ns.Window.rows[index]
end

describe("the window", function()
    it("is the game's own window frame, as BossLoot's is", function()
        local ns = helpers.fighting({ player = 100 })

        local f = frame(ns)
        assertEqual("SettingsFrameTemplate", f.template)
        assertEqual("Threat", f.title:GetText())
        assertEqual("Interface\\AddOns\\ThreatForever\\logo", f.logo:GetTexture())
        assertEqual(1, f.background.color[4], "solid, never see-through")
    end)

    it("stays hidden out of combat", function()
        local ns = helpers.loggedIn()

        assertFalse(frame(ns):IsShown())
    end)

    it("shows in combat and hides after", function()
        local ns, env = helpers.fighting({ player = 100 })
        assertTrue(frame(ns):IsShown(), "in combat")

        helpers.combat(env, false)
        assertFalse(frame(ns):IsShown(), "after")
    end)

    it("stays up out of combat with 'only in combat' off", function()
        local ns = helpers.loggedIn(function(env)
            env.ThreatForeverDB = { settings = { combatOnly = false } }
        end)

        assertTrue(frame(ns):IsShown())
    end)
end)

describe("the rows", function()
    it("list everyone on the threat list, the most first", function()
        local ns = helpers.fighting({ player = 100, party1 = 72, party2 = 91 }, PARTY)

        assertEqual("Skyler", row(ns, 1).name:GetText())
        assertEqual("100%", row(ns, 1).amount:GetText())
        assertEqual(100, row(ns, 1).bar:GetValue())
        assertEqual("Celia", row(ns, 2).name:GetText())
        assertEqual("91%", row(ns, 2).amount:GetText())
        assertEqual("Brann", row(ns, 3).name:GetText())
        assertFalse(row(ns, 4):IsShown(), "Dorn has no threat")
    end)

    it("fill a bar out of what it takes to pull aggro", function()
        local ns = helpers.fighting({ player = 100, party2 = 91 }, PARTY)

        assertEqual(0, row(ns, 2).bar.min)
        assertEqual(100, row(ns, 2).bar.max)
    end)

    it("colour each bar by class", function()
        local ns, env = helpers.fighting({ player = 100, party2 = 91 }, PARTY)

        local mage = env.RAID_CLASS_COLORS.MAGE
        local color = row(ns, 2).bar.barColor
        assertEqual(mage.r, color[1])
        assertEqual(mage.b, color[3])
    end)

    it("keep up as threat changes", function()
        local ns, env = helpers.fighting({ player = 100, party1 = 72, party2 = 91 }, PARTY)

        helpers.threat(env, "party1", 96)

        assertEqual("Brann", row(ns, 2).name:GetText())
        assertEqual("96%", row(ns, 2).amount:GetText())
    end)

    it("make the window as tall as they need", function()
        local ns, env = helpers.fighting({ player = 100 }, PARTY)
        local one = frame(ns):GetHeight()

        helpers.threat(env, "party1", 50)
        helpers.threat(env, "party2", 40)

        assertTrue(frame(ns):GetHeight() > one, "taller with three")
    end)
end)

describe("the mob line", function()
    it("names the mob", function()
        local ns = helpers.fighting({ player = 100 })

        assertEqual("Defias Pillager", frame(ns).mob:GetText())
    end)

    it("says when no enemy is targeted", function()
        local ns, env = helpers.fighting({ player = 100 })

        helpers.target(env, nil)

        assertEqual("No enemy targeted", frame(ns).mob:GetText())
        assertFalse(row(ns, 1):IsShown())
    end)
end)

describe("on a boss", function()
    local function bossFight()
        local ns, env = helpers.loggedIn(function(env)
            for _, member in ipairs(PARTY) do helpers.member(env, member[1], member[2], member[3]) end
        end)
        helpers.mob(env, "mob", "Edwin VanCleef", { boss = true })
        helpers.target(env, "mob")
        helpers.combat(env, true)
        helpers.threat(env, "player", 80, 0)
        helpers.threat(env, "party1", 100, 3)
        helpers.threat(env, "party3", 95, 1)
        return ns, env
    end

    it("draws the hidden numbers on the bars", function()
        local ns, env = bossFight()

        assertTrue(env.issecretvalue(row(ns, 1).bar:GetValue()))
    end)

    it("says who tanks and who is over the tank where it cannot write the number", function()
        local ns = bossFight()

        assertEqual("Tanking", row(ns, 1).amount:GetText())
        assertEqual("Over tank", row(ns, 2).amount:GetText())
        assertEqual("", row(ns, 3).amount:GetText())
    end)

    it("writes the hidden number where the game lets it", function()
        local ns, env = bossFight()
        for _, r in ipairs(ns.Window.rows) do
            function r.amount:SetFormattedText(_, value) self.text = value end
        end

        helpers.threat(env, "party3", 95, 1)

        assertTrue(env.issecretvalue(row(ns, 1).amount:GetText()))
    end)

    it("says the game hides the numbers", function()
        local ns = bossFight()

        assertEqual("The game hides the numbers on this one.", frame(ns).footer:GetText())
    end)

    it("says nothing of it on a mob that shows them", function()
        local ns = helpers.fighting({ player = 100 })

        assertEqual("", frame(ns).footer:GetText())
    end)
end)

describe("turning it off and on", function()
    it("turns off with its red X and says how to get it back", function()
        local ns, env = helpers.fighting({ player = 100 })

        frame(ns).close:GetScript("OnClick")(frame(ns).close)

        assertFalse(frame(ns):IsShown())
        assertFalse(ns.settings.shown)
        assertMatch("/threat", helpers.printed(env))
    end)

    it("stays off through the next fight", function()
        local ns, env = helpers.fighting({ player = 100 })
        frame(ns).close:GetScript("OnClick")(frame(ns).close)

        helpers.combat(env, false)
        helpers.combat(env, true)

        assertFalse(frame(ns):IsShown())
    end)

    it("comes back on with /threat", function()
        local ns, env = helpers.fighting({ player = 100 })
        frame(ns).close:GetScript("OnClick")(frame(ns).close)

        helpers.command(env, "")

        assertTrue(ns.settings.shown)
        assertTrue(frame(ns):IsShown())
    end)

    it("says it waits for combat when turned on outside it", function()
        local ns, env = helpers.loggedIn(function(env)
            env.ThreatForeverDB = { settings = { shown = false } }
        end)

        helpers.command(env, "")

        assertMatch("It shows when you are in combat%.", helpers.printed(env))
    end)
end)

describe("its place", function()
    it("is remembered where it was dragged", function()
        local ns, env = helpers.fighting({ player = 100 })
        local f = frame(ns)

        f:GetScript("OnDragStart")(f)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 120, -340)
        f:GetScript("OnDragStop")(f)

        local saved = ns.settings.window
        assertEqual("TOPLEFT", saved.point)
        assertEqual(120, saved.x)
        assertEqual(-340, saved.y)
    end)

    it("is where it was left at the next login", function()
        local ns = helpers.loggedIn(function(env)
            env.ThreatForeverDB = { settings = {
                window = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 120, y = -340 },
            } }
        end)

        local point, _, relativePoint, x, y = frame(ns):GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertEqual("TOPLEFT", relativePoint)
        assertEqual(120, x)
        assertEqual(-340, y)
    end)
end)
