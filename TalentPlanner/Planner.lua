local addonName, ns = ...

-- The planner: the class's three trees side by side in the game's grid, a
-- click to add a point and a right-click to take one off, and a bar over
-- them with the plan menu, the count, Undo, Clear, Export, Import and Learn
-- next. Also the small text box those last ones and the menu open.

local Planner = {}
ns.Planner = Planner

ns.AddDefaults({
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
})

local ICON = 32
local CELL_W, CELL_H = 50, 58 -- the icon, the count and the level under it
local TREE_GAP = 20
local PADDING = 18
local TOP = 92 -- the title bar, the button bar and the tree names
local BOTTOM = 36 -- the status line
local LOGO = 16 -- the glyph before the name, sized to the title bar
local LOGO_GAP = 6
local MIN_TIERS, MIN_COLUMNS = 7, 4

local HINT = "Left-click a talent to add a point, right-click to take one off."
local RED = { 1, 0.38, 0.38 }
local WHITE = { 1, 1, 1 }
local GOLD, GREEN, GREY = { 1, 0.82, 0 }, { 0.25, 1, 0.25 }, { 0.6, 0.6, 0.6 }

local function paint(text, colour)
    text:SetTextColor(colour[1], colour[2], colour[3])
end

local frame, dialog

--- CreateFrame with a template, or without it on a client that lacks it.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

-- The window's frame, as BossLoot's and LFGBoard's: the options window's
-- own, the name in its title bar and its red X, so this reads as one of the
-- game's windows. On a client without it, the dialog border, a name and a
-- close button of our own. Solid either way: the options window's
-- background lets the world show through, which the trees cannot bear.
local function createWindowFrame(name, titleText)
    local ok, made = pcall(CreateFrame, "Frame", name, UIParent, "SettingsFrameTemplate")
    if not (ok and made) then
        made = createFrame("Frame", name, UIParent, "BackdropTemplate")
    end
    local native = made.NineSlice and made.NineSlice.Text and made.ClosePanelButton and made.Bg

    if native then
        -- On the game's background, so under its border and title bar too.
        made.background = made.Bg:CreateTexture(nil, "BACKGROUND", nil, 7)
        made.background:SetAllPoints(made.Bg)
        made.title = made.NineSlice.Text
        made.title:ClearAllPoints()
        made.title:SetPoint("TOP", made, "TOP", (LOGO + LOGO_GAP) / 2, -5)
        made.close = made.ClosePanelButton
    else
        made.background = made:CreateTexture(nil, "BACKGROUND", nil, -8)
        made.background:SetPoint("TOPLEFT", made, "TOPLEFT", 4, -4)
        made.background:SetPoint("BOTTOMRIGHT", made, "BOTTOMRIGHT", -4, 4)
        if made.SetBackdrop then
            made:SetBackdrop({
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        made.title = made:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        made.title:SetPoint("TOP", made, "TOP", (LOGO + LOGO_GAP) / 2, -14)
        made.close = createFrame("Button", nil, made, "UIPanelCloseButton")
        made.close:SetPoint("TOPRIGHT", made, "TOPRIGHT", -4, -4)
        if not (made.close.GetNormalTexture and made.close:GetNormalTexture()) then
            made.close:SetText("X")
        end
    end
    made.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    made.title:SetText(titleText)

    -- The glyph alone, as the minimap button shows it, before the name: the
    -- AddOns list icon carries a square tile that reads as a sticker here.
    made.logo = (native and made.NineSlice or made):CreateTexture(nil, "OVERLAY")
    made.logo:SetSize(LOGO, LOGO)
    made.logo:SetPoint("RIGHT", made.title, "LEFT", -LOGO_GAP, 0)
    made.logo:SetTexture("Interface\\AddOns\\TalentPlanner\\minimap")

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    made.close:SetScript("OnClick", function()
        made:Hide()
    end)

    made:SetFrameStrata("HIGH")
    made:SetClampedToScreen(true)
    made:SetMovable(true)
    made:EnableMouse(true)
    made:RegisterForDrag("LeftButton")
    made:SetScript("OnDragStart", made.StartMoving)
    table.insert(UISpecialFrames, name)
    return made
end

local function button(parent, label, width, onClick)
    local made = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    made:SetSize(width, 22)
    made:SetText(label)
    made:SetScript("OnClick", onClick)
    return made
end

--------------------------------------------------------------------------------
-- The text box: export, import, a name, or a yes-or-no
--------------------------------------------------------------------------------

local DIALOG_W, DIALOG_H = 380, 150

local function createDialog()
    dialog = createWindowFrame("TalentPlannerDialog", "Talent Planner")
    dialog:SetSize(DIALOG_W, DIALOG_H)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

    dialog.text = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.text:SetPoint("TOPLEFT", dialog, "TOPLEFT", PADDING, -36)
    dialog.text:SetWidth(DIALOG_W - PADDING * 2)
    dialog.text:SetJustifyH("LEFT")

    dialog.box = createFrame("EditBox", nil, dialog, "InputBoxTemplate")
    dialog.box:SetSize(DIALOG_W - PADDING * 2 - 8, 24)
    dialog.box:SetPoint("TOPLEFT", dialog, "TOPLEFT", PADDING + 6, -70)
    dialog.box:SetAutoFocus(false)
    if dialog.box.SetFontObject and not dialog.box.Left then
        -- Without the template's art the box would be invisible text on dark.
        pcall(dialog.box.SetFontObject, dialog.box, "ChatFontNormal")
    end

    dialog.accept = button(dialog, "Okay", 110, function()
        Planner.AcceptDialog()
    end)
    dialog.accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 16)
    dialog.cancel = button(dialog, "Cancel", 110, function()
        dialog:Hide()
    end)
    dialog.cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 16)

    dialog.box:SetScript("OnEnterPressed", function()
        Planner.AcceptDialog()
    end)
    dialog.box:SetScript("OnEscapePressed", function()
        dialog:Hide()
    end)
    dialog:SetScript("OnHide", function()
        dialog.box:ClearFocus()
    end)
    dialog:Hide()
