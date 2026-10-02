local helpers = require("helpers")

local function loggedIn(prepare)
    local ns, env = helpers.loadAddon()
    env.xp, env.xpMax = 500, 1000
    if prepare then
        prepare(env)
    end
    helpers.login(ns, env)
    return ns, env
end

--- The player ticks or unticks a box: it flips, then its script runs.
local function click(box)
    box:SetChecked(not box:GetChecked())
    box.scripts.OnClick(box)
end

describe("the helm and cloak boxes on the character window", function()
    it("sit on the model, one for the helm and one for the cloak", function()
        local ns, env = loggedIn()

        local boxes = ns.HelmCloak.boxes
        assertEqual(env.CharacterModelFrame, boxes.helm.parent)
        assertEqual(env.CharacterModelFrame, boxes.cloak.parent)
        assertEqual("Helm", boxes.helm.label.text)
        assertEqual("Cloak", boxes.cloak.label.text)
    end)

    it("sit each beside its own slot, clear of the slots down the side", function()
        local ns, env = loggedIn()

        local point, relative, relativePoint, x = ns.HelmCloak.boxes.helm:GetPoint(1)
        assertEqual("LEFT", point)
        assertEqual(env.CharacterHeadSlot, relative)
        assertEqual("RIGHT", relativePoint)
        assertTrue(x > 0)
        assertEqual(env.CharacterBackSlot, select(2, ns.HelmCloak.boxes.cloak:GetPoint(1)))
    end)

    it("are ticked while the helm and cloak show", function()
        local ns, env = loggedIn(function(e) e.__showingCloak = false end)
        env.CharacterModelFrame.scripts.OnShow(env.CharacterModelFrame)

        assertTrue(ns.HelmCloak.boxes.helm:GetChecked())
        assertFalse(ns.HelmCloak.boxes.cloak:GetChecked())
    end)

    it("hide the helm when unticked, and show it again when ticked", function()
        local ns, env = loggedIn()
        local helm = ns.HelmCloak.boxes.helm

        click(helm)
        assertFalse(env.__showingHelm)

        click(helm)
        assertTrue(env.__showingHelm)
    end)

    it("hide the cloak when unticked", function()
        local ns, env = loggedIn()

        click(ns.HelmCloak.boxes.cloak)

        assertFalse(env.__showingCloak)
    end)

    it("follow a change made some other way, such as a /run", function()
        local ns, env = loggedIn()

        env.ShowHelm(false)
        helpers.fire(env, "PLAYER_FLAGS_CHANGED", "player")

        assertFalse(ns.HelmCloak.boxes.helm:GetChecked())
    end)

    it("leave out a box the client has no switch for", function()
        local ns = loggedIn(function(e) e.ShowCloak, e.ShowingCloak = nil, nil end)

        assertTrue(ns.HelmCloak.boxes.helm ~= nil)
        assertNil(ns.HelmCloak.boxes.cloak)
    end)

    it("make nothing on a client without a character model", function()
        local ns = loggedIn(function(e) e.CharacterModelFrame = nil end)

        assertNil(ns.HelmCloak.boxes.helm)
    end)
end)
