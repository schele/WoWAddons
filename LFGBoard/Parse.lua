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
    local quest = text:find("|Hquest:", 1, true) ~= nil or isQuest(list)
    -- Asking for a role with nothing to ask it for is Trade talk; a group
    -- says what it is for, or says LFM.
    if not strong and not activity and not quest then
        return nil
    end

    local kind = (activity and activity.kind) or (quest and "quest") or "other"
    return {
        kind = kind,
        activity = activity,
        roles = wantedRoles(list),
        size = size(plain:lower(), list, kind),
    }
end
