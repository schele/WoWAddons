local addonName, ns = ...

-- A plan as text, to paste to a friend or keep: TP1:<CLASS>:<points>, two
-- characters a point, the tree (1-3) and the talent's index in base 36. No
-- game calls: whether the points make sense for this client is Plan's
-- question, asked by the import.

local Codec = {}
ns.Codec = Codec

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local NOT_OURS = "Not a TalentPlanner string."

function Codec.Encode(class, points)
    local parts = {}
    for n, point in ipairs(points) do
        local tab, index = point[1], point[2]
        if index < 1 or index > 35 then
            return nil, string.format("Point %d names talent %d, which cannot be written.", n, index)
        end
        if tab < 1 or tab > 9 then
            return nil, string.format("Point %d names tree %d, which cannot be written.", n, tab)
        end
        parts[#parts + 1] = tostring(tab) .. DIGITS:sub(index + 1, index + 1)
    end
    return "TP1:" .. class .. ":" .. table.concat(parts)
end

--- { class = "DRUID", points = { {tab, index}, ... } }, or nil and why.
function Codec.Decode(text)
    if type(text) ~= "string" then
        return nil, NOT_OURS
    end
    local trimmed = text:match("^%s*(.-)%s*$"):upper()
    local class, body = trimmed:match("^TP1:(%u+):(%w*)$")
    if not class then
        return nil, NOT_OURS
    end
    if #body % 2 ~= 0 then
        return nil, "The points are cut short."
    end

    local points = {}
    for at = 1, #body, 2 do
        local n = #points + 1
        local tab = tonumber(body:sub(at, at))
        local index = tonumber(body:sub(at + 1, at + 1), 36)
        if not tab or tab < 1 or tab > 3 then
            return nil, string.format("Point %d names tree %s; there are three.", n, body:sub(at, at))
        end
        if index == 0 then
            return nil, string.format("Point %d names talent 0.", n)
        end
        points[n] = { tab, index }
    end
    return { class = class, points = points }
end
