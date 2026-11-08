local helpers = require("helpers")

local SLOT = helpers.SLOT

-- A character wearing legs, with a second pair in the backpack.
local function spareLegs()
    local ns, env = helpers.load()
    helpers.fits(env, SLOT.LEGS, helpers.worn(SLOT.LEGS), 101)
    helpers.fits(env, SLOT.LEGS, helpers.inBag(0, 3), 102)
    return ns, env
end

describe("hovering a slot", function()
    it("opens Blizzard's list when you have something else for that slot", function()
        local _, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("keeps it open while you stay on the slot", function()
        -- Blizzard's own per-frame check hides an Alt-less pop-out on the
        -- very next frame; this is the test that proves it stays.
        local _, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.tick(env, 2)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("puts the slot's tooltip beside the list, where Blizzard puts it with Alt", function()
        local _, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)

        assertEqual("flyout", env.__tooltip)
    end)

    it("leaves it closed when the only item for the slot is the one you wear", function()
        local _, env = helpers.load()
        helpers.fits(env, SLOT.LEGS, helpers.worn(SLOT.LEGS), 101)

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.tick(env, 0.5)

        assertFalse(env.EquipmentFlyoutFrame:IsShown())
        assertEqual("slot", env.__tooltip)
    end)

    it("leaves it closed for an empty slot with nothing to put in it", function()
        local _, env = helpers.load()

        helpers.moveTo(env, env.CharacterLegsSlot)

        assertFalse(env.EquipmentFlyoutFrame:IsShown())
    end)

    it("opens it for an empty slot when you have something to put in it", function()
        local _, env = helpers.load()
        helpers.fits(env, SLOT.LEGS, helpers.inBag(2, 7), 102)

        helpers.moveTo(env, env.CharacterLegsSlot)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("does not count the ring on your other finger as something to swap", function()
        -- Blizzard lists both worn rings for either finger slot.
        local _, env = helpers.load()
        helpers.fits(env, SLOT.FINGER0, helpers.worn(SLOT.FINGER0), 201)
        helpers.fits(env, SLOT.FINGER0, helpers.worn(SLOT.FINGER1), 202)

        helpers.moveTo(env, env.CharacterFinger0Slot)

        assertFalse(env.EquipmentFlyoutFrame:IsShown())
    end)

    it("counts an item Blizzard lists from the bank", function()
        local _, env = helpers.load()
        helpers.fits(env, SLOT.LEGS, helpers.worn(SLOT.LEGS), 101)
        helpers.fits(env, SLOT.LEGS, helpers.inBank(5), 103)

        helpers.moveTo(env, env.CharacterLegsSlot)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("works on the weapon slots too", function()
        local _, env = helpers.load()
        helpers.fits(env, SLOT.MAINHAND, helpers.inBag(1, 1), 301)

        helpers.moveTo(env, env.CharacterMainHandSlot)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterMainHandSlot))
    end)

    it("leaves Alt to Blizzard", function()
        local _, env = spareLegs()
        env.__altDown = true

        helpers.moveTo(env, env.CharacterLegsSlot)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot), "Blizzard opens it")
        assertFalse(env.CharacterLegsSlot.popoutButton.flyoutLocked, "and WardrobeForever stayed out of it")
    end)
end)

describe("leaving", function()
    it("stays open while the mouse is on the list", function()
        local ns, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, env.EquipmentFlyoutFrame.buttonFrame)
        helpers.tick(env, ns.CLOSE_DELAY * 4)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("stays open while the mouse is on the page buttons", function()
        local ns, env = spareLegs()
        env.EquipmentFlyoutFrame.NavigationFrame.shown = true

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, env.EquipmentFlyoutFrame.NavigationFrame)
        helpers.tick(env, ns.CLOSE_DELAY * 4)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("survives the mouse crossing the gap between the slot and the list", function()
        local ns, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, nil)
        helpers.tick(env, ns.CLOSE_DELAY / 2)
        helpers.moveTo(env, env.EquipmentFlyoutFrame.buttonFrame)
        helpers.tick(env, ns.CLOSE_DELAY * 4)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("does not close the instant the mouse leaves", function()
        local ns, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, nil)
        helpers.tick(env, ns.CLOSE_DELAY / 2)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("closes once the mouse has been off the slot and the list for a moment", function()
        local ns, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, nil)
        helpers.tick(env, ns.CLOSE_DELAY + 0.1)

        assertFalse(env.EquipmentFlyoutFrame:IsShown())
        assertFalse(env.CharacterLegsSlot.popoutButton.flyoutLocked, "the arrow is not left looking open")
    end)

    it("opens again when you come back after it closed", function()
        local ns, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, nil)
        helpers.tick(env, ns.CLOSE_DELAY + 0.1)
        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.tick(env, 1)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)
end)

describe("moving from one slot to another", function()
    it("hands the list to the new slot", function()
        local ns, env = spareLegs()
        helpers.fits(env, SLOT.FEET, helpers.inBag(0, 4), 401)

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, env.CharacterFeetSlot)
        helpers.tick(env, ns.CLOSE_DELAY * 4)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterFeetSlot))
        assertFalse(env.CharacterLegsSlot.popoutButton.flyoutLocked, "the legs arrow is let go")
    end)

    it("closes the list straight away on a slot with nothing to swap", function()
        -- Otherwise the head's tooltip would sit beside the legs list.
        local _, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, env.CharacterHeadSlot)

        assertFalse(env.EquipmentFlyoutFrame:IsShown())
        assertEqual("slot", env.__tooltip)
    end)
end)

describe("clicking an item in the list", function()
    it("closes the list", function()
        local _, env = spareLegs()

        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, env.EquipmentFlyoutFrame.buttonFrame)
        env.EquipmentFlyoutButton_OnClick()
        helpers.tick(env, 0.1)

        assertFalse(env.EquipmentFlyoutFrame:IsShown())
    end)
end)

describe("a list you pinned open with the arrow", function()
    it("is not closed by moving away", function()
        local ns, env = spareLegs()

        env.EquipmentFlyoutPopoutButton_OnClick(env.CharacterLegsSlot.popoutButton)
        helpers.moveTo(env, nil)
        helpers.tick(env, ns.CLOSE_DELAY * 4)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("stays pinned after you hover its slot and leave again", function()
        local ns, env = spareLegs()

        env.EquipmentFlyoutPopoutButton_OnClick(env.CharacterLegsSlot.popoutButton)
        helpers.moveTo(env, env.CharacterLegsSlot)
        helpers.moveTo(env, nil)
        helpers.tick(env, ns.CLOSE_DELAY * 4)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)

    it("is not closed by hovering a slot with nothing to swap", function()
        local ns, env = spareLegs()

        env.EquipmentFlyoutPopoutButton_OnClick(env.CharacterLegsSlot.popoutButton)
        helpers.moveTo(env, env.CharacterHeadSlot)
        helpers.tick(env, ns.CLOSE_DELAY * 4)

        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)
end)

describe("on a client without Blizzard's pop-out", function()
    it("loads without complaint and does nothing", function()
        local stub = require("wow_stub")
        local env = stub.newEnv()
        env.EquipmentFlyoutFrame = nil

        local chunk = assert(loadfile("WardrobeForever.lua", "t", env))
        chunk("WardrobeForever", {})
    end)
end)
