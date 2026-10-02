local addonName, ns = ...

-- Reading one chat message: whether it is a group recruiting, what for,
-- which roles and classes it wants or turns away, how big the group is,
-- and whether it is done. Words only, no frames.

local Parse = {}
ns.Parse = Parse

local ROLE_WORDS = {
    tank = "tank", tanks = "tank", mt = "tank",
    heal = "healer", heals = "healer", healer = "healer", healers = "healer",
    dps = "dps", dd = "dps", damage = "dps",
}

-- Words after which role words are what the group wants, and after which
-- they are what it already has.
local WANT = { need = true, needs = true, lf = true, lfm = true, looking = true }
local HAVE = { have = true, got = true, has = true, with = true, w = true }

-- The words players type for each class, plurals and short names included.
-- The game's own names for them join these at first use. Kept to words that
-- mean nothing else in a group post: no "war", no "pal".
local CLASS_WORDS = {
    warrior = "WARRIOR", warriors = "WARRIOR", warr = "WARRIOR", warrs = "WARRIOR",
    paladin = "PALADIN", paladins = "PALADIN", pally = "PALADIN", pallies = "PALADIN", pala = "PALADIN",
    hunter = "HUNTER", hunters = "HUNTER", hunt = "HUNTER", hunts = "HUNTER",
    rogue = "ROGUE", rogues = "ROGUE",
    priest = "PRIEST", priests = "PRIEST",
    shaman = "SHAMAN", shamans = "SHAMAN", sham = "SHAMAN", shammy = "SHAMAN", shammies = "SHAMAN",
    mage = "MAGE", mages = "MAGE",
    warlock = "WARLOCK", warlocks = "WARLOCK", lock = "WARLOCK", locks = "WARLOCK",
    druid = "DRUID", druids = "DRUID",
}
local localizedAdded = false

--- The class a word names, or nil. The game's names for the classes count
-- too, where one is a single word once normalized: one with letters outside
-- plain ASCII comes apart in Normalize and is left out.
local function classOf(word)
    if not localizedAdded then
        localizedAdded = true
        for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
            for class, name in pairs(names) do
                local normalized = type(name) == "string" and ns.Activities.Normalize(name):match("^ (%S+) $")
                if normalized and not CLASS_WORDS[normalized] then
                    CLASS_WORDS[normalized] = class
                end
            end
        end
    end
    return CLASS_WORDS[word]
end

-- Sizes a written "3/5" may be out of: a word like "1/2 price" is not one.
local GROUP_SIZES = { [5] = true, [10] = true, [20] = true, [25] = true, [40] = true }

-- Words for a count of places, after need or LF: "need one more".
local COUNT_WORDS = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, one = 1, two = 2, three = 3, four = 4 }

local DONE = { full = true, filled = true, nvm = true }
local QUEST = { quest = true, quests = true, elite = true }

