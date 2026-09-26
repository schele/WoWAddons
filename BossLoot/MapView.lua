local addonName, ns = ...

-- Draws an instance's generated floor plan into a frame of any size, and a
-- numbered pin per boss that has a place. The same view serves the header's
-- inset and the full map.
--
-- The floor comes as runs: row, first column, length. Each run is one strip
-- of texture, so a whole instance is a few hundred strips rather than
-- thousands of squares. The outline is the floor grown by a cell each way,
-- drawn underneath in a lighter colour: only its rim shows.

local MapView = {}
ns.MapView = MapView

local FLOOR = { 0.36, 0.29, 0.19 }
local EDGE = { 0.77, 0.64, 0.43 }
local PIN = "Interface\\COMMON\\Indicator-Red"
local PIN_SELECTED = "Interface\\COMMON\\Indicator-Yellow"

--- How a map of cols by rows cells fits a width by height view: the size of
-- a cell, and the margins that centre the map.
function MapView.Layout(map, width, height)
    local scale = math.min(width / map.cols, height / map.rows)
    return scale, (width - map.cols * scale) / 2, (height - map.rows * scale) / 2
end

--- The floor grown by one cell each way, as runs. Worked out once per map.
function MapView.Outline(map)
    if map.outline then
        return map.outline
    end

    local spans = {}
    local runs = map.runs
    for i = 1, #runs, 3 do
        local row, first, length = runs[i], runs[i + 1], runs[i + 2]
        for r = row - 1, row + 1 do
            if r >= 0 and r < map.rows then
                spans[r] = spans[r] or {}
                table.insert(spans[r], { math.max(0, first - 1), math.min(map.cols, first + length + 1) })
            end
        end
    end

    local rows = {}
    for row in pairs(spans) do
        table.insert(rows, row)
    end
    table.sort(rows)

    local outline = {}
    for _, row in ipairs(rows) do
        local list = spans[row]
        table.sort(list, function(a, b) return a[1] < b[1] end)
        local start, finish = list[1][1], list[1][2]
        for k = 2, #list do
            if list[k][1] <= finish then
                finish = math.max(finish, list[k][2])
            else
                table.insert(outline, row); table.insert(outline, start); table.insert(outline, finish - start)
                start, finish = list[k][1], list[k][2]
            end
        end
        table.insert(outline, row); table.insert(outline, start); table.insert(outline, finish - start)
    end

    map.outline = outline
    return outline
end

function MapView.Create(parent, width, height, options)
    options = options or {}
    local view = CreateFrame("Button", nil, parent)
    view:SetSize(width, height)
    view.options = options
    view.floor = {}
    view.edges = {}
    view.pins = {}

    view.background = view:CreateTexture(nil, "BACKGROUND")
    view.background:SetAllPoints()
    view.background:SetColorTexture(0.06, 0.045, 0.03, 1)

    return view
end

local function pin(view, index)
    local button = view.pins[index]
    if button then
        return button
    end

    local size = view.options.pinSize or 16
    button = CreateFrame("Button", nil, view)
    button:SetSize(size, size)
    button:SetFrameLevel(view:GetFrameLevel() + 2)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)

    if view.options.onPinClick then
        button:SetScript("OnClick", function(self)
            view.options.onPinClick(self.boss)
        end)
    else
        -- The inset: a click on a pin is a click on the map, which opens it.
        button:EnableMouse(false)
    end

    view.pins[index] = button
    return button
end

-- One layer of strips from a run list, reusing the pool's textures.
local function drawStrips(view, pool, runs, layer, colour, scale, offsetX, offsetY)
    local count = 0
    for i = 1, #runs, 3 do
        count = count + 1
        local strip = pool[count]
        if not strip then
            strip = view:CreateTexture(nil, layer)
            pool[count] = strip
        end
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", view, "TOPLEFT", offsetX + runs[i + 1] * scale, -(offsetY + runs[i] * scale))
        strip:SetSize(runs[i + 2] * scale, scale)
        strip:SetColorTexture(colour[1], colour[2], colour[3], 1)
        strip:Show()
    end
    for i = count + 1, #pool do
        pool[i]:Hide()
    end
end

local function hideAll(pool)
    for _, item in ipairs(pool) do
        item:Hide()
    end
end

function MapView.Show(view, instance, selected)
    hideAll(view.pins)

    local map = instance and instance.map
    if not map then
        hideAll(view.floor)
        hideAll(view.edges)
        view.shownMap = nil
        return
    end

    local width, height = view:GetWidth(), view:GetHeight()
    local scale, offsetX, offsetY = MapView.Layout(map, width, height)

    -- The strips only change with the map or the view's size; a redraw of the
    -- same map (a new boss picked, an item arrived) touches just the pins.
    if view.shownMap ~= map or view.shownWidth ~= width or view.shownHeight ~= height then
        drawStrips(view, view.edges, MapView.Outline(map), "BORDER", EDGE, scale, offsetX, offsetY)
        drawStrips(view, view.floor, map.runs, "ARTWORK", FLOOR, scale, offsetX, offsetY)
        view.shownMap, view.shownWidth, view.shownHeight = map, width, height
    end

    local count = 0
    for bossIndex, boss in ipairs(instance.bosses or {}) do
        if boss.pin then
            count = count + 1
            local button = pin(view, count)
            button.boss = bossIndex
            button.selected = bossIndex == selected
            button.text:SetText(tostring(bossIndex))
            button.icon:SetTexture(button.selected and PIN_SELECTED or PIN)
            button:ClearAllPoints()
            button:SetPoint("CENTER", view, "TOPLEFT",
                offsetX + boss.pin[1] * map.cols * scale, -(offsetY + boss.pin[2] * map.rows * scale))
            button:Show()
        end
    end
end
