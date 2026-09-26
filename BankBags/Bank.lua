local addonName, ns = ...

-- Keeping a copy of the bank. The server sends a bank's contents only while
-- a banker is open, so BankBags saves them then -- when it opens, and after
-- every change while it is open -- and the window shows the copy anywhere.
-- Saved variables are per account, so each character's copy is kept, under
-- "<realm>-<name>".

local Bank = {}
ns.Bank = Bank

ns.AddDefaults({
    characters = {},
})

-- The containers, numbered as the game's own bank frame numbers them: the
-- main bank, then the bank bags after every bag the character wears (a
-- reagent bag too, on clients that have one). Not from Enum.BagIndex: on a
-- client whose enum is laid out for another, it would skip a bank bag.
local MAIN = BANK_CONTAINER or -1
local FIRST_BAG = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
local LAST_BAG = FIRST_BAG + (NUM_BANKBAGSLOTS or 6) - 1
local SAVE_DELAY = 0.3 -- seconds of changes gathered into one save

local atBank = false

--- The key a character's copy is kept under: "<realm>-<name>".
function Bank.CharacterKey()
    local name = UnitName and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or ""
    return realm .. "-" .. name
end

local function numSlots(container)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(container) or 0
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(container) or 0
    end
    return 0
end

-- What a slot holds: its link, count, icon and quality; nil when empty.
local function slotItem(container, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(container, slot)
        if info and info.hyperlink then
            return { link = info.hyperlink, count = info.stackCount or 1, icon = info.iconFileID, quality = info.quality }
        end
        return nil
    end
    if GetContainerItemInfo then
        local icon, count, _, quality, _, _, link = GetContainerItemInfo(container, slot)
        if link then
            return { link = link, count = count or 1, icon = icon, quality = quality }
        end
    end
    return nil
end

-- A bank bag's own item, from the inventory slot it sits in: its link and icon.
local function bagItem(container)
    local slot
    if C_Container and C_Container.ContainerIDToInventoryID then
        slot = C_Container.ContainerIDToInventoryID(container)
    elseif ContainerIDToInventoryID then
        slot = ContainerIDToInventoryID(container)
    end
    if not slot then
        return nil
    end
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
    return link, icon
end

local function readContainer(container, name)
    local size = numSlots(container)
    if size <= 0 then
        return nil
    end
    local copy = { id = container, name = name, size = size, slots = {} }
    for slot = 1, size do
        copy.slots[slot] = slotItem(container, slot)
    end
    return copy
end

-- On a client with bank tabs, each tab is a container like a bank bag, and
-- its "bag" is a placeholder item, "Character Bank Tab Bag (DNT)": DNT, do not
-- translate, is Blizzard's mark on a name no player was meant to see. A tab's
-- real name and icon come from C_Bank, where the client has it: tab ID ->
-- { name, icon }.
local function tabData()
    local tabs = {}
    if not (C_Bank and C_Bank.FetchPurchasedBankTabData) then
        return tabs
    end
    local character = (Enum and Enum.BankType and Enum.BankType.Character) or 0
    local ok, list = pcall(C_Bank.FetchPurchasedBankTabData, character)
    if not (ok and type(list) == "table") then
        return tabs
    end
    for _, tab in ipairs(list) do
        if type(tab) == "table" and tab.ID then
            tabs[tab.ID] = tab
        end
    end
    return tabs
end

local function isPlaceholder(name)
    return name ~= nil and name:find("(DNT)", 1, true) ~= nil
end

local function isEmpty(container)
    for slot = 1, container.size do
        if container.slots[slot] then
            return false
        end
    end
    return true
end

--- The bank as it is: the main bank, then each bank bag or tab that has slots.
function Bank.Read()
    local tabs = tabData()
    local containers = {}
    local tabCount = 0
    for container = FIRST_BAG, LAST_BAG do
        local link, icon = bagItem(container)
        local name = link and link:match("%[(.-)%]")
        local copy = readContainer(container, name or "Bag")
        if copy then
            copy.link, copy.icon = link, icon
            local tab = tabs[container]
            if tab or isPlaceholder(name) then
                -- Named as the game's bank names it: what the player called the
                -- tab, or its number. The placeholder item has nothing to say.
                tabCount = tabCount + 1
                copy.name = (tab and type(tab.name) == "string" and tab.name ~= "" and tab.name)
                    or ("Tab " .. tabCount)
                copy.icon = (tab and tab.icon) or icon
                copy.link = nil
            end
            table.insert(containers, copy)
        end
    end

    -- A client with tabs still reports the old bank, every slot of it empty:
    -- shown, it is rows of slots nothing can go in. Kept if anything is there.
    local main = readContainer(MAIN, "Bank")
    if main and not (tabCount > 0 and isEmpty(main)) then
        table.insert(containers, 1, main)
    end
    return containers
end

--- Save the bank, if it is open: anywhere else it reads as empty.
function Bank.Save()
    if not (atBank and ns.db) then
        return false
    end
    local key = Bank.CharacterKey()
    local character = ns.db.characters[key] or {}
    character.name = UnitName and UnitName("player") or character.name
    character.realm = GetRealmName and GetRealmName() or character.realm
    if UnitClass then
        local _, class = UnitClass("player")
        character.class = class or character.class
    end
    character.containers = Bank.Read()
    character.saved = time and time() or 0
    ns.db.characters[key] = character
    if ns.Window and ns.Window.Refresh then
        ns.Window.Refresh()
    end
    return true
end

-- Changes at the bank come in bursts (a bag moved fires several): one save,
-- a moment after the last.
local savePending = false
local function saveSoon()
    if savePending then
        return
    end
    if not (C_Timer and C_Timer.After) then
        Bank.Save()
        return
    end
    savePending = true
    C_Timer.After(SAVE_DELAY, function()
        savePending = false
        Bank.Save()
    end)
end

--- The saved characters: the one played first, then the rest by key.
function Bank.Characters()
    local own = Bank.CharacterKey()
    local keys = {}
    for key in pairs(ns.db.characters) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        if (a == own) ~= (b == own) then
            return a == own
        end
        return a < b
    end)
    return keys
