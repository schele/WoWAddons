local addonName, ns = ...

-- The rows on the board, one per person: what their chat message said and
-- what the group finder listed for them, merged. Adding, replacing,
-- expiring, removing and filtering; no frames.

local Posts = {}
ns.Posts = Posts

-- A chat message, or a finder listing, drops off this long after it was
-- last seen.
Posts.EXPIRY = 600

local ROLE_ORDER = { "tank", "healer", "dps" }

-- A group of five has room for this many of each.
local PLACES = { tank = 1, healer = 1, dps = 3 }

local rows = {}

local function shortName(name)
    return name:match("^([^%-]+)") or name
end

local function keyFor(name)
    return shortName(name):lower()
end

function Posts.Clear()
    rows = {}
end

--- Add what someone said in chat. The row it made or changed, or nil when
-- the message is not about a group. "Full" and the like take the row off.
function Posts.AddChat(message)
    local parsed = ns.Parse.Message(message.text, message.guild)
    if not parsed then
        return nil
    end

    local key = keyFor(message.name)
    if parsed.done then
        rows[key] = nil
        return nil
    end

    local row = rows[key] or { key = key }
    row.name = shortName(message.name)
    row.whisperName = message.name
    row.class = message.class or row.class
    row.chat = {
        kind = parsed.kind,
        activity = parsed.activity,
        roles = parsed.roles,
        size = parsed.size,
        quests = parsed.quests,
        wantClasses = parsed.wantClasses,
        refuseClasses = parsed.refuseClasses,
        text = message.text,
        time = message.time,
    }
    rows[key] = row
    return row
end

--- Put a finder listing on the board, merged with the leader's chat row.
-- A full or delisted listing takes the leader's whole row off instead.
function Posts.PutListing(listing, now)
    local key = keyFor(listing.leader)
    if listing.full or listing.delisted then
        rows[key] = nil
        return nil
    end

    local row = rows[key] or { key = key, name = shortName(listing.leader), whisperName = listing.leader }
    local before = row.finder
    row.class = listing.class or row.class
    row.level = listing.level or row.level
    row.finder = {
        resultID = listing.resultID,
        kind = listing.kind,
        activity = listing.activity,
        comment = listing.comment,
        members = listing.members,
        max = listing.max,
        -- First seen, for the age shown; last seen, for dropping off.
        time = (before and before.resultID == listing.resultID) and before.time or now,
        seen = now,
    }
    rows[key] = row
    return row
end

