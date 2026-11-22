local addonName, ns = ...

-- The name this client gives a quest, item or spell, found from the id in its
-- link. A link carries the name in the sender's language; the id is the same
-- in every language, so the client's own name for it is the translation.
--
-- A name the client has not loaded yet is asked for, and whoever is listening
-- hears when it arrives (chat is rewritten again then).

local Names = {}
ns.Names = Names

-- How to name each kind of link, how to ask the client to load one it does
-- not have yet, and the events that say a load finished: (id, success).
local KINDS = {
    quest = {
        name = function(id)
            if C_QuestLog and C_QuestLog.GetTitleForQuestID then
                return C_QuestLog.GetTitleForQuestID(id)
            end
        end,
        request = function(id)
            if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
                C_QuestLog.RequestLoadQuestByID(id)
                return true
            end
        end,
        events = { "QUEST_DATA_LOAD_RESULT" },
    },
    item = {
        name = function(id, data)
            local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            if not getInfo then
                return nil
            end
            -- The whole item string, not just the id: the link the client
            -- builds from it names the item with its suffix ("of the Bear"),
            -- which the bare name leaves off.
            local name, link = getInfo("item:" .. data)
            local shown = type(link) == "string" and link:match("|h%[(.-)%]|h")
            return shown or name
        end,
        request = function(id)
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(id)
                return true
            end
            -- Asking for its info is a request too, on a client without the
            -- call above: it answers GET_ITEM_INFO_RECEIVED when it has it.
            if GetItemInfo then
                GetItemInfo(id)
                return true
            end
        end,
        events = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" },
    },
    spell = {
        name = function(id)
            if C_Spell and C_Spell.GetSpellName then
                return C_Spell.GetSpellName(id)
            end
            if GetSpellInfo then
                return (GetSpellInfo(id))
            end
        end,
        request = function(id)
            if C_Spell and C_Spell.RequestLoadSpellData then
                C_Spell.RequestLoadSpellData(id)
                return true
            end
        end,
        events = { "SPELL_DATA_LOAD_RESULT" },
    },
}

--- Whether LinkTranslate knows how to name this kind of link.
function Names.Knows(linkType)
    return KINDS[linkType] ~= nil
end

-- Loads asked for and not answered yet, by "quest:2945".
local pending = {}
local listeners = {}

--- `fn(linkType, id)` runs when a name asked for has arrived.
function Names.OnLoaded(fn)
    table.insert(listeners, fn)
end

local function request(linkType, id)
    local key = linkType .. ":" .. id
    if pending[key] then
        return
    end
    if ns.Guarded(function() return KINDS[linkType].request(id) end) then
        pending[key] = true
    end
end

--- The client's name for the thing a link points at, from the link's type
-- ("quest") and the data after it ("2945:28"); nil if it has none yet, in
-- which case it has been asked for.
function Names.Get(linkType, data)
    local kind = KINDS[linkType]
    local id = type(data) == "string" and tonumber(data:match("^(%d+)"))
    if not kind or not id then
        return nil
    end

    local name = ns.Guarded(function() return kind.name(id, data) end)
    if type(name) == "string" and name ~= "" then
        return name
    end

    request(linkType, id)
    return nil
end

local frame = CreateFrame("Frame")

local function loaded(linkType, id, success)
    local key = linkType .. ":" .. tostring(id)
    if not pending[key] then
        return
    end
    pending[key] = nil
    if success == false then
        return
    end
    for _, fn in ipairs(listeners) do
        ns.Guarded(function() fn(linkType, id) end)
    end
end

local typeByEvent = {}
for linkType, kind in pairs(KINDS) do
    for _, event in ipairs(kind.events) do
        typeByEvent[event] = linkType
        frame:RegisterEvent(event)
    end
end

frame:SetScript("OnEvent", function(_, event, id, success)
    local linkType = typeByEvent[event]
    if linkType and id then
        loaded(linkType, id, success)
    end
end)
