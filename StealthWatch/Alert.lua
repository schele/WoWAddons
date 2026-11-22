local addonName, ns = ...

-- Telling the player: a warning sound, the spell and who cast it in red in
-- the middle of the screen (where raid warnings go), and a fuller line in
-- chat. Each can be switched off on the settings page.

local Alert = {}
ns.Alert = Alert

ns.AddDefaults({ sound = true, screen = true, chat = true })

-- The boss emote warning: a horn, unlike the raid warning other addons use.
Alert.SOUND = 12197
Alert.RED = { r = 1, g = 0.25, b = 0.2 }

local function coloured(name, classFile)
    local colour = ns.Guarded(function()
        local entry = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        return entry and entry.colorStr
    end)
    if type(colour) == "string" then
        return string.format("|c%s%s|r", colour, name)
    end
    return name
end

--- The words in the middle of the screen: the spell, or Stealth when the
-- client hid it, then who.
function Alert.ScreenText(info)
    return string.format("%s: %s, %s", info.spell or "Stealth", coloured(info.name or "?", info.classFile),
        info.class or "?")
end

--- The line in chat: who, in full, and what they did.
function Alert.ChatText(info)
    local level = (tonumber(info.level) or 0) > 0 and tostring(info.level) or "??"
    local who = string.format("%s, level %s %s %s", info.name or "?", level, info.race or "?", info.class or "?")
    if info.spell then
        return string.format("%s, cast %s.", who, info.spell)
    end
    return string.format("%s, went out of sight right after an instant cast: likely stealth.", who)
end

local function showOnScreen(text)
    if RaidWarningUtil and RaidWarningUtil.AddMessage then
        RaidWarningUtil.AddMessage(text, Alert.RED)
    elseif RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, Alert.RED)
    elseif UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, Alert.RED.r, Alert.RED.g, Alert.RED.b)
    end
end

--- Alert the player to `info`, as each switch allows.
function Alert.Show(info)
    local settings = ns.settings
    if settings.sound then
        ns.Guarded(function()
            PlaySound(SOUNDKIT and SOUNDKIT.RAID_BOSS_EMOTE_WARNING or Alert.SOUND, "Master")
        end)
    end
    if settings.screen then
        ns.Guarded(function() showOnScreen(Alert.ScreenText(info)) end)
    end
    if settings.chat then
        ns.Print(Alert.ChatText(info))
    end
end

ns.OnStealth(Alert.Show)

--- An alert for a made-up rogue, to see and hear what one is like.
function Alert.Test()
    local settings = ns.settings
    if not (settings.sound or settings.screen or settings.chat) then
        ns.Print("All three alerts are off. Turn one on in the settings page (/sw).")
        return
    end
    local vanish = ns.Guarded(function() return ns.Watcher.Classify(1856) end)
    Alert.Show({
        name = "Example", class = "Rogue", classFile = "ROGUE", level = 60, race = "Night Elf",
        spell = type(vanish) == "string" and vanish or "Vanish", confirmed = true,
    })
end

ns.RegisterCommand("test", "Show what an alert looks like", Alert.Test)
