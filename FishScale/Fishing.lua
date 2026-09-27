local addonName, ns = ...

-- One key for the whole fishing loop.
--
-- An addon cannot cast by itself -- a spell only goes off from the player's
-- own key press or click -- so fully automatic recasting is not on offer to
-- anyone. What is: one key whose meaning follows the loop.
--
--   No line out     the key casts Fishing.
--   Bobber out      the key interacts with it, through the client's soft
--                   targeting, which picks the bobber out by itself.
--   Loot window     the key is let go, so it cannot recast over the loot.
--
-- With auto loot on, that is press, wait for the splash, press, press.
--
-- The key is only taken while a fishing pole is in your hands (or always,
-- if you ask), and never in combat: out of it, the key is yours again.

local Fishing = {}
ns.Fishing = Fishing

ns.AddDefaults({
    fishing = {
        enabled = true,
        key = "F",
        -- Take the key without a pole equipped, for a client that lets you
        -- fish without one.
        withoutPole = false,
        -- Turn auto loot on while fishing, and back to how it was after.
        autoLoot = true,
        -- How far the interact key reaches for the bobber. See DEFAULT_RANGE.
        range = 45,
        -- How much leeway it has in choosing what. See DEFAULT_ARC.
        arc = 2,
    },
})

-- Fishing's spell ID in Classic. Its name, looked up from this, is what the
-- cast button casts -- by name, so it is the best rank you know -- and what
-- a channel is recognised by.
local FISHING_SPELL_ID = 7620

-- Enum.ItemClass.Weapon and Enum.ItemWeaponSubclass.Fishingpole.
local WEAPON_CLASS = 2
local FISHING_POLE_SUBCLASS = 20
local MAIN_HAND_SLOT = 16

-- CVars changed while fishing, with the value each is set to. What they held
-- before is remembered and put back the moment fishing stops.
local SOFT_TARGET_CVARS = {
    -- Let the interact key find game objects -- the bobber is one -- by
    -- itself, without them being clicked or targeted first.
    SoftTargetInteract = "3",
}

-- How much leeway the interact key has in choosing what to aim at: 0 means
-- the player must be facing it, 1 and 2 widen that, 2 to any direction.
--
-- This is a trade, not a dial with a best setting, which is why it is a
-- setting rather than a constant. Too narrow and a bobber a few degrees off
-- centre is never found, and the key does nothing at all. Too wide and the
-- key starts preferring whatever else is around -- an NPC, a node, another
-- player -- and refuses with "you need to be closer" about a thing that is
-- not the bobber and was never going to be reachable.
--
-- Both failures look identical from the bank: the key does not reel in.
-- `/fs status` prints what the key is actually aimed at, which is the only
-- way to tell them apart.
local DEFAULT_ARC = 2
local MIN_ARC, MAX_ARC = 0, 2

-- 1 shipped as the default for one build and was wrong: at that setting the
-- interact key does not acquire a bobber on a long cast at all, so the key
-- does nothing and says nothing. Everyone who ran that build has it stored,
-- where a changed default cannot reach them.
--
-- Only 1 is reset, and only once. A player who deliberately chose 0 or 2
-- keeps it, because this is here to undo a mistake of ours rather than to
-- overrule a decision of theirs.
ns.AddMigration(2, function(db)
    if db.fishing and db.fishing.arc == 1 then
        db.fishing.arc = DEFAULT_ARC
    end
end)

-- How far the interact key will reach for the bobber, in yards.
--
-- This is the one number that decides whether a long cast can be reeled in,
-- and getting it wrong fails in a way that looks like nothing at all: the
-- bobber lands past the reach, the key finds nothing to interact with, and
-- says so by doing nothing -- while casting, which has no range to fall foul
-- of, keeps working perfectly. That is what was reported from the water.
--
-- 30 is what the interact-key fishing technique is usually described with.
-- The client's own ceiling is not documented anywhere, and it clamps silently
-- rather than refusing, so the honest thing is to ask for a generous value
-- and report back what was actually granted -- which Fishing.GrantedRange
-- below does, and `/fs status` prints.
local DEFAULT_RANGE = 45

