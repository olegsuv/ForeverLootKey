-- Forever LootKey
-- One key loots the nearest corpse or quest object (soft-target interact),
-- instant auto loot, and an icon over nearby interactable objects.
local _, ns = ...
local L = ns.L

local DEFAULT_RANGE = 10
local MIN_RANGE, MAX_RANGE = 3, 30
local DEFAULT_ICON = 64
local MIN_ICON, MAX_ICON = 16, 128

-- Settings the addon manages. Range and icon size come from the saved values.
local function managedSettings(range, iconSize)
    return {
        { "autoLootDefault",          "1" },  -- loot without the loot window
        { "softTargetInteract",       "3" },  -- interact key picks the nearest target (keyboard and gamepad)
        { "SoftTargetIconGameObject", "1" },  -- icon over nearby objects: quest items, herbs, ore, chests
        { "SoftTargetIconInteract",   "1" },  -- icon over the current interact target
        { "SoftTargetInteractArc",    "2" },  -- search all around the character, not only in front
        { "SoftTargetInteractRange",  tostring(range) },
        { "SoftTargetWorldtextSize",  tostring(iconSize) }, -- size of the icon over the target (client default 32)
        { "SoftTargetLowPriorityIcons", "1" }, -- keep the icon even when a quest or loot marker is shown
        { "SoftTargetNameplateInteract", "1" }, -- show the name of the interact target
    }
end

local function say(msg)
    print(L.PREFIX .. msg)
end

local function getCVar(name)
    local ok, value = pcall(GetCVar, name)
    if ok then return value end
end

local function setCVar(name, value)
    local ok = pcall(SetCVar, name, value)
    return ok and getCVar(name) ~= nil
end

local db

local function apply()
    local list = managedSettings(db.range, db.iconSize)
    db.previous = db.previous or {}
    local done = 0
    for _, kv in ipairs(list) do
        local name, value = kv[1], kv[2]
        if db.previous[name] == nil then
            db.previous[name] = getCVar(name) or false -- remember the player's own value once
        end
        if setCVar(name, value) then done = done + 1 end
    end
    db.applied = true
    return done, #list
end

local function restore()
    if not db.previous or not next(db.previous) then
        say(L.NOTHING_TO_RESTORE)
        return
    end
    for name, value in pairs(db.previous) do
        if value ~= false then setCVar(name, value) end
    end
    db.previous = nil
    db.applied = false
    db.disabledByUser = true
    say(L.RESTORED)
end

local function describeInteractTarget()
    local ok, exists = pcall(UnitExists, "softinteract")
    if not ok then return L.NOT_SUPPORTED end
    if not exists then return L.NONE end
    local _, name = pcall(UnitName, "softinteract")
    local _, dead = pcall(UnitIsDead, "softinteract")
    return tostring(name or "?") .. (dead and L.CORPSE or "")
end

local function printHelp()
    for i, line in ipairs(L.HELP) do
        if i == 4 then line = line:format(MIN_RANGE, MAX_RANGE, DEFAULT_RANGE) end
        if i == 5 then line = line:format(MIN_ICON, MAX_ICON, DEFAULT_ICON) end
        print("  " .. line)
    end
end

-- Actions shared by the slash commands and the settings window
function ns.IsEnabled()
    return db and not db.disabledByUser
end

function ns.SetEnabled(on)
    if on then
        db.disabledByUser = nil
        say(L.APPLIED:format(apply()))
    else
        restore()
    end
end

function ns.SetRange(n)
    db.range = math.floor(n)
    if db.applied then setCVar("SoftTargetInteractRange", tostring(db.range)) end
end

function ns.SetIconSize(n)
    db.iconSize = math.floor(n)
    if db.applied then setCVar("SoftTargetWorldtextSize", tostring(db.iconSize)) end
end

function ns.PrintWho()
    say(L.WHO:format(describeInteractTarget(),
        tostring(getCVar("softTargetInteract")),
        tostring(getCVar("SoftTargetInteractRange")),
        getCVar("autoLootDefault") == "1" and L.ON or L.OFF))
end

ns.MIN_RANGE, ns.MAX_RANGE, ns.MIN_ICON, ns.MAX_ICON = MIN_RANGE, MAX_RANGE, MIN_ICON, MAX_ICON

SLASH_FOREVERLOOTKEY1 = "/lootkey"
SLASH_FOREVERLOOTKEY2 = "/flk"
SlashCmdList.FOREVERLOOTKEY = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "on" then
        ns.SetEnabled(true)
    elseif cmd == "off" then
        ns.SetEnabled(false)
    elseif cmd == "range" then
        local n = tonumber(arg)
        if not n or n < MIN_RANGE or n > MAX_RANGE then
            say(L.RANGE_BAD:format(MIN_RANGE, MAX_RANGE))
            return
        end
        ns.SetRange(n)
        say(L.RANGE_SET:format(db.range))
    elseif cmd == "icon" then
        local n = tonumber(arg)
        if not n or n < MIN_ICON or n > MAX_ICON then
            say(L.ICON_BAD:format(MIN_ICON, MAX_ICON))
            return
        end
        ns.SetIconSize(n)
        say(L.ICON_SET:format(db.iconSize))
    elseif cmd == "who" then
        ns.PrintWho()
    elseif cmd == "" or cmd == "config" then
        ns.ToggleOptions()
    else
        printHelp()
    end
end

