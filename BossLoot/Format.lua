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
        -- A whole number reads as one: "5%", not "5.0%".
        if tenths == math.floor(tenths) then
            return string.format("%d%%", tenths)
        end
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
    -- Some items come back with an empty type; treat it as none, or the
    -- label reads ", Other".
    local function named(value)
        return value ~= "" and value or nil
    end
    local slot = named(equipLoc) and _G[equipLoc] or nil
    local first = slot or named(itemType)
    local second = named(itemSubType)

    if first and second and second ~= "" and second ~= first then
        return first .. ", " .. second
    end

    return first or second or ""
end
