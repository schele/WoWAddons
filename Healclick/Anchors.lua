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
-- Blizzard has moved these, and PlayerFrame is the only one that stayed put.
-- PartyMemberFrame1 was the global through Classic and Wrath; the 10.x UI
-- rework replaced it with PartyFrame.MemberFrame1, and raid-style party
-- frames use a compact frame in place of either. This client is a 1.60 beta
-- on a modern base -- the same base that took GetSpellInfo and
-- GetSpellBookItemName away from this addon -- so which of the three is here
-- is asked rather than assumed. First to answer wins.
--
-- Order matters only in that every candidate names the same thing; a client
-- carrying the old global as an alias for the new frame can use either.
local FRAME_PATHS = {
    player = { "PlayerFrame" },
    party1 = { "PartyMemberFrame1", "PartyFrame.MemberFrame1", "CompactPartyFrameMember1" },
    party2 = { "PartyMemberFrame2", "PartyFrame.MemberFrame2", "CompactPartyFrameMember2" },
    party3 = { "PartyMemberFrame3", "PartyFrame.MemberFrame3", "CompactPartyFrameMember3" },
    party4 = { "PartyMemberFrame4", "PartyFrame.MemberFrame4", "CompactPartyFrameMember4" },
}

--- The widget at this global name, or nil if there is nothing usable there.
--
-- A name that holds something which is not a widget -- a table another addon
-- has parked there -- has to read as absent rather than be anchored to.
-- GetObjectType is the cheapest thing only a real widget has.
local function isWidget(value)
    return type(value) == "table" and type(value.GetObjectType) == "function"
end

--- The widget at a global path, or nil if there is nothing usable there.
--
-- Dotted, because the modern frames live inside a container rather than at a
-- global of their own -- "PartyFrame.MemberFrame1" is one lookup then one
-- field. A path holding something which is not a widget, such as a table
-- another addon has parked there, reads as absent rather than being anchored
-- to; GetObjectType is the cheapest thing only a real widget has.
local function widgetAt(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end

    return isWidget(value) and value or nil
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
--- The unit frame itself, and the path it turned up at. nil when this UI has
-- no frame for `unit` -- which is an ordinary answer, not a failure.
function Anchors.Frame(unit)
    local paths = FRAME_PATHS[unit]
    if not paths then
        return nil
    end

    for _, path in ipairs(paths) do
        local frame = widgetAt(path)
        if frame then
            return frame, path
        end
    end

    return nil
end

function Anchors.For(unit)
    -- The frame decides whether this unit has a usable anchor at all; the
    -- health bar below only refines where on it.
    local frame, path = Anchors.Frame(unit)
    if not frame then
        return nil
    end

    -- Modern frames keep the health bar as a field; the pre-10.x ones
    -- published it as a global named after the frame. Try both, and settle
    -- for the frame itself, which is a perfectly good anchor -- on this
    -- client it is what the player frame falls back to, and the icons sit
    -- correctly against it.
    if isWidget(frame.healthBar) then
        return frame.healthBar
    end

    return widgetAt(path .. "HealthBar") or frame
end

--- Whether attaching is possible at all: the player's own frame has to be
-- there, since that is the one row every group has.
--
-- Deliberately not "are all five there" -- party2's frame is missing in a
-- two-person group as a matter of course, and that says nothing about
-- whether this UI has party frames.
function Anchors.Available()
    return Anchors.Frame("player") ~= nil
end
