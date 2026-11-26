local helpers = require("helpers")

local SLOT = helpers.SLOT
local CAT, BEAR = helpers.CAT, helpers.BEAR

--- A druid with a mace and an idol, a staff and an idol for Cat in the
-- bags, and Cat's set (1) chosen: `catSlots` says what it holds (default:
-- legs and the staff). The stance bar has its four forms.
local function druid(catSlots, extra)
    local ns, env = helpers.start(nil, function(env)
        helpers.druid(env)
        helpers.wear(env, SLOT.LEGS, "legs-caster")
        helpers.wear(env, SLOT.MAINHAND, "mace")
        helpers.wear(env, SLOT.RANGED, "idol")
        helpers.stow(env, "legs-cat", SLOT.LEGS)
        helpers.stow(env, "staff-cat", SLOT.MAINHAND)
        helpers.stow(env, "idol-cat", SLOT.RANGED)
        helpers.makeSet(env, 1, "Cat", catSlots or { [SLOT.LEGS] = "legs-cat", [SLOT.MAINHAND] = "staff-cat" })
        if extra then extra(env) end
    end)
    ns.Forms.SetSet(CAT, 1)
    return ns, env
end

local function macro(ns, index)
    local button = ns.Stance.buttons[index]
    return button and button:GetAttribute("macrotext")
end

