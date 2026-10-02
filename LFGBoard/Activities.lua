local addonName, ns = ...

-- The dungeons and raids players post about: each one's name, kind, level
-- range (as BossLoot has them) and the words players type for it. Data and
-- matching only, no frames.

local Activities = {}
ns.Activities = Activities

Activities.LIST = {
    { key = "rfc", name = "Ragefire Chasm", kind = "dungeon", levels = { 13, 18 }, words = { "rfc", "ragefire" } },
    { key = "wc", name = "Wailing Caverns", kind = "dungeon", levels = { 17, 24 }, words = { "wc", "wailing" } },
    { key = "dm", name = "The Deadmines", kind = "dungeon", levels = { 17, 26 }, words = { "dm", "vc", "deadmines" } },
    { key = "sfk", name = "Shadowfang Keep", kind = "dungeon", levels = { 22, 30 }, words = { "sfk", "shadowfang" } },
    { key = "bfd", name = "Blackfathom Deeps", kind = "dungeon", levels = { 24, 32 }, words = { "bfd", "blackfathom" } },
    { key = "stocks", name = "The Stockade", kind = "dungeon", levels = { 24, 31 }, words = { "stocks", "stockade", "stockades" } },
    { key = "gnomer", name = "Gnomeregan", kind = "dungeon", levels = { 29, 38 }, words = { "gnomer", "gnomeregan" } },
    { key = "rfk", name = "Razorfen Kraul", kind = "dungeon", levels = { 29, 38 }, words = { "rfk", "kraul" } },
    { key = "sm", name = "Scarlet Monastery", kind = "dungeon", levels = { 26, 45 },
        words = { "sm", "scarlet", "cath", "cathedral", "armory", "armoury", "library", "lib" } },
    { key = "rfd", name = "Razorfen Downs", kind = "dungeon", levels = { 37, 46 }, words = { "rfd", "downs" } },
    { key = "ulda", name = "Uldaman", kind = "dungeon", levels = { 41, 51 }, words = { "ulda", "uldaman" } },
    { key = "zf", name = "Zul'Farrak", kind = "dungeon", levels = { 44, 54 }, words = { "zf", "zulfarrak" } },
    { key = "mara", name = "Maraudon", kind = "dungeon", levels = { 46, 55 }, words = { "mara", "maraudon" } },
    { key = "st", name = "The Temple of Atal'Hakkar", kind = "dungeon", levels = { 50, 56 }, words = { "st", "sunken" } },
    { key = "brd", name = "Blackrock Depths", kind = "dungeon", levels = { 52, 60 }, words = { "brd" } },
    { key = "brs", name = "Blackrock Spire", kind = "dungeon", levels = { 55, 60 }, words = { "lbrs", "ubrs", "brs" } },
    { key = "diremaul", name = "Dire Maul", kind = "dungeon", levels = { 55, 60 },
        words = { "dme", "dmw", "dmn", "dm east", "dm west", "dm north", "diremaul" } },
    { key = "scholo", name = "Scholomance", kind = "dungeon", levels = { 58, 60 }, words = { "scholo", "scholomance" } },
    { key = "strat", name = "Stratholme", kind = "dungeon", levels = { 58, 60 }, words = { "strat", "strath", "stratholme" } },
    { key = "ony", name = "Onyxia's Lair", kind = "raid", levels = { 60, 60 }, words = { "ony", "onyxia" } },
    { key = "mc", name = "Molten Core", kind = "raid", levels = { 60, 60 }, words = { "mc" } },
    { key = "zg", name = "Zul'Gurub", kind = "raid", levels = { 60, 60 }, words = { "zg" } },
    { key = "bwl", name = "Blackwing Lair", kind = "raid", levels = { 60, 60 }, words = { "bwl" } },
    { key = "aq20", name = "Ruins of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, words = { "aq20" } },
    { key = "aq40", name = "Temple of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, words = { "aq40" } },
    { key = "naxx", name = "Naxxramas", kind = "raid", levels = { 60, 60 }, words = { "naxx" } },
}

--- Text as words for matching: lower case, apostrophes dropped (so
-- "Zul'Farrak" is "zulfarrak"), anything else that is not a letter or a
-- digit turned to a space, and a space at each end so a word can be found
-- whole.
function Activities.Normalize(text)
    local words = tostring(text):lower():gsub("'", ""):gsub("[^%w]+", " ")
    words = words:match("^%s*(.-)%s*$")
    return " " .. words .. " "
end

-- Every phrase that names an activity, its own name's words included,
-- longest first: "dm east" has to be found before "dm".
local phrases

local function allPhrases()
    if phrases then
        return phrases
    end
    phrases = {}
    for _, activity in ipairs(Activities.LIST) do
        local name = Activities.Normalize(activity.name):gsub("^ the ", " ")
        table.insert(phrases, { text = name, activity = activity })
        for _, word in ipairs(activity.words) do
            table.insert(phrases, { text = " " .. word .. " ", activity = activity })
        end
    end
    table.sort(phrases, function(a, b)
        return #a.text > #b.text
    end)
    return phrases
end

--- The activity a text names, or nil.
function Activities.Find(text)
    local words = Activities.Normalize(text)
    for _, phrase in ipairs(allPhrases()) do
        if words:find(phrase.text, 1, true) then
            return phrase.activity
        end
    end
    return nil
end

function Activities.ByKey(key)
    for _, activity in ipairs(Activities.LIST) do
        if activity.key == key then
            return activity
        end
    end
    return nil
end

function Activities.Display(activity)
    return (activity.name:gsub("^The ", ""))
end

--- Whether `level` is near an activity: inside its level range widened by
-- 3 at each end. A level that cannot be read hides nothing.
function Activities.Near(activity, level)
    if type(level) ~= "number" then
        return true
    end
    return level >= activity.levels[1] - 3 and level <= activity.levels[2] + 3
end
