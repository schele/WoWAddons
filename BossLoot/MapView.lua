local addonName, ns = ...

-- Draws an instance's generated map into a frame of any size: a small square
-- per filled cell, lighter the higher it lies, and a numbered pin per boss
-- that has a place. The same view serves the header's inset and the full map.

local MapView = {}
ns.MapView = MapView

local BANDS = 4
-- Cells are drawn larger than their spacing so neighbours merge into areas.
local SPREAD = 1.5
local BAND_COLOURS = {
    { 0.20, 0.25, 0.40 },
    { 0.27, 0.34, 0.54 },
    { 0.36, 0.45, 0.68 },
    { 0.50, 0.60, 0.84 },
}
local PIN = "Interface\\COMMON\\Indicator-Red"
local PIN_SELECTED = "Interface\\COMMON\\Indicator-Yellow"

--- How a map of cols by rows cells fits a width by height view: the size of
-- a cell, and the margins that centre the map.
function MapView.Layout(map, width, height)
    local scale = math.min(width / map.cols, height / map.rows)
    return scale, (width - map.cols * scale) / 2, (height - map.rows * scale) / 2
end

function MapView.Create(parent, width, height, options)
    options = options or {}
    local view = CreateFrame("Button", nil, parent)
    view:SetSize(width, height)
    view.options = options
    view.cells = {}
    view.pins = {}

    view.background = view:CreateTexture(nil, "BACKGROUND")
    view.background:SetAllPoints()
    view.background:SetColorTexture(0.02, 0.02, 0.03, 1)

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

function MapView.Show(view, instance, selected)
    for _, cell in ipairs(view.cells) do
        cell:Hide()
    end
    for _, button in ipairs(view.pins) do
        button:Hide()
    end

    local map = instance and instance.map
    if not map then
        return
    end

    local scale, offsetX, offsetY = MapView.Layout(map, view:GetWidth(), view:GetHeight())
    local size = math.max(1, scale * SPREAD)

    for index, value in ipairs(map.cells) do
        local band = value % BANDS
        local cellIndex = (value - band) / BANDS
        local column = cellIndex % map.cols
        local row = (cellIndex - column) / map.cols

        local cell = view.cells[index]
        if not cell then
            cell = view:CreateTexture(nil, "ARTWORK")
            view.cells[index] = cell
        end
        cell:ClearAllPoints()
        cell:SetSize(size, size)
        cell:SetPoint("CENTER", view, "TOPLEFT", offsetX + (column + 0.5) * scale, -(offsetY + (row + 0.5) * scale))
        local colour = BAND_COLOURS[band + 1]
        cell:SetColorTexture(colour[1], colour[2], colour[3], 0.9)
        cell:Show()
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
