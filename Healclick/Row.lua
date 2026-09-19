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

-- A button shows the spell's own icon when one can be found. Row.Label below
-- is what it falls back to when it cannot -- the one thing standing between
-- a healer and casting the wrong spell under pressure, on a client that will
-- not tell us what the icon is.

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

--- Store a spell in a slot and apply it -- the body shared by a drag-and-drop
-- and a click-to-place assignment (see Row.Create), so the two paths cannot
-- drift apart.
local function assignSpellToSlot(slot, name)
    local _, message = ns.Slots.Set(slot, name)
    ClearCursor()

    if ns.Group then
        ns.Group.ApplyAll()
    end

    -- The settings panel's own box for this slot still shows whatever was
    -- there before this assignment; left alone, it stores that stale text
    -- back over the drop or click the next time it loses focus. The `spells`
    -- setting in Slots.lua applies the mirror image of this on its own
    -- change, for the same reason.
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end

    if message then
        ns.Print(message)
    end
end

-- Diagnostic scaffolding, off unless `/hc debug` turns it on.
--
-- A secure button that will not cast gives nothing away from outside the
-- game: the client's handler reads the attributes, then either acts or
-- silently declines, and logs neither. These hooks bracket that moment so a
-- single click says where it stopped.
--
--   OnMouseDown fires whenever the frame receives the mouse at all.
--   PreClick fires only once the click matches RegisterForClicks and OnClick
--   runs -- the same instant the secure handler reads `type`.
--
-- So neither line printing means the mouse never reached the button; the
-- first without the second means the click arrived but was not a registered
-- click type; both printing, with the attributes reading correctly, means
-- the handler itself declined.
local debugging = false

local function debugClick(button, stage, detail)
    if not debugging then
        return
    end

    ns.Print(string.format(
        "%s slot %s (%s) type=%s spell=%s unit=%s",
        stage,
        tostring(button.slot),
        tostring(detail),
        tostring(button:GetAttribute("type")),
        tostring(button:GetAttribute("spell")),
        tostring(button:GetAttribute("unit"))
    ))
end

