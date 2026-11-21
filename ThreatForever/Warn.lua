local addonName, ns = ...

-- Warns you before you pull aggro off the tank: the raid warning sound and
-- red words in the middle of the screen. Once per scare: it comes again only
-- after you have dropped well back, on a new target, or in the next fight.
--
-- It comes when the game says you have more threat than the tank without
-- having pulled yet (status 1), which it says even on a boss, or at 90% of
-- what pulls while you are still under the tank, where the numbers show.

local Warn = {}
ns.Warn = Warn

ns.AddDefaults({ warn = true })

Warn.AT = 90 -- percent of what pulls aggro
Warn.CALM = 80 -- dropped back this far, it may warn again
Warn.TEXT = "You are about to pull aggro!"
Warn.RED = { r = 1, g = 0.25, b = 0.2 }

local armed = true

local function playerRow(list)
    for _, row in ipairs(list.rows) do
        if row.isPlayer then
            return row
        end
    end
end

-- Plain numbers only: a secret one cannot be compared, so on a boss it is
-- the game's word alone.
local function over(row, limit)
    return not row.secret and type(row.scaled) == "number" and row.scaled >= limit
end

local function danger(row)
    return row ~= nil and not row.tanking and (row.status == 1 or over(row, Warn.AT))
end

local function calm(row)
    if row == nil or row.tanking then
        return true
    end
    if row.secret then
        return row.status == 0
    end
    return row.status == 0 and not over(row, Warn.CALM)
end

local function showOnScreen(text)
    if RaidWarningUtil and RaidWarningUtil.AddMessage then
        RaidWarningUtil.AddMessage(text, Warn.RED)
    elseif RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, Warn.RED)
    elseif UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, Warn.RED.r, Warn.RED.g, Warn.RED.b)
    end
end

function Warn.Show()
    ns.Guarded(function()
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end)
    ns.Guarded(function() showOnScreen(Warn.TEXT) end)
end

--- Over every mob shown: about to pull any of them sets it off, and it is
-- ready again once you are well back on all of them.
function Warn.Check()
    if not ns.settings.warn or ns.Threat.InDemo() then
        return
    end
    local anyDanger, allCalm = false, true
    for _, list in ipairs(ns.Threat.All()) do
        local row = playerRow(list)
        anyDanger = anyDanger or danger(row)
        allCalm = allCalm and calm(row)
    end
    if armed and anyDanger then
        armed = false
        Warn.Show()
    elseif not armed and allCalm then
        armed = true
    end
end

ns.Threat.OnUpdate(Warn.Check)

-- A new target or a new fight is a fresh start.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
    armed = true
end)

ns.RegisterCommand("test", "Show what the warning is like", function()
    if not ns.settings.warn then
        ns.Print("The warning is off. Turn it on in the settings page (/threat settings).")
        return
    end
    Warn.Show()
end)
