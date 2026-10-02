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

-- The settings page, told of every change however it was made, so the list
-- it shows never disagrees with what a command has just done.
local function changed()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

--- Never sell this item. Says so in chat.
function Keep.Add(itemID, name)
    ns.db.keep[itemID] = name
    ns.Print(string.format("Keeping %s: it will not be sold.", shown(name)))
    changed()
end

--- Sell this item again. Says so in chat. /av unkeep and the settings
-- page's buttons both come through here.
function Keep.Remove(itemID)
    local kept = ns.db.keep[itemID]
    if kept == nil then
        return
    end
    ns.db.keep[itemID] = nil
    ns.Print(string.format("No longer keeping %s.", shown(kept)))
    changed()
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

    Keep.Add(id, name)
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

    Keep.Remove(id)
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
