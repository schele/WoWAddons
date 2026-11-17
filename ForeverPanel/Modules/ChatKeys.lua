local addonName, ns = ...

-- Keys that open the chat box on a channel. Ctrl+S for /say and so on,
-- configurable from the settings panel.
--
-- The game opens the box: each key is bound to its own OPENCHAT, and the
-- channel is set afterwards through the box's attributes. Opening the box
-- from addon code, as ChatFrame_OpenChat("/p ") did, marks the box and the
-- globals naming the open box as ForeverPanel's, and the game then blocks its
-- own code that reads them. Shift-clicking a map pin into chat copies a
-- /mappin line to the clipboard, which only the game may do, so it was
-- blocked and blamed on ForeverPanel. Attributes carry no such mark, which is
-- why the game keeps the channel in them. Typing into the box would mark it
-- again, so a row can pick a channel but never type text.

local ROWS = 8

-- A working set out of the box. It matters more than it usually would: this
-- client restores SavedVariables for no addon, so without these the table is
-- empty every login.
local SEED = {
    { key = "CTRL-S", command = "/s" },
    { key = "CTRL-G", command = "/g" },
    -- Trade chat is channel 2 in a city. "/trade" opens a trade with your
    -- target instead, and is not a channel at all.
    { key = "CTRL-T", command = "/2" },
    { key = "CTRL-Y", command = "/y" },
    { key = "CTRL-P", command = "/p" },
}

ns.AddDefaults({
    chat = {
        -- On by default: this client discards SavedVariables, so anything off
        -- by default is off at every login. Turned off, nothing here is
        -- created at all, which is what makes the switch worth having.
        enabled = true,
        keys = {},
        seeded = false,
    },
})

local ChatKeys = {}
ns.ChatKeys = ChatKeys
ChatKeys.ROWS = ROWS

local owner = CreateFrame("Frame", nil, UIParent)
local pending = false
local hooked = false

--- Build a binding string from a key and whatever modifiers are held.
-- Returns nil for a key that cannot stand on its own, so the capture keeps
-- waiting rather than binding "CTRL-" to something.
function ChatKeys.Combination(key)
    if not key or key == "ESCAPE" or key == "UNKNOWN" then
        return nil
    end

    -- A modifier pressed by itself is the player reaching for the combination,
    -- not the combination.
    if key:match("^[LR]CTRL$") or key:match("^[LR]SHIFT$") or key:match("^[LR]ALT$") then
        return nil
    end

    -- WoW writes them in this order, and matching it is what makes the string
    -- usable as a binding.
    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end

    -- A bare key takes that key everywhere: bind "B" and bags stop opening,
    -- bind a movement key and the character stops moving. Function keys are
    -- the exception, being nobody else's by default.
    if prefix == "" and not key:match("^F%d+$") then
        return nil
    end

    return prefix .. key
end

--- The chat type one of the game's slash commands selects, such as PARTY for
-- "/p" or "/party". Read from the game's own tables, so every alias and
-- language it knows works. Once the game has hashed its slash commands it
-- moves each chat type into a proxy behind ChatTypeInfo's __index, so both
-- are searched.
local function chatTypeFor(slash)
    if type(ChatTypeInfo) ~= "table" then
        return nil
    end

    local wanted = slash:upper()

    local function search(list)
        for chatType, info in pairs(list) do
            if type(chatType) == "string" and type(info) == "table" and not info.ignoreChatTypeProcessing then
                local index = 1
                local alias = _G["SLASH_" .. chatType .. index]
                while alias do
                    if alias:upper() == wanted then
                        return chatType
                    end
                    index = index + 1
                    alias = _G["SLASH_" .. chatType .. index]
                end
            end
        end
    end

    local found = search(ChatTypeInfo)
    if found then
        return found
    end

    local meta = getmetatable(ChatTypeInfo)
    if meta and type(meta.__index) == "table" then
        return search(meta.__index)
    end
end

local WHISPERS = { WHISPER = true, SMART_WHISPER = true, BN_WHISPER = true }

-- Types the game fills in from something besides the command: the last
-- whisper for a reply, a name typed after /c for a channel.
local NOT_A_CHANNEL = { REPLY = true, CHANNEL = true }

--- What a row's command opens: a chat type, plus the channel number or the
-- name to whisper. Nil for anything that is not a channel, such as "/trade",
-- or that carries text, such as "/s hello".
function ChatKeys.Resolve(command)
    if type(command) ~= "string" then
        return nil
    end

    local slash, rest = command:match("^%s*(/%S+)%s*(.-)%s*$")
    if not slash then
        return nil
    end

    local number = tonumber(slash:match("^/(%d+)$"))
    if number then
        if number > 0 and rest == "" then
            return { chatType = "CHANNEL", channelTarget = number }
        end
        return nil
    end

    local chatType = chatTypeFor(slash)
    if not chatType or NOT_A_CHANNEL[chatType] then
        return nil
    end

    if WHISPERS[chatType] then
        if rest:match("^%S+$") then
            return { chatType = chatType, tellTarget = rest }
        end
        return nil
    end

    if rest ~= "" then
        return nil
    end

    return { chatType = chatType }
end

local function rowFor(index)
    local rows = ns.db and ns.db.chat and ns.db.chat.keys
    return rows and rows[index]
end

