local helpers = require("helpers")

local function opened()
    local ns, env = helpers.loggedIn()
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

describe("the settings page", function()
    it("is a page in the game's options, named GatherMap, with its logo", function()
        local ns, env, panel = opened()
        assertEqual("GatherMap", env.__settingsCategory.name)
        assertEqual("Interface\\AddOns\\GatherMap\\minimap", panel.logo:GetTexture())
    end)

    it("opens from a bare /gmap and from /gmap settings", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "")
        assertEqual("category-id", env.__openedCategory)
        env.__openedCategory = nil
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("shows what is saved", function()
        local ns, env = helpers.loggedIn()
        ns.settings.minimap.kinds.ore = false
        ns.settings.worldmap.hidden.Silverleaf = true
        ns.settings.minimap.hideGrey = true
        ns.settings.worldmap.pinSize = 16
        local panel = ns.SettingsPanel
        panel.panel:Show()
        assertFalse(panel.kinds.ore.buttons.minimap:GetChecked())
        assertTrue(panel.kinds.ore.buttons.worldmap:GetChecked())
        assertFalse(panel.nodes.Silverleaf.buttons.worldmap:GetChecked())
        assertTrue(panel.nodes.Silverleaf.buttons.minimap:GetChecked())
        assertTrue(panel.filters.hideGrey.buttons.minimap:GetChecked())
        assertTrue(panel.filters.hideUngatherable.buttons.worldmap:GetChecked())
        assertEqual(16, panel.sizes.worldmap:GetValue())
        assertTrue(panel.enabled:GetChecked())
    end)
end)

describe("the page's switches", function()
    it("turn every pin off and on", function()
        local ns, env, panel = opened()
        click(panel.enabled)
        assertFalse(ns.settings.enabled)
        click(panel.enabled)
        assertTrue(ns.settings.enabled)
    end)

    it("turn a kind off on one map and redraw", function()
        local ns, env, panel = opened()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        click(panel.kinds.herb.buttons.minimap)
        assertFalse(ns.settings.minimap.kinds.herb)
        assertTrue(ns.settings.worldmap.kinds.herb)
        assertEqual(1, count)
    end)

    it("hide and show one node by name", function()
        local ns, env, panel = opened()
        click(panel.nodes["Copper Vein"].buttons.worldmap)
        assertTrue(ns.settings.worldmap.hidden["Copper Vein"])
        click(panel.nodes["Copper Vein"].buttons.worldmap)
        assertNil(ns.settings.worldmap.hidden["Copper Vein"])
    end)

    it("set the skill filters per map", function()
        local ns, env, panel = opened()
        click(panel.filters.hideUngatherable.buttons.minimap)
        click(panel.filters.hideGrey.buttons.worldmap)
        assertFalse(ns.settings.minimap.hideUngatherable)
        assertTrue(ns.settings.worldmap.hideUngatherable)
        assertTrue(ns.settings.worldmap.hideGrey)
        assertFalse(ns.settings.minimap.hideGrey)
        assertNil(panel.filters.onlyConfirmed)
        assertNil(panel.filters.showMissing)
    end)

    it("size the pins", function()
        local ns, env, panel = opened()
        panel.sizes.minimap:SetValue(14.4)
        assertEqual(14, ns.settings.minimap.pinSize)
    end)
end)

