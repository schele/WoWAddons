local addonName, ns = ...

-- Reading one chat message: whether it is a group recruiting, what for,
-- which roles it wants, how big the group is, and whether it is done.
-- Words only, no frames.

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

local function isRecruiting(list)
    for index, word in ipairs(list) do
        local nextWord = list[index + 1]
        if word == "lfm" or openPlaces(list, index) then
            return true
        end
        if (word == "lf" or word == "need" or word == "needs") and nextWord
            and (ROLE_WORDS[nextWord] or nextWord == "all" or nextWord == "more") then
            return true
        end
        if word == "looking" and nextWord == "for" and list[index + 2] == "more" then
            return true
        end
    end
    return false
end

--- The roles a message asks for, or nil when it names none.
local function wantedRoles(list)
    local wanted, wanting, any = {}, true, false
    for index, word in ipairs(list) do
        if WANT[word] or word:match("^lf%dm?$") then
            wanting = true
        elseif HAVE[word] then
            wanting = false
        end

        if wanting then
            local before = list[index - 1]
            if word == "all" and (before == "need" or before == "lf") then
                wanted.tank, wanted.healer, wanted.dps = true, true, true
                any = true
            elseif ROLE_WORDS[word] then
                wanted[ROLE_WORDS[word]] = true
                any = true
            end
        end
    end
    return any and wanted or nil
end

local function size(lowerText, list, kind)
    local have, of = lowerText:match("(%d+)%s*/%s*(%d+)")
    if have then
        return { have = tonumber(have), of = tonumber(of) }
    end
    if kind == "raid" then
        return nil
    end
    for index in ipairs(list) do
        local open = openPlaces(list, index)
        if open then
            return { have = 5 - open, of = 5 }
        end
    end
    return nil
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

    local words = ns.Activities.Normalize(text)
    local list = tokens(words)

    -- Guild recruitment in the public channels is not a group; in guild chat
    -- the word means nothing.
    if not fromGuild and words:find(" guild ", 1, true) then
        return nil
    end

    if not isRecruiting(list) then
        return isDone(list) and { done = true } or nil
    end

    local activity = ns.Activities.Find(text)
    local kind = (activity and activity.kind) or (isQuest(list) and "quest") or "other"
    return {
        kind = kind,
        activity = activity,
        roles = wantedRoles(list),
        size = size(text:lower(), list, kind),
    }
end
