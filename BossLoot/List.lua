local addonName, ns = ...

-- A scrolling list: a fixed set of rows, re-pointed at a window of entries.
-- All three columns are one of these; they differ only in how a row is built
-- and drawn. Built by hand rather than on a scroll template, because this
-- client family has already dropped templates out from under these addons.

local List = {}
ns.List = List

-- How many lines one notch of the mouse wheel moves.
local WHEEL_STEP = 3

local MORE_ARROW = "|TInterface\\Buttons\\Arrow-Down-Up:12:12|t "

local function columns(list)
    return list.options.columns or 1
end

function List.Render(list)
    for index, row in ipairs(list.rows) do
        local entry = list.entries[index + list.offset]
        if entry then
            list.options.renderRow(row, entry)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    -- Mouse-wheel scrolling leaves no other sign that there is more.
    local below = #list.entries - list.offset - #list.rows
    if below > 0 then
        list.more:SetText(MORE_ARROW .. below .. " more")
        list.more:Show()
    else
        list.more:Hide()
    end
end

--- Move by whole lines; a line is one row per column.
function List.Scroll(list, lines)
    local perLine = columns(list)
    local totalLines = math.ceil(#list.entries / perLine)
    local maxOffset = math.max(0, totalLines - list.options.rows) * perLine
    list.offset = math.min(maxOffset, math.max(0, list.offset + lines * perLine))
    List.Render(list)
end

--- Point the list at new entries. Back to the top unless `keepOffset`, which
-- a redraw of the same entries (an item finished loading) wants.
function List.SetEntries(list, entries, keepOffset)
    list.entries = entries or {}
    if not keepOffset then
        list.offset = 0
    end
    List.Scroll(list, 0)
end

--- A list of `rows` lines. With `columns`, each line holds that many rows,
-- `columnWidth` apart, filled left to right: a grid.
function List.Create(parent, options)
    local list = CreateFrame("Frame", nil, parent)
    local perLine = options.columns or 1
    local columnWidth = options.columnWidth or options.width
    list:SetSize(options.width, options.rowHeight * options.rows)
    list.options = options
    list.rows = {}
    list.entries = {}
    list.offset = 0

    for index = 1, options.rows * perLine do
        local column = (index - 1) % perLine
        local line = math.floor((index - 1) / perLine)
        local row = options.createRow(list, index)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", column * columnWidth, -line * options.rowHeight)
        row:Hide()
        list.rows[index] = row
    end

    list.more = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    list.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -2)
    list.more:Hide()

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        List.Scroll(self, -delta * WHEEL_STEP)
    end)

    return list
end

--- A row factory for plain text entries: a line of text, a hover glow, and a
-- band behind the selected one.
function List.TextRow(onClick)
    return function(list)
        local row = CreateFrame("Button", nil, list)
        row:SetSize(list.options.columnWidth or list.options.width, list.options.rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
        row.selectedTexture:SetAllPoints()
        row.selectedTexture:SetColorTexture(1, 0.82, 0, 0.18)
        row.selectedTexture:Hide()

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")

        row:SetScript("OnClick", function(self, mouseButton)
            if self.entry and self.entry.kind ~= "heading" then
                onClick(self.entry, mouseButton)
            end
        end)

        return row
    end
end

--- Draw a text entry. Headings are gold and take no clicks.
function List.RenderText(row, entry)
    row.entry = entry
    row.text:SetText(entry.text)

    if entry.kind == "heading" then
        row.text:SetTextColor(1, 0.82, 0)
        row:EnableMouse(false)
    else
        row.text:SetTextColor(1, 1, 1)
        row:EnableMouse(true)
    end

    row.selectedTexture:SetShown(entry.selected and true or false)
end
