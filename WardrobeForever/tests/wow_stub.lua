-- A stand-in for the bits of the Forever client WardrobeForever touches: the
-- character sheet's slot buttons and Blizzard's equipment pop-out.
--
-- The pop-out's functions below are copies of Blizzard's own decisions from
-- Gethe/wow-ui-source, branch "forever" (1.60.1):
--   Blizzard_FrameXML/Camelot/EquipmentFlyout.lua
--   Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua
--   Blizzard_FrameXML/Shared/EquipmentManager.lua
-- trimmed to what decides whether the pop-out opens, stays open or closes.
-- They matter more than anything else here: Blizzard's pop-out re-checks Alt
-- every frame and hides itself when Alt is up, so a test that did not run
-- Blizzard's per-frame check could pass while the real pop-out vanished.

local stub = {}

local LOCATION_PLAYER = 0x00100000
local LOCATION_BAGS = 0x00200000
local LOCATION_BANK = 0x00400000
local BAG_BIT_OFFSET = 8

stub.SLOT = {
    HEAD = 1,
    LEGS = 7,
    FEET = 8,
    FINGER0 = 11,
    FINGER1 = 12,
    MAINHAND = 16,
}

-- Item locations, packed the way GetInventoryItemsForSlot packs them.
function stub.worn(slotID)
    return LOCATION_PLAYER | slotID
end

function stub.inBag(bag, slot)
    return LOCATION_PLAYER | LOCATION_BAGS | (bag << BAG_BIT_OFFSET) | slot
end

function stub.inBank(slot)
    return LOCATION_PLAYER | LOCATION_BANK | slot
end

