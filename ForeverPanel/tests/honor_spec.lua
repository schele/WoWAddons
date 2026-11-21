local helpers = require("helpers")

-- The icon comes first, so stripping it leaves a leading space.
local function plain(text)
    return (helpers.plain(text):gsub("^%s+", ""))
end

local function printed(env)
    return table.concat(env.__printed, "\n")
end

--- Give the character honor under the given currency id.
local function earn(env, id, quantity, extra)
    local currency = { name = "Honor", quantity = quantity }
    for key, value in pairs(extra or {}) do
        currency[key] = value
    end
    env.__currencies[id] = currency
end

--- Log in, after `setup` has had a chance to change the game.
local function loggedIn(setup)
    local ns, env = helpers.loadAddon()
    if setup then
        setup(env)
    end
    helpers.login(ns, env)
    helpers.firstFrame(env)
    return ns, env
end

local function module(ns)
    return ns.Bar:GetModule("honor")
end

describe("FormatHonor", function()
    local ns = helpers.loadAddon()

    it("shows the amount after the currency's own icon", function()
        assertEqual("1,234", plain(ns.FormatHonor(1234, 463450, 12)))
        assertMatch("|T463450:12:12:", ns.FormatHonor(1234, 463450, 12))
    end)

    it("treats a missing or negative amount as none", function()
        assertEqual("0", plain(ns.FormatHonor(nil, 463450, 12)))
        assertEqual("0", plain(ns.FormatHonor(-5, 463450, 12)))
    end)
end)

describe("finding honor", function()
    it("reads the classic honor currency", function()
        local ns = loggedIn(function(env) earn(env, 1901, 1234) end)

        local honor = ns.HonorInfo()
        assertEqual(1901, honor.currencyID)
        assertEqual(1234, honor.quantity)
    end)

    it("reads the current game's honor currency too", function()
        local ns = loggedIn(function(env) earn(env, 1792, 50) end)

        assertEqual(1792, ns.HonorInfo().currencyID)
    end)

    it("finds honor by name in the currency tab when its id is another", function()
        local ns = loggedIn(function(env)
            earn(env, 3001, 700)
            env.__currencyList = { "Player vs. Player", 3001 }
        end)

        assertEqual(3001, ns.HonorInfo().currencyID)
    end)

    it("keeps finding it after its header in the currency tab is collapsed", function()
        local ns, env = loggedIn(function(env)
            earn(env, 3001, 700)
            env.__currencyList = { "Player vs. Player", 3001 }
        end)
        ns.HonorInfo()

        env.__currencyList = { "Player vs. Player" }

        assertEqual(3001, ns.HonorInfo().currencyID)
    end)

    it("passes over an honor currency the character has never had", function()
        -- The game answers for a real id even when the character has none, so
        -- an unused id would otherwise read 0 for ever.
        local ns = loggedIn(function(env)
            earn(env, 1901, 0, { discovered = false })
            earn(env, 3001, 700)
            env.__currencyList = { "Player vs. Player", 3001 }
        end)

        assertEqual(3001, ns.HonorInfo().currencyID)
    end)

    it("finds none on a character without honor", function()
        local ns = loggedIn(function(env) earn(env, 1901, 0, { discovered = false }) end)

        assertEqual(nil, ns.HonorInfo())
    end)

    it("finds none on a client without the currency API", function()
        local ns = loggedIn(function(env) env.C_CurrencyInfo = nil end)

        assertEqual(nil, ns.HonorInfo())
    end)
end)

describe("the honor module", function()
    it("shows honor on the bar, after xp on the left", function()
        local ns = loggedIn(function(env) earn(env, 1901, 1234) end)

        assertEqual("1,234", plain(module(ns).text:GetText()))
        assertTrue(module(ns).shown, "shown")
        assertEqual("LEFT", module(ns).side)
        assertTrue(ns.Bar:GetModule("xp").order < module(ns).order, "right of the xp block")
    end)

    it("draws the currency's own icon at the bar's text size", function()
        local ns = loggedIn(function(env) earn(env, 1901, 1234, { iconFileID = 463450 }) end)

        local _, size = module(ns).text:GetFont()
        assertMatch("|T463450:" .. size .. ":" .. size .. ":", module(ns).text:GetText())
    end)

    it("stays off the bar for a character without honor", function()
        local ns = loggedIn()

        assertFalse(module(ns).shown)
    end)

    it("follows a change in honor", function()
        local ns, env = loggedIn(function(env) earn(env, 1901, 1234) end)

        env.__currencies[1901].quantity = 1500
        helpers.fire(env, "CURRENCY_DISPLAY_UPDATE")

        assertEqual("1,500", plain(module(ns).text:GetText()))
    end)

    it("appears once the character first earns honor", function()
        local ns, env = loggedIn()

        earn(env, 1901, 25)
        helpers.fire(env, "CURRENCY_DISPLAY_UPDATE")

        assertTrue(module(ns).shown)
        assertEqual("25", plain(module(ns).text:GetText()))
    end)

    it("opens the currency tab when clicked", function()
        local ns, env = loggedIn(function(env) earn(env, 1901, 1234) end)

        module(ns).frame:GetScript("OnClick")(module(ns).frame, "LeftButton")

        assertEqual("TokenFrame", env.__characterTab)
    end)

    it("shows the game's own honor tooltip on hover", function()
        local ns, env = loggedIn(function(env) earn(env, 1901, 1234) end)

        module(ns).frame:GetScript("OnEnter")(module(ns).frame)

        assertEqual(1901, env.GameTooltip.currencyID)
        assertEqual(module(ns).frame, env.GameTooltip:GetOwner())
        assertTrue(env.GameTooltip:IsShown(), "shown")

        module(ns).frame:GetScript("OnLeave")(module(ns).frame)
        assertFalse(env.GameTooltip:IsShown(), "and hidden again")
    end)

    it("gets a visibility switch like every other module", function()
        local ns = loggedIn()

        local found
        for _, setting in ipairs(ns.settings) do
            if setting.store == "modules" and setting.key == "honor" then
                found = setting
            end
        end

        assertTrue(found ~= nil, "on the settings panel")
        assertEqual("Show honor", found.name)
    end)
end)

describe("/fp honor", function()
    local function honor(setup)
        local _, env = loggedIn(setup)
        helpers.command(env, "honor")
        return printed(env)
    end

    it("says how much honor there is, the cap, and which currency it is", function()
        local text = honor(function(env) earn(env, 1901, 1234, { maxQuantity = 15000 }) end)
        assertMatch("Honor: 1,234 of 15,000 %(currency 1901%)%.", text)
    end)

    it("leaves out a cap the game does not set", function()
        assertMatch("Honor: 1,234 %(currency 1901%)%.", honor(function(env) earn(env, 1901, 1234) end))
    end)

    it("says so when the character has no honor", function()
        assertMatch("No honor on this character yet%.", honor())
    end)

    it("is listed in the help", function()
        local _, env = loggedIn()
        helpers.command(env, "help")
        assertMatch("/fp honor %- ", printed(env))
    end)
end)