---------------------------------------------------------------------------
-- Full bags (off by default): throw away the least useful item so the loot fits.
-- Gray junk first (cheapest stack), then food / drink you have plenty of better.
---------------------------------------------------------------------------
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5 -- Consumable > Food & Drink
local PLENTY = 20                        -- better food / drink you carry before the weaker one may go
local MAX_THROWS = 5                     -- per corpse

local function bagSlots()
    return 0, NUM_BAG_SLOTS or 4
end

local function freeSlots()
    local n = 0
    local first, last = bagSlots()
    for bag = first, last do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if free and (family == nil or family == 0) then n = n + free end -- not quivers / soul bags
    end
    return n
end

local function wellFed(bag, slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or type(data) ~= "table" or not data.lines then return false end
    for _, line in ipairs(data.lines) do
        local t = line.leftText and line.leftText:lower()
        if t and (t:find("well fed", 1, true) or t:find("сыт", 1, true)) then return true end
    end
    return false
end

-- the item to throw away: { bag, slot, link, gray, value } or nil
local function findJunk()
    local gray
    local food = {} -- [item spell name: Food / Drink] = { stacks }
    local first, last = bagSlots()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked then
                local _, _, _, ilvl, _, _, _, _, _, _, price, classID, subID = C_Item.GetItemInfo(info.itemID)
                local count = info.stackCount or 1
                local value = (price or 0) * count
                if info.quality == 0 then
                    if not gray or value < gray.value then
                        gray = { bag = bag, slot = slot, link = info.hyperlink, gray = true, value = value }
                    end
                elseif classID == FOOD_CLASS and subID == FOOD_SUBCLASS and ilvl then
                    local spell = C_Item.GetItemSpell(info.itemID)
                    if spell then
                        food[spell] = food[spell] or {}
                        table.insert(food[spell], { bag = bag, slot = slot, link = info.hyperlink,
                            ilvl = ilvl, count = count, value = value })
                    end
                end
            end
        end
    end
    if gray then return gray end

    local pick
    for _, stacks in pairs(food) do
        for _, s in ipairs(stacks) do
            local better = 0
            for _, o in ipairs(stacks) do
                if o.ilvl > s.ilvl then better = better + o.count end
            end
            if better >= PLENTY and not wellFed(s.bag, s.slot)
                and (not pick or s.ilvl < pick.ilvl or (s.ilvl == pick.ilvl and s.count < pick.count)) then
                pick = s
            end
        end
    end
    return pick
end

-- the most wanted item still in the loot window
local function bestLoot()
    local best, bestRank
    for slot = 1, GetNumLootItems() do
        local isItem = LootSlotHasItem(slot)
        if isItem and GetLootSlotType and Enum.LootSlotType then
            isItem = GetLootSlotType(slot) == Enum.LootSlotType.Item
        end
        if isItem then
            local _, _, qty, _, quality, locked, isQuest = GetLootSlotInfo(slot)
            if not locked then
                local link = GetLootSlotLink(slot)
                local price = link and select(11, C_Item.GetItemInfo(link)) or 0
                local value = (price or 0) * (qty or 1)
                local rank = isQuest and math.huge or ((quality or 0) * 1e9 + value)
                if not bestRank or rank > bestRank then
                    best = { slot = slot, link = link, quality = quality or 0, value = value, quest = isQuest }
                    bestRank = rank
                end
            end
        end
    end
    return best
end

local function throwAway(junk)
    if GetCursorInfo() then return false end
    C_Container.PickupContainerItem(junk.bag, junk.slot)
    if GetCursorInfo() ~= "item" then ClearCursor(); return false end
    local ok = pcall(DeleteCursorItem)
    if not ok or GetCursorInfo() then ClearCursor(); return false end
    return true
end

local throws = 0
local function makeRoom()
    if not db.makeRoom or throws >= MAX_THROWS then return end
    if GetNumLootItems() == 0 or freeSlots() > 0 then return end
    local loot = bestLoot()
    if not loot then return end
    local junk = findJunk()
    if not junk then return end
    -- gray loot only pushes out cheaper gray junk
    if not loot.quest and loot.quality == 0 and not (junk.gray and loot.value > junk.value) then return end
    if not throwAway(junk) then return end
    throws = throws + 1
    say(L.THREW_AWAY:format(junk.link or "?", loot.link or "?"))
    C_Timer.After(0.3, function()
        if GetNumLootItems() >= loot.slot and LootSlotHasItem(loot.slot) then LootSlot(loot.slot) end
        C_Timer.After(0.3, makeRoom)
    end)
end

-- Instant loot: take every slot as soon as the loot is ready.
local lastLoot = 0
local function onLootReady(autoLoot)
    local now = GetTime()
    if now - lastLoot < 0.2 then return end
    lastLoot = now
    local wanted = autoLoot
    if wanted == nil then
        wanted = GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")
    end
    if not wanted then return end
    for slot = GetNumLootItems(), 1, -1 do
        LootSlot(slot)
    end
    if db and db.makeRoom then
        throws = 0
        C_Timer.After(0.3, makeRoom) -- whatever did not fit is still in the loot window
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("LOOT_READY")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "LOOT_READY" then
        onLootReady(arg1)
        return
    end
    ForeverLootKeyDB = ForeverLootKeyDB or {}
    db = ForeverLootKeyDB
    db.range = db.range or DEFAULT_RANGE
    db.iconSize = db.iconSize or DEFAULT_ICON
    ns.db = db
    if ns.InitOptions then ns.InitOptions() end
    if db.disabledByUser then return end
    if not db.applied then
        say(L.APPLIED:format(apply()))
    else
        apply() -- keep settings in place after game patches reset them; silent
    end
end)