local function tokens(words)
    local list = {}
    for word in words:gmatch("%S+") do
        list[#list + 1] = word
    end
    return list
end

--- How many places "LF2M" (or "LF 2M", "lf2") says are open, or nil.
local function openPlaces(list, index)
    local word = list[index]
    local count = word:match("^lf(%d)m?$")
    if count then
        return tonumber(count)
    end
    if word == "lf" and list[index + 1] then
        count = list[index + 1]:match("^(%d)m$")
        if count then
            return tonumber(count)
        end
    end
    return nil
end

-- Words that may come between an ask and its role: "need a tank",
-- "LF 1 more dps".
local FILLER = {
    a = true, an = true, one = true, two = true, three = true, more = true, another = true,
    ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true,
}

--- The first word after `index` that is not filler, looking a few words on.
local function asked(list, index)
    for step = 1, 4 do
        local word = list[index + step]
        if not word or not FILLER[word] then
            return word
        end
    end
    return nil
end

--- How many places "need 1 more", "LF one more" or "looking for 2 more"
-- asks to fill, or nil. Only with "more": "need 2 dps" may not be all.
local function morePlaces(list, index)
    local word = list[index]
    local at = index + 1
    if word == "looking" and list[at] == "for" then
        at = at + 1
    elseif word ~= "need" and word ~= "needs" and word ~= "lf" then
        return nil
    end
    local count = COUNT_WORDS[list[at] or ""]
    if count and list[at + 1] == "more" then
        return count
    end
    return nil
end

--- Whether a message recruits: strongly with LFM or "LF2M", which say so
-- whatever else is in the message; weakly by asking for a role or for
-- more, which Trade talk does too ("need tank gear?").
local function recruiting(list)
    local strong, weak = false, false
    for index, word in ipairs(list) do
        local nextWord = list[index + 1]
        if word == "lfm" or openPlaces(list, index) then
            strong = true
        end
        if (word == "lf" or word == "need" or word == "needs") and nextWord
            and (nextWord == "all" or nextWord == "more" or ROLE_WORDS[asked(list, index) or ""]) then
            weak = true
        end
        if word == "looking" and nextWord == "for"
            and (list[index + 2] == "more" or ROLE_WORDS[asked(list, index + 1) or ""]) then
            weak = true
        end
        if ROLE_WORDS[word] and (nextWord == "needed" or nextWord == "wanted") then
            weak = true
        end
        if morePlaces(list, index) then
            weak = true
        end
    end
    return strong, weak
end

--- Whether a role word at `index` is the poster's own: said just before
-- what they look for, as in "Tank LFM SFK".
local function ownRole(list, index)
    local after = list[index + 1]
    return after ~= nil and (after == "lf" or after == "lfm" or after == "looking" or after:match("^lf%dm?$") ~= nil)
end

--- The roles a message asks for, or nil when it names none. Not the ones
-- the group has ("have tank"), the poster's own, or ones it has no room
-- for ("no dps", "dps full").
local function wantedRoles(list)
    local wanted, wanting, any = {}, true, false
    for index, word in ipairs(list) do
        if WANT[word] or word:match("^lf%dm?$") then
            wanting = true
        elseif HAVE[word] then
            wanting = false
        end

        if wanting then
            local before, after = list[index - 1], list[index + 1]
            if word == "all" and (before == "need" or before == "lf") then
                wanted.tank, wanted.healer, wanted.dps = true, true, true
                any = true
            elseif ROLE_WORDS[word] and not ownRole(list, index) and before ~= "no" and after ~= "full" then
                wanted[ROLE_WORDS[word]] = true
                any = true
            end
        end
    end
    return any and wanted or nil
end

--- A message without its links and colours: an item's or a quest's name
-- names neither a dungeon nor a role.
local function withoutLinks(text)
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h.-|h", " ")
    return plain
end

--- How many are in the group, as { have, of }, or nil when the message
-- does not say clearly. A written "3/5" counts for any group; the places
-- asked for only for a group of five, which a dungeon or quest group is. A
-- raid's size, or one the board cannot place, is not known from them.
local function size(lowerText, list, kind)
    for have, of in lowerText:gmatch("(%d+)%s*/%s*(%d+)") do
        have, of = tonumber(have), tonumber(of)
        if GROUP_SIZES[of] and have >= 1 and have <= of then
            return { have = have, of = of }
        end
    end
    if kind ~= "dungeon" and kind ~= "quest" then
        return nil
    end
    for index in ipairs(list) do
        local open = openPlaces(list, index) or morePlaces(list, index)
        if open and open >= 1 and open <= 4 then
            return { have = 5 - open, of = 5 }
        end
    end
    return nil
end

--- Whether the word at `index` turns away the class it names: "no hunters",
-- "no more hunters", "hunters full".
local function refused(list, index)
    local before, after = list[index - 1], list[index + 1]
    if before == "no" or after == "full" then
        return true
    end
    return before == "more" and list[index - 2] == "no"
end

-- Words that may come between an ask and the classes it asks for, as well
-- as the activity's own: "LF1M DM healer, priest or druid".
local LINKING = { ["and"] = true, ["or"] = true, n = true, ["for"] = true, pref = true, preferably = true }

local function activityWords(activity)
    local words = {}
    if activity then
        for word in ns.Activities.Normalize(activity.name):gmatch("%S+") do
            words[word] = true
        end
        for _, phrase in ipairs(activity.words) do
            for word in phrase:gmatch("%S+") do
                words[word] = true
            end
        end
    end
    return words
end

-- Words that, ending a run of classes, say the group has them already:
-- "hunter and priest in group", "mage here".
local HAD = { ["in"] = true, here = true, already = true, inside = true, grouped = true }

--- The classes a message asks for and the ones it turns away, each a set
-- by class file ("HUNTER"), or nil. A class asked for is one in the run of
-- words straight after an ask, kept only when the run does not end by
-- saying the group has it: "LF1M DM, hunter and priest in group" asks for
-- neither. The poster's own, said before an ask, is left out.
local function classes(list, activity)
    local wanted, refusedSet = {}, {}
    local own = activityWords(activity)
    local inAsk, pending = false, {}

    local function endRun(word)
        if not HAD[word or ""] then
            for class in pairs(pending) do
                wanted[class] = true
            end
        end
        inAsk, pending = false, {}
    end

    for index, word in ipairs(list) do
        local class = classOf(word)
        if WANT[word] or word:match("^lf%d?m?$") then
            if inAsk then
                endRun(word)
            end
            inAsk = true
        elseif class then
            if refused(list, index) then
                refusedSet[class] = true
            elseif inAsk and not ownRole(list, index) then
                pending[class] = true
            end
        elseif inAsk and not (FILLER[word] or LINKING[word] or ROLE_WORDS[word] or own[word] or word == "no") then
            endRun(word)
        end
    end
    endRun(nil)
    for class in pairs(refusedSet) do
        wanted[class] = nil
    end
    return next(wanted) and wanted or nil, next(refusedSet) and refusedSet or nil
end

local function isDone(list)
    for index, word in ipairs(list) do
        if DONE[word] then
            return true
        end
        if word == "no" and list[index + 1] == "longer" then
            return true
        end
    end
    return false
end

--- The ids of the quests a message links, in order, or nil for none. A
-- link reads |Hquest:<id>:<level>|h[Name]|h.
local function linkedQuests(text)
    local ids = {}
    for id in text:gmatch("|Hquest:(%d+)") do
        ids[#ids + 1] = tonumber(id)
    end
    return #ids > 0 and ids or nil
end

local function isQuest(list)
    for index, word in ipairs(list) do
        if QUEST[word] then
            return true
        end
        if word == "q" and list[index + 1] then
            return true
        end
    end
    return false
end

--- What a message says about a group, or nil when it says nothing about
-- one. `{ done = true }` for a message saying the group has filled.
function Parse.Message(text, fromGuild)
    if type(text) ~= "string" then
        return nil
    end

    local plain = withoutLinks(text)
    local words = ns.Activities.Normalize(plain)
    local list = tokens(words)

    -- Guild recruitment in the public channels is not a group; in guild chat
    -- the word means nothing.
    if not fromGuild and words:find(" guild ", 1, true) then
        return nil
    end

    local strong, weak = recruiting(list)
    if not (strong or weak) then
        return isDone(list) and { done = true } or nil
    end

    local activity = ns.Activities.Find(plain)
    local quests = linkedQuests(text)
    local quest = quests ~= nil or isQuest(list)
    -- Asking for a role with nothing to ask it for is Trade talk; a group
    -- says what it is for, or says LFM.
    if not strong and not activity and not quest then
        return nil
    end

    local kind = (activity and activity.kind) or (quest and "quest") or "other"
    local wantClasses, refuseClasses = classes(list, activity)
    return {
        wantClasses = wantClasses,
        refuseClasses = refuseClasses,
        kind = kind,
        activity = activity,
        roles = wantedRoles(list),
        size = size(plain:lower(), list, kind),
        quests = quests,
    }
end
