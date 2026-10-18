local addonName, ns = ...

-- The action bars, each where it was last saved in Edit Mode on this screen.
-- The game saves the layout to the account, so a bar placed right on a laptop
-- moves on the desktop too; here each screen keeps its own places, layout by
-- layout. A screen starts from the layout as it first sees it, and after that
-- only a save in Edit Mode on that screen changes them.
--
-- A bar is moved with the frame's own SetPoint, never Edit Mode's wrapper
-- around it: the wrapper writes Edit Mode's tables, and run from an addon it
-- would taint them, and with them the bars in combat.

-- The client's Lua has it global; a newer Lua keeps it in table.
local unpack = unpack or table.unpack

ns.AddDefaults({
    ui = {
        barsPerScreen = true,
        -- By screen, as "3840x2160", then by Edit Mode layout name: each
        -- bar's place as Edit Mode keeps it, by the bar's frame name.
        barScreens = {},
    },
})

-- True while this file moves a bar, so the hook on its SetPoint does not take
-- our own move for the game's.
local moving = false
local queued = false
-- A move the game refused during a fight, to make when it ends.
local pending = false
-- Each bar's own points, kept from our first move since the game last placed
-- it, so they can be given back.
local original = {}
-- Each bar's place when Edit Mode opened, so a save that moved it can be told
-- from one that moved something else.
local noted
local hookedBars = {}

local function screenKey()
    local width, height = GetPhysicalScreenSize()
    if width and height then
        return width .. "x" .. height
    end
end

local function editModeOpen()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

