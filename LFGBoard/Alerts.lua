local addonName, ns = ...

-- Telling you about a group that wants you: a sound and a chat line with a
-- link that opens the whisper, once per person and activity, and never
-- while you are in a group already.

local Alerts = {}
ns.Alerts = Alerts

ns.AddDefaults({
    alerts = true,
})

local LINK_COLOR = "ff66ccff"

-- "person|activity" already alerted for, and the view each link opens, so
-- a link still works after its row has dropped off the board.
local alerted = {}
local linked = {}

local function inGroup()
    return ns.Guarded(function()
        if IsInGroup then
            return IsInGroup() and true or false
        end
        if GetNumGroupMembers then
            return GetNumGroupMembers() > 0
        end
        return false
    end, false)
end

local function sound()
    local kit = SOUNDKIT and SOUNDKIT.TELL_MESSAGE
    if kit and PlaySound then
        pcall(PlaySound, kit)
    end
end

function Alerts.Link(view)
    return string.format("|Hlfgboard:whisper:%s|h|c%s[Whisper]|r|h", view.key, LINK_COLOR)
end

local function forWhat(view)
    if view.activity then
        return ns.Activities.Display(view.activity)
    end
    return view.kind == "quest" and "a quest group" or "a group"
end

--- Alert for `view` if it explicitly wants one of your roles near your
-- level, you are not in a group, and it is new. True when it did.
function Alerts.Consider(view)
    if not (view and ns.db and ns.db.alerts) or inGroup() then
        return false
    end
    local mine = ns.Roles()
    if not ns.Posts.WantsMe(view, mine) then
        return false
    end
    if view.activity and not ns.Activities.Near(view.activity, UnitLevel("player")) then
        return false
    end

    local id = view.key .. "|" .. (view.activity and view.activity.key or view.kind)
    if alerted[id] then
        return false
    end
    alerted[id] = true
    linked[view.key] = view

    sound()
    ns.Print(string.format("%s wants a %s for %s. %s",
        view.name, ns.Whisper.Roles(view.roles, mine), forWhat(view), Alerts.Link(view)))
    return true
end

local function onLink(link)
    local key = type(link) == "string" and link:match("^lfgboard:whisper:(.+)$")
    if not key then
        return
    end
    local view = ns.Posts.Get(key) or linked[key]
    if view then
        ns.Whisper.Open(view)
    end
end

local installed = false

--- Hooked rather than replaced, so every other link type reaches the
-- client's own handler untouched, as UrlCopy's links do.
function Alerts.Install()
    if installed then
        return
    end
    installed = true
    if hooksecurefunc and SetItemRef then
        hooksecurefunc("SetItemRef", onLink)
    end
end

ns.OnLogin(Alerts.Install)
