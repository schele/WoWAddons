local helpers = require("helpers")

describe("the addon's chat lines", function()
    it("start with its name", function()
        local ns, env = helpers.loadAddon()

        ns.Print("hello")

        assertMatch("^|cff66ccffRankUp|r hello$", helpers.printed(env))
    end)
end)

describe("counting buttons", function()
    it("says one button, or a number of buttons", function()
        local ns = helpers.loadAddon()

        assertEqual("1 button", ns.Buttons(1))
        assertEqual("2 buttons", ns.Buttons(2))
    end)
end)
