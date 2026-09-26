local addonName, ns = ...

-- Boss pictures, drawn by the client from the model IDs in the data: a round
-- portrait for the boss list, a 3D model for the boss page. Both calls are
-- guarded -- an ID the client does not know, or a value it keeps secret,
-- falls back to an icon rather than an error.

local Portrait = {}
ns.Portrait = Portrait

Portrait.ICONS = {
    trash = "Interface\\Icons\\INV_Misc_Bag_10",
    objects = "Interface\\Icons\\INV_Box_02",
    unknown = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
}

--- A round portrait of the creature with this model on `texture`, or the
-- fallback icon. Returns which it drew.
function Portrait.Set(texture, display, fallbackIcon)
    if display and SetPortraitTextureFromCreatureDisplayID then
        if pcall(SetPortraitTextureFromCreatureDisplayID, texture, display) then
            return "portrait"
        end
    end
    texture:SetTexture(fallbackIcon or Portrait.ICONS.unknown)
    return "icon"
end

--- The creature's 3D model on a PlayerModel frame. False when there is no
-- model to show, so the caller can show a portrait instead.
function Portrait.SetModel(model, display)
    if not (display and model and model.SetDisplayInfo) then
        return false
    end
    return pcall(model.SetDisplayInfo, model, display) and true or false
end
