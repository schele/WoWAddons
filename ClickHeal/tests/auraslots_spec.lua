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

describe("the game drawing a row's timers", function()
    it("gives a row one container, on the row's unit", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertTrue(ns.AuraSlots.Drawn(row))
        assertEqual("CustomAuraContainerTemplate", row.auraContainer.template)
        assertEqual("party1", row.auraContainer.unit)
        assertEqual(row, row.auraContainer:GetParent(), "shows, hides and fades with the row")
    end)

    it("puts two slots under every button: yours, and anyone else's", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            local slots = row.auraSlots[index]
            assertEqual("HELPFUL", slots.own.frame.filterString)
            assertEqual("HELPFUL", slots.other.frame.filterString)
            assertEqual(true, slots.own.frame.candidateFilters.isFromPlayerOrPlayerPet)
            assertEqual(false, slots.other.frame.candidateFilters.isFromPlayerOrPlayerPet)
            assertFalse(slots.own.frame.enabled, "off until the button has a spell")
            assertFalse(slots.other.frame.enabled)
        end
    end)

    it("writes each number on its slot's own frame, just under the button", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            for _, slot in pairs(row.auraSlots[index]) do
                assertEqual(slot.frame, slot.label:GetParent(), "the game refuses any other label")
                assertEqual(slot.label, slot.frame.durationText)
                local point, relativeTo, relativePoint, x, y = slot.frame:GetPoint(1)
                assertEqual("TOP", point)
                assertEqual(row.buttons[index], relativeTo, "follows the button when it is resized")
                assertEqual("BOTTOM", relativePoint)
                assertEqual(0, x)
                assertEqual(-3, y)
                assertEqual(40, slot.label.width)
                assertEqual(14, slot.label.height)
            end
        end
    end)

    it("draws yours white on a dark plate, above anyone else's grey", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        local slots = row.auraSlots[1]

        assertEqual(1, slots.own.label.textColor[1])
        assertEqual(0.85, slots.own.plate.colorTexture[4])
        assertEqual(slots.own.frame, slots.own.plate:GetParent())
        assertEqual(0.55, slots.other.label.textColor[1])
        assertNil(slots.other.plate)
        assertTrue(slots.own.frame:GetFrameLevel() > slots.other.frame:GetFrameLevel(),
            "your plate covers the grey number when both are there")
    end)

    it("leaves a row to ClickHeal's own timers on a client without the container", function()
        local ns, env = loggedIn(function(e) e.__auraContainer = false end)
        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        assertFalse(ns.AuraSlots.Drawn(row))
        ns.Row.Refresh(row)
        assertEqual("7s", row.buttons[1].timer:GetText())
    end)

    it("falls back to ClickHeal's own timers when the game refuses a slot", function()
        local ns, env = loggedIn(function(e) e.__auraSlotError = "refused" end)
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(ns.AuraSlots.Drawn(row))
        assertNil(row.auraSlots)
    end)

    it("falls back, and puts the half-built container away, when the game refuses a label", function()
        local ns, env = loggedIn()
        local created = env.CreateFrame
        env.CreateFrame = function(kind, name, parent, template)
            local made = created(kind, name, parent, template)
            if kind == "AuraContainer" then
                local add = made.AddAuraSlot
                function made:AddAuraSlot(key, filterString, options)
                    local slot = add(self, key, filterString, {
                        candidateFilters = options.candidateFilters,
                        initializeFrame = function(frame)
                            frame.SetDurationText = function() error("refused", 0) end
                            options.initializeFrame(frame)
                        end,
                    })
                    return slot
                end
            end
            return made
        end
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(ns.AuraSlots.Drawn(row))
        local container
        for _, frame in ipairs(env.__frames) do
            if frame.kind == "AuraContainer" then container = frame end
        end
        assertFalse(container:IsShown(), "nothing half-built left on screen")
    end)
end)

describe("pointing a button's slots at its spell", function()
    local function withIDs(e)
        e.__spellIDsByName["Rejuvenation"] = 774
        e.__spellIDsByName["Mark of the Wild"] = 1126
    end

    it("matches both slots to the button's spell by its ID, and switches them on", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        local slots = row.auraSlots[1]

        assertTrue(slots.own.frame.candidateFilters.includeSpellIDs[774])
        assertTrue(slots.other.frame.candidateFilters.includeSpellIDs[774])
        assertEqual(true, slots.own.frame.candidateFilters.isFromPlayerOrPlayerPet)
        assertEqual(false, slots.other.frame.candidateFilters.isFromPlayerOrPlayerPet)
        assertTrue(slots.own.frame.enabled)
        assertTrue(slots.other.frame.enabled)
    end)

    it("keeps the slots of a button with no spell switched off", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        assertFalse(row.auraSlots[2].own.frame.enabled)
        assertFalse(row.auraSlots[2].other.frame.enabled)
    end)

    it("switches a button's slots off when its spell has no ID, rather than matching every buff", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Healing Touch" })

        assertFalse(row.auraSlots[1].own.frame.enabled)
        assertFalse(row.auraSlots[1].other.frame.enabled)
    end)

    it("follows a change of spell", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        ns.Slots.Set(1, "Mark of the Wild")
        ns.Row.ApplySpells(row)

        local ids = row.auraSlots[1].own.frame.candidateFilters.includeSpellIDs
        assertTrue(ids[1126])
        assertNil(ids[774])
    end)

    it("takes its slots with it when a button is emptied", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        -- Emptied, not counted away: Slots.Count never goes below 1.
        ns.Slots.Set(1, "")
        ns.Row.ApplySpells(row)

        assertFalse(row.auraSlots[1].own.frame.enabled)
    end)
end)