describe("a kind's checklist", function()
    it("lists its node names once each, by required skill, with the skill", function()
        local ns = helpers.loggedIn()
        local names = {}
        for _, node in ipairs(ns.SettingsPanel.NodeNames("herb")) do names[#names + 1] = node.name end
        assertEqual("Peacebloom,Silverleaf,Earthroot,Stranglekelp", table.concat(names, ","))
        ns.SettingsPanel.panel:Show()
        assertEqual("Earthroot (15)", ns.SettingsPanel.nodes.Earthroot.label:GetText())
        assertNil(ns.SettingsPanel.kinds.pool)
        assertNil(ns.SettingsPanel.kinds.chest)
    end)

    it("lists the unlisted nodes the player gathered too, by their loot's name", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local names = {}
        for _, node in ipairs(ns.SettingsPanel.NodeNames("ore")) do names[#names + 1] = node.name end
        assertEqual("Strange Ore,Copper Vein,Tin Vein,Silver Vein", table.concat(names, ","))
        ns.SettingsPanel.panel:Show()
        assertEqual("Strange Ore", ns.SettingsPanel.nodes["Strange Ore"].label:GetText())
    end)

    it("is folded away until its kind is opened", function()
        local ns, env, panel = opened()
        assertFalse(panel.nodes.Silverleaf.buttons.worldmap:IsShown())
        panel.kinds.herb.toggle.scripts.OnClick(panel.kinds.herb.toggle)
        assertTrue(panel.nodes.Silverleaf.buttons.worldmap:IsShown())
        assertTrue(panel.nodes.Silverleaf.label:IsShown())
        assertFalse(panel.nodes["Copper Vein"].buttons.worldmap:IsShown(), "other kinds stay folded")
        panel.kinds.herb.toggle.scripts.OnClick(panel.kinds.herb.toggle)
        assertFalse(panel.nodes.Silverleaf.buttons.worldmap:IsShown())
    end)

    it("hides or shows every node of its kind, on both maps, at once", function()
        local ns, env, panel = opened()
        panel.kinds.ore.none.scripts.OnClick(panel.kinds.ore.none)
        assertTrue(ns.settings.worldmap.hidden["Copper Vein"])
        assertTrue(ns.settings.minimap.hidden["Tin Vein"])
        assertNil(ns.settings.worldmap.hidden.Silverleaf, "herbs untouched")
        assertFalse(panel.nodes["Tin Vein"].buttons.minimap:GetChecked())
        panel.kinds.ore.all.scripts.OnClick(panel.kinds.ore.all)
        assertNil(ns.settings.worldmap.hidden["Copper Vein"])
        assertTrue(panel.nodes["Tin Vein"].buttons.minimap:GetChecked())
    end)
end)

describe("the page's layout", function()
    -- The hint wraps to as many lines as the font needs. Rows placed at a
    -- fixed height on the page let its last line crowd the first checkbox.
    it("hangs the first row off the bottom of the hint, with room to breathe", function()
        local ns, env, panel = opened()
        local point, relativeTo, relativePoint, x, y = panel.enabled:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertTrue(relativeTo == panel.hint, "anchored to the hint")
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(0, x, "the checkbox lines up with the hint, as before")
        assertTrue(y <= -16, "at least 16px below the hint")
    end)

    it("keeps the rows below it in order, and their labels beside them", function()
        local ns, env, panel = opened()
        local _, _, _, _, enabledY = panel.enabled:GetPoint(1)
        local _, to, _, x, y = panel.filters.show.buttons.worldmap:GetPoint(1)
        assertTrue(to == panel.hint)
        assertEqual(0, x)
        assertTrue(y < enabledY, "below the first row")
        local _, _, _, labelX, labelY = panel.filters.show.label:GetPoint(1)
        assertEqual(30 * 2 + 6, labelX, "past both checkbox columns, as before")
        assertEqual(y - 5, labelY, "on the same row")
    end)

    it("makes the scrolling page as tall as the hint really is", function()
        local ns, env, panel = opened()
        local content = panel.hint:GetParent()
        local toggle = panel.kinds.herb.toggle
        local function relaid(height)
            panel.hint.stringHeight = height
            toggle.scripts.OnClick(toggle)
            toggle.scripts.OnClick(toggle)
            return content:GetHeight()
        end
        assertEqual(50, relaid(80) - relaid(30), "a taller hint, a taller page")
        assertTrue(relaid(0) > 0, "and a guess when the client will not measure it")
    end)

    it("hides the scroll bar while everything fits, and brings it back when not", function()
        local _, _, panel = opened()
        local scroll = panel.hint:GetParent():GetParent()
        local function rangeChanged(range)
            scroll.scrollRange = range
            -- The template's own handler shows the bar, greyed out, first.
            scroll.ScrollBar:Show()
            scroll.scripts.OnScrollRangeChanged(scroll, 0, range)
        end

        rangeChanged(0)
        assertFalse(scroll.ScrollBar:IsShown())

        rangeChanged(120)
        assertTrue(scroll.ScrollBar:IsShown())
    end)

    it("hides the scroll bar on a page that fits from the moment it opens", function()
        local _, _, panel = opened()
        local scroll = panel.hint:GetParent():GetParent()

        assertFalse(scroll.ScrollBar:IsShown())
    end)
end)
