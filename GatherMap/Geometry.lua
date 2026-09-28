local addonName, ns = ...

-- The sums that put a world position, in yards, on a map or the minimap.
-- World X runs north and Y west; a map's x runs east and its y south, so a
-- map's x follows world Y and its y follows world X.

local Geometry = {}
ns.Geometry = Geometry

-- How many yards across the minimap is at each zoom level, 0 to 5, as the
-- client draws it, out of doors and in.
Geometry.OUTDOOR = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
Geometry.INDOOR = { 300, 240, 180, 120, 80, 50 }

local rects = {}

--- Where map `uiMapID` sits in the world: its continent, and the world
-- positions of its top-left (x0, y0) and bottom-right (x1, y1) corners. Nil
-- for a map the client cannot place, such as the whole world. Kept once
-- known, refusals included: a map's place never moves.
function Geometry.MapRect(uiMapID)
    if not uiMapID then
        return nil
    end
    if rects[uiMapID] == nil then
        rects[uiMapID] = ns.Guarded(function()
            local continent, topLeft = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(0, 0))
            local _, bottomRight = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(1, 1))
            if not continent or not topLeft or not bottomRight then
                return false
            end
            if topLeft.x == bottomRight.x or topLeft.y == bottomRight.y then
                return false
            end
            return { continent = continent, x0 = topLeft.x, y0 = topLeft.y, x1 = bottomRight.x, y1 = bottomRight.y }
        end, false)
    end
    return rects[uiMapID] or nil
end

--- A world position on the map `rect` describes: 0..1 each way inside it.
function Geometry.ToMap(rect, x, y)
    return (y - rect.y0) / (rect.y1 - rect.y0), (x - rect.x0) / (rect.x1 - rect.x0)
end

function Geometry.MinimapDiameter(zoom, indoors)
    local sizes = indoors and Geometry.INDOOR or Geometry.OUTDOOR
    return sizes[(zoom or 0) + 1] or sizes[1]
end

--- Where a spawn at (x, y) sits from the player at (px, py) on the
-- minimap, in yards: right and up. With the minimap turning, the direction
-- faced (`facing`, radians anticlockwise from north) is up.
function Geometry.MinimapOffset(px, py, x, y, facing, rotate)
    local right, up = py - y, x - px
    if rotate and facing then
        local c, s = math.cos(facing), math.sin(facing)
        right, up = right * c + up * s, -right * s + up * c
    end
    return right, up
end
