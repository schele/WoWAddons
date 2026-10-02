local addonName, ns = ...

-- The whisper a row's button opens: who you are and what you can do, typed
-- out, so Enter is all that is left.

local Whisper = {}
ns.Whisper = Whisper

-- The words players use for a talent tree, where it is not its first word.
Whisper.SHORT = {
    ["restoration"] = "resto",
    ["protection"] = "prot",
    ["beast mastery"] = "bm",
    ["discipline"] = "disc",
    ["elemental"] = "ele",
    ["enhancement"] = "enh",
    ["demonology"] = "demo",
    ["destruction"] = "destro",
    ["affliction"] = "affli",
}

local ROLE_ORDER = { "tank", "healer", "dps" }

--- The talent tree with the most points, or nil with none spent. Points are
-- counted talent by talent: where the tab's own count sits differs between
-- clients, and the name may come before or after an ID.
local function talentTree()
    return ns.Guarded(function()
        if not (GetNumTalentTabs and GetTalentTabInfo and GetNumTalents and GetTalentInfo) then
            return nil
        end
        local best, bestPoints = nil, 0
        for tab = 1, GetNumTalentTabs() do
            local first, second = GetTalentTabInfo(tab)
            local name = type(first) == "string" and first or second
            local points = 0
            for index = 1, GetNumTalents(tab) do
                local rank = select(5, GetTalentInfo(tab, index))
                points = points + (type(rank) == "number" and rank or 0)
            end
            if type(name) == "string" and points > bestPoints then
                best, bestPoints = name, points
            end
        end
        return best
    end, nil)
end

function Whisper.SpecWord(treeName)
    if type(treeName) ~= "string" then
        return nil
    end
    local lower = treeName:lower()
    return Whisper.SHORT[lower] or lower:match("^(%S+)")
end

--- Your roles that a group wants, "tank or dps"; all your roles when it
-- does not say, or wants none of them.
function Whisper.Roles(wanted, mine)
    local parts = {}
    for _, role in ipairs(ROLE_ORDER) do
        if mine[role] and (wanted == nil or wanted[role]) then
            parts[#parts + 1] = role
        end
    end
    if #parts == 0 then
        for _, role in ipairs(ROLE_ORDER) do
            if mine[role] then
                parts[#parts + 1] = role
            end
        end
    end
    return table.concat(parts, " or ")
end

local function forWhat(view)
    if view.activity then
        return ns.Activities.Display(view.activity)
    end
    return view.kind == "quest" and "your quest group" or "your group"
end

function Whisper.Message(view)
    local level = UnitLevel("player") or 0
    local class = (UnitClass("player") or ""):lower()
    local spec = Whisper.SpecWord(talentTree())
    local who = spec and (spec .. " " .. class) or class

    local text = string.format("Hi! Level %d %s", level, who)
    local roles = Whisper.Roles(view.roles, ns.Roles())
    if roles ~= "" then
        text = text .. ", " .. roles
    end
    return text .. ". Room for me in " .. forWhat(view) .. "?"
end

function Whisper.Open(view)
    local line = "/w " .. (view.whisperName or view.name) .. " " .. Whisper.Message(view)
    local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
    if open then
        open(line)
    end
end
