-- Test data in the shape of the generated Data files. The test Westfall
-- (1436) runs from world (-10000, 2000) at its top left to (-11000, 1000);
-- the player stands at (-10603.8, 1154.0).
local _, ns = ...

ns.AddRares({
    [462] = { "Vultros", 26, 26, false },
    [520] = { "Brack", 19, 19, false },
    [1] = { "Elite Rare", 40, 42, true },
    [99] = { "Morgaine the Sly", 10, 10, false },
    [5] = { "Kalimdor Rare", 30, 30, false },
    [61] = { "Never Spawned", 11, 11, false },
})

ns.AddSpawns(0, {
    462, -10500, 1500,  -- the middle of Westfall
    520, -10610, 1160,  -- 8.6 yards from the player
    1, -10900, 1100,
    99, -9000, 500,     -- off Westfall
})

ns.AddSpawns(1, {
    5, 100, 200,
})
