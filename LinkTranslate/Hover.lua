local addonName, ns = ...

-- Pointing at a link LinkTranslate changed shows, in a small tooltip, what
-- the sender's game called it: the words to use when answering them, or to
-- search for on a site in their language.

ns.AddDefaults({
    hover = true,
})

local Hover = {}
ns.Hover = Hover

-- The chat window whose link the tooltip is showing, while it shows one of ours.
local shownFor

function Hover.Enter(chatFrame, link)
    if not (ns.settings and ns.settings.hover) or not GameTooltip then
        return
    end
    local original = ns.Chat.Original(link)
    if not original then
        return
    end

    GameTooltip:SetOwner(chatFrame, "ANCHOR_CURSOR")
    GameTooltip:SetText(original, 1, 1, 1)
    GameTooltip:AddLine("What the sender's game calls it", 0.6, 0.6, 0.6)
    GameTooltip:Show()
    shownFor = chatFrame
end

function Hover.Leave(chatFrame)
    if not shownFor or (chatFrame and chatFrame ~= shownFor) then
        return
    end
    -- Only our tooltip: something else may have taken it over since.
    if GameTooltip:GetOwner() == shownFor then
        GameTooltip:Hide()
    end
    shownFor = nil
end

local installed = false

function Hover.Install()
    if installed then
        return
    end
    installed = true

    -- Forever's chat windows announce a pointed-at link to anyone listening,
    -- the temporary whisper windows included.
    if EventRegistry and ChatFrameMixin and ChatFrameMixin.OnHyperlinkEnter then
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, chatFrame, link)
            Hover.Enter(chatFrame, link)
        end, Hover)
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function(_, chatFrame)
            Hover.Leave(chatFrame)
        end, Hover)
        return
    end

    -- Elsewhere, each window that is there at login is hooked by hand.
    for _, frame in ipairs(ns.Chat.Frames()) do
        if frame.HookScript then
            frame:HookScript("OnHyperlinkEnter", function(self, link)
                Hover.Enter(self, link)
            end)
            frame:HookScript("OnHyperlinkLeave", function(self)
                Hover.Leave(self)
            end)
        end
    end
end

ns.OnLogin(Hover.Install)
