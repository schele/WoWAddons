-- A minimal stand-in for the WoW API, enough to load AutoVendor outside the
-- game: frames, timers, bags, items, a merchant and money. It records what
-- was done so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {},
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end

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

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
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
