local addonName, ns = ...

-- The Auctions tab's total: the gold of every sold auction on its way to the
-- mailbox, added up. The game shows each sale's Incoming Amount on its own
-- row; this line, in the strip under the list between your gold and Cancel
-- Auction, says what they come to. Its tooltip says when the last one
-- arrives and what the auctions still listed are worth.
--
-- Only WoW Forever's auction house (the current game's window) lists sold
-- auctions; elsewhere nothing is added.

local Incoming = {}
ns.Incoming = Incoming

-- Enum.AuctionStatus.Sold, for a client without the enum.
local SOLD = 1
-- Right of your gold, clear of its border.
local GAP = 12
local HEIGHT = 20
local WIDTH = 360
local NORMAL = { 1, 0.82, 0 }
local GREY = { 0.5, 0.5, 0.5 }
local WHITE = "|cffffffff"

local function amountOf(auction)
    local amount = auction.buyoutAmount or auction.bidAmount
    return type(amount) == "number" and amount or 0
end

--- Your auctions, added up: the sold ones { count, copper, arrives }, where
-- arrives is the seconds until the last reaches the mailbox, and the ones
-- still listed { count, copper } at their buyout.
function Incoming.Sum()
    local sold = { count = 0, copper = 0, arrives = 0 }
    local listed = { count = 0, copper = 0 }
    local api = C_AuctionHouse
    if not (api and api.GetNumOwnedAuctions and api.GetOwnedAuctionInfo) then
        return sold, listed
    end
    local soldStatus = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or SOLD
    for index = 1, api.GetNumOwnedAuctions() or 0 do
        local auction = api.GetOwnedAuctionInfo(index)
        if type(auction) == "table" then
            if auction.status == soldStatus then
                sold.count = sold.count + 1
                sold.copper = sold.copper + amountOf(auction)
                local left = auction.timeLeftSeconds
                if type(left) == "number" and left > sold.arrives then
                    sold.arrives = left
                end
            else
                listed.count = listed.count + 1
                listed.copper = listed.copper + amountOf(auction)
            end
        end
    end
    return sold, listed
end

local function plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

--- "about 33 min", or "within a minute".
local function inMinutes(seconds)
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 1 then
        return "within a minute"
    end
    return "in about " .. minutes .. " min"
end

local function showTooltip(line)
    if not GameTooltip then
        return
    end
    local sold, listed = Incoming.Sum()
    GameTooltip:SetOwner(line, "ANCHOR_TOP")
    GameTooltip:SetText("Incoming gold")
    if sold.count > 0 then
        GameTooltip:AddLine("The Incoming Amount of your " .. plural(sold.count, "sold auction")
            .. ", added up, on its way to your mailbox.", 1, 1, 1, true)
        if sold.arrives > 0 then
            GameTooltip:AddLine("The last arrives " .. inMinutes(sold.arrives) .. ".", 1, 1, 1, true)
        end
    else
        GameTooltip:AddLine("None of your auctions has sold.", 1, 1, 1, true)
    end
    if listed.count > 0 then
        GameTooltip:AddLine("Still listed: " .. plural(listed.count, "auction") .. ", worth "
            .. ns.Money(listed.copper) .. " at their buyout.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

--- Add the line up again, or hide it while the Bids sub-tab shows.
function Incoming.Refresh()
    local line = Incoming.line
    if not line then
        return
    end
    local auctions = line:GetParent()
    local bids = auctions and auctions.IsDisplayingBids and auctions:IsDisplayingBids()
    line:SetShown(not bids)
    if bids then
        return
    end

    local sold = Incoming.Sum()
    local text = line.text
    if sold.count == 0 then
        text:SetText("Incoming: none")
        text:SetTextColor(GREY[1], GREY[2], GREY[3])
    else
        text:SetText(string.format("Incoming: %s%s|r from %d sold",
            WHITE, ns.Money(sold.copper), sold.count))
        text:SetTextColor(NORMAL[1], NORMAL[2], NORMAL[3])
    end
    -- Only the words take the mouse.
    if text.GetStringWidth then
        line:SetWidth(math.max(1, text:GetStringWidth()))
    end
end

local function build()
    local frame = AuctionHouseFrame
    local auctions = frame and frame.AuctionsFrame
    local api = C_AuctionHouse
    if Incoming.line or not (auctions and api and api.GetOwnedAuctionInfo) then
        return
    end

    local line = CreateFrame("Frame", nil, auctions)
    line:SetSize(WIDTH, HEIGHT)
    if frame.MoneyFrameBorder then
        line:SetPoint("LEFT", frame.MoneyFrameBorder, "RIGHT", GAP, 0)
    else
        line:SetPoint("TOPLEFT", auctions, "BOTTOMLEFT", 170, 0)
    end
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line.text:SetPoint("LEFT")
    line.text:SetJustifyH("LEFT")
    line:EnableMouse(true)
    line:SetScript("OnEnter", showTooltip)
    line:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    line:RegisterEvent("OWNED_AUCTIONS_UPDATED")
    line:SetScript("OnEvent", Incoming.Refresh)
    Incoming.line = line

    auctions:HookScript("OnShow", Incoming.Refresh)
    if auctions.SetTab then
        hooksecurefunc(auctions, "SetTab", Incoming.Refresh)
    end
    Incoming.Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_AuctionHouseUI" then
        build()
    end
end)

-- After a /reload at the auctioneer, the auction house UI is back before
-- this file runs, so its load event has come and gone.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    build()
end
