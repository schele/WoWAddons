local addonName, ns = ...

-- Where Blizzard's own unit frames are, for the layout that hangs a row's
-- buttons off them instead of off a bar of our own.
--
-- Every lookup here is by global name and every one of them may come back
-- empty. That is not defensiveness for its own sake: these frames genuinely
-- are not always there. "Use Raid-Style Party Frames" replaces
-- PartyMemberFrame1-4 with a compact frame entirely, and any unit-frame addon
-- may remove them outright. A missing frame is an ordinary answer, not an
-- error, and Group falls back to the standalone bar when it gets one.

local Anchors = {}
ns.Anchors = Anchors

-- Blizzard's frame for each unit this addon draws a row for. PlayerFrame is
-- a different size and shape from the party frames, which is why the offsets
-- below are per unit rather than one figure for all five.
local FRAME_NAMES = {
    player = "PlayerFrame",
    party1 = "PartyMemberFrame1",
    party2 = "PartyMemberFrame2",
    party3 = "PartyMemberFrame3",
    party4 = "PartyMemberFrame4",
}

--- The widget at this global name, or nil if there is nothing usable there.
--
-- A name that holds something which is not a widget -- a table another addon
-- has parked there -- has to read as absent rather than be anchored to.
-- GetObjectType is the cheapest thing only a real widget has.
local function widgetNamed(name)
    local value = _G and _G[name]
    if type(value) ~= "table" or type(value.GetObjectType) ~= "function" then
        return nil
    end
    return value
end

--- What `unit`'s buttons should hang off, or nil if this UI has nothing.
--
-- The health bar in preference to the frame itself. A unit frame's rect runs
-- well past the art it draws, and PlayerFrame and PartyMemberFrame do not
-- overhang by the same amount -- anchored to the frames, one offset put the
-- player's icons snug against the portrait and a party member's a whole
-- frame-width out into empty screen. The health bar's right edge is where a
-- unit frame visibly ends, for both, so one offset means one thing.
--
-- Looked up through _G on every call rather than cached at load: these
-- frames are built by Blizzard's own UI, which may not have run when this
-- file loads, and an addon may swap one out later.
function Anchors.For(unit)
    local name = FRAME_NAMES[unit]
    if not name then
        return nil
    end

    -- The frame decides whether this unit has a usable anchor at all; the
    -- health bar only refines where on it. A name holding something that is
    -- not a frame is absent whatever else shares its prefix.
    local frame = widgetNamed(name)
    if not frame then
        return nil
    end

    return widgetNamed(name .. "HealthBar") or frame
end

--- Whether attaching is possible at all: the player's own frame has to be
-- there, since that is the one row every group has.
--
-- Deliberately not "are all five there" -- party2's frame is missing in a
-- two-person group as a matter of course, and that says nothing about
-- whether this UI has party frames.
function Anchors.Available()
    return Anchors.For("player") ~= nil
end
