-- Free Swing Timer - options window (/swing)
-- Graphite + ember. Game fonts only. Own frames only (no Blizzard frame is modified).

local ADDON, ns = ...

local MEDIA  = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local WHITE  = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = MEDIA .. "circle"
local FONT   = "Fonts\\ARIALN.TTF"

local C = {
    bg       = { 0.070, 0.074, 0.085, 0.97 },
    panel    = { 0.098, 0.104, 0.118, 1 },
    control  = { 0.145, 0.151, 0.170, 1 },
    hover    = { 0.190, 0.197, 0.222, 1 },
    text     = { 0.930, 0.937, 0.955, 1 },
    dim      = { 0.700, 0.712, 0.750, 1 },
    muted    = { 0.500, 0.515, 0.560, 1 },
    accent   = { 1.000, 0.540, 0.240, 1 },
    accentHi = { 1.000, 0.640, 0.380, 1 },
    onAccent = { 0.100, 0.050, 0.020, 1 },
}

local W, H = 720, 580
local PAD = 18
local frame
local selected = "MH"
local refreshers = {}
local function OnRefresh(fn) refreshers[#refreshers + 1] = fn end

-- Elements that follow the two-column layout when the window is resized (inside Free Hub).
-- Each one remembers its place for the natural width W; the right column moves and both columns widen.
local GAP = 40
local COLW0 = (W - 2 * PAD - GAP) / 2
local RX0 = PAD + COLW0 + GAP
local flow, onResize = {}, {}
-- point: anchor of the element, placed at (x, y) from the parent's top-left corner.
-- right: x is a right edge (moves with the column width). width: stretched with the column.
local function Flow(obj, point, x, y, width, right)
    flow[#flow + 1] = { o = obj, p = point, x = x, y = y, w = width, right = right }
end
local function Reflow(width)
    width = math.max(W, width or W)
    local colW = (width - 2 * PAD - GAP) / 2
    local dC = colW - COLW0
    local rx = PAD + colW + GAP
    for _, e in ipairs(flow) do
        if e.p then
            local x = e.x
            if x >= RX0 - 1 then x = x - RX0 + rx end
            if e.right then x = x + dC end
            e.o:SetPoint(e.p, e.o:GetParent(), "TOPLEFT", x, e.y)
        end
        if e.w and e.w >= 100 then e.o:SetWidth(e.w + dC) end
    end
    for _, fn in ipairs(onResize) do fn(width) end
end

local function Cfg() return ns.GetDB().bars[selected] end
local function Set(field, value)
    Cfg()[field] = value
    ns.ApplyAll()
    if frame then frame:Refresh() end
end

-- ------------------------------------------------------------ primitives
local function SetFont(obj, size, flags)
    obj:SetFont(FONT, size, flags or "")
    if not obj:GetFont() then obj:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end
-- Draws a text in its own font (font dropdown rows and value); falls back to the options font.
local function SetItemFont(obj, path, size)
    if path then
        local ok, res = pcall(obj.SetFont, obj, path, size, "")
        if ok and res ~= false and obj:GetFont() then return end
    end
    SetFont(obj, size)
end

local function Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    SetFont(fs, size)
    fs:SetTextColor(unpack(color))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function Fill(parent, color, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(unpack(color))
    return t
end

local function Border(f, alpha, layer)
    f.edges = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                         { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local e = f:CreateTexture(nil, layer or "BORDER")
        e:SetTexture(WHITE)
        e:SetVertexColor(1, 1, 1, alpha or 0.07)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
        f.edges[i] = e
    end
end
local function BorderColor(f, r, g, b, a) for _, e in ipairs(f.edges) do e:SetVertexColor(r, g, b, a) end end

local function Label(parent, text, x, y)
    local fs = Text(parent, 13, C.text)
    fs:SetPoint("TOPLEFT", x, y)
    Flow(fs, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Hint(parent, text, x, y, width)
    local fs = Text(parent, 11, C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    Flow(fs, "TOPLEFT", x, y, width)
    fs:SetText(text or "")
    return fs
end

local function Caption(parent, text, x, y)
    local fs = Text(parent, 11, C.accent)
    fs:SetPoint("TOPLEFT", x, y)
    Flow(fs, "TOPLEFT", x, y)
    fs:SetText(text:upper())
    return fs
end

-- ------------------------------------------------------------ controls
local function Button(parent, label, width, primary, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    b.bg = Fill(b, primary and C.accent or C.control)
    b.bg:SetAllPoints()
    if not primary then Border(b, 0.08) end
    b.label = Text(b, 13, primary and C.onAccent or C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(unpack(primary and C.accentHi or C.hover)) end)
    b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(primary and C.accent or C.control)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Switch: track and knob are regions of the same button (knob on a higher layer).
local function Switch(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 18)
    local function cap(left)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE)
        t:SetTexCoord(left and 0 or 0.5, left and 0.5 or 1, 0, 1)
        t:SetSize(9, 18)
        t:SetPoint(left and "LEFT" or "RIGHT")
        return t
    end
    local l, r = cap(true), cap(false)
    local m = b:CreateTexture(nil, "ARTWORK"); m:SetTexture(WHITE)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local knob = b:CreateTexture(nil, "OVERLAY"); knob:SetTexture(CIRCLE); knob:SetSize(14, 14)
    local function paint(on)
        local col = on and C.accent or C.control
        l:SetVertexColor(unpack(col)); r:SetVertexColor(unpack(col)); m:SetVertexColor(unpack(col))
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", -2, 0); knob:SetVertexColor(unpack(C.onAccent))
        else
            knob:SetPoint("LEFT", 2, 0); knob:SetVertexColor(unpack(C.dim))
        end
    end
    b:SetScript("OnClick", function() set(not get()); paint(get()) end)
    OnRefresh(function() paint(get() and true or false) end)
    return b
end

local function SwitchRow(parent, text, x, y, width, get, set)
    Label(parent, text, x, y - 2)
    local s = Switch(parent, get, set)
    s:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    Flow(s, "TOPRIGHT", x + width, y, nil, true)
    return s
end

local function Segmented(parent, items, x, y, width, get, set, height)
    height = height or 26
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    f:SetPoint("TOPLEFT", x, y)
    Flow(f, "TOPLEFT", x, y, width)
    local bg = Fill(f, C.control); bg:SetAllPoints()
    local buttons = {}
    local function layout()
        local w = (f:GetWidth() or width) / #items
        if not w or w <= 0 then w = width / #items end
        for i, b in ipairs(buttons) do
            b:SetSize(w - 2, height - 4)
            b:SetPoint("LEFT", 1 + (i - 1) * w, 0)
        end
    end
    f:SetScript("OnSizeChanged", layout)
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b.sel = Fill(b, C.accent, "ARTWORK"); b.sel:SetAllPoints()
        b.hl = Fill(b, { 1, 1, 1, 0.05 }, "ARTWORK", 1); b.hl:SetAllPoints(); b.hl:Hide()
        b.label = Text(b, 12, C.dim); b.label:SetPoint("CENTER"); b.label:SetText(it[2])
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
        b:SetScript("OnClick", function() set(it[1]) end)
        b.value = it[1]
        buttons[i] = b
    end
    layout()
    OnRefresh(function()
        local v = get()
        for _, b in ipairs(buttons) do
            local on = (b.value == v)
            b.sel:SetShown(on)
            b.label:SetTextColor(unpack(on and C.onAccent or C.dim))
        end
    end)
    return f
end

local function InputBox(parent, width, height)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, height or 24)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(6, 6, 0, 0)
    SetFont(eb, 13)
    eb:SetTextColor(unpack(C.text))
    local bg = Fill(eb, C.control); bg:SetAllPoints()
    Border(eb, 0.08)
    eb:SetScript("OnEditFocusGained", function(self) BorderColor(self, C.accent[1], C.accent[2], C.accent[3], 0.9); self:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function(self) BorderColor(self, 1, 1, 1, 0.08); self:HighlightText(0, 0) end)
    return eb
end

local function num(text)
    local t = (text or ""):gsub(",", ".")
    t = t:gsub("[^%d%.%-]", "")
    return tonumber(t)
end
local function fmtNum(v)
    if math.floor(v) == v then return tostring(v) end
    local s = string.format("%.2f", v):gsub("0+$", "")
    s = s:gsub("%.$", "")
    return s
end

-- Slider row: slim slider with an indicative range + free value box (no limit).
local function SliderRow(parent, text, x, y, width, field, o)
    Label(parent, text, x, y - 5)
    local box = InputBox(parent, 64)
    box:SetJustifyH("CENTER")
    box:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    Flow(box, "TOPRIGHT", x + width, y, nil, true)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width - 110 - 64 - 12, 18)
    Flow(s, nil, 0, 0, width - 110 - 64 - 12)
    s:SetPoint("RIGHT", box, "LEFT", -12, 0)
    s:SetMinMaxValues(o.lo, o.hi)
    s:SetValueStep(o.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local track = Fill(s, { 1, 1, 1, 0.10 }); track:SetHeight(4); track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    local fill = Fill(s, C.accent, "ARTWORK"); fill:SetHeight(4); fill:SetPoint("LEFT")
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(6, 16)
    thumb:SetVertexColor(unpack(C.text))

    local toS = o.toSlider or function(v) return v end
    local fromS = o.fromSlider or function(v) return v end
    local updating = false
    local function paint(v)
        local frac = (math.max(o.lo, math.min(o.hi, v)) - o.lo) / (o.hi - o.lo)
        fill:SetWidth(math.max(0.01, frac * s:GetWidth()))
    end
    s:SetScript("OnSizeChanged", function() paint(toS(Cfg()[field])) end)
    s:SetScript("OnValueChanged", function(_, v)
        paint(v)
        if updating then return end
        v = math.floor(v / o.step + 0.5) * o.step
        Set(field, fromS(v))
    end)
    s:SetScript("OnMouseWheel", function(_, d)
        local v = toS(Cfg()[field]) + d * o.step * (IsShiftKeyDown() and 10 or 1)
        local parsed = o.parse(fmtNum(v))
        if parsed ~= nil then Set(field, parsed) end
    end)
    s:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(C.accent)) end)
    s:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(C.text)) end)
    box:SetScript("OnEnterPressed", function(self)
        local v = o.parse(self:GetText())
        self:ClearFocus()
        if v ~= nil then Set(field, v) else frame:Refresh() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Refresh() end)
    OnRefresh(function()
        local v = toS(Cfg()[field])
        updating = true
        s:SetValue(math.max(o.lo, math.min(o.hi, v)))
        updating = false
        paint(v)
        if not box:HasFocus() then box:SetText(o.fmt(Cfg()[field])) end
    end)
end

-- Colour swatch (opens the game's colour picker)
local function OpenColorPicker(r, g, b, a, hasAlpha, onChange)
    local function current()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if hasAlpha then
            if ColorPickerFrame.GetColorAlpha then na = ColorPickerFrame:GetColorAlpha()
            elseif OpacitySliderFrame then na = 1 - OpacitySliderFrame:GetValue() end
        end
        return nr, ng, nb, na
    end
    local info = {
        r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha,
        swatchFunc = function() onChange(current()) end,
        opacityFunc = function() onChange(current()) end,
        cancelFunc = function() onChange(r, g, b, a) end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = info.swatchFunc, info.opacityFunc, info.cancelFunc
        ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = hasAlpha, hasAlpha and (1 - (a or 1)) or nil
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end
end

local function ColorRow(parent, text, x, y, width, field, hasAlpha, enabledFn)
    local lbl = Label(parent, text, x, y - 3)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(46, 20)
    b:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    Flow(b, "TOPRIGHT", x + width, y, nil, true)
    local checker = Fill(b, { 0.3, 0.3, 0.3, 1 }); checker:SetAllPoints()
    local sw = Fill(b, { 1, 1, 1, 1 }, "ARTWORK"); sw:SetPoint("TOPLEFT", 2, -2); sw:SetPoint("BOTTOMRIGHT", -2, 2)
    Border(b, 0.15, "OVERLAY")
    b:SetScript("OnEnter", function(self) BorderColor(self, C.accent[1], C.accent[2], C.accent[3], 1) end)
    b:SetScript("OnLeave", function(self) BorderColor(self, 1, 1, 1, 0.15) end)
    b:SetScript("OnClick", function()
        if enabledFn and not enabledFn() then return end
        local c = Cfg()[field]
        local key = selected
        OpenColorPicker(c[1], c[2], c[3], c[4] or 1, hasAlpha, function(r, g, bl, a)
            local t = ns.GetDB().bars[key][field]
            t[1], t[2], t[3] = r, g, bl
            if hasAlpha then t[4] = a end
            ns.ApplyAll()
            if frame then frame:Refresh() end
        end)
    end)
    OnRefresh(function()
        local c = Cfg()[field]
        sw:SetVertexColor(c[1], c[2], c[3], hasAlpha and (c[4] or 1) or 1)
        local on = not enabledFn or enabledFn()
        b:SetAlpha(on and 1 or 0.35)
        lbl:SetTextColor(unpack(on and C.text or C.muted))
    end)
end

-- Dropdown with optional texture preview (items: { key=, label=, path= })
local openList
local function Dropdown(parent, text, x, y, width, getItems, get, set, showTextures)
    Label(parent, text, x, y - 5)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width - 120, 26)
    b:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    Flow(b, "TOPRIGHT", x + width, y, width - 120, true)
    local bg = Fill(b, C.control); bg:SetAllPoints()
    Border(b, 0.08)
    local prev = b:CreateTexture(nil, "ARTWORK"); prev:SetPoint("TOPLEFT", 1, -1); prev:SetPoint("BOTTOMRIGHT", -22, 1); prev:SetAlpha(0.35)
    local val = Text(b, 13, C.text); val:SetPoint("LEFT", 8, 0); val:SetPoint("RIGHT", -24, 0); val:SetWordWrap(false)
    local arrow = Text(b, 12, C.dim); arrow:SetPoint("RIGHT", -8, 0); arrow:SetText("v")
    b:SetScript("OnEnter", function() bg:SetVertexColor(unpack(C.hover)) end)
    b:SetScript("OnLeave", function() bg:SetVertexColor(unpack(C.control)) end)

    local list = CreateFrame("Frame", nil, frame)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetWidth(width - 120)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:Hide()
    local lbg = Fill(list, { 0.11, 0.115, 0.13, 1 }); lbg:SetAllPoints()
    Border(list, 0.12)
    local ROWS, RH = 12, 22
    local rows, offset = {}, 0
    -- scroll bar (shown when there are more items than rows: the list scrolls with the mouse wheel)
    local track = Fill(list, { 1, 1, 1, 0.06 }, "OVERLAY"); track:SetWidth(4); track:SetPoint("TOPRIGHT", -2, -2); track:SetPoint("BOTTOMRIGHT", -2, 2)
    local thumb = Fill(list, C.accent, "OVERLAY", 2); thumb:SetWidth(4)
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(RH)
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * RH); r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * RH)
        r.tex = r:CreateTexture(nil, "ARTWORK"); r.tex:SetPoint("TOPLEFT", 2, -2); r.tex:SetPoint("BOTTOMRIGHT", -2, 2); r.tex:SetAlpha(0.55)
        r.hl = Fill(r, { 1, 1, 1, 0.08 }, "ARTWORK", 2); r.hl:SetAllPoints(); r.hl:Hide()
        r.text = Text(r, 12, C.text); r.text:SetPoint("LEFT", 8, 0); r.text:SetPoint("RIGHT", -8, 0); r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self) set(self.key); list:Hide(); openList = nil end)
        rows[i] = r
    end
    local function render()
        local items = getItems()
        offset = math.max(0, math.min(offset, #items - ROWS))
        local shown = math.min(ROWS, #items)
        list:SetHeight(shown * RH + 2)
        if #items > ROWS then
            local h = shown * RH - 2
            local th = math.max(16, h * ROWS / #items)
            thumb:SetHeight(th); thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2 - (h - th) * offset / (#items - ROWS))
            track:Show(); thumb:Show()
        else
            track:Hide(); thumb:Hide()
        end
        for i = 1, ROWS do
            local it = items[i + offset]
            local r = rows[i]
            if it then
                r.key = it.key
                r.text:SetText(it.label)
                SetItemFont(r.text, it.font, 12)
                r.text:SetTextColor(unpack(it.key == get() and C.accent or C.text))
                if showTextures and it.path then r.tex:SetTexture(it.path); r.tex:SetVertexColor(0.8, 0.8, 0.85); r.tex:Show()
                elseif showTextures and it.key == "blizzard" then r.tex:SetAtlas("ui-swingtimerbar-filling-mainhand"); r.tex:SetVertexColor(1, 1, 1); r.tex:Show()
                else r.tex:Hide() end
                r:Show()
            else
                r:Hide()
            end
        end
    end
    list:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; render() end)
    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide(); openList = nil; return end
        if openList then openList:Hide() end
        local items = getItems()
        offset = 0
        for i, it in ipairs(items) do if it.key == get() then offset = math.max(0, i - 5) end end
        -- the window's strata is copied to its children (Free Hub), so put the list back on top each time
        list:SetWidth(b:GetWidth() or (width - 120))
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetFrameLevel((frame:GetFrameLevel() or 1) + 100)
        render(); list:Show(); openList = list
    end)
    OnRefresh(function()
        local cur = get()
        local label, path, font = cur, nil, nil
        for _, it in ipairs(getItems()) do if it.key == cur then label, path, font = it.label, it.path, it.font end end
        val:SetText(label)
        SetItemFont(val, font, 13)
        if showTextures and path then prev:SetTexture(path); prev:SetVertexColor(1, 1, 1); prev:Show()
        elseif showTextures and cur == "blizzard" then prev:SetAtlas("ui-swingtimerbar-filling-mainhand"); prev:SetVertexColor(1, 1, 1); prev:Show()
        else prev:Hide() end
    end)
end

-- ------------------------------------------------------------ window
local function Build()
    frame = CreateFrame("Frame", "FreeSwingOptions", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.fhShadow = shadow
    shadow:SetTexture(MEDIA .. "shadow"); shadow:SetVertexColor(0, 0, 0, 0.8)
    shadow:SetPoint("TOPLEFT", -36, 36); shadow:SetPoint("BOTTOMRIGHT", 36, -36)
    local bg = Fill(frame, C.bg, "BACKGROUND", -6); bg:SetAllPoints()
    Border(frame, 0.09)
    local topLine = Fill(frame, C.accent, "BORDER", 2); topLine:SetHeight(2); topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")

    -- header
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(54)
    header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    -- inside Free Hub, dragging the header moves the hub window instead
    header:SetScript("OnDragStart", function() (frame.fhMover or frame):StartMoving() end)
    header:SetScript("OnDragStop", function() (frame.fhMover or frame):StopMovingOrSizing() end)
    local icon = header:CreateTexture(nil, "ARTWORK"); icon:SetTexture(MEDIA .. "icon"); icon:SetSize(32, 32); icon:SetPoint("LEFT", PAD, -1)
    local title = Text(header, 17, C.text); title:SetPoint("LEFT", icon, "RIGHT", 10, 7); title:SetText("Free Swing Timer")
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or ""
    local sub = Text(header, 11, C.muted); sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3); sub:SetText("Swing timers  ·  v" .. ver)
    local close = CreateFrame("Button", nil, header); close:SetSize(26, 26); close:SetPoint("RIGHT", -12, 0)
    local x1 = Fill(close, C.dim, "ARTWORK"); x1:SetSize(14, 2); x1:SetPoint("CENTER"); x1:SetRotation(math.rad(45))
    local x2 = Fill(close, C.dim, "ARTWORK"); x2:SetSize(14, 2); x2:SetPoint("CENTER"); x2:SetRotation(math.rad(-45))
    close:SetScript("OnEnter", function() x1:SetVertexColor(unpack(C.accent)); x2:SetVertexColor(unpack(C.accent)) end)
    close:SetScript("OnLeave", function() x1:SetVertexColor(unpack(C.dim)); x2:SetVertexColor(unpack(C.dim)) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.fhClose = close

    -- bar cards
    local NB = #ns.BAR_KEYS
    local cardW = (W - 2 * PAD - (NB - 1) * 8) / NB
    local cards = {}
    onResize[#onResize + 1] = function(width)
        local cw = (width - 2 * PAD - (NB - 1) * 8) / NB
        for i, card in ipairs(cards) do
            card:SetWidth(cw)
            card:SetPoint("TOPLEFT", PAD + (i - 1) * (cw + 8), -62)
        end
    end
    local VIS = { always = "Always shown", combat = "In combat", active = "While swinging", hidden = "Disabled" }
    for i, key in ipairs(ns.BAR_KEYS) do
        local card = CreateFrame("Button", nil, frame)
        card:SetSize(cardW, 46)
        card:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + 8), -62)
        cards[i] = card
        card.bg = Fill(card, C.panel); card.bg:SetAllPoints()
        Border(card, 0.06)
        card.mark = Fill(card, C.accent, "ARTWORK"); card.mark:SetHeight(2); card.mark:SetPoint("BOTTOMLEFT"); card.mark:SetPoint("BOTTOMRIGHT")
        card.dot = card:CreateTexture(nil, "ARTWORK"); card.dot:SetTexture(CIRCLE); card.dot:SetSize(10, 10); card.dot:SetPoint("TOPLEFT", 12, -12)
        card.name = Text(card, 14, C.text); card.name:SetPoint("LEFT", card.dot, "RIGHT", 8, 0); card.name:SetPoint("RIGHT", -8, 0); card.name:SetWordWrap(false)
        card.state = Text(card, 11, C.muted); card.state:SetPoint("TOPLEFT", 30, -27)
        card:SetScript("OnEnter", function(self) if selected ~= key then self.bg:SetVertexColor(unpack(C.control)) end end)
        card:SetScript("OnLeave", function(self) if selected ~= key then self.bg:SetVertexColor(unpack(C.panel)) end end)
        card:SetScript("OnClick", function() selected = key; if openList then openList:Hide() end; frame:Refresh() end)
        OnRefresh(function()
            local c = ns.GetDB().bars[key]
            local on = (selected == key)
            card.bg:SetVertexColor(unpack(on and C.control or C.panel))
            card.mark:SetShown(on)
            card.dot:SetVertexColor(c.color[1], c.color[2], c.color[3], c.visibility == "hidden" and 0.3 or 1)
            card.name:SetText((c.name ~= "" and c.name) or ns.BAR_INFO[key].label)
            card.name:SetTextColor(unpack(c.visibility == "hidden" and C.muted or C.text))
            card.state:SetText(VIS[c.visibility] or "")
        end)
    end

    -- live preview
    local pv = CreateFrame("Frame", nil, frame)
    pv:SetPoint("TOPLEFT", PAD, -118); pv:SetPoint("TOPRIGHT", -PAD, -118); pv:SetHeight(70)
    local pvbg = Fill(pv, { 0.045, 0.048, 0.056, 1 }); pvbg:SetAllPoints()
    Border(pv, 0.05)
    local pvCap = Text(pv, 10, C.muted); pvCap:SetPoint("TOPLEFT", 8, -6); pvCap:SetText("LIVE PREVIEW")
    local holder = CreateFrame("Frame", nil, pv); holder:SetAllPoints()
    local preview = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        local p = ns.CreateBar(key, holder, function() return ns.GetDB().bars[key] end, true)
        p:SetPoint("CENTER", holder, "CENTER", 0, -4)
        p:Hide()
        preview[key] = p
    end
    local function UpdatePreview()
        for key, p in pairs(preview) do
            if key == selected then
                local c = ns.GetDB().bars[key]
                local maxW, maxH = (frame:GetWidth() or W) - 2 * PAD - 80, 44
                local s = math.min(1, maxW / math.max(1, c.width + (c.showIcon and c.height + 4 or 0)), maxH / math.max(1, c.height))
                p:SetScale(s)
                p:ApplyStyle()
                p:Show()
                if not p.swingEnd then p:StartSwing(2.6) end
            else
                p:Hide()
            end
        end
    end
    ns.OnStyleChanged = function() if frame and frame:IsShown() then UpdatePreview() end end
    OnRefresh(UpdatePreview)

    -- tabs
    local TABS = { { "layout", "Layout" }, { "bar", "Bar" }, { "text", "Text & Icon" }, { "behavior", "Behavior" }, { "profiles", "Profiles" } }
    local pages, tabButtons, activeTab = {}, {}, "layout"
    local tabY = -200
    local line = Fill(frame, { 1, 1, 1, 0.07 }, "BORDER"); line:SetHeight(1)
    line:SetPoint("TOPLEFT", PAD, tabY - 30); line:SetPoint("TOPRIGHT", -PAD, tabY - 30)
    local tx = PAD
    for _, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame)
        b.label = Text(b, 14, C.dim); b.label:SetPoint("LEFT"); b.label:SetText(t[2])
        b:SetSize(b.label:GetStringWidth() + 4, 30)
        b:SetPoint("TOPLEFT", tx, tabY)
        b.under = Fill(b, C.accent, "ARTWORK"); b.under:SetHeight(2); b.under:SetPoint("BOTTOMLEFT", 0, -1); b.under:SetPoint("BOTTOMRIGHT", 0, -1)
        b:SetScript("OnClick", function() activeTab = t[1]; if openList then openList:Hide() end; frame:Refresh() end)
        b:SetScript("OnEnter", function(self) if activeTab ~= t[1] then self.label:SetTextColor(unpack(C.text)) end end)
        b:SetScript("OnLeave", function(self) if activeTab ~= t[1] then self.label:SetTextColor(unpack(C.dim)) end end)
        tabButtons[t[1]] = b
        tx = tx + b:GetWidth() + 26
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 0, tabY - 44); page:SetPoint("BOTTOMRIGHT", 0, 60)
        pages[t[1]] = page
    end
    OnRefresh(function()
        for k, b in pairs(tabButtons) do
            local on = (k == activeTab)
            b.under:SetShown(on)
            b.label:SetTextColor(unpack(on and C.text or C.dim))
            pages[k]:SetShown(on)
        end
    end)

    local COLW = COLW0
    local LX, RX = PAD, RX0
    local ROW = 38
    local positive = function(t) local v = num(t); return (v and v > 0) and v or nil end
    local any = function(t) return num(t) end
    local function bool(field) return function() return Cfg()[field] and true or false end, function(v) Set(field, v) end end

    -- Layout
    local p = pages.layout
    Caption(p, "Size", LX, 0)
    SliderRow(p, "Width", LX, -22, COLW, "width", { lo = 20, hi = 1000, step = 1, fmt = fmtNum, parse = positive })
    SliderRow(p, "Height", LX, -22 - ROW, COLW, "height", { lo = 1, hi = 80, step = 1, fmt = fmtNum, parse = positive })
    SliderRow(p, "Scale", LX, -22 - 2 * ROW, COLW, "scale", { lo = 0.5, hi = 2, step = 0.05, fmt = fmtNum, parse = positive })
    SliderRow(p, "Opacity", LX, -22 - 3 * ROW, COLW, "alpha", {
        lo = 0, hi = 100, step = 1,
        toSlider = function(v) return math.floor(v * 100 + 0.5) end, fromSlider = function(v) return v / 100 end,
        fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        parse = function(t) local v = num(t); if v and v >= 0 and v <= 100 then return v / 100 end end,
    })
    Hint(p, "Sliders cover the usual range; type any value in the box and press Enter. Mouse wheel steps, Shift x10.", LX, -22 - 4 * ROW, COLW)
    Caption(p, "Position", RX, 0)
    SliderRow(p, "Offset X", RX, -22, COLW, "x", { lo = -1500, hi = 1500, step = 1, fmt = fmtNum, parse = any })
    SliderRow(p, "Offset Y", RX, -22 - ROW, COLW, "y", { lo = 0, hi = 1200, step = 1, fmt = fmtNum, parse = any })
    SwitchRow(p, "Fill right to left", RX, -22 - 2 * ROW, COLW, bool("reverse"))
    local center = Button(p, "Center horizontally", 150, false, function()
        local c = Cfg(); c.point, c.relPoint, c.x = "BOTTOM", "BOTTOM", 0; ns.ApplyAll(); frame:Refresh()
    end)
    center:SetPoint("TOPLEFT", RX, -22 - 3 * ROW)
    Flow(center, "TOPLEFT", RX, -22 - 3 * ROW)
    Hint(p, "Offsets are measured from the bottom centre of the screen. Unlock to drag bars with the mouse.", RX, -22 - 4 * ROW + 2, COLW)

    -- Bar
    p = pages.bar
    Caption(p, "Fill", LX, 0)
    Dropdown(p, "Texture", LX, -22, COLW, ns.TextureList, function() return Cfg().texture end, function(v) Set("texture", v) end, true)
    ColorRow(p, "Bar colour", LX, -22 - ROW, COLW, "color", false, function()
        local c = Cfg(); return not c.classColor and (c.texture ~= "blizzard" or c.tint)
    end)
    SwitchRow(p, "Use class colour", LX, -22 - 2 * ROW, COLW, bool("classColor"))
    SwitchRow(p, "Tint Blizzard texture", LX, -22 - 3 * ROW, COLW, bool("tint"))
    SwitchRow(p, "Spark", LX, -22 - 4 * ROW, COLW, bool("spark"))
    local BG = { { key = "blizzard", label = "Blizzard" }, { key = "solid", label = "Solid colour" }, { key = "none", label = "None" } }
    Caption(p, "Frame", RX, 0)
    Dropdown(p, "Background", RX, -22, COLW, function() return BG end, function() return Cfg().background end, function(v) Set("background", v) end)
    ColorRow(p, "Background colour", RX, -22 - ROW, COLW, "bgColor", true, function() return Cfg().background == "solid" end)
    local BD = { { key = "blizzard", label = "Blizzard" }, { key = "thin", label = "Thin line" }, { key = "none", label = "None" } }
    Dropdown(p, "Border", RX, -22 - 2 * ROW, COLW, function() return BD end, function() return Cfg().border end, function(v) Set("border", v) end)
    ColorRow(p, "Border colour", RX, -22 - 3 * ROW, COLW, "borderColor", true, function() return Cfg().border == "thin" end)
    Hint(p, "Textures from other addons (LibSharedMedia) appear in the list automatically.", RX, -22 - 4 * ROW + 4, COLW)

    -- Text & Icon
    p = pages.text
    Caption(p, "Text", LX, 0)
    SwitchRow(p, "Show name", LX, -22, COLW, bool("showName"))
    Label(p, "Custom name", LX, -22 - ROW - 3)
    local nameBox = InputBox(p, COLW - 120)
    nameBox:SetPoint("TOPRIGHT", p, "TOPLEFT", LX + COLW, -22 - ROW)
    Flow(nameBox, "TOPRIGHT", LX + COLW, -22 - ROW, COLW - 120, true)
    local ghost = Text(nameBox, 13, C.muted); ghost:SetPoint("LEFT", 6, 0)
    nameBox:SetScript("OnTextChanged", function(self) ghost:SetShown(self:GetText() == "") end)
    nameBox:SetScript("OnEnterPressed", function(self) Set("name", self:GetText()); self:ClearFocus() end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Refresh() end)
    OnRefresh(function()
        ghost:SetText(ns.BAR_INFO[selected].label)
        if not nameBox:HasFocus() then nameBox:SetText(Cfg().name or "") end
        ghost:SetShown(nameBox:GetText() == "")
    end)
    SwitchRow(p, "Show time", LX, -22 - 2 * ROW, COLW, bool("showTime"))
    Label(p, "Time", LX, -22 - 3 * ROW - 3)
    Segmented(p, { { "remaining", "Remaining" }, { "elapsed", "Elapsed" }, { "both", "Rem. / total" } }, LX + 120, -22 - 3 * ROW, COLW - 120,
        function() return Cfg().timeFormat end, function(v) Set("timeFormat", v) end)
    Label(p, "Decimals", LX, -22 - 4 * ROW - 3)
    Segmented(p, { { 0, "0" }, { 1, "0.0" }, { 2, "0.00" } }, LX + 120, -22 - 4 * ROW, COLW - 120,
        function() return Cfg().decimals end, function(v) Set("decimals", v) end)
    Caption(p, "Font", RX, 0)
    -- every font is listed in its own typeface (LibFreeMedia); the bars use it for the name and the time
    local function FontItems()
        local out, LFM = {}, LibStub and LibStub("LibFreeMedia-1.0", true)
        for _, f in ipairs(LFM and LFM:ListFonts() or {}) do out[#out + 1] = { key = f.key, label = f.label, font = f.path } end
        if #out == 0 then out[1] = { key = "ARIALN", label = "Arial Narrow", font = FONT } end
        return out
    end
    Dropdown(p, "Font", RX, -22, COLW, FontItems, function() return Cfg().font or "ARIALN" end, function(v) Set("font", v) end)
    SliderRow(p, "Font size", RX, -22 - ROW, COLW, "fontSize", {
        lo = 0, hi = 32, step = 1,
        fmt = function(v) return (v and v > 0) and fmtNum(v) or "Auto" end,
        parse = function(t) if (t or ""):lower():find("auto") then return 0 end local v = num(t); return (v and v >= 0) and v or nil end,
    })
    Label(p, "Outline", RX, -22 - 2 * ROW - 3)
    Segmented(p, { { "NONE", "Shadow" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" } }, RX + 120, -22 - 2 * ROW, COLW - 120,
        function() return Cfg().outline end, function(v) Set("outline", v) end)
    Caption(p, "Icon", RX, -22 - 3 * ROW - 4)
    SwitchRow(p, "Show icon", RX, -22 - 3 * ROW - 22, COLW, bool("showIcon"))
    Label(p, "Icon side", RX, -22 - 4 * ROW - 25)
    Segmented(p, { { "LEFT", "Left" }, { "RIGHT", "Right" } }, RX + 120, -22 - 4 * ROW - 22, COLW - 120,
        function() return Cfg().iconSide end, function(v) Set("iconSide", v) end)
    Hint(p, "Shows the icon of the equipped weapon.", RX, -22 - 5 * ROW - 18, COLW)

    -- Behavior
    p = pages.behavior
    Caption(p, "Visibility", LX, 0)
    Segmented(p, { { "always", "Always" }, { "combat", "In combat" }, { "active", "Swinging" }, { "hidden", "Off" } }, LX, -22, COLW,
        function() return Cfg().visibility end, function(v) Set("visibility", v) end, 28)
    local visHint = Hint(p, "", LX, -58, COLW)
    OnRefresh(function()
        visHint:SetText(({
            always = "Always on screen (hidden only when the weapon is missing).",
            combat = "Shown in combat and during a swing.",
            active = "Only while the timer runs: hidden as soon as it reaches 0. Ideal for a ranged weapon you rarely use.",
            hidden = "This bar is disabled.",
        })[Cfg().visibility] or "")
    end)
    SwitchRow(p, "Dim when out of range", LX, -22 - 2 * ROW - 4, COLW, bool("rangeDim"))
    local rangeHint = Hint(p, "", LX, -22 - 3 * ROW + 6, COLW)
    OnRefresh(function()
        rangeHint:SetText("Fades the bar and turns its text red while your target is out of reach.")
    end)
    Caption(p, "General", RX, 0)
    SwitchRow(p, "Minimap button", RX, -22, COLW,
        function() return ns.IsMinimapShown == nil or ns.IsMinimapShown() end,
        function(v) if ns.SetMinimapShown then ns.SetMinimapShown(v) end end)

    -- Profiles (like ElvUI: each character picks one; export / import as text)
    p = pages.profiles
    local PM = function() return ns.profiles end
    local function profileItems(exceptCurrent)
        local out = {}
        local m = PM()
        if not m then return out end
        for _, name in ipairs(m:List()) do
            if not (exceptCurrent and name == m:Current()) then
                local n = m:Users(name)
                out[#out + 1] = { key = name, label = name .. (n > 0 and ("  (" .. n .. " char.)") or "") }
            end
        end
        return out
    end
    Caption(p, "Profile", LX, 0)
    Dropdown(p, "This character", LX, -22, COLW, function() return profileItems(false) end,
        function() return PM() and PM():Current() end, function(v) if PM() then PM():Set(v); frame:Refresh() end end)
    Label(p, "New profile", LX, -22 - ROW - 5)
    local newBox = InputBox(p, COLW - 120 - 2 * 76)
    newBox:SetPoint("TOPLEFT", LX + 120, -22 - ROW)
    Flow(newBox, "TOPLEFT", LX + 120, -22 - ROW, COLW - 120 - 2 * 76)
    local function newName() local t = (newBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""); return t ~= "" and t or nil end
    local bNew = Button(p, "Empty", 72, false, function()
        local n = newName(); if not n or not PM() then return end
        newBox:SetText(""); newBox:ClearFocus(); PM():Set(n); frame:Refresh()
    end)
    bNew:SetPoint("LEFT", newBox, "RIGHT", 4, 0)
    local bDup = Button(p, "Copy", 72, true, function()
        local n = newName(); if not n or not PM() then return end
        newBox:SetText(""); newBox:ClearFocus(); PM():Set(n, PM():Current()); frame:Refresh()
    end)
    bDup:SetPoint("LEFT", bNew, "RIGHT", 4, 0)
    newBox:SetScript("OnEnterPressed", function() bDup:Click() end)
    newBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Dropdown(p, "Copy settings", LX, -22 - 2 * ROW, COLW, function() return profileItems(true) end,
        function() return "from another profile..." end, function(v) if PM() then PM():CopyFrom(v); frame:Refresh() end end)
    Dropdown(p, "Delete", LX, -22 - 3 * ROW, COLW, function() return profileItems(true) end,
        function() return "choose a profile..." end, function(v) if PM() then PM():Delete(v); frame:Refresh() end end)
    Label(p, "Current profile", LX, -22 - 4 * ROW - 5)
    local bReset
    bReset = Button(p, "Reset to defaults", 150, false, function()
        local now = GetTime and GetTime() or 0
        if bReset.armed and now - bReset.armed < 4 then
            bReset.armed = nil; bReset.label:SetText("Reset to defaults")
            if PM() then PM():Reset(); frame:Refresh() end
        else
            bReset.armed = now; bReset.label:SetText("Click again")
        end
    end)
    bReset:SetPoint("TOPLEFT", LX + 120, -22 - 4 * ROW)
    OnRefresh(function() bReset.armed = nil; bReset.label:SetText("Reset to defaults") end)
    Hint(p, "Each character remembers its profile. \"Copy\" starts the new profile from the current one.", LX, -22 - 5 * ROW + 4, COLW)

    local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
    Caption(p, "Share", RX, 0)
    local bExp = Button(p, "Export profile", 150, false, function()
        if LFP and PM() then LFP:ShowExport("Export Free Swing profile: " .. PM():Current(), PM():Export()) end
    end)
    bExp:SetPoint("TOPLEFT", RX, -22)
    Flow(bExp, "TOPLEFT", RX, -22)
    local bImp = Button(p, "Import profile", 150, false, function()
        if LFP and PM() then
            LFP:ShowImport("Import a Free Swing profile", "Imported", function(text, name)
                local ok, res = PM():Import(text, name)
                if ok then frame:Refresh() end
                return ok, res
            end)
        end
    end)
    bImp:SetPoint("LEFT", bExp, "RIGHT", 8, 0)
    Hint(p, "Export gives one line of text to paste on another character or account (or to share with a friend). Import creates a profile from such a text and selects it.", RX, -22 - ROW, COLW)

    -- footer
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT"); footer:SetHeight(56)
    local fbg = Fill(footer, C.panel, "BACKGROUND", -5); fbg:SetAllPoints()
    local fl = Fill(footer, { 1, 1, 1, 0.06 }, "BORDER"); fl:SetHeight(1); fl:SetPoint("TOPLEFT"); fl:SetPoint("TOPRIGHT")
    local copy = Button(footer, "Copy style to all bars", 170, false, function() ns.CopyStyle(selected) end)
    copy:SetPoint("LEFT", PAD, 0)
    local reset = Button(footer, "Reset bar", 96, false, function() ns.Reset(selected) end)
    reset:SetPoint("LEFT", copy, "RIGHT", 8, 0)
    local lock = Button(footer, "Unlock", 120, true, function() ns.SetUnlocked(not ns.IsUnlocked()) end)
    lock:SetPoint("RIGHT", -PAD, 0)
    OnRefresh(function() lock.label:SetText(ns.IsUnlocked() and "Lock" or "Unlock") end)
    local test = Button(footer, "Test", 80, false, function() ns.Test() end)
    test:SetPoint("RIGHT", lock, "LEFT", -8, 0)

    function frame:Refresh()
        for _, fn in ipairs(refreshers) do fn() end
    end
    frame:SetScript("OnShow", function(self) self:Refresh() end)
    frame:SetScript("OnSizeChanged", function(_, w) Reflow(w); if ns.OnStyleChanged then ns.OnStyleChanged() end end)
    frame:SetScript("OnHide", function() if openList then openList:Hide(); openList = nil end end)
    frame:Hide()
end

-- ------------------------------------------------------------ Free Hub integration
-- When Free Hub is installed, these options open inside its window (sidebar on the left).
local function Embed(parent)
    if not ns.GetDB() then return end
    if not frame then Build() end
    frame.fhEmbedded = true
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)   -- fills the hub; the layout follows its size
    frame:SetFrameStrata(parent:GetFrameStrata())
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)
    frame.fhShadow:Hide()
    frame.fhClose:Hide()
    frame.fhMover = FreeHub:GetFrame()
    frame.fhNaturalW, frame.fhNaturalH = W, H
    frame:Show()
    return frame
end
local function Unembed()
    if not frame or not frame.fhEmbedded then return end
    frame.fhEmbedded = nil
    frame:Hide()
    frame:SetParent(UIParent)
    frame:ClearAllPoints()
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame.fhShadow:Show()
    frame.fhClose:Show()
    frame.fhMover = nil
end
if FreeHub and FreeHub.Register then
    FreeHub:Register("FreeSwing", {
        embed = Embed,
        unembed = Unembed,
        minW = W, minH = H,   -- natural size of these options; the hub never gets smaller than this
        minimap = function(show) if ns.ApplyMinimapVisibility then ns.ApplyMinimapVisibility(show) end end,
    })
end

ns.ToggleConfig = function()
    if not ns.GetDB() then return end
    if FreeHub and FreeHub.Toggle and FreeHub:IsRegistered("FreeSwing") then FreeHub:Toggle("FreeSwing"); return end
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

ns.OnChanged = function()
    if frame and frame:IsShown() then frame:Refresh() end
end
