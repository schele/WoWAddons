local addonName, ns = ...

-- One chat line when a talent point is free, naming the plan's next talent,
-- and Learn next: spending that point with LearnTalent, when the player has
-- turned it on and the client has the call.

local Reminder = {}
ns.Reminder = Reminder

-- The point last named, so a level-up and the points event that follows it
-- do not say the same thing twice.
local lastKey

-- What Learn next last did, for /tp probe: { name, result }.
local lastLearn

-- How long the client gets to answer a LearnTalent before the rank is read.
local LEARN_CHECK_DELAY = 1

--- The plan's next point, with the talent's name and ranks: nil when there
-- is no plan left to follow or the trees cannot be read.
function Reminder.Next()
    local trees = ns.Trees.Read()
    if not trees then
        return nil
    end
    local plan = ns.Plans.Active()
    local n, tab, index, rank = ns.Plan.Next(plan.points, ns.Plan.RanksOf(trees))
    if not n then
        return nil
    end
    local talent = trees[tab] and trees[tab].talents[index]
    if not talent then
        -- The plan names a talent this client does not have: nothing to offer.
        return nil
    end
    return {
        n = n, tab = tab, index = index, rank = rank,
        name = talent.name, maxRank = talent.maxRank, current = talent.rank,
    }
end

function Reminder.Describe(info)
    return string.format("%s (%d/%d)", info.name, info.rank, info.maxRank)
end

function Reminder.Check()
    if not (ns.db and ns.db.remind) then
        return
    end
    local unspent = ns.Trees.Unspent()
    if not unspent or unspent < 1 then
        return
    end
    local info = Reminder.Next()
    if not info then
        return
    end
    local key = string.format("%d:%d:%d:%d", info.n, info.tab, info.index, info.rank)
    if key == lastKey then
        return
    end
    lastKey = key
    ns.Print("Talent point ready: " .. Reminder.Describe(info))
end

--- Whether a Learn next would be allowed to try, and why not.
function Reminder.CanLearn()
    if not ns.db.learn then
        return false, "Learn next is off in the settings."
    end
    if type(LearnTalent) ~= "function" then
        return false, "This client has no LearnTalent."
    end
    if ns.Guarded(function() return InCombatLockdown() end, true) then
        return false, "Not in combat."
    end
    return true
end

--- Spend a free point on the plan's next talent. True once asked; the
-- client may still refuse, which is noted for the probe a moment later.
function Reminder.LearnNext()
    local can, why = Reminder.CanLearn()
    if not can then
        return false, why
    end
    local unspent = ns.Trees.Unspent()
    if not unspent or unspent < 1 then
        return false, "No talent point to spend."
    end
    local info = Reminder.Next()
    if not info then
        return false, "The plan has no point left to learn."
    end

    lastLearn = { name = info.name, result = "sent" }
    local attempt = lastLearn
    local asked = ns.Guarded(function()
        LearnTalent(info.tab, info.index)
        return true
    end, false)
    if not asked then
        attempt.result = "refused"
        return false, "The client would not learn " .. info.name .. "."
    end

    local function verify()
        local trees = ns.Trees.Read()
        local talent = trees and trees[info.tab] and trees[info.tab].talents[info.index]
        if talent then
            attempt.result = talent.rank > info.current and "worked" or "refused"
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(LEARN_CHECK_DELAY, verify)
    else
        verify()
    end
    return true
end

function Reminder.LastLearn()
    return lastLearn
end

ns.OnLogin(Reminder.Check)

local events = CreateFrame("Frame")
-- Guarded: the client raises on an event it does not have.
for _, event in ipairs({ "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
    Reminder.Check()
end)
