local addonName, ns = ...

-- The player's portrait, kept a few pixels under the bar. The game saves where
-- the portrait goes to the account, measured in a way that lands it at a
-- different height on a screen of another shape, so one placed right on a
-- laptop overlaps the bar on a desktop. Here only its height is decided, from
-- the bar's bottom edge, on whatever screen this is; left and right stay where
-- the game's layout put them.

ns.AddDefaults({
    ui = {
        portraitBelowBar = true,
        portraitGap = 4,
    },
})

-- The client's Lua has it global; a newer Lua keeps it in table.
local unpack = unpack or table.unpack

-- True while this file moves the portrait, so the hook on its SetPoint does
-- not take our own move for the game's.
local moving = false
local queued = false
-- The game's own points, kept from the first move so turning this off can
-- give them back.
local original
-- A move the game refused during a fight, to make when it ends.
local pending = false

local function editModeOpen()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

local function savePoints(frame)
    local points = {}
    for index = 1, (frame.GetNumPoints and frame:GetNumPoints() or 1) do
        local point = { frame:GetPoint(index) }
        if #point == 0 then
            break
        end
        points[#points + 1] = point
    end
    return points
end

local function setPoints(frame, points)
    moving = true
    frame:ClearAllPoints()
    for _, point in ipairs(points) do
        frame:SetPoint(unpack(point))
    end
    moving = false
end

--- Where the bar's bottom edge is, in screen pixels.
local function barBottom()
    local bar = ForeverBar
    local bottom = bar and bar.GetBottom and bar:GetBottom()
    if not bottom then
        return nil
    end
    return bottom * bar:GetEffectiveScale()
end

local function restore()
    local frame = PlayerFrame
    if frame and original and not InCombatLockdown() then
        setPoints(frame, original)
        original = nil
    end
end

--- Put the portrait's top the gap under the bar, its left edge where it is.
local function apply()
    local frame = PlayerFrame
    if not frame or not ns.db then
        return
    end

    if not (ns.db.ui.portraitBelowBar and ns.db.bar.enabled) then
        restore()
        return
    end
    -- Edit Mode is where the player drags it; left alone until it closes.
    if editModeOpen() then
        return
    end
    if InCombatLockdown() then
        pending = true
        return
    end

    local bottom, left = barBottom(), frame:GetLeft()
    local uiTop = UIParent:GetTop()
    if not (bottom and left and uiTop) then
        return
    end

    -- Every number in the portrait's own scale, which Edit Mode can change.
    local scale = frame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local x = left - (UIParent:GetLeft() or 0) * uiScale / scale
    local top = bottom - ns.db.ui.portraitGap * uiScale
    local y = (top - uiTop * uiScale) / scale

    if not original then
        original = savePoints(frame)
    end
    setPoints(frame, { { "TOPLEFT", UIParent, "TOPLEFT", x, y } })
end

ns.ApplyPortrait = apply

--- Once, on the next frame: the game moves the portrait in bursts, and its
-- edges are only right once it has finished.
local function applySoon()
    if queued then
        return
    end
    queued = true
    C_Timer.After(0, function()
        queued = false
        apply()
    end)
end

local hooked = false

local function hook()
    if hooked or not PlayerFrame or not hooksecurefunc then
        return
    end
    hooked = true

    hooksecurefunc(PlayerFrame, "SetPoint", function()
        if not moving then
            applySoon()
        end
    end)
    if ns.Bar and ns.Bar.Update then
        hooksecurefunc(ns.Bar, "Update", applySoon)
    end
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
        EditModeManagerFrame:HookScript("OnHide", applySoon)
    end
end

ns.RegisterSetting({
    store = "ui",
    key = "portraitBelowBar",
    type = "checkbox",
    section = "layout",
    -- The left column is full; this would run off the bottom of the page.
    column = 2,
    name = "Keep the portrait under the bar",
    tooltip = "The same gap on every screen. Left and right stay where you put it.",
    onChange = apply,
})

ns.RegisterSetting({
    store = "ui",
    key = "portraitGap",
    type = "slider",
    parent = "ui.portraitBelowBar",
    section = "layout",
    column = 2,
    name = "Gap under the bar",
    min = 0,
    max = 40,
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
