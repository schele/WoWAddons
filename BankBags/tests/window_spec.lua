local helpers = require("helpers")

local LINEN = { link = "|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r", count = 20, icon = 132889, quality = 1 }
local BOOTS = { link = "|cff1eff00|Hitem:9387::|h[Revelosh's Boots]|h|r", count = 1, icon = 132541, quality = 2 }
local EMPTY = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

-- Carl's bank saved two hours ago: Linen and Boots in the main bank's 24
-- slots, and a 4-slot Mooncloth Bag holding Linen.
local function carl(env)
    return {
        name = "Carl", realm = "Stormwind", class = "DRUID", saved = env.__now - 7200,
        containers = {
            { id = -1, name = "Bank", size = 24, slots = { [1] = LINEN, [3] = BOOTS } },
            { id = 5, name = "Mooncloth Bag", icon = 133652, size = 4, slots = { [2] = LINEN } },
        },
    }
end

local function opened()
    local ns, env = helpers.loggedIn()
    ns.db.characters["Stormwind-Carl"] = carl(env)
    ns.Window.Open()
    return ns, env, ns.Window.Frame()
end

local function shown(list)
    local n = 0
    for _, item in ipairs(list) do if item:IsShown() then n = n + 1 end end
    return n
end

describe("the bank window", function()
    it("draws a section for the bank and each bag, with its name", function()
        local ns, env, frame = opened()
        assertEqual(2, shown(frame.headers))
        assertEqual("Bank", frame.headers[1].text:GetText())
        assertEqual("Mooncloth Bag", frame.headers[2].text:GetText())
        assertEqual(133652, frame.headers[2].icon:GetTexture())
    end)

    it("draws every slot: items with their count and quality edge, empty slots empty", function()
        local ns, env, frame = opened()
        assertEqual(28, shown(frame.slots))
        assertEqual(132889, frame.slots[1].icon:GetTexture())
        assertEqual("20", tostring(frame.slots[1].count:GetText()))
        assertFalse(frame.slots[1].edge:IsShown(), "common items have no edge")
        assertTrue(frame.slots[3].edge:IsShown(), "uncommon and better do")
        assertEqual(EMPTY, frame.slots[2].icon:GetTexture())
        assertEqual("", frame.slots[3].count:GetText(), "no count for one")
    end)

    it("lays the slots out twelve to a row", function()
        local ns, env, frame = opened()
        local _, _, _, x1, y1 = frame.slots[1]:GetPoint(1)
        local _, _, _, x13, y13 = frame.slots[13]:GetPoint(1)
        assertEqual(x1, x13)
        assertEqual(y1 - 41, y13)
    end)

    it("dims what does not match the search", function()
        local ns, env, frame = opened()
        frame.search:SetText("boots")
        frame.search.scripts.OnTextChanged(frame.search)
        assertEqual(1, frame.slots[3].alpha)
        assertEqual(0.25, frame.slots[1].alpha)
        assertEqual(0.25, frame.slots[2].alpha, "empty slots too")
        frame.search:SetText("")
        frame.search.scripts.OnTextChanged(frame.search)
        assertEqual(1, frame.slots[1].alpha)
    end)

    it("lets go of the keyboard when Enter is pressed in the search", function()
        -- Otherwise the movement keys go on typing into the box.
        local ns, env, frame = opened()
        local cleared = false
        function frame.search:ClearFocus() cleared = true end
        frame.search.scripts.OnEnterPressed(frame.search)
        assertTrue(cleared)
    end)

    it("says when the bank was saved", function()
        local ns, env, frame = opened()
        assertEqual("Saved 2 hours ago", frame.footer:GetText())
    end)

    it("says how to save a bank never saved", function()
        local ns = helpers.loggedIn()
        ns.Window.Open()
        assertEqual("Visit a banker to save your bank", ns.Window.Frame().footer:GetText())
        assertEqual(0, shown(ns.Window.Frame().slots))
    end)

    it("shows an item's tooltip, and passes a modified click on", function()
        local ns, env, frame = opened()
        frame.slots[1].scripts.OnEnter(frame.slots[1])
        assertEqual(LINEN.link, env.GameTooltip.hyperlink)
        frame.slots[1].scripts.OnClick(frame.slots[1], "LeftButton")
        assertEqual(LINEN.link, env.__modifiedClicks[1])
        frame.slots[2].scripts.OnClick(frame.slots[2], "LeftButton")
        assertEqual(1, #env.__modifiedClicks, "nothing for an empty slot")
    end)

    it("scrolls with the mouse wheel, no further than the end", function()
        local ns, env = helpers.loggedIn()
        local big = carl(env)
        for id = 5, 10 do
            big.containers[id - 3] = { id = id, name = "Big Bag", size = 24, slots = {} }
        end
        ns.db.characters["Stormwind-Carl"] = big
        ns.Window.Open()
        local frame = ns.Window.Frame()
        frame.scroll.scripts.OnMouseWheel(frame.scroll, -1)
        assertTrue(frame.scroll:GetVerticalScroll() > 0)
        for _ = 1, 100 do frame.scroll.scripts.OnMouseWheel(frame.scroll, -1) end
        local most = frame.content:GetHeight() - frame.scroll:GetHeight()
        assertEqual(most, frame.scroll:GetVerticalScroll())
        for _ = 1, 100 do frame.scroll.scripts.OnMouseWheel(frame.scroll, 1) end
        assertEqual(0, frame.scroll:GetVerticalScroll())
    end)

    it("opens and closes with a bare /bb, and closes on Escape", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "")
        assertTrue(ns.Window.Frame():IsShown())
        helpers.command(env, "")
        assertFalse(ns.Window.Frame():IsShown())
        local escapes = false
        for _, name in ipairs(env.UISpecialFrames) do
            if name == "BankBagsFrame" then escapes = true end
        end
        assertTrue(escapes)
    end)
end)

