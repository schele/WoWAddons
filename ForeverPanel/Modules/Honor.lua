local addonName, ns = ...

-- Honor points: WoW Forever's spendable PvP currency, the one its PvP vendors
-- take. Rank points, which set your PvP rank, are another thing (a renown
-- track, the character window's PvP tab) and not shown here.
--
-- Forever's own interface code never names its honor currency, so which id
-- the game uses is not confirmed. The block tries the two honor ids the game
-- defines, then looks for a currency called Honor in the currency tab, and
-- /fp honor says which one it found.

--- The amount after the currency's own icon. Pure, so it is unit tested
-- directly.
local function formatHonor(amount, icon, iconSize)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    iconSize = math.max(1, math.floor(tonumber(iconSize) or 12))

    local count = BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or tostring(amount)
    return string.format("|T%s:%d:%d:0:0|t %s", tostring(icon), iconSize, iconSize, count)
end

ns.FormatHonor = formatHonor

-- Remembered once found by name, so collapsing its header in the currency
-- tab, which hides its row from the list, does not lose it.
local foundID

local function discovered(id)
    local info = id and C_CurrencyInfo.GetCurrencyInfo(id)
    if info and info.discovered then
        return info
    end
end

local function knownIDs()
    local consts = Constants and Constants.CurrencyConsts or {}
    return {
        foundID,
        consts.CLASSIC_HONOR_CURRENCY_ID or 1901,
        consts.HONOR_CURRENCY_ID or 1792,
    }
end

local function isHonorName(name)
    return name ~= nil and (name == HONOR or name == HONOR_POINTS)
end

--- The character's honor currency (the game's CurrencyInfo, with its
-- currencyID), or nil when it has none: never earned any, or a client
-- without it. The game answers for any real currency id, so one the character
-- has never had is passed over rather than read as 0.
local function honorInfo()
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then
        return nil
    end

    -- Walked with an index, since foundID may be nil and leave a hole.
    local ids = knownIDs()
    for index = 1, 3 do
        local info = discovered(ids[index])
        if info then
            info.currencyID = info.currencyID or ids[index]
            return info
        end
    end

    local size = C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0
    for index = 1, size do
        local row = C_CurrencyInfo.GetCurrencyListInfo(index)
        if row and not row.isHeader and isHonorName(row.name) and row.currencyID then
            local info = discovered(row.currencyID)
            if info then
                foundID = row.currencyID
                info.currencyID = info.currencyID or foundID
                return info
            end
        end
    end
end

ns.HonorInfo = honorInfo

ns.Bar:RegisterModule({
    name = "honor",
    side = "LEFT",
    order = 40,
    events = { "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD" },

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
    end,

    OnUpdate = function(module)
        local info = honorInfo()
        if not info then
            module:SetShown(false)
            return
        end

        local _, fontSize = module.text:GetFont()
        module.text:SetText(formatHonor(info.quantity, info.iconFileID, fontSize))
        module:SetWidth(module.text:GetStringWidth())
        module:SetShown(true)
    end,

    -- The currency tab, where honor sits with the character's other currencies.
    OnClick = function(_, button)
        if button == "LeftButton" and ToggleCharacter then
            ToggleCharacter("TokenFrame")
        end
    end,

    -- The game's own tooltip for the currency: what it is and the most you
    -- can hold.
    OnEnter = function(module)
        local info = honorInfo()
        if not info or not GameTooltip.SetCurrencyByID then
            return
        end

        GameTooltip:SetOwner(module.frame, "ANCHOR_BOTTOM")
        GameTooltip:SetCurrencyByID(info.currencyID)
        GameTooltip:Show()
    end,

    OnLeave = function()
        GameTooltip:Hide()
    end,
})

ns.RegisterCommand("honor", "Say how much honor you have, and which currency the bar reads it from", function()
    local info = honorInfo()
    if not info then
        ns.Print("No honor on this character yet.")
        return
    end

    local amount = BreakUpLargeNumbers and BreakUpLargeNumbers(info.quantity) or tostring(info.quantity)
    local cap = ""
    if (info.maxQuantity or 0) > 0 then
        cap = " of " .. (BreakUpLargeNumbers and BreakUpLargeNumbers(info.maxQuantity) or tostring(info.maxQuantity))
    end

    ns.Print(string.format("%s: %s%s (currency %d).", info.name or "Honor", amount, cap, info.currencyID))
end)
