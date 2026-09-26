local helpers = require("helpers")

describe("chance text", function()
    local ns = helpers.loadAddon({ "BossLoot.lua", "Format.lua" })

    it("shows one decimal under ten percent", function()
        assertEqual("1.8%", ns.Format.Chance(1.8))
        assertEqual("0.5%", ns.Format.Chance(0.5))
    end)

    it("shows whole numbers from ten percent up", function()
        assertEqual("14%", ns.Format.Chance(14.2))
        assertEqual("100%", ns.Format.Chance(100))
    end)

    it("does not print 10.0% for a chance that rounds up to ten", function()
        assertEqual("10%", ns.Format.Chance(9.96))
    end)

    it("says under 0.1% rather than 0.0%", function()
        assertEqual("<0.1%", ns.Format.Chance(0.04))
    end)
end)

describe("quality colours", function()
    local ns = helpers.loadAddon({ "BossLoot.lua", "Format.lua" })

    it("colours text by quality", function()
        assertEqual("|cffa335eeIronfoe|r", ns.Format.Colored("Ironfoe", 4))
    end)

    it("falls back to white for an unknown quality", function()
        assertEqual("ffffff", ns.Format.QualityHex(nil))
    end)
end)

describe("type labels", function()
    local ns = helpers.loadAddon({ "BossLoot.lua", "Format.lua" })

    it("names the slot and the kind of item", function()
        assertEqual("Two-Hand, Maces", ns.Format.TypeLabel("Weapon", "Maces", "INVTYPE_2HWEAPON"))
    end)

    it("names the type for something that is not worn", function()
        assertEqual("Recipe, Tailoring", ns.Format.TypeLabel("Recipe", "Tailoring", ""))
        assertEqual("Key", ns.Format.TypeLabel("Key", "Key", ""))
    end)
end)
