local addonName, ns = ...

-- Items never sold, by item ID, with a name to show for each. One list for
-- every character: a grey worth keeping is worth keeping on any of them.

local Keep = {}
ns.Keep = Keep

ns.AddDefaults({
    keep = {},
})

function Keep.All()
    return ns.db.keep
end

function Keep.Has(itemID)
    return ns.db.keep[itemID] ~= nil
end

local function itemName(itemID)
    return ns.Guarded(function()
        if C_Item and C_Item.GetItemNameByID then
            local name = C_Item.GetItemNameByID(itemID)
            if type(name) == "string" then
                return name
            end
        end
        local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local name = getItemInfo and getItemInfo(itemID)
        return type(name) == "string" and name or nil
    end, nil)
end

--- An item from what was typed: a Shift-clicked link, or a bare number.
-- Its ID and its name, or nil for anything else.
local function readItem(text)
    local id, name = text:match("|Hitem:(%d+)[^|]*|h%[(.-)%]|h")
    if id then
        return tonumber(id), name
    end

    id = text:match("^(%d+)$")
    if id then
        id = tonumber(id)
        return id, itemName(id) or ("item " .. id)
    end

    return nil
end

local function shown(name)
    return "[" .. name .. "]"
end

ns.RegisterCommand("keep", "never sell an item: Shift-click it after the command", function(rest)
    local id, name = readItem(rest)
    if not id then
        ns.ShowHelp()
        return
    end

    if Keep.Has(id) then
        ns.Print(string.format("%s is already on the keep list.", shown(ns.db.keep[id])))
        return
    end

    ns.db.keep[id] = name
    ns.Print(string.format("Keeping %s: it will not be sold.", shown(name)))
end)

ns.RegisterCommand("unkeep", "sell a kept item again: Shift-click it after the command", function(rest)
    local id, name = readItem(rest)
    if not id then
        ns.ShowHelp()
        return
    end

    if not Keep.Has(id) then
        ns.Print(string.format("%s is not on the keep list.", shown(name)))
        return
    end

    local kept = ns.db.keep[id]
    ns.db.keep[id] = nil
    ns.Print(string.format("No longer keeping %s.", shown(kept)))
end)

ns.RegisterCommand("list", "show the items that are never sold", function()
    local names = {}
    for _, name in pairs(ns.db.keep) do
        names[#names + 1] = name
    end

    if #names == 0 then
        ns.Print("Nothing is on the keep list.")
        return
    end

    table.sort(names)
    ns.Print("Never sold:")
    for _, name in ipairs(names) do
        ns.Print("  " .. shown(name))
    end
end)
