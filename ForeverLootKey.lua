-- Forever LootKey
-- One key loots the nearest corpse or quest object (soft-target interact),
-- instant auto loot, and an icon over nearby interactable objects.
local _, ns = ...
local L = ns.L

local DEFAULT_RANGE = 10
local MIN_RANGE, MAX_RANGE = 3, 30

-- Settings the addon manages. Range is filled from the saved value.
local function managedSettings(range)
    return {
        { "autoLootDefault",          "1" },  -- loot without the loot window
        { "softTargetInteract",       "3" },  -- interact key picks the nearest target (keyboard and gamepad)
        { "SoftTargetIconGameObject", "1" },  -- icon over nearby objects: quest items, herbs, ore, chests
        { "SoftTargetIconInteract",   "1" },  -- icon over the current interact target
        { "SoftTargetInteractArc",    "2" },  -- search all around the character, not only in front
        { "SoftTargetInteractRange",  tostring(range) },
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
    local list = managedSettings(db.range)
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
        if i == 3 then line = line:format(MIN_RANGE, MAX_RANGE, DEFAULT_RANGE) end
        print("  " .. line)
    end
end

SLASH_FOREVERLOOTKEY1 = "/lootkey"
SLASH_FOREVERLOOTKEY2 = "/flk"
SlashCmdList.FOREVERLOOTKEY = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "on" then
        db.disabledByUser = nil
        say(L.APPLIED:format(apply()))
    elseif cmd == "off" then
        restore()
    elseif cmd == "range" then
        local n = tonumber(arg)
        if not n or n < MIN_RANGE or n > MAX_RANGE then
            say(L.RANGE_BAD:format(MIN_RANGE, MAX_RANGE))
            return
        end
        db.range = math.floor(n)
        if db.applied then setCVar("SoftTargetInteractRange", tostring(db.range)) end
        say(L.RANGE_SET:format(db.range))
    elseif cmd == "who" then
        say(L.WHO:format(describeInteractTarget(),
            tostring(getCVar("softTargetInteract")),
            tostring(getCVar("SoftTargetInteractRange")),
            getCVar("autoLootDefault") == "1" and L.ON or L.OFF))
    else
        printHelp()
    end
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
    if db.disabledByUser then return end
    if not db.applied then
        say(L.APPLIED:format(apply()))
    else
        apply() -- keep settings in place after game patches reset them; silent
    end
end)
