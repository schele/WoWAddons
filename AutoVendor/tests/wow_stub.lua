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
    widget.points = {}
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
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
        return frame
    end

    env.UIParent = makeWidget("Frame")

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
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

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
        env.__timers, env.__replies = {}, {}
        for _, fn in ipairs(pending) do fn() end
        for _, fn in ipairs(replies) do fn() end
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
    }
    -- Items the client has not described yet: asking about them gives nothing.
    env.__uncached = {}

    function env.__link(id)
        return "|cff9d9d9d|Hitem:" .. id .. "::::::::20:::::::|h[" .. env.__items[id].name .. "]|h|r"
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

    env.C_Item = {
        GetItemInfo = function(id)
            local item = env.__items[id]
            if not item or env.__uncached[id] then return nil end
            return item.name, env.__link(id), item.quality, 1, 1, "Junk", "Junk", 1, "", 1, item.price
        end,
        GetItemNameByID = function(id)
            local item = env.__items[id]
            if item and not env.__uncached[id] then return item.name end
        end,
    }

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
end

return stub