-- Where a cast can land. Beyond this the client is certainly not going to
-- help, and asking for more only widens what else the key might grab.
local MIN_RANGE, MAX_RANGE = 5, 100

local guarded = ns.Guarded

local owner = CreateFrame("Frame", "FishScaleBindingOwner")
local castButton

local state = {
    channeling = false,
    looting = false,
}

-- Diagnostic scaffolding, off unless `/fs debug` turns it on.
--
-- The loop is driven entirely by events, and an event that does not arrive
-- leaves the key pointing at the wrong thing with nothing to correct it. From
-- outside the game the two are indistinguishable: a key that does nothing
-- looks the same whether the binding is wrong, the binding is missing, or the
-- binding is right and what it points at has stopped working. This says which.
local debugging = false

local function note(fmt, ...)
    if not debugging then
        return
    end
    ns.Print("|cff888888" .. string.format(fmt, ...) .. "|r")
end

--- A value as text, or "<secret>" where this client will not allow it.
--
-- tostring() is not the safe conversion it looks like. On a secret value it
-- neither raises nor de-secrets: what comes back is a secret *string*, and
-- the raise happens later, in whatever first tries to use it. Here that was
-- table.concat, several lines and one function away from the tostring that
-- looked harmless -- so the using has to happen in here, where it is caught.
--
-- The concatenation is the test. It is the operation that raised in the
-- crash this came from, so performing it inside the guard is what proves the
-- result is safe to hand out.
local function describeArg(value)
    return guarded(function()
        return "" .. tostring(value)
    end, "<secret>")
end

-- CVar name -> the value it held before fishing changed it.
local saved = {}

--- The localised name of Fishing, from whichever API this client has.
function Fishing.SpellName()
    local name = guarded(function()
        if C_Spell and C_Spell.GetSpellName then
            return C_Spell.GetSpellName(FISHING_SPELL_ID)
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(FISHING_SPELL_ID)
            return info and info.name
        end
        if GetSpellInfo then
            return (GetSpellInfo(FISHING_SPELL_ID))
        end
    end, nil)

    return name or "Fishing"
end

local function spellNameOf(spellID)
    return guarded(function()
        if C_Spell and C_Spell.GetSpellName then
            return C_Spell.GetSpellName(spellID)
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            return info and info.name
        end
        if GetSpellInfo then
            return (GetSpellInfo(spellID))
        end
    end, nil)
end

--- Whether a spell is Fishing, any rank. Compared by name, because every
-- rank has its own ID and they all share the one name.
local function isFishing(spellID)
    return guarded(function()
        return spellID == FISHING_SPELL_ID or spellNameOf(spellID) == Fishing.SpellName()
    end, false)
end

--- Whether a fishing pole is in the main hand.
function Fishing.PoleEquipped()
    return guarded(function()
        local itemID = GetInventoryItemID("player", MAIN_HAND_SLOT)
        if not itemID then
            return false
        end

        local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local _, _, _, _, _, classID, subclassID = getInfo(itemID)
        return classID == WEAPON_CLASS and subclassID == FISHING_POLE_SUBCLASS
    end, false)
end

--- Whether FishScale should be holding the key right now.
function Fishing.Active()
    local db = ns.db and ns.db.fishing
    if not (db and db.enabled) then
        return false
    end
    if InCombatLockdown() then
        return false
    end
    return db.withoutPole or Fishing.PoleEquipped()
end

local function setCVar(name, value)
    if saved[name] == nil then
        local current = GetCVar(name)
        -- A CVar this client does not have reads nil. Leave it alone rather
        -- than invent it.
        if current == nil then
            return
        end
        saved[name] = current
    end
    SetCVar(name, value)
end

--- The reach asked for, as a whole number inside the bounds. Clamped here
-- rather than trusted from the database, which a player can edit by hand.
local function requestedRange()
    local range = math.floor(tonumber(ns.db and ns.db.fishing and ns.db.fishing.range)
        or DEFAULT_RANGE)

    if range < MIN_RANGE then
        return MIN_RANGE
    elseif range > MAX_RANGE then
        return MAX_RANGE
    end
    return range
