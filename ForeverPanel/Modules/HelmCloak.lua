local addonName, ns = ...

-- Helm and Cloak boxes on the character window's model. The game keeps both
-- switches on the account and still answers ShowHelm and ShowCloak, but this
-- client has lost the checkboxes that used to set them.

local HelmCloak = { boxes = {} }
ns.HelmCloak = HelmCloak

local SIZE = 22
-- Without its slot, a box goes down the model's top left instead.
local TOP = -40

-- Each switch the client may have, and the slot its box sits beside: the
-- model starts behind the slots down the window's left, so the box goes just
-- right of its own slot, where it reads as that slot's.
local SWITCHES = {
    { key = "helm", label = "Helm", show = "ShowHelm", showing = "ShowingHelm", slot = "CharacterHeadSlot" },
    { key = "cloak", label = "Cloak", show = "ShowCloak", showing = "ShowingCloak", slot = "CharacterBackSlot" },
}

local function modelFrame()
    return CharacterModelFrame or CharacterModelScene
end

function HelmCloak.Refresh()
    for _, switch in ipairs(SWITCHES) do
        local box = HelmCloak.boxes[switch.key]
        if box then
            box:SetChecked(_G[switch.showing]() and true or false)
        end
    end
end

local function create()
    local model = modelFrame()
    if not model or HelmCloak.boxes.helm or HelmCloak.boxes.cloak then
        return
    end

    local y = TOP
    for _, switch in ipairs(SWITCHES) do
        if type(_G[switch.show]) == "function" and type(_G[switch.showing]) == "function" then
            local box = CreateFrame("CheckButton", nil, model, "UICheckButtonTemplate")
            box:SetSize(SIZE, SIZE)
            local slot = _G[switch.slot]
            if slot then
                box:SetPoint("LEFT", slot, "RIGHT", 4, 0)
            else
                box:SetPoint("TOPLEFT", model, "TOPLEFT", 4, y)
            end

            -- Our own label: the template's is not there on every client.
            local label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            label:SetPoint("LEFT", box, "RIGHT", 2, 0)
            label:SetText(switch.label)
            box.label = label

            box:SetScript("OnClick", function(self)
                _G[switch.show](self:GetChecked() and true or false)
            end)

            HelmCloak.boxes[switch.key] = box
            y = y - SIZE
        end
    end

    if model.HookScript then
        model:HookScript("OnShow", HelmCloak.Refresh)
    end
    HelmCloak.Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
-- Fires when the account's switches change, by a box here or any other way.
events:RegisterEvent("PLAYER_FLAGS_CHANGED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        create()
    elseif unit == nil or unit == "player" then
        HelmCloak.Refresh()
    end
end)