end

--- Open the box. `options`: title, text, value (nil for no edit box),
-- accept (the button's word), cancel (false for no Cancel), onAccept(text)
-- returning true to close or false and why to stay open.
function Planner.ShowDialog(options)
    if not dialog then
        createDialog()
    end
    dialog.options = options
    dialog.title:SetText(options.title or "Talent Planner")
    dialog.text:SetText(options.text or "")
    paint(dialog.text, WHITE)
    dialog.accept:SetText(options.accept or "Okay")
    dialog.cancel:SetShown(options.cancel ~= false)

    local editing = options.value ~= nil
    dialog.box:SetShown(editing)
    dialog:Show()
    if editing then
        dialog.box:SetText(options.value)
        dialog.box:HighlightText()
        dialog.box:SetFocus()
    end
    return dialog
end

function Planner.AcceptDialog()
    local options = dialog and dialog.options
    if not options then
        return
    end
    if not options.onAccept then
        dialog:Hide()
        return
    end
    local ok, why = options.onAccept(dialog.box:IsShown() and dialog.box:GetText() or nil)
    if ok then
        dialog:Hide()
    else
        dialog.text:SetText(why or "That did not work.")
        paint(dialog.text, RED)
    end
end

function Planner.Dialog()
    return dialog
end

--------------------------------------------------------------------------------
-- The plan menu
--------------------------------------------------------------------------------

local function askNewName()
    Planner.ShowDialog({
        title = "New plan", text = "Name the new plan:", value = "", accept = "Create",
        onAccept = ns.Plans.New,
    })
end

local function askRename()
    local _, name = ns.Plans.Active()
    Planner.ShowDialog({
        title = "Rename plan", text = "A new name for " .. name .. ":", value = name, accept = "Rename",
        onAccept = ns.Plans.Rename,
    })
end

local function askDelete()
    local _, name = ns.Plans.Active()
    Planner.ShowDialog({
        title = "Delete plan", text = "Delete the plan " .. name .. "? This cannot be undone.", accept = "Delete",
        onAccept = function()
            ns.Plans.Delete()
            return true
        end,
    })
end

local ACTIONS = {
    { text = "New plan...", run = askNewName },
    { text = "Rename...", run = askRename },
    { text = "Delete...", run = askDelete },
}

local menuFrame

--- The plans to pick from and what can be done to them, in the client's own
-- menu: MenuUtil on modern frames, EasyMenu on older ones. With neither,
-- the selector steps through the plans and the rest is /tp new, rename and
-- delete.
function Planner.OpenMenu(owner)
    local _, active = ns.Plans.Active()
    local names = ns.Plans.Names()

    if MenuUtil and MenuUtil.CreateContextMenu then
        local shown = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            if root.CreateTitle then
                root:CreateTitle("Plans")
            end
            for _, name in ipairs(names) do
                if root.CreateRadio then
                    root:CreateRadio(name, function(value) return value == active end, ns.Plans.Select, name)
                else
                    root:CreateButton((name == active and "> " or "") .. name, function()
                        ns.Plans.Select(name)
                    end)
                end
            end
            if root.CreateDivider then
                root:CreateDivider()
            end
            for _, action in ipairs(ACTIONS) do
                root:CreateButton(action.text, action.run)
            end
        end)
        if shown then
            return
        end
    end

    if EasyMenu then
        local list = { { text = "Plans", isTitle = true, notCheckable = true } }
        for _, name in ipairs(names) do
            list[#list + 1] = {
                text = name, checked = name == active,
                func = function() ns.Plans.Select(name) end,
            }
        end
        for _, action in ipairs(ACTIONS) do
            list[#list + 1] = { text = action.text, notCheckable = true, func = action.run }
        end
        menuFrame = menuFrame or createFrame("Frame", "TalentPlannerMenu", UIParent, "UIDropDownMenuTemplate")
        if pcall(EasyMenu, list, menuFrame, owner, 0, 0, "MENU") then
            return
        end
    end

    -- No menu: the next plan along.
    local nextName = names[1]
    for index, name in ipairs(names) do
        if name == active then
            nextName = names[index % #names + 1]
        end
    end
    if nextName then
        ns.Plans.Select(nextName)
    end
end

--------------------------------------------------------------------------------
-- The trees
--------------------------------------------------------------------------------

--- The line under the trees: why something was refused, or the hint.
local function setStatus(text, refused)
    frame.status:SetText(text or HINT)
    paint(frame.status, refused and RED or WHITE)
end

local function showTooltip(talentButton)
    if not GameTooltip then
        return
    end
    local tab, index = talentButton.tab, talentButton.index
    GameTooltip:SetOwner(talentButton, "ANCHOR_RIGHT")
    local shown = pcall(GameTooltip.SetTalent, GameTooltip, tab, index)
    if not shown then
        GameTooltip:SetText(talentButton.name or "")
    end
    local levels = ns.Plan.Levels(ns.Plans.Active().points, tab, index)
    if #levels > 0 then
        GameTooltip:AddLine("Planned at levels " .. table.concat(levels, ", "), 0.25, 1, 0.25)
    else
        GameTooltip:AddLine("Not in the plan.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function clickTalent(talentButton, mouseButton)
    local trees = ns.Trees.Read()
    if not trees then
        Planner.Refresh()
        return
    end
    local plan = ns.Plans.Active()
    local ok, result
    if mouseButton == "RightButton" then
        ok, result = ns.Plan.Remove(trees, plan.points, talentButton.tab, talentButton.index)
    else
        ok, result = ns.Plan.Add(trees, plan.points, talentButton.tab, talentButton.index)
    end
    ns.Changed()
    setStatus(not ok and result or nil, not ok)
    if GameTooltip and GameTooltip:GetOwner() == talentButton then
        showTooltip(talentButton)
    end
end

local function makeTalentButton(tree, tab, index)
    local made = CreateFrame("Button", nil, tree.panel)
    made:SetSize(ICON, ICON)
    made:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    made.tab, made.index = tab, index

    made.icon = made:CreateTexture(nil, "ARTWORK")
    made.icon:SetAllPoints(made)

    made.count = made:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    made.count:SetPoint("TOP", made, "BOTTOM", 0, -1)
    made.level = made:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    made.level:SetPoint("TOP", made.count, "BOTTOM", 0, -1)

    made:SetScript("OnClick", clickTalent)
    made:SetScript("OnEnter", showTooltip)
    made:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return made
end

local function cellCentre(talent)
    return (talent.column - 1) * CELL_W + ICON / 2, -((talent.tier - 1) * CELL_H + ICON / 2)
end

-- A prerequisite as a line: along the prerequisite's row, then down to the
-- talent. Simple lines, under the icons.
local function drawLine(tree, from, to, lit)
    local x1, y1 = cellCentre(from)
    local x2, y2 = cellCentre(to)
    local r, g, b = 0.45, 0.45, 0.45
    if lit then
        r, g, b = 1, 0.82, 0
    end

    local function segment(x, y, width, height)
        tree.lineCount = tree.lineCount + 1
        local line = tree.lines[tree.lineCount]
        if not line then
            line = tree.panel:CreateTexture(nil, "BACKGROUND")
            tree.lines[tree.lineCount] = line
        end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", tree.panel, "TOPLEFT", x, y)
        line:SetSize(math.max(width, 2), math.max(height, 2))
        line:SetColorTexture(r, g, b, 1)
        line:Show()
    end

    if x1 ~= x2 then
        segment(math.min(x1, x2), y1 + 1, math.abs(x2 - x1), 2)
    end
    if y1 ~= y2 then
        segment(x2 - 1, math.max(y1, y2), 2, math.abs(y2 - y1))
    end
end

local function treeFor(tab)
    local tree = frame.trees[tab]
    if not tree then
        tree = { buttons = {}, lines = {}, lineCount = 0 }
        tree.panel = CreateFrame("Frame", nil, frame)
        tree.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tree.header:SetPoint("BOTTOM", tree.panel, "TOP", 0, 8)
        frame.trees[tab] = tree
    end
    return tree
end

local function drawTrees(trees, points)
    local tiers, columns = MIN_TIERS, MIN_COLUMNS
    for _, tree in ipairs(trees) do
        for _, talent in pairs(tree.talents) do
            tiers = math.max(tiers, talent.tier)
            columns = math.max(columns, talent.column)
        end
    end
    local treeWidth = (columns - 1) * CELL_W + ICON
    frame:SetSize(PADDING * 2 + #trees * treeWidth + (#trees - 1) * TREE_GAP, TOP + tiers * CELL_H + BOTTOM)

    for tab, data in ipairs(trees) do
        local tree = treeFor(tab)
        tree.panel:ClearAllPoints()
        tree.panel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + (tab - 1) * (treeWidth + TREE_GAP), -TOP)
        tree.panel:SetSize(treeWidth, tiers * CELL_H)
        tree.panel:Show()
        tree.header:SetText(data.name)
        tree.header:Show()

        tree.lineCount = 0
        for index, talent in pairs(data.talents) do
            local made = tree.buttons[index] or makeTalentButton(tree, tab, index)
            tree.buttons[index] = made
            made.name = talent.name
            local x, y = cellCentre(talent)
            made:ClearAllPoints()
            made:SetPoint("CENTER", tree.panel, "TOPLEFT", x, y)
            made.icon:SetTexture(talent.icon)

            local planned = ns.Plan.Count(points, tab, index)
            local colour = planned >= talent.maxRank and GOLD or (planned > 0 and GREEN or GREY)
            made.count:SetText(planned .. "/" .. talent.maxRank)
            paint(made.count, colour)
            local levels = ns.Plan.Levels(points, tab, index)
            made.level:SetText(levels[1] and tostring(levels[1]) or "")
            -- Dimmed while it could not take a point yet and has none.
            if made.icon.SetDesaturated then
                made.icon:SetDesaturated(planned == 0 and not ns.Plan.Check(trees, points, tab, index))
            end
            made:Show()

            local needed = talent.prereq and data.talents[talent.prereq]
            if needed then
                drawLine(tree, needed, talent, ns.Plan.Count(points, tab, talent.prereq) >= needed.maxRank)
            end
        end
        for index, made in pairs(tree.buttons) do
            if not data.talents[index] then
                made:Hide()
            end
        end
        for index = tree.lineCount + 1, #tree.lines do
            tree.lines[index]:Hide()
        end
    end
    for tab, tree in pairs(frame.trees) do
        if not trees[tab] then
            tree.panel:Hide()
            tree.header:Hide()
        end
    end
end

function Planner.Refresh()
    if not (frame and frame:IsShown()) then
        return
    end
    local plan, name = ns.Plans.Active()
    frame.selector:SetText(name)
    frame.total:SetText(#plan.points .. "/" .. ns.Plan.MAX)
    frame.learn:SetShown(ns.db.learn and type(LearnTalent) == "function")

    local trees, missing = ns.Trees.Read()
    if not trees then
        for _, tree in pairs(frame.trees) do
            tree.panel:Hide()
            tree.header:Hide()
        end
        frame.message:SetText(ns.Trees.Unreadable(missing))
        frame.message:Show()
        return
    end
    frame.message:Hide()
    drawTrees(trees, plan.points)

    -- A saved plan the client no longer agrees with: say where it breaks.
    local ok, bad, why = ns.Plan.Validate(trees, plan.points)
    if not ok then
        setStatus(ns.Plan.Describe(trees, bad, plan.points[bad]) .. ": " .. why, true)
    end
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function clearPlan()
    local plan, name = ns.Plans.Active()
    if #plan.points == 0 then
        return
    end
    Planner.ShowDialog({
        title = "Clear plan", text = "Take every point out of " .. name .. "?", accept = "Clear",
        onAccept = function()
            local current = ns.Plans.Active()
            for index = #current.points, 1, -1 do
                current.points[index] = nil
            end
            ns.Changed()
            return true
        end,
    })
end

local function exportPlan()
    local text, why = ns.Export()
    Planner.ShowDialog({
        title = "Export plan", text = text and "Ctrl+C to copy:" or why, value = text or "",
        accept = "Close", cancel = false,
    })
end

local function importPlan()
    Planner.ShowDialog({
        title = "Import plan", text = "Paste a plan (Ctrl+V):", value = "", accept = "Import",
        onAccept = ns.Import,
    })
end

local function learnNext()
    local ok, why = ns.Reminder.LearnNext()
    if ok then
        setStatus(nil)
    else
        setStatus(why, true)
    end
end

local function create()
    frame = createWindowFrame("TalentPlannerFrame", "Talent Planner")
    frame:SetScript("OnDragStop", savePosition)
    local saved = ns.db.window
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetSize(640, 520)
    frame.trees = {}

    frame.selector = button(frame, "", 130, function(self)
        Planner.OpenMenu(self)
    end)
    frame.selector:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -32)

    frame.total = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.total:SetPoint("LEFT", frame.selector, "RIGHT", 10, 0)

    local x = -PADDING
    local function rightButton(label, width, onClick)
        local made = button(frame, label, width, onClick)
        made:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, -32)
        x = x - width - 4
        return made
    end
    frame.import = rightButton("Import", 64, importPlan)
    frame.export = rightButton("Export", 64, exportPlan)
    frame.clear = rightButton("Clear", 56, clearPlan)
    frame.undo = rightButton("Undo", 56, function()
        ns.Plan.Undo(ns.Plans.Active().points)
        setStatus(nil)
        ns.Changed()
    end)
    frame.learn = rightButton("Learn next", 90, learnNext)

    frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.message:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.message:SetWidth(440)
    frame.message:Hide()

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, 14)
    frame.status:SetJustifyH("LEFT")
    setStatus(nil)

    frame:SetScript("OnShow", function()
        setStatus(nil)
        Planner.Refresh()
    end)
    frame:Hide()
end

function Planner.Toggle()
    if not frame then
        create()
    end
    frame:SetShown(not frame:IsShown())
end

function Planner.Open()
    if not frame then
        create()
    end
    frame:Show()
end

function Planner.Frame()
    return frame
end

ns.OnChange(Planner.Refresh)
