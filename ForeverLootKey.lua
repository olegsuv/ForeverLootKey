-- Forever Loot
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

local db  -- account: options
local cdb -- character: the settings you had before the addon (CVars are kept per character)

-- the value to remember as "yours": the current one, unless the addon (on another character)
-- already set it, then the game's default
local function ownValue(name, addonValue)
    local cur = getCVar(name)
    if cur == nil then return false end
    if cur == addonValue and GetCVarDefault then
        local ok, def = pcall(GetCVarDefault, name)
        if ok and def ~= nil then return def end
    end
    return cur
end

local function apply()
    local list = managedSettings(db.range, db.iconSize)
    cdb.previous = cdb.previous or {}
    local done = 0
    for _, kv in ipairs(list) do
        local name, value = kv[1], kv[2]
        if cdb.previous[name] == nil then
            cdb.previous[name] = ownValue(name, value) -- remembered once per character
        end
        if setCVar(name, value) then done = done + 1 end
    end
    cdb.applied = true
    return done, #list
end

local function restore()
    if not cdb.previous or not next(cdb.previous) then
        say(L.NOTHING_TO_RESTORE)
        return
    end
    for name, value in pairs(cdb.previous) do
        if value ~= false then setCVar(name, value) end
    end
    cdb.previous = nil
    cdb.applied = false
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
        if line:find("range <") then line = line:format(MIN_RANGE, MAX_RANGE, DEFAULT_RANGE) end
        if line:find("icon <") then line = line:format(MIN_ICON, MAX_ICON, DEFAULT_ICON) end
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
    if cdb.applied then setCVar("SoftTargetInteractRange", tostring(db.range)) end
end

function ns.SetIconSize(n)
    db.iconSize = math.floor(n)
    if cdb.applied then setCVar("SoftTargetWorldtextSize", tostring(db.iconSize)) end
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
-- Full bags (off by default): make room so the loot fits. Junk (the cheapest gray stack or weaker
-- food / drink) goes on its own; otherwise a list of what could go, for you to pick from.
---------------------------------------------------------------------------
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5 -- Consumable > Food & Drink
local MAX_THROWS = 5                     -- per corpse
local QUEST_CLASS = 12                   -- Quest items
local BIND_ON_PICKUP = 1

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

