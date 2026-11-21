local helpers = require("helpers")

local function headings(ns)
    local out = {}
    for index, header in ipairs(ns.Window.headers) do
        if header:IsShown() then
            out[#out + 1] = header:GetText()
        end
    end
    return table.concat(out, ", ")
end

describe("/threat demo", function()
    it("shows the window out of combat, with made-up mobs and a party", function()
        local ns, env = helpers.loggedIn()

        helpers.command(env, "demo")

        assertTrue(ns.Window.frame:IsShown())
        assertEqual("Defias Pillager, Defias Thug, Defias Looter", headings(ns))
        assertEqual("Brann", ns.Window.rows[1].name:GetText(), "the tank first")
        assertMatch("[Mm]ade%-up", ns.Window.frame.footer:GetText())
    end)

    it("puts you in it, by your own name", function()
        local ns, env = helpers.loggedIn()

        helpers.command(env, "demo")

        local names = {}
        for _, row in ipairs(ns.Window.rows) do
            if row:IsShown() then names[#names + 1] = row.name:GetText() end
        end
        assertMatch("Skyler", table.concat(names, ","))
    end)

    it("follows the settings: how many mobs, and a part per mob or not", function()
        local ns, env = helpers.loggedIn(function(env)
            env.ThreatForeverDB = { settings = { maxMobs = 2 } }
        end)
        helpers.command(env, "demo")
        assertEqual("Defias Pillager, Defias Thug", headings(ns))

        ns.settings.split = false
        ns.Refresh()
        env.__runTimers()

        assertEqual("Defias Pillager", headings(ns))
        assertTrue(ns.Window.rows[6]:IsShown(), "one mob, all its rows")
    end)

    it("shows even with the window turned off", function()
        local ns, env = helpers.loggedIn(function(env)
            env.ThreatForeverDB = { settings = { shown = false } }
        end)

        helpers.command(env, "demo")

        assertTrue(ns.Window.frame:IsShown())
    end)

    it("ends with /threat demo again", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "demo")

        helpers.command(env, "demo")

        assertFalse(ns.Window.frame:IsShown(), "out of combat, the window waits again")
        assertMatch("Demo ended", helpers.printed(env))
    end)

    it("ends when a real fight starts", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "demo")
        helpers.mob(env, "mob", "Kobold Vermin")
        helpers.target(env, "mob")

        helpers.combat(env, true)

        assertEqual("Kobold Vermin", ns.Window.headers[1]:GetText())
        assertEqual("", ns.Window.frame.footer:GetText())
    end)

    it("never sets off the warning", function()
        local _, env = helpers.loggedIn()

        helpers.command(env, "demo")

        assertEqual(0, #env.__warnings)
        assertEqual(0, #env.__sounds)
    end)

    it("is in the help", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "help")
        assertMatch("/threat demo %- ", helpers.printed(env))
    end)
end)
