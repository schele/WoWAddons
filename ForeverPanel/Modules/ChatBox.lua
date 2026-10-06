local addonName, ns = ...

-- The main chat box, where and how big it was last saved in Edit Mode on this
-- screen. The game saves both to the account, so one placed right on a laptop
-- sits wrong on a desktop; here each screen keeps its own. On a screen it was
-- never placed on, the game's layout has it.

ns.AddDefaults({
    ui = {
        chatPerScreen = true,
        -- By screen, as "3840x2160": its width and height, and its bottom
        -- left corner from the screen's in its own units.
        chatScreens = {},
    },
})

-- The client's Lua has it global; a newer Lua keeps it in table.
local unpack = unpack or table.unpack

-- True while this file moves or sizes the chat box, so the hooks on its
-- SetPoint and SetSize do not take our own change for the game's.
local moving = false
local queued = false
-- The game's own points, kept from our first move since the game last set
-- them, so turning this off can give them back.
local original
-- The layout's size, kept from our first resize the same way.
local originalSize
-- Its place and size when Edit Mode opened, so a save that changed them can
-- be told from one that changed something else.
local noted

local function chatFrame()
    return ChatFrame1
end

local function screenKey()
    local width, height = GetPhysicalScreenSize()
    if width and height then
        return width .. "x" .. height
    end
end

--- Its size in whole units, as Edit Mode saves it.
local function sizeOf(frame)
    return math.floor(frame:GetWidth()), math.floor(frame:GetHeight())
end

local function setSize(frame, width, height)
    moving = true
    frame:SetSize(width, height)
    moving = false
end

local function restoreSize()
    local frame = chatFrame()
    if frame and originalSize then
        setSize(frame, originalSize[1], originalSize[2])
        originalSize = nil
    end
end

local function resize(frame, width, height)
    local currentWidth, currentHeight = sizeOf(frame)
    if currentWidth == width and currentHeight == height then
        return
    end
    if not originalSize then
        originalSize = { frame:GetWidth(), frame:GetHeight() }
    end
    setSize(frame, width, height)
end

--- Where it is and how big, its corner from the screen's bottom left in its
-- own units, as SetPoint takes it. Nil while it is not laid out.
local function snapshot(frame)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not (left and bottom) then
        return
    end
    local scale = frame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local width, height = sizeOf(frame)
    return {
        width = width,
        height = height,
        x = left - (UIParent:GetLeft() or 0) * uiScale / scale,
        y = bottom - (UIParent:GetBottom() or 0) * uiScale / scale,
    }
end

--- The same place and size, give or take what Edit Mode rounds away.
local function same(a, b)
    return a.width == b.width and a.height == b.height
        and math.abs(a.x - b.x) < 0.5 and math.abs(a.y - b.y) < 0.5
end

local function noteScreen()
    local frame = chatFrame()
    noted = frame and snapshot(frame)
end

--- Edit Mode saved: a place or size the player gave the chat box since it
-- opened is this screen's from now on. The layout has them too, so they are
-- the ones to give back as well.
local function recordScreen()
    local frame = chatFrame()
    local key = screenKey()
    local now = frame and snapshot(frame)
    if not (now and noted and key and ns.db) or same(now, noted) then
        return
    end
    ns.db.ui.chatScreens[key] = now
    noted = snapshot(frame)
    original, originalSize = nil, nil
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

--- Its bottom left corner at x, y from the screen's, in its own units.
local function place(frame, x, y)
    if not original then
        original = savePoints(frame)
    end
    setPoints(frame, { { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y } })
end

local function restore()
    local frame = chatFrame()
    if frame and original then
        setPoints(frame, original)
        original = nil
    end
end

--- Where and how big it was last saved on this screen. On a screen it was
-- never placed on, the layout's place and size.
local function apply()
    local frame = chatFrame()
    if not frame or not ns.db then
        return
    end
    -- Edit Mode is where the player drags and sizes it; left alone until it
    -- closes.
    if editModeOpen() then
        return
    end

    local ui = ns.db.ui
    local key = screenKey()
    local screen = ui.chatPerScreen and key and ui.chatScreens[key]
    if screen then
        resize(frame, screen.width, screen.height)
        place(frame, screen.x, screen.y)
        return
    end
    restoreSize()
    restore()
end

ns.ApplyChatBox = apply

--- Once, on the next frame: the game moves and sizes the chat box in bursts,
-- and its edges are only right once it has finished.
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

    -- The game putting the layout's place or size back: those are the ones
    -- to give back now, and ours go back over them.
    hooksecurefunc(frame, "SetPoint", function()
        if not moving then
            original = nil
            applySoon()
        end
    end)
    hooksecurefunc(frame, "SetSize", function()
        if not moving then
            originalSize = nil
            applySoon()
        end
    end)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", noteScreen)
        EventRegistry:RegisterCallback("EditMode.SavedLayouts", recordScreen)
        EventRegistry:RegisterCallback("EditMode.Exit", function() noted = nil end)
    end
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
        EditModeManagerFrame:HookScript("OnHide", applySoon)
    end
end

ns.RegisterSetting({
    store = "ui",
    key = "chatPerScreen",
    type = "checkbox",
    section = "layout",
    column = 2,
    name = "Keep the chat box's place and size for each screen",
    tooltip = "Where and how big you last saved it in Edit Mode on this screen. Another screen keeps its own.",
    onChange = apply,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
-- Not on every client; registering a name a client lacks raises.
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function()
    hook()
    applySoon()
end)
