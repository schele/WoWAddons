local helpers = require("helpers")

local SLOT = helpers.SLOT

--- A druid with the set icon window open, its set's icon 136000. The
-- spellbook has Cat Form, Bear Form, Healing Touch and Claw; Defender of
-- Dalaran is worn and Feral Gloves are in the bags.
local function window(extra)
    local ns, env = helpers.start(nil, function(env)
        helpers.druid(env)
        env.__spellbook = {
            { name = "Cat Form", iconID = 132115 },
            { name = "Bear Form", iconID = 132276 },
            { name = "Healing Touch", iconID = 136041 },
            { name = "Claw", iconID = 132140 },
        }
        helpers.wear(env, SLOT.MAINHAND, "Defender of Dalaran")
        env.__itemInfo["Defender of Dalaran"].icon = 135000
        helpers.stow(env, "Feral Gloves", SLOT.HANDS)
        env.__itemInfo["Feral Gloves"].icon = 132939
        if extra then extra(env) end
    end)
    local popup = env.GearManagerPopupFrame
    popup.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(136000)
    popup:Show()
    return ns, env, popup, ns.IconSearch and ns.IconSearch.box
end

--- The icons the grid shows, comma separated.
local function shown(popup)
    local icons = {}
    for index = 1, popup.IconSelector:GetNumSelections() do
        icons[index] = tostring(popup.IconSelector:GetSelection(index))
    end
    return table.concat(icons, ",")
end

describe("searching the set icons", function()
    it("puts a search box in the set icon window, beside the icon type menu", function()
        local _, _, popup, box = window()
        assertTrue(box ~= nil, "a box")
        assertEqual("SearchBoxTemplate", box.template)
        assertEqual(popup.BorderBox, box:GetParent())
        assertEqual(popup.BorderBox.IconTypeDropdown, box.points[1][2])
    end)

    it("finds Cat Form's icon when you search for cat", function()
        local _, _, popup, box = window()
        box:Type("cat")
        assertEqual("132115", shown(popup))
    end)

    it("shows Cat Form's own icon while you are in Cat Form, not the stance bar's glow", function()
        local _, env, popup, box = window()
        env.__form = 3
        box:Type("cat")
        assertEqual("132115", shown(popup))
    end)

    it("does not mind capitals", function()
        local _, _, popup, box = window()
        box:Type("CAT")
        assertEqual("132115", shown(popup))
    end)

    it("finds part of a name", function()
        local _, _, popup, box = window()
        box:Type("heal")
        assertEqual("136041", shown(popup))
    end)

    it("finds the items you wear and carry", function()
        local _, _, popup, box = window()
        box:Type("dalaran")
        assertEqual("135000", shown(popup))
        box:Type("feral")
        assertEqual("132939", shown(popup))
    end)

    it("lists forms first, then spells, then items, each icon once", function()
        local _, _, popup, box = window()
        box:Type("form")
        assertEqual("132276,132112,132115,132144", shown(popup))
    end)

    it("keeps the set's icon marked when it is among the results", function()
        local _, _, popup, box = window()
        popup.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(132115)
        box:Type("cat")
        assertEqual(1, popup.IconSelector:GetSelectedIndex())
        box:Type("bear")
        assertNil(popup.IconSelector:GetSelectedIndex())
    end)

    it("gives the set the icon you click in the results", function()
        local _, _, popup, box = window()
        box:Type("bear")
        popup.IconSelector:OnSelection(1)
        assertEqual(132276, popup.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture())
    end)

    it("puts the game's full list back when the search is cleared", function()
        local _, _, popup, box = window()
        box:Type("cat")
        box:Type("")
        assertEqual(#popup.baseIcons, popup.IconSelector:GetNumSelections())
        assertEqual(132115, popup.IconSelector:GetSelection(4))
        assertEqual(popup:GetIndexOfIcon(136000), popup.IconSelector:GetSelectedIndex())
    end)

    it("starts empty each time the window opens", function()
        local _, _, popup, box = window()
        box:Type("cat")
        popup:Hide()
        assertEqual("", box:GetText())
        popup:Show()
        assertEqual(#popup.baseIcons, popup.IconSelector:GetNumSelections())
    end)

    it("leaves things be on a client without the window", function()
        local ns = helpers.start(nil, function(env)
            env.GearManagerPopupFrame = nil
        end)
        assertNil(ns.IconSearch and ns.IconSearch.box)
    end)
end)