-- What could go to make room, cheapest stack first: { bag, slot, link, value, junk, ... }.
-- Junk (thrown on its own when the loot is worth it): gray items and food / drink weaker than
-- the best of its kind you carry (the best food, the best drink and Well Fed food stay).
-- One of each kind only (five gray items show as the cheapest one), so the choice stays short.
-- Quest items and things without a vendor price (hearthstone and such) are never offered.
local function candidates()
    local list = {}
    local food = {} -- [item spell name: Food / Drink] = { stacks }
    local first, last = bagSlots()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked then
                local _, _, _, ilvl, _, _, _, _, _, _, price, classID, subID = C_Item.GetItemInfo(info.itemID)
                if not price then
                    -- not in the cache yet: ask for it, the next pass will know
                    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, info.itemID) end
                    local _, _, _, _, _, cls, sub = C_Item.GetItemInfoInstant(info.itemID)
                    classID, subID = classID or cls, subID or sub
                end
                if classID ~= QUEST_CLASS and price and price > 0 then
                    local c = { bag = bag, slot = slot, link = info.hyperlink, ilvl = ilvl, itemID = info.itemID,
                                icon = info.iconFileID, count = info.stackCount, quality = info.quality,
                                value = price * (info.stackCount or 1) }
                    list[#list + 1] = c
                    c.kind = tostring(classID) .. ":" .. tostring(subID)
                    if info.quality == 0 then
                        c.junk = true
                        c.kind = "gray"
                    elseif classID == FOOD_CLASS and subID == FOOD_SUBCLASS and ilvl then
                        local spell = C_Item.GetItemSpell(info.itemID)
                        if spell then
                            c.kind = "food:" .. spell
                            food[spell] = food[spell] or {}
                            table.insert(food[spell], c)
                        end
                    end
                end
            end
        end
    end
    for _, stacks in pairs(food) do
        local best = 0
        for _, s in ipairs(stacks) do best = math.max(best, s.ilvl) end
        for _, s in ipairs(stacks) do
            if s.ilvl < best and not wellFed(s.bag, s.slot) then s.junk = true end
        end
    end
    -- cheapest first (junk first at the same price)
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        return a.junk == true and b.junk ~= true
    end)
    -- one of each kind: the cheapest gray, food, drink, cloth, ... (junk of a kind before the rest)
    local pick, order = {}, {}
    for _, c in ipairs(list) do
        local cur = pick[c.kind]
        if not cur then
            pick[c.kind] = c
            order[#order + 1] = c.kind
        elseif c.junk and not cur.junk then
            pick[c.kind] = c
        end
    end
    local out = {}
    for _, kind in ipairs(order) do out[#out + 1] = pick[kind] end
    table.sort(out, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        return a.junk == true and b.junk ~= true
    end)
    return out
end

-- the most wanted item still in the loot window; must = quest item, green or better
-- (what you won on a roll) or bind on pickup: it gets room whatever the junk is worth
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
                local price, classID, bind
                if link then
                    price, classID, _, bind = select(11, C_Item.GetItemInfo(link))
                    if not price then
                        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, link) end
                        classID = select(6, C_Item.GetItemInfoInstant(link))
                    end
                end
                quality = quality or 0
                local must = isQuest or classID == QUEST_CLASS or quality >= 2 or bind == BIND_ON_PICKUP
                local value = (price or 0) * (qty or 1)
                local rank = (must and 1e12 or 0) + quality * 1e9 + value
                if not bestRank or rank > bestRank then
                    best = { slot = slot, link = link, must = must and true or false, value = value }
                    bestRank = rank
                end
            end
        end
    end
    return best
end

-- short log of make-room decisions (saved, for bug reports)
local function note(msg)
    db.roomLog = db.roomLog or {}
    table.insert(db.roomLog, date("%H:%M:%S ") .. msg)
    while #db.roomLog > 40 do table.remove(db.roomLog, 1) end
end

-- Throw an item away, then done(result): "ok", "busy" (something else on the cursor), "blocked"
-- or "cursor" (from a click: the item waits on the cursor, one click on the ground and the game
-- throws it away itself). Deleting is checked on the bag slot a moment later (the cursor may still
-- show the item while the game deletes it). Once the game has refused (db.deleteBlocked, Forever
-- does), a click only picks the item up.
local function stillThere(c)
    if GetCursorInfo() == "item" then return true end -- waiting on the cursor
    local info = C_Container.GetContainerItemInfo(c.bag, c.slot)
    return info and info.itemID == c.itemID
end

local function throwAway(c, fromClick, done)
    if GetCursorInfo() then
        if not fromClick then done("busy"); return end
        ClearCursor() -- you clicked another row: swap the item on the cursor
    end
    C_Container.PickupContainerItem(c.bag, c.slot)
    if GetCursorInfo() ~= "item" then ClearCursor(); done("busy"); return end
    if db.deleteBlocked then
        if fromClick then done("cursor"); return end
        ClearCursor(); done("blocked"); return
    end
    local ok, err = pcall(DeleteCursorItem)
    if not ok then note("DeleteCursorItem error: " .. tostring(err)) end
    C_Timer.After(0.5, function()
        if not stillThere(c) then done("ok"); return end
        db.deleteBlocked = true
        if fromClick and GetCursorInfo() == "item" then done("cursor"); return end
        ClearCursor()
        done("blocked")
    end)
end

local MAX_ROWS = 5 -- slots in the make-room panel (fewer when the loot window is narrow)
local throws, busyUntil = 0, 0
local makeRoom, panel

-- one make-room pass a moment later, however many events asked for it
local roomPending = false
local function makeRoomSoon(delay)
    if roomPending then return end
    roomPending = true
    C_Timer.After(delay or 0.3, function()
        roomPending = false
        makeRoom()
    end)
end

local function lootAgain(loot)
    if GetNumLootItems() >= loot.slot and LootSlotHasItem(loot.slot) then LootSlot(loot.slot) end
end

local function thrown(c, loot)
    throws = throws + 1
    busyUntil = GetTime() + 0.8
    note("threw " .. tostring(c.link) .. " for " .. tostring(loot.link))
    say(L.THREW_AWAY:format(c.link or "?", loot.link or "?"))
    C_Timer.After(0.3, function()
        lootAgain(loot)
        makeRoomSoon(0.4)
    end)
end

---------------------------------------------------------------------------
-- The panel under the loot window: what you could throw away, in a row of bag slots
-- (icon, quality border, count, vendor price on the slot, the bag tooltip on hover), no wider
-- than the loot window. A click on a slot throws that item away and loots: a click counts as
-- your own action. The "click on the ground" hint goes under the slots so they don't move.
---------------------------------------------------------------------------
local SLOT, GAP, PAD = 36, 5, 10
local MIN_ROWS = 4

local COIN = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t",
}

