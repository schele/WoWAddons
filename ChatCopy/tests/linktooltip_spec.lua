local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)
    return ns, env
end

local function tooltip(env)
    return env.ItemRefTooltip
end

describe("a second click on a linked item", function()
    it("closes the tooltip showing it", function()
        local _, env = loggedIn()

        helpers.click(env, "item:2589")
        assertTrue(tooltip(env):IsShown(), "the first click shows it")
        helpers.click(env, "item:2589")
        assertFalse(tooltip(env):IsShown(), "the second closes it")
    end)

    it("opens it again on a third", function()
        local _, env = loggedIn()

        helpers.click(env, "item:2589")
        helpers.click(env, "item:2589")
        helpers.click(env, "item:2589")
        assertTrue(tooltip(env):IsShown())
        assertEqual("item:2589", tooltip(env).hyperlink)
    end)

    it("works for spell and quest links too", function()
        local _, env = loggedIn()

        helpers.click(env, "spell:133")
        helpers.click(env, "spell:133")
        assertFalse(tooltip(env):IsShown(), "spell")

        helpers.click(env, "quest:5:12")
        helpers.click(env, "quest:5:12")
        assertFalse(tooltip(env):IsShown(), "quest")
    end)
end)

describe("a click on a different link", function()
    it("shows that one rather than closing", function()
        local _, env = loggedIn()

        helpers.click(env, "item:2589")
        helpers.click(env, "item:4306")
        assertTrue(tooltip(env):IsShown())
        assertEqual("item:4306", tooltip(env).hyperlink)
    end)

    it("leaves the next click on the first link showing it, not closing it", function()
        local _, env = loggedIn()

        helpers.click(env, "item:2589")
        helpers.click(env, "item:4306")
        helpers.click(env, "item:2589")
        assertTrue(tooltip(env):IsShown())
        assertEqual("item:2589", tooltip(env).hyperlink)
    end)
end)

describe("a tooltip closed some other way", function()
    it("opens on the next click after its X closed it", function()
        local _, env = loggedIn()

        helpers.click(env, "item:2589")
        tooltip(env):Hide()
        helpers.click(env, "item:2589")
        assertTrue(tooltip(env):IsShown())
    end)

    it("opens on the next click after a link it could not show closed it", function()
        local _, env = loggedIn()

        helpers.click(env, "item:2589")
        helpers.click(env, "chatcopy:example.com")
        assertFalse(tooltip(env):IsShown(), "the client hid it for the URL link")
        helpers.click(env, "item:2589")
        assertTrue(tooltip(env):IsShown())
    end)
end)

describe("a client that closes the tooltip itself", function()
    it("is left to do it, without a second close or a missed open", function()
        local _, env = loggedIn()
        env.__itemRefClosesItself = true

        helpers.click(env, "item:2589")
        helpers.click(env, "item:2589")
        assertFalse(tooltip(env):IsShown(), "the client closed it")
        helpers.click(env, "item:2589")
        assertTrue(tooltip(env):IsShown(), "and the next click opens it")
        helpers.click(env, "item:2589")
        assertFalse(tooltip(env):IsShown())
    end)
end)

describe("the setting", function()
    it("is on by default", function()
        local ns = loggedIn()
        assertTrue(ns.db.linkTooltip.toggle)
    end)

    it("off, leaves the client's own behaviour alone", function()
        local ns, env = loggedIn()
        ns.db.linkTooltip.toggle = false

        helpers.click(env, "item:2589")
        helpers.click(env, "item:2589")
        assertTrue(tooltip(env):IsShown(), "the client draws it again")
    end)

    it("turned on while the tooltip is open, closes it on the next click", function()
        local ns, env = loggedIn()
        ns.db.linkTooltip.toggle = false
        helpers.click(env, "item:2589")

        ns.db.linkTooltip.toggle = true
        helpers.click(env, "item:2589")
        assertFalse(tooltip(env):IsShown())
    end)
end)

describe("a client without the linked-item tooltip", function()
    it("loads and logs in without it", function()
        local ns, env = helpers.loadAddon()
        env.ItemRefTooltip = nil
        helpers.login(ns, env)
        assertTrue(ns.db ~= nil)
    end)
end)
