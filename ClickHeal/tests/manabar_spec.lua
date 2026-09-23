local helpers = require("helpers")

-- MANA and RAGE as Enum.PowerType numbers them.
local MANA, RAGE = 0, 1

--- Logged in as a druid with 300 of 500 mana, in whichever form is given.
local function druid(powerType)
    local ns, env = helpers.loadAddon()
    env.__powerType = powerType
    env.__mana, env.__manaMax = 300, 500
    function env.UnitPowerType() return env.__powerType end
    function env.UnitPower(_, kind) return kind == MANA and env.__mana or 0 end
    function env.UnitPowerMax(_, kind) return kind == MANA and env.__manaMax or 100 end
    helpers.login(ns, env)
    return ns, env
end

local function settingFor(ns, store, key)
    for _, setting in ipairs(ns.settings) do
        if setting.store == store and setting.key == key then
            return setting
        end
    end
end

describe("the mana bar", function()
    it("shows mana in Bear Form, the setting defaulting on", function()
        local ns = druid(RAGE)

        local bar = ns.ManaBar.Frame()
        assertTrue(bar:IsShown())
        assertEqual(300, bar:GetValue())
        local _, maximum = bar:GetMinMaxValues()
        assertEqual(500, maximum)
        assertEqual("300 / 500", bar.text:GetText())
    end)

    it("hides in caster form, where Blizzard's own bar shows mana", function()
        local ns = druid(MANA)

        assertFalse(ns.ManaBar.Frame():IsShown())
    end)

    it("follows a shift into and out of a form", function()
        local ns, env = druid(MANA)

        env.__powerType = RAGE
        helpers.fire(env, "UNIT_DISPLAYPOWER", "player")
        assertTrue(ns.ManaBar.Frame():IsShown(), "into Bear Form")

        env.__powerType = MANA
        helpers.fire(env, "UNIT_DISPLAYPOWER", "player")
        assertFalse(ns.ManaBar.Frame():IsShown(), "back to caster form")
    end)

    it("keeps up as mana regenerates", function()
        local ns, env = druid(RAGE)

        env.__mana = 420
        helpers.fire(env, "UNIT_POWER_FREQUENT", "player", "MANA")

        assertEqual(420, ns.ManaBar.Frame():GetValue())
    end)

    it("ignores other people's power", function()
        local ns, env = druid(RAGE)

        env.__mana = 1
        helpers.fire(env, "UNIT_POWER_FREQUENT", "party1", "MANA")

        assertEqual(300, ns.ManaBar.Frame():GetValue())
    end)

    it("stays hidden for a class with no mana", function()
        local ns, env = druid(RAGE)

        env.__manaMax = 0
        helpers.fire(env, "UNIT_MAXPOWER", "player")

        assertFalse(ns.ManaBar.Frame():IsShown())
    end)

    it("hides when turned off", function()
        local ns = druid(RAGE)

        ns.SetSettingValue(settingFor(ns, "manaBar", "show"), false)

        assertFalse(ns.ManaBar.Frame():IsShown())
    end)

    it("sits under the rage bar, as wide and as tall as it", function()
        -- Nested the way the rebuilt player frame nests it. Under the
        -- portrait instead, the level badge covered all but the numbers.
        local ns, env = helpers.loadAddon()
        local rage = env.CreateFrame("StatusBar")
        rage:SetHeight(18)
        env.PlayerFrame.PlayerFrameContent = {
            PlayerFrameContentMain = { ManaBarArea = { ManaBar = rage } },
        }
        function env.UnitPowerType() return RAGE end
        function env.UnitPower() return 1 end
        function env.UnitPowerMax() return 1 end
        helpers.login(ns, env)

        local bar = ns.ManaBar.Frame()
        local point, relativeTo, relativePoint, leftX = bar:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertEqual(rage, relativeTo)
        assertEqual("BOTTOMLEFT", relativePoint)
        local right, rightTo, rightPoint, rightX = bar:GetPoint(2)
        assertEqual("TOPRIGHT", right)
        assertEqual(rage, rightTo)
        assertEqual("BOTTOMRIGHT", rightPoint)
        -- Inset so the border, which hangs outside the bar, stops at the rage
        -- bar's edges instead of overlapping the portrait's frame.
        assertTrue(leftX > 0, "pulled in on the left")
        assertEqual(-leftX, rightX, "and by the same on the right")
        assertEqual(18, bar:GetHeight())
    end)

    it("still appears, under the frame, when there is no rage bar to find", function()
        local ns = druid(RAGE)

        local bar = ns.ManaBar.Frame()
        assertTrue(bar:IsShown())
        assertTrue(bar:GetHeight() > 0)
    end)

    it("hides rather than erroring when the client keeps the power type secret", function()
        local ns, env = druid(RAGE)

        function env.UnitPowerType() error("secret number value") end
        helpers.fire(env, "UNIT_DISPLAYPOWER", "player")

        assertFalse(ns.ManaBar.Frame():IsShown())
    end)
end)

describe("the mana bar's look", function()
    local function withBackdrop(env)
        env.__backdrops = {}
        local create = env.CreateFrame
        env.CreateFrame = function(kind, name, parent, template)
            local frame = create(kind, name, parent, template)
            if template == "BackdropTemplate" then
                function frame:SetBackdrop(backdrop) self.backdrop = backdrop end
                function frame:SetBackdropBorderColor(r, g, b, a) self.borderColor = { r, g, b, a } end
            end
            return frame
        end
    end

    local function druidWith(setup)
        local ns, env = helpers.loadAddon()
        setup(env)
        function env.UnitPowerType() return RAGE end
        function env.UnitPower() return 1 end
        function env.UnitPowerMax() return 1 end
        helpers.login(ns, env)
        return ns, env
    end

    it("uses the player frame's own mana fill when the client has it", function()
        local ns = druidWith(function(env)
            env.C_Texture = {
                GetAtlasInfo = function(name)
                    return name == "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana" and {} or nil
                end,
            }
        end)

        assertEqual("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
            ns.ManaBar.Frame():GetStatusBarTexture())
    end)

    it("falls back to a plain blue fill when it does not", function()
        local ns = druidWith(function() end)

        local bar = ns.ManaBar.Frame()
        assertEqual("Interface\\TargetingFrame\\UI-StatusBar", bar:GetStatusBarTexture())
        assertEqual(1, bar.barColor[3])
    end)

    it("draws a border around the bar, with the numbers above it", function()
        local ns = druidWith(withBackdrop)

        local bar = ns.ManaBar.Frame()
        assertTrue(bar.border ~= nil, "has a border")
        assertEqual("Interface\\Tooltips\\UI-Tooltip-Border", bar.border.backdrop.edgeFile)
        assertEqual(bar.border, bar.text:GetParent(), "text drawn over the border")
    end)

    it("still builds without BackdropTemplate", function()
        local ns = druidWith(function(env)
            env.__missingTemplates.BackdropTemplate = true
        end)

        local bar = ns.ManaBar.Frame()
        assertNil(bar.border)
        assertTrue(bar:IsShown())
    end)
end)
