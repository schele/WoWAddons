-- A minimal stand-in for the WoW API, enough to load AutoVendor outside the
-- game: frames, timers, bags, items, a merchant, money and the options
-- window. It records what was done so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent, template)
    local widget = {
        kind = kind,
        parent = parent,
        template = template,
        scripts = {},
        registeredEvents = {},
        shown = true,
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end

    -- For the settings page. Showing and hiding fire their scripts, and only
    -- on a real transition, the way the client does.
    function widget:Show()
        if self.shown then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function widget:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function widget:IsShown() return self.shown end
    -- Seen only when it and every frame it sits in are shown: the options
    -- window keeps a closed page shown, inside itself.
    function widget:IsVisible()
        if not self.shown then return false end
        if self.parent and self.parent.IsVisible then return self.parent:IsVisible() end
        return true
    end
    -- Where the mouse is, as a test says.
    function widget:IsMouseOver() return self.mouseOver == true end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:SetDesaturated(value) self.desaturated = value and true or false end
    function widget:SetAlpha(value) self.alpha = value end
    widget.points = {}
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:GetHeight() return self.height or 0 end
    function widget:SetAllPoints(target) self.allPoints = target or true end
    -- A line of text, whatever it says: enough for a page to add up heights.
    function widget:GetStringHeight() return 12 end
    -- A scroll frame: what it scrolls, and nothing to scroll by.
    function widget:SetScrollChild(child) self.scrollChild = child end
    function widget:GetVerticalScrollRange() return 0 end
    function widget:SetVerticalScroll(value) self.verticalScroll = value end
    function widget:SetShown(value) if value then self:Show() else self:Hide() end end
    function widget:SetHighlightTexture(texture, mode) self.highlight = texture end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetText(value) self.text = value end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:GetTextColor()
        if self.textColor then return table.unpack(self.textColor) end
    end
    function widget:GetText() return self.text end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:GetParent() return self.parent end
    -- Sliders. Setting a new value fires OnValueChanged, as the client's
    -- does, with userInput false.
    function widget:SetMinMaxValues(low, high) self.min, self.max = low, high end
    function widget:GetMinMaxValues() return self.min, self.max end
    function widget:SetValueStep(value) self.valueStep = value end
    function widget:SetObeyStepOnDrag(value) self.obeyStep = value end
    function widget:SetValue(value)
        if self.min then value = math.max(self.min, math.min(self.max, value)) end
        if self.value == value then return end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, false) end
    end
    function widget:GetValue() return self.value end
    -- Status bars: the texture and colour they fill with.
    function widget:SetStatusBarTexture(value) self.barTexture = value end
    function widget:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
    -- Atlas art, by name.
    function widget:SetAtlas(atlas) self.atlas = atlas end
    function widget:GetAtlas() return self.atlas end
    function widget:SetBlendMode(mode) self.blendMode = mode end
    --- Test helper: the player dragging a slider to `value`.
    function widget:Drag(value)
        self.value = nil
        if self.min then value = math.max(self.min, math.min(self.max, value)) end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, true) end
    end
    function widget:SetEnabled(value) self.disabled = not value end
    function widget:Enable() self.disabled = false end
    function widget:Disable() self.disabled = true end
    function widget:IsEnabled() return not self.disabled end
    function widget:EnableMouseWheel(value) self.mouseWheel = value end
    function widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:CreateTexture() return makeWidget("Texture", self) end
    -- Remembered on the parent, so a test can find a label by its text.
    function widget:CreateFontString()
        local fontString = makeWidget("FontString", self)
        self.fontStrings = self.fontStrings or {}
        table.insert(self.fontStrings, fontString)
        return fontString
    end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

