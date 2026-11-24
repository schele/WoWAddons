local helpers = require("helpers")

local POLE, STAFF = 6256, 1161

--- Logged in holding whatever is given, a pole by default. `setup` runs
-- before login, on the env.
local function loggedIn(mainHand, setup)
    local ns, env = helpers.loadAddon()
    env.__mainHand = mainHand or POLE
    if setup then setup(env) end
    helpers.login(ns, env)
    return ns, env, ns.SkillBar.Frame()
end

local function catch(env)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    env.__fishingLoot = true
    helpers.fire(env, "LOOT_OPENED")
    helpers.fire(env, "LOOT_CLOSED")
    env.__fishingLoot = false
end

local function tooltipText(env)
    return table.concat({ env.GameTooltip.text or "", table.concat(env.GameTooltip.lines or {}, "\n") }, "\n")
end

describe("the skill bar", function()
    it("shows the skill, and fills toward the next point without counting it out in words", function()
        local ns, env, bar = loggedIn()
        catch(env)
        catch(env)
        assertTrue(bar:IsShown())
        assertEqual("Fishing 231/300", bar.label.text)
        assertEqual("", bar.count.text, "the fill says how close; the tooltip has the count")
    end)

    it("fills by the catches over what a point takes, and no further", function()
        local ns, env, bar = loggedIn()
        for _ = 1, 3 do catch(env) end
        local expected = ns.Skill.Expected(231)
        assertEqual(0, bar.minValue)
        assertEqual(1, bar.maxValue)
        assertEqual(3 / expected, bar.value)
        for _ = 1, 10 do catch(env) end
        assertEqual(1, bar.value)
    end)

    it("empties at a point", function()
        local ns, env, bar = loggedIn()
        catch(env)
        env.__fishing.rank = 232
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertEqual("Fishing 232/300", bar.label.text)
        assertEqual(0, bar.value)
    end)

    it("says when the skill is at its cap, and follows a trainer raising it", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 150, maxRank = 150 } end)
        assertEqual("Fishing 150/150", bar.label.text)
        assertEqual("capped", bar.count.text)
        env.__fishing.maxRank = 225
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertEqual("Fishing 150/225", bar.label.text)
        assertEqual("", bar.count.text)
    end)

    it("shows only while a pole is equipped", function()
        local ns, env, bar = loggedIn(STAFF)
        assertFalse(bar:IsShown())
        env.__mainHand = POLE
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", 16)
        assertTrue(bar:IsShown())
        env.__mainHand = STAFF
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", 16)
        assertFalse(bar:IsShown())
    end)

    it("stays hidden without a pole, even where an old save asked to fish without one", function()
        local ns, env, bar = loggedIn(STAFF, function(e)
            e.FishingForeverDB = { fishing = { withoutPole = true } }
        end)
        assertFalse(bar:IsShown())
    end)

    it("stays hidden for a character without Fishing", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = nil end)
        assertFalse(bar:IsShown())
    end)
end)

describe("the skill bar's tooltip", function()
    local function hover(bar)
        bar.scripts.OnEnter(bar)
    end

    it("is short: the skill, and a click for the stats, where the rest is", function()
        local ns, env, bar = loggedIn()
        catch(env)
        hover(bar)
        local text = tooltipText(env)
        assertMatch("Fishing 231/300", text)
        assertMatch("Click to open or close your fishing stats", text)
        assertFalse(text:find("since your last point", 1, true) ~= nil)
        assertFalse(text:find("1 in", 1, true) ~= nil)
    end)

    it("says on the bar when the game refused a cast here for too little skill, until another zone", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 106, maxRank = 150 } end)
        helpers.fire(env, "UNIT_SPELLCAST_SENT", "player", "", "guid", 7620)
        helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
        assertEqual("too low here", bar.count.text)

        env.__map = { id = 1436, name = "Westfall" }
        helpers.fire(env, "ZONE_CHANGED_NEW_AREA")
        assertEqual("", bar.count.text, "somewhere else the warning is gone")
    end)

    it("says on the bar when every fish of five casts here got away", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 150, maxRank = 225 } end)
        for _ = 1, 5 do
            helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
            helpers.fire(env, "UI_ERROR_MESSAGE", 400, "Your fish got away!")
        end
        assertEqual("too low here", bar.count.text)
    end)

    it("says how to move it while it can be moved", function()
        local ns, env, bar = loggedIn()
        hover(bar)
        assertMatch("Drag", tooltipText(env))
        ns.SkillBar.SetLocked(true)
        hover(bar)
        assertFalse(tooltipText(env):find("Drag", 1, true) ~= nil, "locked: nothing to drag")
    end)
end)

