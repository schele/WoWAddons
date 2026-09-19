local addonName, ns = ...

-- One unit's row: a name, a health bar, and the secure buttons that cast on
-- that unit. The buttons are the only part the client treats as special, and
-- the only thing we ever do to them is write attributes.

local Row = {}
ns.Row = Row

local NAME_WIDTH = 70
local BAR_WIDTH = 120
local BUTTON_SIZE = 22
local BUTTON_GAP = 2
local PADDING = 4

Row.HEIGHT = BUTTON_SIZE + 2
Row.WIDTH = NAME_WIDTH + BAR_WIDTH + PADDING * 2
    + (BUTTON_SIZE + BUTTON_GAP) * ns.Slots.MAX

-- How far a row fades when clicking it would achieve nothing.
local DIM = 0.35

--- Build one unit's row. Called once per unit, at login, out of combat.
function Row.Create(unit, parent)
    local row = CreateFrame("Frame", "HealclickRow" .. unit, parent)
    row:SetSize(Row.WIDTH, Row.HEIGHT)
    row.unit = unit

    -- Blizzard decides whether this row is on screen, via RegisterUnitWatch,
    -- and it reads the unit from here. Group makes that call.
    row:SetAttribute("unit", unit)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", PADDING, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")

    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetPoint("LEFT", NAME_WIDTH + PADDING * 2, 0)
    row.health:SetSize(BAR_WIDTH, Row.HEIGHT - 6)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)

    row.buttons = {}

    for index = 1, ns.Slots.MAX do
        local button = CreateFrame(
            "Button",
            "HealclickButton" .. unit .. index,
            row,
            "SecureActionButtonTemplate"
        )
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:SetPoint(
            "LEFT",
            NAME_WIDTH + BAR_WIDTH + PADDING * 3 + (index - 1) * (BUTTON_SIZE + BUTTON_GAP),
            0
        )
        button:RegisterForClicks("AnyUp")

        -- The two attributes that are written once and never again. Blizzard
        -- will not let us re-point a secure button in combat, so we never try:
        -- a button can only ever cast on the row it sits in.
        button:SetAttribute("type", "spell")
        button:SetAttribute("unit", unit)

        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER")

        button:Hide()
        row.buttons[index] = button
    end

    return row
end

--- Write the spell attributes and show only the slots in use.
-- Every call here is blocked once the player is in combat, so the caller is
-- responsible for not being in any. Group.ApplyAll is that caller.
function Row.ApplySpells(row)
    local count = ns.Slots.Count()

    for index = 1, ns.Slots.MAX do
        local button = row.buttons[index]
        local spell = index <= count and ns.Slots.Spell(index) or nil

        if spell then
            button:SetAttribute("spell", spell)
            button.label:SetText(spell:sub(1, 2))
            button:Show()
        else
            -- An empty slot is hidden rather than shown and inert. A button
            -- that looks pressable and does nothing is the worse failure.
            button:SetAttribute("spell", nil)
            button.label:SetText("")
            button:Hide()
        end
    end
end

--- Name, colour, health and the dim state. Touches nothing secure, so this is
-- safe at any time, including mid-fight when it matters most.
function Row.Refresh(row)
    local unit = row.unit

    if not UnitExists(unit) then
        row.name:SetText("")
        return
    end

    row.name:SetText(UnitName(unit) or "")

    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
        row.name:SetTextColor(color.r, color.g, color.b)
        row.health:SetStatusBarColor(color.r, color.g, color.b)
    end

    local health = UnitHealth(unit) or 0
    local healthMax = UnitHealthMax(unit) or 0
    row.health:SetMinMaxValues(0, healthMax > 0 and healthMax or 1)
    row.health:SetValue(health)

    -- Clicking a heal on someone dead, offline or out of range burns a global
    -- cooldown and gives nothing back. Fading the row is the cheapest way to
    -- stop the hand before it does that.
    local reachable = not UnitIsDeadOrGhost(unit)
        and UnitIsConnected(unit)
        and (UnitInRange(unit))

    row:SetAlpha(reachable and 1 or DIM)
end