describe("the stance bar's buttons", function()
    it("are left alone while no chosen set holds a weapon", function()
        local ns = druid({ [SLOT.LEGS] = "legs-cat" })
        assertNil(next(ns.Stance.buttons))
    end)

    it("get a button of WardrobeForever's over each form once a set holds a weapon", function()
        local ns, env = druid()
        for index = 1, 4 do
            local button = ns.Stance.buttons[index]
            assertTrue(button and button:IsShown(), "over stance button " .. index)
            assertEqual(env.StanceBar.actionButtons[index], button:GetParent())
            assertEqual(env.StanceBar.actionButtons[index], button.allPoints)
            assertEqual("macro", button:GetAttribute("type"))
        end
        assertNil(ns.Stance.buttons[5], "no button where there is no form")
    end)

    it("shift Cat and swap the staff in, or the mace back when leaving Cat", function()
        local ns = druid()
        assertEqual("/cast Cat Form\n"
            .. "/equipslot [form:3] 16 mace\n"
            .. "/equipslot [noform:3] 16 staff-cat", macro(ns, 3))
    end)

    it("put the mace back from a form with no set", function()
        local ns = druid()
        assertEqual("/cast Bear Form\n/equipslot 16 mace", macro(ns, 1))
    end)

    it("swap every weapon slot a set fills", function()
        local ns = druid({ [SLOT.MAINHAND] = "staff-cat", [SLOT.RANGED] = "idol-cat" })
        assertEqual("/cast Cat Form\n"
            .. "/equipslot [form:3] 16 mace\n"
            .. "/equipslot [noform:3] 16 staff-cat\n"
            .. "/equipslot [form:3] 18 idol\n"
            .. "/equipslot [noform:3] 18 idol-cat", macro(ns, 3))
    end)

    it("leave out a set weapon that is gone", function()
        local ns, env = druid({ [SLOT.MAINHAND] = "staff-cat", [SLOT.RANGED] = "idol-cat" })
        helpers.remove(env, "staff-cat")
        helpers.fire(env, "BAG_UPDATE_DELAYED")
        assertEqual("/cast Cat Form\n"
            .. "/equipslot [form:3] 18 idol\n"
            .. "/equipslot [noform:3] 18 idol-cat", macro(ns, 3))
    end)

    it("keep the normal weapon while you are shifted", function()
        local ns, env = druid()
        helpers.shift(env, CAT)
        assertEqual("staff-cat", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("/cast Bear Form\n/equipslot 16 mace", macro(ns, 1))
    end)

    it("follow a new weapon you put on in normal form", function()
        local ns, env = druid(nil, function(env)
            helpers.stow(env, "mace-new", SLOT.MAINHAND)
        end)
        helpers.byHand(env, SLOT.MAINHAND, "mace-new")
        assertEqual("/cast Bear Form\n/equipslot 16 mace-new", macro(ns, 1))
    end)

    it("keep their text through a fight, and catch up when it ends", function()
        local ns, env = druid(nil, function(env)
            helpers.stow(env, "staff-cat2", SLOT.MAINHAND)
        end)
        helpers.fight(env, true)
        helpers.makeSet(env, 1, "Cat", { [SLOT.MAINHAND] = "staff-cat2" })
        helpers.fire(env, "EQUIPMENT_SETS_CHANGED")
        assertMatch("noform:3%] 16 staff%-cat\n?$", macro(ns, 3))

        helpers.fight(env, false)
        assertMatch("noform:3%] 16 staff%-cat2$", macro(ns, 3))
    end)

    it("tell WardrobeForever a shift is coming when clicked", function()
        local ns, env = druid()
        ns.Stance.buttons[3]:Fire("PreClick", "LeftButton", true)
        helpers.byHand(env, SLOT.MAINHAND, "staff-cat") -- the click's /equipslot
        assertEqual("mace", env.WardrobeForeverCharDB.home[SLOT.MAINHAND])
    end)

    it("show the form's tooltip", function()
        local ns, env = druid()
        ns.Stance.buttons[3]:Fire("OnEnter")
        assertEqual(3, env.GameTooltip.shapeshift)
        assertEqual(ns.Stance.buttons[3], env.GameTooltip.owner)
    end)

    it("step aside in Edit Mode, so the bar can be moved", function()
        local ns, env = druid()
        env.EditModeManagerFrame:Show()
        assertFalse(ns.Stance.buttons[3]:IsShown())
        env.EditModeManagerFrame:Hide()
        assertTrue(ns.Stance.buttons[3]:IsShown())
    end)

    it("step aside in Quick Keybind mode, so the bar can be bound", function()
        local ns, env = druid()
        env.QuickKeybindFrame:Show()
        assertFalse(ns.Stance.buttons[3]:IsShown())
        env.QuickKeybindFrame:Hide()
        assertTrue(ns.Stance.buttons[3]:IsShown())
    end)

    it("go away when no set holds a weapon any more", function()
        local ns = druid()
        ns.Forms.SetSet(CAT, nil)
        assertFalse(ns.Stance.buttons[3]:IsShown())
    end)
end)

describe("the stance bar's buttons, after the review", function()
    it("put the mace and the book back when leaving a two-handed Cat", function()
        local ns = druid({ [SLOT.MAINHAND] = "staff-cat", [SLOT.OFFHAND] = "empty" }, function(env)
            helpers.wear(env, SLOT.OFFHAND, "book")
        end)
        assertEqual("/cast Cat Form\n"
            .. "/equipslot [form:3] 16 mace\n"
            .. "/equipslot [noform:3] 16 staff-cat\n"
            .. "/equipslot [form:3] 17 book", macro(ns, 3))
        assertEqual("/cast Bear Form\n/equipslot 16 mace\n/equipslot 17 book", macro(ns, 1))
    end)

    it("do not knock a set's main hand off with the normal off-hand", function()
        local ns = druid({ [SLOT.MAINHAND] = "staff-cat" }, function(env)
            helpers.wear(env, SLOT.OFFHAND, "book")
            helpers.stow(env, "shield", SLOT.OFFHAND)
            helpers.makeSet(env, 2, "Bear", { [SLOT.OFFHAND] = "shield" })
        end)
        ns.Forms.SetSet(BEAR, 2)
        assertEqual("/cast Cat Form\n"
            .. "/equipslot [form:3] 16 mace\n"
            .. "/equipslot [noform:3] 16 staff-cat\n"
            .. "/equipslot [form:3] 17 book", macro(ns, 3))
        assertEqual("/cast Bear Form\n"
            .. "/equipslot 16 mace\n"
            .. "/equipslot [form:1] 17 book\n"
            .. "/equipslot [noform:1] 17 shield", macro(ns, 1))
    end)

    it("tell WardrobeForever which weapons a click puts on, going in or coming out", function()
        local ns, env = druid()
        local expected
        ns.Forms.ExpectClick = function(targets) expected = targets end
        ns.Stance.buttons[3]:Fire("PreClick", "LeftButton", true)
        assertEqual("staff-cat", expected[SLOT.MAINHAND], "into Cat")

        helpers.shift(env, CAT)
        ns.Stance.buttons[3]:Fire("PreClick", "LeftButton", true)
        assertEqual("mace", expected[SLOT.MAINHAND], "out of Cat")
    end)

    it("leave a warrior's stance bar alone: druids only for now", function()
        local ns = druid(nil, function(env)
            env.__class = "WARRIOR"
        end)
        assertNil(next(ns.Stance.buttons))
    end)

    it("follow the stance bar when a form is learned", function()
        local ns, env = druid()
        table.insert(env.__forms, { spellID = 24858, name = "Moonkin Form" })
        helpers.fire(env, "UPDATE_SHAPESHIFT_FORMS")
        assertEqual("/cast Moonkin Form\n/equipslot 16 mace", macro(ns, 5))
    end)

    it("follow Dire Bear Form taking Bear Form's place", function()
        local ns, env = druid()
        env.__forms[1] = { spellID = 9634, name = "Dire Bear Form" }
        helpers.fire(env, "SPELLS_CHANGED")
        assertMatch("^/cast Dire Bear Form\n", macro(ns, 1))
    end)
end)