--- The action bars Edit Mode has laid out.
local function bars()
    local list = {}
    local manager = EditModeManagerFrame
    local system = Enum and Enum.EditModeSystem and Enum.EditModeSystem.ActionBar
    if not (manager and manager.registeredSystemFrames and system) then
        return list
    end
    for _, frame in ipairs(manager.registeredSystemFrames) do
        if frame.system == system and frame.systemInfo and frame:GetName() then
            list[#list + 1] = frame
        end
    end
    return list
end

--- This screen's places for the active layout, made on first use. Nil until
-- the game has a layout.
local function screenPlaces()
    local manager = EditModeManagerFrame
    local layout = manager and manager.GetActiveLayoutInfo and manager:GetActiveLayoutInfo()
    local name, key = layout and layout.layoutName, screenKey()
    if not (name and key and ns.db) then
        return nil
    end
    local screens = ns.db.ui.barScreens
    screens[key] = screens[key] or {}
    screens[key][name] = screens[key][name] or {}
    return screens[key][name]
end

local function copyAnchor(anchor)
    if not anchor then
        return nil
    end
    local relativeTo = anchor.relativeTo
    if type(relativeTo) == "table" then
        relativeTo = relativeTo:GetName()
    end
    return {
        point = anchor.point,
        relativeTo = relativeTo,
        relativePoint = anchor.relativePoint,
        offsetX = anchor.offsetX,
        offsetY = anchor.offsetY,
    }
end

--- A bar's place as the layout has it now, copied: Edit Mode changes its
-- own table in place as the bar is dragged.
local function placeOf(bar)
    local info = bar.systemInfo
    return {
        default = info.isInDefaultPosition and true or false,
        anchor = copyAnchor(info.anchorInfo),
        anchor2 = copyAnchor(info.anchorInfo2),
    }
end

local function sameAnchor(a, b)
    if not (a and b) then
        return a == b
    end
    return a.point == b.point and a.relativeTo == b.relativeTo and a.relativePoint == b.relativePoint
        and math.abs(a.offsetX - b.offsetX) < 0.01 and math.abs(a.offsetY - b.offsetY) < 0.01
end

--- The game puts a bar in its default place itself, wherever its anchor says.
local function samePlace(a, b)
    if a.default and b.default then
        return true
    end
    return a.default == b.default and sameAnchor(a.anchor, b.anchor) and sameAnchor(a.anchor2, b.anchor2)
end

--- In the stack along the bottom or down the right, which the game lays out
-- itself: only it can put a bar back in.
local function stacked(bar)
    local util = EditModeUtil
    if not util then
        return false
    end
    return (util.IsBottomAnchoredActionBar and util:IsBottomAnchoredActionBar(bar))
        or (util.IsRightAnchoredActionBar and util:IsRightAnchoredActionBar(bar))
        or false
end

local function savePoints(bar)
    local points = {}
    for index = 1, (bar.GetNumPoints and bar:GetNumPoints() or 1) do
        local point = { bar:GetPoint(index) }
        if #point == 0 then
            break
        end
        points[#points + 1] = point
    end
    return points
end

local function clearPoints(bar)
    (bar.ClearAllPointsBase or bar.ClearAllPoints)(bar)
end

local function setPoint(bar, ...)
    (bar.SetPointBase or bar.SetPoint)(bar, ...)
end

local function restore(bar)
    local points = original[bar]
    if not points then
        return
    end
    moving = true
    clearPoints(bar)
    for _, point in ipairs(points) do
        setPoint(bar, unpack(point))
    end
    moving = false
    original[bar] = nil
end

--- Anchored as Edit Mode anchors it, its offsets in the bar's own scale. The
-- client refuses an anchor that would loop, as one can when this screen's
-- place hangs off a bar the layout now hangs off this one: the layout's
-- place goes back then.
local function place(bar, wanted)
    if not original[bar] then
        original[bar] = savePoints(bar)
    end
    local scale = bar:GetScale()
    moving = true
    clearPoints(bar)
    local placed = pcall(function()
        for _, anchor in ipairs({ wanted.anchor, wanted.anchor2 }) do
            setPoint(bar, anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.offsetX / scale, anchor.offsetY / scale)
        end
    end)
    moving = false
    if not placed then
        restore(bar)
    end
end

local applySoon

local function hookBar(bar)
    if hookedBars[bar] or not hooksecurefunc then
        return
    end
    hookedBars[bar] = true
    -- The game putting the layout's place back: that is the one to give back
    -- now, and this screen's goes back over it.
    hooksecurefunc(bar, "SetPoint", function()
        if not moving then
            original[bar] = nil
            applySoon()
        end
    end)
end

--- Each bar where this screen has it. A bar this screen has not seen under
-- this layout takes the layout's place, and keeps it from now on.
local function apply()
    if not ns.db or editModeOpen() then
        return
    end
    if InCombatLockdown() then
        pending = true
        return
    end

    local places = screenPlaces()
    for _, bar in ipairs(bars()) do
        hookBar(bar)
        local name = bar:GetName()
        local layout = placeOf(bar)
        if places and not places[name] then
            places[name] = layout
        end
        local wanted = places and places[name]
        if ns.db.ui.barsPerScreen and wanted and wanted.anchor
            and not samePlace(wanted, layout) and not (wanted.default and stacked(bar)) then
            place(bar, wanted)
        else
            restore(bar)
        end
    end
end

ns.ApplyActionBars = apply

--- Once, on the next frame: the game lays the bars out in bursts.
applySoon = function()
    if queued then
        return
    end
    queued = true
    C_Timer.After(0, function()
        queued = false
        apply()
    end)
end

local function noteBars()
    noted = {}
    for _, bar in ipairs(bars()) do
        noted[bar:GetName()] = placeOf(bar)
    end
end

--- Edit Mode saved: a bar the player moved since it opened is in this
-- screen's place from now on.
local function recordBars()
    local places = noted and screenPlaces()
    if not places then
        return
    end
    for _, bar in ipairs(bars()) do
        local name = bar:GetName()
        local now = placeOf(bar)
        if noted[name] and not samePlace(now, noted[name]) then
            places[name] = now
        end
    end
    noteBars()
end

local hooked = false

local function hook()
    if hooked then
        return
    end
    hooked = true
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", noteBars)
        EventRegistry:RegisterCallback("EditMode.SavedLayouts", recordBars)
        EventRegistry:RegisterCallback("EditMode.Exit", function() noted = nil end)
    end
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
        EditModeManagerFrame:HookScript("OnHide", applySoon)
    end
end

ns.RegisterSetting({
    store = "ui",
    key = "barsPerScreen",
    type = "checkbox",
    section = "layout",
    column = 2,
    name = "Keep the action bars' places for each screen",
    tooltip = "Where you last saved each bar in Edit Mode on this screen. Moving one on another screen leaves this one's alone.",
    onChange = apply,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
-- Not on every client; registering a name a client lacks raises.
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            pending = false
            apply()
        end
        return
    end
    hook()
    applySoon()
end)