--- Split "ALT-CTRL-S" into its modifiers and the key itself.
local function parseCombination(combination)
    local modifiers = {}
    local key = combination

    while true do
        local modifier, remainder = key:match("^(%u+)%-(.+)$")
        if modifier ~= "ALT" and modifier ~= "CTRL" and modifier ~= "SHIFT" then
            break
        end
        modifiers[modifier] = true
        key = remainder
    end

    return modifiers, key
end

local function isDown(check)
    return (check and check()) and true or false
end

--- The row whose combination is held down right now, resolved. The game's
-- binding knows which key it answered but does not say, so ask the keyboard.
local function heldTarget()
    if not IsKeyDown then
        return nil
    end

    for index = 1, ROWS do
        local row = rowFor(index)
        if row and row.key and row.key ~= "" then
            local modifiers, key = parseCombination(row.key)

            if isDown(IsAltKeyDown) == (modifiers.ALT == true)
                and isDown(IsControlKeyDown) == (modifiers.CTRL == true)
                and isDown(IsShiftKeyDown) == (modifiers.SHIFT == true)
                and IsKeyDown(key) then
                local target = ChatKeys.Resolve(row.command)
                if target then
                    return target
                end
            end
        end
    end
end

--- Runs after the game has opened the chat box, from its own code. Only ever
-- sets attributes, and redraws the header, which reads them and draws.
local function onOpenChat(text)
    if not (ns.db and ns.db.chat and ns.db.chat.enabled) then
        return
    end

    -- A link, a whisper from a name, anything opened with text: not our key.
    -- The binding passes nil on Forever and "" on Classic Era.
    if text ~= nil and text ~= "" then
        return
    end

    local target = heldTarget()
    if not target then
        return
    end

    -- Outside a city there is no Trade channel, so open on the usual one.
    if target.channelTarget and GetChannelName and GetChannelName(target.channelTarget) == 0 then
        return
    end

    local box = ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
    if not box or not box.SetChatType then
        return
    end

    if target.tellTarget then
        box:SetTellTarget(target.tellTarget)
    end
    if target.channelTarget then
        box:SetChannelTarget(target.channelTarget)
    end
    box:SetChatType(target.chatType)

    if box.UpdateHeader then
        box:UpdateHeader()
    end
end

--- Hook the game's OpenChat, once. hooksecurefunc leaves the game's own call
-- untouched and runs ours after it, so the box is opened by the game.
local function hookOpenChat()
    if hooked then
        return true
    end
    if not hooksecurefunc or not ChatFrameUtil or not ChatFrameUtil.OpenChat then
        return false
    end

    hooksecurefunc(ChatFrameUtil, "OpenChat", onOpenChat)
    hooked = true
    return true
end

--- Put every row that opens a channel on its key.
-- Override bindings layer on top of the player's own, so nothing they have set
-- is edited or lost, and a reload clears ours.
function ChatKeys.Apply()
    if not SetOverrideBinding or not ClearOverrideBindings then
        return false
    end

    -- Bindings are protected in combat. Hold the change rather than erroring,
    -- and put it on when the fight ends.
    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return false
    end

    pending = false
    ClearOverrideBindings(owner)

    -- Nothing exists while the feature is off: no bindings and no hook. That
    -- makes "off" mean genuinely absent rather than merely inactive, which is
    -- the only way to tell whether this feature is behind a problem or not. A
    -- hook cannot be taken off again, so once made it checks the switch.
    if ns.db.chat.enabled and hookOpenChat() then
        for index = 1, ROWS do
            local row = rowFor(index)
            if row and row.key and row.key ~= "" and ChatKeys.Resolve(row.command) then
                SetOverrideBinding(owner, true, row.key, "OPENCHAT")
            end
        end
    end

    return true
end

--- Drop every binding we hold, without changing the table.
-- The way out if ours are the ones swallowing keys.
function ChatKeys.ReleaseBindings()
    if ClearOverrideBindings then
        ClearOverrideBindings(owner)
    end
end

ns.RegisterSetting({
    store = "chat",
    key = "enabled",
    type = "checkbox",
    column = 2,
    name = "Chat shortcut keys",
    tooltip = "Ctrl+P opens chat on /party and so on. Each key picks a channel: /s, /p, /g, /ra, /y, /e, a channel number such as /2, or /w and a name. It cannot type anything else.",
    onChange = ChatKeys.Apply,
})

ns.RegisterSetting({
    store = "chat",
    key = "keys",
    type = "keytable",
    parent = "chat.enabled",
    name = "Chat shortcuts",
    -- Its own column: eight rows down the left would push everything else off
    -- the bottom of the panel.
    column = 2,
    rows = ROWS,
    onChange = ChatKeys.Apply,
})

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not ns.db.chat.seeded then
            ns.db.chat.seeded = true
            for index, entry in ipairs(SEED) do
                ns.db.chat.keys[index] = { key = entry.key, command = entry.command }
            end
        end

        for index = 1, ROWS do
            ns.db.chat.keys[index] = ns.db.chat.keys[index] or { key = "", command = "" }
        end

        ChatKeys.Apply()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The binding set has loaded by now, so this is the one that sticks.
        ChatKeys.Apply()
    elseif event == "PLAYER_REGEN_ENABLED" and pending then
        ChatKeys.Apply()
    end
end)
