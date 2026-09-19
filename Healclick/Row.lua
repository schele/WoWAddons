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

-- Where the button strip begins: past the name, the bar, and a PADDING gap
-- after each. Create and WIDTH both anchor on this so they cannot drift
-- apart the way they did when WIDTH counted its own, separate offset.
local BUTTONS_START = NAME_WIDTH + BAR_WIDTH + PADDING * 3

Row.HEIGHT = BUTTON_SIZE + 2

-- The last button's right edge, not one gap further -- there is no gap after
-- the final button, only between buttons.
Row.WIDTH = BUTTONS_START + ns.Slots.MAX * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP

-- How far a row fades when clicking it would achieve nothing.
local DIM = 0.35

-- A button has no icon, only this label, so it is the one thing standing
-- between a healer and casting the wrong spell under pressure.

--- Split a string into its UTF-8 characters, without assuming a UTF-8
-- library exists on the client. A continuation byte (0x80-0xBF) never starts
-- a character, so any other byte is where the previous character ends and
-- the next begins.
local function characters(text)
    local chars = {}
    local charStart = 1

    for index = 1, #text do
        local byte = text:byte(index)
        local isContinuation = byte >= 0x80 and byte <= 0xBF
        if not isContinuation and index > charStart then
            table.insert(chars, text:sub(charStart, index - 1))
            charStart = index
        end
    end

    if charStart <= #text then
        table.insert(chars, text:sub(charStart, #text))
    end

    return chars
end

--- The first `count` characters of `text`, never cutting a multi-byte one.
local function firstChars(text, count)
    local chars = characters(text)
    local pieces = {}
    for index = 1, math.min(count, #chars) do
        pieces[index] = chars[index]
    end
    return table.concat(pieces)
end

-- Lua's %p is ASCII punctuation only, so this leaves multi-byte characters
-- (all of them >= 0x80, none of them %p) untouched.
local function withoutPunctuation(word)
    return (word:gsub("%p", ""))
end

-- A fixed list, not a length rule: "Cat", "Ice" and "War" are short but
-- carry the spell's meaning ("Cat Form", "Ice Block", "War Stomp" all need
-- their first letter), so word length cannot tell a filler word from a
-- significant one. Only these specific connectives are ever dropped.
local STOP_WORDS = {
    ["of"] = true,
    ["the"] = true,
    ["a"] = true,
    ["an"] = true,
    ["and"] = true,
    ["to"] = true,
}

--- A connective skipped when a multi-word label is built, compared
-- case-insensitively against the fixed list above.
local function isStopWord(word)
    return STOP_WORDS[word:lower()] == true
end

--- The text a button shows for a spell, since there is no icon.
-- A single-word name gives its first four characters. A multi-word name
-- gives the first letter of each significant word (the connectives in
-- STOP_WORDS are dropped, unless dropping them would leave nothing), which
-- is what keeps "Remove Curse" from reading the same as "Regrowth".
function Row.Label(spellName)
    if type(spellName) ~= "string" or spellName == "" then
        return ""
    end

    local words = {}
    for word in spellName:gmatch("%S+") do
        table.insert(words, word)
    end

    if #words == 0 then
        return ""
    elseif #words == 1 then
        return firstChars(words[1], 4)
    end

    local significant = {}
    for _, word in ipairs(words) do
        if not isStopWord(withoutPunctuation(word)) then
            table.insert(significant, word)
        end
    end
    if #significant == 0 then
        significant = words
    end

    local letters = {}
    for index = 1, math.min(4, #significant) do
        local firstChar = characters(withoutPunctuation(significant[index]))[1]
        if firstChar then
            table.insert(letters, firstChar:upper())
        end
    end

    return table.concat(letters)
end

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
            -- The separator matters once slot counts grow past single digits:
            -- without it, unit "raid1" slot 11 and unit "raid11" slot 1 both
            -- name themselves HealclickButtonraid111, clobbering a _G entry.
            string.format("HealclickButton%s_%d", unit, index),
            row,
            "SecureActionButtonTemplate"
        )
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:SetPoint(
            "LEFT",
            BUTTONS_START + (index - 1) * (BUTTON_SIZE + BUTTON_GAP),
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
            button.label:SetText(Row.Label(spell))
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
    --
    -- UnitInRange's second return says whether ranging could even be checked.
    -- It comes back false for "player" while solo, among others -- that is
    -- "unknown", not "out of range", so an unchecked unit counts as reachable
    -- rather than being dimmed forever.
    local inRange, checked = UnitInRange(unit)
    local reachable = not UnitIsDeadOrGhost(unit)
        and UnitIsConnected(unit)
        and (inRange or not checked)

    row:SetAlpha(reachable and 1 or DIM)
end
