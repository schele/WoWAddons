local helpers = require("helpers")

local function opened(count, prepare)
    local ns, env = helpers.loadAddon(prepare)
    for index = 1, count do
        helpers.sale(env, "Stone " .. index, 1, 100 * index)
    end
    helpers.openMailbox(env)
    return ns, env, ns.Buttons.Parts()
end

describe("the boxes", function()
    it("sit on each row, for that row's mail", function()
        local ns, _, parts = opened(3)
        local mails = ns.Inbox.Mails()

        assertEqual(mails[1].key, parts.boxes[1].key)
        assertEqual(mails[3].key, parts.boxes[3].key)
        assertTrue(parts.boxes[3]:IsShown())
        assertFalse(parts.boxes[4]:IsShown())
    end)

    it("follow a page change", function()
        local ns, env, parts = opened(9)

        env.InboxFrame.pageNum = 2
        env.InboxFrame_Update()

        assertEqual(ns.Inbox.Mails()[8].key, parts.boxes[1].key)
        assertTrue(parts.boxes[2]:IsShown())
        assertFalse(parts.boxes[3]:IsShown())
    end)

    it("tick their mail, and Open counts it", function()
        local ns, _, parts = opened(3)

        parts.boxes[2]:Click()

        assertTrue(ns.Ticks.Is(ns.Inbox.Mails()[2].key))
        assertEqual("Open (1)", parts.open:GetText())
        assertTrue(parts.boxes[2]:GetChecked())
    end)
end)

describe("Open", function()
    it("is greyed while nothing is ticked", function()
        local _, _, parts = opened(3)
        assertFalse(parts.open:IsEnabled())

        parts.boxes[1]:Click()
        assertTrue(parts.open:IsEnabled())
    end)

    it("opens the ticked mails", function()
        local _, env, parts = opened(3)
        parts.boxes[2]:Click()

        parts.open:Click()
        env.__runAllTimers()

        assertEqual(200, env.__money)
    end)

    it("is greyed while it is opening", function()
        local _, env, parts = opened(3)
        env.__slowServer = true
        parts.boxes[1]:Click()
        parts.boxes[2]:Click()

        parts.open:Click()

        assertFalse(parts.open:IsEnabled())
    end)
end)

describe("Select all", function()
    it("ticks every mail on every page, and unticks them", function()
        local ns, _, parts = opened(9)

        parts.selectAll:Click()
        assertEqual(9, ns.Ticks.Count())
        assertEqual("Open (9)", parts.open:GetText())
        assertTrue(parts.selectAll:GetChecked())

        parts.selectAll:Click()
        assertEqual(0, ns.Ticks.Count())
    end)

    it("shows ticked only while every mail is", function()
        local _, _, parts = opened(3)
        parts.selectAll:Click()

        parts.boxes[2]:Click()

        assertFalse(parts.selectAll:GetChecked())
    end)
end)

describe("Open All", function()
    it("is the game's own, moved over to make room", function()
        local _, env, parts = opened(3)

        local _, _, _, x = env.OpenAllMail:GetPoint(1)
        local _, _, _, openX = parts.open:GetPoint(1)
        assertEqual(50, x)
        assertEqual(-50, openX)
        assertTrue(env.OpenAllMail:IsShown())
        assertNil(parts.openAll)
    end)

    it("is MailHandler's own where the game has none, and opens every mail", function()
        local _, env, parts = opened(3, function(e) e.OpenAllMail = nil end)

        assertTrue(parts.openAll ~= nil)
        parts.openAll:Click()
        env.__runAllTimers()

        assertEqual(600, env.__money)
    end)
end)

describe("closing the mailbox", function()
    it("forgets the ticks", function()
        local ns, env, parts = opened(3)
        parts.boxes[1]:Click()

        helpers.closeMailbox(env)

        assertEqual(0, ns.Ticks.Count())
        assertEqual("Open (0)", parts.open:GetText())
    end)
end)

describe("the boxes on Forever's inbox", function()
    it("follow a page change, which Forever draws with InboxFrame:Update", function()
        local ns, env = helpers.loadAddon(helpers.forever)
        for index = 1, 9 do
            helpers.sale(env, "Stone " .. index, 1, 100 * index)
        end
        helpers.openMailbox(env)
        local parts = ns.Buttons.Parts()

        env.InboxFrame.pageNum = 2
        env.InboxFrame:Update()

        assertEqual(ns.Inbox.Mails()[8].key, parts.boxes[1].key)
        assertFalse(parts.boxes[3]:IsShown())
    end)
end)
