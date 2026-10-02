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

--- Turn alerts on or off; remembered. The board's switch and the settings
-- page both write through here.
function Alerts.SetEnabled(on)
    ns.db.alerts = on and true or false
    ns.Changed()
end

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

--- Whether a view says it has no places left: "5/5".
local function full(view)
    return view.size ~= nil and view.size.have >= view.size.of
end

--- Alert for `view` if it explicitly wants one of your roles or your class
-- near your level, does not turn your class away or ask only for others,
-- has room, you are not in a group, and it is new. True when it did.
function Alerts.Consider(view)
    -- A group for something the board does not know is as likely Trade
    -- talk as a group, so it is shown but never sounded.
    if not (view and ns.db and ns.db.alerts) or view.kind == "other" or inGroup() or full(view) then
        return false
    end
    local className, class = UnitClass("player")
    if class and view.refuseClasses and view.refuseClasses[class] then
        return false
    end
    -- Asking for classes and not this one says no, whatever the roles.
    if view.wantClasses and not (class and view.wantClasses[class]) then
        return false
    end
    local mine = ns.Roles()
    local byRole = ns.Posts.WantsMe(view, mine)
    if not byRole and not view.wantClasses then
        return false
    end
    if view.activity and not ns.Activities.Near(view.activity, UnitLevel("player")) then
        return false
    end
    -- Hidden from the board, so not sounded either.
    if ns.db.hideCompleted and ns.Posts.ForCompletedQuests(view) then
        return false
    end

    local id = view.key .. "|" .. (view.activity and view.activity.key or view.kind)
    if alerted[id] then
        return false
    end
    alerted[id] = true
    linked[view.key] = view

    sound()
    local what = byRole and ns.Whisper.Roles(view.roles, mine) or className or "player"
    ns.Print(string.format("%s wants a %s for %s. %s", view.name, what, forWhat(view), Alerts.Link(view)))
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
