-- Test data in the shape of the generated Data files: a few nodes, and
-- spawns placed around the probe's spot in Westfall (-10603.8, 1154.0).
local _, ns = ...

ns.AddNodes({
    [1731] = { kind = "ore", name = "Copper Vein", skill = 1, item = 2770 },
    [3764] = { kind = "ore", name = "Tin Vein", skill = 65, item = 2771 },
    [1617] = { kind = "herb", name = "Silverleaf", skill = 1, item = 765 },
    [1618] = { kind = "herb", name = "Peacebloom", skill = 1, item = 2447 },
    [1619] = { kind = "herb", name = "Earthroot", skill = 15, item = 2449 },
    [2045] = { kind = "herb", name = "Stranglekelp", skill = 85, item = 3820 },
    [180582] = { kind = "pool", name = "Oily Blackmouth School" },
    [2843] = { kind = "chest", name = "Battered Chest" },
})

ns.AddSpawns(0, {
    1731, -10603.8, 1154.0,  -- A: under the player
    1731, -10000.0, 1000.0,  -- B: the map's top-right corner, 623 yards off
    3764, -10610.0, 1160.0,  -- C: 8.6 yards off
    1617, -9000.0, 500.0,    -- D: off map 1436
    180582, -10620.0, 1170.0, -- E: a pool 22.8 yards off
    2843, -10700.0, 1300.0,  -- F: a chest 175 yards off
    99999, -10600.0, 1150.0, -- an object the catalog does not know
})

ns.AddSpawns(1, {
    1618, 100.0, 200.0,
})

-- C, the Tin Vein, confirmed by a baked recording.
ns.AddConfirmed({
    "0:3764:-10610.0:1160.0",
})
