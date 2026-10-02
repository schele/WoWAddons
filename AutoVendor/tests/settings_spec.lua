local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

--- Logged in with the page on screen, as the options window shows it.
local function opened()
    local ns, env = loggedIn()
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- The rows the page is showing, top to bottom: rows are kept for reuse, so
-- one hidden is not part of the list.
local function shownRows(panel)
    local rows = {}
    for _, row in ipairs(panel.rows) do
        if row.frame:IsShown() then
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function shownNames(panel)
    local names = {}
    for _, row in ipairs(shownRows(panel)) do
        names[#names + 1] = row.label:GetText()
    end
    return table.concat(names, ", ")
end

local function hasText(frame, pattern)
    for _, fontString in ipairs(frame.fontStrings or {}) do
        if tostring(fontString:GetText()):find(pattern) then
            return true
        end
    end
    return false
end

describe("the settings page", function()
    it("is a page in the game's options, named AutoVendor", function()
        local _, env = loggedIn()
        assertEqual("AutoVendor", env.__settingsCategory.name)
    end)

    it("opens from /av settings", function()
        local _, env = loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("is in /av's help", function()
        local _, env = loggedIn()
        helpers.command(env, "help")
        assertMatch("/av settings", helpers.printed(env))
    end)

    it("heads the page with AutoVendor's own logo, not the tiled icon", function()
        local _, _, panel = opened()
        assertEqual("Interface\\AddOns\\AutoVendor\\logo", panel.logo:GetTexture())
    end)

    it("shows the version from the addon's metadata", function()
        local _, _, panel = opened()
        assertTrue(hasText(panel.panel, "^Version 9%.9%.9$"))
    end)

    it("says what AutoVendor does", function()
        local _, _, panel = opened()
        assertTrue(hasText(panel.panel, "grey"))
    end)

    it("is not built until it is first shown", function()
        local ns = loggedIn()
        assertNil(ns.SettingsPanel.logo)
    end)

    it("says so on a client without a settings panel", function()
        local ns, env = helpers.loadAddon()
        env.Settings = nil
        helpers.login(env)
        helpers.command(env, "settings")
        assertMatch("no settings panel", helpers.printed(env))
    end)
end)

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

describe("the page's switches", function()
    it("are both ticked to begin with", function()
        local _, _, panel = opened()
        assertTrue(panel.sell:GetChecked())
        assertTrue(panel.repair:GetChecked())
    end)

    it("turn repairs off and on again", function()
        local ns, _, panel = opened()
        click(panel.repair)
        assertFalse(ns.db.repair)
        click(panel.repair)
        assertTrue(ns.db.repair)
    end)

    it("turn selling off and on again", function()
        local ns, _, panel = opened()
        click(panel.sell)
        assertFalse(ns.db.sell)
        click(panel.sell)
        assertTrue(ns.db.sell)
    end)

    it("are labelled with what they do", function()
        local _, _, panel = opened()
        assertTrue(hasText(panel.repair, "^Repair my gear at merchants that can$"))
        assertTrue(hasText(panel.sell, "^Sell grey items$"))
    end)

    it("follow /av repair and /av sell while the page is open", function()
        local _, env, panel = opened()
        helpers.command(env, "repair")
        assertFalse(panel.repair:GetChecked())
        helpers.command(env, "sell")
        assertFalse(panel.sell:GetChecked())
    end)

    it("show what was saved before a reload", function()
        local _, env = loggedIn()
        helpers.command(env, "repair")
        local ns = helpers.reload(env)
        ns.SettingsPanel.panel:Show()
        assertFalse(ns.SettingsPanel.repair:GetChecked())
        assertTrue(ns.SettingsPanel.sell:GetChecked())
    end)
end)

--- What `widget` is first anchored to, and how far below it.
local function anchor(widget)
    local point = widget.points[1]
    return point[2], point[3], point[5]
end

describe("the page's layout", function()
    -- Each part hangs from the one above it, so a description that wraps to
    -- another line pushes the rest down instead of running into it.
    it("puts the switches under the description, then the list's heading under them", function()
        local _, _, panel = opened()
        local to, where, y = anchor(panel.sell)
        assertEqual(panel.hint, to)
        assertEqual("BOTTOMLEFT", where)
        assertEqual(-16, y)
        assertEqual(panel.sell, (anchor(panel.repair)))
        assertEqual(panel.repair, (anchor(panel.heading)))
    end)

    it("puts the list just under its heading", function()
        local ns, env = loggedIn()
        helpers.command(env, "keep 3300")
        helpers.command(env, "keep 7073")
        local panel = ns.SettingsPanel
        panel.panel:Show()

        local to, where, y = anchor(panel.rows[1].frame)
        assertEqual(panel.heading, to)
        assertEqual("BOTTOMLEFT", where)
        assertTrue(y <= -8 and y >= -10, "a small gap under the heading")
        local _, _, second = anchor(panel.rows[2].frame)
        assertTrue(second < y, "the second row below the first")
        assertEqual(panel.heading, (anchor(panel.empty)))
    end)
end)

describe("the page's kept items", function()
    it("says nothing is kept, and how to keep something", function()
        local _, _, panel = opened()
        assertEqual("", shownNames(panel))
        assertTrue(panel.empty:IsShown())
        assertMatch("/av keep", panel.empty:GetText())
        assertMatch("Shift%-click", panel.empty:GetText())
    end)

    it("lists every kept item by name, in name order", function()
        local ns, env = loggedIn()
        helpers.command(env, "keep 3300")
        helpers.command(env, "keep 7073")
        ns.SettingsPanel.panel:Show()
        assertEqual("Broken Fang, Rabbit's Foot", shownNames(ns.SettingsPanel))
        assertFalse(ns.SettingsPanel.empty:IsShown())
    end)

    it("sells an item again from its row's button, as /av unkeep does", function()
        local ns, env = loggedIn()
        helpers.command(env, "keep 3300")
        helpers.command(env, "keep 7073")
        local panel = ns.SettingsPanel
        panel.panel:Show()

        local fang = shownRows(panel)[1]
        fang.button.scripts.OnClick(fang.button)

        assertFalse(ns.Keep.Has(7073))
        assertTrue(ns.Keep.Has(3300))
        assertMatch("No longer keeping %[Broken Fang%]%.", helpers.printed(env))
        assertEqual("Rabbit's Foot", shownNames(panel))
    end)

    it("says nothing is kept once the last one is sold again", function()
        local ns, env = loggedIn()
        helpers.command(env, "keep 7073")
        local panel = ns.SettingsPanel
        panel.panel:Show()

        local row = shownRows(panel)[1]
        row.button.scripts.OnClick(row.button)

        assertEqual("", shownNames(panel))
        assertTrue(panel.empty:IsShown())
    end)

    it("follows /av keep and /av unkeep while the page is open", function()
        local _, env, panel = opened()
        helpers.command(env, "keep " .. env.__link(7073))
        assertEqual("Broken Fang", shownNames(panel))
        helpers.command(env, "keep 3300")
        assertEqual("Broken Fang, Rabbit's Foot", shownNames(panel))
        helpers.command(env, "unkeep 7073")
        assertEqual("Rabbit's Foot", shownNames(panel))
    end)

    it("shows what was kept since it was last open", function()
        local ns, env, panel = opened()
        panel.panel:Hide()
        ns.db.keep[1411] = "Withered Staff"
        panel.panel:Show()
        assertEqual("Withered Staff", shownNames(panel))
    end)
end)

describe("closing the page", function()
    -- Opening a page by command leaves the client queued to fall back to the
    -- game menu when it closes, which is not where the player came from.
    it("does not leave the game menu behind", function()
        local ns, env = loggedIn()
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        assertFalse(env.GameMenuFrame:IsShown(), "gone before a frame is drawn")
    end)

    it("leaves the game menu alone when the player opened the page from it", function()
        local ns, env = loggedIn()
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.__runTimers()

        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        env.__runTimers()
        assertTrue(env.GameMenuFrame:IsShown(), "left where the client put it")
    end)
end)
