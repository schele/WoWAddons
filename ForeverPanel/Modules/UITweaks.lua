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
        showQuestXP = true,
        backpackFirst = true,
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

local SELL_PRICE_LABEL = SELL_PRICE or "Sell Price"

--- Whether the client already put its own price on this tooltip.
-- The 1.60 client writes it as a text line with coin icons rather than a money
-- frame, so look for that line as well as for money frames and the data.
local function hasNativeSellPrice(tooltip, data)
    if (tooltip.shownMoneyFrames or 0) > 0 then
        return true
    end

    local sellPriceLine = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
    if sellPriceLine and type(data) == "table" and type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            if line.type == sellPriceLine then
                return true
            end
        end
    end

    local name = tooltip.GetName and tooltip:GetName()
    if name and tooltip.NumLines then
        for index = 1, tooltip:NumLines() do
            local line = _G[name .. "TextLeft" .. index]
            local text = line and line.GetText and line:GetText()
            if type(text) == "string" and text:find(SELL_PRICE_LABEL, 1, true) == 1 then
                return true
            end
        end
    end

    return false
end

--- How many items the tooltip is showing: the stack on the button it is for.
local function stackCount(tooltip)
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    local count = type(owner) == "table" and tonumber(owner.count) or nil
    return count or 1
end