ns.RegisterCommand("debug", "Trace what happens when a button is clicked", function()
    debugging = not debugging
    ns.Print(debugging and "Click tracing on. Click a spell button."
        or "Click tracing off.")
end)

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
    -- A StatusBar with no texture draws nothing at all: Row.Refresh's
    -- SetStatusBarColor would be tinting a bar nobody can see. ForeverPanel
    -- paints its own bars from plain textures rather than a StatusBar
    -- widget, so there is no in-repo StatusBar to copy; this is Blizzard's
    -- own default health-bar texture, the standard choice absent a reason
    -- to hand-roll art.
    row.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
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
        -- Both edges, and the press is the one that matters. Registered for
        -- "AnyUp" alone these buttons silently refused to cast: tracing a
        -- click in game showed OnMouseDown, OnMouseUp, PreClick and PostClick
        -- all firing, with type=spell spell=Rejuvenation unit=player read
        -- correctly at click time -- and always down=false. The client
        -- performs a secure action on the press, so a button that only asks
        -- for the release never gives it a pass it will act on. The release
        -- stays registered because a client configured the other way acts on
        -- that one instead, and the spare pass costs nothing: it finds an
        -- empty cursor and falls straight through.
        button:RegisterForClicks("AnyUp", "AnyDown")

        -- Fires on any mouse press the frame receives, whether or not that
        -- press is a click type this button is registered for -- which is
        -- exactly what separates "the mouse never got here" from "the click
        -- got here and was not one we asked for". See debugClick above.
        button:SetScript("OnMouseDown", function(self, mouseButton)
            debugClick(self, "OnMouseDown", mouseButton)
        end)

        button:SetScript("OnMouseUp", function(self, mouseButton)
            debugClick(self, "OnMouseUp", mouseButton)
        end)

        -- The two attributes that are written once and never again. Blizzard
        -- will not let us re-point a secure button in combat, so we never try:
        -- a button can only ever cast on the row it sits in.
        button:SetAttribute("type", "spell")
        button:SetAttribute("unit", unit)

        -- Which slot a drop onto this button should land in.
        button.slot = index

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints(button)
        -- The standard action-bar crop: default spell icons carry their own
        -- border baked in, and without trimming it every button looks wrong
        -- next to this one's.
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.icon:Hide()

        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER")

        -- RegisterForDrag is for STARTING a drag; this button's left-click
        -- already casts a spell, and registering it for drag risks a drag
        -- swallowing that click. OnReceiveDrag alone, which fires whenever
        -- something lands here regardless of who can start a drag, is all a
        -- real drag needs.
        button:SetScript("OnReceiveDrag", function(self)
            local name = ns.Spells.CursorSpell()
            if not name then
                -- Not a spell: an item, a macro, whatever else can ride a
                -- cursor. Leave it exactly where it was.
                return
            end

            assignSpellToSlot(self.slot, name)
        end)

        -- Most players assign a spell by clicking it in the spellbook, then
        -- clicking the button -- an ordinary click, which the secure handler
        -- below would otherwise read as "cast this button's spell" and fire
        -- it on whoever this row is for. PreClick/PostClick wrap around
        -- every click regardless of what handles it, which is the documented
        -- way to suppress one click's cast without touching how any other
        -- click on this button is handled.
        --
        -- Not set past the click that fills it: PostClick clears it
        -- unconditionally once used, so a later ordinary click never finds a
        -- stash left over from this one.
        button.pendingAssign = nil

        button:SetScript("PreClick", function(self, mouseButton, down)
            debugClick(self, "PreClick", string.format("%s down=%s",
                tostring(mouseButton), tostring(down)))

            if InCombatLockdown and InCombatLockdown() then
                -- SetAttribute is refused outright in combat, even to nil
                -- `type` out for a single click, so a click mid-fight is left
                -- to cast normally, exactly as if nothing were picked up.
                return
            end

            local name = ns.Spells.CursorSpell()
            if not name then
                return
            end

            -- Suppress the cast this click would otherwise trigger: the
            -- secure handler reads `type` at click time, so nil-ing it here
            -- is what stops this click casting while it is placing a spell
            -- instead.
            self.pendingAssign = name
            self:SetAttribute("type", nil)
        end)

        button:SetScript("PostClick", function(self, mouseButton, down)
            debugClick(self, "PostClick", string.format("%s down=%s",
                tostring(mouseButton), tostring(down)))

            if InCombatLockdown and InCombatLockdown() then
                -- Belt-and-braces: PreClick already refuses to stash
                -- anything while in combat, so this should be unreachable
                -- from any path the addon itself takes. Clearing the stash
                -- here regardless (not just returning) is what stops this
                -- guard from stranding the exact bug it exists to prevent;
                -- neither the attribute restore nor the assignment below may
                -- run either way, since both are secure writes the client
                -- refuses outright in combat.
                self.pendingAssign = nil
                return
            end

            if not self.pendingAssign then
                return
            end

            local name = self.pendingAssign
            -- Cleared before the call below, not after: assignSpellToSlot
            -- has five call sites (Slots.Set, ClearCursor, Group.ApplyAll,
            -- SettingsPanel.Refresh, Print), four of them reaching real
            -- client widgets. If any of them throws, the stash must not
            -- survive to be found -- and acted on -- by a later, unrelated
            -- click, possibly one that lands mid-fight.
            self.pendingAssign = nil
            self:SetAttribute("type", "spell")
            assignSpellToSlot(self.slot, name)
        end)

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

        -- Reasserted on every call, not assumed to still hold from
        -- creation: PreClick's click-suppression trick (above) nils this
        -- out for the span of one click, and if PostClick were ever to
        -- leave it that way -- a stranded stash from a bug, present or
        -- future -- this is what recovers it, since some ApplyAll follows
        -- shortly after anything that could go wrong. Safe here because
        -- ApplySpells, like every secure write in this file, only ever runs
        -- out of combat.
        button:SetAttribute("type", "spell")

        if spell then
            button:SetAttribute("spell", spell)

            local texture = ns.Spells.Texture(spell)
            if texture then
                button.icon:SetTexture(texture)
                button.icon:Show()
                button.label:SetText("")
            else
                button.icon:Hide()
                button.label:SetText(Row.Label(spell))
            end

            button:Show()
        else
            -- An empty slot is hidden rather than shown and inert. A button
            -- that looks pressable and does nothing is the worse failure.
            button:SetAttribute("spell", nil)
            button.icon:Hide()
            button.label:SetText("")
            button:Hide()
        end
    end
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises.
--
-- Some clients hand tainted code (ours) a "secret" value: the API call that
-- produced it succeeds, but the client refuses to let addon code inspect
-- the result afterwards -- comparing it, or testing its truthiness, raises
-- "attempt to perform boolean test on ... a secret ... value". Which
-- particular return is secret varies by client build and by how the call
-- was reached, so every place below that branches on one of these values is
-- routed through here, in one place, rather than guarded ad hoc.
--
-- `fn` must both make the call and perform the branch that can raise, not
-- just fetch a value for the caller to test afterwards -- in the game it is
-- the branch that raises, the call having already succeeded. Routing both
-- through the same pcall is also what makes this testable at all: Lua has
-- no way to construct a value that raises when its truthiness is checked,
-- so a test instead makes the stubbed API call itself raise. Both failure
-- shapes land in this same pcall, so the fallback path is exercised even
-- though the exact in-game trigger (a secret value, not a raising call)
-- cannot be reproduced.
local function guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

