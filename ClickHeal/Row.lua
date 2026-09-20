local addonName, ns = ...

-- One unit's row: a name, a health bar, and the secure buttons that cast on
-- that unit. The buttons are the only part the client treats as special, and
-- the only thing we ever do to them is write attributes.

local Row = {}
ns.Row = Row

local NAME_WIDTH = 70
local BAR_WIDTH = 120
-- Blizzard's own action buttons are 36; this is smaller because five rows of
-- these stack beside five unit frames rather than sitting alone at the foot
-- of the screen. The bounds are what a spell icon still reads at, and what
-- fits beside a unit frame without swamping it.
Row.DEFAULT_BUTTON_SIZE = 24
Row.MIN_BUTTON_SIZE = 12
Row.MAX_BUTTON_SIZE = 48

--- The icon size in force, as a whole number inside the bounds.
--
-- Clamped here rather than trusted from the database: the slider cannot
-- produce a bad value, but a saved variable edited by hand can, and a row
-- sized from a negative number is a frame the client complains about.
local function buttonSize()
    local size = math.floor(
        tonumber(ns.db and ns.db.bar and ns.db.bar.iconSize)
            or Row.DEFAULT_BUTTON_SIZE
    )

    if size < Row.MIN_BUTTON_SIZE then
        return Row.MIN_BUTTON_SIZE
    elseif size > Row.MAX_BUTTON_SIZE then
        return Row.MAX_BUTTON_SIZE
    end

    return size
end

local BUTTON_GAP = 4
local PADDING = 4

-- Exported because the row's width, the gap a hidden button gives back and
-- Group's own arithmetic all have to agree on it, and because a test that
-- restates it as a literal stops agreeing the moment it changes.
Row.BUTTON_GAP = BUTTON_GAP

-- Where the button strip begins: past the name, the bar, and a PADDING gap
-- after each. Create and WIDTH both anchor on this so they cannot drift
-- apart the way they did when WIDTH counted its own, separate offset.
local BUTTONS_START = NAME_WIDTH + BAR_WIDTH + PADDING * 3



--- Whether rows hang off Blizzard's own unit frames rather than off a bar of
-- ours.
--
-- Both halves have to hold: the player asked for it, and this UI actually
-- has the frames to hang from. Asking for the attached layout cannot conjure
-- frames that raid-style party frames or a unit-frame addon have taken away,
-- so the answer is no whenever they are gone, and everything downstream --
-- widths, button offsets, Group's layout -- follows from this one question.
function Row.Attached()
    if not (ns.db and ns.db.bar and ns.db.bar.attached) then
        return false
    end
    return ns.Anchors.Available()
end

--- Whether this unit's row is switched off, buttons and all.
--
-- Only the player's, and only by choice. A healer watching the party rather
-- than themselves has a row beside their own frame they never click, sitting
-- where their eyes go first.
--
-- The row is kept and emptied rather than never built: rows can only be
-- created out of combat, so a row that does not exist is one the setting
-- could not bring back mid-fight.
function Row.Suppressed(unit)
    if unit ~= "player" then
        return false
    end

    return (ns.db and ns.db.bar and ns.db.bar.showSelf) == false
end

-- Where the button strip begins inside a row. Attached, Blizzard's frame is
-- already showing the name and health, so ours are hidden and there is
-- nothing for the buttons to start after.
local function buttonsStart()
    return Row.Attached() and 0 or BUTTONS_START
end

--- How wide a row must be to carry `count` buttons: everything up to the
-- button strip, then the strip. It reaches the last button's right edge and
-- no further -- there is no gap after the final button, only between two.
local function widthFor(count)
    local start = buttonsStart()
    if count < 1 then
        -- Never zero: a row with no buttons is hidden anyway, and a frame
        -- sized zero is a thing the client has opinions about.
        return math.max(start, 1)
    end
    return start + count * (buttonSize() + BUTTON_GAP) - BUTTON_GAP
end

--- Recompute the exported HEIGHT and WIDTH from the icon size now in force.
--
-- These stay values rather than becoming functions because Group reads them
-- from half a dozen places, including before a row has been through
-- ApplySpells. This is what keeps them true once the size setting moves;
-- Group calls it before it lays anything out.
function Row.SyncSize()
    Row.HEIGHT = buttonSize() + 2
    Row.WIDTH = widthFor(ns.Slots.MAX)
end

-- Once now, so HEIGHT and WIDTH exist before anything reads them. WIDTH is
-- the widest a row can be at the current icon size; what one actually
-- measures is Row.CurrentWidth below, and it is usually narrower.
Row.SyncSize()

-- How far a row fades when clicking it would achieve nothing.
local DIM = 0.35

-- How far an icon darkens when its own spell cannot reach this row's unit.
local RANGE_DIM = 0.4

-- Blizzard's own stand-in for a spell it will not draw. Reached only when
-- the player knows the spell but the icon lookup came back empty, so that a
-- client with no texture API costs the picture rather than the button.
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Whether a slot's spell earns a button. A slot past the configured count
-- has no spell as far as its caller is concerned, so one test covers both
-- reasons a button might not appear.
local function hasButton(spell)
    return spell ~= nil and ns.Spells.IsKnown(spell)
