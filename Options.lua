local _, ns = ...
local L = ns.L

local ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local win, mini

local function build()
    local db = ns.db
    win = ns.UI.Window("ForeverLootKeyOptions", "Forever Loot", 320)
    win:AddCheck(L.UI_ENABLED, ns.IsEnabled, function(v) ns.SetEnabled(v) end)
    win:AddSlider(L.UI_RANGE, ns.MIN_RANGE, ns.MAX_RANGE, 1, function() return db.range end,
        function(v) ns.SetRange(v) end, function(v) return L.UI_YARDS:format(v) end)
    win:AddSlider(L.UI_ICON, ns.MIN_ICON, ns.MAX_ICON, 4, function() return db.iconSize end,
        function(v) ns.SetIconSize(v) end)
    win:AddCheck(L.UI_MAKE_ROOM, function() return db.makeRoom end,
        function(v) db.makeRoom = v or nil end, ns.IsEnabled)
    win:AddCheck(L.UI_MINIMAP, function() return not db.minimapHide end,
        function(v) db.minimapHide = not v; mini:UpdateShown() end)
    win:AddButtons({ { L.UI_WHO, ns.PrintWho } })
    win:Finish()
end

function ns.ToggleOptions()
    if not win then build() end
    win:Toggle()
end

function ns.InitOptions()
    if mini then return end
    mini = ns.UI.MinimapButton({
        name = "ForeverLootKeyMinimapButton",
        icon = ICON,
        db = ns.db,
        angle = 235,
        title = "Forever Loot",
        lines = function() return { L.UI_TIP_LEFT, L.UI_TIP_RIGHT, L.UI_TIP_DRAG } end,
        onLeft = ns.ToggleOptions,
        onRight = ns.PrintWho,
    })
end

function ForeverLootKey_OnAddonCompartmentClick()
    ns.ToggleOptions()
end
