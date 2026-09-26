local addonName, ns = ...

-- What has been recorded in WoW Forever: the player's own recordings and any
-- baked into the release, merged, and laid onto BossLoot's instances.

local Recordings = {}
ns.Recordings = Recordings

--- Something was recorded: bring the lists up to date.
function Recordings.Changed()
    if ns.Index and ns.Index.Build then
        ns.Index.Build()
    end
end
