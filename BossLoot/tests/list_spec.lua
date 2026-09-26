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

describe("a list laid out as a grid", function()
    local function grid(ns, env)
        return ns.List.Create(env.UIParent, {
            width = 200, columnWidth = 100, columns = 2, rowHeight = 20, rows = 2,
            createRow = ns.List.TextRow(function() end), renderRow = ns.List.RenderText,
        })
    end

    it("fills rows left to right, then top to bottom", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = grid(ns, env)
        assertEqual(4, #list.rows)
        local _, _, _, x2, y2 = list.rows[2]:GetPoint(1)
        local _, _, _, x3, y3 = list.rows[3]:GetPoint(1)
        assertEqual(100, x2); assertEqual(0, y2)
        assertEqual(0, x3); assertEqual(-20, y3)
    end)

    it("scrolls a whole line at a time", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = grid(ns, env)
        ns.List.SetEntries(list, entries(7))
        ns.List.Scroll(list, 1)
        assertEqual(2, list.offset)
        assertEqual("Entry 3", list.rows[1].text:GetText())
        ns.List.Scroll(list, 5)
        assertEqual(4, list.offset, "four lines of entries, two shown")
    end)
end)

describe("the more-below line", function()
    it("says how many entries are below the visible rows", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(10))
        assertTrue(list.more:IsShown())
        assertMatch("7 more", list.more:GetText())
        ns.List.Scroll(list, 100)
        assertFalse(list.more:IsShown())
    end)
end)

describe("revealing an entry", function()
    it("scrolls just far enough to show it", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(10))
        ns.List.Reveal(list, 8)
        assertEqual(5, list.offset, "entry 8 on the bottom row")
        ns.List.Reveal(list, 2)
        assertEqual(1, list.offset, "entry 2 on the top row")
        ns.List.Reveal(list, 3)
        assertEqual(1, list.offset, "already in view: no scroll")
    end)
end)
