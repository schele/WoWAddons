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
    CHEST = 5,
    LEGS = 7,
    FEET = 8,
    HANDS = 10,
    FINGER0 = 11,
    FINGER1 = 12,
    MAINHAND = 16,
    OFFHAND = 17,
    RANGED = 18,
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
            points = {},
        }

        -- What a settings page does to its widgets, recorded for the tests.
        function frame:SetPoint(...) table.insert(self.points, { ... }) end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetWidth(width) self.width = width end
        function frame:SetJustifyH(value) self.justifyH = value end
        function frame:SetText(text) self.text = text end
        function frame:GetText() return self.text end
        function frame:SetTexture(texture) self.texture = texture end
        function frame:GetTexture() return self.texture end
        function frame:CreateFontString() return makeFrame(nil, self) end
        function frame:CreateTexture() return makeFrame(nil, self) end

        -- A secure button may not be shown, hidden or changed in a fight.
        local function lockedDown(self, what)
            if self.protected and env.__inCombat then
                error(what .. ": action blocked in combat", 3)
            end
        end

        function frame:Show()
            lockedDown(self, "Show")
            if not self.shown then
                self.shown = true
                self:Fire("OnShow")
            end
        end

        function frame:Hide()
            lockedDown(self, "Hide")
            if self.shown then
                self.shown = false
                self:Fire("OnHide")
            end
        end

        function frame:SetShown(shown)
            if shown then self:Show() else self:Hide() end
        end

        function frame:SetAllPoints(target) self.allPoints = target end
        function frame:SetFrameLevel(level) self.frameLevel = level end
        function frame:GetFrameLevel() return self.frameLevel or 1 end
        function frame:RegisterForClicks(...) self.clicks = { ... } end
        function frame:SetHighlightTexture(texture, blend) self.highlight = { texture, blend } end

        function frame:SetAttribute(key, value)
            lockedDown(self, "SetAttribute")
            self.attributes = self.attributes or {}
            self.attributes[key] = value
        end
        function frame:GetAttribute(key) return self.attributes and self.attributes[key] end

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

    env.CreateFrame = function(kind, name, parent, template)
        if template == "SecureActionButtonTemplate" and env.__inCombat then
            error("CreateFrame: secure button in combat", 2)
        end
        local frame = makeFrame(name, parent)
        frame.template = template
        frame.protected = template == "SecureActionButtonTemplate"
        if name then env[name] = frame end
        -- An edit box tells its OnTextChanged about every change, typed or set.
        if kind == "EditBox" then
            function frame:SetText(text)
                self.text = text
                self:Fire("OnTextChanged", false)
            end
            function frame:Type(text)
                self.text = text
                self:Fire("OnTextChanged", true)
            end
            function frame:ClearFocus() end
            function frame:SetAutoFocus(auto) self.autoFocus = auto end
            if template == "SearchBoxTemplate" then
                frame.Instructions = makeFrame(nil, frame)
            end
        end
        -- The game's dropdown, as Blizzard_Menu's guide describes it (copied
        -- from BankBags' stub): a function fills the menu with radios, and
        -- the button reads the one selected, or the default text when none
        -- is. `radios` is the menu as last made, each { text, isSelected,
        -- setSelected, data }.
        if template == "WowStyle1DropdownTemplate" then
            frame.radios = {}
            function frame:SetDefaultText(text) self.defaultText = text end
            function frame:SetupMenu(generator)
                self.menuGenerator = generator
                if self:IsShown() then self:GenerateMenu() end
            end
            local function readSelection(self)
                local selected = {}
                for _, radio in ipairs(self.radios) do
                    if radio.isSelected(radio.data) then table.insert(selected, radio.text) end
                end
                self.selectionText = #selected > 0 and table.concat(selected, ", ") or self.defaultText
            end
            function frame:GenerateMenu()
                if not self.menuGenerator then return end
                local radios, root = {}, {}
                function root:CreateRadio(text, isSelected, setSelected, data)
                    table.insert(radios, { text = text, isSelected = isSelected, setSelected = setSelected, data = data })
                end
                self.menuGenerator(self, root)
                self.radios = radios
                readSelection(self)
            end
            -- A player choosing an entry: the client sets it, then reads the
            -- selection again from the menu it has.
            function frame:Pick(index)
                local radio = self.radios[index]
                radio.setSelected(radio.data)
                readSelection(self)
            end
        end
        return frame
    end

    env.UIParent = makeFrame("UIParent")

    -- The game's options window, and the addon's own .toc.
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return { name = name, frame = frame }
        end,
        RegisterAddOnCategory = function(category) env.__settingsCategory = category end,
    }
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

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

    -- The stance bar: ten buttons, as Blizzard_ActionBar's StanceBar makes
    -- them, shown or not by how many forms there are.
    local stanceBar = makeFrame("StanceBar")
    stanceBar.actionButtons = {}
    for index = 1, 10 do
        local button = makeFrame(nil, stanceBar)
        button.id = index
        button.frameLevel = 5
        stanceBar.actionButtons[index] = button
    end
    env.StanceBar = stanceBar

    -- The tooltip, recording what it was asked to show.
    local tooltip = makeFrame("GameTooltip")
    tooltip.shown = false
    function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor; self.shown = true end
    function tooltip:SetShapeshift(index) self.shapeshift = index end
    env.GameTooltip = tooltip

    -- Edit Mode and Quick Keybind mode, closed.
    env.EditModeManagerFrame = makeFrame("EditModeManagerFrame")
    env.EditModeManagerFrame.shown = false
    env.QuickKeybindFrame = makeFrame("QuickKeybindFrame")
    env.QuickKeybindFrame.shown = false

    -- The equipment set icon window (GearManagerPopupFrame, from
    -- Camelot/PaperDollFrame.lua on IconSelectorPopupFrameTemplate), cut down
    -- to its icon list: the game's list by index, the icon grid (a
    -- SelectorMixin), and the "selected icon" button whose texture the Okay
    -- button saves.
    local popup = makeFrame("GearManagerPopupFrame")
    popup.shown = false
    popup.baseIcons = { "INV_MISC_QUESTIONMARK", 136000, 136001, 132115, 132276, 135000 }
    -- Its OnHide releases the icon list (self.iconDataProvider = nil), so
    -- these raise while it is closed, as they do in the game.
    local function provider(self)
        if self.released then error("attempt to index field 'iconDataProvider' (a nil value)", 3) end
    end
    popup.scripts.OnHide = function(self) self.released = true end
    function popup:GetNumIcons() provider(self) return #self.baseIcons end
    function popup:GetIconByIndex(index) provider(self) return self.baseIcons[index] end
    function popup:GetIndexOfIcon(icon)
        provider(self)
        for index, each in ipairs(self.baseIcons) do
            if each == icon then return index end
        end
        return nil
    end
    popup.BorderBox = makeFrame(nil, popup)
    popup.BorderBox.IconTypeDropdown = makeFrame(nil, popup.BorderBox)
    popup.BorderBox.SelectedIconArea = makeFrame(nil, popup.BorderBox)
    local selectedButton = makeFrame(nil, popup.BorderBox.SelectedIconArea)
    function selectedButton:SetIconTexture(icon) self.icon = icon end
    function selectedButton:GetIconTexture() return self.icon end
    popup.BorderBox.SelectedIconArea.SelectedIconButton = selectedButton

    local selector = makeFrame(nil, popup)
    function selector:SetSelectionsDataProvider(get, count) self.getSelection, self.countSelections = get, count end
    function selector:SetSelectionsArray(array)
        self:SetSelectionsDataProvider(function(index) return array[index] end, function() return #array end)
    end
    function selector:GetNumSelections() return self.countSelections and self.countSelections() or 0 end
    function selector:GetSelection(index) return self.getSelection(index) end
    function selector:SetSelectedIndex(index) self.selectedIndex = index end
    function selector:GetSelectedIndex() return self.selectedIndex end
    function selector:SetSelectedCallback(callback) self.selectedCallback = callback end
    -- A click on an icon in the grid.
    function selector:OnSelection(index)
        if self.selectedCallback then self.selectedCallback(index, self:GetSelection(index)) end
        self:SetSelectedIndex(index)
    end
    popup.IconSelector = selector

    -- GearManagerPopupFrameMixin:OnShow and :Update: the game's list, the
    -- set's icon marked, and a click putting its icon on the selected button.
    popup.scripts.OnShow = function(self)
        self.released = false
        selector:SetSelectionsDataProvider(
            function(index) return self:GetIconByIndex(index) end,
            function() return self:GetNumIcons() end)
        selector:SetSelectedIndex(self:GetIndexOfIcon(selectedButton:GetIconTexture()))
        selector:SetSelectedCallback(function(_, icon) selectedButton:SetIconTexture(icon) end)
    end
    env.GearManagerPopupFrame = popup

    -- The spellbook: { name, iconID } per entry.
    env.__spellbook = {}
    env.Enum = { SpellBookSpellBank = { Player = 0 } }
    env.C_SpellBook = {
        GetSpellBookItemInfo = function(index)
            local spell = env.__spellbook[index]
            return spell and { name = spell.name, iconID = spell.iconID } or nil
        end,
    }

    stub.addGear(env)
    return env
end

-- Gear, forms, combat and equipment sets ---------------------------------
--
-- What the form sets touch. Items are known by GUID, as the client knows
-- them (C_Item.GetItemGUID). The cursor rules are the game's: picking an
-- item up and dropping it on a slot swaps the two, the old one going where
-- the new one came from.
function stub.addGear(env)
    env.__worn = {}                                      -- [slot] = guid
    env.__bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
    env.__bagSize = { [0] = 16, [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    env.__itemInfo = {}                                  -- [guid] = { slots = {[slot]=true}, twoHand }
    env.__locked = {}                                    -- [guid] = true
    env.__cursor = nil                                   -- the location picked up from
    env.__pickups = 0                                    -- PickupInventoryItem + PickupContainerItem calls
    env.__refused = 0                                    -- drops the game turned down in combat (a red error)
    env.__inCombat = false
    env.__forms = {}                                     -- { { spellID, name } }, the stance bar
    env.__form = 0                                       -- the stance bar index worn, 0 for none
    env.__sets = {}                                      -- [setID] = { name, slots = { [slot] = guid | "empty" } }

    env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
    env.INVSLOT_MAINHAND = 16
    env.INVSLOT_OFFHAND = 17
    env.INVSLOTS_EQUIPABLE_IN_COMBAT = { [16] = true, [17] = true, [18] = true }
    env.EQUIPMENT_SET_EMPTY_SLOT = 0
    env.EQUIPMENT_SET_IGNORED_SLOT = 1
    env.EQUIPMENT_SET_ITEM_MISSING = -1

    local function newLocation(fields)
        function fields:IsEquipmentSlot() return self.equipmentSlot ~= nil end
        function fields:GetEquipmentSlot() return self.equipmentSlot end
        function fields:IsBagAndSlot() return self.bag ~= nil end
        function fields:GetBagAndSlot() return self.bag, self.slot end
        return fields
    end

    env.ItemLocation = {
        CreateFromEquipmentSlot = function(_, slot) return newLocation({ equipmentSlot = slot }) end,
        CreateFromBagAndSlot = function(_, bag, slot) return newLocation({ bag = bag, slot = slot }) end,
    }

    local function itemAt(location)
        if location.equipmentSlot then
            return env.__worn[location.equipmentSlot]
        end
        return env.__bags[location.bag] and env.__bags[location.bag][location.slot]
    end

    local function put(location, guid)
        if location.equipmentSlot then
            env.__worn[location.equipmentSlot] = guid
        else
            env.__bags[location.bag][location.slot] = guid
        end
    end

    local function find(guid)
        for slot, worn in pairs(env.__worn) do
            if worn == guid then return newLocation({ equipmentSlot = slot }) end
        end
        for bag, contents in pairs(env.__bags) do
            for slot, held in pairs(contents) do
                if held == guid then return newLocation({ bag = bag, slot = slot }) end
            end
        end
        return nil
    end

    local function freeSlots(bag)
        local free = {}
        for slot = 1, env.__bagSize[bag] or 0 do
            if not env.__bags[bag][slot] then free[#free + 1] = slot end
        end
        return free
    end

    local function fits(guid, slot)
        local info = guid and env.__itemInfo[guid]
        return info ~= nil and info.slots[slot] == true
    end

    env.C_Item = {
        DoesItemExist = function(location) return itemAt(location) ~= nil end,
        -- The client raises for a location with nothing in it.
        GetItemGUID = function(location)
            local guid = itemAt(location)
            if not guid then error("GetItemGUID: invalid item location", 2) end
            return guid
        end,
        GetItemLocation = function(guid) return find(guid) end,
        -- An item's name is its GUID here, which keeps macro text readable.
        GetItemName = function(location) return itemAt(location) end,
        IsLocked = function(location)
            local guid = itemAt(location)
            return guid ~= nil and env.__locked[guid] == true
        end,
    }

    env.IsInventoryItemLocked = function(slot)
        local guid = env.__worn[slot]
        return guid ~= nil and env.__locked[guid] == true
    end

    env.ClearCursor = function() env.__cursor = nil end
    env.CursorHasItem = function() return env.__cursor ~= nil end

    -- The item on the cursor lands on `target`.
    local function drop(target)
        local source = env.__cursor
        env.__cursor = nil
        local moving, old = itemAt(source), itemAt(target)
        if target.equipmentSlot and not fits(moving, target.equipmentSlot) then return end
        if target.equipmentSlot == 17 and env.__worn[16] and env.__itemInfo[env.__worn[16]].twoHand then
            env.__refused = env.__refused + 1 -- "Cannot equip that with a two-handed weapon"
            return
        end
        if source.equipmentSlot and old and not fits(old, source.equipmentSlot) then return end

        -- A two-hander takes the off hand's item off, into the bags.
        local pushed
        if target.equipmentSlot == 16 and env.__itemInfo[moving].twoHand and env.__worn[17] then
            for bag = 0, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS do
                for _, slot in ipairs(freeSlots(bag)) do
                    local spot = newLocation({ bag = bag, slot = slot })
                    if not (source.bag == bag and source.slot == slot) then
                        pushed = pushed or spot
                    end
                end
            end
            if not pushed then return end
        end

        put(target, moving)
        put(source, old)
        if pushed then
            put(pushed, env.__worn[17])
            env.__worn[17] = nil
        end
    end

    local function pickup(location)
        env.__pickups = env.__pickups + 1
        if env.__cursor then
            drop(location)
        elseif itemAt(location) then
            env.__cursor = location
        end
    end

    -- In a fight Forever blocks addons from this, weapons too: "Interface
    -- action failed because of an AddOn", and what was picked up stays on
    -- the cursor (seen 2026-11-26). Only the player's own click works then.
    env.__blocked = 0
    env.PickupInventoryItem = function(slot)
        if env.__inCombat and not env.__player then
            env.__blocked = env.__blocked + 1
            return
        end
        pickup(newLocation({ equipmentSlot = slot }))
    end
    env.InCombatLockdown = function() return env.__inCombat end

    -- An item's link and icon: its name is its GUID; its icon whatever the
    -- test gave __itemInfo[guid].icon.
    local function linkOf(guid)
        return guid and ("|cffffffff|Hitem:1::::::::38:::::|h[" .. guid .. "]|h|r") or nil
    end
    local function iconOf(guid)
        return guid and (env.__itemInfo[guid] and env.__itemInfo[guid].icon or 134400) or nil
    end

    env.C_Container = {
        PickupContainerItem = function(bag, slot) pickup(newLocation({ bag = bag, slot = slot })) end,
        GetContainerFreeSlots = function(bag) return freeSlots(bag) end,
        GetContainerNumFreeSlots = function(bag) return #freeSlots(bag), 0 end,
        GetContainerNumSlots = function(bag) return env.__bagSize[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local guid = env.__bags[bag] and env.__bags[bag][slot]
            if not guid then return nil end
            return { iconFileID = iconOf(guid), hyperlink = linkOf(guid), itemID = 1 }
        end,
    }
    env.GetInventoryItemTexture = function(_, slot) return iconOf(env.__worn[slot]) end
    env.GetInventoryItemLink = function(_, slot) return linkOf(env.__worn[slot]) end

    env.C_PaperDollInfo = {
        -- Nothing goes in the off hand beside a two-hander.
        CursorCanGoInSlot = function(slot)
            if slot == 17 and env.__worn[16] and env.__itemInfo[env.__worn[16]].twoHand then
                return false
            end
            return env.__cursor ~= nil and fits(itemAt(env.__cursor), slot)
        end,
    }

    env.UnitAffectingCombat = function(unit) return unit == "player" and env.__inCombat end
    env.__class = "DRUID"
    env.UnitClass = function() return "Druid", env.__class, 11 end
    env.__casting = false
    env.__dead = false
    env.UnitCastingInfo = function(unit)
        if unit == "player" and env.__casting then return "Healing Touch" end
        return nil
    end
    env.UnitChannelInfo = function() return nil end
    env.UnitIsDeadOrGhost = function(unit) return unit == "player" and env.__dead end

    -- The stance bar.
    env.GetNumShapeshiftForms = function() return #env.__forms end
    env.GetShapeshiftForm = function() return env.__form end
    -- `__formsLoading`: at login the bar can be there before its spells.
    env.GetShapeshiftFormInfo = function(index)
        local form = env.__forms[index]
        if not form then return nil end
        local icon = form.icon or 132000 + index
        -- The form you are in shows the "active" glow (Spell_Nature_WispSplode)
        -- instead of its icon, as on Carl's stance bar.
        if env.__form == index then icon = 136116 end
        if env.__formsLoading then return icon, env.__form == index, true, nil end
        return icon, env.__form == index, true, form.spellID
    end
    local function formOf(spellID)
        for index, form in ipairs(env.__forms) do
            if form.spellID == spellID then return form, index end
        end
        return nil
    end
    env.C_Spell = {
        GetSpellName = function(spellID)
            local form = formOf(spellID)
            return form and form.name or nil
        end,
        GetSpellTexture = function(spellID)
            local form, index = formOf(spellID)
            return form and (form.icon or 132000 + index) or nil
        end,
    }

    -- The equipment manager's sets, packed the way the client packs them.
    env.C_EquipmentSet = {
        GetEquipmentSetIDs = function()
            local ids = {}
            for setID in pairs(env.__sets) do ids[#ids + 1] = setID end
            table.sort(ids)
            return ids
        end,
        GetEquipmentSetInfo = function(setID)
            local set = env.__sets[setID]
            if not set then return nil end
            return set.name, 134000 + setID, setID, false, 0, 0, 0, 0, 0
        end,
        GetItemLocations = function(setID)
            local set = env.__sets[setID]
            if not set then return nil end
            local locations = {}
            for slot = 1, 19 do
                local want = set.slots[slot]
                if want == nil then
                    locations[slot] = env.EQUIPMENT_SET_IGNORED_SLOT
                elseif want == "empty" then
                    locations[slot] = env.EQUIPMENT_SET_EMPTY_SLOT
                else
                    local at = find(want)
                    if not at then
                        locations[slot] = env.EQUIPMENT_SET_ITEM_MISSING
                    elseif at.equipmentSlot then
                        locations[slot] = stub.worn(at.equipmentSlot)
                    else
                        locations[slot] = stub.inBag(at.bag, at.slot)
                    end
                end
            end
            return locations
        end,
    }
end

return stub
