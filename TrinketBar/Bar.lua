local addonName, ns = ...

-- The bar: a pool of secure buttons, each carrying an /equipslot macro, and
-- the queue that holds a change until combat ends.

local Bar = {}
ns.Bar = Bar

-- Every button the pool will ever have. Past what anyone carries, because a
-- secure button cannot be created mid-fight: a pool that grows on demand is
-- one that cannot grow at the moment a trinket is looted.
Bar.MAX_BUTTONS = 16

local BUTTON_SIZE = 24
local BUTTON_GAP = 4

local DEFAULT_ANCHOR = { point = "CENTER", x = 0, y = -160 }

ns.AddDefaults({
    anchor = {
        point = DEFAULT_ANCHOR.point,
        x = DEFAULT_ANCHOR.x,
        y = DEFAULT_ANCHOR.y,
    },
    bar = {
        iconSize = 24,
        -- Eight, because sixteen in a line is wider than most screens and
        -- nobody carries sixteen anyway.
        perRow = 8,
        locked = false,
    },
})

-- Faint enough not to compete with the icons over it, visible enough that
-- the drag region reads as a thing you can grab rather than empty air.
local BACKDROP_ALPHA = 0.12

local anchor
local buttons = {}

-- Nothing secure may be written in combat: not an attribute, not showing or
-- hiding a button, not moving the frame they sit in. Rather than attempt it
-- and put an error in the player's face, hold the change and do it the
-- moment the fight ends.
local pending = false
local buildPending = false

function Bar.Buttons()
    return buttons
end

function Bar.Anchor()
    return anchor
end

function Bar.Pending()
    return pending
end

--- The icon size in force, clamped where it is read rather than trusted from
-- the database: a slider cannot produce a bad value but a saved variable
-- edited by hand can, and a frame sized from a negative number is one the
-- client complains about.
local function iconSize()
    local size = math.floor(tonumber(ns.db and ns.db.bar and ns.db.bar.iconSize) or 24)
    if size < 12 then return 12 end
    if size > 48 then return 48 end
    return size
end

local function perRow()
    local count = math.floor(tonumber(ns.db and ns.db.bar and ns.db.bar.perRow) or 8)
    if count < 1 then return 1 end
    if count > Bar.MAX_BUTTONS then return Bar.MAX_BUTTONS end
    return count
end

local function repositionAnchor()
    if anchor then
        anchor:ClearAllPoints()
        anchor:SetPoint(ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y)
    end
end

--- Read the anchor's current point and save it. The inverse of
-- repositionAnchor: that writes ns.db to the anchor, this reads the anchor
-- into ns.db.
local function saveAnchorPosition()
    local point, _, _, x, y = anchor:GetPoint(1)
    ns.db.anchor.point = point or DEFAULT_ANCHOR.point
    ns.db.anchor.x = x or DEFAULT_ANCHOR.x
    ns.db.anchor.y = y or DEFAULT_ANCHOR.y
end

local function createAnchor()
    anchor = CreateFrame("Frame", "TrinketBarAnchor", UIParent)
    anchor:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    local background = anchor:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, BACKDROP_ALPHA)
    anchor.background = background

    repositionAnchor()
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    anchor:SetScript("OnDragStart", function(self)
        if ns.db.bar.locked then
            return
        end

        if InCombatLockdown and InCombatLockdown() then
            -- StartMoving repositions every button hanging off this frame,
            -- which the client refuses in combat the same as any other
            -- secure change.
            ns.Print("Cannot move the bar in combat.")
            return
        end

        self:StartMoving()
    end)

    anchor:SetScript("OnDragStop", function(self)
        -- A refusal here must not raise: the drag has to be able to end even
        -- if a mob pulls between the last mouse-move and the release, or the
        -- bar is stuck to the cursor for the rest of the fight. Refusing to
        -- start (OnDragStart above) is the safe place to hold the line;
        -- refusing to stop is not.
        pcall(self.StopMovingOrSizing, self)

        -- Written immediately, combat or not: this is GetPoint (a read) and
        -- three assignments into a plain Lua table, not a secure write, so
        -- nothing here is ever refused and nothing needs deferring. An
        -- earlier version queued this for PLAYER_REGEN_ENABLED, which lost
        -- data -- runPending() repositions the anchor from ns.db.anchor
        -- before a queued save would run, so a /tb reset issued mid-drag
        -- was clobbered by the stale position the drag was carrying.
        saveAnchorPosition()
    end)
end

