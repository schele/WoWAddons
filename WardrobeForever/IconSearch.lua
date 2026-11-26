local _, ns = ...

-- A search box for the equipment set icon window (the one New Set opens on
-- the Equipment Manager tab). Its grid holds thousands of icons and the
-- game gives them no names, so the search matches the names of what has
-- each icon: this character's forms, its spells, and the items it wears or
-- carries. "cat" finds Cat Form's icon.
--
-- It only changes which icons the grid lists. Clicking one puts it on the
-- window's "selected" button as before, and that button's icon is what the
-- Okay button saves (GearManagerPopupFrameMixin:OkayButton_OnClick), so a
-- shorter list cannot save a wrong icon. Clearing the box puts the game's
-- own list back.

local IconSearch = {}
ns.IconSearch = IconSearch

local BOX_WIDTH = 150
local BOX_HEIGHT = 20
-- Spellbook entries looked at, at most.
local SPELLBOOK_LIMIT = 1000

local function nameInLink(link)
    return type(link) == "string" and link:match("%[(.-)%]") or nil
end

--- Every icon that has a name to search by, forms first, then spells, then
-- worn and carried items: { icon, name } each.
local function namedIcons()
    local list = {}
    local function add(icon, name)
        if icon and type(name) == "string" and name ~= "" then
            list[#list + 1] = { icon = icon, name = name }
        end
    end

    if GetNumShapeshiftForms and C_Spell and C_Spell.GetSpellName then
        for index = 1, GetNumShapeshiftForms() do
            local icon, active, _, spellID = GetShapeshiftFormInfo(index)
            -- The form you are in gives the stance bar's "active" glow, not
            -- its icon: ask the spell for its own.
            if spellID and C_Spell.GetSpellTexture then
                icon = C_Spell.GetSpellTexture(spellID) or icon
            elseif active then
                icon = nil
            end
            add(icon, spellID and C_Spell.GetSpellName(spellID))
        end
    end

    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for index = 1, SPELLBOOK_LIMIT do
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, index, bank)
            if not ok or type(info) ~= "table" then
                break
            end
            add(info.iconID, info.name)
        end
    end

    for slot = 1, 19 do
        add(GetInventoryItemTexture("player", slot), nameInLink(GetInventoryItemLink("player", slot)))
    end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                add(info.iconFileID, nameInLink(info.hyperlink))
            end
        end
    end
    return list
end

--- The icons whose name holds `text`, any case, each once.
function IconSearch.Find(text)
    local query = text:lower()
    local seen, icons = {}, {}
    for _, entry in ipairs(namedIcons()) do
        if not seen[entry.icon] and entry.name:lower():find(query, 1, true) then
            seen[entry.icon] = true
            icons[#icons + 1] = entry.icon
        end
    end
    return icons
end

--- Fill the grid: the icons found for `text`, or the game's list when it is
-- empty. The set's current icon stays marked when it is listed.
local function fill(popup, text)
    if not popup:IsShown() then
        return -- hidden: the game fills it again when it opens
    end
    local selector = popup.IconSelector
    local icon = popup.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
    if text == "" then
        selector:SetSelectionsDataProvider(
            function(index) return popup:GetIconByIndex(index) end,
            function() return popup:GetNumIcons() end)
        selector:SetSelectedIndex(popup:GetIndexOfIcon(icon))
        return
    end
    local icons = IconSearch.Find(text)
    selector:SetSelectionsArray(icons)
    local marked
    for index, each in ipairs(icons) do
        if each == icon then
            marked = index
            break
        end
    end
    selector:SetSelectedIndex(marked)
end

--- Put the box in the window, once, beside its "Spells / Items" menu.
local function attach()
    local popup = GearManagerPopupFrame
    if IconSearch.box or not (popup and popup.IconSelector and popup.BorderBox
        and popup.BorderBox.SelectedIconArea) then
        return
    end
    local ok, box = pcall(CreateFrame, "EditBox", nil, popup.BorderBox, "SearchBoxTemplate")
    if not (ok and box) then
        return
    end
    box:SetSize(BOX_WIDTH, BOX_HEIGHT)
    box:SetAutoFocus(false) -- the set's name box keeps the cursor
    local menu = popup.BorderBox.IconTypeDropdown
    if menu then
        box:SetPoint("RIGHT", menu, "LEFT", -12, 0)
    else
        box:SetPoint("BOTTOMRIGHT", popup.IconSelector, "TOPRIGHT", -170, 4)
    end
    -- Hooked, not set: SearchBoxTemplate shows and hides its "Search" hint
    -- from its own OnTextChanged.
    box:HookScript("OnTextChanged", function(self)
        fill(popup, self:GetText() or "")
    end)
    popup:HookScript("OnHide", function()
        box:SetText("")
    end)
    IconSearch.box = box
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    attach()
end)
