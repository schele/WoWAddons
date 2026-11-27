local helpers = require("helpers")

local POLE, STAFF = 6256, 1161

local BLUE, GREY = { 0.4, 0.8, 1 }, { 0.5, 0.5, 0.5 }

--- Whether a colour the bar was given is `want`; false for none at all.
local function colourIs(got, want)
    return got ~= nil and got[1] == want[1] and got[2] == want[2] and got[3] == want[3]
end

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

--- The game refusing a cast here for too little skill.
local function refused(env)
    helpers.fire(env, "UNIT_SPELLCAST_SENT", "player", "", "guid", 7620)
    helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
end

local function tooltipText(env)
    return table.concat({ env.GameTooltip.text or "", table.concat(env.GameTooltip.lines or {}, "\n") }, "\n")
end

describe("the skill bar", function()
    it("shows the next point on the left and the skill on the right", function()
        local ns, env, bar = loggedIn()
        for _ = 1, 3 do catch(env) end
        assertTrue(bar:IsShown())
        assertEqual("Next point", bar.pointLabel.text)
        assertEqual("Fishing 231/300", bar.skillLabel.text)
        assertEqual(3 / ns.Skill.Expected(231), bar.pointFill.value)
        assertNear(231 / 300, bar.skillFill.value, 1e-9)
        assertTrue(colourIs(bar.pointFill.barColor, BLUE))
        assertFalse(colourIs(bar.skillFill.barColor, BLUE), "the halves are told apart by colour")
    end)

    it("fills the left half by the catches over what a point takes, and no further", function()
        local ns, env, bar = loggedIn()
        for _ = 1, 3 do catch(env) end
        local expected = ns.Skill.Expected(231)
        assertEqual(0, bar.pointFill.minValue)
        assertEqual(1, bar.pointFill.maxValue)
        assertEqual(3 / expected, bar.pointFill.value)
        for _ = 1, 10 do catch(env) end
        assertEqual(1, bar.pointFill.value)
    end)

    it("empties the left half at a point, and moves the right", function()
        local ns, env, bar = loggedIn()
        catch(env)
        env.__fishing.rank = 232
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertEqual("Fishing 232/300", bar.skillLabel.text)
        assertEqual(0, bar.pointFill.value)
        assertNear(232 / 300, bar.skillFill.value, 1e-9)
    end)

    it("says capped on the left at a trainer's cap, both fills grey, and follows a trainer raising it", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 150, maxRank = 150 } end)
        assertEqual("capped", bar.pointLabel.text)
        assertEqual("Fishing 150/150", bar.skillLabel.text)
        assertEqual(1, bar.pointFill.value)
        assertEqual(1, bar.skillFill.value)
        assertTrue(colourIs(bar.pointFill.barColor, GREY))
        assertTrue(colourIs(bar.skillFill.barColor, GREY))
        env.__fishing.maxRank = 225
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertEqual("Next point", bar.pointLabel.text)
        assertEqual("Fishing 150/225", bar.skillLabel.text)
        assertNear(150 / 225, bar.skillFill.value, 1e-9)
        assertFalse(colourIs(bar.pointFill.barColor, GREY), "no grey left over")
        assertFalse(colourIs(bar.skillFill.barColor, GREY), "no grey left over")
    end)

    it("keeps the right fill within the bar for a cap of 0", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 5, maxRank = 0 } end)
        assertEqual(1, bar.skillFill.value)
    end)

    it("is two halves of the bar's width, following it when it is widened", function()
        local ns, env, bar = loggedIn()
        assertEqual(110, bar.pointFill.width)
        assertEqual(110, bar.skillFill.width)
        bar:SetWidth(307)
        assertEqual(153, bar.pointFill.width)
        assertEqual(154, bar.skillFill.width)
    end)

    it("shows the skill alone, full width, while every catch raises it", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 50, maxRank = 75 } end)
        assertFalse(bar.pointFill:IsShown())
        assertFalse(bar.pointLabel:IsShown())
        assertFalse(bar.divider:IsShown())
        assertEqual(220, bar.skillFill.width)
        assertEqual("Fishing 50/75", bar.skillLabel.text)
        assertNear(50 / 75, bar.skillFill.value, 1e-9)
    end)

    it("brings the left half back once a point takes more than one catch", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 50, maxRank = 150 } end)
        env.__fishing.rank = 100 -- the old rule: a point takes 2 catches here
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertTrue(bar.pointFill:IsShown())
        assertTrue(bar.pointLabel:IsShown())
        assertTrue(bar.divider:IsShown())
        assertEqual(110, bar.pointFill.width)
        assertEqual(110, bar.skillFill.width)
    end)

    it("goes by the measured catches per point where there are enough", function()
        -- Five points at rank 100 that took one catch each: skill alone there.
        local ns, env, bar = loggedIn(POLE, function(e)
            e.__fishing = { rank = 100, maxRank = 150 }
            e.FishingForeverDB = { skillUps = { [100] = { points = 5, catches = 5 } } }
        end)
        assertFalse(bar.pointFill:IsShown())
    end)

    it("brings the left half back for a warning even while every catch raises the skill", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 50, maxRank = 75 } end)
        refused(env)
        assertTrue(bar.pointFill:IsShown())
        assertEqual("too low here", bar.pointLabel.text)
        assertEqual(110, bar.pointFill.width)
        assertEqual(110, bar.skillFill.width)
    end)

    it("keeps the left fill empty, not NaN, when a measured point took no catches and none have been made", function()
        local ns, env, bar = loggedIn(POLE, function(e)
            e.__fishing = { rank = 100, maxRank = 150 }
            e.FishingForeverDB = { skillUps = { [100] = { points = 5, catches = 0 } } }
        end)
        refused(env)
        assertTrue(bar.pointFill:IsShown())
        assertEqual(0, bar.pointFill.value, "no catches since the last point: nothing filled")
    end)

    it("is only a label at 300, the highest rank", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 300, maxRank = 300 } end)
        assertTrue(bar:IsShown())
        assertEqual("Fishing 300/300", bar.skillLabel.text)
        assertFalse(bar.pointFill:IsShown())
        assertFalse(bar.skillFill:IsShown())
        assertFalse(bar.pointLabel:IsShown())
        assertFalse(bar.divider:IsShown())
    end)

    it("turns into the label with the last point, and not before", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 299, maxRank = 300 } end)
        assertTrue(bar.skillFill:IsShown())
        env.__fishing.rank = 300
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertFalse(bar.skillFill:IsShown())
        assertEqual("Fishing 300/300", bar.skillLabel.text)
    end)

    it("brings the halves back at 300 for a warning, grey, with the words in red", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 300, maxRank = 300 } end)
        refused(env)
        assertTrue(bar.pointFill:IsShown())
        assertTrue(bar.skillFill:IsShown())
        assertEqual("too low here", bar.pointLabel.text)
        assertEqual(0.3, bar.pointLabel.textColor[2])
        assertEqual("Fishing 300/300", bar.skillLabel.text)
        assertTrue(colourIs(bar.skillFill.barColor, GREY))

        env.__map = { id = 1436, name = "Westfall" }
        helpers.fire(env, "ZONE_CHANGED_NEW_AREA")
        assertFalse(bar.pointFill:IsShown(), "somewhere else it is the label again")
        assertFalse(bar.skillFill:IsShown())
    end)

    it("is not the label at a trainer's cap below 300", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 225, maxRank = 225 } end)
        assertTrue(bar.skillFill:IsShown())
        assertEqual("capped", bar.pointLabel.text)
    end)

    it("still says capped at the first trainer's cap, where every catch would otherwise raise the skill", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 75, maxRank = 75 } end)
        assertTrue(bar.pointFill:IsShown())
        assertEqual("capped", bar.pointLabel.text)
        assertEqual("Fishing 75/75", bar.skillLabel.text)
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

    it("says what each showing half is", function()
        local ns, env, bar = loggedIn()
        hover(bar)
        assertMatch("next skill point", tooltipText(env))
        assertMatch("against its cap", tooltipText(env))
    end)

    it("does not describe a half that is not there", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 50, maxRank = 75 } end)
        hover(bar)
        assertMatch("against its cap", tooltipText(env))
        assertFalse(tooltipText(env):find("next skill point", 1, true) ~= nil)
    end)

    it("says nothing about halves at 300", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 300, maxRank = 300 } end)
        hover(bar)
        assertFalse(tooltipText(env):find("against its cap", 1, true) ~= nil)
        assertFalse(tooltipText(env):find("next skill point", 1, true) ~= nil)
        assertMatch("Click to open or close your fishing stats", tooltipText(env))
    end)

    it("says on the left, in red, when the game refused a cast here for too little skill, until another zone", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 106, maxRank = 150 } end)
        helpers.fire(env, "UNIT_SPELLCAST_SENT", "player", "", "guid", 7620)
        helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
        assertEqual("too low here", bar.pointLabel.text)
        assertEqual(1, bar.pointLabel.textColor[1])
        assertEqual(0.3, bar.pointLabel.textColor[2])
        assertEqual(0.3, bar.pointLabel.textColor[3])

        env.__map = { id = 1436, name = "Westfall" }
        helpers.fire(env, "ZONE_CHANGED_NEW_AREA")
        assertEqual("Next point", bar.pointLabel.text, "somewhere else the warning is gone")
        assertEqual(1, bar.pointLabel.textColor[2], "and the red with it")
        assertEqual(1, bar.pointLabel.textColor[3], "and the red with it")
    end)

    it("says on the left when every fish of five casts here got away", function()
        local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 150, maxRank = 225 } end)
        for _ = 1, 5 do
            helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
            helpers.fire(env, "UI_ERROR_MESSAGE", 400, "Your fish got away!")
        end
        assertEqual("too low here", bar.pointLabel.text)
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