function stub.newEnv()
    local env = {
        __frames = {},
        -- Which frames the cursor is over right now, keyed by frame.
        __mouseOver = {},
        __altDown = false,
        -- What GetInventoryItemsForSlot returns: [slotID] = { [location] = itemID }.
        __items = {},
        -- Where Blizzard last anchored the slot tooltip: "flyout" or "slot".
        __tooltip = nil,
    }
    env._G = env
    setmetatable(env, { __index = _G })

    local function makeFrame(name, parent)
        local frame = {
            name = name,
            parent = parent,
            shown = true,
            scripts = {},
            hooks = {},
            registeredEvents = {},
        }

        function frame:Show()
            if not self.shown then
                self.shown = true
                if self.scripts.OnShow then self.scripts.OnShow(self) end
            end
        end

        function frame:Hide()
            if self.shown then
                self.shown = false
                if self.scripts.OnHide then self.scripts.OnHide(self) end
            end
        end

        function frame:IsShown() return self.shown end
        function frame:IsMouseOver() return env.__mouseOver[self] == true end
        function frame:SetScript(script, fn) self.scripts[script] = fn end
        -- The handler the frame was built with, not the hooks on top of it.
        function frame:GetScript(script) return self.scripts[script] end

        function frame:HookScript(script, fn)
            self.hooks[script] = self.hooks[script] or {}
            table.insert(self.hooks[script], fn)
        end

        function frame:RegisterEvent(event) self.registeredEvents[event] = true end
        function frame:UnregisterEvent(event) self.registeredEvents[event] = nil end
        function frame:GetID() return self.id end
        function frame:GetParent() return self.parent end

        -- What the client does when a script fires: the handler, then its hooks.
        function frame:Fire(script, ...)
            if self.scripts[script] then self.scripts[script](self, ...) end
            for _, hook in ipairs(self.hooks[script] or {}) do
                hook(self, ...)
            end
        end

        table.insert(env.__frames, frame)
        return frame
    end

    env.CreateFrame = function(_, name, parent)
        local frame = makeFrame(name, parent)
        if name then env[name] = frame end
        return frame
    end

    env.IsModifiedClick = function(action)
        return action == "SHOWITEMFLYOUT" and env.__altDown
    end

    env.INVSLOT_AMMO = 0
    env.ITEM_INVENTORY_LOCATION_PLAYER = LOCATION_PLAYER
    env.ITEM_INVENTORY_LOCATION_BAGS = LOCATION_BAGS
    env.ITEM_INVENTORY_LOCATION_BANK = LOCATION_BANK
    env.ITEM_INVENTORY_BAG_BIT_OFFSET = BAG_BIT_OFFSET
    env.ITEM_INVENTORY_BANK_BAG_OFFSET = 4

    env.bit = {
        band = function(a, b) return a & b end,
        lshift = function(a, n) return a << n end,
        rshift = function(a, n) return a >> n end,
    }

    env.GetInventoryItemsForSlot = function(slotID, itemTable)
        for location, itemID in pairs(env.__items[slotID] or {}) do
            itemTable[location] = itemID
        end
    end

    -- Shared/EquipmentManager.lua, verbatim apart from the bit shim above.
    env.EquipmentManager_GetLocationData = function(location)
        local bit = env.bit
        local locationData = {}
        if location < 0 then
            return locationData
        end

        locationData.isPlayer = (bit.band(location, env.ITEM_INVENTORY_LOCATION_PLAYER) ~= 0)
        locationData.isBank = (bit.band(location, env.ITEM_INVENTORY_LOCATION_BANK) ~= 0)
        locationData.isBags = (bit.band(location, env.ITEM_INVENTORY_LOCATION_BAGS) ~= 0)

        locationData.slot = location
        if locationData.isPlayer then
            locationData.slot = locationData.slot - env.ITEM_INVENTORY_LOCATION_PLAYER
        elseif locationData.isBank then
            locationData.slot = locationData.slot - env.ITEM_INVENTORY_LOCATION_BANK
        end

        if locationData.isBags then
            locationData.slot = locationData.slot - env.ITEM_INVENTORY_LOCATION_BAGS
            locationData.bag = bit.rshift(locationData.slot, env.ITEM_INVENTORY_BAG_BIT_OFFSET)
            locationData.slot = locationData.slot - bit.lshift(locationData.bag, env.ITEM_INVENTORY_BAG_BIT_OFFSET)

            if locationData.isBank then
                locationData.bag = locationData.bag + env.ITEM_INVENTORY_BANK_BAG_OFFSET
            end
        end

        return locationData
    end

    -- The pop-out ------------------------------------------------------------

    local flyout = makeFrame("EquipmentFlyoutFrame")
    flyout.shown = false
    flyout.buttonFrame = makeFrame("EquipmentFlyoutFrameButtons", flyout)
    flyout.NavigationFrame = makeFrame(nil, flyout)
    flyout.NavigationFrame.shown = false
    env.EquipmentFlyoutFrame = flyout

    -- How many times each popout arrow was asked to redraw.
    env.__arrowRefreshes = {}
    env.EquipmentFlyoutPopoutButton_RefreshVisualState = function(popoutButton)
        env.__arrowRefreshes[popoutButton] = (env.__arrowRefreshes[popoutButton] or 0) + 1
    end

    -- EquipmentFlyout_OnHide
    flyout.scripts.OnHide = function(self)
        if self.button and self.button.popoutButton then
            local popoutButton = self.button.popoutButton
            popoutButton.flyoutLocked = false
            env.EquipmentFlyoutPopoutButton_RefreshVisualState(popoutButton)
        end
        self.button = nil
    end

    -- EquipmentFlyout_Show, minus building the item buttons.
    env.EquipmentFlyout_Show = function(itemButton)
        if flyout:IsShown() and flyout.button ~= itemButton then
            flyout:Hide()
        end
        if flyout.button and flyout.button ~= itemButton then
            local popoutButton = flyout.button.popoutButton
            if popoutButton and popoutButton.flyoutLocked then
                popoutButton.flyoutLocked = false
                env.EquipmentFlyoutPopoutButton_RefreshVisualState(popoutButton)
            end
        end
        flyout.button = itemButton
        flyout:Show()
    end

    env.EquipmentFlyout_UpdateFlyout = function(button)
        local id = button.id or button:GetID()
        if id ~= env.INVSLOT_AMMO then
            local hasLock = button.popoutButton and button.popoutButton.flyoutLocked
            if (env.IsModifiedClick("SHOWITEMFLYOUT") and not (flyout:IsShown() and flyout.button == button)) or
                hasLock then
                env.EquipmentFlyout_Show(button)
            elseif (flyout:IsShown() and flyout.button == button) and
                not hasLock and not env.IsModifiedClick("SHOWITEMFLYOUT") then
                flyout:Hide()
            end
        end
    end

    -- EquipmentFlyout_OnUpdate: runs every frame while the pop-out is shown.
    flyout.scripts.OnUpdate = function(self)
        if not env.IsModifiedClick("SHOWITEMFLYOUT") then
            local button = self.button
            if button and button.popoutButton and button.popoutButton.flyoutLocked then
                env.EquipmentFlyout_UpdateFlyout(button)
            elseif button and button:IsMouseOver() then
                local onEnterFunc = button:GetScript("OnEnter")
                if onEnterFunc then
                    onEnterFunc(button)
                end
            else
                self:Hide()
            end
        end
    end

    -- EquipmentFlyoutPopoutButton_OnClick: the arrow beside a slot, shown
    -- while the equipment manager tab is open, pins the pop-out open.
    env.EquipmentFlyoutPopoutButton_OnClick = function(self)
        if self.flyoutLocked then
            self.flyoutLocked = false
            flyout:Hide()
        else
            self.flyoutLocked = true
            env.EquipmentFlyout_Show(self:GetParent())
        end
        env.EquipmentFlyoutPopoutButton_RefreshVisualState(self)
    end

    -- EquipmentFlyoutButton_OnClick: clicking an item in the pop-out. The
    -- equipping itself is the paper doll's onClickFunc, left out here.
    env.EquipmentFlyoutButton_OnClick = function()
        local button = flyout.button
        if button.popoutButton and button.popoutButton.flyoutLocked then
            flyout:Hide()
        end
    end

    -- The character sheet ---------------------------------------------------

    env.PaperDollItemSlotButton_OnEnter = function(self)
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
        env.EquipmentFlyout_UpdateFlyout(self)
        -- EquipmentFlyout_SetTooltipAnchor: beside the pop-out when it is open.
        env.__tooltip = flyout:IsShown() and "flyout" or "slot"
    end

    env.PaperDollItemSlotButton_OnLeave = function(self)
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
        env.__tooltip = nil
    end

    local itemsFrame = makeFrame("PaperDollItemsFrame")
    itemsFrame.flyoutSettings = {}
    itemsFrame.EquipmentSlots = {}
    itemsFrame.WeaponSlots = {}
    env.PaperDollItemsFrame = itemsFrame

    local function makeSlot(name, id, list)
        local slot = makeFrame(name, itemsFrame)
        slot.id = id
        slot.popoutButton = makeFrame(name .. "PopoutButton", slot)
        slot.popoutButton.shown = false
        slot.scripts.OnEnter = env.PaperDollItemSlotButton_OnEnter
        slot.scripts.OnLeave = env.PaperDollItemSlotButton_OnLeave
        table.insert(list, slot)
        env[name] = slot
        return slot
    end

    makeSlot("CharacterHeadSlot", stub.SLOT.HEAD, itemsFrame.EquipmentSlots)
    makeSlot("CharacterLegsSlot", stub.SLOT.LEGS, itemsFrame.EquipmentSlots)
    makeSlot("CharacterFeetSlot", stub.SLOT.FEET, itemsFrame.EquipmentSlots)
    makeSlot("CharacterFinger0Slot", stub.SLOT.FINGER0, itemsFrame.EquipmentSlots)
    makeSlot("CharacterFinger1Slot", stub.SLOT.FINGER1, itemsFrame.EquipmentSlots)
    makeSlot("CharacterMainHandSlot", stub.SLOT.MAINHAND, itemsFrame.WeaponSlots)

    -- The ammo slot sits outside both lists and has no arrow.
    local ammo = makeFrame("CharacterAmmoSlot", itemsFrame)
    ammo.id = env.INVSLOT_AMMO
    ammo.scripts.OnEnter = env.PaperDollItemSlotButton_OnEnter
    ammo.scripts.OnLeave = env.PaperDollItemSlotButton_OnLeave
    env.CharacterAmmoSlot = ammo

    return env
end

return stub
