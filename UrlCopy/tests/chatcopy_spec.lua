local helpers = require("helpers")

-- Give a chat frame a history, oldest first, the way the client hands it
-- out: GetMessageInfo(1) is the oldest line. A line given as an error is
-- one the client will not let an addon read.
local function history(frame, lines)
    frame.GetNumMessages = function() return #lines end
    frame.GetMessageInfo = function(_, index)
        local line = lines[index]
        if type(line) == "table" and line.error then
            error("attempt to read a secret value")
        end
        return line, 1, 1, 1
    end
end

-- Logged in with three chat windows: General, the combat log, and a third.
local function loggedIn()
    local ns, env = helpers.loadAddon()
    env.ChatFrame2 = env.CreateFrame("ScrollingMessageFrame", "ChatFrame2", env.UIParent)
    env.ChatFrame3 = env.CreateFrame("ScrollingMessageFrame", "ChatFrame3", env.UIParent)
    env.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2", "ChatFrame3" }
    env.COMBATLOG = env.ChatFrame2
    env.SELECTED_CHAT_FRAME = env.ChatFrame1
    history(env.ChatFrame1, { "first", "second" })
    history(env.ChatFrame2, { "combat" })
    history(env.ChatFrame3, { "third window" })
    helpers.login(ns, env)
    return ns, env
end

local function setting(ns, key)
    for _, definition in ipairs(ns.settings) do
        if definition.store == "chatCopy" and definition.key == key then
            return definition
        end
    end
end

describe("chat text as plain text", function()
    local ns = helpers.loadAddon()
    local plain = ns.ChatCopy.Plain

    it("drops colour codes", function()
        assertEqual("BossLoot Loaded.", plain("|cff66ccffBossLoot|r Loaded."))
        assertEqual("ok", plain("|cnGREEN_FONT_COLOR:ok|r"))
    end)

    it("turns a link into the name it shows", function()
        assertEqual("[Thunderfury] drops", plain("|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r drops"))
        assertEqual("[Icedog Elric]: Lfg", plain("|Hplayer:Icedog Elric:12:CHANNEL:1|h[Icedog Elric]|h: Lfg"))
    end)

    it("drops icons", function()
        assertEqual("pull  now", plain("pull |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t now"))
        assertEqual("a  b", plain("a |A:groupfinder-icon-role-large-tank:16:16|a b"))
    end)

    it("keeps an escaped pipe as a pipe", function()
        assertEqual("a | b", plain("a || b"))
        assertEqual("||cff", plain("||||cff"))
    end)

    it("leaves ordinary text alone", function()
        assertEqual("Hall of Thanes 13-20, map 3065: new to BossLoot", plain("Hall of Thanes 13-20, map 3065: new to BossLoot"))
    end)
end)