local COIN_ICONS = {
    gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

--- A price as text with coin icons, the way the client writes its own.
-- Text rather than SetTooltipMoney: called from addon code on the 1.60 client,
-- the money frame measures its coins as secret numbers and then errors doing
-- arithmetic on them. A text line has nothing to measure.
local function moneyText(copper)
    if GetMoneyString then
        return GetMoneyString(copper)
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    copper = copper % 100

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. COIN_ICONS.gold
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. COIN_ICONS.silver
    end
    if copper > 0 then
        parts[#parts + 1] = copper .. COIN_ICONS.copper
    end
    return table.concat(parts, " ")
end

--- Add the vendor price to an item tooltip that left it out.
-- The client shows it on items you carry but not on quest rewards, which is
-- exactly where it matters when picking one to sell. A single item the client
-- already priced is left to the client. On a stack, the price of one item is
-- added beside the client's, labelled as such.
local function addSellPrice(tooltip, data)
    if not (ns.db and ns.db.ui.showSellPrice) then
        return
    end
    if type(tooltip) ~= "table" or not tooltip.GetItem or not tooltip.AddLine then
        return
    end

    local count = stackCount(tooltip)
    if count <= 1 and hasNativeSellPrice(tooltip, data) then
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

    local label = count > 1 and (SELL_PRICE_LABEL .. " (each):") or (SELL_PRICE_LABEL .. ":")
    tooltip:AddLine(label .. " " .. moneyText(sellPrice), 1, 1, 1)
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
-- XP on quests
--------------------------------------------------------------------------------

-- The quest window's pages that know what a quest gives: the button taking
-- the quest, and the one across the bar from it. The client has the XP but
-- never shows it, so it goes on the bar between the two, where it does not
-- depend on how the client lays out the rewards above.
local QUEST_PAGES = {
    QUEST_DETAIL = { "QuestFrameAcceptButton", "QuestFrameDeclineButton" },
    QUEST_COMPLETE = { "QuestFrameCompleteQuestButton", "QuestFrameCancelButton" },
}

local questXPLabels = {}
-- The page on screen, so the setting can take effect on it at once.
local openQuestPage

--- What a quest gives, as "+1,234 XP (8.2% of level)", or nil for nothing.
-- The share of a level is left out when there is no level to share.
local function formatQuestXP(xp, xpMax)
    xp = tonumber(xp) or 0
    if xp <= 0 then
        return nil
    end

    local group = BreakUpLargeNumbers or tostring
    local text = "+" .. group(xp) .. " XP"

    xpMax = tonumber(xpMax) or 0
    if xpMax > 0 then
        text = text .. string.format(" (%.1f%% of level)", xp / xpMax * 100)
    end
    return text
end

ns.FormatQuestXP = formatQuestXP

--- The line beside a page's button, made the first time it has something to
-- say. A child of the button, so it hides with the page.
local function questXPLabel(page)
    if questXPLabels[page] then
        return questXPLabels[page]
    end

    local names = QUEST_PAGES[page]
    local button, across = _G[names[1]], _G[names[2]]
    if type(button) ~= "table" or not button.CreateFontString then
        return nil
    end

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", 8, 0)
    if type(across) == "table" then
        label:SetPoint("RIGHT", across, "LEFT", -8, 0)
        label:SetJustifyH("CENTER")
    else
        label:SetJustifyH("LEFT")
    end
    -- Cut short rather than wrapped onto the buttons, on a narrow window.
    label:SetWordWrap(false)

    questXPLabels[page] = label
    return label
end

local function questXPText()
    if not (ns.db and ns.db.ui.showQuestXP and GetRewardXP) then
        return nil
    end
    if IsXPUserDisabled and IsXPUserDisabled() then
        return nil
    end
    return formatQuestXP(GetRewardXP(), UnitXPMax and UnitXPMax("player"))
end

local function showQuestXP(page)
    local text = questXPText()
    local label = text and questXPLabel(page) or questXPLabels[page]
    if not label then
        return
    end

    label:SetText(text or "")
    label:SetShown(text ~= nil)
end

local function applyQuestXP()
    for page, label in pairs(questXPLabels) do
        if page ~= openQuestPage then
            label:Hide()
        end
    end
    if openQuestPage then
        showQuestXP(openQuestPage)
    end
end

local questEvents = CreateFrame("Frame")
questEvents:RegisterEvent("QUEST_DETAIL")
questEvents:RegisterEvent("QUEST_COMPLETE")
questEvents:RegisterEvent("QUEST_FINISHED")
questEvents:SetScript("OnEvent", function(self, event)
    if QUEST_PAGES[event] then
        openQuestPage = event
        showQuestXP(event)
    else
        openQuestPage = nil
    end
end)

ns.RegisterSetting({
    store = "ui",
    key = "showQuestXP",
    type = "checkbox",
    section = "extras",
    name = "Show the XP a quest gives",
    tooltip = "Beside the Accept and Complete Quest buttons, with how much of a level it is.",
    onChange = applyQuestXP,
})

--------------------------------------------------------------------------------
-- The combined bags' order
--------------------------------------------------------------------------------

-- WoW Forever's 1.60.1 (70291) build sorts the Combined Backpack's slots for
-- the gamepad layout, which fills from the top left. With a mouse the frame
-- still fills from the bottom right, by the money, so the backpack came out
-- at the bottom and the last bag on top. This lays the same slots out again
-- on the game's own grid: the backpack's first slot in the top-left corner,
-- every bag in order after it, and any gap at the bottom right.

-- Empty cells, laid out first so they take the bottom right.
local emptyCells = {}

local function emptyCell(bags, index, width, height)
    local cell = emptyCells[index]
    if not cell then
        cell = CreateFrame("Frame", nil, bags)
        cell:Hide()
        emptyCells[index] = cell
    end
    -- The grid sizes every cell by the first frame it is given.
    cell:SetSize(width, height)
    return cell
end

-- Reading order, top left to bottom right: bag by bag, slot by slot, and the
-- slots that wait on a secured account after all the rest.
local function readingOrder(a, b)
    local extendedA = a.IsExtended and a:IsExtended() or false
    local extendedB = b.IsExtended and b:IsExtended() or false
    if extendedA ~= extendedB then
        return extendedB
    end
    local bagA, bagB = a:GetBagID(), b:GetBagID()
    if bagA ~= bagB then
        return bagA < bagB
    end
    return a:GetID() < b:GetID()
end

local function backpackFirst(bags)
    local slots = {}
    for _, slot in bags:EnumerateValidItems() do
        table.insert(slots, slot)
    end
    if #slots == 0 then
        return
    end
    table.sort(slots, readingOrder)

    -- The grid fills from the bottom right, so it gets the reading order
    -- backwards, after the empty cells.
    local columns = bags:GetColumns()
    local empty = (columns - #slots % columns) % columns
    local width, height = slots[1]:GetWidth(), slots[1]:GetHeight()
    local frames = {}
    for index = 1, empty do
        frames[index] = emptyCell(bags, index, width, height)
    end
    for index = #slots, 1, -1 do
        table.insert(frames, slots[index])
    end

    AnchorUtil.GridLayout(frames, bags:GetInitialItemAnchor(), bags:GetAnchorLayout())
    bags:LayoutAddSlots()
end

local function gamepad()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
end

local hookedBags = false

-- After every layout the game does of the Combined Backpack. Guarded: a later
-- build that changes the frame must not break the bags, so on any error the
-- game's own layout stands.
local function hookCombinedBags()
    local bags = ContainerFrameCombinedBags
    if hookedBags or type(bags) ~= "table" or not bags.UpdateItemLayout then
        return
    end
    hookedBags = true
    hooksecurefunc(bags, "UpdateItemLayout", function(self)
        if ns.db and ns.db.ui.backpackFirst and not gamepad() and AnchorUtil then
            pcall(backpackFirst, self)
        end
    end)
end

--- Lay open bags out again, so the setting shows at once either way.
local function applyBagOrder()
    hookCombinedBags()
    local bags = ContainerFrameCombinedBags
    if hookedBags and bags:IsShown() then
        pcall(bags.UpdateItemLayout, bags)
    end
end

ns.RegisterSetting({
    store = "ui",
    key = "backpackFirst",
    type = "checkbox",
    section = "extras",
    name = "Backpack first in the combined bags",
    tooltip = "Its first slot in the top-left corner and each bag after it, as before the 1.60.1 (70291) patch put it at the bottom.",
    onChange = applyBagOrder,
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

    -- The hook sits idle with the setting off, so it can always go on.
    hookCombinedBags()
end)