-- Text without its colour codes.
local function plain(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function entries(dropdown)
    local names = {}
    for _, radio in ipairs(dropdown.radios) do
        names[#names + 1] = plain(radio.text)
    end
    return table.concat(names, ", ")
end

describe("choosing whose bank to show", function()
    -- Carl's bank, and Alt's, a mage on the same realm.
    local function twoSaved(setup)
        local ns, env = helpers.loggedIn(setup)
        ns.db.characters["Stormwind-Carl"] = carl(env)
        ns.db.characters["Stormwind-Alt"] = { name = "Alt", realm = "Stormwind", class = "MAGE", saved = env.__now, containers = {} }
        ns.Window.Open()
        return ns, env, ns.Window.Frame()
    end

    it("is a dropdown of every saved character, the one played first", function()
        local _, _, frame = twoSaved()
        assertEqual("WowStyle1DropdownTemplate", frame.dropdown.template)
        assertEqual("Carl, Alt", entries(frame.dropdown))
        assertEqual("Carl", plain(frame.dropdown.selectionText))
    end)

    -- The dropdown is 25 tall, and the game draws its box a few past that.
    it("leaves room under the dropdown before the bank starts", function()
        local _, _, frame = twoSaved()
        local dropdownTop = -frame.dropdown.points[1][5]
        local bankTop = -frame.scroll.points[1][5]
        assertTrue(bankTop - (dropdownTop + 25) >= 10, "gap under the dropdown: " .. (bankTop - dropdownTop - 25))
    end)

    -- Under the game's title bar, 24 tall, with as much room above the
    -- dropdown's box as under it.
    it("leaves room above the dropdown too", function()
        local _, _, frame = twoSaved()
        local dropdownTop = -frame.dropdown.points[1][5]
        assertTrue(dropdownTop - 24 >= 16, "gap above the dropdown: " .. (dropdownTop - 24))
    end)

    it("shows the bank of the character picked", function()
        local ns, _, frame = twoSaved()
        frame.dropdown:Pick(2)
        assertEqual("Stormwind-Alt", ns.Window.Shown())
        assertEqual("Alt", plain(frame.dropdown.selectionText))
        assertEqual(0, shown(frame.headers), "Alt's bank is empty")
    end)

    it("names each character in their class colour, without their realm", function()
        local _, _, frame = twoSaved(function(e)
            e.RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
        end)
        assertEqual("|cffff7c0aCarl|r", frame.dropdown.radios[1].text)
        assertEqual("|cff3fc6eaAlt|r", frame.dropdown.radios[2].text)
    end)

    it("tells apart two characters of one name on different realms", function()
        local ns, env, frame = twoSaved()
        ns.db.characters["Ironforge-Carl"] = { name = "Carl", realm = "Ironforge", class = "MAGE", saved = env.__now, containers = {} }
        ns.Window.Refresh()
        assertEqual("Carl (Stormwind), Carl (Ironforge), Alt", entries(frame.dropdown))
    end)

    it("follows a bank saved or forgotten while it is open", function()
        local ns, env, frame = twoSaved()
        ns.db.characters["Stormwind-Morwen"] = { name = "Morwen", realm = "Stormwind", saved = env.__now, containers = {} }
        ns.Window.Refresh()
        assertEqual("Carl, Alt, Morwen", entries(frame.dropdown))
        helpers.command(env, "forget Alt")
        assertEqual("Carl, Morwen", entries(frame.dropdown))
    end)

    it("names the character played before their bank is saved", function()
        local ns = helpers.loggedIn()
        ns.Window.Open()
        local frame = ns.Window.Frame()
        assertEqual(0, #frame.dropdown.radios)
        assertEqual("Carl", plain(frame.dropdown.selectionText))
    end)

    it("steps through the characters on a client without the game's dropdown", function()
        local ns, _, frame = twoSaved(function(e)
            e.__missingTemplates["WowStyle1DropdownTemplate"] = true
        end)
        assertEqual(nil, frame.dropdown)
        assertEqual("Carl", plain(frame.picker.text:GetText()), "no realm")
        frame.picker.scripts.OnClick(frame.picker, "LeftButton")
        assertEqual("Stormwind-Alt", ns.Window.Shown())
        assertEqual("Alt", plain(frame.picker.text:GetText()))
        frame.picker.scripts.OnClick(frame.picker, "RightButton")
        assertEqual("Carl", plain(frame.picker.text:GetText()), "a right-click goes back")
    end)
end)

describe("the window's words", function()
    local ns = helpers.loadAddon()

    it("says how long ago, in minutes, hours or days", function()
        assertEqual("Saved just now", ns.Window.SavedText(30))
        assertEqual("Saved 1 minute ago", ns.Window.SavedText(90))
        assertEqual("Saved 5 minutes ago", ns.Window.SavedText(300))
        assertEqual("Saved 2 hours ago", ns.Window.SavedText(7200))
        assertEqual("Saved 1 day ago", ns.Window.SavedText(86400))
        assertEqual("Saved 3 days ago", ns.Window.SavedText(3 * 86400))
    end)

    it("matches an item by the name in its link, ignoring case", function()
        assertTrue(ns.Window.Matches(LINEN.link, "LINEN"))
        assertTrue(ns.Window.Matches(LINEN.link, ""))
        assertFalse(ns.Window.Matches(LINEN.link, "boots"))
        assertTrue(ns.Window.Matches(BOOTS.link, "h's b"), "plain text, not a pattern")
    end)
end)

describe("the window's heading", function()
    it("shows BankBags' own icon before its name", function()
        local ns, env, frame = opened()
        assertEqual("Interface\\AddOns\\BankBags\\minimap", frame.logo:GetTexture())
        assertEqual("BankBags", frame.title:GetText())
        local point, relativeTo, relativePoint = frame.logo:GetPoint(1)
        assertEqual(frame.title, relativeTo, "the icon sits against the name")
        assertEqual("RIGHT", point)
        assertEqual("LEFT", relativePoint)
    end)
end)

describe("the window's frame", function()
    it("is the options window's own, with the name in its title bar", function()
        local ns, env, frame = opened()
        assertEqual("SettingsFrameTemplate", frame.template)
        assertEqual(frame.NineSlice.Text, frame.title)
        assertEqual(frame.ClosePanelButton, frame.close)
    end)

    it("is solid inside the game's border", function()
        local ns, env, frame = opened()
        assertEqual(frame.Bg, frame.background:GetParent(), "drawn with the game's background, under all else")
        assertEqual(1, frame.background.colorTexture[4])
    end)

    it("closes with its X", function()
        local ns, env, frame = opened()
        frame.close.scripts.OnClick(frame.close, "LeftButton")
        assertFalse(frame:IsShown())
    end)

    it("falls back to the dialog border on a client without that frame", function()
        local ns, env = helpers.loggedIn(function(e) e.__missingTemplates.SettingsFrameTemplate = true end)
        ns.Window.Open()
        local frame = ns.Window.Frame()
        assertTrue(frame:IsShown())
        assertTrue(frame.backdrop ~= nil, "the dialog border")
        assertEqual(1, frame.background.colorTexture[4])
        assertEqual("BankBags", frame.title:GetText())
        frame.close.scripts.OnClick(frame.close, "LeftButton")
        assertFalse(frame:IsShown())
    end)
end)

describe("one window at a time", function()
    it("closes the options window as it opens, and keeps the game menu away", function()
        local ns, env = helpers.loggedIn()
        env.SettingsPanel:Show()
        ns.Window.Open()
        assertTrue(ns.Window.Frame():IsShown())
        assertFalse(env.SettingsPanel:IsShown())
        env.GameMenuFrame:Show()
        assertFalse(env.GameMenuFrame:IsShown(), "the menu the options came from stays shut")
    end)

    it("closes as the options window opens", function()
        local ns, env, frame = opened()
        env.SettingsPanel:Show()
        assertFalse(frame:IsShown())
    end)

    it("closes BossLoot's window as it opens", function()
        local ns, env = helpers.loggedIn()
        local bossLoot = env.CreateFrame("Frame", "BossLootFrame", env.UIParent)
        ns.Window.Open()
        assertFalse(bossLoot:IsShown())
    end)
end)

describe("the window's sound", function()
    it("clicks as it opens, as the options window does", function()
        local ns, env = opened()
        assertEqual(1, #env.__sounds)
        assertEqual(env.SOUNDKIT.IG_CHARACTER_INFO_TAB, env.__sounds[1])
    end)

    it("is silent as it closes, and when opened while open", function()
        local ns, env = opened()
        ns.Window.Open()
        ns.Window.Toggle()
        assertEqual(1, #env.__sounds)
    end)

    it("opens silently on a client without the sound", function()
        local ns, env = helpers.loggedIn(function(e) e.PlaySound = nil end)
        ns.Window.Open()
        assertTrue(ns.Window.Frame():IsShown())
    end)
end)

-- The game's search box, as far as a test needs it: its word and glass, and
-- an OnTextChanged of its own that shows and hides the word.
local function withGameSearchBox(env)
    local create = env.CreateFrame
    function env.CreateFrame(kind, name, parent, template)
        local made = create(kind, name, parent, template)
        if template == "SearchBoxTemplate" then
            made.Instructions = made:CreateFontString()
            made.Instructions:SetText("Search")
            made.searchIcon = made:CreateTexture()
            made:SetScript("OnTextChanged", function(self)
                self.Instructions:SetShown(self:GetText() == "")
            end)
        end
        return made
    end
end

local function withoutGameSearchBox(env)
    env.__missingTemplates.SearchBoxTemplate = true
end

describe("the search box", function()
    local function openedWith(setup)
        local ns, env = helpers.loggedIn(setup)
        ns.db.characters["Stormwind-Carl"] = carl(env)
        ns.Window.Open()
        return ns, env, ns.Window.Frame()
    end

    it("is the game's own search box, whose word its own script still hides", function()
        local ns, env, frame = openedWith(withGameSearchBox)
        assertEqual(frame.search.Instructions, frame.search.hint)
        assertTrue(frame.search.hint:IsShown())
        frame.search:SetText("boots")
        assertFalse(frame.search.hint:IsShown(), "the game's own script still runs")
        assertEqual(0.25, frame.slots[1].alpha, "and so does the search")
    end)

    it("draws the glass and the word itself on a client without that box", function()
        local ns, env, frame = openedWith(withoutGameSearchBox)
        assertEqual("Interface\\Common\\UI-Searchbox-Icon", frame.search.icon:GetTexture())
        assertEqual("Search", frame.search.hint:GetText())
        assertTrue(frame.search.hint:IsShown())
        frame.search:SetText("boots")
        assertFalse(frame.search.hint:IsShown())
        assertEqual(0.25, frame.slots[1].alpha)
        frame.search:SetText("")
        assertTrue(frame.search.hint:IsShown())
    end)
end)
