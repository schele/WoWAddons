-- WardrobeForever: Blizzard's own equipment pop-out on the character sheet,
-- opened by hovering a slot instead of holding Alt.
--
-- Blizzard already keeps a pop-out open without Alt in one case: when its
-- slot's arrow is "locked" (the arrows beside each slot on the equipment
-- manager tab). Hovering a slot that has something to swap to locks it the
-- same way, so Blizzard opens it, lays out the items, moves the tooltip
-- beside it and closes it when an item is clicked. All WardrobeForever adds
-- is closing it again once the mouse has left both the slot and the list.

local _, ns = ...

-- How long the mouse may be off the slot and the list before it closes.
-- Long enough to cross the arrow-wide gap between them.
ns.CLOSE_DELAY = 0.3

local flyout = EquipmentFlyoutFrame
local items = PaperDollItemsFrame
if not (flyout and items) then
    return
end

--- Whether anything you are not wearing fits this slot. The worn item, and
-- for rings and trinkets the one in the other slot, do not count.
function ns.HasSomethingToSwap(slotID)
    local fitting = {}
    GetInventoryItemsForSlot(slotID, fitting)
    for location in pairs(fitting) do
        local data = EquipmentManager_GetLocationData(location)
        if data.isBags or data.isBank then
            return true
        end
    end
    return false
end

-- The slot whose list was opened by hovering it, while that list is open.
local hovered
local outside = 0
local watcher = CreateFrame("Frame")
watcher:Hide()

local function isHoveredOpen()
    return hovered ~= nil and flyout:IsShown() and flyout.button == hovered
        and hovered.popoutButton.flyoutLocked
end

local function forget()
    hovered = nil
    watcher:Hide()
end

local function close()
    if isHoveredOpen() then
        forget()
        flyout:Hide() -- Blizzard's OnHide lets go of the arrow
    else
        forget()
    end
end

local function mouseIsOnIt()
    local nav = flyout.NavigationFrame
    return hovered:IsMouseOver()
        or hovered.popoutButton:IsMouseOver()
        or flyout.buttonFrame:IsMouseOver()
        or (nav:IsShown() and nav:IsMouseOver())
end

watcher:SetScript("OnUpdate", function(_, elapsed)
    if not isHoveredOpen() then
        -- Closed by Blizzard (an item was clicked, the window shut) or
        -- taken over by a pinned or Alt-opened list.
        forget()
        return
    end
    if mouseIsOnIt() then
        outside = 0
        return
    end
    outside = outside + elapsed
    if outside >= ns.CLOSE_DELAY then
        close()
    end
end)

local function onSlotEnter(button)
    if IsModifiedClick("SHOWITEMFLYOUT") then
        return -- Alt is Blizzard's
    end
    if flyout:IsShown() and flyout.button == button then
        return -- already open for this slot, by hover or pinned
    end

    if not ns.HasSomethingToSwap(button:GetID()) then
        if isHoveredOpen() then
            close()
            -- Blizzard anchored this slot's tooltip beside the list that
            -- just closed; run its hover again to put it back on the slot.
            PaperDollItemSlotButton_OnEnter(button)
        end
        return
    end

    hovered = button
    outside = 0
    button.popoutButton.flyoutLocked = true
    EquipmentFlyoutPopoutButton_RefreshVisualState(button.popoutButton)
    -- Blizzard's hover again, now that the slot is locked: it opens the list
    -- and anchors the tooltip beside it.
    PaperDollItemSlotButton_OnEnter(button)
    watcher:Show()
end

for _, slots in ipairs({ items.EquipmentSlots, items.WeaponSlots }) do
    for _, button in ipairs(slots or {}) do
        if button.popoutButton then
            button:HookScript("OnEnter", onSlotEnter)
        end
    end
end
