local addonName, ns = ...

local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
local COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"

local function coinIcon(path, size)
    return string.format("|T%s:%d:%d:2:0|t", path, size, size)
end

--- Build the money string with the in-game coin icons.
-- Deliberately different from GetCoinTextureString, which hides denominations
-- that are zero: all three are always shown, so the block reads the same way
-- whatever you are carrying. Amounts are not padded, so the block does change
-- width as silver and copper cross ten; the bar re-flows to suit.
local function formatMoney(copper, iconSize)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    iconSize = math.max(1, math.floor(tonumber(iconSize) or 12))

    local goldAmount = math.floor(copper / 10000)
    local silverAmount = math.floor((copper % 10000) / 100)
    local copperAmount = copper % 100

    local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(goldAmount) or tostring(goldAmount)

    return string.format(
        "%s%s %d%s %d%s",
        goldText,
        coinIcon(GOLD_ICON, iconSize),
        silverAmount,
        coinIcon(SILVER_ICON, iconSize),
        copperAmount,
        coinIcon(COPPER_ICON, iconSize)
    )
end

ns.FormatMoney = formatMoney

local GAIN_COLOR = "|cff40ff40"
local LOSS_COLOR = "|cffff4040"
local FLAT_COLOR = "|cffffffff"

--- Build the "money made this session" string: the change since login. No
-- sign characters; the colour alone carries the direction — green digits for
-- a gain, red for a loss, white for a flat session. Pure, so it is unit
-- tested directly.
local function formatSessionMoney(delta, iconSize)
    delta = math.floor(tonumber(delta) or 0)
    local amount = formatMoney(math.abs(delta), iconSize)

    local color = FLAT_COLOR
    if delta > 0 then
        color = GAIN_COLOR
    elseif delta < 0 then
        color = LOSS_COLOR
    end
    return "Session: " .. color .. amount .. "|r"
end

ns.FormatSessionMoney = formatSessionMoney

ns.AddDefaults({
    money = {
        -- Copper at the start of the session; false until one has begun.
        -- Saved so a /reload carries the session on; a real login starts over.
        sessionStart = false,
    },
})

-- The bar's event plumbing drops event arguments, and this is the one place
-- they matter: PLAYER_ENTERING_WORLD says whether the world appeared through
-- a real login (new session) or a /reload or zoning (same session carries on).
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, _, isInitialLogin)
    if not ns.db then
        return
    end

    if isInitialLogin then
        ns.db.money.sessionStart = GetMoney()
        local module = ns.Bar:GetModule("money")
        if module then
            module:Refresh()
        end
    end
end)

ns.Bar:RegisterModule({
    name = "money",
    side = "LEFT",
    order = 10,
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
    end,

    OnUpdate = function(module)
        local money = GetMoney()
        local config = ns.db.money

        -- No session on record yet (first run ever, or the addon arrived
        -- mid-session through a /reload): the purse as it stands starts one.
        if config.sessionStart == false then
            config.sessionStart = money
        end

        local _, fontSize = module.text:GetFont()
        if module.showSession then
            module.text:SetText(formatSessionMoney(money - config.sessionStart, fontSize))
        else
            module.text:SetText(formatMoney(money, fontSize))
        end
        module:SetWidth(module.text:GetStringWidth())
    end,

    -- Click to flip between what you are carrying and what this session has
    -- made; not saved, so a fresh login always starts on the purse.
    OnClick = function(module, button)
        if button == "LeftButton" then
            module.showSession = not module.showSession
            module:Refresh()
        end
    end,
})