end

--- What the interact key is currently aimed at, as the client sees it.
--
-- "softinteract" is the client's own token for it, and it is the one thing
-- that settles an argument this addon cannot settle from outside: a key that
-- says "you need to be closer" while the bobber can still be clicked by hand
-- is not being refused for the bobber at all -- it has picked something else
-- and is complaining about that. Same object, same distance: a click and an
-- interact cannot disagree about range.
--
-- Returns a description, never a bare nil, because "nothing aimed at" and
-- "this client has no soft targeting" are different faults with the same
-- symptom.
function Fishing.SoftTarget()
    return guarded(function()
        if not UnitExists then
            return "this client has no soft targeting"
        end

        if not UnitExists("softinteract") then
            return "nothing"
        end

        local name = UnitName and UnitName("softinteract")
        if name and name ~= "" then
            return name
        end

        -- A game object is not a unit, so it has no name to give. The bobber
        -- is a game object, which makes this the answer we want to see.
        return "something unnamed (a game object -- possibly the bobber)"
    end, "could not be read")
end

--- What the client actually granted, which is not always what was asked for:
-- it clamps this CVar silently rather than refusing. nil on a client that
-- does not have the setting at all.
function Fishing.GrantedRange()
    return guarded(function()
        local current = GetCVar("SoftTargetInteractRange")
        return current and tonumber(current) or nil
    end, nil)
end

--- The arc asked for, clamped the same way the reach is.
local function requestedArc()
    local arc = math.floor(tonumber(ns.db and ns.db.fishing and ns.db.fishing.arc)
        or DEFAULT_ARC)

    if arc < MIN_ARC then
        return MIN_ARC
    elseif arc > MAX_ARC then
        return MAX_ARC
    end
    return arc
end

local function applyCVars()
    for name, value in pairs(SOFT_TARGET_CVARS) do
        setCVar(name, value)
    end
    setCVar("SoftTargetInteractRange", tostring(requestedRange()))
    setCVar("SoftTargetInteractArc", tostring(requestedArc()))
    if ns.db.fishing.autoLoot then
        setCVar("autoLootDefault", "1")
    end
end

local function restoreCVars()
    for name, value in pairs(saved) do
        SetCVar(name, value)
        saved[name] = nil
    end
end

--- Whether the line is actually out, asked of the client rather than
-- remembered from events.
--
-- UNIT_SPELLCAST_CHANNEL_START and _STOP are the only things that move
-- state.channeling, so a single missed edge leaves it stuck and nothing ever
-- puts it right: stuck true and the key never casts again, stuck false and it
-- never reels in. Events do go missing -- a loading screen, a disconnect, a
-- channel ended by something that reports it differently -- and "it worked
-- for a few minutes" is what that looks like from the bank of a lake.
--
-- UnitChannelInfo cannot drift, because it is the thing itself rather than a
-- memory of it. Three answers, not two: yes, no, and "this client will not
-- say" -- collapsing the last two would make a client without the API look
-- like a line that is never out.
function Fishing.Channeling()
    local live = guarded(function()
        if not UnitChannelInfo then
            return nil
        end

        local name = UnitChannelInfo("player")
        if name == nil then
            return "no"
        end
        return name == Fishing.SpellName() and "yes" or "no"
    end, nil)

    if live == "yes" then
        return true
    elseif live == "no" then
        return false
    end

    -- No answer to be had; the remembered edges are all there is.
    return state.channeling
end

--- What the key does right now: "cast", "interact", or nil for nothing.
function Fishing.KeyAction()
    if not Fishing.Active() then
        return nil
    end
    if state.looting then
        return nil
    end
    if Fishing.Channeling() then
        return "interact"
    end
    return "cast"
end

