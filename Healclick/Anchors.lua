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

--- The Blizzard frame `unit`'s buttons should hang off, or nil.
--
-- Looked up through _G on every call rather than cached at load: these
-- frames are created by Blizzard's own UI, which may not have run yet when
-- this file loads, and an addon may swap one out later.
function Anchors.For(unit)
    local name = FRAME_NAMES[unit]
    if not name then
        return nil
    end

    -- A frame that exists but is not a frame -- a name some other addon has
    -- taken for a table of its own -- must read as absent, not be anchored
    -- to. GetObjectType is the cheapest thing only a real widget has.
    local frame = _G and _G[name]
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then
        return nil
    end

    return frame
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
