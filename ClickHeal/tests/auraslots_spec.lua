local helpers = require("helpers")

local FILES = { "ClickHeal.lua", "Anchors.lua", "Spells.lua", "Slots.lua", "AuraSlots.lua", "Row.lua" }

--- Logged in on a client with the aura container, as 1.60.1 is.
local function loggedIn(setup)
    local ns, env = helpers.loadAddon(FILES)
    env.__auraContainer = true
    if setup then setup(env) end
    helpers.login(ns, env)
    return ns, env
end

--- A row for `unit` holding `spells` in its first slots, applied.
local function rowWith(ns, env, unit, spells)
    ns.db.bar.slots = #spells
    for index, spell in ipairs(spells) do
        ns.Slots.Set(index, spell)
    end
    local row = ns.Row.Create(unit, env.UIParent)
    ns.Row.ApplySpells(row)
    return row
end

local SIDES = { "under", "over" }

--- Button `index`'s group of numbers: "own" for yours, "other" for anyone
-- else's, in the container for the number under the icon or, with `side`
-- "over", the one for the number above it.
local function group(row, index, key, side)
    return row.auraTimers[index][side or "under"].container.groups[key]
end

--- Every frame the game may write a number in, for every button.
local function everyNumberFrame(row)
    local frames = {}
    for index, timers in ipairs(row.auraTimers) do
        for _, side in ipairs(SIDES) do
            for _, key in ipairs({ "own", "other" }) do
                for _, frame in ipairs(timers[side].container.groups[key].frames) do
                    frames[#frames + 1] = { frame = frame, key = key, side = side, index = index }
                end
            end
        end
    end
    return frames
end

--- Every aura container made so far.
local function containers(env)
    local found = {}
    for _, frame in ipairs(env.__frames) do
        if frame.kind == "AuraContainer" then
            found[#found + 1] = frame
        end
    end
    return found
end

--- Have the client refuse to let every group's frames write a number:
-- SetDurationText raises inside initializeFrame, where the client only
-- reports it.
local function refuseLabels(env)
    local created = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local made = created(kind, name, parent, template)
        if kind == "AuraContainer" then
            local add = made.AddAuraGroup
            function made:AddAuraGroup(key, filterString, options)
                return add(self, key, filterString, {
                    candidateFilters = options.candidateFilters,
                    maxFrameCount = options.maxFrameCount,
                    layout = options.layout,
                    initializeFrame = function(frame)
                        frame.SetDurationText = function() error("refused", 0) end
                        options.initializeFrame(frame)
                    end,
                })
            end
        end
        return made
    end
end

describe("the game drawing a row's timers", function()
    it("gives a row one container, on the row's unit", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertTrue(ns.AuraSlots.Drawn(row))
        assertEqual("CustomAuraContainerTemplate", row.auraContainer.template)
        assertEqual("party1", row.auraContainer.unit)
        assertEqual(row, row.auraContainer:GetParent(), "shows, hides and fades with the row")
    end)

    it("gives every button two containers of its own for its numbers, on the row's unit", function()
        -- The game lays a group's numbers out inside its container, so a
        -- container serves one button: a second copy of a buff on button 2
        -- must not push button 3's number along. Two, because the frame the
        -- game puts under the icon can be the one it puts over it next, so
        -- a colour for the number over it cannot be set frame by frame.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            local under, over = row.auraTimers[index].under, row.auraTimers[index].over
            for _, set in ipairs({ under, over }) do
                assertEqual("CustomAuraContainerTemplate", set.container.template)
                assertEqual("party1", set.container.unit)
                assertEqual(set.clip, set.container:GetParent())
                assertEqual(row, set.clip:GetParent(), "shows, hides and fades with the row")
                assertTrue(set.container ~= row.auraContainer)
            end
            assertTrue(under.container ~= over.container)
        end
    end)

    it("counts yours and anyone else's apart, two copies of each, yours first, in both", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            for _, side in ipairs(SIDES) do
                local order = row.auraTimers[index][side].container.groupOrder
                assertEqual("own", order[1].key, "yours take the place under the icon")
                assertEqual("other", order[2].key)

                local own, other = group(row, index, "own", side), group(row, index, "other", side)
                assertEqual("HELPFUL", own.filterString)
                assertEqual("HELPFUL", other.filterString)
                assertEqual(true, own.candidateFilters.isFromPlayerOrPlayerPet)
                assertEqual(false, other.candidateFilters.isFromPlayerOrPlayerPet)
                assertEqual(2, own.maxFrameCount)
                assertEqual(2, other.maxFrameCount)
                assertFalse(own.enabled, "off until the button has a spell")
                assertFalse(other.enabled)
            end
        end
    end)

    it("writes each number on its frame's own label, in the timer's box", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for _, entry in ipairs(everyNumberFrame(row)) do
            local frame = entry.frame
            local label = frame.durationText
            assertTrue(label ~= nil, "button " .. entry.index .. " " .. entry.key .. ": a label")
            assertEqual(frame, label:GetParent(), "the game refuses any other label")
            assertEqual(40, label.width)
            assertEqual(14, label.height)
            assertEqual(40, frame.width)
            assertEqual(14, frame.height)
        end
    end)

    it("draws the numbers under the icon white, or grey for anyone else's, and the ones over it green", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        local expected = {
            under = { own = { 1, 1, 1 }, other = { 0.55, 0.55, 0.55 } },
            over = { own = { 0.1, 1, 0.1 }, other = { 0.1 * 0.55, 0.55, 0.1 * 0.55 } },
        }
        for _, entry in ipairs(everyNumberFrame(row)) do
            local colour = entry.frame.durationText.textColor
            local want = expected[entry.side][entry.key]
            for channel = 1, 3 do
                assertNear(want[channel], colour[channel], 1e-9, entry.side .. " " .. entry.key)
            end
            assertNil(entry.frame.plate, "no box behind it")
        end
    end)

    it("leaves a row to ClickHeal's own timers on a client without the container", function()
        local ns, env = loggedIn(function(e) e.__auraContainer = false end)
        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        assertFalse(ns.AuraSlots.Drawn(row))
        ns.Row.Refresh(row)
        assertEqual("7 s", row.buttons[1].timer:GetText())
    end)

    it("falls back to ClickHeal's own timers, with nothing left on screen, when the game refuses a group", function()
        local ns, env = loggedIn(function(e) e.__auraGroupError = "refused" end)
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(ns.AuraSlots.Drawn(row))
        assertNil(row.auraTimers)
        assertNil(row.auraContainer)
        for _, container in ipairs(containers(env)) do
            assertFalse(container:IsShown(), "nothing half-built left on screen")
        end
    end)

    it("falls back, and puts the half-built containers away, when the game refuses a label", function()
        local ns, env = loggedIn()
        refuseLabels(env)
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(ns.AuraSlots.Drawn(row))
        assertTrue(#containers(env) > 0)
        for _, container in ipairs(containers(env)) do
            assertFalse(container:IsShown(), "nothing half-built left on screen")
        end
    end)
end)

describe("where the game puts the numbers", function()
    local function withRejuvenationID(e)
        e.__spellIDsByName["Rejuvenation"] = 774
    end

    --- How far above the bottom of button `index` a shown number's bottom
    -- edge sits: the container hangs off the button, and the game places
    -- each number inside the container.
    local function bottomOf(container, frame)
        local _, _, _, _, containerY = container:GetPoint(1)
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        assertEqual("BOTTOM", point)
        assertEqual(container, relativeTo)
        assertEqual("BOTTOM", relativePoint)
        assertEqual(0, x, "centred on the icon")
        return containerY + y
    end

    --- The numbers button `index` shows when the game finds `counts` copies
    -- (by group) on the unit: every number either container lays out that
    -- falls inside the box clipping it, bottom to top, each with its bottom
    -- edge measured from the bottom of the button and its colour.
    local function visible(row, index, counts)
        local button = row.buttons[index]
        local numbers = {}

        for _, side in ipairs(SIDES) do
            local set = row.auraTimers[index][side]
            assertTrue(set.clip.clipsChildren, side .. ": cuts off what falls outside it")

            local point, relativeTo, relativePoint, x, y = set.clip:GetPoint(1)
            assertEqual(button, relativeTo)
            assertEqual("CENTER", relativePoint)
            assertEqual(0, x)
            local middle = button.height / 2 + y
            local low, high
            if point == "TOP" then
                low, high = middle - set.clip.height, middle
            else
                assertEqual("BOTTOM", point)
                low, high = middle, middle + set.clip.height
            end

            for _, frame in ipairs(set.container:__showAuras(counts)) do
                local bottom = bottomOf(set.container, frame)
                if bottom >= low and bottom + frame.height <= high then
                    numbers[#numbers + 1] = { bottom = bottom, colour = frame.durationText.textColor, side = side }
                end
            end
        end

        table.sort(numbers, function(a, b) return a.bottom < b.bottom end)
        return numbers
    end

    it("hangs each button's containers from the bottom of its button, and stacks the numbers upward", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            for _, side in ipairs(SIDES) do
                local container = row.auraTimers[index][side].container
                local point, relativeTo, relativePoint = container:GetPoint(1)
                assertEqual("BOTTOM", point)
                assertEqual(row.buttons[index], relativeTo, "follows the button when it moves or grows")
                assertEqual("BOTTOM", relativePoint)
                assertEqual(40, container.width, "a size of its own until the game lays it out")
                assertEqual(14, container.height)
                assertEqual(env.AnchorUtil.FlowLayoutAxis.Vertical, container.flow.axis)
                assertEqual("BOTTOM", container.flow.anchorPoint)
                assertEqual(env.AnchorUtil.FlowDirection.Up, container.flow.vertical)
            end
        end
    end)

    it("shows a buff's only number just under the icon, where it always was, in white", function()
        local ns, env = loggedIn(withRejuvenationID)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        local numbers = visible(row, 1, { own = 1 })

        assertEqual(1, #numbers)
        assertEqual(-3, numbers[1].bottom + 14, "its top 3 pixels under the icon")
        assertEqual(1, numbers[1].colour[1])
    end)

    it("shows a second copy of yours above the icon, in green", function()
        local ns, env = loggedIn(withRejuvenationID)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        local numbers = visible(row, 1, { own = 2 })

        assertEqual(2, #numbers)
        assertEqual(-3, numbers[1].bottom + 14, "the first stays under it")
        assertEqual(1, numbers[1].colour[1], "white")
        assertEqual(24 + 3, numbers[2].bottom, "3 pixels above a 24 pixel icon")
        assertEqual("over", numbers[2].side)
        assertEqual(0.1, numbers[2].colour[1], "green")
        assertEqual(1, numbers[2].colour[2])
    end)

    it("shows another caster's copy above yours, in a dimmer green", function()
        local ns, env = loggedIn(withRejuvenationID)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        local numbers = visible(row, 1, { own = 1, other = 1 })

        assertEqual(2, #numbers)
        assertEqual(1, numbers[1].colour[1], "yours under the icon, white")
        assertEqual(24 + 3, numbers[2].bottom)
        assertEqual(0.55, numbers[2].colour[2], "theirs above it, green and dimmed")
    end)

    it("shows another caster's copy under the icon, in grey, when it is the only one", function()
        local ns, env = loggedIn(withRejuvenationID)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        local numbers = visible(row, 1, { other = 1 })

        assertEqual(1, #numbers)
        assertEqual(-3, numbers[1].bottom + 14)
        assertEqual(0.55, numbers[1].colour[1])
        assertEqual(0.55, numbers[1].colour[2])
    end)

    it("shows no more than two of your copies", function()
        local ns, env = loggedIn(withRejuvenationID)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        assertEqual(2, #visible(row, 1, { own = 3 }))
    end)

    it("keeps the upper number clear of a bigger icon, and still green", function()
        local ns, env = loggedIn(withRejuvenationID)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        ns.db.bar.iconSize = 36
        ns.Row.ApplySpells(row)
        local numbers = visible(row, 1, { own = 2 })

        assertEqual(2, #numbers)
        assertEqual(-3, numbers[1].bottom + 14)
        assertEqual(36 + 3, numbers[2].bottom)
        assertEqual("over", numbers[2].side)
    end)

    it("keeps the upper number clear of the smallest icon", function()
        local ns, env = loggedIn(withRejuvenationID)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        ns.db.bar.iconSize = ns.Row.MIN_BUTTON_SIZE
        ns.Row.ApplySpells(row)
        local numbers = visible(row, 1, { own = 2 })

        assertEqual(2, #numbers, "one under and one over, neither cut off nor doubled")
        assertEqual("under", numbers[1].side)
        assertEqual("over", numbers[2].side)
    end)
end)

describe("pointing a button's numbers at its spell", function()
    local function withIDs(e)
        e.__spellIDsByName["Rejuvenation"] = 774
        e.__spellIDsByName["Mark of the Wild"] = 1126
    end

    it("matches both groups, under the icon and over it, to the button's spell by its ID, and switches them on", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        for _, side in ipairs(SIDES) do
            local own, other = group(row, 1, "own", side), group(row, 1, "other", side)
            assertTrue(own.candidateFilters.includeSpellIDs[774], side)
            assertTrue(other.candidateFilters.includeSpellIDs[774], side)
            assertEqual(true, own.candidateFilters.isFromPlayerOrPlayerPet)
            assertEqual(false, other.candidateFilters.isFromPlayerOrPlayerPet)
            assertTrue(own.enabled, side)
            assertTrue(other.enabled, side)
        end
    end)

    it("keeps the numbers of a button with no spell switched off", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        for _, side in ipairs(SIDES) do
            assertFalse(group(row, 2, "own", side).enabled, side)
            assertFalse(group(row, 2, "other", side).enabled, side)
        end
    end)

    it("switches a button's numbers off when its spell has no ID, rather than matching every buff", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Healing Touch" })

        for _, side in ipairs(SIDES) do
            assertFalse(group(row, 1, "own", side).enabled, side)
            assertFalse(group(row, 1, "other", side).enabled, side)
        end
    end)

    it("follows a change of spell", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        ns.Slots.Set(1, "Mark of the Wild")
        ns.Row.ApplySpells(row)

        for _, side in ipairs(SIDES) do
            local ids = group(row, 1, "own", side).candidateFilters.includeSpellIDs
            assertTrue(ids[1126], side)
            assertNil(ids[774], side)
        end
    end)

    it("takes its numbers with it when a button is emptied", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        -- Emptied, not counted away: Slots.Count never goes below 1.
        ns.Slots.Set(1, "")
        ns.Row.ApplySpells(row)

        assertFalse(group(row, 1, "own").enabled)
        assertFalse(group(row, 1, "own", "over").enabled)
    end)
end)

describe("learning other ranks' IDs", function()
    local function withIDs(e)
        e.__spellIDsByName["Rejuvenation"] = 774
    end

    it("widens both groups with an ID seen on a buff out of combat", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 } }

        ns.Row.Refresh(row)

        assertTrue(group(row, 1, "own").candidateFilters.includeSpellIDs[774], "the spellbook's still")
        assertTrue(group(row, 1, "own").candidateFilters.includeSpellIDs[1430])
        assertTrue(group(row, 1, "other").candidateFilters.includeSpellIDs[1430])
        assertTrue(group(row, 1, "own", "over").candidateFilters.includeSpellIDs[1430], "over the icon too")
        assertTrue(group(row, 1, "other", "over").candidateFilters.includeSpellIDs[1430])
    end)

    it("learns the ID of every copy on the unit, not only the first's", function()
        -- Two copies are exactly when the second number shows, and the
        -- second can be another rank: another druid's, or your own lower one.
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        env.__auras.party1 = {
            { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 },
            { name = "Rejuvenation", expirationTime = 1012, spellId = 2090, caster = "party2" },
        }

        ns.Row.Refresh(row)

        assertTrue(group(row, 1, "own").candidateFilters.includeSpellIDs[1430])
        assertTrue(group(row, 1, "other").candidateFilters.includeSpellIDs[2090])
        assertTrue(group(row, 1, "other", "over").candidateFilters.includeSpellIDs[2090])
    end)

    it("waits for combat to end before touching the groups", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 } }
        local under, over = row.auraTimers[1].under.container, row.auraTimers[1].over.container
        local writes = under.filterWrites + over.filterWrites

        env.__inCombat = true
        ns.Row.RefreshAuras(row)
        assertEqual(writes, under.filterWrites + over.filterWrites, "no filter changes in combat")

        env.__inCombat = false
        ns.Row.RefreshAuras(row)
        assertTrue(group(row, 1, "own").candidateFilters.includeSpellIDs[1430])
    end)

    it("widens every row holding the spell, not just the one it was seen on", function()
        local ns, env = loggedIn(withIDs)
        local first = rowWith(ns, env, "party1", { "Rejuvenation" })
        local second = rowWith(ns, env, "party2", { "Rejuvenation" })
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 } }

        ns.Row.Refresh(first)

        assertTrue(group(second, 1, "own").candidateFilters.includeSpellIDs[1430])
    end)

    it("writes no number of its own on a row the game draws", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        env.__now = 1000
        env.__auras.party1 = {
            { name = "Rejuvenation", expirationTime = 1007, spellId = 774 },
            { name = "Rejuvenation", expirationTime = 1012, spellId = 774 },
        }

        ns.Row.Refresh(row)

        assertEqual("", row.buttons[1].timer:GetText(), "the game's number is the only one")
        assertEqual("", row.buttons[1].timerAbove:GetText(), "above the icon as well")
    end)
end)

-- The game's seconds formatter, as far as a test needs it: every setting it
-- is given, recorded.
local function withFormatter(e, leaveOut)
    e.Enum.SecondsFormatterAbbreviation = { None = 0, Truncate = 1, OneLetter = 2 }
    e.Enum.SecondsFormatterIntervalWhitespace = { Preserve = 0, Strip = 1, StripIgnoreLocale = 2 }
    e.Enum.SecondsFormatterInterval = { Seconds = 0, Minutes = 1, Hours = 2, Days = 3 }
    e.Enum.SecondsFormatterRounding = { RoundUp = 0, Truncate = 1 }
    e.C_StringUtil = {
        CreateSecondsFormatter = function()
            local formatter = { settings = {} }
            for _, setter in ipairs({ "SetDefaultAbbreviation", "SetStripIntervalWhitespace",
                "SetDesiredUnitCount", "SetMinInterval", "SetRounding", "SetCanRoundUpLastUnit" }) do
                if setter ~= leaveOut then
                    formatter[setter] = function(self, value) self.settings[setter] = value end
                end
            end
            return formatter
        end,
    }
end

describe("the game's numbers", function()
    it("are written by the game's own formatter, as its buff icons are", function()
        -- ClickHeal's own formatter rounded seconds up, and read a second
        -- ahead of the game's buff icon for the same buff; it also turned
        -- 75 s into 2 m. With no formatter of ours, SetDurationText uses the
        -- game's default: seconds cut, seconds up to 90, minutes rounded up.
        local ns, env = loggedIn(function(e) withFormatter(e) end)
        local row = ns.Row.Create("party1", env.UIParent)

        for _, entry in ipairs(everyNumberFrame(row)) do
            local options = entry.frame.durationOptions
            assertNil(options and options.textFormatter, entry.key .. " leaves the formatting to the game")
        end
    end)
end)

describe("the game's timers on screen, after review", function()
    it("let clicks through to the spell icons around them", function()
        -- Each number is on Blizzard's aura button, which takes the mouse.
        -- In the stacked bar a 40 by 14 timer box sits over the top of the
        -- icon on the row below, and the one above the icon over the row
        -- above: a click there would land on the timer and cast nothing.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for _, entry in ipairs(everyNumberFrame(row)) do
            assertFalse(entry.frame.mouseEnabled, "button " .. entry.index .. ": " .. entry.side .. " " .. entry.key)
        end
    end)

    it("give the container its row's place, as the probe did", function()
        -- A frame with no points is not drawn; the dispel slots are anchored
        -- to the buttons, but nothing promises the game draws them under a
        -- parent that has no place of its own.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertEqual(row, row.auraContainer.allPointsTo)
    end)

    it("re-read every container's unit when asked, the numbers' as well as the blink's", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        ns.AuraSlots.Refresh(row)

        assertEqual(1, row.auraContainer.refreshes)
        for index = 1, ns.Slots.MAX do
            assertEqual(1, row.auraTimers[index].under.container.refreshes, "button " .. index)
            assertEqual(1, row.auraTimers[index].over.container.refreshes, "button " .. index)
        end
    end)
end)

describe("blinking a button whose spell can remove a debuff on the unit", function()
    it("gives every button a slot of its own over its icon, for debuffs, switched off", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            local frame = row.dispelSlots[index].frame
            local button = row.buttons[index]
            assertEqual("HARMFUL", frame.filterString)
            assertFalse(frame.enabled, "off until the button has a spell that removes something")
            assertEqual(button, frame.allPointsTo, "over the icon, following it through a resize")
            assertTrue(frame:GetFrameLevel() > button:GetFrameLevel(), "drawn over the icon")
            assertFalse(frame.mouseEnabled, "a click goes through to the spell")
        end
    end)

    it("switches on a Remove Curse button's slot, for curses only", function()
        local ns, env = loggedIn()
        local row = rowWith(ns, env, "party1", { "Rejuvenation", "Remove Curse" })

        local curse = row.dispelSlots[2].frame
        assertTrue(curse.enabled)
        assertTrue(curse.candidateFilters.includeDispelTypes.Curse)
        assertNil(curse.candidateFilters.includeDispelTypes.Poison)
        assertFalse(row.dispelSlots[1].frame.enabled, "Rejuvenation removes nothing")
    end)

    it("matches every type a spell removes, as Cleanse does", function()
        local ns, env = loggedIn(function(e) e.__spells["Cleanse"] = true end)
        local row = rowWith(ns, env, "party1", { "Cleanse" })

        local types = row.dispelSlots[1].frame.candidateFilters.includeDispelTypes
        assertTrue(types.Poison)
        assertTrue(types.Disease)
        assertTrue(types.Magic)
    end)

    it("follows a change of spell", function()
        local ns, env = loggedIn()
        local row = rowWith(ns, env, "party1", { "Remove Curse" })

        ns.Slots.Set(1, "Rejuvenation")
        ns.Row.ApplySpells(row)

        assertFalse(row.dispelSlots[1].frame.enabled)
    end)

    it("blinks while the game shows it, by fading the frame in and out", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        local frame = row.dispelSlots[1].frame

        local group = frame.shownAnimations[1]
        assertTrue(group ~= nil, "handed to the game, which plays it when the debuff appears")
        assertEqual("BOUNCE", group.looping, "keeps blinking until the debuff is gone")
        local fade = group.animations[1]
        assertEqual("Alpha", fade.kind)
        assertEqual(frame, fade:GetTarget())
        assertTrue(fade.toAlpha < fade.fromAlpha)
    end)

    it("frames the icon in the colour the game gives the debuff's type", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        local frame = row.dispelSlots[1].frame

        assertEqual(4, #frame.dispelTextures, "the four edges")
        for _, entry in ipairs(frame.dispelTextures) do
            assertEqual(env.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, entry.options.style,
                "the edge keeps its shape and takes the colour")
        end
    end)

    it("still lights the icon, unblinking, when the game refuses the animation", function()
        local ns, env = loggedIn()
        local created = env.CreateFrame
        env.CreateFrame = function(kind, name, parent, template)
            local made = created(kind, name, parent, template)
            if kind == "AuraContainer" then
                local add = made.AddAuraSlot
                function made:AddAuraSlot(key, filterString, options)
                    return add(self, key, filterString, {
                        candidateFilters = options.candidateFilters,
                        initializeFrame = function(frame)
                            frame.AddAuraShownAnimation = function() error("refused", 0) end
                            options.initializeFrame(frame)
                        end,
                    })
                end
            end
            return made
        end
        local row = rowWith(ns, env, "party1", { "Remove Curse" })

        assertTrue(row.dispelSlots[1].frame.enabled)
        assertTrue(ns.AuraSlots.Drawn(row), "the timers are untouched")
    end)

    it("costs only the blink, never the timers, when the game refuses the slot", function()
        local ns, env = loggedIn()
        local created = env.CreateFrame
        env.CreateFrame = function(kind, name, parent, template)
            local made = created(kind, name, parent, template)
            if kind == "AuraContainer" then
                local add = made.AddAuraSlot
                function made:AddAuraSlot(key, filterString, options)
                    if key:find("^dispel") then
                        error("refused", 0)
                    end
                    return add(self, key, filterString, options)
                end
            end
            return made
        end
        local row = rowWith(ns, env, "party1", { "Remove Curse" })

        assertTrue(ns.AuraSlots.Drawn(row))
        assertNil(row.dispelSlots)
    end)

    it("switches off what was built when a later slot is refused", function()
        local ns, env = loggedIn()
        local created = env.CreateFrame
        env.CreateFrame = function(kind, name, parent, template)
            local made = created(kind, name, parent, template)
            if kind == "AuraContainer" then
                local add = made.AddAuraSlot
                function made:AddAuraSlot(key, filterString, options)
                    if key == "dispel2" then
                        error("refused", 0)
                    end
                    return add(self, key, filterString, options)
                end
            end
            return made
        end
        local row = rowWith(ns, env, "party1", { "Remove Curse" })

        assertFalse(row.auraContainer.slots.dispel1.enabled, "nothing half-built left blinking")
    end)

    it("blinks nothing on a client without the container", function()
        local ns, env = loggedIn(function(e) e.__auraContainer = false end)
        local row = rowWith(ns, env, "party1", { "Remove Curse" })

        assertNil(row.dispelSlots)
    end)
end)


describe("timers for a lower rank", function()
    it("match every rank of the button's spell, so a rank cast on someone low has its number", function()
        local ns, env = loggedIn(function(e)
            e.__learnRank(1, "Mark of the Wild", 1126, 1)
            e.__learnRank(2, "Mark of the Wild", 5232, 10)
            e.__learnRank(3, "Mark of the Wild", 6756, 20)
        end)
        local row = rowWith(ns, env, "party1", { "Mark of the Wild" })

        local ids = group(row, 1, "own").candidateFilters.includeSpellIDs
        assertTrue(ids[1126])
        assertTrue(ids[5232])
        assertTrue(ids[6756])
    end)
end)
