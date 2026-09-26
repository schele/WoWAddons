local addonName, ns = ...

-- Draws an instance's generated floor plan into a frame of any size, with a
-- numbered pin per boss that has a place and a marker at the entrance. The
-- same view serves the header's inset and the full map; the full map also
-- writes each boss's name beside its pin, and zooms: the mouse wheel zooms
-- in on the cursor, a drag moves the map, a right-click shows it whole.
--
-- The floor comes as runs: row, first column, length. Each run is one strip
-- of texture, so a whole instance is a few hundred strips rather than
-- thousands of squares. Three layers give the walls some depth: the floor
-- grown by a cell (a light rim), the floor itself, and the floor shrunk by a
-- cell (a darker fill), so every room reads as sunk between raised edges.
--
-- Everything that moves with the map is drawn on the view's canvas. On the
-- inset the canvas is the view itself; on the full map it is the child of a
-- scroll frame, drawn as big as the zoom asks, of which the view shows part.

local MapView = {}
ns.MapView = MapView

MapView.MAX_ZOOM = 4

local EDGE = { 0.80, 0.68, 0.46 }
local FLOOR = { 0.44, 0.35, 0.22 }
local INNER = { 0.30, 0.24, 0.15 }
local BACKGROUND = { 0.06, 0.045, 0.03 }
local GOLD = { 1, 0.82, 0 }
local PIN = "Interface\\COMMON\\Indicator-Red"
local ENTRANCE = "Interface\\COMMON\\Indicator-Green"
-- A white disc: tinted gold behind a pin, it rings the picked boss.
local RING = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LABEL_HEIGHT = 12
-- A pin this far right gets its name on its left, so it stays on the map.
local LABEL_FLIP = 0.7
local ZOOM_STEP = 1.25
local HINT = "Scroll to zoom, drag to move, right-click for the whole map"

--- How a map of cols by rows cells fits a width by height view: the size of
-- a cell, and the margins that centre the map.
function MapView.Layout(map, width, height)
    local scale = math.min(width / map.cols, height / map.rows)
    return scale, (width - map.cols * scale) / 2, (height - map.rows * scale) / 2
end

-- A map's runs grouped by row: row -> { { first, afterLast }, ... }, sorted.
local function spansByRow(map)
    local spans = {}
    local runs = map.runs
    for i = 1, #runs, 3 do
        local row = runs[i]
        spans[row] = spans[row] or {}
        table.insert(spans[row], { runs[i + 1], runs[i + 1] + runs[i + 2] })
    end
    for _, list in pairs(spans) do
        table.sort(list, function(a, b) return a[1] < b[1] end)
    end
    return spans
end

local function appendRun(out, row, first, afterLast)
    table.insert(out, row)
    table.insert(out, first)
    table.insert(out, afterLast - first)
end

local function sortedRows(spans)
    local rows = {}
    for row in pairs(spans) do
        table.insert(rows, row)
    end
    table.sort(rows)
    return rows
end

--- The floor grown by one cell each way, as runs. Worked out once per map.
function MapView.Outline(map)
    if map.outline then
        return map.outline
    end

    local grown = {}
    for row, list in pairs(spansByRow(map)) do
        for r = row - 1, row + 1 do
            if r >= 0 and r < map.rows then
                grown[r] = grown[r] or {}
                for _, span in ipairs(list) do
                    table.insert(grown[r], { math.max(0, span[1] - 1), math.min(map.cols, span[2] + 1) })
                end
            end
        end
    end

    local outline = {}
    for _, row in ipairs(sortedRows(grown)) do
        local list = grown[row]
        table.sort(list, function(a, b) return a[1] < b[1] end)
        local first, afterLast = list[1][1], list[1][2]
        for k = 2, #list do
            if list[k][1] <= afterLast then
                afterLast = math.max(afterLast, list[k][2])
            else
                appendRun(outline, row, first, afterLast)
                first, afterLast = list[k][1], list[k][2]
            end
        end
        appendRun(outline, row, first, afterLast)
    end

    map.outline = outline
    return outline
end

-- Spans pulled in by a cell at each end; spans too short to survive go.
local function shrink(list)
    local out = {}
    for _, span in ipairs(list or {}) do
        if span[2] - span[1] > 2 then
            table.insert(out, { span[1] + 1, span[2] - 1 })
        end
    end
    return out
