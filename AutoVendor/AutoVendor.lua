local addonName, ns = ...

ns.PREFIX = "|cff66ccffAutoVendor|r"

-- Defaults are contributed by each file at load time, so every piece of
-- saved state lives next to the code that reads it.
local defaults = {
    version = 1,
}

--- Merge a defaults table into a saved one without clobbering stored values.
-- Recursive, so state added in a later version is filled in on upgrade.
local function applyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises.
-- This client hands addon code some values as secrets: the call succeeds,
-- but comparing or testing the result raises. The branch has to happen
-- inside `fn`, not on a value fetched through here and tested outside.
function ns.Guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

--- An item's name from its ID, or nil when the client has not described it.
function ns.ItemName(itemID)
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
-- Its ID and its name, or nil for anything else. The keep list and the junk
-- list both read their commands through here.
function ns.ReadItem(text)
    local id, name = text:match("|Hitem:(%d+)[^|]*|h%[(.-)%]|h")
    if id then
        return tonumber(id), name
    end

    id = text:match("^(%d+)$")
    if id then
        id = tonumber(id)
        return id, ns.ItemName(id) or ("item " .. id)
    end

    return nil
end

--- An item's name as chat shows it: "[Linen Cloth]".
function ns.ShownItem(name)
    return "[" .. name .. "]"
end

-- In an item's place when the client has no icon for it.
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- An item's icon from its ID. The client knows it without asking the
-- server, so it is there even before the item's name is.
function ns.ItemIcon(itemID)
    return ns.Guarded(function()
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        return getIcon and getIcon(itemID) or UNKNOWN_ICON
    end, UNKNOWN_ICON)
end

--- The colour the game writes an item's name in, by its quality, as
-- { r, g, b }; white until the client has described the item.
function ns.ItemColor(itemID)
    return ns.Guarded(function()
        local quality
        if C_Item and C_Item.GetItemQualityByID then
            quality = C_Item.GetItemQualityByID(itemID)
        else
            local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            quality = getItemInfo and select(3, getItemInfo(itemID))
        end
        local qualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
        if type(quality) == "number" and qualityColor then
            local r, g, b = qualityColor(quality)
            if r then
                return { r, g, b }
            end
        end
        return { 1, 1, 1 }
    end, { 1, 1, 1 })
end

--- Show the tooltip of the item `owner` holds (`owner.itemID`) beside it.
-- Also the owner's UpdateTooltip: the game asks the owner to redraw its
-- tooltip while it shows, so it names what the owner holds now.
function ns.ShowItemTooltip(owner)
    if not (GameTooltip and owner.itemID) then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(owner.itemID)
    else
        GameTooltip:SetHyperlink("item:" .. owner.itemID)
    end
    GameTooltip:Show()
end

function ns.HideItemTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

--- Copper as the game writes money, coin icons and all; "1g 23s 4c" on a
-- client without that.
function ns.Money(copper)
    if GetMoneyString then
        return GetMoneyString(copper)
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if rest > 0 or #parts == 0 then
        parts[#parts + 1] = rest .. "c"
    end
    return table.concat(parts, " ")
end

local function ensureDatabase()
    if type(AutoVendorDB) ~= "table" then
        AutoVendorDB = {}
    end

    applyDefaults(AutoVendorDB, defaults)
    ns.db = AutoVendorDB
end

-- Slash commands. Each file registers its own, so a feature owns its
-- commands and their help.
local commands = {}

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

function ns.ShowHelp()
    ns.Print("Commands:")

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/av %s - %s", name, commands[name].help))
    end
end

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" or input == "help" then
        ns.ShowHelp()
        return
    end

    local name, rest = input:match("^(%S+)%s*(.-)$")
    name = name and name:lower() or ""

    local command = commands[name]
    if command then
        command.handler(rest)
        return
    end

    ns.Print(string.format("Unknown command: %s", name))
    ns.ShowHelp()
end

SLASH_AUTOVENDOR1 = "/autovendor"
SLASH_AUTOVENDOR2 = "/av"
SlashCmdList.AUTOVENDOR = runCommand

-- Work to do once the player is in the world and the database exists.
local loginHandlers = {}

function ns.OnLogin(handler)
    table.insert(loginHandlers, handler)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDatabase()
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()

        for _, handler in ipairs(loginHandlers) do
            handler()
        end
    end
end)
