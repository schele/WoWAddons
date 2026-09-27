local helpers = require("helpers")
local FILES = { "BossLoot.lua", "Portrait.lua" }

describe("a boss portrait", function()
    it("is drawn from the boss's model", function()
        local ns, env = helpers.loadAddon(FILES)
        local texture = env.UIParent:CreateTexture()
        assertEqual("portrait", ns.Portrait.Set(texture, 8807))
        assertEqual(8807, texture.portraitDisplay)
    end)

    it("falls back to an icon without a model", function()
        local ns, env = helpers.loadAddon(FILES)
        local texture = env.UIParent:CreateTexture()
        assertEqual("icon", ns.Portrait.Set(texture, nil, "Interface\\Icons\\INV_Box_02"))
        assertEqual("Interface\\Icons\\INV_Box_02", texture:GetTexture())
    end)

    it("falls back to the skull on a client without portraits", function()
        local ns, env = helpers.loadAddon(FILES)
        env.SetPortraitTextureFromCreatureDisplayID = nil
        local texture = env.UIParent:CreateTexture()
        assertEqual("icon", ns.Portrait.Set(texture, 8807))
        assertEqual(ns.Portrait.ICONS.unknown, texture:GetTexture())
    end)

    it("falls back when the client refuses the model", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__badDisplay = 666
        local texture = env.UIParent:CreateTexture()
        assertEqual("icon", ns.Portrait.Set(texture, 666))
    end)
end)

describe("a boss model", function()
    it("shows the boss's model", function()
        local ns, env = helpers.loadAddon(FILES)
        local model = env.CreateFrame("PlayerModel")
        assertTrue(ns.Portrait.SetModel(model, 8807))
        assertEqual(8807, model.display)
    end)

    it("says it could not, without a model id or when the client refuses", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__badDisplay = 666
        local model = env.CreateFrame("PlayerModel")
        assertFalse(ns.Portrait.SetModel(model, nil))
        assertFalse(ns.Portrait.SetModel(model, 666))
    end)
end)
