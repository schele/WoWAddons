local addonName, ns = ...

-- The game's group finder: searching it from a click, and reading what it
-- lists, members and roles included. The only file that knows the
-- finder's calls; without them the board runs on chat alone.

local Finder = {}
ns.Finder = Finder

local ROLES = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

-- The word in a finder category's name for each tab. All searches dungeons.
local TAB_WORDS = { all = "dungeon", dungeon = "dungeon", quest = "quest", raid = "raid" }

function Finder.Available()
    return C_LFGList ~= nil and C_LFGList.Search ~= nil
end

local function categoryName(id)
    if C_LFGList.GetLfgCategoryInfo then
        local info = C_LFGList.GetLfgCategoryInfo(id)
        return type(info) == "table" and info.name or nil
    end
    if C_LFGList.GetCategoryInfo then
        return (C_LFGList.GetCategoryInfo(id))
    end
    return nil
end

function Finder.CategoryFor(tab)
    if not Finder.Available() then
        return nil
    end
    local word = TAB_WORDS[tab] or "dungeon"
    return ns.Guarded(function()
        for _, id in ipairs(C_LFGList.GetAvailableCategories() or {}) do
            local name = categoryName(id)
            if type(name) == "string" and name:lower():find(word, 1, true) then
                return id
            end
        end
        return nil
    end, nil)
end

--- Search the finder for a tab's category. The game takes a search only
-- from a click, so this runs from the Refresh button. True, or false and
-- why not.
function Finder.Search(tab)
    if not Finder.Available() then
        return false, "this client has no group finder"
    end
    local id = Finder.CategoryFor(tab)
    if not id then
        return false, "the group finder has no list for that tab"
    end
    if not pcall(C_LFGList.Search, id) then
        return false, "the game refused the search"
    end
    return true
end

--- A listing's activity name and size.
local function activityOf(info)
    local id = info.activityID or (type(info.activityIDs) == "table" and info.activityIDs[1]) or nil
    if not id then
        return nil, nil
    end
    if C_LFGList.GetActivityInfoTable then
        local activity = C_LFGList.GetActivityInfoTable(id)
        if type(activity) == "table" then
            return activity.fullName, activity.maxNumPlayers
        end
        return nil, nil
    end
    if C_LFGList.GetActivityInfo then
        local name, _, _, _, _, _, _, maxPlayers = C_LFGList.GetActivityInfo(id)
        return name, maxPlayers
    end
    return nil, nil
end

--- One listing as the board keeps it, or nil when the finder will not say.
function Finder.Read(resultID)
    return ns.Guarded(function()
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if type(info) ~= "table" or type(info.leaderName) ~= "string" then
            return nil
        end
        -- Your own listing, or a group you are already in, is not one to join.
        if info.hasSelf or ns.IsMe(info.leaderName) then
            return nil
        end

        local name, max = activityOf(info)
        local activity = type(name) == "string" and ns.Activities.Find(name) or nil
        local kind = (activity and activity.kind)
            or (type(name) == "string" and name:lower():find("quest", 1, true) and "quest")
            or "other"
        if type(max) ~= "number" or max <= 0 then
            max = kind == "raid" and 40 or 5
        end

        local members = {}
        for index = 1, info.numMembers or 0 do
            local role, class = C_LFGList.GetSearchResultMemberInfo(resultID, index)
            members[#members + 1] = { role = ROLES[role], class = class }
        end

        local comment = info.comment
        if type(comment) ~= "string" or comment == "" then
            comment = info.name
        end

        return {
            resultID = resultID,
            leader = info.leaderName,
            class = members[1] and members[1].class or nil,
            comment = comment,
            activity = activity,
            kind = kind,
            members = members,
            max = max,
            full = #members >= max,
            delisted = info.isDelisted == true,
        }
    end, nil)
end

function Finder.Results()
    return ns.Guarded(function()
        local _, ids = C_LFGList.GetSearchResults()
        local listings = {}
        for _, id in ipairs(ids or {}) do
            local listing = Finder.Read(id)
            if listing then
                listings[#listings + 1] = listing
            end
        end
        return listings
    end, {})
end

-- No alerts from a search: whoever searched is already looking at the
-- groups, and one Refresh would sound once for every one of them.
local function received()
    ns.Posts.SetListings(Finder.Results(), GetTime())
    ns.Changed()
end

local function updated(resultID)
    local listing = Finder.Read(resultID)
    if not listing or listing.full or listing.delisted then
        ns.Posts.DropListing(resultID)
    else
        ns.Posts.PutListing(listing, GetTime())
    end
    ns.Changed()
end

-- Each on its own: a client without the finder does not have these names,
-- and registering one it does not have raises.
local events = CreateFrame("Frame")
for _, event in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, resultID)
    if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        received()
    else
        updated(resultID)
    end
end)
