local addonName, ns = ...

-- Items always sold, by item ID, with a name to show for each: the keep
-- list's opposite. The player picks them, typically white items outgrown,
-- and they go with the greys at every merchant. One list for every
-- character, as the keep list is.

local Junk = {}
ns.Junk = Junk

ns.AddDefaults({
    junk = {},
})

local shown = ns.ShownItem

function Junk.All()
    return ns.db.junk
end

function Junk.Has(itemID)
    return ns.db.junk[itemID] ~= nil
end

local function changed()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

--- Take an item off the list without a word. True when it was on it. For
-- the keep list, which says in its own line that it moved the item.
function Junk.Drop(itemID)
    if ns.db.junk[itemID] == nil then
        return false
    end
    ns.db.junk[itemID] = nil
    return true
end

--- Sell this item at every merchant. Says so in chat. An item is on one
-- list at most, so a kept one comes off the keep list: the latest choice
-- wins. /av junk and the settings page's bag icons both come through here.
function Junk.Add(itemID, name)
    ns.db.junk[itemID] = name
    local moved = ns.Keep.Drop(itemID)
    ns.Print(string.format("Selling %s at every merchant.%s", shown(name),
        moved and " It is off the keep list." or ""))
    changed()
end

--- Stop selling this item. Says so in chat. /av unjunk and the settings
-- page's buttons both come through here.
function Junk.Remove(itemID)
    local listed = ns.db.junk[itemID]
    if listed == nil then
        return
    end
    ns.db.junk[itemID] = nil
    ns.Print(string.format("No longer selling %s.", shown(listed)))
    changed()
end

ns.RegisterCommand("junk", "always sell an item: Shift-click it after the command", function(rest)
    local id, name = ns.ReadItem(rest)
    if not id then
        ns.ShowHelp()
        return
    end

    if Junk.Has(id) then
        ns.Print(string.format("%s is already on the junk list.", shown(ns.db.junk[id])))
        return
    end

    Junk.Add(id, name)
end)

ns.RegisterCommand("unjunk", "stop selling an item: Shift-click it after the command", function(rest)
    local id, name = ns.ReadItem(rest)
    if not id then
        ns.ShowHelp()
        return
    end

    if not Junk.Has(id) then
        ns.Print(string.format("%s is not on the junk list.", shown(name)))
        return
    end

    Junk.Remove(id)
end)