end

-- Where two sorted span lists overlap.
local function intersect(a, b)
    local out = {}
    local i, j = 1, 1
    while i <= #a and j <= #b do
        local first = math.max(a[i][1], b[j][1])
        local afterLast = math.min(a[i][2], b[j][2])
        if first < afterLast then
            table.insert(out, { first, afterLast })
        end
        if a[i][2] < b[j][2] then i = i + 1 else j = j + 1 end
    end
    return out
end

--- The floor shrunk by one cell each way, as runs: a cell whose eight
-- neighbours are all floor. Worked out once per map.
function MapView.Inner(map)
    if map.inner then
        return map.inner
    end

    local spans = spansByRow(map)
    local inner = {}
    for _, row in ipairs(sortedRows(spans)) do
        local kept = intersect(intersect(shrink(spans[row]), shrink(spans[row - 1])), shrink(spans[row + 1]))
        for _, span in ipairs(kept) do
            appendRun(inner, row, span[1], span[2])
        end
    end

    map.inner = inner
    return inner
end

-- Zooming ---------------------------------------------------------------

-- The cursor's place on the view, from its top left.
local function cursorOn(view)
    local x, y = GetCursorPosition()
    local scale = view:GetEffectiveScale()
    return x / scale - (view:GetLeft() or 0), (view:GetTop() or 0) - y / scale
end

-- Only pins in sight show: one scrolled out of sight could still be hovered.
local function showPinsInSight(view)
    if not view.options.zoom then
        return
    end
    local left, top = view:GetHorizontalScroll(), view:GetVerticalScroll()
    local right, bottom = left + view:GetWidth(), top + view:GetHeight()
    for i = 1, view.pinCount or 0 do
        local button = view.pins[i]
        button:SetShown(button.x >= left and button.x <= right and button.y >= top and button.y <= bottom)
    end
end

-- Scroll the canvas to show from (x, y), kept so the map fills the view.
local function scrollTo(view, x, y)
    local maxX = view.canvas:GetWidth() - view:GetWidth()
    local maxY = view.canvas:GetHeight() - view:GetHeight()
    view:SetHorizontalScroll(math.max(0, math.min(maxX, x)))
    view:SetVerticalScroll(math.max(0, math.min(maxY, y)))
    showPinsInSight(view)
end

local function setZoom(view, zoom)
    view.zoom = zoom
    if view.canvas ~= view then
        view.canvas:SetSize(view:GetWidth() * zoom, view:GetHeight() * zoom)
        if view.UpdateScrollChildRect then
            view:UpdateScrollChildRect()
        end
    end
end

--- Zoom by `factor`, between the whole map and MAX_ZOOM, keeping the spot at
-- (x, y) from the view's top left where it is.
function MapView.Zoom(view, factor, x, y)
    local zoom = math.max(1, math.min(MapView.MAX_ZOOM, view.zoom * factor))
    if zoom == view.zoom then
        return
    end
    local ratio = zoom / view.zoom
    local left = (view:GetHorizontalScroll() + x) * ratio - x
    local top = (view:GetVerticalScroll() + y) * ratio - y
    setZoom(view, zoom)
    MapView.Show(view, view.instance, view.selected)
    scrollTo(view, left, top)
end

--- Back to the whole map.
function MapView.ResetZoom(view)
    setZoom(view, 1)
    MapView.Show(view, view.instance, view.selected)
    scrollTo(view, 0, 0)
end

local function enableZoom(view)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:RegisterForDrag("LeftButton")

    view:SetScript("OnMouseWheel", function(self, delta)
        local x, y = cursorOn(self)
        MapView.Zoom(self, delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP, x, y)
    end)
    view:SetScript("OnDragStart", function(self)
        self.dragFrom = { cursorOn(self) }
    end)
    view:SetScript("OnDragStop", function(self)
        self.dragFrom = nil
    end)
    -- While dragged, the map follows the cursor.
    view:SetScript("OnUpdate", function(self)
        if not self.dragFrom then
            return
        end
        local x, y = cursorOn(self)
        scrollTo(self, self:GetHorizontalScroll() - (x - self.dragFrom[1]),
            self:GetVerticalScroll() - (y - self.dragFrom[2]))
        self.dragFrom = { x, y }
    end)
    view:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MapView.ResetZoom(self)
        end
    end)

    view.hint = view.overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.hint:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 8, 6)
    view.hint:SetText(HINT)
