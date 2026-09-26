local addonName, ns = ...

-- Pure helpers for how things read in the loot column.

local Format = {}
ns.Format = Format

--- A drop chance as the loot column shows it: one decimal under ten percent,
-- whole numbers from there, and "<0.1%" rather than a misleading "0.0%".
function Format.Chance(percent)
    percent = tonumber(percent) or 0

    if percent < 0.1 then
        return "<0.1%"
    end

    local tenths = math.floor(percent * 10 + 0.5) / 10
    if tenths < 10 then
        return string.format("%.1f%%", tenths)
    end

    return string.format("%d%%", math.floor(percent + 0.5))
end

-- The game's own quality colours, written in rather than asked for: the API
-- for them has moved between clients, and the colours never have.
local QUALITY_HEX = {
    [0] = "9d9d9d", -- poor
    [1] = "ffffff", -- common
    [2] = "1eff00", -- uncommon
    [3] = "0070dd", -- rare
    [4] = "a335ee", -- epic
    [5] = "ff8000", -- legendary
    [6] = "e6cc80", -- artifact
}

function Format.QualityHex(quality)
    return QUALITY_HEX[quality] or QUALITY_HEX[1]
end

function Format.Colored(text, quality)
    return "|cff" .. Format.QualityHex(quality) .. tostring(text) .. "|r"
end

--- The grey line under an item's name: the slot and kind for gear
-- ("Two-Hand, Maces"), the type and kind for anything else ("Recipe,
-- Tailoring"), collapsing a repeat ("Key", not "Key, Key").
function Format.TypeLabel(itemType, itemSubType, equipLoc)
    local slot = equipLoc and equipLoc ~= "" and _G[equipLoc] or nil
    local first = slot or itemType
    local second = itemSubType

    if first and second and second ~= "" and second ~= first then
        return first .. ", " .. second
    end

    return first or second or ""
end