end

--- How many buttons a row shows: the configured slots, less any holding a
-- spell this player has not learned yet. ApplySpells counts the same thing
-- as it goes; this answers it for callers that need the number before a row
-- has been through it -- Group, sizing the frame the rows sit on.
function Row.VisibleCount()
    local shown = 0
    for index = 1, ns.Slots.Count() do
        if hasButton(ns.Slots.Spell(index)) then
            shown = shown + 1
        end
    end
    return shown
end

--- How wide a row measures as things currently stand.
function Row.CurrentWidth()
    return widthFor(Row.VisibleCount())
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

-- Diagnostic scaffolding, off unless `/ch debug` turns it on.
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
    local row = CreateFrame("Frame", "ClickHealRow" .. unit, parent)
    row:SetSize(Row.CurrentWidth(), Row.HEIGHT)
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
            -- name themselves ClickHealButtonraid111, clobbering a _G entry.
            string.format("ClickHealButton%s_%d", unit, index),
            row,
            "SecureActionButtonTemplate"
        )
        button:SetSize(buttonSize(), buttonSize())
        button:SetPoint(
            "LEFT",
            buttonsStart() + (index - 1) * (buttonSize() + BUTTON_GAP),
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

        -- The action bar's own hover highlight, so these buttons light up
        -- under the cursor the way the ones beside them do. The client draws
        -- it; there is no OnEnter or OnLeave to write, and nothing to undo
        -- when the cursor leaves. ADD blends it as a glow over the icon
        -- rather than laying an opaque square on top of it.
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        -- Just below the icon rather than across it: at 22 pixels there is
        -- no room to lay a number over the art and still read either.
        button.timer = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.timer:SetPoint("TOP", button, "BOTTOM", 0, -3)

        -- Blizzard's own cooldown widget, so the sweep is the one the action
        -- bars draw and the client animates it for us; all we ever hand it is
        -- a start and a duration.
        --
        -- Through pcall because a template is not something this client
        -- family can be trusted to have -- it has already dropped
        -- GetSpellInfo and GetSpellBookItemName out from under the addon --
        -- and an unknown template raises rather than returning nil. The sweep
        -- is decoration; casting is the point, so losing the template costs
        -- the sweep and nothing else.
        local created, cooldown = pcall(
            CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate"
        )
        if created and cooldown then
            cooldown:SetAllPoints(button)
            button.cooldown = cooldown
        end


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
    local shown = 0
    local size = buttonSize()

    -- Resized here, not only at creation, because the icon size is a setting
    -- and the rows outlive a change to it -- they can only be built out of
    -- combat, so rebuilding them is not an option the setting has. Safe for
    -- the same reason every other write in this function is: ApplySpells
    -- runs out of combat only, and resizing a secure button is refused in it.
    row:SetHeight(Row.HEIGHT)
    row.health:SetHeight(math.max(Row.HEIGHT - 6, 1))

    -- Attached, Blizzard's frame is already showing this unit's name and
    -- health, so drawing ours would put a second copy of each right beside
    -- the first. Done here rather than at creation so the layout can change
    -- without rebuilding the rows -- which would be impossible in combat.
    if Row.Attached() then
        row.name:Hide()
        row.health:Hide()
    else
        row.name:Show()
        row.health:Show()
    end

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

        -- Whether the player knows the spell, never whether an icon turned
        -- up. The two nearly always agree -- both are name lookups against
        -- the spellbook -- but they fail differently: Spells.IsKnown reports
        -- a spell it cannot check at all as known, while Spells.Texture
        -- reports one it cannot check as having no icon. Deciding on the
        -- icon would empty the whole bar on a client with no texture API,
        -- which is the one outcome that leaves a healer nothing to click.
        if hasButton(spell) and not Row.Suppressed(row.unit) then
            button:SetAttribute("spell", spell)

            button.icon:SetTexture(ns.Spells.Texture(spell) or UNKNOWN_ICON)
            button.icon:Show()

            -- Placed by how many buttons are already showing, not by slot
            -- index: a slot hidden in the middle would otherwise leave a
            -- hole where its button would have been. Group.Layout does the
            -- same for the rows themselves, for the same reason. Safe here
            -- because ApplySpells only ever runs out of combat, and moving
            -- a secure frame is refused in it.
            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint(
                "LEFT",
                buttonsStart() + shown * (size + BUTTON_GAP),
                0
            )
            shown = shown + 1

            button:Show()
        else
            -- Hidden rather than shown and inert, whether the slot is empty
            -- or holds a spell this player cannot cast yet. A button that
            -- looks pressable and does nothing is the worse failure.
            button:SetAttribute("spell", nil)
            button.icon:Hide()
            button:Hide()
        end
    end

    -- Narrowed to what is actually on it, so the frame behind the row stops
    -- where the last button does. Safe for the same reason every other
    -- write here is: ApplySpells only ever runs out of combat, and resizing
    -- a frame the client is watching is refused in it.
    row:SetWidth(widthFor(shown))
end


-- The secret-value guard lives in ClickHeal.lua, beside the explanation of
-- what a secret value is and why a branch on one has to be wrapped. Spells.lua
-- needs the same guard, so there is one of it rather than one per file.
local guarded = ns.Guarded

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

--- Draw each button's cooldown sweep.
--
-- Reads the spell off the button's own attribute rather than out of Slots,
-- so the sweep can only ever show the cooldown of the spell this button will
-- actually cast. Touches nothing secure -- reading an attribute we set
-- ourselves is not a secure write -- so like Row.Refresh this is safe
-- mid-fight, which is the only time it matters.
function Row.RefreshCooldowns(row)
    for index = 1, ns.Slots.MAX do
        local cooldown = row.buttons[index].cooldown
        if cooldown then
            local start, duration, enabled =
                ns.Spells.Cooldown(row.buttons[index]:GetAttribute("spell"))

            if start and duration and duration > 0 and enabled then
                cooldown:SetCooldown(start, duration)
            else
                -- A zero-length cooldown is how the widget is told to draw
                -- nothing. Without this an expired sweep would sit there
                -- for good, since nothing else ever clears one.
                cooldown:SetCooldown(0, 0)
            end
        end
    end
end

--- Darken the icon of any spell that cannot reach this row's unit.
--
-- Per button, not per row. Spells differ in reach, so fading the whole row
-- would be answering a question nobody asked -- and the row-wide fade is
-- already spoken for by dead and offline, which make every spell on the row
-- useless at once. Being out of reach of one of them does not.
--
-- Anything the client declines to answer leaves the icon at full colour. A
-- healer told a spell is out of reach when it is not loses a cast they had,
-- which is worse than never dimming at all.
function Row.RefreshRange(row)
    for index = 1, ns.Slots.MAX do
        local button = row.buttons[index]
        local spell = button:GetAttribute("spell")

        if spell then
            -- Compared against false rather than tested, because nil here
            -- means "cannot tell" and must not dim.
            if ns.Spells.InRange(spell, row.unit) == false then
                button.icon:SetVertexColor(RANGE_DIM, RANGE_DIM, RANGE_DIM)
            else
                button.icon:SetVertexColor(1, 1, 1)
            end
        end
    end
end

--- How long is left, written the way the game's own buff frames write it.
--
-- One unit, never two: under a small icon "38m" is readable and "38m 12s" is
-- a smear.
--
-- Minutes and hours round up, which is what the game's own buff frames do --
-- SecondsToTimeAbbrev ceils everything above a minute. Rounding down instead
-- put our number a whole minute below the one Blizzard was showing for the
-- same buff, side by side on the same screen: 56m against 57 m. Seconds
-- round up too, so a buff still running never reads 0s.
function Row.FormatDuration(seconds)
    if not seconds or seconds <= 0 then
        return ""
    end

    if seconds < 60 then
        return string.format("%ds", math.ceil(seconds))
    end

    if seconds < 3600 then
        return string.format("%dm", math.ceil(seconds / 60))
    end

    return string.format("%dh", math.ceil(seconds / 3600))
end

--- Write the remaining time of each button's own spell on this row's unit.
--
-- The unit's auras are gathered once and shared across the row's buttons.
-- Asked per button instead, eight buttons on each of five rows refreshed
-- five times a second would be thousands of calls into the client every
-- second, nearly all of them repeats.
function Row.RefreshAuras(row)
    local auras = ns.Spells.PlayerAuras(row.unit)

    for index = 1, ns.Slots.MAX do
        local button = row.buttons[index]
        local spell = button:GetAttribute("spell")

        button.timer:SetText(Row.FormatDuration(
            spell and ns.Spells.AuraRemaining(row.unit, spell, auras) or nil
        ))
    end
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

    Row.RefreshRange(row)
    Row.RefreshAuras(row)
end

-- Declared here rather than with Group's layout settings: this file owns the
-- size -- it clamps it, derives HEIGHT and WIDTH from it, and sizes the
-- buttons by it -- so it owns what happens when nothing has set one.
ns.AddDefaults({
    bar = {
        iconSize = Row.DEFAULT_BUTTON_SIZE,
    },
})

ns.RegisterSetting({
    store = "bar",
    key = "iconSize",
    type = "slider",
    name = "Icon size",
    tooltip = "How big each spell icon is. Blizzard's own action buttons are 36; these are smaller by default because five rows of them sit beside five unit frames rather than one bar sitting alone.",
    min = Row.MIN_BUTTON_SIZE,
    max = Row.MAX_BUTTON_SIZE,
    step = 1,
    onChange = function()
        -- ApplyAll syncs the derived sizes before it lays anything out, and
        -- resizes the buttons that already exist on its way through
        -- ApplySpells.
        if ns.Group then ns.Group.ApplyAll() end
    end,
})