--- Point the key at whatever the loop needs next. Every change to the state
-- ends here, so there is one place that decides.
function Fishing.Refresh()
    -- Bindings cannot be touched in combat. PLAYER_REGEN_DISABLED fires just
    -- before the lockdown starts, which is where the key is given back.
    if InCombatLockdown() then
        return
    end

    ClearOverrideBindings(owner)

    local action = Fishing.KeyAction()
    if not Fishing.Active() then
        note("refresh: not active, key given back")
        restoreCVars()
        return
    end
    applyCVars()

    local key = ns.db.fishing.key
    if action == "cast" then
        SetOverrideBindingClick(owner, true, key, castButton:GetName(), "LeftButton")
    elseif action == "interact" then
        SetOverrideBinding(owner, true, key, "INTERACTTARGET")
    end

    note("refresh: %s -> %s (channel flag=%s, client=%s, looting=%s)",
        key, tostring(action), tostring(state.channeling),
        tostring(Fishing.Channeling()), tostring(state.looting))
end

-- The last thing the trace reported the key aimed at, so it says so on a
-- change rather than five times a second.
local lastAimedAt

-- The events are still what drives the loop -- polling is a net under it, not
-- a replacement. Without this, a missed edge is only corrected by whatever
-- event happens to fire next, and if the player is standing still fishing,
-- that may be nothing at all.
local POLL_INTERVAL = 0.2
local sincePoll = 0

owner:SetScript("OnUpdate", function(_, elapsed)
    sincePoll = sincePoll + elapsed
    if sincePoll < POLL_INTERVAL then
        return
    end
    sincePoll = 0

    -- Only while the key is ours. Off the water this costs one comparison.
    if not Fishing.Active() then
        return
    end

    -- Traced while the line is out, because the interesting moment has no
    -- event to hang off. The key finding nothing produces no error and no
    -- message -- the player presses it and the game does not react at all --
    -- so the only way to see it is to watch what the key is aimed at as the
    -- bobber sits there.
    if debugging and Fishing.Channeling() then
        local aimed = Fishing.SoftTarget()
        if aimed ~= lastAimedAt then
            lastAimedAt = aimed
            -- The settings that decided it, on the same line. A trace saying
            -- only "nothing" is a reading nobody can interpret a day later
            -- without also knowing what the arc and reach were at the time,
            -- and those are exactly what gets changed between readings.
            note("aimed at: %s (arc %s, reach %s)", aimed,
                describeArg(requestedArc()), describeArg(Fishing.GrantedRange()))
        end
    end

    -- Compared against the addon's own belief rather than against a separate
    -- record of what the poll last saw. A second variable only the poll
    -- updates goes stale the moment an event moves the first one, and then
    -- the two agree by accident and the poll stops looking.
    local channeling = Fishing.Channeling()
    if channeling == state.channeling then
        return
    end

    note("poll: line %s without an event saying so", channeling and "out" or "in")
    state.channeling = channeling
    Fishing.Refresh()
end)

--- Build the button the key clicks to cast. Once, at login, out of combat.
local function createCastButton()
    castButton = CreateFrame("Button", "FishScaleCastButton", UIParent, "SecureActionButtonTemplate")
    castButton:SetSize(1, 1)
    castButton:SetAlpha(0)
    castButton:EnableMouse(false)
    -- Both edges, as ClickHeal's buttons need on this client: it acts on the
    -- press, so a button asking only for the release never casts, and the
    -- secure handler itself ignores whichever edge the client is not set to
    -- act on.
    castButton:RegisterForClicks("AnyUp", "AnyDown")
    castButton:SetAttribute("type", "spell")
    castButton:SetAttribute("spell", Fishing.SpellName())
    Fishing.castButton = castButton
end

ns.OnLogin(function()
    createCastButton()
    Fishing.Refresh()
end)

-- Said once per cast at most. The client repeats an interact refusal for as
-- long as the key is held, and a diagnostic that buries the chat is one the
-- player turns off before it has told anyone anything.
local reportedThisCast = false

