local addonName, ns = ...

-- Lighting a glow only when the target's health is at most what a Bite
-- takes, without ever looking at the health.
--
-- On WoW Forever a mob's health and its max health are both secrets to
-- addons: they may be handed to the screen, not compared. Nor can there be a
-- sum or a curve over them here: curves work on health as a percentage, and
-- that needs the max. So the client's own status bars do the comparing.
--
-- The clamp bar's range is the Bite's reach to one point more, and the
-- health goes in as its value. The client keeps a value inside its range, so
-- what comes back (still a secret) is the reach when the health is at or
-- below it, and one more when above: health comes in whole points. Each
-- piece of the glow is a bar running from the reach to that value, filled to
-- the reach. A range of one point fills it 0%. A range of nothing, with the
-- StandardNoRangeFill style, fills it 100%. So a piece is all there when the
-- Bite would kill and none of it otherwise.
--
-- Where the client shows the health as a plain number (Classic Era), the
-- comparison is a plain one here.

local Gate = {}
ns.Gate = Gate

Gate.WHITE = "Interface\\Buttons\\WHITE8X8"

local function noRangeFill()
    return Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.StandardNoRangeFill
end

--- Whether this client has what the comparing by bars needs.
function Gate.ClientCompares()
    return noRangeFill() ~= nil
end

--- Whether this client hides values from addons, so the bars must compare.
function Gate.Needed()
    return issecretvalue ~= nil
end

local Prototype = {}
Prototype.__index = Prototype

--- A gate over `frame`: an empty holder for the glow's pieces, the size of
-- `frame`, and the clamp bar, which draws nothing.
function Gate.New(frame)
    local gate = setmetatable({ pieces = {} }, Prototype)
    gate.holder = CreateFrame("Frame", nil, frame)
    gate.holder:SetAllPoints(frame)
    gate.clamp = CreateFrame("StatusBar", nil, gate.holder)
    gate.clamp:SetAllPoints(gate.holder)
    return gate
end

--- A piece of the glow: a bar whose fill is `texture` (white when nil) in
-- colour r, g, b, a, drawn with `blend`, `level` frames above the holder.
-- Place it as any frame.
function Prototype:Piece(texture, r, g, b, a, blend, level)
    local piece = CreateFrame("StatusBar", nil, self.holder)
    piece:SetStatusBarTexture(texture or Gate.WHITE)
    piece:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1)
    if blend then
        piece:GetStatusBarTexture():SetBlendMode(blend)
    end
    local style = noRangeFill()
    if style and piece.SetFillStyle then
        piece:SetFillStyle(style)
    end
    piece:SetFrameLevel(self.holder:GetFrameLevel() + (level or 1))
    piece:SetMinMaxValues(0, 1)
    piece:SetValue(0)
    table.insert(self.pieces, piece)
    return piece
end

--- Every piece all there, or none of it.
function Prototype:Fill(full)
    for _, piece in ipairs(self.pieces) do
        piece:SetMinMaxValues(0, 1)
        piece:SetValue(full and 1 or 0)
    end
end

--- The pieces filled through the client's bars: all there when `health` is
-- at most `reach`, none otherwise. `health` may be a secret: it is only
-- handed on.
function Prototype:Through(reach, health)
    self.clamp:SetMinMaxValues(reach, reach + 1)
    self.clamp:SetValue(health)
    local kept = self.clamp:GetValue()
    for _, piece in ipairs(self.pieces) do
        piece:SetMinMaxValues(reach, kept)
        piece:SetValue(reach)
    end
end

--- Light the pieces when `health` is at most `reach`, a plain whole number.
-- `health` may be a secret, and then the client compares.
function Prototype:Set(reach, health)
    if ns.IsSecret(health) then
        self:Through(reach, health)
    else
        self:Fill(health <= reach)
    end
end

--- Light the pieces as a kill would: through the client's bars where it
-- compares, so a test that lights shows they work.
function Prototype:Test()
    if Gate.ClientCompares() then
        self:Through(1, 1)
    else
        self:Fill(true)
    end
end

-- A bar that is never shown, for Gate.Check.
local checkBar

--- Whether the client keeps a bar's value inside its range, as the
-- comparing needs. Asked with plain numbers, so the answer can be read.
function Gate.Check()
    return ns.Guarded(function()
        checkBar = checkBar or CreateFrame("StatusBar")
        checkBar:SetMinMaxValues(10, 11)
        checkBar:SetValue(5)
        local low = ns.Number(checkBar:GetValue())
        checkBar:SetValue(50)
        local high = ns.Number(checkBar:GetValue())
        return low == 10 and high == 11
    end, false)
end
