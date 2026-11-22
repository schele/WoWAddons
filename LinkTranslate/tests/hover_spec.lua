local helpers = require("helpers")

local link = helpers.link

local FRENCH = link("quest", "2945:28", "La fiancée de l'Embaumeur")

local function translated()
    local ns, env = helpers.loggedIn(function(env)
        env.__names.quest[2945] = "Bride of the Embalmer"
    end)
    helpers.say(env, FRENCH)
    return ns, env
end

describe("pointing at a changed link", function()
    it("shows what the sender's game calls it", function()
        local _, env = translated()
        helpers.pointAt(env, env.ChatFrame1, "quest:2945:28")
        local tooltip = env.GameTooltip
        assertTrue(tooltip:IsShown())
        assertEqual(env.ChatFrame1, tooltip:GetOwner())
        assertEqual("ANCHOR_CURSOR", tooltip.anchor)
        assertEqual("La fiancée de l'Embaumeur", tooltip.lines[1][1])
        assertEqual("What the sender's game calls it", tooltip.lines[2][1])
    end)

    it("hides the tooltip again on moving off it", function()
        local _, env = translated()
        helpers.pointAt(env, env.ChatFrame1, "quest:2945:28")
        helpers.pointAway(env, env.ChatFrame1)
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("leaves a tooltip something else has taken over since", function()
        local _, env = translated()
        helpers.pointAt(env, env.ChatFrame1, "quest:2945:28")
        env.GameTooltip:SetOwner(env.UIParent, "ANCHOR_NONE")
        helpers.pointAway(env, env.ChatFrame1)
        assertTrue(env.GameTooltip:IsShown())
    end)

    it("shows nothing for a link it did not change", function()
        local _, env = translated()
        helpers.pointAt(env, env.ChatFrame1, "quest:176:10")
        helpers.pointAt(env, env.ChatFrame1, "player:Tranzalorr:12")
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("shows nothing with the switch off", function()
        local ns, env = translated()
        ns.settings.hover = false
        helpers.pointAt(env, env.ChatFrame1, "quest:2945:28")
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("leaves the tooltip alone on moving off a link it showed nothing for", function()
        local _, env = translated()
        env.GameTooltip:SetOwner(env.ChatFrame1, "ANCHOR_CURSOR")
        env.GameTooltip:Show()
        helpers.pointAway(env, env.ChatFrame1)
        assertTrue(env.GameTooltip:IsShown())
    end)
end)

describe("pointing at a link on a client without EventRegistry's chat events", function()
    it("is heard through each chat window's own handlers", function()
        local _, env = helpers.loggedIn(function(env)
            env.__names.quest[2945] = "Bride of the Embalmer"
            env.ChatFrameMixin = nil
        end)
        helpers.say(env, FRENCH)
        assertNil(env.__callbacks["ChatFrame.OnHyperlinkEnter"])
        env.ChatFrame2.scripts.OnHyperlinkEnter(env.ChatFrame2, "quest:2945:28", "[Bride of the Embalmer]")
        assertEqual("La fiancée de l'Embaumeur", env.GameTooltip.lines[1][1])
        env.ChatFrame2.scripts.OnHyperlinkLeave(env.ChatFrame2)
        assertFalse(env.GameTooltip:IsShown())
    end)
end)