--- Say what the interact key was aimed at when the client refused it.
--
-- Caught at the moment of failure rather than asked for afterwards. "You need
-- to be closer" names no target, and by the time anyone types a command the
-- bobber may be in, the cast retried, the soft target moved on. This is the
-- state as it was when it went wrong, which is the only state worth having.
local function reportInteractFailure(message)
    if reportedThisCast or not Fishing.Channeling() then
        return
    end
    reportedThisCast = true

    -- describeArg, not tostring: the message comes straight off an event and
    -- a secret one would sail through tostring and raise in this concat --
    -- the same fault, in the reporting for the same bug.
    ns.Print("|cffff9900" .. describeArg(message) .. "|r")
    ns.Print(string.format(
        -- describeArg on every one of these, not tostring. string.format
        -- raises on a secret string exactly as concat does, and a value that
        -- reached here through tonumber or GetCVar is not proven safe just
        -- because it came back. This function exists to report a fault; it
        -- must not become one.
        "It was aimed at: %s. Reach %s, arc %s.",
        describeArg(Fishing.SoftTarget()),
        describeArg(Fishing.GrantedRange()),
        describeArg(guarded(function() return GetCVar("SoftTargetInteractArc") end, "?"))))
    ns.Print("If that is not the bobber, the key is grabbing something else "
        .. "and no reach will help. Try /fs arc 0.")
end

owner:RegisterEvent("UI_ERROR_MESSAGE")
owner:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
owner:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
owner:RegisterEvent("LOOT_OPENED")
owner:RegisterEvent("LOOT_CLOSED")

owner:SetScript("OnEvent", function(_, event, ...)
    local unit, _, spellID = ...

    -- Logged for the player only. Every nameplate in sight reports its casts
    -- through these same events, which buries the one cast being diagnosed
    -- and was six crashes a second before the conversion below was made safe.
    if debugging and (unit == nil or unit == "player" or event:sub(1, 5) ~= "UNIT_") then
        local parts = {}
        for index = 1, select("#", ...) do
            parts[index] = describeArg((select(index, ...)))
        end
        note("event %s(%s)", event, guarded(function()
            return table.concat(parts, ", ")
        end, "?"))
    end

    if not castButton then
        return
    end

    if event == "UI_ERROR_MESSAGE" then
        -- The payload is (errorType, message) on clients that have the type
        -- and (message) on those that do not, so take whichever argument is
        -- the string rather than counting on a position.
        local message = unit
        if type(message) ~= "string" then
            message = select(2, ...)
        end
        reportInteractFailure(message)
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The last moment bindings can change before the fight locks them:
        -- give the key back so it does its usual job while fighting.
        ClearOverrideBindings(owner)
        restoreCVars()
        return
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if unit ~= "player" or not isFishing(spellID) then
            return
        end
        state.channeling = true
        -- A new cast earns a new report: the last one's answer was about a
        -- bobber that is no longer there.
        reportedThisCast = false
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if unit ~= "player" or not isFishing(spellID) then
            return
        end
        state.channeling = false
    elseif event == "LOOT_OPENED" then
        state.looting = true
    elseif event == "LOOT_CLOSED" then
        state.looting = false
    end

    Fishing.Refresh()
end)

--- Change the key. Anything the client accepts as a binding: F, SHIFT-F,
-- BUTTON4, and so on.
function Fishing.SetKey(key)
    key = key and key:match("^%s*(.-)%s*$"):upper() or ""
    if key == "" then
        return false
    end

    -- Let go of the old key before taking the new one.
    if not InCombatLockdown() then
        ClearOverrideBindings(owner)
    end
    ns.db.fishing.key = key
    Fishing.Refresh()
    return true
end

local function onOff(value)
    return value and "on" or "off"
end

-- Declared next to the code that reads them. Settings.lua renders whatever it
-- finds registered, so none of this needs an edit there.
ns.RegisterSetting({
    store = "fishing",
    key = "enabled",
    type = "checkbox",
    name = "Turn FishScale on",
    tooltip = "Take the key while a fishing pole is in your hands.",
    onChange = function() Fishing.Refresh() end,
})

ns.RegisterSetting({
    store = "fishing",
    key = "key",
    type = "keybind",
    name = "Fishing key",
    tooltip = "The one key that casts, then picks the bobber up.",
    onChange = function()
        -- Let go of the old key before taking the new one, or the binding
        -- this owner holds on it outlives the change.
        if not InCombatLockdown() then
            ClearOverrideBindings(owner)
        end
        Fishing.Refresh()
    end,
})