-- vendor price like the game shows it, the two biggest coins (12g 40s, 3s 15c, 80c)
local function coins(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. COIN.g end
    if s > 0 and #parts < 2 then parts[#parts + 1] = s .. COIN.s end
    if c > 0 and #parts < 2 and g == 0 then parts[#parts + 1] = c .. COIN.c end
    if #parts == 0 then return "0" .. COIN.c end
    return table.concat(parts, " ")
end

local function rowWidth(n)
    return PAD * 2 + n * SLOT + (n - 1) * GAP
end

local function layout()
    local h = 9 + math.ceil(panel.title:GetStringHeight()) + 3 + math.ceil(panel.sub:GetStringHeight()) + 6 + SLOT
    if panel.hint:IsShown() then h = h + 6 + math.ceil(panel.hint:GetStringHeight()) end
    panel:SetHeight(h + PAD)
end

-- the item waiting on the cursor for a click on the ground, or nil
local function setHint(link)
    if link then
        panel.hint:SetText(L.THROW_BY_HAND:format(link))
        panel.hint:Show()
    else
        panel.hint:SetText("")
        panel.hint:Hide()
    end
    layout()
end

local function onSlotClick(b)
    local c, loot = b.item, panel.loot
    if not c then return end
    GameTooltip:Hide()
    throwAway(c, true, function(result)
        note("click: " .. result .. " " .. tostring(c.link))
        if result == "ok" then
            thrown(c, loot)
        elseif result == "cursor" then
            setHint(c.link or "?")
        end
    end)
end

local function createSlot(i)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(SLOT, SLOT)
    b:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", (i - 1) * (SLOT + GAP), -6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.border:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("TOPRIGHT", -2, -2)
    -- price on a dark strip along the bottom of the slot
    b.strip = b:CreateTexture(nil, "OVERLAY")
    b.strip:SetColorTexture(0, 0, 0, 0.7)
    b.strip:SetPoint("BOTTOMLEFT", 2, 2)
    b.strip:SetPoint("BOTTOMRIGHT", -2, 2)
    b.strip:SetHeight(12)
    b.price = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.price:SetPoint("BOTTOM", 0, 3)
    b.price:SetTextColor(1, 1, 1)
    b:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.item.bag, self.item.slot)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", onSlotClick)
    return b
end

local function createPanel()
    local p = CreateFrame("Frame", "ForeverLootKeyRoomPanel", UIParent, "BackdropTemplate")
    p:SetWidth(rowWidth(MAX_ROWS))
    p:SetFrameStrata("DIALOG")
    p:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0, 0, 0, 0.9)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOPLEFT", PAD, -9)
    p.title:SetPoint("RIGHT", -24, 0)
    p.title:SetJustifyH("LEFT")
    p.title:SetText(L.THROW_BUTTON)
    p.sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
    p.sub:SetPoint("RIGHT", -PAD, 0)
    p.sub:SetJustifyH("LEFT")
    p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.hint:SetPoint("TOPLEFT", p.sub, "BOTTOMLEFT", 0, -(6 + SLOT + 6))
    p.hint:SetPoint("RIGHT", -PAD, 0)
    p.hint:SetJustifyH("LEFT")
    p.hint:Hide()
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -2)
    p.slots = {}
    -- the item went back to the bag (right click, Escape): drop the hint
    local elapsed = 0
    p:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed < 0.2 then return end
        elapsed = 0
        if self.hint:IsShown() and GetCursorInfo() ~= "item" then setHint(nil) end
    end)
    p:Hide()
    return p
end

local function showPanel(list, loot)
    panel = panel or createPanel()
    panel.loot = loot
    -- as many slots as fit under the loot window (4 or 5), the panel as wide as the window
    local rows, width = MAX_ROWS, rowWidth(MAX_ROWS)
    local lootShown = LootFrame and LootFrame:IsShown()
    if lootShown then
        local w = LootFrame:GetWidth() or 0
        while rows > MIN_ROWS and rowWidth(rows) > w do rows = rows - 1 end
        width = math.max(rowWidth(rows), w)
    end
    panel:SetWidth(width)
    panel.sub:SetText(L.THROW_FOR:format(loot.link or "?"))
    for i = 1, MAX_ROWS do
        local c = i <= rows and list[i] or nil
        local b = panel.slots[i]
        if c and not b then b = createSlot(i); panel.slots[i] = b end
        if b then
            b.item = c
            if c then
                b.icon:SetTexture(c.icon or 134400)
                local cr, cg, cb = 1, 1, 1
                if c.quality and C_Item.GetItemQualityColor then cr, cg, cb = C_Item.GetItemQualityColor(c.quality) end
                b.border:SetVertexColor(cr, cg, cb)
                b.count:SetText((c.count or 1) > 1 and c.count or "")
                b.price:SetText(coins(c.value))
                b:Show()
            else
                b:Hide()
            end
        end
    end
    if GetCursorInfo() == "item" then
        local _, _, link = GetCursorInfo()
        setHint(link or "?")
    else
        setHint(nil)
    end
    panel:ClearAllPoints()
    if lootShown then
        panel:SetPoint("TOPLEFT", LootFrame, "BOTTOMLEFT", 0, -6)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
    panel:Show()