end

function Bank.Get(key)
    return ns.db.characters[key]
end

--- Forget the saved characters with this name, or this "<realm>-<name>",
-- ignoring case. Returns how many.
function Bank.Forget(name)
    local wanted = name:lower()
    local forgotten = 0
    for key, character in pairs(ns.db.characters) do
        if key:lower() == wanted or (character.name and character.name:lower() == wanted) then
            ns.db.characters[key] = nil
            forgotten = forgotten + 1
        end
    end
    return forgotten
end

ns.RegisterCommand("forget", "Forget a character's saved bank: /bb forget <name>", function(rest)
    if rest == "" then
        ns.Print("Whose bank? /bb forget <name>")
        return
    end
    if Bank.Forget(rest) == 0 then
        ns.Print("No saved bank for " .. rest .. ".")
    else
        ns.Print("Forgot " .. rest .. "'s bank.")
    end
    if ns.Window and ns.Window.Refresh then
        ns.Window.Refresh()
    end
end)

local function isBankContainer(container)
    return container == MAIN or (container and container >= FIRST_BAG and container <= LAST_BAG)
end

local handlers = {
    BANKFRAME_OPENED = function()
        atBank = true
        Bank.Save()
    end,
    BANKFRAME_CLOSED = function()
        -- A change just made is saved now, while the bank can still be read.
        if savePending then
            Bank.Save()
        end
        atBank = false
    end,
    PLAYERBANKSLOTS_CHANGED = function() saveSoon() end,
    PLAYERBANKBAGSLOTS_CHANGED = function() saveSoon() end,
    BAG_UPDATE = function(container)
        if atBank and isBankContainer(container) then
            saveSoon()
        end
    end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        handler(...)
    end
end)
