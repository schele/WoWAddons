local addonName, ns = ...

-- Tweaks to Blizzard's own UI rather than to the bar. They live here, apart
-- from the bar's own code, because they share nothing with it but the settings
-- panel they appear on.

ns.AddDefaults({
    ui = {
        hideEndCaps = true,
        showStatusText = true,
        statusTextSize = 14,
        showSellPrice = true,
    },
})

--------------------------------------------------------------------------------
-- Action bar end caps
--------------------------------------------------------------------------------

-- The gryphons flanking the action bar. Blizzard has moved these between
-- globals and nested fields across versions, so look for all the shapes rather
-- than assume one and silently do nothing.
local END_CAP_PATHS = {
    -- What the 1.60 client actually reports, per /fstack.
    { "MainActionBar", "EndCaps" },
    { "MainActionBar", "EndCaps", "LeftEndCap" },
    { "MainActionBar", "EndCaps", "RightEndCap" },
    -- Older layouts, kept so this keeps working on other clients.
    { "MainMenuBarLeftEndCap" },
    { "MainMenuBarRightEndCap" },
    { "MainMenuBarArtFrame", "LeftEndCap" },
    { "MainMenuBarArtFrame", "RightEndCap" },
    { "MainMenuBar", "EndCaps", "LeftEndCap" },
    { "MainMenuBar", "EndCaps", "RightEndCap" },
}

local hookedCaps = {}

local function endCaps()
    local found = {}

    for _, path in ipairs(END_CAP_PATHS) do
        local frame = _G[path[1]]
        for index = 2, #path do
            frame = type(frame) == "table" and frame[path[index]] or nil
        end

        if type(frame) == "table" and frame.Hide and frame.Show then
            table.insert(found, frame)
        end
    end

    return found
end

--- Show or hide the end caps, reversibly.
-- Hidden with a Show hook rather than by reparenting, so Blizzard putting them
-- back does not undo the setting and turning it off really gives them back.
local function applyEndCaps()
    local hide = ns.db.ui.hideEndCaps

    for _, frame in ipairs(endCaps()) do
        if not hookedCaps[frame] then
            hookedCaps[frame] = true
            hooksecurefunc(frame, "Show", function(self)
                if ns.db and ns.db.ui.hideEndCaps then
                    self:Hide()
                end
            end)
        end

        if hide then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

ns.ApplyEndCaps = applyEndCaps

ns.RegisterSetting({
    store = "ui",
    key = "hideEndCaps",
    type = "checkbox",
    section = "extras",
    name = "Hide the action bar end caps",
    tooltip = "The two gryphons either side of the main action bar.",
    onChange = applyEndCaps,
})

--------------------------------------------------------------------------------
-- Health and mana numbers
--------------------------------------------------------------------------------

-- The client's own font, remembered the first time we change it so turning the
-- setting off really gives it back rather than guessing at a default.
local originalFont

--- Restyle the font object that every unit frame's health and mana text
-- inherits from. One change covers the player, target and party frames, and it
-- survives Blizzard rearranging any of them.
local function applyStatusTextFont()
    local fontObject = TextStatusBarText
    if not fontObject or not fontObject.SetFont or not fontObject.GetFont then
        return
    end

    if not originalFont then
        local file, size, flags = fontObject:GetFont()
        originalFont = { file = file, size = size, flags = flags or "" }
    end

    if ns.db.ui.showStatusText then
        -- Outlined, because the numbers sit on top of a bright health bar.
        fontObject:SetFont(originalFont.file, ns.db.ui.statusTextSize, "OUTLINE")
    else
        fontObject:SetFont(originalFont.file, originalFont.size, originalFont.flags)
    end
end

--- Turn on the client's own status text rather than drawing our own.
-- It is the supported mechanism, it covers every unit frame at once, and it
-- survives Blizzard rearranging the player frame.
local function applyStatusText()
    if not SetCVar then
        return
    end

    if ns.db.ui.showStatusText then
        SetCVar("statusText", "1")
        SetCVar("statusTextDisplay", "NUMERIC")
    else
        SetCVar("statusText", "0")
    end

    applyStatusTextFont()
end

ns.ApplyStatusText = applyStatusText

ns.RegisterSetting({
    store = "ui",
    key = "showStatusText",
    type = "checkbox",
    section = "extras",
    name = "Show health and mana numbers",
    tooltip = "Turns on the game's own status text on the unit frames.",
    onChange = applyStatusText,
})

ns.RegisterSetting({
    store = "ui",
    key = "statusTextSize",
    type = "slider",
    section = "extras",
    name = "Health and mana number size",
    min = 10,
    max = 24,
    onChange = applyStatusTextFont,
})

--------------------------------------------------------------------------------
-- Sell prices on quest rewards
--------------------------------------------------------------------------------

--- Add the vendor price to an item tooltip that left it out.
-- The client shows it on items you carry but not on quest rewards, which is
-- exactly where it matters when picking one to sell. A tooltip that already
-- carries a price is left alone, so it never shows twice.
local function addSellPrice(tooltip, data)
    if not (ns.db and ns.db.ui.showSellPrice) then
        return
    end
    if type(tooltip) ~= "table" or not tooltip.GetItem or not SetTooltipMoney then
        return
    end
    if (tooltip.shownMoneyFrames or 0) > 0 then
        return
    end

    -- The 1.60 client only has the C_Item version; older ones only the global.
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo then
        return
    end

    -- TooltipDataProcessor hands over the item's id; the older script path
    -- has to ask the tooltip for its link.
    local item = type(data) == "table" and data.id or nil
    if not item then
        local _, link = tooltip:GetItem()
        item = link
    end
    if not item then
        return
    end

    -- Nil until the client has the item cached; the tooltip refreshes once it
    -- arrives, and this runs again then.
    local sellPrice = select(11, getItemInfo(item))
    if not sellPrice or sellPrice <= 0 then
        return
    end

    SetTooltipMoney(tooltip, sellPrice, nil, (SELL_PRICE or "Sell Price") .. ":")
    if tooltip:IsShown() then
        -- Resize around the new line.
        tooltip:Show()
    end
end

ns.AddSellPrice = addSellPrice

-- Newer clients route every tooltip through TooltipDataProcessor and may never
-- fire OnTooltipSetItem; older ones only have the script.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addSellPrice)
else
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            tooltip:HookScript("OnTooltipSetItem", addSellPrice)
        end
    end
end

ns.RegisterSetting({
    store = "ui",
    key = "showSellPrice",
    type = "checkbox",
    section = "extras",
    name = "Show sell prices on quest rewards",
    tooltip = "Adds the vendor price to item tooltips that leave it out, such as quest rewards.",
})

--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Only touch either one if it has been turned on, so a default install
    -- leaves the player's own choices exactly as they were.
    if ns.db.ui.hideEndCaps then
        applyEndCaps()
    end

    if ns.db.ui.showStatusText then
        applyStatusText()
    end
end)