end

-- Drawing ---------------------------------------------------------------

function MapView.Create(parent, width, height, options)
    options = options or {}
    local view
    if options.zoom then
        view = CreateFrame("ScrollFrame", nil, parent)
        view.canvas = CreateFrame("Frame", nil, view)
        view.canvas:SetSize(width, height)
        view:SetScrollChild(view.canvas)
        -- Above the map and its pins, for what stays put: the hint, a title.
        view.overlay = CreateFrame("Frame", nil, view)
        view.overlay:SetAllPoints(view)
        view.overlay:SetFrameLevel(view.canvas:GetFrameLevel() + 5)
    else
        view = CreateFrame("Button", nil, parent)
        view.canvas = view
        view.overlay = view
    end
    view:SetSize(width, height)
    view.options = options
    view.zoom = 1
    view.edges = {}
    view.floor = {}
    view.inner = {}
    view.pins = {}
    view.labels = {}

    view.background = view:CreateTexture(nil, "BACKGROUND")
    view.background:SetAllPoints()
    view.background:SetColorTexture(BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 1)

    local canvas = view.canvas
    view.entrance = canvas:CreateTexture(nil, "OVERLAY")
    view.entrance:SetSize(12, 12)
    view.entrance:SetTexture(ENTRANCE)
    view.entrance:Hide()
    view.entranceLabel = canvas:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    view.entranceLabel:SetText("Entrance")
    view.entranceLabel:Hide()

    -- The dark tag behind the picked boss's name: over the floor, under the text.
    view.tag = canvas:CreateTexture(nil, "ARTWORK", nil, 7)
    view.tag:SetColorTexture(0, 0, 0, 0.65)
    view.tag:Hide()

    if options.zoom then
        enableZoom(view)
    end
    return view
end

local function showTooltip(button)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(button.boss .. ". " .. button.name)
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function pin(view, index)
    local button = view.pins[index]
    if button then
        return button
    end

    local size = view.options.pinSize or 16
    button = CreateFrame("Button", nil, view.canvas)
    button:SetSize(size, size)
    button:SetFrameLevel(view.canvas:GetFrameLevel() + 2)
    button.ring = button:CreateTexture(nil, "BACKGROUND")
    button.ring:SetSize(size + 8, size + 8)
    button.ring:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.ring:SetTexture(RING)
    button.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    button.ring:Hide()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(PIN)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)

    if view.options.onPinClick then
        button:SetScript("OnClick", function(self)
            view.options.onPinClick(self.boss)
        end)
        button:SetScript("OnEnter", showTooltip)
        button:SetScript("OnLeave", hideTooltip)
    else
        -- The inset: a click on a pin is a click on the map, which opens it.
        button:EnableMouse(false)
    end

    view.pins[index] = button
    return button
end

local function label(view, index)
    local text = view.labels[index]
    if not text then
        text = view.canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        view.labels[index] = text
    end
    return text
end

-- One layer of strips from a run list, reusing the pool's textures.
local function drawStrips(view, pool, runs, sublevel, colour, scale, offsetX, offsetY)
    local canvas = view.canvas
    local count = 0
    for i = 1, #runs, 3 do
        count = count + 1
        local strip = pool[count]
        if not strip then
            strip = canvas:CreateTexture(nil, "ARTWORK", nil, sublevel)
            pool[count] = strip
        end
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", canvas, "TOPLEFT", offsetX + runs[i + 1] * scale, -(offsetY + runs[i] * scale))
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

-- Whether a label at (x0..x1, y) would sit on one already placed.
local function collides(placed, x0, x1, y)
    for _, other in ipairs(placed) do
        if math.abs(other.y - y) < LABEL_HEIGHT and x0 < other.x1 and other.x0 < x1 then
            return true
        end
    end
    return false
end

