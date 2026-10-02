local addonName, ns = ...

-- The main chat box, kept a few pixels over the action bars under it. The
-- game saves where the chat box goes to the account, so one placed right on a
-- laptop sits wrong on a desktop. Here only its height on the screen is
-- decided: its bottom edge goes the gap over the highest bar beneath it, which
-- for a druid is the bear and cat form bar. Left and right stay where the
-- game's layout put them, and its size is left alone.

ns.AddDefaults({
    ui = {
        chatAboveBars = true,
        chatGap = 4,
    },
})

-- The bars that can sit under the chat box, by every name the clients this
-- loads on give them. Only the ones shown and under it count.
local BARS = {
    "MainActionBar", "MainMenuBar",
    "MultiBarBottomLeft", "MultiBarBottomRight",
    "StanceBar", "StanceBarFrame",
    "PetActionBar", "PetActionBarFrame",
}

-- The client's Lua has it global; a newer Lua keeps it in table.
local unpack = unpack or table.unpack

-- True while this file moves the chat box, so the hook on its SetPoint does
-- not take our own move for the game's.
local moving = false
local queued = false
-- The game's own points, kept from the first move so turning this off can
-- give them back.
local original

local function chatFrame()
    return ChatFrame1
end

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

--- The top of the highest shown bar under the chat box, in screen pixels.
-- A bar counts as under it when the two overlap left to right.
local function highestBarTop(left, right)
    local highest
    for _, name in ipairs(BARS) do
        local frame = _G[name]
        if type(frame) == "table" and frame.IsShown and frame:IsShown() and frame.GetTop then
            local scale = frame:GetEffectiveScale()
            local top, barLeft, barRight = frame:GetTop(), frame:GetLeft(), frame.GetRight and frame:GetRight()
            if top and barLeft and barRight
                and barLeft * scale < right and barRight * scale > left then
                top = top * scale
                if not highest or top > highest then
                    highest = top
                end
            end
        end
    end
    return highest
end

local function restore()
    local frame = chatFrame()
    if frame and original then
        setPoints(frame, original)
        original = nil
    end
end

--- Put the chat box's bottom the gap over the bars, its left edge where it is.
local function apply()
    local frame = chatFrame()
    if not frame or not ns.db then
        return
    end

    if not ns.db.ui.chatAboveBars then
        restore()
        return
    end
    -- Edit Mode is where the player drags it; left alone until it closes.
    if editModeOpen() then
        return
    end

    local scale = frame:GetEffectiveScale()
    local left, right = frame:GetLeft(), frame.GetRight and frame:GetRight()
    if not (left and right) then
        return
    end
    local barTop = highestBarTop(left * scale, right * scale)
    if not barTop then
        return
    end

    -- Every number in the chat box's own scale.
    local uiScale = UIParent:GetEffectiveScale()
    local uiLeft = (UIParent:GetLeft() or 0) * uiScale
    local uiBottom = (UIParent:GetBottom() or 0) * uiScale
    -- The box you type in hangs under the chat box and moves with it, so the
    -- gap is kept under whichever reaches lower.
    local below = 0
    local editBox = ChatFrame1EditBox
    local bottom = frame:GetBottom()
    local editBottom = editBox and editBox.GetBottom and editBox:GetBottom()
    if bottom and editBottom then
        below = math.max(0, bottom * scale - editBottom * editBox:GetEffectiveScale())
    end

    local x = left - uiLeft / scale
    local y = (barTop + ns.db.ui.chatGap * uiScale + below - uiBottom) / scale

    if not original then
        original = savePoints(frame)
    end
    setPoints(frame, { { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y } })
end

ns.ApplyChatBox = apply

--- Once, on the next frame: the game moves the chat box and the bars in
-- bursts, and their edges are only right once it has finished.
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
    local frame = chatFrame()
    if hooked or not frame or not hooksecurefunc then
        return
    end
    hooked = true

    hooksecurefunc(frame, "SetPoint", function()
        if not moving then
            applySoon()
        end
    end)
    -- A bar appearing, going or moving: the druid's form bar comes and goes
    -- with the forms learned, the pet bar with the pet.
    for _, name in ipairs(BARS) do
        local bar = _G[name]
        if type(bar) == "table" and bar.HookScript then
            bar:HookScript("OnShow", applySoon)
            bar:HookScript("OnHide", applySoon)
            if bar.SetPoint then
                hooksecurefunc(bar, "SetPoint", applySoon)
            end
        end
    end
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
        EditModeManagerFrame:HookScript("OnHide", applySoon)
    end
end

ns.RegisterSetting({
    store = "ui",
    key = "chatAboveBars",
    type = "checkbox",
    section = "layout",
    column = 2,
    name = "Keep the chat box over the action bars",
    tooltip = "The same gap on every screen. Left and right, and its size, stay as you set them.",
    onChange = apply,
})

ns.RegisterSetting({
    store = "ui",
    key = "chatGap",
    type = "slider",
    parent = "ui.chatAboveBars",
    section = "layout",
    column = 2,
    name = "Gap over the action bars",
    min = 0,
    max = 40,
    onChange = apply,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
-- Not on every client; registering a name a client lacks raises.
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function()
    hook()
    applySoon()
end)