--- Whether `unit` is someone to draw a row for at all.
--
-- Guarded for the reason given above `guarded`, and note which reads need it:
-- the client keeps *booleans* secret, not numbers. A secret number survives
-- `x or 0` because a number is never falsy, so testing it reveals nothing;
-- a boolean's truthiness is the whole of its value, which is exactly what
-- the client is refusing to hand over. Every boolean return we branch on is
-- therefore a candidate, not just the one that has crashed so far.
--
-- Unknown counts as present: a row drawn for someone who has left is a stale
-- name until the next roster event, while a row withheld from someone
-- standing there is a player the healer cannot click.
function Row.Exists(unit)
    return guarded(function() return not not UnitExists(unit) end, true)
end

--- Whether clicking a heal on `unit` could land. False only when we could
-- affirmatively tell otherwise; anything we could not check at all reads as
-- reachable -- wrongly dimming a row that could in fact be healed costs a
-- healer a click they needed, which is worse than never dimming at all.
function Row.Reachable(unit)
    -- Dead/offline and range are guarded, and read, independently. If range
    -- cannot be determined at all, a dead or disconnected unit must still
    -- dim; one guard wrapping all three would let a raise on any one of
    -- them swallow a read that would otherwise have succeeded on another.
    if guarded(function() return not not UnitIsDeadOrGhost(unit) end, false) then
        return false
    end

    if not guarded(function() return not not UnitIsConnected(unit) end, true) then
        return false
    end

    -- UnitInRange's second return says whether ranging could even be
    -- checked. It comes back false for "player" while solo, among others --
    -- that is "unknown", not "out of range", so an unchecked unit counts as
    -- reachable rather than being dimmed forever.
    return guarded(function()
        local inRange, checked = UnitInRange(unit)
        return inRange or not checked
    end, true)
end

--- Name, colour, health and the dim state. Touches nothing secure, so this is
-- safe at any time, including mid-fight when it matters most.
function Row.Refresh(row)
    local unit = row.unit

    if not Row.Exists(unit) then
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

    -- UnitHealth's secret return is fine to pass straight to SetValue below
    -- -- handing a secret value onward to a widget is sanctioned, only
    -- inspecting one is not. healthMax's own comparison just below is the
    -- inspection, so it is what needs the same guard as Row.Reachable above,
    -- for the same reason: nothing guarantees a max-health return is exempt
    -- on every client just because it has been so far.
    local health = UnitHealth(unit) or 0
    local healthMax = guarded(function()
        local max = UnitHealthMax(unit) or 0
        return max > 0 and max or 1
    end, 1)
    row.health:SetMinMaxValues(0, healthMax)
    row.health:SetValue(health)

    -- Clicking a heal on someone dead, offline or out of range burns a global
    -- cooldown and gives nothing back. Fading the row is the cheapest way to
    -- stop the hand before it does that. See Row.Reachable above for why
    -- each check behind this is guarded rather than tested plainly.
    row:SetAlpha(Row.Reachable(unit) and 1 or DIM)
end
