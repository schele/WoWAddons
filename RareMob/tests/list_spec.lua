local helpers = require("helpers")

local NOW = 1790000000
local DAY = 86400

local function ids(entries)
    local list = {}
    for _, entry in ipairs(entries) do list[#list + 1] = tostring(entry.id) end
    return table.concat(list, ",")
end

local function shownRows(frame)
    local shown = {}
    for _, row in ipairs(frame.rows) do
        if row:IsShown() then shown[#shown + 1] = row end
    end
    return shown
end

local withVultros = helpers.withSightings({ [462] = helpers.sighting("Vultros", 26, NOW - 3 * DAY, { helpers.place(0.5, 0.5) }) })

describe("the list's entries", function()
    it("are the zone's rares, database and sightings, by level", function()
        local ns = helpers.loggedIn(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { helpers.place(0.2, 0.3) }),
        }))
        assertEqual("520,462,777,1", ids(ns.List.Entries(1436)))
    end)

    it("say each one's name, level, when last seen, and whether WoW Forever has it", function()
        local ns = helpers.loggedIn(withVultros)
        local entries = ns.List.Entries(1436)
        local vultros, elite = entries[2], entries[3]
        assertEqual("Vultros", vultros.name)
        assertEqual("26", vultros.level)
        assertEqual("3 days ago", vultros.last)
        assertTrue(vultros.seen)
        assertEqual("Elite Rare", elite.name)
        assertEqual("40-42", elite.level)
        assertEqual("never", elite.last)
        assertFalse(elite.seen)
    end)

    it("leave out the database-only rares when the setting says so", function()
        local ns = helpers.loggedIn(withVultros)
        ns.settings.showUnseen = false
        assertEqual("462", ids(ns.List.Entries(1436)))
    end)

    it("are none where the map has no place", function()
        local ns = helpers.loggedIn()
        assertEqual("", ids(ns.List.Entries(947)))
        assertEqual("", ids(ns.List.Entries(nil)))
    end)
end)

describe("the list window", function()
    it("opens on a bare /rm, on the player's zone", function()
        local ns, env = helpers.loggedIn(withVultros)
        helpers.command(env, "")
        local frame = ns.List.Frame()
        assertTrue(frame:IsShown())
        assertEqual("RareMob", frame.title:GetText())
        assertMatch("Westfall", frame.zone:GetText())
        local rows = shownRows(frame)
        assertEqual(3, #rows)
        assertEqual("Brack", rows[1].name:GetText())
        assertEqual("19", rows[1].level:GetText())
        assertEqual("never", rows[1].last:GetText())
        assertEqual("3 days ago", rows[2].last:GetText())
        assertMatch("Yes", rows[2].seen:GetText())
        assertMatch("No", rows[1].seen:GetText())
    end)

    it("closes on a second /rm", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "")
        helpers.command(env, "")
        assertFalse(ns.List.Frame():IsShown())
    end)

    it("has BossLoot's frame, with a solid background", function()
        local ns, env = helpers.loggedIn()
        ns.List.Open()
        local frame = ns.List.Frame()
        assertEqual(1, frame.background.color[4])
        assertEqual("Interface\\AddOns\\RareMob\\minimap", frame.logo:GetTexture())
        frame.close.scripts.OnClick(frame.close)
        assertFalse(frame:IsShown())
    end)

    it("opens the map on a clicked rare, with its pins glowing", function()
        local ns, env = helpers.loggedIn()
        ns.List.Open()
        local row = shownRows(ns.List.Frame())[2]
        row.scripts.OnClick(row)
        assertTrue(env.WorldMapFrame:IsShown())
        assertEqual(1436, env.__worldMapID)
        assertEqual(462, ns.Pins.highlight)
        assertFalse(ns.List.Frame():IsShown(), "out of the map's way")
    end)

    it("adds a rare spotted while it is open", function()
        local ns, env = helpers.loggedIn()
        ns.List.Open()
        env.__units.target = env.__creature(777, "New Rare", 33, "rare")
        helpers.fire(env, "PLAYER_TARGET_CHANGED")
        local rows = shownRows(ns.List.Frame())
        assertEqual(4, #rows)
        assertEqual("New Rare", rows[3].name:GetText())
        assertEqual("just now", rows[3].last:GetText())
    end)

    it("follows the player into another zone", function()
        local ns, env = helpers.loggedIn()
        ns.List.Open()
        env.__playerMap = 947
        helpers.fire(env, "ZONE_CHANGED_NEW_AREA")
        assertEqual(0, #shownRows(ns.List.Frame()))
        assertMatch("No rares", ns.List.Frame().empty:GetText())
        assertTrue(ns.List.Frame().empty:IsShown())
    end)
end)
