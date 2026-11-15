-- CraftScout options: Esc > Options > AddOns > CraftScout.
-- Declarative like LevelScout: add a default in UI.lua CS.DEFAULTS + an entry here.

local CS = CraftScout
if not CS then return end
local msg = CS.msg

local function ui() return CS.GetUI and CS.GetUI() end
local function refresh() if CS.Refresh then CS.Refresh(true) end end

local PAGES = {
    {
        name = "CraftScout",
        intro = "Profession helper: skill-up crafts with the mats you carry, trainers for your next rank, "
            .. "and recipes you can learn with where to get them. Recipe data: LibProfessionDB (MIT). "
            .. "NPC locations: Questie.",
        options = {
            { type = "header", label = "Window" },
            { type = "check", key = "shown", label = "Show the CraftScout window",
              apply = function(v) CS.SetShown(v) end },
            { type = "check", key = "locked", label = "Lock window position and size",
              apply = function() CS.ApplyLock() end },
            { type = "slider", key = "alpha", label = "Background opacity", min = 0, max = 1, step = 0.05,
              fmt = function(v) return ("%d%%"):format(v * 100) end, apply = function(v) CS.SetAlpha(v) end },
            { type = "button", label = "Reset window position", run = function() CS.ResetPosition() end },
            { type = "header", label = "Content" },
            { type = "check", key = "includeBank", label = "Count items in your bank as available mats",
              tip = "Bank counts are only known after you've opened your bank this session." },
            { type = "check", key = "onlyFriendly", label = "Hide opposite-faction trainers and vendors" },
            { type = "check", key = "showNeedMats", label = "Show skill-ups you're missing mats for" },
            { type = "check", key = "showLearn", label = "Show recipes you can learn now" },
            { type = "check", key = "showDrops", label = "Include recipes that only come from drops" },
            { type = "check", key = "showUpcoming", label = "Show recipes coming up soon" },
            { type = "slider", key = "upcomingRange", label = "Coming up: skill points ahead", min = 5, max = 75, step = 5,
              fmt = function(v) return tostring(v) end },
            { type = "slider", key = "maxRows", label = "Max rows per section", min = 5, max = 60, step = 5,
              fmt = function(v) return tostring(v) end },
            { type = "header", label = "Disenchanting (item tooltips)" },
            { type = "check", key = "deTooltip", label = "Show what items disenchant into",
              tip = "Odds use Forever's disenchant brackets with Classic-derived chances (not measured on Forever)." },
            { type = "check", key = "deAdvice", label = "Suggest sell or disenchant",
              tip = "Disenchant when a likely result is a mat your known Enchanting skill-ups use; otherwise "
                .. "sell at vendor price. Uses Auctionator prices when there are no skill-up needs, if installed." },
            { type = "check", key = "deOnlyEnchanters", label = "Only on characters with Enchanting" },
            { type = "text", label = "|cffa0a0a0Commands: /craftscout (toggle), /craftscout config, /craftscout trainers. "
                .. "Addon menu: left-click toggles, right-click opens options.|r" },
        },
    },
}

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT"); fs:SetText(text)
    return fs
end

local function addTooltip(frame, title, tip)
    if not tip then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 0.82, 0); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function setValue(opt, v)
    local u = ui(); if not u then return end
    u[opt.key] = v
    if opt.apply then pcall(opt.apply, v) end
    refresh()
end

local function makeCheck(parent, opt)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local text = label(cb, opt.label); text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    if type(cb.Text) == "table" and cb.Text.SetText then cb.Text:SetText("") end
    cb:SetScript("OnClick", function(self) setValue(opt, self:GetChecked() and true or false) end)
    addTooltip(cb, opt.label, opt.tip)
    cb.sync = function() local u = ui(); cb:SetChecked(u and u[opt.key] and true or false) end
    return cb, 30
end