ns.RegisterSetting({
    store = "fishing",
    key = "withoutPole",
    type = "checkbox",
    name = "Take the key without a fishing pole",
    tooltip = "For a client that lets you fish without one.",
    onChange = function() Fishing.Refresh() end,
})

ns.RegisterSetting({
    store = "fishing",
    key = "autoLoot",
    type = "checkbox",
    name = "Turn auto loot on while fishing",
    tooltip = "And put your own setting back the moment fishing stops.",
    onChange = function()
        if not InCombatLockdown() then
            restoreCVars()
        end
        Fishing.Refresh()
    end,
})

ns.RegisterSetting({
    store = "fishing",
    key = "range",
    type = "slider",
    name = "How far the key reaches for the bobber",
    tooltip = "A cast landing past this cannot be reeled in with the key. "
        .. "The client may grant less than you ask for.",
    min = MIN_RANGE,
    max = MAX_RANGE,
    step = 1,
    -- The slider shows what was asked for; this adds what was granted, when
    -- the two differ. The client clamps this setting silently rather than
    -- refusing, so a slider reading 45 beside a client that allowed 20 would
    -- be a lie with nothing to catch it.
    describe = function(value)
        local granted = Fishing.GrantedRange()
        if granted and granted < value then
            return string.format("%d yards (client granted %d)", value, granted)
        end
        return string.format("%d yards", value)
    end,
    onChange = function()
        -- Put the old reach back before asking for the new one, or setCVar
        -- remembers the fishing value as the player's own.
        if not InCombatLockdown() then
            restoreCVars()
        end
        Fishing.Refresh()
    end,
})

ns.RegisterSetting({
    store = "fishing",
    key = "arc",
    type = "slider",
    name = "How freely the key chooses what to aim at",
    tooltip = "0 must be facing it, 2 any direction. Too narrow and the "
        .. "bobber is never found; too wide and the key prefers whatever "
        .. "else is nearby.",
    min = MIN_ARC,
    max = MAX_ARC,
    step = 1,
    describe = function(value)
        return value == 0 and "0 (must be facing it)"
            or value == 1 and "1 (some leeway)"
            or "2 (any direction)"
    end,
    onChange = function()
        if not InCombatLockdown() then
            restoreCVars()
        end
        Fishing.Refresh()
    end,
})

ns.RegisterCommand("key", "Set the fishing key, e.g. /fs key F", function(rest)
    if rest == "" then
        ns.Print("Fishing key: " .. ns.db.fishing.key)
    elseif Fishing.SetKey(rest) then
        ns.Print("Fishing key set to " .. ns.db.fishing.key .. ".")
    end
end)

ns.RegisterCommand("on", "Turn FishScale on", function()
    ns.db.fishing.enabled = true
    Fishing.Refresh()
    ns.Print("On.")
end)

ns.RegisterCommand("off", "Turn FishScale off and give the key back", function()
    ns.db.fishing.enabled = false
    Fishing.Refresh()
    ns.Print("Off.")
end)

ns.RegisterCommand("nopole", "Take the key even without a fishing pole equipped", function()
    ns.db.fishing.withoutPole = not ns.db.fishing.withoutPole
    Fishing.Refresh()
    ns.Print("Without a pole: " .. onOff(ns.db.fishing.withoutPole) .. ".")
end)

ns.RegisterCommand("autoloot", "Turn auto loot on while fishing", function()
    ns.db.fishing.autoLoot = not ns.db.fishing.autoLoot
    -- Put auto loot back as it was before choosing again, so turning this
    -- off really does give the player their own setting back.
    if not InCombatLockdown() then
        restoreCVars()
    end
    Fishing.Refresh()
    ns.Print("Auto loot while fishing: " .. onOff(ns.db.fishing.autoLoot) .. ".")
end)

