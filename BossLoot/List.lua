local addonName, ns = ...

-- A scrolling list: a fixed set of rows, re-pointed at a window of entries.
-- All three columns are one of these; they differ only in how a row is built
-- and drawn. Built by hand rather than on a scroll template, because this
-- client family has already dropped templates out from under these addons.

local List = {}
ns.List = List

-- How many entries one notch of the mouse wheel moves.
local WHEEL_STEP = 3

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
end

function List.Scroll(list, by)
    local maxOffset = math.max(0, #list.entries - #list.rows)
    list.offset = math.min(maxOffset, math.max(0, list.offset + by))
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

function List.Create(parent, options)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(options.width, options.rowHeight * options.rows)
    list.options = options
    list.rows = {}
    list.entries = {}
    list.offset = 0

    for index = 1, options.rows do
        local row = options.createRow(list, index)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * options.rowHeight)
        row:Hide()
        list.rows[index] = row
    end

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
        row:SetSize(list.options.width, list.options.rowHeight)
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