local function makeSlider(parent, opt)
    local holder = CreateFrame("Frame", nil, parent); holder:SetSize(420, 40)
    local title = label(holder, opt.label); title:SetPoint("TOPLEFT", 4, 0)
    local value = label(holder, "", "GameFontNormal"); value:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local s = CreateFrame("Slider", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetOrientation("HORIZONTAL"); s:SetSize(220, 16); s:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)
    if s.SetBackdrop then
        s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(opt.min, opt.max); s:SetValueStep(opt.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * opt.step) end)
    local syncing = false
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / opt.step + 0.5) * opt.step
        value:SetText(opt.fmt and opt.fmt(v) or tostring(v))
        if not syncing then setValue(opt, v) end
    end)
    holder.sync = function()
        local u = ui(); syncing = true
        local v = (u and u[opt.key]) or opt.min
        s:SetValue(v); value:SetText(opt.fmt and opt.fmt(v) or tostring(v))
        syncing = false
    end
    return holder, 46
end

local function makeButton(parent, opt)
    local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not ok or not b then
        b = CreateFrame("Button", nil, parent)
        local t = b:CreateFontString(nil, "ARTWORK", "GameFontNormal"); t:SetAllPoints()
        b.SetText = function(_, s) t:SetText(s) end
    end
    b:SetSize(220, 22); b:SetText(opt.label)
    b:SetScript("OnClick", function() pcall(opt.run); refresh() end)
    return b, 30
end

local function buildPage(page)
    local f = CreateFrame("Frame"); f.name = page.name; f:Hide()
    local title = label(f, page.name, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -16)
    local y = -44
    if page.intro then
        local intro = label(f, page.intro, "GameFontHighlightSmall")
        intro:SetPoint("TOPLEFT", 16, y); intro:SetPoint("RIGHT", f, "RIGHT", -16, 0); intro:SetWordWrap(true)
        y = y - 40
    end
    local widgets = {}
    for _, opt in ipairs(page.options) do
        local w, h
        if opt.type == "header" then w = label(f, opt.label, "GameFontNormal"); h = 22; y = y - 6
        elseif opt.type == "text" then
            w = label(f, opt.label, "GameFontHighlightSmall"); w:SetPoint("RIGHT", f, "RIGHT", -16, 0); w:SetWordWrap(true); h = 36
        elseif opt.type == "check" then w, h = makeCheck(f, opt)
        elseif opt.type == "slider" then w, h = makeSlider(f, opt)
        elseif opt.type == "button" then w, h = makeButton(f, opt) end
        if w then
            w:SetPoint("TOPLEFT", f, "TOPLEFT", opt.type == "header" and 16 or 20, y)
            if w.sync then widgets[#widgets + 1] = w end
            y = y - h
        end
    end
    f:SetScript("OnShow", function() for _, w in ipairs(widgets) do pcall(w.sync) end end)
    f.OnCommit, f.OnDefault, f.OnRefresh = function() end, function() end, function() end
    return f
end

local mainCategory
local function register()
    if mainCategory then return end
    local frames = {}
    for i, page in ipairs(PAGES) do frames[i] = buildPage(page) end
    if Settings and Settings.RegisterCanvasLayoutCategory then
        for i, f in ipairs(frames) do
            local cat
            if i == 1 then cat = Settings.RegisterCanvasLayoutCategory(f, f.name); mainCategory = cat
            else cat = Settings.RegisterCanvasLayoutSubcategory(mainCategory, f, f.name) end
            Settings.RegisterAddOnCategory(cat)
        end
    elseif InterfaceOptions_AddCategory then
        for i, f in ipairs(frames) do
            if i > 1 then f.parent = frames[1].name end
            InterfaceOptions_AddCategory(f)
        end
        mainCategory = frames[1]
    end
end

function CS.OpenOptions()
    if InCombatLockdown and InCombatLockdown() then msg("options can't open during combat") return end
    if Settings and Settings.OpenToCategory and mainCategory then
        Settings.OpenToCategory((mainCategory.GetID and mainCategory:GetID()) or mainCategory.ID)
    elseif InterfaceOptionsFrame_OpenToCategory and mainCategory then
        InterfaceOptionsFrame_OpenToCategory(mainCategory); InterfaceOptionsFrame_OpenToCategory(mainCategory)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    local ok, err = pcall(register)
    if not ok then msg("options failed to register: " .. tostring(err)) end
end)