--- Take a new search's listings: they replace the last search's, and chat
-- rows stay. The rows the listings made or changed.
function Posts.SetListings(listings, now)
    local changed, found = {}, {}
    for _, listing in ipairs(listings) do
        found[keyFor(listing.leader)] = true
        local row = Posts.PutListing(listing, now)
        if row then
            changed[#changed + 1] = row
        end
    end

    for key, row in pairs(rows) do
        if row.finder and not found[key] then
            row.finder = nil
            if not row.chat then
                rows[key] = nil
            end
        end
    end
    return changed
end

--- A listing the finder says has filled, delisted or gone: its row goes.
function Posts.DropListing(resultID)
    for key, row in pairs(rows) do
        if row.finder and row.finder.resultID == resultID then
            rows[key] = nil
        end
    end
end

function Posts.Expire(now)
    for key, row in pairs(rows) do
        if row.chat and now - row.chat.time >= Posts.EXPIRY then
            row.chat = nil
        end
        if row.finder and now - row.finder.seen >= Posts.EXPIRY then
            row.finder = nil
        end
        if not row.chat and not row.finder then
            rows[key] = nil
        end
    end
end

--- The roles a finder group of five has room for, from its members' roles.
local function room(members, max)
    if max ~= 5 then
        return nil
    end
    local counts = { tank = 0, healer = 0, dps = 0 }
    for _, member in ipairs(members) do
        if member.role then
            counts[member.role] = counts[member.role] + 1
        end
    end
    local wanted, any = {}, false
    for _, role in ipairs(ROLE_ORDER) do
        if counts[role] < PLACES[role] then
            wanted[role] = true
            any = true
        end
    end
    return any and wanted or nil
end

--- One row as the board shows it. The finder decides what it is for and
-- who is in it; the chat message's words, time and roles win where there
-- is one, since they are what the leader said.
function Posts.View(row)
    local chat, finder = row.chat, row.finder
    local main = finder or chat
    local view = {
        key = row.key,
        name = row.name,
        whisperName = row.whisperName,
        class = row.class,
        level = row.level,
        kind = main.kind,
        activity = main.activity,
        text = chat and chat.text or finder.comment,
        time = chat and chat.time or finder.time,
        source = (chat and finder) and "both" or (finder and "finder" or "chat"),
        -- Only chat links a quest; a finder listing names a zone.
        quests = chat and chat.quests or nil,
        -- Only what was said names classes.
        wantClasses = chat and chat.wantClasses or nil,
        refuseClasses = chat and chat.refuseClasses or nil,
    }
    if finder then
        view.members = finder.members
        view.size = { have = #finder.members, of = finder.max }
        view.roles = (chat and chat.roles) or room(finder.members, finder.max)
    else
        view.size = chat.size
        view.roles = chat.roles
    end
    return view
end

function Posts.Get(key)
    local row = rows[key]
    return row and Posts.View(row) or nil
end

--- Whether a view explicitly asks for one of `roles`.
function Posts.WantsMe(view, roles)
    if not view.roles then
        return false
    end
    for _, role in ipairs(ROLE_ORDER) do
        if view.roles[role] and roles[role] then
            return true
        end
    end
    return false
end

--- Whether the player has handed in quest `id`. Unknown counts as not:
-- a row wrongly shown costs less than one wrongly hidden.
local function questDone(id)
    return ns.Guarded(function()
        if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
            return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
        end
        if IsQuestFlaggedCompleted then
            return IsQuestFlaggedCompleted(id) and true or false
        end
        if GetQuestsCompleted then
            local done = GetQuestsCompleted()
            return type(done) == "table" and done[id] and true or false
        end
        return false
    end, false)
end

--- Whether a view is a quest group for quests the player has completed:
-- every quest it links handed in. One named only in words cannot be told,
-- and a dungeon group linking a quest is still a dungeon run.
function Posts.ForCompletedQuests(view)
    if view.kind ~= "quest" or not view.quests then
        return false
    end
    for _, id in ipairs(view.quests) do
        if not questDone(id) then
            return false
        end
    end
    return true
end

--- Whether a view passes every filter but the tab.
local function passes(view, filter)
    if filter.hideCompleted and Posts.ForCompletedQuests(view) then
        return false
    end
    if filter.activity and view.activity ~= filter.activity then
        return false
    end
    if view.roles and not Posts.WantsMe(view, filter.roles) then
        return false
    end
    if filter.nearLevel and view.activity and not ns.Activities.Near(view.activity, filter.level) then
        return false
    end
    return true
end

function Posts.Visible(filter)
    local tab = filter.tab or "all"
    local list = {}
    for _, row in pairs(rows) do
        local view = Posts.View(row)
        if (tab == "all" or view.kind == tab) and passes(view, filter) then
            list[#list + 1] = view
        end
    end
    table.sort(list, function(a, b)
        if a.time ~= b.time then
            return a.time > b.time
        end
        return a.key < b.key
    end)
    return list
end

function Posts.Counts(filter)
    local counts = { all = 0, dungeon = 0, quest = 0, raid = 0 }
    for _, row in pairs(rows) do
        local view = Posts.View(row)
        if passes(view, filter) then
            counts.all = counts.all + 1
            if counts[view.kind] then
                counts[view.kind] = counts[view.kind] + 1
            end
        end
    end
    return counts
end

--- The activities on the board, by name: what the dungeon picker steps through.
function Posts.Activities()
    local seen, list = {}, {}
    for _, row in pairs(rows) do
        local activity = Posts.View(row).activity
        if activity and not seen[activity] then
            seen[activity] = true
            list[#list + 1] = activity
        end
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end
