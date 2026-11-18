local addonName, ns = ...

-- Items never sold, by item ID, with a name to show for each. One list for
-- every character: a grey worth keeping is worth keeping on any of them.

local Keep = {}
ns.Keep = Keep

ns.AddDefaults({
    keep = {},
})

local shown = ns.ShownItem

function Keep.All()
    return ns.db.keep
end

function Keep.Has(itemID)
    return ns.db.keep[itemID] ~= nil
end

-- The settings page, told of every change however it was made, so the list
-- it shows never disagrees with what a command has just done.
local function changed()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

--- Take an item off the list without a word. True when it was on it. For
-- the junk list, which says in its own line that it moved the item.
function Keep.Drop(itemID)
    if ns.db.keep[itemID] == nil then
        return false
    end
    ns.db.keep[itemID] = nil
    return true
end

--- Never sell this item. Says so in chat. An item is on one list at most,
-- so a listed one comes off the junk list.
function Keep.Add(itemID, name)
    ns.db.keep[itemID] = name
    local moved = ns.Junk and ns.Junk.Drop(itemID)
    ns.Print(string.format("Keeping %s: it will not be sold.%s", shown(name),
        moved and " It is off the junk list." or ""))
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
    local id, name = ns.ReadItem(rest)
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
    local id, name = ns.ReadItem(rest)
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

--- Print one list, by name, under its heading; or that it is empty.
local function printList(list, heading, empty)
    local names = {}
    for _, name in pairs(list) do
        names[#names + 1] = name
    end

    if #names == 0 then
        ns.Print(empty)
        return
    end

    table.sort(names)
    ns.Print(heading)
    for _, name in ipairs(names) do
        ns.Print("  " .. shown(name))
    end
end

ns.RegisterCommand("list", "show the items never sold and always sold", function()
    printList(ns.db.keep, "Never sold:", "Nothing is on the keep list.")
    printList(ns.db.junk or {}, "Always sold:", "Nothing is on the junk list.")
end)