end

makeRoom = function()
    if not db.makeRoom or GetTime() < busyUntil then return end
    if GetNumLootItems() == 0 or freeSlots() > 0 then
        if panel then panel:Hide() end
        return
    end
    local loot = bestLoot()
    if not loot then return end
    local list = candidates()
    if not loot.must then
        -- gray / white loot: only things worth less than it are worth throwing away for it
        local cheaper = {}
        for _, c in ipairs(list) do
            if c.value < loot.value then cheaper[#cheaper + 1] = c end
        end
        list = cheaper
    end
    if #list == 0 then
        note("full, nothing cheaper to offer for " .. tostring(loot.link))
        if panel then panel:Hide() end
        if loot.must then say(L.NO_JUNK) end
        return
    end
    -- on its own only junk goes (the cheapest), and only for loot worth more (quest, rolled and
    -- green+ always)
    local junk
    for _, c in ipairs(list) do
        if c.junk then junk = c; break end
    end
    local auto = junk and not db.deleteBlocked and throws < MAX_THROWS and (loot.must or loot.value > junk.value)
    if not auto then
        note("full, offered " .. #list .. " for " .. tostring(loot.link))
        showPanel(list, loot)
        return
    end
    busyUntil = GetTime() + 1
    throwAway(junk, false, function(result)
        note("auto: " .. result .. " " .. tostring(junk.link))
        if result == "ok" then thrown(junk, loot); return end
        busyUntil = 0
        if GetNumLootItems() > 0 then showPanel(candidates(), loot) end
    end)
end

-- Instant loot: take every slot as soon as the loot is ready.
local lastLoot, lastKey = 0, nil
local function lootKey()
    local n = GetNumLootItems()
    local guid
    if GetLootSourceInfo then
        local ok, g = pcall(GetLootSourceInfo, 1)
        if ok then guid = g end
    end
    return tostring(guid) .. ":" .. n
end

local function onLootReady(autoLoot)
    local now = GetTime()
    local key = lootKey()
    if key == lastKey and now - lastLoot < 0.5 then return end -- the same loot, fired again
    lastLoot, lastKey = now, key
    local wanted = autoLoot
    if wanted == nil then
        wanted = GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")
    end
    if wanted then
        for slot = GetNumLootItems(), 1, -1 do
            LootSlot(slot)
        end
    end
    if db and db.makeRoom and now >= busyUntil then
        throws = 0
        makeRoomSoon(0.3) -- whatever did not fit is still in the loot window
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("LOOT_BIND_CONFIRM")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "LOOT_READY" then
        onLootReady(arg1)
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        -- bags changed with the loot window open: a slot freed (you threw something on the
        -- ground) takes the best loot left, then the list shows again if more is waiting
        if db and db.makeRoom and GetNumLootItems() > 0 then
            if freeSlots() > 0 and GetTime() >= busyUntil then
                local loot = bestLoot()
                if loot then
                    note("room made, looting " .. tostring(loot.link))
                    lootAgain(loot)
                end
            end
            makeRoomSoon(0.3)
        end
        return
    elseif event == "LOOT_BIND_CONFIRM" then
        -- bind-on-pickup loot asks "are you sure?": with auto loot on, yes
        if arg1 and GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
            pcall(ConfirmLootSlot, arg1)
            if StaticPopup_Hide then StaticPopup_Hide("LOOT_BIND") end
        end
        return
    elseif event == "LOOT_CLOSED" then
        if panel then panel:Hide() end
        return
    end
    ForeverLootKeyDB = ForeverLootKeyDB or {}
    db = ForeverLootKeyDB
    db.range = db.range or DEFAULT_RANGE
    db.iconSize = db.iconSize or DEFAULT_ICON
    ForeverLootKeyCharDB = ForeverLootKeyCharDB or {}
    cdb = ForeverLootKeyCharDB
    if db.previous and not cdb.previous then -- 1.3.2: the snapshot moves to the character
        cdb.previous, cdb.applied = db.previous, db.applied
    end
    db.previous, db.applied = nil, nil
    if db.deleteBlocked == nil then db.deleteBlocked = true end -- Forever: addons can't delete items
    ns.db = db
    if ns.InitOptions then ns.InitOptions() end
    if db.disabledByUser then return end
    if not cdb.applied then
        say(L.APPLIED:format(apply()))
    else
        apply() -- keep settings in place after game patches reset them; silent
    end
end)
