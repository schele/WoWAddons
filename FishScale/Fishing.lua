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
    -- A cast lands well past the default interact range.
    SoftTargetInteractRange = "30",
}

local guarded = ns.Guarded

local owner = CreateFrame("Frame", "FishScaleBindingOwner")
local castButton

local state = {
    channeling = false,
    looting = false,
}

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

local function applyCVars()
    for name, value in pairs(SOFT_TARGET_CVARS) do
        setCVar(name, value)
    end
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

--- What the key does right now: "cast", "interact", or nil for nothing.
function Fishing.KeyAction()
    if not Fishing.Active() then
        return nil
    end
    if state.looting then
        return nil
    end
    if state.channeling then
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
end

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

owner:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
owner:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
owner:RegisterEvent("LOOT_OPENED")
owner:RegisterEvent("LOOT_CLOSED")

owner:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if not castButton then
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
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
end)