describe("moving the skill bar", function()
    local function drag(bar, point, relativePoint, x, y)
        bar.scripts.OnDragStart(bar)
        if bar.moving then
            bar:ClearAllPoints()
            bar:SetPoint(point, UIParent, relativePoint, x, y)
        end
        bar.scripts.OnDragStop(bar)
    end

    it("is dragged with the left button, and remembers where it was put", function()
        local ns, env, bar = loggedIn()
        assertEqual("LeftButton", bar.drag[1])
        drag(bar, "TOPLEFT", "TOPLEFT", 300, -400)
        assertEqual("TOPLEFT", ns.db.skillBar.point)
        assertEqual(300, ns.db.skillBar.x)
        assertEqual(-400, ns.db.skillBar.y)

        local saved = env.FishingForeverDB
        local _, _, again = loggedIn(POLE, function(e) e.FishingForeverDB = saved end)
        local point, _, relativePoint, x, y = again:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertEqual("TOPLEFT", relativePoint)
        assertEqual(300, x)
        assertEqual(-400, y)
    end)

    it("stays put while locked", function()
        local ns, env, bar = loggedIn()
        ns.SkillBar.SetLocked(true)
        bar.scripts.OnDragStart(bar)
        assertFalse(bar.moving == true)
    end)

    it("goes back to where it started on a reset", function()
        local ns, env, bar = loggedIn()
        drag(bar, "TOPLEFT", "TOPLEFT", 300, -400)
        ns.SkillBar.ResetPosition()
        local point, _, relativePoint, x, y = bar:GetPoint(1)
        assertEqual("CENTER", point)
        assertEqual("CENTER", relativePoint)
        assertEqual(0, x)
        assertEqual(-200, y)
    end)

    it("keeps to the screen", function()
        local _, _, bar = loggedIn()
        assertTrue(bar.clamped)
    end)
end)

describe("the skill bar's commands", function()
    it("hides and shows it with /ff bar, and remembers", function()
        local ns, env, bar = loggedIn()
        helpers.command(env, "bar")
        assertFalse(bar:IsShown())
        assertFalse(ns.db.skillBar.shown)
        assertMatch("hidden", helpers.printed(env))
        helpers.command(env, "bar")
        assertTrue(bar:IsShown())
    end)

    it("locks and unlocks it with /ff bar lock", function()
        local ns, env = loggedIn()
        helpers.command(env, "bar lock")
        assertTrue(ns.db.skillBar.locked)
        helpers.command(env, "bar lock")
        assertFalse(ns.db.skillBar.locked)
    end)

    it("puts it back with /ff bar reset", function()
        local ns, env, bar = loggedIn()
        ns.db.skillBar.x = 500
        helpers.command(env, "bar reset")
        local _, _, _, x = bar:GetPoint(1)
        assertEqual(0, x)
    end)
end)

describe("the skill bar on the settings page", function()
    local function opened()
        local ns, env, bar = loggedIn()
        ns.SettingsPanel.panel:Show()
        return ns, env, ns.SettingsPanel, bar
    end

    local function click(checkbox)
        checkbox:SetChecked(not checkbox:GetChecked())
        checkbox.scripts.OnClick(checkbox)
    end

    local function label(widget)
        return widget.fontStrings and widget.fontStrings[1] and widget.fontStrings[1].text
    end

    it("has a box to show it, ticked while it is on", function()
        local ns, env, panel, bar = opened()
        assertEqual("Show the skill bar while a pole is equipped", label(panel.skillBar))
        assertTrue(panel.skillBar:GetChecked())
        click(panel.skillBar)
        assertFalse(bar:IsShown())
        assertFalse(ns.db.skillBar.shown)
    end)

    it("has a box to lock it, under the first", function()
        local ns, env, panel = opened()
        assertEqual("Lock it in place", label(panel.skillBarLocked))
        assertFalse(panel.skillBarLocked:GetChecked())
        click(panel.skillBarLocked)
        assertTrue(ns.db.skillBar.locked)
        local _, _, _, showX = panel.skillBar:GetPoint(1)
        local _, _, _, lockX = panel.skillBarLocked:GetPoint(1)
        assertTrue(lockX > showX, "indented under the box it belongs to")
    end)

    it("has a button to put it back", function()
        local ns, env, panel, bar = opened()
        ns.db.skillBar.x = 500
        assertEqual("Reset its position", panel.skillBarReset.text)
        panel.skillBarReset.scripts.OnClick(panel.skillBarReset)
        local _, _, _, x = bar:GetPoint(1)
        assertEqual(0, x)
    end)

    it("follows a change made by command while the page is open", function()
        local ns, env, panel = opened()
        helpers.command(env, "bar")
        helpers.command(env, "bar lock")
        assertFalse(panel.skillBar:GetChecked())
        assertTrue(panel.skillBarLocked:GetChecked())
    end)
end)
