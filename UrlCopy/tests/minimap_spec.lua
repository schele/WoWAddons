local helpers = require("helpers")

-- Logged in with a minimap on screen, which the stub does not have, and
-- what is printed kept.
local function withMinimap()
    local ns, env = helpers.loadAddon()
    env.Minimap = env.CreateFrame("Frame", nil, env.UIParent)
    env.Minimap:SetSize(140, 140)
    env.__said = {}
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        table.insert(env.__said, table.concat(parts, " "))
    end
    helpers.login(ns, env)
    return ns, env
end

-- The game's options window, as far as a click needs it: closed to begin
-- with, and opening a category shows the window with that category's page.
local function withOptionsWindow()
    local ns, env = withMinimap()
    env.SettingsPanel:Hide()
    env.Settings.OpenToCategory = function()
        env.SettingsPanel:Show()
        env.__settingsCategory.frame:Show()
    end
    return ns, env
end

describe("the minimap button's geometry", function()
    local ns = helpers.loadAddon()

    it("puts angle 0 to the right and 90 at the top", function()
        local x, y = ns.MinimapButton.PositionFor(0, 80)
        assertNear(80, x)
        assertNear(0, y)
        x, y = ns.MinimapButton.PositionFor(90, 80)
        assertNear(0, x)
        assertNear(80, y)
    end)

    it("turns a cursor offset back into an angle between 0 and 360", function()
        assertNear(0, ns.MinimapButton.AngleFor(10, 0))
        assertNear(90, ns.MinimapButton.AngleFor(0, 10))
        assertNear(225, ns.MinimapButton.AngleFor(-10, -10))
    end)
end)

describe("the minimap button", function()
    it("sits on the minimap at its own angle, with UrlCopy's own icon", function()
        local ns, env = withMinimap()
        local button = ns.MinimapButton.Button()
        assertEqual(env.Minimap, button:GetParent())
        assertEqual(300, ns.db.minimap.angle)
        assertEqual("Interface\\AddOns\\UrlCopy\\logo", button.icon:GetTexture())
    end)

    it("opens the settings on a click, and closes them on the next", function()
        local ns, env = withOptionsWindow()
        local button = ns.MinimapButton.Button()
        button.scripts.OnClick(button, "LeftButton")
        assertTrue(env.SettingsPanel:IsShown())
        assertTrue(env.__settingsCategory.frame:IsShown(), "on this addon's own page")
        button.scripts.OnClick(button, "LeftButton")
        assertFalse(env.SettingsPanel:IsShown())
    end)

    it("turns the options window to its own page when another addon's is up", function()
        local ns, env = withOptionsWindow()
        env.SettingsPanel:Show()
        local button = ns.MinimapButton.Button()
        button.scripts.OnClick(button, "LeftButton")
        assertTrue(env.SettingsPanel:IsShown())
        assertTrue(env.__settingsCategory.frame:IsShown())
    end)

    it("hides and shows with /url minimap, says so, and remembers", function()
        local ns, env = withMinimap()
        helpers.command(env, "minimap")
        assertFalse(ns.MinimapButton.Button():IsShown())
        assertTrue(ns.db.minimap.hide)
        assertMatch("/url minimap brings it back", table.concat(env.__said, "\n"))
        helpers.command(env, "minimap")
        assertTrue(ns.MinimapButton.Button():IsShown())
    end)
end)

describe("the minimap checkbox", function()
    local function minimapBox(ns)
        ns.SettingsPanel.EnsureBuilt()
        for _, control in ipairs(ns.SettingsPanel.controls) do
            if control.setting.store == "minimap" and control.setting.key == "hide" then
                return control.widget, control
            end
        end
    end

    local function click(box, checked)
        box:SetChecked(checked)
        box.scripts.OnClick(box)
    end

    it("is labelled 'Show the minimap button' and is ticked while the button shows", function()
        local ns = withMinimap()
        local box, control = minimapBox(ns)
        assertTrue(box ~= nil, "the box is on the page")
        assertEqual("Show the minimap button", control.setting.name)
        assertTrue(box:GetChecked())
    end)

    it("starts unticked when the saved choice is hidden", function()
        local ns, env = helpers.loadAddon()
        env.Minimap = env.CreateFrame("Frame", nil, env.UIParent)
        env.Minimap:SetSize(140, 140)
        env.UrlCopyDB = { minimap = { hide = true } }
        helpers.login(ns, env)
        assertFalse(minimapBox(ns):GetChecked())
        assertFalse(ns.MinimapButton.Button():IsShown())
    end)

    it("hides the button at once when unticked, and remembers", function()
        local ns = withMinimap()
        click(minimapBox(ns), false)
        assertFalse(ns.MinimapButton.Button():IsShown())
        assertTrue(ns.db.minimap.hide)
    end)

    it("shows the button again when ticked", function()
        local ns = withMinimap()
        local box = minimapBox(ns)
        click(box, false)
        click(box, true)
        assertTrue(ns.MinimapButton.Button():IsShown())
        assertFalse(ns.db.minimap.hide)
    end)

    it("follows /url minimap", function()
        local ns, env = withMinimap()
        local box = minimapBox(ns)
        helpers.command(env, "minimap")
        assertFalse(box:GetChecked(), "unticked after hiding by command")
        helpers.command(env, "minimap")
        assertTrue(box:GetChecked(), "ticked after showing by command")
    end)

    it("still prints what the command did", function()
        local ns, env = withMinimap()
        minimapBox(ns)
        helpers.command(env, "minimap")
        assertMatch("/url minimap brings it back", table.concat(env.__said, "\n"))
    end)
end)