--- Build the pool. Out of combat only: creating a secure button writes
-- attributes, which is refused mid-fight the same as anything else.
-- Returns true once the buttons exist, false when the build was held.
function Bar.Build()
    if anchor then
        return true
    end

    if InCombatLockdown and InCombatLockdown() then
        -- pending is armed here too, not left for the caller: the buttons
        -- this build will eventually create start with no macros at all, so
        -- whoever finishes the build later must also apply.
        buildPending = true
        pending = true
        return false
    end

    buildPending = false
    createAnchor()

    for index = 1, Bar.MAX_BUTTONS do
        local button = CreateFrame(
            "Button",
            string.format("TrinketBarButton%d", index),
            anchor,
            "SecureActionButtonTemplate"
        )
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:EnableMouse(true)
        -- Both edges. This client performs a secure action on the press
        -- where others act on the release, and a button registered for only
        -- one of them can be handed a pass it will not act on.
        button:RegisterForClicks("AnyUp", "AnyDown")

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints(button)
        -- The standard action-bar crop: item icons carry their own border
        -- baked in, and without trimming it every button looks wrong next
        -- to the ones the game draws.
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.icon:Hide()

        -- A gold border on whichever trinkets are on. Drawn rather than
        -- taken from Blizzard's art: a texture path this client turns out
        -- not to have fails silently, drawing nothing and saying nothing
        -- about why.
        button.worn = button:CreateTexture(nil, "OVERLAY")
        button.worn:SetAllPoints(button)
        button.worn:SetColorTexture(1, 0.82, 0, 0.35)
        button.worn:Hide()

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(button)
        highlight:SetColorTexture(1, 1, 1, 0.2)

        -- Blizzard's own cooldown widget, so the sweep is the one the
        -- action bars draw. Through pcall because a template is not
        -- something this client family can be trusted to have, and an
        -- unknown one raises rather than returning nil. The sweep is
        -- decoration; equipping is the point.
        local created, cooldown = pcall(
            CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate"
        )
        if created and cooldown then
            cooldown:SetAllPoints(button)
            button.cooldown = cooldown
        end

        button:Hide()

        buttons[index] = button
    end

    return true
end

--- Point every button at a trinket, and hide the rest.
-- Returns true when it wrote, false when combat held it.
function Bar.Apply()
    if not anchor then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return false
    end

    pending = false

    local all = ns.Items.All()
    local shown = 0

    for index = 1, Bar.MAX_BUTTONS do
        local button = buttons[index]
        local entry = all[index]

        if entry then
            -- A macro rather than type="item": using an equippable item
            -- lets the game pick the slot, and this bar has to say which.
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macrotext1", "/equipslot "
                .. ns.Items.TRINKET_SLOTS[1] .. " " .. entry.name)
            button:SetAttribute("type2", "macro")
            button:SetAttribute("macrotext2", "/equipslot "
                .. ns.Items.TRINKET_SLOTS[2] .. " " .. entry.name)

            if entry.texture then
                button.icon:SetTexture(entry.texture)
                button.icon:Show()
            else
                button.icon:Hide()
            end

            button.worn:SetShown(entry.wornSlot ~= nil)

            button.entry = entry
            button:Show()
            shown = shown + 1
        else
            -- Cleared, not merely hidden. A hidden button still carrying an
            -- instruction is one keybind away from running it.
            button:SetAttribute("type1", nil)
            button:SetAttribute("macrotext1", nil)
            button:SetAttribute("type2", nil)
            button:SetAttribute("macrotext2", nil)

            button.icon:Hide()
            button.worn:Hide()

            button.entry = nil
            button:Hide()
        end
    end

    Bar.Layout(shown)
    Bar.RefreshCooldowns()

    return true
end

--- A fresh name -> entry map, used to re-resolve a trinket's coordinates for
-- a cooldown lookup rather than trusting whatever Apply last wrote.
local function freshEntriesByName()
    local byName = {}
    for _, entry in ipairs(ns.Items.All()) do
        byName[entry.name] = entry
    end
    return byName
end

--- Draw each button's cooldown sweep.
--
-- Separate from Apply because a cooldown starts without anything else
-- changing: the bar is right, only the sweeps are stale.
--
-- Re-resolved by name from a fresh bag walk rather than read through
-- button.entry.bag/.slot: those coordinates are a snapshot from the last
-- Apply, and Apply cannot repair them mid-fight. Clicking a button equips
-- the trinket it names and drops whatever comes off into that same bag
-- slot -- PLAYER_EQUIPMENT_CHANGED fires, but combat holds Apply, so
-- button.entry still names the old trinket at coordinates a different item
-- now occupies. Reading (bag, slot) at face value would paint the new
-- occupant's cooldown on a button whose macro still names the old trinket,
-- for as long as the fight lasts. Walking the bags is a pure read, legal in
-- combat, so it costs nothing to do here every time.
--
-- button.entry itself is left untouched: it drives the macro, which is a
-- secure attribute, and only the cooldown lookup uses the fresh coordinates.
function Bar.RefreshCooldowns()
    local fresh

    for index = 1, Bar.MAX_BUTTONS do
        local button = buttons[index]
        local cooldown = button and button.cooldown

        if cooldown then
            fresh = fresh or freshEntriesByName()

            -- nil when the name is no longer carried and not worn -- gone
            -- from the bags and the body both -- in which case no sweep is
            -- drawn rather than a wrong one.
            local current = button.entry and fresh[button.entry.name]
            local start, duration = ns.Items.Cooldown(current)

            if start and duration and duration > 0 then
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

