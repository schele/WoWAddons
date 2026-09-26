-- The generated files, loaded for real: they must load, hold sane values, and
-- every one must be listed in the .toc.
local helpers = require("helpers")

local function dataFiles()
    local files = {}
    for line in io.lines("BossLoot.toc") do
        local file = line:match("^Data\\(.+%.lua)%s*$")
        if file then table.insert(files, "Data/" .. file) end
    end
    return files
end

describe("the generated data", function()
    local files = dataFiles()
    local all = { "BossLoot.lua" }
    for _, file in ipairs(files) do table.insert(all, file) end
    local ns = helpers.loadAddon(all)

    it("has at least one instance listed in the .toc", function()
        assertTrue(#files > 0)
        assertEqual(#files, #ns.instances)
    end)

    it("gives every instance a key, name, kind and level range", function()
        for _, instance in ipairs(ns.instances) do
            assertTrue(type(instance.key) == "string" and instance.key ~= "", "key")
            assertTrue(instance.kind == "dungeon" or instance.kind == "raid", instance.key .. " kind")
            assertTrue(instance.levels[1] <= instance.levels[2], instance.key .. " levels")
            assertTrue(#instance.bosses > 0, instance.key .. " has bosses")
        end
    end)

    it("holds only item ids and chances between 0 and 100", function()
        for _, instance in ipairs(ns.instances) do
            local lists = {}
            for _, boss in ipairs(instance.bosses) do table.insert(lists, boss.loot) end
            table.insert(lists, instance.notable.trash)
            table.insert(lists, instance.notable.objects)
            for _, list in ipairs(lists) do
                for _, entry in ipairs(list) do
                    assertTrue(math.type(entry[1]) == "integer" and entry[1] > 0, instance.key .. " item id")
                    assertTrue(entry[2] > 0 and entry[2] <= 100, instance.key .. " chance " .. tostring(entry[2]))
                end
            end
        end
    end)

    it("lists random encounters boss by boss, since only one of them comes each run", function()
        -- Merged, Grizzle's guaranteed plans read as a 100% drop from the
        -- Ring of Law, which it is not.
        local names = {}
        for _, instance in ipairs(ns.instances) do
            for _, boss in ipairs(instance.bosses) do names[boss.name] = true end
        end
        assertNil(names["Ring of Law"], "Ring of Law merged")
        assertNil(names["Edge of Madness"], "Edge of Madness merged")
        assertTrue(names["Ring of Law: Grizzle"], "Grizzle on his own")
        assertTrue(names["Edge of Madness: Gri'lek"], "Gri'lek on his own")
    end)

    it("has no two instances with the same key", function()
        local seen = {}
        for _, instance in ipairs(ns.instances) do
            assertNil(seen[instance.key], "duplicate " .. instance.key)
            seen[instance.key] = true
        end
    end)
end)