--- A fresh client. `saved` is AutoVendorDB as the client would load it from
-- SavedVariables, or nil for a first run.
function stub.newEnv(saved)
    local env = setmetatable({}, { __index = _G })

    env._G = env
    env.__frames = {}
    env.__printed = {}
    env.SlashCmdList = {}
    env.AutoVendorDB = saved

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent, template)
        local frame = makeWidget(kind or "Frame", parent, template)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        -- The auction house's tab template: parentArray="Tabs" puts the tab
        -- on its window's list, and a click sets the tab's display mode.
        if template == "AuctionHouseFrameDisplayModeTabTemplate" and parent and parent.Tabs then
            table.insert(parent.Tabs, frame)
            frame:SetScript("OnClick", function(self) parent:SetDisplayMode(self.displayMode) end)
        end
        -- The options slider's own labels: its two ends and its name.
        if template == "OptionsSliderTemplate" then
            frame.Low = frame:CreateFontString()
            frame.High = frame:CreateFontString()
            frame.Text = frame:CreateFontString()
        end
        return frame
    end

    -- PanelTemplates, as far as tabs go: how many, and which is selected.
    function env.PanelTemplates_SetNumTabs(frame, count) frame.numTabs = count end
    function env.PanelTemplates_SetTab(frame, index) frame.selectedTab = index end
    function env.PanelTemplates_GetSelectedTab(frame) return frame.selectedTab end

    -- Art the client has by atlas name, and the border layouts it draws
    -- (NineSliceUtil), recorded on the frame they were laid on.
    env.__atlases = {
        ["auctionhouse-background-index"] = true,
        ["auctionhouse-rowstripe-1"] = true,
        ["auctionhouse-rowstripe-2"] = true,
        ["auctionhouse-ui-row-highlight"] = true,
    }
    env.C_Texture = {
        GetAtlasInfo = function(name)
            if env.__atlases[name] then return { width = 1, height = 1 } end
        end,
    }
    env.NineSliceUtil = {
        ApplyLayoutByName = function(frame, layout) frame.layout = layout end,
    }

    -- The clock, in seconds since 1970, as time() gives it, and date() to
    -- write a time of day.
    env.__clock = 1700000000
    function env.time() return env.__clock end
    env.date = os.date

    function env.UnitName(unit)
        if unit == "player" then return "Skyler" end
    end

    -- The auction house's full scan (C_AuctionHouse.ReplicateItems): every
    -- auction up, as { itemID, count, buyout, bid, owner, saleStatus }. A
    -- scan asked for is answered when a test fires REPLICATE_ITEM_LIST_UPDATE.
    -- The game counts the auctions from 0, so index 0 is the first.
    env.__auctions = {}
    env.__owned = {}
    env.Enum = { AuctionStatus = { Active = 0, Sold = 1 } }
    env.__replicates = 0
    -- How many auctions were read, to tell a slice from the whole list.
    env.__replicateReads = 0
    env.C_AuctionHouse = {
        ReplicateItems = function() env.__replicates = env.__replicates + 1 end,
        GetNumReplicateItems = function() return #env.__auctions end,
        -- An auction's name is its own: with a suffix ("of the Whale") when
        -- it has `fullName`. One the game has not finished describing
        -- (`unnamed`) comes with an empty name and hasAllInfo false, though
        -- its item, and so its sell price, may be known; with `nolink` it
        -- has no link yet either.
        GetReplicateItemInfo = function(index)
            env.__replicateReads = env.__replicateReads + 1
            local auction = env.__auctions[index + 1]
            if not auction then return nil end
            local item = env.__items[auction.itemID] or {}
            local described = not env.__uncached[auction.itemID] and not auction.unnamed
            local name = nil
            if auction.unnamed then
                name = ""
            elseif described then
                name = auction.fullName or item.name
            end
            return name, 1000 + auction.itemID, auction.count or 1,
                item.quality or 1, true, 1, "", auction.bid or 0, 1, auction.buyout or 0, 0, nil, nil,
                auction.owner or "Someone", auction.owner or "Someone", auction.saleStatus or 0,
                auction.itemID, described
        end,
        -- Your own auctions, as the Auctions tab lists them: each an
        -- OwnedAuctionInfo table (status, buyoutAmount, bidAmount,
        -- timeLeftSeconds), from __owned.
        GetNumOwnedAuctions = function() return #env.__owned end,
        GetOwnedAuctionInfo = function(index) return env.__owned[index] end,
        GetReplicateItemLink = function(index)
            local auction = env.__auctions[index + 1]
            if auction and not auction.nolink and env.__items[auction.itemID] and not env.__uncached[auction.itemID] then
                return env.__link(auction.itemID, auction.fullName)
            end
        end,
    }

    env.UIParent = makeWidget("Frame")

    -- The tooltip, hidden to begin with: whose it is and which item it shows.
    env.GameTooltip = makeWidget("GameTooltip", env.UIParent)
    env.GameTooltip.shown = false
    env.GameTooltip.lines = {}
    function env.GameTooltip:SetOwner(owner, anchor)
        self.owner, self.anchor, self.lines = owner, anchor, {}
    end
    function env.GameTooltip:SetText(text) self.lines = { text } end
    function env.GameTooltip:AddLine(text) table.insert(self.lines, text) end
    function env.GameTooltip:SetItemByID(itemID) self.itemID = itemID end

    -- The game's options window and the game menu, both closed to begin with.
    env.SettingsPanel = makeWidget("Frame", env.UIParent)
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame", env.UIParent)
    env.GameMenuFrame.shown = false
    function env.HideUIPanel(frame)
        if frame and frame.Hide then frame:Hide() end
    end
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return { name = name, frame = frame, GetID = function() return "category-id" end }
        end,
        RegisterAddOnCategory = function(category) env.__settingsCategory = category end,
        OpenToCategory = function(id) env.__openedCategory = id end,
    }
    env.__loadedAddons = {}
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
        IsAddOnLoaded = function(name)
            return env.__loadedAddons[name] == true
        end,
    }

    -- The real one is taint-safe; for tests it only has to run the original
    -- and then the hook, and hand back what the original returned.
    function env.hooksecurefunc(target, name, hook)
        if type(target) == "string" then
            target, name, hook = env, target, name
        end
        local original = target[name]
        target[name] = function(...)
            local results = table.pack(original(...))
            hook(...)
            return table.unpack(results, 1, results.n)
        end
    end

    -- The client runs a timer after the current chain of calls, not inside
    -- it: queued here with its delay, and run by __runTimers.
    env.__timers = {}
    env.__timerDelays = {}
    env.C_Timer = {
        After = function(delay, fn)
            table.insert(env.__timerDelays, delay)
            table.insert(env.__timers, fn)
        end,
    }
    --- One round: the timers queued so far, not the ones they queue.
    -- The server's answers to sales made before this round land after its
    -- timers have run, so a step always looks before the answer arrives.
    function env.__runTimers()
        local pending, replies = env.__timers, env.__replies
        env.__timers, env.__replies, env.__timerDelays = {}, {}, {}
        for _, fn in ipairs(pending) do fn() end
        for _, fn in ipairs(replies) do fn() end
    end
    --- Only the timers queued with a delay of `seconds` or less; the rest
    -- stay queued, as the client would still be waiting on them.
    function env.__runTimersUpTo(seconds)
        local pending, delays = env.__timers, env.__timerDelays
        env.__timers, env.__timerDelays = {}, {}
        for index, fn in ipairs(pending) do
            if (delays[index] or 0) <= seconds then
                fn()
            else
                table.insert(env.__timers, fn)
                table.insert(env.__timerDelays, delays[index])
            end
        end
    end
    --- Every round until nothing is queued.
    function env.__runAllTimers()
        for _ = 1, 1000 do
            if #env.__timers == 0 then return end
            env.__runTimers()
        end
        error("timers never stopped queuing")
    end

    -- Items: name, quality (0 grey, 1 white) and sell price in copper.
    env.__items = {
        [3300] = { name = "Rabbit's Foot", quality = 0, price = 15 },
        [7073] = { name = "Broken Fang", quality = 0, price = 6 },
        [1411] = { name = "Withered Staff", quality = 0, price = 12345 },
        [9999] = { name = "Worthless Rock", quality = 0, price = 0 },
        [2589] = { name = "Linen Cloth", quality = 1, price = 13 },
        [6948] = { name = "Hearthstone", quality = 1, price = 0 },
        [117] = { name = "Tough Jerky", quality = 1, price = 1 },
        [6070] = { name = "Wolfskin Bracers", quality = 2, price = 77 },
        [9798] = { name = "Ivycloth Boots of Arcane Protection", quality = 2, price = 823 },
        -- An item with a random suffix: its own name is the plain one.
        [15251] = { name = "Polished Zweihander", quality = 2, price = 3877 },
    }
    -- Items asked for with C_Item.RequestLoadItemDataByID.
    env.__requested = {}
    -- How the game colours each quality: grey, white, green.
    env.__qualityColors = {
        [0] = { 0.62, 0.62, 0.62 },
        [1] = { 1, 1, 1 },
        [2] = { 0.12, 1, 0 },
    }
    -- Items the client has not described yet: asking about them gives nothing.
    env.__uncached = {}

    function env.__link(id, fullName)
        return "|cff9d9d9d|Hitem:" .. id .. "::::::::20:::::::|h[" .. (fullName or env.__items[id].name) .. "]|h|r"
    end

    -- Bags by number, and each slot's contents keyed "bag:slot":
    -- { itemID, count, locked }.
    env.__bagSizes = { [0] = 16, [1] = 6, [2] = 6, [3] = 6, [4] = 6 }
    env.__slots = {}
    -- Slots whose read raises, as the client does on a secret value.
    env.__raisingSlots = {}

    -- The merchant, the money, and what was done at it.
    env.__merchantOpen = false
    env.__money = 0
    env.__canRepair = true
    env.__repairCost = 0
    env.__repairs = 0
    -- Items the merchant will not take, without saying so.
    env.__refused = {}
    -- A server that answers sales late (see UseContainerItem), and sales it
    -- never answers at all, whose slots stay locked.
    env.__slowSales = false
    env.__lostSales = {}
    env.__replies = {}
    env.__sales = {}
    env.__log = {}

    local function slotKey(bag, slot)
        return bag .. ":" .. slot
    end

    env.C_Container = {
        GetContainerNumSlots = function(bag)
            return env.__bagSizes[bag] or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local key = slotKey(bag, slot)
            if env.__raisingSlots[key] then
                error("attempt to compare a secret value", 2)
            end
            local held = env.__slots[key]
            if not held then return nil end
            local item = env.__items[held.itemID]
            return {
                iconFileID = 1,
                stackCount = held.count,
                isLocked = held.locked == true,
                quality = item.quality,
                hasNoValue = item.price == 0,
                hyperlink = env.__link(held.itemID),
                itemID = held.itemID,
            }
        end,
        -- At an open merchant, using an item sells it.
        UseContainerItem = function(bag, slot)
            local key = slotKey(bag, slot)
            table.insert(env.__sales, key)
            table.insert(env.__log, "sell " .. key)
            local held = env.__slots[key]
            if not (env.__merchantOpen and held) or env.__refused[held.itemID] then
                return
            end
            if env.__slowSales then
                -- The slot locks at once; the sale lands when the server
                -- answers, at the end of the next round of timers.
                held.locked = true
                if env.__lostSales[held.itemID] then return end
                local price = env.__items[held.itemID].price * held.count
                table.insert(env.__replies, function()
                    env.__money = env.__money + price
                    env.__slots[key] = nil
                end)
                return
            end
            env.__money = env.__money + env.__items[held.itemID].price * held.count
            env.__slots[key] = nil
        end,
    }

    -- How often each item was looked up.
    env.__itemInfoCalls = {}
    env.C_Item = {
        GetItemInfo = function(id)
            env.__itemInfoCalls[id] = (env.__itemInfoCalls[id] or 0) + 1
            local item = env.__items[id]
            if not item or env.__uncached[id] then return nil end
            return item.name, env.__link(id), item.quality, 1, 1, "Junk", "Junk", 1, "", 1, item.price
        end,
        GetItemNameByID = function(id)
            local item = env.__items[id]
            if item and not env.__uncached[id] then return item.name end
        end,
        -- The client knows every item's icon without asking the server.
        GetItemIconByID = function(id)
            if env.__items[id] then return 1000 + id end
        end,
        GetItemQualityByID = function(id)
            local item = env.__items[id]
            if item and not env.__uncached[id] then return item.quality end
        end,
        GetItemQualityColor = function(quality)
            local color = env.__qualityColors[quality]
            if color then return color[1], color[2], color[3], "ffffffff" end
        end,
        RequestLoadItemDataByID = function(id) env.__requested[id] = true end,
    }

    -- The tooltip can show a link as well as an item by ID.
    function env.GameTooltip:SetHyperlink(link) self.link = link end

    -- Shift, Ctrl or Alt held, when a test says so.
    env.__modifierDown = false
    function env.IsModifierKeyDown() return env.__modifierDown end

    function env.GetMoney() return env.__money end
    function env.CanMerchantRepair() return env.__canRepair end
    function env.GetRepairAllCost() return env.__repairCost, env.__repairCost > 0 end
    function env.RepairAllItems()
        table.insert(env.__log, "repair")
        env.__repairs = env.__repairs + 1
        env.__money = env.__money - env.__repairCost
        env.__repairCost = 0
    end

    return env