--- Place the buttons that are showing, and size the anchor to hold them.
--
-- Placed by how many are showing rather than by index, so a gap never opens
-- where a hidden button would have been. Safe here because Apply only ever
-- runs out of combat, and moving a secure button is refused in it.
function Bar.Layout(shown)
    local size = iconSize()
    local columns = perRow()
    local placed = 0

    for index = 1, Bar.MAX_BUTTONS do
        local button = buttons[index]

        if index <= shown then
            local column = placed % columns
            local row = math.floor(placed / columns)

            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT", anchor, "TOPLEFT",
                column * (size + BUTTON_GAP),
                -row * (size + BUTTON_GAP)
            )
            placed = placed + 1
        end
    end

    local across = math.min(math.max(shown, 1), columns)
    local down = math.max(math.ceil(shown / columns), 1)

    anchor:SetSize(
        across * size + (across - 1) * BUTTON_GAP,
        down * size + (down - 1) * BUTTON_GAP
    )
end

--- Run whatever combat was holding.
local function runPending()
    if buildPending and Bar.Build() then
        pending = true
    end

    if pending and not (InCombatLockdown and InCombatLockdown()) then
        repositionAnchor()
    end

    if pending then
        Bar.Apply()
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("BAG_UPDATE_DELAYED")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
-- GetItemInfo answers with nothing for an item this client has not cached
-- yet, so a trinket sitting in the bags at a cold-cache login can be missing
-- from the bar with nothing else to bring it back. This event is the client
-- saying it has since learned what the item is.
watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
watcher:RegisterEvent("BAG_UPDATE_COOLDOWN")

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        runPending()
        return
    end

    if event == "BAG_UPDATE_COOLDOWN" then
        -- Nothing about the bar changed, only the sweeps over it. Re-pointing
        -- sixteen secure buttons for that would be a secure write for a
        -- purely cosmetic reason -- and refused outright mid-fight, which is
        -- exactly when trinket cooldowns are being watched.
        Bar.RefreshCooldowns()
        return
    end

    -- BAG_UPDATE_DELAYED rather than BAG_UPDATE: the latter fires once per
    -- bag per change, and re-pointing sixteen secure buttons five times for
    -- one looted item is work nobody asked for.
    Bar.Apply()
end)

ns.OnLogin(function()
    Bar.Build()
    Bar.Apply()
end)

-- Assigned below, where the setting is declared -- forward-declared here so
-- the command's closure can reach it without caring about file order.
local lockedSetting

ns.RegisterCommand("lock", "Stop the bar being dragged", function()
    -- Routed through ns.SetSettingValue rather than assigning
    -- ns.db.bar.locked directly, like every other writer -- but routing
    -- alone only fixes where the value is stored. What actually keeps the
    -- settings panel's checkbox from going stale when /tb lock changes the
    -- value out from under it is the setting's own onChange (below), which
    -- SetSettingValue is what makes reachable.
    ns.SetSettingValue(lockedSetting, not ns.db.bar.locked)
    ns.Print(ns.db.bar.locked and "Bar locked." or "Bar unlocked.")
end)

ns.RegisterCommand("reset", "Put the bar back in the middle", function()
    ns.db.anchor.point = DEFAULT_ANCHOR.point
    ns.db.anchor.x = DEFAULT_ANCHOR.x
    ns.db.anchor.y = DEFAULT_ANCHOR.y

    if InCombatLockdown and InCombatLockdown() then
        pending = true
        ns.Print("Bar will move back once combat ends.")
        return
    end

    repositionAnchor()
    ns.Print("Bar back in the middle.")
end)

-- Declared next to the code that reads them. Settings.lua renders whatever
-- has been declared, so adding one here needs no edit there.
ns.RegisterSetting({
    store = "bar",
    key = "iconSize",
    type = "slider",
    name = "Icon size",
    tooltip = "How big each trinket icon is.",
    min = 12,
    max = 48,
    step = 1,
    onChange = function() Bar.Apply() end,
})

ns.RegisterSetting({
    store = "bar",
    key = "perRow",
    type = "slider",
    name = "Buttons per row",
    tooltip = "How many icons sit side by side before the bar wraps onto another row.",
    min = 1,
    max = Bar.MAX_BUTTONS,
    step = 1,
    onChange = function() Bar.Apply() end,
})

lockedSetting = ns.RegisterSetting({
    store = "bar",
    key = "locked",
    type = "checkbox",
    name = "Lock the bar",
    tooltip = "Stops the bar being dragged around by accident.",
    -- Keeps the checkbox honest when the value changes from somewhere other
    -- than the checkbox itself -- /tb lock, now that it is routed through
    -- here too. Refresh sets the same value the widget already has when the
    -- change came from the widget, which is harmless, not a loop.
    onChange = function()
        if ns.SettingsPanel then
            ns.SettingsPanel.Refresh()
        end
    end,
})
