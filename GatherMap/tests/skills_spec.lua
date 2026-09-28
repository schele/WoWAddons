local helpers = require("helpers")

describe("the player's skills", function()
    it("are read from the skill list by name, skipping headers", function()
        local ns = helpers.loggedIn()
        assertEqual(50, ns.Skills.Get("herb"))
        assertEqual(70, ns.Skills.Get("ore"))
    end)

    it("are found in another client language", function()
        local ns = helpers.loggedIn(function(env)
            env.__skills = { { "Berufe", true }, { "Bergbau", false, 120 }, { "Kräuterkunde", false, 30 } }
        end)
        assertEqual(120, ns.Skills.Get("ore"))
        assertEqual(30, ns.Skills.Get("herb"))
    end)

    it("are 0 without the profession", function()
        local ns = helpers.loggedIn(function(env) env.__skills = { { "Professions", true } } end)
        assertEqual(0, ns.Skills.Get("herb"))
        assertEqual(0, ns.Skills.Get("ore"))
        assertEqual(0, ns.Skills.Get("pool"))
    end)

    it("are read again when they change, and the pins redrawn", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        env.__skills[3] = { "Mining", false, 71 }
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertEqual(71, ns.Skills.Get("ore"))
        assertEqual(1, count)
    end)

    it("stay as they were when the client refuses", function()
        local ns, env = helpers.loggedIn()
        env.GetSkillLineInfo = function() error("secret") end
        ns.Skills.Read()
        assertEqual(70, ns.Skills.Get("ore"))
    end)

    it("stay as they were while a header is collapsed and hides one", function()
        local ns, env = helpers.loggedIn()
        env.__skills = { { "Professions", true, nil, false } }
        ns.Skills.Read()
        assertEqual(70, ns.Skills.Get("ore"), "a collapsed header is not a forgotten profession")
        assertEqual(50, ns.Skills.Get("herb"))
    end)
end)

describe("a node's colour", function()
    it("follows the skill-up bands", function()
        local ns = helpers.loggedIn()
        assertEqual("red", ns.Skills.Color(100, 99))
        assertEqual("orange", ns.Skills.Color(100, 100))
        assertEqual("orange", ns.Skills.Color(100, 124))
        assertEqual("yellow", ns.Skills.Color(100, 125))
        assertEqual("yellow", ns.Skills.Color(100, 149))
        assertEqual("green", ns.Skills.Color(100, 150))
        assertEqual("green", ns.Skills.Color(100, 199))
        assertEqual("grey", ns.Skills.Color(100, 200))
    end)
end)
