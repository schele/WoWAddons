local helpers = require("helpers")

describe("the instance list", function()
    it("lists an instance kind in level order", function()
        local ns = helpers.loggedIn()
        local names = {}
        for _, instance in ipairs(ns.Index.Instances("dungeon")) do table.insert(names, instance.name) end
        assertEqual("Test Depths,Low Spire", table.concat(names, ","))
    end)

    it("keeps raids and dungeons apart", function()
        local ns = helpers.loggedIn()
        assertEqual(1, #ns.Index.Instances("raid"))
    end)

    it("leaves out an instance the player hid", function()
        local ns = helpers.loggedIn()
        ns.db.hidden.Depths = true
        assertEqual(1, #ns.Index.Instances("dungeon"))
        assertTrue(ns.Index.IsHidden("Depths"))
    end)
end)

describe("where an item drops", function()
    it("finds every boss and notable list that has it", function()
        local ns = helpers.loggedIn()
        local sources = ns.Index.Sources(1001)
        assertEqual(2, #sources)
        assertEqual("Depths", sources[1].instance)
        assertEqual(1, sources[1].boss)
        assertEqual("Core", sources[2].instance)
    end)

    it("finds notable drops by which list they are on", function()
        local ns = helpers.loggedIn()
        assertEqual("trash", ns.Index.Sources(2001)[1].boss)
        assertEqual("objects", ns.Index.Sources(3002)[1].boss)
    end)

    it("lists every item in an instance once, for loading", function()
        local ns = helpers.loggedIn()
        assertEqual(5, #ns.Index.ItemIDs("Depths"))
    end)
end)

describe("search", function()
    local function nameOf(names)
        return function(id) return names[id] end
    end

    it("matches instance names, ignoring case", function()
        local ns = helpers.loggedIn()
        local result = ns.Index.Search("depths", nameOf({}))
        assertEqual("Depths", result.instances[1].key)
    end)

    it("matches item names the client knows", function()
        local ns = helpers.loggedIn()
        local result = ns.Index.Search("hand", nameOf({ [1002] = "Hand of Justice" }))
        assertEqual(1002, result.items[1].id)
        assertEqual("Depths", result.items[1].sources[1].instance)
    end)

    it("needs two letters before it searches at all", function()
        local ns = helpers.loggedIn()
        local result = ns.Index.Search("d", nameOf({}))
        assertEqual(0, #result.instances)
    end)

    it("treats pattern characters as plain text", function()
        local ns = helpers.loggedIn()
        local result = ns.Index.Search("(%[-", nameOf({ [1001] = "Odd (%[- Name" }))
        assertEqual(1001, result.items[1].id)
    end)

    it("leaves out items that only drop in hidden instances", function()
        local ns = helpers.loggedIn()
        ns.db.hidden.Depths = true
        local result = ns.Index.Search("justice", nameOf({ [1002] = "Hand of Justice" }))
        assertEqual(0, #result.items)
    end)
end)
