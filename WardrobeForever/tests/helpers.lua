local stub = require("wow_stub")

local M = {}

M.SLOT = stub.SLOT
M.worn = stub.worn
M.inBag = stub.inBag
M.inBank = stub.inBank

M.FILES = { "WardrobeForever.lua" }

--- Load the addon into a stubbed client the way WoW would: in .toc order,
-- each chunk receiving (addonName, privateTable).
function M.load()
    local env = stub.newEnv()
    local ns = {}

    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("WardrobeForever", ns)
    end

    return ns, env
end

--- Say that an item at `location` fits the slot, as GetInventoryItemsForSlot
-- would list it.
function M.fits(env, slotID, location, itemID)
    env.__items[slotID] = env.__items[slotID] or {}
    env.__items[slotID][location] = itemID or location
end

--- Move the cursor onto `frame`, or off everything when `frame` is nil:
-- OnLeave for whatever it was over, then OnEnter for the new frame.
function M.moveTo(env, frame)
    local left = {}
    for over in pairs(env.__mouseOver) do
        if over ~= frame then
            left[#left + 1] = over
        end
    end
    for _, over in ipairs(left) do
        env.__mouseOver[over] = nil
        over:Fire("OnLeave")
    end

    if frame and not env.__mouseOver[frame] then
        env.__mouseOver[frame] = true
        frame:Fire("OnEnter")
    end
end

--- Let `seconds` of game time pass, a frame at a time, running every shown
-- frame's OnUpdate.
function M.tick(env, seconds)
    local step = 1 / 60
    local elapsed = 0
    while elapsed < seconds - 1e-9 do
        local frames = {}
        for index, frame in ipairs(env.__frames) do
            frames[index] = frame
        end
        for _, frame in ipairs(frames) do
            if frame.shown and frame.scripts.OnUpdate then
                frame.scripts.OnUpdate(frame, step)
            end
        end
        elapsed = elapsed + step
    end
end

function M.flyoutOpenFor(env, slot)
    return env.EquipmentFlyoutFrame:IsShown() and env.EquipmentFlyoutFrame.button == slot
end

return M
