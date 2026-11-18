-- Small UI kit shared by the Forever addons: a minimap button that sits on the
-- minimap edge (drag to move) and a simple options window.
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local function tryFrame(kind, name, parent, template)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f end
    return CreateFrame(kind, name, parent)
end

---------------------------------------------------------------------------
-- Minimap button
-- opts = { name, icon, db, angle, title, lines = function() return {...} end,
--          onLeft = fn, onRight = fn }
---------------------------------------------------------------------------
function UI.MinimapButton(opts)
    local db = opts.db
    db.minimapAngle = db.minimapAngle or opts.angle or 200

    local b = CreateFrame("Button", opts.name, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(opts.icon)
    icon:SetPoint("TOPLEFT", 7, -6)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    local function place()
        local a = math.rad(db.minimapAngle)
        local r = (Minimap:GetWidth() / 2) + 5
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end

    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            db.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
            place()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" and opts.onRight then opts.onRight() elseif opts.onLeft then opts.onLeft() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddDoubleLine(opts.title, "v" .. UI.Version(), nil, nil, nil, 0.6, 0.6, 0.6)
        if opts.lines then
            for _, line in ipairs(opts.lines()) do GameTooltip:AddLine(line, 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function b:UpdateShown()
        if db.minimapHide then self:Hide() else self:Show(); place() end
    end
    b:UpdateShown()
    return b
end

-- the loaded version from the TOC ("dev" for an unpackaged copy)
function UI.Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get(ADDON, "Version")
    if not v or v == "" or v:find("@", 1, true) then return "dev" end
    return v
end

---------------------------------------------------------------------------
-- Options window
---------------------------------------------------------------------------
local Window = {}

function UI.Window(name, title, width)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
        -- template missing in this client: plain dialog look
        f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    f:SetSize(width or 340, 100)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, name) -- Esc closes it

    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOP", 0, -6)
    t:SetText(title)

    local v = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    v:SetPoint("BOTTOMRIGHT", -14, 10)
    v:SetText("v" .. UI.Version())
    f.versionText = v

    f.y = -34
    f.width = width or 340
    f.controls = {}
    for k, v in pairs(Window) do f[k] = v end
    f:SetScript("OnShow", function(self) self:Refresh() end)
    return f
end

function Window:Refresh()
    for _, c in ipairs(self.controls) do c:Refresh() end
end

function Window:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

function Window:AddHeader(text)
    local h = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", 16, self.y - 4)
    h:SetText(text)
    self.y = self.y - 24
end

-- get() -> bool, set(bool); enabled() optional -> bool (greys out)
function Window:AddCheck(label, get, set, enabled)
    local cb = tryFrame("CheckButton", nil, self, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 16, self.y)
    for _, k in ipairs({ "Text", "text" }) do
        local r = rawget(cb, k)
        if type(r) == "table" and r.SetText then r:SetText("") end
    end
    local txt = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    txt:SetText(label)
    cb:SetScript("OnClick", function(btn)
        set(btn:GetChecked() and true or false)
        self:Refresh()
    end)
    function cb.Refresh()
        cb:SetChecked(get() and true or false)
        local on = not enabled or enabled()
        cb:SetEnabled(on)
        txt:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
    end
    self.controls[#self.controls + 1] = cb
    self.y = self.y - 26
    return cb
end

-- numeric slider; fmt(value) -> string
function Window:AddSlider(label, min, max, step, get, set, fmt)
    fmt = fmt or function(v) return tostring(v) end
    local title = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 22, self.y)
    title:SetText(label)
    local value = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("TOPRIGHT", -22, self.y)

    local s = tryFrame("Slider", nil, self, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(self.width - 44, 16)
    s:SetPoint("TOPLEFT", 22, self.y - 16)
    if s.SetBackdrop then
        s:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(sl, delta)
        sl:SetValue(math.max(min, math.min(max, sl:GetValue() + delta * step)))
    end)
    s:SetScript("OnValueChanged", function(sl, v)
        v = math.floor(v / step + 0.5) * step
        value:SetText(fmt(v))
        if not sl.updating then set(v) end
    end)
    function s.Refresh()
        s.updating = true
        s:SetValue(get())
        value:SetText(fmt(get()))
        s.updating = false
    end
    self.controls[#self.controls + 1] = s
    self.y = self.y - 42
    return s
end

-- one or two buttons in a row: AddButtons({ {label, fn}, {label, fn} })
function Window:AddButtons(list)
    local w = (self.width - 32 - (#list - 1) * 8) / #list
    for i, item in ipairs(list) do
        local b = tryFrame("Button", nil, self, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", 16 + (i - 1) * (w + 8), self.y)
        b:SetText(item[1])
        b:SetScript("OnClick", item[2])
    end
    self.y = self.y - 30
end

function Window:Finish()
    self:SetHeight(-self.y + 26) -- room for the version line
end
