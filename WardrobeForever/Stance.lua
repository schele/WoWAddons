local _, ns = ...

-- Weapons with the shift, from the stance bar.
--
-- Forever lets no addon change gear in a fight, but it lets the player's
-- own click run /equipslot. So once a chosen set holds a weapon, each
-- stance bar button gets a button of WardrobeForever's laid over it: a
-- secure macro button that casts the form, as the stance button did, and in
-- the same click swaps the weapons. Going into a form, its set's weapons;
-- leaving it, the normal ones. Forms.lua still does everything else, and
-- all of it out of combat.
--
-- Druids only for now: the macros take a click on the form you are in to
-- leave it, which a warrior's stance or a rogue's stealth does not do.
--
-- The macro text is written only out of combat (secure buttons are locked
-- in a fight), whenever Forms.lua has looked at the gear.

local Forms = ns.Forms
if not (Forms and StanceBar and StanceBar.actionButtons) then
    return
end

local Stance = {}
ns.Stance = Stance
Stance.buttons = {}

-- The slots a click may change in a fight: main hand, off hand, ranged.
local WEAPON_SLOTS = { 16, 17, 18 }
local MAIN_HAND, OFF_HAND, RANGED = 16, 17, 18

--- The name /equipslot takes for the item with `guid` (what Carl tested
-- with), or nil when it is not on the character.
local function itemName(guid)
    if not guid then
        return nil
    end
    local location = C_Item.GetItemLocation(guid)
    return location and C_Item.GetItemName(location) or nil
end

local function isDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

--- The forms by stance bar index, each with its set's items; the weapon
-- slots the macros look after; and whether any set swaps a weapon at all.
-- A set with an item in either hand brings both hands in (its off hand is
-- often saved empty, beside a two-hander), so leaving it puts the normal
-- pair back.
local function lookAtSets()
    local byIndex, weaponSlots, swapsAny = {}, {}, false
    for _, form in ipairs(Forms.List()) do
        local setID = Forms.GetSet(form.spellID)
        local items = setID and Forms.SetItems(setID) or {}
        byIndex[form.index] = { name = form.name, items = items }
        if items[MAIN_HAND] or items[OFF_HAND] then
            weaponSlots[MAIN_HAND], weaponSlots[OFF_HAND] = true, true
        end
        if items[RANGED] then
            weaponSlots[RANGED] = true
        end
        for _, slot in ipairs(WEAPON_SLOTS) do
            if items[slot] then
                swapsAny = true
            end
        end
    end
    return byIndex, weaponSlots, swapsAny
end

--- Per weapon slot, what a click on this form's button puts on when it
-- leaves the form (`leave`: the normal weapon) and when it enters it
-- (`enter`: the set's, or the normal one). Nil where there is nothing to
-- put on: a slot saved empty, or the off hand beside a set's main hand,
-- which is the game's to fill (a two-hander takes it).
local function swapsFor(form, weaponSlots)
    local swaps = {}
    for _, slot in ipairs(WEAPON_SLOTS) do
        if weaponSlots[slot] then
            local normal = Forms.Normal(slot) or nil
            local own = form.items[slot]
            local enter
            if own then
                enter = own
            elseif own == nil and not (slot == OFF_HAND and form.items[MAIN_HAND]) then
                enter = normal
            end
            swaps[slot] = { leave = normal, enter = enter }
        end
    end
    return swaps
end

--- The macro for stance button `index`: cast its form, then per weapon
-- slot the normal weapon if this click leaves the form ([form:i]) and the
-- form's own if it enters it ([noform:i]); one line when they are alike.
local function macroFor(index, form, weaponSlots)
    local lines = { "/cast " .. form.name }
    local swaps = swapsFor(form, weaponSlots)
    for _, slot in ipairs(WEAPON_SLOTS) do
        local swap = swaps[slot]
        if swap then
            local leave, enter = itemName(swap.leave), itemName(swap.enter)
            if leave and leave == enter then
                lines[#lines + 1] = ("/equipslot %d %s"):format(slot, leave)
            else
                if leave then
                    lines[#lines + 1] = ("/equipslot [form:%d] %d %s"):format(index, slot, leave)
                end
                if enter then
                    lines[#lines + 1] = ("/equipslot [noform:%d] %d %s"):format(index, slot, enter)
                end
            end
        end
    end
    return table.concat(lines, "\n")
end

--- What a click on button `index` is about to put on, [slot] = GUID: the
-- `leave` side in that form, the `enter` side out of it.
local function clickTargets(index)
    local byIndex, weaponSlots = lookAtSets()
    local form = byIndex[index]
    local targets = {}
    if not form then
        return targets
    end
    local leaving = GetShapeshiftForm() == index
    for slot, swap in pairs(swapsFor(form, weaponSlots)) do
        targets[slot] = leaving and swap.leave or swap.enter
    end
    return targets
end

local function createButton(index, stanceButton)
    local button = CreateFrame("Button", "WardrobeForeverStance" .. index, stanceButton, "SecureActionButtonTemplate")
    button:SetAllPoints(stanceButton)
    button:SetFrameLevel(stanceButton:GetFrameLevel() + 5)
    -- Both edges, as on this client a secure button acts on whichever the
    -- player's settings say (see FishingForever's cast button).
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    -- The stance button underneath no longer sees the mouse: its glow and
    -- tooltip are drawn here instead.
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetShapeshift(index)
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("PreClick", function()
        Forms.ExpectClick(clickTargets(index))
    end)
    Stance.buttons[index] = button
    return button
end

--- Edit Mode moves the bar and Quick Keybind mode binds it: both need the
-- stance buttons themselves.
local function editing()
    return (EditModeManagerFrame and EditModeManagerFrame:IsShown())
        or (QuickKeybindFrame and QuickKeybindFrame:IsShown()) or false
end

local hooked = {}
local function watchModes()
    for _, frame in ipairs({ EditModeManagerFrame, QuickKeybindFrame }) do
        if frame and not hooked[frame] then
            hooked[frame] = true
            frame:HookScript("OnShow", function() Stance.Refresh() end)
            frame:HookScript("OnHide", function() Stance.Refresh() end)
        end
    end
end

--- Lay the buttons over the stance bar, or take them away, and write their
-- macros. Out of combat only; Forms.lua calls this again when a fight ends.
function Stance.Refresh()
    if InCombatLockdown() then
        return
    end
    watchModes()
    local byIndex, weaponSlots, swapsAny = lookAtSets()
    local needed = swapsAny and isDruid()
    local hide = editing()
    for index, stanceButton in ipairs(StanceBar.actionButtons) do
        local form = byIndex[index]
        local text = needed and form and macroFor(index, form, weaponSlots) or nil
        local button = Stance.buttons[index]
        if text and not button then
            button = createButton(index, stanceButton)
        end
        if button then
            if text and button:GetAttribute("macrotext") ~= text then
                button:SetAttribute("macrotext", text)
            end
            button:SetShown(text ~= nil and not hide)
        end
    end
end
