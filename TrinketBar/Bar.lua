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

local function createAnchor()
    anchor = CreateFrame("Frame", "TrinketBarAnchor", UIParent)
    anchor:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    anchor:SetPoint("CENTER", 0, -160)
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

            button.entry = entry
            button:Show()
        else
            -- Cleared, not merely hidden. A hidden button still carrying an
            -- instruction is one keybind away from running it.
            button:SetAttribute("type1", nil)
            button:SetAttribute("macrotext1", nil)
            button:SetAttribute("type2", nil)
            button:SetAttribute("macrotext2", nil)

            button.entry = nil
            button:Hide()
        end
    end

    return true
end

--- Run whatever combat was holding.
local function runPending()
    if buildPending and Bar.Build() then
        pending = true
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

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        runPending()
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
