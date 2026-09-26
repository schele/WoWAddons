local helpers = require("helpers")

local function textList(ns, env, rows, onClick)
    return ns.List.Create(env.UIParent, {
        width = 200, rowHeight = 18, rows = rows,
        createRow = ns.List.TextRow(onClick or function() end),
        renderRow = ns.List.RenderText,
    })
end

local function entries(count)
    local list = {}
    for index = 1, count do list[index] = { kind = "item", text = "Entry " .. index } end
    return list
end

describe("a scrolling list", function()
    it("shows as many entries as it has rows, and hides the spare rows", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(2))
        assertEqual("Entry 1", list.rows[1].text:GetText())
        assertTrue(list.rows[2]:IsShown())
        assertFalse(list.rows[3]:IsShown())
    end)

    it("scrolls, but never past either end", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(10))
        ns.List.Scroll(list, 5)
        assertEqual("Entry 6", list.rows[1].text:GetText())
        ns.List.Scroll(list, 100)
        assertEqual(7, list.offset)
        ns.List.Scroll(list, -100)
        assertEqual(0, list.offset)
    end)

    it("scrolls three rows a notch of the mouse wheel", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(10))
        list.scripts.OnMouseWheel(list, -1)
        assertEqual(3, list.offset)
    end)

    it("goes back to the top for new entries, unless told to keep its place", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(10))
        ns.List.Scroll(list, 4)
        ns.List.SetEntries(list, entries(10), true)
        assertEqual(4, list.offset)
        ns.List.SetEntries(list, entries(10))
        assertEqual(0, list.offset)
    end)

    it("keeps its place only as far as the new entries reach", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(10))
        ns.List.Scroll(list, 7)
        ns.List.SetEntries(list, entries(4), true)
        assertEqual(1, list.offset)
    end)

    it("passes a click on an entry, with the mouse button", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local clicked, button
        local list = textList(ns, env, 3, function(entry, mouseButton) clicked, button = entry, mouseButton end)
        ns.List.SetEntries(list, entries(2))
        list.rows[2].scripts.OnClick(list.rows[2], "RightButton")
        assertEqual("Entry 2", clicked.text)
        assertEqual("RightButton", button)
    end)

    it("does nothing for a click on a heading", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local clicked = false
        local list = textList(ns, env, 3, function() clicked = true end)
        ns.List.SetEntries(list, { { kind = "heading", text = "East" } })
        list.rows[1].scripts.OnClick(list.rows[1], "LeftButton")
        assertFalse(clicked)
    end)

    it("marks the selected entry", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, { { kind = "item", text = "A" }, { kind = "item", text = "B", selected = true } })
        assertFalse(list.rows[1].selectedTexture:IsShown())
        assertTrue(list.rows[2].selectedTexture:IsShown())
    end)
end)