-- Each pinned boss's name beside its pin: on the right, or on the left near
-- the right edge, nudged down a line at a time off any name already there.
-- The picked boss's name is gold, on a dark tag.
local function drawLabels(view, placedPins, selected)
    local canvas = view.canvas
    local placed = {}
    local half = (view.options.pinSize or 16) / 2 + 2
    view.tag:Hide()
    for index, spot in ipairs(placedPins) do
        local text = label(view, index)
        text:SetText(spot.name)
        local width = text.GetStringWidth and text:GetStringWidth() or #spot.name * 6
        local onLeft = spot.fraction > LABEL_FLIP
        local x0 = onLeft and (spot.x - half - width) or (spot.x + half)
        local y = spot.y
        for _ = 1, 6 do
            if not collides(placed, x0, x0 + width, y) then
                break
            end
            y = y + LABEL_HEIGHT
        end
        table.insert(placed, { x0 = x0, x1 = x0 + width, y = y })

        text:ClearAllPoints()
        if onLeft then
            text:SetPoint("RIGHT", canvas, "TOPLEFT", spot.x - half, -y)
            text:SetJustifyH("RIGHT")
        else
            text:SetPoint("LEFT", canvas, "TOPLEFT", spot.x + half, -y)
            text:SetJustifyH("LEFT")
        end
        if spot.boss == selected then
            text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            view.tag:ClearAllPoints()
            view.tag:SetPoint("CENTER", canvas, "TOPLEFT", x0 + width / 2, -y)
            view.tag:SetSize(width + 10, LABEL_HEIGHT + 5)
            view.tag:Show()
        else
            text:SetTextColor(0.95, 0.92, 0.85)
        end
        text:Show()
    end
    for i = #placedPins + 1, #view.labels do
        view.labels[i]:Hide()
    end
end

function MapView.Show(view, instance, selected)
    -- Another instance starts at its whole map; another boss keeps the zoom.
    if instance ~= view.instance then
        view.instance = instance
        setZoom(view, 1)
        if view.options.zoom then
            view:SetHorizontalScroll(0)
            view:SetVerticalScroll(0)
        end
    end
    view.selected = selected

    hideAll(view.pins)
    hideAll(view.labels)
    view.pinCount = 0
    view.tag:Hide()
    view.entrance:Hide()
    view.entranceLabel:Hide()

    local map = instance and instance.map
    if not map then
        hideAll(view.edges)
        hideAll(view.floor)
        hideAll(view.inner)
        view.shownMap = nil
        return
    end

    local canvas = view.canvas
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local scale, offsetX, offsetY = MapView.Layout(map, width, height)
    local function place(fraction)
        return offsetX + fraction[1] * map.cols * scale, offsetY + fraction[2] * map.rows * scale
    end

    -- The strips only change with the map or the canvas's size; a redraw of
    -- the same map (a new boss picked, an item arrived) touches just the pins.
    if view.shownMap ~= map or view.shownWidth ~= width or view.shownHeight ~= height then
        drawStrips(view, view.edges, MapView.Outline(map), 0, EDGE, scale, offsetX, offsetY)
        drawStrips(view, view.floor, map.runs, 1, FLOOR, scale, offsetX, offsetY)
        drawStrips(view, view.inner, MapView.Inner(map), 2, INNER, scale, offsetX, offsetY)
        view.shownMap, view.shownWidth, view.shownHeight = map, width, height
    end

    if instance.entrance then
        local x, y = place(instance.entrance)
        view.entrance:ClearAllPoints()
        view.entrance:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
        view.entrance:Show()
        if view.options.labels then
            view.entranceLabel:ClearAllPoints()
            view.entranceLabel:SetPoint("LEFT", view.entrance, "RIGHT", 2, 0)
            view.entranceLabel:Show()
        end
    end

    local placedPins = {}
    for bossIndex, boss in ipairs(instance.bosses or {}) do
        if boss.pin then
            local x, y = place(boss.pin)
            local button = pin(view, #placedPins + 1)
            button.boss = bossIndex
            button.name = boss.name
            button.selected = bossIndex == selected
            button.x, button.y = x, y
            button.text:SetText(tostring(bossIndex))
            button.ring:SetShown(button.selected)
            button:ClearAllPoints()
            button:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
            button:Show()
            table.insert(placedPins, { boss = bossIndex, name = boss.name, x = x, y = y, fraction = boss.pin[1] })
        end
    end
    view.pinCount = #placedPins

    if view.options.labels then
        drawLabels(view, placedPins, selected)
    end
    showPinsInSight(view)
end
