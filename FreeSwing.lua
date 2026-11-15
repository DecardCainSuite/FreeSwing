-- Free Swing Timer - core
-- Swing timers for main hand, off hand and ranged (Blizzard's PLAYER_SWING event).
-- Own frames only: no Blizzard frame is touched.

local ADDON, ns = ...

local OUT_OF_RANGE_ALPHA = 0.4
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

ns.BAR_KEYS = { "MH", "OH", "RG" }
local BAR_KEYS = ns.BAR_KEYS

local BAR_INFO = {
    MH = { label = "Main Hand", swingType = 0, slot = 16, atlas = "ui-swingtimerbar-filling-mainhand", y = 417,
           color = { 0.96, 0.76, 0.32 }, visibility = "combat" },
    OH = { label = "Off Hand",  swingType = 1, slot = 17, atlas = "ui-swingtimerbar-filling-offhand",  y = 442,
           color = { 0.42, 0.74, 1.00 }, visibility = "combat" },
    RG = { label = "Ranged",    swingType = 2, slot = 18, atlas = "ui-swingtimerbar-filling-ranged",   y = 467,
           color = { 0.52, 0.88, 0.42 }, visibility = "active" },
}
ns.BAR_INFO = BAR_INFO
if Enum and Enum.PlayerSwingType then
    BAR_INFO.MH.swingType = Enum.PlayerSwingType.MainHand
    BAR_INFO.OH.swingType = Enum.PlayerSwingType.OffHand
    BAR_INFO.RG.swingType = Enum.PlayerSwingType.Ranged
end

-- Built-in textures (+ every LibSharedMedia "statusbar" texture installed by other addons)
ns.BUILTIN_TEXTURES = {
    { key = "blizzard", label = "Blizzard swing" },
    { key = "flat",     label = "Flat",     path = "Interface\\Buttons\\WHITE8x8" },
    { key = "smooth",   label = "Smooth",   path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "raid",     label = "Raid",     path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "glass",    label = "Glass",    path = MEDIA .. "bar-glass" },
    { key = "stripe",   label = "Stripes",  path = MEDIA .. "bar-stripe" },
}

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

function ns.TextureList()
    local list = {}
    for _, t in ipairs(ns.BUILTIN_TEXTURES) do list[#list + 1] = t end
    local lsm = LSM()
    if lsm then
        local names = lsm:List("statusbar")
        for _, name in ipairs(names or {}) do
            list[#list + 1] = { key = "lsm:" .. name, label = name, path = lsm:Fetch("statusbar", name) }
        end
    end
    return list
end

function ns.TexturePath(key)
    for _, t in ipairs(ns.BUILTIN_TEXTURES) do
        if t.key == key then return t.path end
    end
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = LSM()
        if lsm then return lsm:Fetch("statusbar", key:sub(5), true) end
    end
    return nil
end

local function Defaults(key)
    local info = BAR_INFO[key]
    return {
        point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = info.y,
        width = 260, height = 18, scale = 1, alpha = 1,
        visibility = info.visibility,     -- always | combat | active | hidden
        texture = "blizzard",
        color = { info.color[1], info.color[2], info.color[3] },
        tint = info.tint or false,         -- tint the Blizzard texture with the bar colour
        classColor = false,
        reverse = false,
        spark = true,
        background = "blizzard",           -- blizzard | solid | none
        bgColor = { 0, 0, 0, 0.55 },
        border = "blizzard",               -- blizzard | thin | none
        borderColor = { 0, 0, 0, 1 },
        showName = true, name = "",
        showTime = true, timeFormat = "remaining", decimals = 1,   -- remaining | elapsed | both
        font = "ARIALN",                   -- LibFreeMedia key (ARIALN, FRIZQT, PTSANS...)
        fontSize = 0, outline = "NONE",    -- size (0 = automatic) | NONE (shadow) | OUTLINE | THICKOUTLINE
        showIcon = false, iconSide = "LEFT",
        rangeDim = true,
    }
end
ns.Defaults = Defaults

local db
local bars = {}
local unlocked, inCombat = false, false

-- ------------------------------------------------------------ helpers
local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffff8a3dFree Swing|r: " .. msg) end
ns.Print = Print

local function FillDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                local c = {}; for i, x in pairs(v) do c[i] = x end; dst[k] = c
            else
                dst[k] = v
            end
        end
    end
end

local function AttackSpeeds() return UnitAttackSpeed("player") end

local function ClassColor()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Optional shared libraries (listed in FreeSwing.toc before this file; nil-safe)
local function GetLib(name) return LibStub and LibStub(name, true) end

-- Bar text: font (LibFreeMedia key c.font), size, and outline / shadow (c.outline)
local function StyleText(fs, c, size)
    local LFM = GetLib("LibFreeMedia-1.0")
    if LFM then
        LFM:SetFont(fs, c.font or "ARIALN", size, c.outline or "NONE")
        LFM:ApplyOutline(fs, c.outline or "NONE")
    else
        local flags = (c.outline ~= "NONE") and c.outline or ""
        fs:SetFont(GameFontHighlightSmall:GetFont(), size, flags)
    end
end

-- ------------------------------------------------------------ bar object
-- A bar renders a config table. Real bars use db.bars[key]; the config window
-- creates a preview bar whose config is the currently selected bar.
local Bar = {}

function Bar:Config() return self.getConfig() end

function Bar:Label()
    local c = self:Config()
    if c.name and c.name ~= "" then return c.name end
    return self.info.label
end

function Bar:HasWeapon()
    if self.isPreview or self.key == "MH" then return true end
    local _, oh, rg = AttackSpeeds()
    local v = (self.key == "OH") and oh or rg
    if IsSecret(v) then return true end
    return v ~= nil and v > 0
end

function Bar:ShouldShow()
    if self.isPreview then return true end
    if unlocked then return true end
    local c = self:Config()
    if c.visibility == "hidden" or not self:HasWeapon() then return false end
    if c.visibility == "always" then return true end
    if c.visibility == "active" then return self.swingEnd ~= nil end
    return inCombat or self.swingEnd ~= nil
end

function Bar:UpdateShown()
    self:SetShown(self:ShouldShow())
    self:ApplyRange()
end

function Bar:ApplyStyle()
    local c = self:Config()
    local info = self.info

    if not self.isPreview then
        self:SetScale(c.scale)
        self:ClearAllPoints()
        self:SetPoint(c.point, UIParent, c.relPoint, c.x, c.y)
        self:SetAlpha(c.alpha)
    end
    self:SetSize(c.width, c.height)

    -- background
    self.BgAtlas:SetShown(c.background == "blizzard")
    self.BgSolid:SetShown(c.background == "solid")
    self.BgSolid:SetVertexColor(c.bgColor[1], c.bgColor[2], c.bgColor[3], c.bgColor[4] or 1)

    -- border
    self.BorderAtlas:SetShown(c.border == "blizzard")
    for _, e in ipairs(self.BorderThin) do
        e:SetShown(c.border == "thin")
        e:SetVertexColor(c.borderColor[1], c.borderColor[2], c.borderColor[3], c.borderColor[4] or 1)
    end

    -- icon
    local iconSize = c.height
    self.Icon:SetShown(c.showIcon)
    self.Icon:SetSize(iconSize, iconSize)
    self.Icon:ClearAllPoints()
    if c.iconSide == "RIGHT" then
        self.Icon:SetPoint("LEFT", self, "RIGHT", 2, 0)
    else
        self.Icon:SetPoint("RIGHT", self, "LEFT", -2, 0)
    end
    self:UpdateIcon()

    -- bar inset: only the Blizzard frame art needs room
    local ix, iy = 0, 0
    if c.border == "blizzard" then
        ix = math.min(5, c.width * 0.02)
        iy = math.min(4, c.height * 0.2)
    elseif c.border == "thin" then
        ix, iy = 1, 1
    end
    self.Bar:ClearAllPoints()
    self.Bar:SetPoint("TOPLEFT", ix, -iy)
    self.Bar:SetPoint("BOTTOMRIGHT", -ix, iy)

    -- texture and colour
    if c.texture == "blizzard" then
        self.Bar:SetStatusBarTexture(info.atlas)
    else
        self.Bar:SetStatusBarTexture(ns.TexturePath(c.texture) or "Interface\\Buttons\\WHITE8x8")
    end
    local r, g, b = c.color[1], c.color[2], c.color[3]
    if c.classColor then r, g, b = ClassColor() end
    if c.texture == "blizzard" and not c.tint and not c.classColor then r, g, b = 1, 1, 1 end
    self.Bar:SetStatusBarColor(r, g, b, 1)
    if self.Bar.SetReverseFill then self.Bar:SetReverseFill(c.reverse) end

    -- spark
    local barH = math.max(1, c.height - 2 * iy)
    self.Spark:ClearAllPoints()
    self.Spark:SetPoint(c.reverse and "LEFT" or "RIGHT", self.Bar:GetStatusBarTexture(), c.reverse and "LEFT" or "RIGHT", 0, 0)
    local pw, ph = 6, 20
    self.Spark:SetSize(pw * barH / ph, barH)

    -- texts
    local size = c.fontSize
    if not size or size <= 0 then size = math.max(6, math.min(c.height * 0.6, 24)) end
    StyleText(self.Title, c, size)
    StyleText(self.Time, c, size)
    local pad = math.min(8, c.width * 0.03)
    self.Title:ClearAllPoints(); self.Time:ClearAllPoints()
    if c.reverse then
        self.Title:SetPoint("RIGHT", self.Bar, "RIGHT", -pad, 0); self.Title:SetJustifyH("RIGHT")
        self.Time:SetPoint("LEFT", self.Bar, "LEFT", pad, 0);     self.Time:SetJustifyH("LEFT")
    else
        self.Title:SetPoint("LEFT", self.Bar, "LEFT", pad, 0);    self.Title:SetJustifyH("LEFT")
        self.Time:SetPoint("RIGHT", self.Bar, "RIGHT", -pad, 0);  self.Time:SetJustifyH("RIGHT")
    end
    self.Title:SetText(self:Label())
    self.Title:SetShown(c.showName)
    self.Time:SetShown(c.showTime)

    if self.Handle then self.Handle:SetShown(unlocked) end
    self:UpdateSpark()
    self:UpdateShown()
end

function Bar:UpdateIcon()
    local c = self:Config()
    if not c.showIcon then return end
    local tex = GetInventoryItemTexture("player", self.info.slot)
    self.Icon:SetTexture(tex or 134400)   -- 134400 = question mark icon
    self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

function Bar:FormatTime(remaining, duration)
    local c = self:Config()
    local fmt = "%." .. (c.decimals or 1) .. "f"
    if c.timeFormat == "elapsed" then
        return string.format(fmt, duration - remaining)
    elseif c.timeFormat == "both" then
        return string.format(fmt .. " / " .. fmt, remaining, duration)
    end
    return string.format(fmt, remaining)
end

function Bar:UpdateSpark()
    local c = self:Config()
    local v = self.Bar:GetValue()
    self.Spark:SetShown(c.spark and v > 0 and v < 1)
end

function Bar:IsOutOfRange()
    if unlocked or self.isPreview or self.swingEnd or not self:Config().rangeDim then return false end
    return self.outOfRange == true
end

function Bar:ApplyRange()
    local out = self:IsOutOfRange()
    local a = out and OUT_OF_RANGE_ALPHA or 1
    self.Bar:SetAlpha(a)
    self.BgAtlas:SetAlpha(a); self.BorderAtlas:SetAlpha(a)
    local r, g, b = 1, 1, 1
    if out then r, g, b = 1, 0.15, 0.15 end
    self.Title:SetTextColor(r, g, b); self.Time:SetTextColor(r, g, b)
end

function Bar:UpdateRange()
    if self.isPreview then return end
    local ok, inRange = false, nil
    if C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange then
        ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, self.info.swingType)
    end
    if not ok or IsSecret(inRange) then inRange = nil end
    local out = (inRange == false)
    if out ~= self.outOfRange then self.outOfRange = out; self:ApplyRange() end
end

function Bar:Clear()
    self.swingDuration, self.swingEnd = nil, nil
    if not self.isPreview then self:SetScript("OnUpdate", nil) end
    local demo = unlocked and not self.isPreview
    self.Bar:SetValue(demo and 0.6 or 0)
    self.Time:SetText(demo and self:FormatTime(1.2, 3.0) or self:FormatTime(0, 0))
    self:UpdateSpark()
    self:UpdateShown()
end

function Bar:OnSwingUpdate()
    local remaining = self.swingEnd - GetTime()
    if remaining <= 0 then
        if self.isPreview then self:StartSwing(self.swingDuration); return end
        self:Clear(); return
    end
    local v = (self.swingDuration - remaining) / self.swingDuration
    self.Bar:SetValue(v)
    self.Time:SetText(self:FormatTime(remaining, self.swingDuration))
    self:UpdateSpark()
end

function Bar:StartSwing(duration)
    if not duration or IsSecret(duration) or duration <= 0 then return end
    self.swingDuration = duration
    self.swingEnd = GetTime() + duration
    self.Bar:SetValue(0)
    self:SetScript("OnUpdate", self.OnSwingUpdate)
    self:UpdateShown()
end

function Bar:RestartForWeaponChange()
    if not self.swingEnd then return end
    local mh, oh, rg = AttackSpeeds()
    self:StartSwing((self.key == "MH" and mh) or (self.key == "OH" and oh) or rg)
end

-- Save position after dragging, as BOTTOM / BOTTOM offsets in the bar's own scale.
function Bar:SaveGeometry()
    local c = self:Config()
    local s = self:GetScale()
    local cx = self:GetLeft() + self:GetWidth() / 2
    c.point, c.relPoint = "BOTTOM", "BOTTOM"
    c.x = math.floor((cx - UIParent:GetWidth() / (2 * s)) + 0.5)
    c.y = math.floor(self:GetBottom() + 0.5)
    c.width = math.floor(self:GetWidth() + 0.5)
    c.height = math.floor(self:GetHeight() + 0.5)
    self:ApplyStyle()
    if ns.OnChanged then ns.OnChanged() end
end

-- Unlocked drag: snap the bar to the grid and to the other bars (LibFreeGrid), in UIParent units.
local function SnapToGrid(f)
    if not (ns.grid and unlocked) then return end
    local l, b = f:GetLeft(), f:GetBottom()
    if not (l and b) then return end
    local s = f:GetScale() or 1
    local others = {}
    for _, key in ipairs(BAR_KEYS) do
        local o = bars[key]
        if o ~= f and o:IsShown() and o:GetLeft() and o:GetBottom() then
            local os = o:GetScale() or 1
            others[#others + 1] = { l = o:GetLeft(), b = o:GetBottom(), w = o:GetWidth() * os, h = o:GetHeight() * os }
        end
    end
    local nl, nb = ns.grid:Snap(l, b, f:GetWidth() * s, f:GetHeight() * s, others)
    if nl and nb and (nl ~= l or nb ~= b) then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nl, nb)
    end
end

local function CreateBar(key, parent, getConfig, isPreview)
    local info = BAR_INFO[key]
    local f = CreateFrame("Frame", (not isPreview) and ("FreeSwingBar" .. key) or nil, parent or UIParent)
    Mixin(f, Bar)
    f.key, f.info, f.getConfig, f.isPreview = key, info, getConfig, isPreview

    f.BgAtlas = f:CreateTexture(nil, "BACKGROUND"); f.BgAtlas:SetAtlas("ui-swingtimerbar-background"); f.BgAtlas:SetAllPoints()
    f.BgSolid = f:CreateTexture(nil, "BACKGROUND", nil, 1); f.BgSolid:SetTexture("Interface\\Buttons\\WHITE8x8"); f.BgSolid:SetAllPoints()

    f.Bar = CreateFrame("StatusBar", nil, f)
    f.Bar:SetMinMaxValues(0, 1)
    f.Bar:SetValue(0)
    f.Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

    -- art above the fill
    local art = CreateFrame("Frame", nil, f)
    art:SetAllPoints()
    art:SetFrameLevel(f.Bar:GetFrameLevel() + 2)
    f.BorderAtlas = art:CreateTexture(nil, "BORDER"); f.BorderAtlas:SetAtlas("ui-swingtimerbar-frame"); f.BorderAtlas:SetAllPoints()
    f.BorderThin = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                           { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local e = art:CreateTexture(nil, "BORDER")
        e:SetTexture("Interface\\Buttons\\WHITE8x8")
        e:SetPoint(pts[1]); e:SetPoint(pts[2])
        if pts[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
        f.BorderThin[i] = e
    end
    f.Spark = art:CreateTexture(nil, "OVERLAY")
    f.Spark:SetAtlas("ui-swingtimerbar-pip")
    f.Spark:SetBlendMode("ADD")
    f.Title = art:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.Time = art:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.Icon = art:CreateTexture(nil, "ARTWORK")

    if not isPreview then
        f:SetFrameStrata("MEDIUM")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:SetResizable(true)
        if f.SetResizeBounds then f:SetResizeBounds(1, 1) end
        if f.SetDontSavePosition then f:SetDontSavePosition(true) end
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SnapToGrid(self); self:SaveGeometry() end)

        f.Handle = CreateFrame("Frame", nil, f)
        f.Handle:SetAllPoints()
        f.Handle:SetFrameLevel(art:GetFrameLevel() + 2)
        local hl = f.Handle:CreateTexture(nil, "OVERLAY"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.54, 0.24, 0.22)
        local tag = f.Handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tag:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
        f.Handle.tag = tag
        local grip = CreateFrame("Button", nil, f.Handle)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", 2, -2)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); f:SaveGeometry() end)
        f:SetScript("OnSizeChanged", function(self, w, h)
            if unlocked then self.Handle.tag:SetFormattedText("%s  %d x %d", self:Label(), w, h) end
        end)
        bars[key] = f
    end
    return f
end
ns.CreateBar = CreateBar

-- ------------------------------------------------------------ global state
local function ApplyAll()
    for _, key in ipairs(BAR_KEYS) do
        local f = bars[key]
        f:EnableMouse(unlocked)
        f:ApplyStyle()
        if not f.swingEnd then f:Clear() end
        local c = f:Config()
        f.Handle.tag:SetFormattedText("%s  %d x %d", f:Label(), c.width, c.height)
    end
    if ns.OnStyleChanged then ns.OnStyleChanged() end
end
ns.ApplyAll = ApplyAll

local function RangeTick()
    for _, key in ipairs(BAR_KEYS) do
        local f = bars[key]
        if f:IsShown() then f:UpdateRange() end
    end
end

ns.GetDB = function() return db end
ns.IsUnlocked = function() return unlocked end
ns.SetUnlocked = function(v)
    unlocked = v and true or false
    ApplyAll()
    if ns.gridToolbar then
        if unlocked then ns.gridToolbar:Show() else ns.gridToolbar:Hide() end
    end
    if ns.OnChanged then ns.OnChanged() end
end
ns.Test = function()
    local mh, oh, rg = AttackSpeeds()
    local function ok(v, d) return (not IsSecret(v) and v and v > 0) and v or d end
    bars.MH:StartSwing(ok(mh, 2.4)); bars.OH:StartSwing(ok(oh, 1.8)); bars.RG:StartSwing(ok(rg, 2.8))
    for _, key in ipairs(BAR_KEYS) do bars[key]:Show() end
end
ns.Reset = function(which)
    for _, key in ipairs(BAR_KEYS) do
        if which == "all" or which == key then db.bars[key] = Defaults(key) end
    end
    ApplyAll()
    if ns.OnChanged then ns.OnChanged() end
end
-- Copy the style of one bar to the others (position, label and visibility are kept).
ns.CopyStyle = function(from)
    local keep = { point = true, relPoint = true, x = true, y = true, name = true, visibility = true, color = true, tint = true }
    local src = db.bars[from]
    for _, key in ipairs(BAR_KEYS) do
        if key ~= from then
            for k, v in pairs(src) do
                if not keep[k] then
                    if type(v) == "table" then
                        local c = {}; for i, x in pairs(v) do c[i] = x end; db.bars[key][k] = c
                    else
                        db.bars[key][k] = v
                    end
                end
            end
        end
    end
    ApplyAll()
    if ns.OnChanged then ns.OnChanged() end
end

-- Note: no target swing timer. On this client every event that reports hits
-- (COMBAT_LOG_EVENT_UNFILTERED, UNIT_COMBAT) is reserved to the Blizzard UI, and
-- registering them makes the game block the addon.

-- ------------------------------------------------------------ events
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        FreeSwingDB = FreeSwingDB or {}
        db = FreeSwingDB
        -- profiles: the bars of the active profile are reached through db.bars
        db.profiles = db.profiles or {}
        if db.bars and not db.profiles.Default then db.profiles.Default = { bars = db.bars } end
        db.bars = nil
        local function prepare(p)
            p.bars = p.bars or {}
            for _, key in ipairs(BAR_KEYS) do
                p.bars[key] = p.bars[key] or {}
                local c = p.bars[key]
                -- migration from 1.x
                if c.border == true then c.border = "blizzard" elseif c.border == false then c.border = "none" end
                if c.background == true then c.background = "blizzard" elseif c.background == false then c.background = "none" end
                if c.showTitle ~= nil then c.showName = c.showTitle; c.showTitle = nil end
                FillDefaults(c, Defaults(key))
            end
        end
        local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
        if LFP then
            ns.profiles = LFP:New("FreeSwing", db, function(d)
                db.bars = d.bars
                if bars.MH then ApplyAll(); if ns.OnChanged then ns.OnChanged() end end
            end, prepare, nil, { perCharacter = true })
            db.bars = ns.profiles:Data().bars
        else
            db.profiles.Default = db.profiles.Default or {}
            prepare(db.profiles.Default)
            db.bars = db.profiles.Default.bars
        end
        for _, key in ipairs(BAR_KEYS) do
            CreateBar(key, UIParent, function() return db.bars[key] end, false)
        end
        db.minimap = db.minimap or { hide = false }
        -- unlock toolbar: grid, snapping (settings in FreeSwingDB.grid)
        local LFG = GetLib("LibFreeGrid-1.0")
        if LFG then
            db.grid = db.grid or {}
            ns.grid = LFG:Attach(db.grid)
            ns.gridToolbar = ns.grid:Toolbar(db.grid, nil, function() ns.SetUnlocked(false) end, "Free Swing")
        end
        self:UnregisterEvent("ADDON_LOADED")
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                             "PLAYER_TARGET_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do
            self:RegisterEvent(e)
        end
        self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
        self:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
        pcall(self.RegisterEvent, self, "PLAYER_SWING")
        C_Timer.NewTicker(0.2, RangeTick)
        ApplyAll()
    elseif event == "PLAYER_SWING" then
        local duration, swingType = ...
        for _, key in ipairs({ "MH", "OH", "RG" }) do
            local f = bars[key]
            if f.info.swingType == swingType and f:Config().visibility ~= "hidden" then f:StartSwing(duration) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" and ns.profiles and not ns.profileReady then
            -- the character name is surely known now: use this character's profile
            ns.profileReady = true
            ns.profiles:Activate()
        end
        if event == "PLAYER_ENTERING_WORLD" then
            -- positions saved with another anchor (1.x drag) are converted once to bottom-centre offsets
            for _, key in ipairs(BAR_KEYS) do
                local c = db.bars[key]
                if (c.point ~= "BOTTOM" or c.relPoint ~= "BOTTOM") and bars[key]:GetLeft() then
                    bars[key]:SaveGeometry()
                end
            end
        end
        inCombat = (event == "PLAYER_REGEN_DISABLED") or (UnitAffectingCombat("player") and true or false)
        for _, key in ipairs(BAR_KEYS) do bars[key]:UpdateShown() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        RangeTick()
    else -- inventory / attack speed / equipment
        for _, key in ipairs(BAR_KEYS) do
            local f = bars[key]
            f:UpdateIcon()
            f:UpdateShown()
            if event == "UNIT_INVENTORY_CHANGED" then f:RestartForWeaponChange() end
        end
    end
end)

-- ------------------------------------------------------------ slash commands
local ALIASES = { mh = "MH", main = "MH", oh = "OH", off = "OH", rg = "RG", ranged = "RG" }

local function Help()
    Print("commands:")
    print("  /swing            open / close the options window")
    print("  /swing unlock | lock   move and resize the bars with the mouse")
    print("  /swing test       simulate a swing on every bar")
    print("  /swing minimap    show / hide the minimap button")
    print("  /swing reset [mh|oh|rg|all]")
    print("  /swing <bar> width|height|scale <n>    (bar = mh, oh, rg, all)")
end

SLASH_FREESWING1 = "/swing"
SLASH_FREESWING2 = "/freeswing"
SlashCmdList.FREESWING = function(msg)
    local args = {}
    for w in (msg or ""):lower():gmatch("%S+") do args[#args + 1] = w end
    local cmd = args[1]
    if not cmd or cmd == "config" or cmd == "options" then
        if ns.ToggleConfig then ns.ToggleConfig() else Help() end
    elseif cmd == "help" then Help()
    elseif cmd == "unlock" then ns.SetUnlocked(true); Print("unlocked: drag to move, pull the bottom-right corner to resize.")
    elseif cmd == "lock" then ns.SetUnlocked(false); Print("locked.")
    elseif cmd == "test" then ns.Test()
    elseif cmd == "minimap" then if ns.SetMinimapShown then ns.SetMinimapShown(not ns.IsMinimapShown()) end
    elseif cmd == "reset" then
        local which = args[2] and (ALIASES[args[2]] or (args[2] == "all" and "all")) or "all"
        ns.Reset(which); Print("settings reset.")
    else
        local targets = (cmd == "all") and BAR_KEYS or (ALIASES[cmd] and { ALIASES[cmd] })
        local field = ({ width = "width", height = "height", scale = "scale" })[args[2] or ""]
        local n = tonumber(args[3] or "")
        if not targets or not field or not n or n <= 0 then Help(); return end
        for _, key in ipairs(targets) do db.bars[key][field] = n end
        ApplyAll()
        if ns.OnChanged then ns.OnChanged() end
    end
end