describe("reading a chat window", function()
    it("gives its lines oldest first, as plain text", function()
        local ns, env = loggedIn()
        history(env.ChatFrame1, { "|cffffff00old|r", "new" })
        local lines, skipped = ns.ChatCopy.Lines(env.ChatFrame1)
        assertEqual("old|new", table.concat(lines, "|"))
        assertEqual(0, skipped)
    end)

    it("leaves out a line it may not read, and counts it", function()
        local ns, env = loggedIn()
        history(env.ChatFrame1, { "one", { error = true }, "three" })
        local lines, skipped = ns.ChatCopy.Lines(env.ChatFrame1)
        assertEqual("one|three", table.concat(lines, "|"))
        assertEqual(1, skipped)
    end)

    it("gives nothing, and does not fail, for a frame without the calls", function()
        local ns, env = loggedIn()
        local lines, skipped = ns.ChatCopy.Lines(env.CreateFrame("Frame"))
        assertEqual(0, #lines)
        assertEqual(0, skipped)
    end)
end)

describe("the copy window", function()
    it("opens on /url chat with the chat tab being looked at, newest at the bottom, ready to copy", function()
        local ns, env = loggedIn()
        helpers.command(env, "chat")
        local frame = ns.ChatCopy.Frame()
        assertTrue(frame:IsShown())
        assertEqual("first\nsecond", frame.box:GetText())
        assertTrue(frame.box.focused)
        assertEqual(#"first\nsecond", frame.box.cursor)
        assertMatch("Ctrl%+C", frame.hint:GetText())
    end)

    it("opens on the chat tab /url chat is typed in, whichever that is", function()
        local ns, env = loggedIn()
        env.SELECTED_CHAT_FRAME = env.ChatFrame3
        helpers.command(env, "chat")
        assertEqual("third window", ns.ChatCopy.Frame().box:GetText())
    end)

    it("says how many lines it could not read", function()
        local ns, env = loggedIn()
        history(env.ChatFrame1, { "one", { error = true }, { error = true } })
        ns.ChatCopy.Open(env.ChatFrame1)
        assertMatch("2 lines could not be read", ns.ChatCopy.Frame().hint:GetText())
    end)

    it("says so when the window holds nothing", function()
        local ns, env = loggedIn()
        history(env.ChatFrame1, {})
        ns.ChatCopy.Open(env.ChatFrame1)
        assertMatch("nothing", ns.ChatCopy.Frame().hint:GetText())
    end)

    it("puts its text back when typed into", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Open(env.ChatFrame1)
        local box = ns.ChatCopy.Frame().box
        box:SetText("first\nsecondx")
        assertEqual("first\nsecond", box:GetText())
    end)

    it("closes on Escape", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Open(env.ChatFrame1)
        local frame = ns.ChatCopy.Frame()
        frame.box.scripts.OnEscapePressed(frame.box)
        assertFalse(frame:IsShown())
        assertFalse(frame.box.focused)
    end)

    it("closes with Escape from the game too", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Open(env.ChatFrame1)
        local listed = false
        for _, name in ipairs(env.UISpecialFrames) do
            if env[name] == ns.ChatCopy.Frame() then listed = true end
        end
        assertTrue(listed)
    end)

    it("shows what has been said since, when opened again", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Open(env.ChatFrame1)
        history(env.ChatFrame1, { "first", "second", "third" })
        ns.ChatCopy.Open(env.ChatFrame1)
        assertEqual("first\nsecond\nthird", ns.ChatCopy.Frame().box:GetText())
    end)

    it("scrolls to the newest line once the text is laid out", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Open(env.ChatFrame1)
        local scroll = ns.ChatCopy.Frame().scroll
        scroll.verticalScrollRange = 240
        env.__runTimers()
        assertEqual(240, scroll.verticalScroll)
    end)
end)

describe("the copy button", function()
    it("is put on each chat window but the combat log", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Update()
        assertTrue(ns.ChatCopy.Button(env.ChatFrame1) ~= nil)
        assertTrue(ns.ChatCopy.Button(env.ChatFrame3) ~= nil)
        assertNil(ns.ChatCopy.Button(env.ChatFrame2))
    end)

    it("sits in the top-right corner, clear of the chat's scroll bar", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Update()
        local point, relativeTo, relativePoint, x, y = ns.ChatCopy.Button(env.ChatFrame1):GetPoint(1)
        assertEqual("TOPRIGHT", point)
        assertEqual(env.ChatFrame1, relativeTo)
        assertEqual("TOPRIGHT", relativePoint)
        assertEqual(-24, x)
        assertEqual(0, y)
    end)

    it("shows only while the mouse is over its chat window", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Update()
        local button = ns.ChatCopy.Button(env.ChatFrame1)
        assertFalse(button:IsShown())
        env.ChatFrame1.mouseOver = true
        ns.ChatCopy.Update()
        assertTrue(button:IsShown())
        assertFalse(ns.ChatCopy.Button(env.ChatFrame3):IsShown(), "only the window under the mouse")
        env.ChatFrame1.mouseOver = false
        ns.ChatCopy.Update()
        assertFalse(button:IsShown())
    end)

    it("checks where the mouse is as the frames update", function()
        local ns, env = loggedIn()
        env.ChatFrame1.mouseOver = true
        for _, frame in ipairs(env.__frames) do
            if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end
        end
        assertTrue(ns.ChatCopy.Button(env.ChatFrame1):IsShown())
    end)

    it("opens its own chat window's text", function()
        local ns, env = loggedIn()
        ns.ChatCopy.Update()
        ns.ChatCopy.Button(env.ChatFrame3).scripts.OnClick(ns.ChatCopy.Button(env.ChatFrame3))
        assertEqual("third window", ns.ChatCopy.Frame().box:GetText())
    end)

    it("is gone, mouse or not, with the setting off, and /url chat still works", function()
        local ns, env = loggedIn()
        env.ChatFrame1.mouseOver = true
        ns.ChatCopy.Update()
        ns.SetSettingValue(setting(ns, "button"), false)
        assertFalse(ns.ChatCopy.Button(env.ChatFrame1):IsShown())
        ns.ChatCopy.Update()
        assertFalse(ns.ChatCopy.Button(env.ChatFrame1):IsShown())
        helpers.command(env, "chat")
        assertTrue(ns.ChatCopy.Frame():IsShown())
    end)

    it("is not made at all while the setting is off", function()
        local ns, env = helpers.loadAddon()
        env.UrlCopyDB = { chatCopy = { button = false } }
        env.ChatFrame1.mouseOver = true
        helpers.login(ns, env)
        ns.ChatCopy.Update()
        assertNil(ns.ChatCopy.Button(env.ChatFrame1))
    end)

    it("is a setting, on by default, in the settings panel", function()
        local ns = loggedIn()
        local definition = setting(ns, "button")
        assertEqual("checkbox", definition.type)
        assertEqual("Copy button on chat windows", definition.name)
        assertTrue(ns.db.chatCopy.button)
    end)
end)
