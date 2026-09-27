local addonName, ns = ...

-- What the addon knows about an item without asking the server: its name,
-- quality, kind and slot, built in from the world database. The server is
-- asked too, but will not always say -- WoW Forever answered not one of
-- thousands of requests -- so every row, search and link works from this,
-- and the client's own copy takes over whenever it has one. The icon comes
-- from the client, which has it without the server.

local ItemData = {}
ns.ItemData = ItemData

-- The game's names for the kinds of item, by class and subclass, for a
-- client that cannot name them itself. Classes and subclasses the
-- instances never list are left out.
local CLASS_NAMES = {
    [0] = "Consumable", [1] = "Container", [2] = "Weapon", [4] = "Armor", [5] = "Reagent",
    [6] = "Projectile", [7] = "Trade Goods", [9] = "Recipe", [11] = "Quiver", [12] = "Quest",
    [13] = "Key", [15] = "Miscellaneous",
}
local SUBCLASS_NAMES = {
    [0] = { [0] = "Consumable" },
    [1] = { [0] = "Bag", [1] = "Soul Bag", [2] = "Herb Bag", [3] = "Enchanting Bag" },
    [2] = {
        [0] = "One-Handed Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns",
        [4] = "One-Handed Maces", [5] = "Two-Handed Maces", [6] = "Polearms",
        [7] = "One-Handed Swords", [8] = "Two-Handed Swords", [10] = "Staves",
        [13] = "Fist Weapons", [14] = "Miscellaneous", [15] = "Daggers", [16] = "Thrown",
        [17] = "Spears", [18] = "Crossbows", [19] = "Wands", [20] = "Fishing Poles",
    },
    [4] = {
        [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate",
        [6] = "Shields", [7] = "Librams", [8] = "Idols", [9] = "Totems",
    },
    [5] = { [0] = "Reagent" },
    [6] = { [2] = "Arrow", [3] = "Bullet" },
    [7] = { [0] = "Trade Goods", [1] = "Parts", [2] = "Explosives", [3] = "Devices" },
    [9] = {
        [0] = "Book", [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering",
        [4] = "Blacksmithing", [5] = "Cooking", [6] = "Alchemy", [7] = "First Aid",
        [8] = "Enchanting", [9] = "Fishing",
    },
    [11] = { [2] = "Quiver", [3] = "Ammo Pouch" },
    [12] = { [0] = "Quest" },
    [13] = { [0] = "Key", [1] = "Lockpick" },
    [15] = { [0] = "Junk", [1] = "Reagent", [2] = "Pet", [3] = "Holiday", [4] = "Other", [5] = "Mount" },
}
-- Slot numbers to the game's slot names, which Format.TypeLabel reads.
local SLOTS = {
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST",
    "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND",
    "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_SHIELD", "INVTYPE_RANGED",
    "INVTYPE_CLOAK", "INVTYPE_2HWEAPON", "INVTYPE_BAG", "INVTYPE_TABARD", "INVTYPE_ROBE",
    "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "INVTYPE_AMMO",
    "INVTYPE_THROWN", "INVTYPE_RANGEDRIGHT", "INVTYPE_QUIVER", "INVTYPE_RELIC",
}

-- The client's name for a kind, in its own language, if it can give one.
local function clientName(lookup)
    local name = ns.Guarded(lookup)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function className(class)
    local get = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
    local own = get and clientName(function() return get(class) end)
    return own or CLASS_NAMES[class]
end

local function subclassName(class, subclass)
    local get = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    local own = get and clientName(function() return get(class, subclass) end)
    return own or (SUBCLASS_NAMES[class] or {})[subclass]
end

--- The game's name for an item class (9 recipes, 13 keys, ...).
function ItemData.ClassName(class)
    return className(class)
end

--- What the addon knows about an item, in the shape LootRow.ItemInfo gives,
-- with `builtIn` set; nil for an item it does not know.
function ItemData.Get(itemID)
    -- Recorded in WoW Forever: the real item, over a vanilla one of the same id.
    local recorded = ns.Recordings and ns.Recordings.Item(itemID)
    if recorded then
        local name, quality = recorded[1], recorded[2] or 1
        return {
            name = name,
            quality = quality,
            link = "|cff" .. ns.Format.QualityHex(quality) .. "|Hitem:" .. itemID .. "|h[" .. name .. "]|h|r",
            itemType = recorded[3],
            itemSubType = recorded[4],
            equipLoc = recorded[5] or "",
            builtIn = true,
        }
    end
    local entry = ns.builtInItems[itemID]
    if not entry then
        return nil
    end
    local name, quality, class, subclass, slot = entry[1], entry[2], entry[3], entry[4], entry[5]
    return {
        name = name,
        quality = quality,
        link = "|cff" .. ns.Format.QualityHex(quality) .. "|Hitem:" .. itemID .. "|h[" .. name .. "]|h|r",
        itemType = className(class),
        itemSubType = subclassName(class, subclass),
        equipLoc = SLOTS[slot] or "",
        builtIn = true,
    }
end
