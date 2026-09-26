local stub = require("wow_stub")

local M = {}

M.FILES = { "BankBags.lua", "Bank.lua", "Window.lua", "Minimap.lua" }

local function exists(path)
    local file = io.open(path)
    if file then
        file:close()
        return true
    end
    return false
end

--- Load files into a fresh stubbed environment; files not written yet are skipped.
function M.loadAddon(files, setup)
    local env = stub.newEnv()
    function env.GameTooltip:SetHyperlink(link) self.hyperlink = link end
    local ns = {}
    if setup then setup(env, ns) end
    for _, path in ipairs(files or M.FILES) do
        if exists(path) then
            local chunk = assert(loadfile(path, "t", env))
            chunk("BankBags", ns)
        end
    end
    return ns, env
end

function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do frames[index] = frame end
    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then frame:Fire(event, ...) end
    end
end

function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "BankBags")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.BANKBAGS(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- Playing Carl, a druid on Stormwind, at a time the test can move (env.__now).
function M.player(env)
    function env.UnitName(unit) if unit == "player" then return "Carl" end end
    function env.GetRealmName() return "Stormwind" end
    function env.UnitClass(unit) if unit == "player" then return "Druid", "DRUID" end end
    env.__now = env.__now or 1790000000
    function env.time() return env.__now end
end

--- A bank for C_Container: container id -> list of slots (false for empty),
-- each { link, count, icon, quality }; bag id -> { link, icon } for each
-- bank bag's own item.
function M.bank(env, containers, bags)
    env.C_Container = {
        GetContainerNumSlots = function(id)
            local slots = containers[id]
            return slots and #slots or 0
        end,
        GetContainerItemInfo = function(id, slot)
            local item = containers[id] and containers[id][slot]
            if not item then return nil end
            return { hyperlink = item.link, stackCount = item.count, iconFileID = item.icon, quality = item.quality }
        end,
        ContainerIDToInventoryID = function(id) return 100 + id end,
    }
    function env.GetInventoryItemLink(_, slot)
        local bag = bags and bags[slot - 100]
        return bag and bag.link
    end
    function env.GetInventoryItemTexture(_, slot)
        local bag = bags and bags[slot - 100]
        return bag and bag.icon
    end
end

--- Loaded and logged in as Carl.
function M.loggedIn(setup)
    local ns, env = M.loadAddon(nil, function(e, n)
        M.player(e)
        if setup then setup(e, n) end
    end)
    M.login(ns, env)
    return ns, env
end

return M
