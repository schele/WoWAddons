local addonName, ns = ...

ns.PREFIX = "|cff66ccffRankUp|r"

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

function ns.Buttons(count)
    if count == 1 then
        return "1 button"
    end
    return string.format("%d buttons", count)
end

-- How long after a learned spell to look. The spellbook lists a rank the
-- trainer just taught a moment after the event saying so, and "train all"
-- teaches several in a row: one look, once they are all in.
local LEARN_DELAY = 1

-- A look that came during combat, waiting for it to end; and whether it was
-- /rankup, which answers even when there is nothing to do.
local held, heldAsked = false, false

--- Ask the bars what is outdated and show it, or hide the popup when nothing
-- is. Never during combat: the look waits for the fight to end. `asked` is
-- true for /rankup.
function ns.Look(asked)
    if InCombatLockdown() then
        held = true
        heldAsked = heldAsked or asked == true
        return
    end

    local groups = ns.Ranks.Outdated()
    if #groups == 0 then
        ns.Popup.Hide()
        if asked then
            ns.Print("Every button already holds your highest rank.")
        end
        return
    end

    ns.Popup.Show(groups)
end

local lookPending = false

local function lookSoon()
    if lookPending then
        return
    end
    lookPending = true
    C_Timer.After(LEARN_DELAY, function()
        lookPending = false
        ns.Look(false)
    end)
end

SLASH_RANKUP1 = "/rankup"
SlashCmdList.RANKUP = function()
    ns.Look(true)
end

-- The clients this addon loads on name the "spell learned" event two ways,
-- and registering a name a client does not have raises: each on its own.
local LEARN_EVENTS = { "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }

local lookedAtLogin = false

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
for _, event in ipairs(LEARN_EVENTS) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Every loading screen fires this; only the first is the login.
        if not lookedAtLogin then
            lookedAtLogin = true
            lookSoon()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Popup.SetCombat(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Popup.SetCombat(false)
        -- A look held through the fight, or a popup whose upgrade the fight
        -- cut short: look again, so the list is what is left.
        if held or ns.Popup.IsShown() then
            local asked = heldAsked
            held, heldAsked = false, false
            ns.Look(asked)
        end
    else
        lookSoon()
    end
end)