end

--- The auction house's sell frames, modeled on Blizzard_AuctionHouseUI in
-- the Forever client: selecting a row in the sell list runs a callback that
-- copies the row's price into the inputs. As in the client, the callback
-- captures the handler method when the frame first shows, so a hook has to
-- be on the frame by then to be caught up in it.
function stub.buildAuctionHouse(env)
    local function makePriceInput(shown)
        local input = { amount = 0, shown = shown }
        function input:SetAmount(value) self.amount = value end
        function input:GetAmount() return self.amount end
        function input:IsShown() return self.shown end
        return input
    end

    -- Stackable goods: one price input, filled with the row's unit price.
    local commodities = { PriceInput = makePriceInput(true) }
    function commodities:OnAuctionSelected(result)
        if not result then
            return
        end
        self.PriceInput:SetAmount(result.unitPrice)
    end
    function commodities:Show()
        local handler = self.OnAuctionSelected
        self.selectionCallback = function(rowData) handler(self, rowData) end
    end

    -- Single items: a buyout input, and a bid input shown only outside the
    -- default buyout-only mode.
    local items = {
        PriceInput = makePriceInput(true),
        SecondaryPriceInput = makePriceInput(false),
    }
    function items:OnSearchResultSelected(result)
        if not result then
            return
        end
        if self.SecondaryPriceInput:IsShown() then
            self.SecondaryPriceInput:SetAmount(result.bidAmount or 0)
        end
        self.PriceInput:SetAmount(result.buyoutAmount or 0)
    end
    function items:Show()
        local handler = self.OnSearchResultSelected
        self.selectionCallback = function(rowData) handler(self, rowData) end
    end

    -- The window, closed: its Buy, Sell and Auctions tabs, each showing its
    -- own part of the window (Blizzard_AuctionHouseFrame.lua's display
    -- modes, cut down to one part each), and the Buy tab's search bar.
    local frame = makeWidget("Frame", env.UIParent)
    frame.shown = false
    frame.CommoditiesSellFrame = commodities
    frame.ItemSellFrame = items

    env.AuctionHouseFrameDisplayMode = {
        Buy = { "BrowseResultsFrame" },
        ItemSell = { "ItemSellList" },
        Auctions = { "AuctionsFrame" },
    }
    local modes = env.AuctionHouseFrameDisplayMode
    for _, part in ipairs({ "BrowseResultsFrame", "ItemSellList", "AuctionsFrame" }) do
        frame[part] = makeWidget("Frame", frame)
        frame[part].shown = false
    end
    -- The Auctions tab's own Auctions and Bids tabs, 1 and 2.
    local auctions = frame.AuctionsFrame
    auctions.tab = 1
    function auctions:SetTab(id) self.tab = id end
    function auctions:GetTab() return self.tab end
    function auctions:IsDisplayingBids() return self.tab == 2 end
    -- Your gold, bottom left of the window.
    frame.MoneyFrameBorder = makeWidget("Frame", frame)

    frame.Tabs = {}
    frame.tabsForDisplayMode = {}
    for index, info in ipairs({ { "BuyTab", modes.Buy }, { "SellTab", modes.ItemSell }, { "AuctionsTab", modes.Auctions } }) do
        local tab = makeWidget("Button", frame)
        tab.displayMode = info[2]
        tab:SetScript("OnClick", function(self) frame:SetDisplayMode(self.displayMode) end)
        frame[info[1]] = tab
        frame.Tabs[index] = tab
        frame.tabsForDisplayMode[info[2]] = index
    end
    frame.numTabs = 3

    function frame:SetDisplayMode(mode)
        if self.displayMode == mode then return end
        self.displayMode = mode
        local wanted = {}
        for _, part in ipairs(mode) do wanted[part] = true end
        for _, other in pairs(env.AuctionHouseFrameDisplayMode) do
            for _, part in ipairs(other) do
                if not wanted[part] then self[part]:Hide() end
            end
        end
        for _, part in ipairs(mode) do self[part]:Show() end
        local tab = self.tabsForDisplayMode[mode]
        if tab then
            env.PanelTemplates_SetTab(self, tab)
            self:UpdateTitle()
        end
    end
    function frame:GetDisplayMode() return self.displayMode end
    function frame:UpdateTitle()
        local titles = { "Browse Auctions", "Post Auctions", "Auctions" }
        self:SetTitle(titles[self.selectedTab] or "Browse Auctions")
    end
    function frame:SetTitle(text) self.title = text end

    -- What the Buy tab was asked to look for, in order.
    env.__searches = {}
    frame.SearchBar = {}
    function frame.SearchBar:SetSearchText(text) self.text = text end
    function frame.SearchBar:StartSearch()
        table.insert(env.__searches, self.text)
        frame:SetDisplayMode(modes.Buy)
    end

    -- Opening it lands on the Buy tab, as the game's OnShow does.
    frame:SetScript("OnShow", function(self) self:SetDisplayMode(modes.Buy) end)

    env.AuctionHouseFrame = frame
    env.__loadedAddons["Blizzard_AuctionHouseUI"] = true
    return env.AuctionHouseFrame
end

--- The older client: no C_Container or C_Item, the old globals in their
-- place, answering the same way.
function stub.useLegacyAPI(env)
    local container, item = env.C_Container, env.C_Item
    env.C_Container, env.C_Item = nil, nil

    env.GetContainerNumSlots = container.GetContainerNumSlots
    function env.GetContainerItemInfo(bag, slot)
        local info = container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return info.iconFileID, info.stackCount, info.isLocked, info.quality, false, false,
            info.hyperlink, false, info.hasNoValue, info.itemID
    end
    env.UseContainerItem = container.UseContainerItem
    env.GetItemInfo = item.GetItemInfo
    env.GetItemIcon = item.GetItemIconByID
    env.GetItemQualityColor = item.GetItemQualityColor
end

return stub
