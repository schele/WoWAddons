local helpers = require("helpers")

local POLE = 6256

local function loggedIn()
    local ns, env = helpers.loadAddon()
    env.__mainHand = POLE
    helpers.login(ns, env)
    ns.SettingsPanel.EnsureBuilt()
    return ns, env
end

describe("the panel", function()
    it("registers itself with the game's options", function()
        local ns, env = loggedIn()

        assertTrue(env.__settingsCategory ~= nil)
        assertEqual("FishScale", env.__settingsCategory.name)
    end)

    it("builds once, however often it is asked", function()
        local ns, env = loggedIn()
        local count = #ns.SettingsPanel.controls

        ns.SettingsPanel.EnsureBuilt()

        assertEqual(count, #ns.SettingsPanel.controls)
    end)

    it("renders a control for every registered setting", function()
        local ns, env = loggedIn()

        assertEqual(#ns.settings, #ns.SettingsPanel.controls)
    end)

    it("hangs each control off the one above it, not off the top of the panel", function()
        -- The intro paragraph wraps to however many lines its text needs, and
        -- only the client knows how many. Counting rows from the top was
        -- right for two lines and put the first checkbox on top of the third,
        -- which is what it looked like in the game. Anchoring relatively
        -- cannot be wrong about a height it never has to know.
        local ns, env = loggedIn()
        local controls = ns.SettingsPanel.controls

        for index, control in ipairs(controls) do
            local point = control.widget.points[1]
            assertEqual("TOPLEFT", point[1],
                "control " .. index .. " should anchor by its top-left")
            assertEqual("BOTTOMLEFT", point[3],
                "control " .. index .. " should hang below whatever is above it")

            if index == 1 then
                -- The one that actually collided. Anchored to the panel it
                -- sits at a counted offset from the top, which is right until
                -- the paragraph wraps one line further than the count allows.
                assertEqual(ns.SettingsPanel.hint, point[2],
                    "the first control must hang off the paragraph itself")
            else
                assertEqual(controls[index - 1].widget, point[2],
                    "control " .. index .. " should hang off control " .. (index - 1))
            end
        end
    end)

    it("leaves a gap between a control and the words naming it", function()
        local ns, env = loggedIn()
        local label = helpers.control(ns, "enabled").widget.children[1]

        assertTrue(label.points[1][4] >= 8,
            "a label touching its checkbox is what 4 looked like")
    end)

    it("shows the logo, not the tile the AddOns list wants", function()
        local ns, env = loggedIn()

        assertEqual("Interface\\AddOns\\FishScale\\logo",
            ns.SettingsPanel.logo:GetTexture())
        assertEqual("ARTWORK", ns.SettingsPanel.logo.drawLayer)
    end)
end)

describe("the checkboxes", function()
    it("shows what is stored", function()
        local ns, env = loggedIn()
        ns.db.fishing.withoutPole = true

        ns.SettingsPanel.Refresh()

        assertTrue(helpers.control(ns, "withoutPole").widget:GetChecked())
    end)

    it("writes through to the database when clicked", function()
        local ns, env = loggedIn()
        local control = helpers.control(ns, "withoutPole")

        control.widget:SetChecked(true)
        control.widget:Click()

        assertTrue(ns.db.fishing.withoutPole)
    end)

    it("takes the mouse, or it shows nothing and does nothing", function()
        local ns, env = loggedIn()

        assertTrue(helpers.control(ns, "enabled").widget.mouseEnabled ~= false)
    end)
end)

describe("the reach slider", function()
    it("writes through to the database", function()
        local ns, env = loggedIn()

        helpers.control(ns, "range").widget:SetValue(60)

        assertEqual(60, ns.db.fishing.range)
        assertEqual("60", env.__cvars.SoftTargetInteractRange)
    end)

    it("says what the client granted when it is less than was asked", function()
        -- The client clamps this setting silently. A slider reading 60 beside
        -- a client that allowed 20 is a lie with nothing to catch it, and
        -- the reach is the one number that decides whether a long cast can
        -- be reeled in at all.
        local ns, env = loggedIn()
        env.SetCVar = function(name, value)
            if name == "SoftTargetInteractRange" then
                value = math.min(20, tonumber(value) or 20)
            end
            env.__cvars[name] = tostring(value)
        end

        helpers.control(ns, "range").widget:SetValue(60)

        local label = helpers.control(ns, "range").widget.children[1]
        assertMatch("granted 20", label:GetText())
    end)

    it("carries the real bounds, not the template's Low and High", function()
        local ns, env = loggedIn()
        local slider = helpers.control(ns, "range").widget

        assertEqual(5, slider.minValue)
        assertEqual(100, slider.maxValue)
    end)
end)

describe("the fishing key", function()
    it("shows the key currently bound", function()
        local ns, env = loggedIn()

        assertEqual("F", helpers.control(ns, "key").widget:GetText())
    end)

    it("takes a key by having one pressed at it", function()
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        button:Click()
        button:PressKey("G")

        assertEqual("G", ns.db.fishing.key)
        assertEqual("G", button:GetText())
    end)

    it("says it is listening while it waits", function()
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        button:Click()

        assertMatch("Press a key", button:GetText())
    end)

    it("builds the binding with whatever modifiers are held", function()
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        button:Click()
        env.__modifiers.shift = true
        env.__modifiers.ctrl = true
        button:PressKey("F")

        assertEqual("CTRL-SHIFT-F", ns.db.fishing.key)
    end)

    it("keeps listening through a modifier pressed on its own", function()
        -- Reaching for Shift must not end the capture, or the key it was
        -- meant to modify is never seen.
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        button:Click()
        button:PressKey("LSHIFT")

        assertEqual("F", ns.db.fishing.key, "nothing bound yet")
        assertMatch("Press a key", button:GetText(), "still listening")
    end)

    it("gives up on escape without changing the key", function()
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        button:Click()
        button:PressKey("ESCAPE")

        assertEqual("F", ns.db.fishing.key)
        assertEqual("F", button:GetText())
    end)

    it("gives the keyboard back the moment it has a key", function()
        -- A capture left running swallows every key press in the game, which
        -- looks exactly like the client having frozen.
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        button:Click()
        assertEqual(false, button.propagateKeyboard, "swallowing while it waits")

        button:PressKey("G")

        assertEqual(false, button.keyboardEnabled)
        assertEqual(true, button.propagateKeyboard, "and keys reach the game again")
    end)

    it("gives the keyboard back when the panel closes mid-capture", function()
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        -- Shown first, because the panel is created hidden and hiding an
        -- already-hidden frame fires nothing -- in the stub and in the
        -- client alike.
        ns.SettingsPanel.panel:Show()
        button:Click()
        ns.SettingsPanel.panel:Hide()

        assertEqual(false, button.keyboardEnabled)
        assertEqual(true, button.propagateKeyboard)
    end)

    it("rebinds the key that was just chosen", function()
        local ns, env = loggedIn()
        local button = helpers.control(ns, "key").widget

        button:Click()
        button:PressKey("G")

        assertEqual("FishScaleCastButton", env.__bindings.G.button,
            "the new key casts")
        assertNil(env.__bindings.F, "and the old one is the player's again")
    end)
end)