ns.RegisterCommand("arc", "How freely the key picks a target, 0 to 2, e.g. /fs arc 2", function(rest)
    if rest ~= "" then
        local wanted = tonumber(rest)
        if not wanted then
            ns.Print("That is not a number between 0 and 2.")
            return
        end
        ns.db.fishing.arc = wanted
        -- Put the old arc back before asking for the new one, or setCVar
        -- remembers the fishing value as the player's own.
        if not InCombatLockdown() then
            restoreCVars()
        end
        Fishing.Refresh()
        if ns.SettingsPanel then
            ns.SettingsPanel.Refresh()
        end
    end

    ns.Print(string.format("Arc: %d (%s).", requestedArc(),
        requestedArc() == 0 and "must be facing it"
            or requestedArc() == 1 and "some leeway"
            or "any direction"))
end)

ns.RegisterCommand("status", "Show what the key is doing", function()
    local db = ns.db.fishing
    local action = Fishing.KeyAction()
    ns.Print(string.format(
        "%s. Key %s: %s. Pole equipped: %s. Without a pole: %s. Auto loot: %s.",
        db.enabled and "On" or "Off",
        db.key,
        action == "cast" and "casts " .. Fishing.SpellName()
            or action == "interact" and "picks up the bobber"
            or "not taken",
        Fishing.PoleEquipped() and "yes" or "no",
        onOff(db.withoutPole),
        onOff(db.autoLoot)
    ))

    -- What the addon believes against what the client says. A key that does
    -- nothing is either bound to the wrong thing or bound to the right thing
    -- with the ground cut from under it, and only these two lines together
    -- tell those apart: soft targeting off is what makes INTERACTTARGET find
    -- no bobber, and it leaves casting working perfectly.
    ns.Print(string.format(
        "Line out: addon thinks %s, client says %s.",
        onOff(state.channeling), onOff(Fishing.Channeling())))

    local granted = Fishing.GrantedRange()
    local asked = requestedRange()
    if granted == nil then
        ns.Print("Reach: this client has no SoftTargetInteractRange setting.")
    elseif granted < asked then
        ns.Print(string.format(
            "Reach: asked for %d yards, client granted %d. A cast landing "
                .. "past %d cannot be reeled in with the key.",
            asked, granted, granted))
    else
        ns.Print(string.format("Reach: %d yards.", granted))
    end

    -- Printed beside the reach because the two fail identically -- the key
    -- does nothing -- and only seeing both says which one is at fault.
    local arc = guarded(function() return GetCVar("SoftTargetInteractArc") end, nil)
    ns.Print(string.format("Arc: %s (%s).", describeArg(arc),
        arc == "0" and "must be facing it"
            or arc == "1" and "some leeway"
            or "any direction"))

    -- The line that settles it. Run this with the bobber out: if the key is
    -- aimed at a murloc, no amount of reach or arc was ever going to help.
    local aimed = Fishing.SoftTarget()
    ns.Print("Interact key is aimed at: " .. aimed .. ".")

    -- Said because "nothing" during the wait is the right answer, not a
    -- fault, and reading it as one sent four rounds of this chasing reach
    -- and arc settings that were never involved. A bobber is not something
    -- the game lets anyone interact with until the fish takes it.
    if aimed == "nothing" and Fishing.Channeling() then
        ns.Print("|cffffcc33Nothing to aim at yet is normal:|r the bobber "
            .. "only becomes interactable when it splashes. The reading that "
            .. "matters is taken at the splash, not during the wait.")
    end
end)

ns.RegisterCommand("range", "How far the key reaches for the bobber, e.g. /fs range 45", function(rest)
    if rest ~= "" then
        local wanted = tonumber(rest)
        if not wanted then
            ns.Print("That is not a number of yards.")
            return
        end
        ns.db.fishing.range = wanted
        -- Put the old reach back before asking for the new one, or setCVar
        -- remembers the fishing value as the player's own.
        if not InCombatLockdown() then
            restoreCVars()
        end
        Fishing.Refresh()
    end

    local granted = Fishing.GrantedRange()
    ns.Print(string.format("Reach: asked for %d yards, client granted %s.",
        requestedRange(), granted and describeArg(granted) or "nothing"))
end)

ns.RegisterCommand("debug", "Log every event and binding change to chat", function()
    debugging = not debugging
    ns.Print("Debug logging: " .. onOff(debugging) .. ".")
    if debugging then
        ns.Print("Fish until it stops responding, then run /fs status.")
    end
end)
