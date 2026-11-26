local addonName, ns = ...

-- A second click on a link closes the tooltip it opened.
--
-- Forever's linked-item tooltip means to do this itself: its SetHyperlink
-- hides the tooltip when asked for the link it already shows. The check never
-- matches, though. The link it keeps was packed with SafePack, which adds an
-- `n` field, and tCompare counts that field as a difference, so a second
-- click draws the same tooltip again. Retail's code has the same slip.
--
-- Hooked after the client's SetHyperlink rather than replacing it, so the
-- tooltip's own code stays Blizzard's. A client that gets the check right
-- hides the tooltip itself, and the hook finds it hidden and leaves it.

ns.AddDefaults({
    linkTooltip = {
        toggle = true,
    },
})

local LinkTooltip = {}
ns.LinkTooltip = LinkTooltip

-- What the tooltip was last asked to show, for as long as it has stayed on
-- screen since. Hiding it, by its X or any other way, forgets it.
local showing = nil

local function pack(...)
    return { n = select("#", ...), ... }
end

local function same(a, b)
    if not a or a.n ~= b.n then
        return false
    end
    for index = 1, b.n do
        if a[index] ~= b[index] then
            return false
        end
    end
    return true
end

local function afterSetHyperlink(tooltip, ...)
    -- Hidden: the client could not show the link, or closed the tooltip
    -- itself because it was the same one.
    if not tooltip:IsShown() then
        showing = nil
        return
    end

    local asked = pack(...)
    if ns.db and ns.db.linkTooltip.toggle and same(showing, asked) then
        tooltip:Hide()
        showing = nil
        return
    end
    showing = asked
end

local installed = false

function LinkTooltip.Install()
    if installed then
        return
    end
    installed = true

    local tooltip = ItemRefTooltip
    if not (hooksecurefunc and tooltip and tooltip.SetHyperlink and tooltip.HookScript) then
        return
    end
    hooksecurefunc(tooltip, "SetHyperlink", afterSetHyperlink)
    tooltip:HookScript("OnHide", function()
        showing = nil
    end)
end

ns.OnLogin(LinkTooltip.Install)

ns.RegisterSetting({
    store = "linkTooltip",
    key = "toggle",
    type = "checkbox",
    name = "Click a link again to close it",
    tooltip = "A second click on the item, spell or quest link a tooltip is showing closes the tooltip, as the game means to but does not.",
})
