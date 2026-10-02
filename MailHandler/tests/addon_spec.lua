local helpers = require("helpers")

describe("the addon's chat lines", function()
    it("start with its name", function()
        local ns, env = helpers.loadAddon()

        ns.Print("hello")

        assertMatch("^|cff66ccffMailHandler|r hello$", helpers.printed(env))
    end)
end)

describe("money words", function()
    it("spell out gold, silver and copper", function()
        local ns = helpers.loadAddon()

        assertEqual("1g 23s 45c", ns.Money(12345))
    end)

    it("leave out the parts that are zero", function()
        local ns = helpers.loadAddon()

        assertEqual("5s", ns.Money(500))
        assertEqual("1g 2s", ns.Money(10200))
    end)

    it("say 0c for nothing", function()
        local ns = helpers.loadAddon()

        assertEqual("0c", ns.Money(0))
    end)

    it("are the client's own where it has them", function()
        local ns, env = helpers.loadAddon()
        env.GetMoneyString = function(copper) return "MONEY:" .. copper end

        assertEqual("MONEY:5", ns.Money(5))
    end)
end)

describe("counting", function()
    it("says one mail, or a number of mails", function()
        local ns = helpers.loadAddon()

        assertEqual("1 mail", ns.Count(1, "mail"))
        assertEqual("3 items", ns.Count(3, "item"))
    end)
end)

describe("a change", function()
    it("does nothing while there are no buttons", function()
        local ns = helpers.loadAddon()

        ns.Changed()
    end)
end)
