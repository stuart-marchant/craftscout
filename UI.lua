-- CraftScout window: one tab per profession with
--   Craft now (skill-ups you have mats for) / Skill-ups needing mats /
--   Next rank + trainers / Learn now (unknown recipes + where) / Coming up

local CS = CraftScout
if not CS then return end
local S, try, msg = CS.S, CS.try, CS.msg

local ui
CS.DEFAULTS = {
    shown = true, locked = false, alpha = 0.88, w = 340, h = 480,
    collapsed = { upcoming = false },
    onlyFriendly = true,   -- hide opposite-faction trainers/vendors
    includeBank = true,    -- count bank items for mats
    showNeedMats = true,
    showLearn = true,
    showDrops = true,      -- include learnable recipes that only drop
    showUpcoming = true,
    upcomingRange = 25,
    maxRows = 20,
    -- disenchant tooltips (Disenchant.lua)
    deTooltip = true,         -- add disenchant results to item tooltips
    deAdvice = true,          -- sell / disenchant suggestion
    deOnlyEnchanters = true,  -- only on characters with Enchanting
}

local function initUI()
    local db = CS.DB()
    db.ui = db.ui or {}
    ui = db.ui
    for k, v in pairs(CS.DEFAULTS) do
        if ui[k] == nil then
            if type(v) == "table" then
                local c = {}
                for kk, vv in pairs(v) do c[kk] = vv end
                ui[k] = c
            else
                ui[k] = v
            end
        end
    end
end
function CS.GetUI() return ui end

local function color(hex, s) return "|c" .. hex .. s .. "|r" end
local DIM, WHITE, CYAN, GOLD, GREEN, RED = "ffa0a0a0", "ffffffff", "ff66ccff", "ffffd100", "ff40c040", "ffff6060"

local function coin(c)
    if type(c) ~= "number" or c <= 0 then return "" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return ("%dg %ds"):format(g, s) end
    if s > 0 then return ("%ds %dc"):format(s, cp) end
    return ("%dc"):format(cp)
end

-------------------------------------------------------------------------------
-- model
-------------------------------------------------------------------------------
local SOURCE_ORDER = { "trainer", "vendor", "quest", "container", "drop" }
local SOURCE_LABEL = { trainer = "Trainer", vendor = "Vendor", quest = "Quest", container = "Container", drop = "Drop" }

local function bestNPC(ids, onlyFriendly)
    local best, bestKey, bestD, any
    for _, src in ipairs(ids) do
        local npc = CS.NPC(src.id)
        if npc and not (onlyFriendly and npc.friendly == false) then
            any = any or npc
            local d = CS.Distance(npc)
            local key = d or 1e12
            if npc.uiMap and (not bestKey or key < bestKey) then
                best, bestKey, bestD = npc, key, d
            end
        end
    end
    return best or any, bestD
end

-- where to get an unknown recipe: { kind, npc, dist, count, sources, borrowed }
local function acquisition(lib, rid)
    local src = lib.GetRecipeSources and lib:GetRecipeSources(rid)
    if not src then
        if lib.IsAutoTaughtRecipe and lib:IsAutoTaughtRecipe(rid) then
            return { kind = "auto" }
        end
        return { kind = "unknown" }
    end
    for _, kind in ipairs(SOURCE_ORDER) do
        local list = src[kind]
        if list and #list > 0 then
            local a = { kind = kind, sources = src, count = list.total or #list }
            if kind == "trainer" or kind == "vendor" then
                a.npc, a.dist = bestNPC(list, ui.onlyFriendly)
                if not a.npc then a.wrongFaction = true end
            elseif kind == "drop" then
                a.example = list[1] and (list[1].name or CS.NPC(list[1].id).name)
            elseif kind == "quest" then
                a.questId = list[1] and list[1].id
            end
            a.borrowed = lib.IsBorrowed and lib:IsBorrowed(rid, "sources")
            -- a recipe with only opposite-faction trainers/vendors: try next kind
            if not a.wrongFaction then return a end
        end
    end
    return { kind = "wrongFaction" }
end

function CS.BuildModel(prof)
    local m = { prof = prof, craftNow = {}, needMats = {}, learn = {}, upcoming = {} }
    local lib = CS.Lib()
    m.libReady = lib ~= nil
    if not lib then return m end
    local cdb = CS.CharDB()
    local skill = prof.rank or 0
    local known = cdb.known[prof.id]
    m.scanned = known ~= nil
    m.scannedAt = cdb.scannedAt[prof.id]
    known = known or {}
    CS.UpdatePlayerPos()

    local recipes = lib:GetRecipes(prof.id) or {}
    for rid, r in pairs(recipes) do
        local isKnown = known[rid] or (lib.IsAutoTaughtRecipe and lib:IsAutoTaughtRecipe(rid))
        local col = CS.Color(r, skill)
        if isKnown then
            if col == "orange" or col == "yellow" or col == "green" then
                local craftable, missing, list = CS.Reagents(r, ui.includeBank)
                local row = { id = rid, r = r, color = col, craftable = craftable, missing = missing, reagents = list }
                if craftable > 0 then m.craftNow[#m.craftNow + 1] = row
                else m.needMats[#m.needMats + 1] = row end
            end
        elseif not (lib.IsHiddenRecipe and lib:IsHiddenRecipe(rid)) then
            if col == "orange" or col == "yellow" or col == "green" then
                local a = acquisition(lib, rid)
                if a.kind ~= "wrongFaction" and (ui.showDrops or a.kind ~= "drop") then
                    m.learn[#m.learn + 1] = { id = rid, r = r, color = col, acq = a }
                end
            elseif col == "locked" then
                local req = r.requiredSkill or (r.difficulty and r.difficulty[1]) or 0
                if req <= skill + (ui.upcomingRange or 25) then
                    local a = acquisition(lib, rid)
                    if a.kind ~= "wrongFaction" and (ui.showDrops or a.kind ~= "drop") then
                        m.upcoming[#m.upcoming + 1] = { id = rid, r = r, color = col, acq = a, req = req }
                    end
                end
            end
        end
    end

    local CO = CS.COLOR_ORDER
    table.sort(m.craftNow, function(a, b)
        if a.color ~= b.color then return CO[a.color] < CO[b.color] end
        return a.craftable > b.craftable
    end)
    table.sort(m.needMats, function(a, b)
        if a.color ~= b.color then return CO[a.color] < CO[b.color] end
        return #a.missing < #b.missing
    end)
    local KIND = { trainer = 1, vendor = 2, quest = 3, container = 4, auto = 5, drop = 6, unknown = 7 }
    table.sort(m.learn, function(a, b)
        if a.acq.kind ~= b.acq.kind then return (KIND[a.acq.kind] or 9) < (KIND[b.acq.kind] or 9) end
        if a.color ~= b.color then return CO[a.color] < CO[b.color] end
        return (a.acq.dist or 1e12) < (b.acq.dist or 1e12)
    end)
    table.sort(m.upcoming, function(a, b) return a.req < b.req end)

    -- ranks
    local cur
    for i, rk in ipairs(CS.RANKS) do if (prof.max or 0) <= rk.max then cur = i break end end
    cur = cur or #CS.RANKS
    m.rank = CS.RANKS[cur]
    m.nextRank = CS.RANKS[cur + 1]
    m.nextRankIndex = cur + 1
    m.playerLevel = S(UnitLevel("player")) or 1
    if m.nextRank then
        m.canTrain = skill >= m.nextRank.reqSkill and m.playerLevel >= m.nextRank.reqLevel
        -- trainers
        local db = CS.DB()
        local list = {}
        for _, id in ipairs(CS.TrainerIds(prof.id)) do
            local npc = CS.NPC(id)
            if npc and not (ui.onlyFriendly and npc.friendly == false) then
                local visited = db.trainers[id]
                local subRank = CS.SubtitleRank(npc.subName)
                local teaches
                if visited and visited.rankTaught then
                    teaches = visited.rankTaught
                elseif subRank then
                    teaches = subRank
                end
                list[#list + 1] = {
                    npc = npc, dist = CS.Distance(npc), teaches = teaches,
                    confirmed = visited and visited.rankTaught ~= nil,
                }
            end
        end
        local need = m.nextRankIndex
        table.sort(list, function(a, b)
            local ga = (a.teaches and a.teaches >= need) and 0 or (a.teaches and 2 or 1)
            local gb = (b.teaches and b.teaches >= need) and 0 or (b.teaches and 2 or 1)
            if ga ~= gb then return ga < gb end
            return (a.dist or 1e12) < (b.dist or 1e12)
        end)
        m.trainers = list
    end
    return m
end

-------------------------------------------------------------------------------
-- frame
-------------------------------------------------------------------------------
local F, scroll, child, tabBar, skillBar, skillText, infoText
local rows, rowCount, tabs = {}, 0, {}
local ROW_H = 14
local current -- selected profession id

local function addTooltipLines(d)
    local GT = GameTooltip
    if d.kind == "recipe" or d.kind == "learn" then
        local row = d.row
        local r = row.r
        GT:AddLine(CS.RecipeName(d.profId, row.id, r), 1, 0.82, 0)
        if r.difficulty then
            local dd = r.difficulty
            GT:AddLine(("|cffff8040%s|r  |cffffff00%s|r  |cff40c040%s|r  |cff808080%s|r"):format(
                dd[1], dd[2], dd[3], dd[4]))
        end
        if r.requiredSkill then GT:AddDoubleLine("Requires", tostring(r.requiredSkill), 1, 1, 1, 1, 1, 1) end
        local list = row.reagents
        if not list then
            local _, _, l = CS.Reagents(r, ui.includeBank)
            list = l
        end
        if #list > 0 then GT:AddLine("Reagents:", 1, 0.82, 0) end
        for _, it in ipairs(list) do
            local ok = it.have >= it.need
            GT:AddDoubleLine("  " .. (CS.ItemName(it.id) or ("item " .. it.id)),
                ("%d / %d"):format(it.have, it.need),
                0.9, 0.9, 0.9, ok and 0.3 or 1, ok and 0.9 or 0.4, ok and 0.3 or 0.4)
        end
        local a = row.acq
        if a then
            GT:AddLine(" ")
            if a.kind == "auto" then
                GT:AddLine("Learned with the profession", 0.7, 0.7, 0.7)
            elseif a.kind == "unknown" then
                GT:AddLine("Source unknown", 0.7, 0.7, 0.7)
            else
                for _, kind in ipairs(SOURCE_ORDER) do
                    local l = a.sources and a.sources[kind]
                    if l and #l > 0 then
                        GT:AddLine(SOURCE_LABEL[kind] .. ((l.total or #l) > #l and (" (%d, showing %d)"):format(l.total, #l) or ""), 1, 0.82, 0)
                        for i, s in ipairs(l) do
                            if i > 5 then GT:AddLine("    ...", 0.6, 0.6, 0.6) break end
                            local npc = (kind == "trainer" or kind == "vendor" or kind == "drop") and CS.NPC(s.id)
                            local nm = (npc and npc.name) or s.name or ("#" .. s.id)
                            local where = npc and npc.zone and (" - %s %s,%s"):format(npc.zone, tostring(npc.x), tostring(npc.y)) or ""
                            local fr = npc and npc.friendly == false and " |cffff6060(hostile)|r" or ""
                            GT:AddLine("    " .. nm .. where .. fr, 0.85, 0.85, 0.85)
                        end
                    end
                end
                if a.borrowed then GT:AddLine("Sources from Classic data (unconfirmed on Forever)", 0.6, 0.6, 0.6, true) end
            end
            local item = CS.Lib().GetRecipeItem and CS.Lib():GetRecipeItem(row.id)
            if item then GT:AddDoubleLine("Recipe item", CS.ItemName(item) or ("#" .. item), 1, 1, 1, 0.8, 0.8, 0.8) end
        end
        if d.kind == "learn" and a and a.npc then GT:AddLine("Click: waypoint to " .. a.npc.name, 0.5, 0.5, 0.5) end
    elseif d.kind == "trainer" then
        local t = d.t
        GT:AddLine(t.npc.name or "?", 1, 0.82, 0)
        if t.npc.subName then GT:AddLine("<" .. t.npc.subName .. ">", 0.8, 0.8, 0.8) end
        if t.npc.zone then GT:AddLine(("%s %s,%s"):format(t.npc.zone, tostring(t.npc.x), tostring(t.npc.y)), 0.4, 0.8, 1) end
        if t.teaches then
            GT:AddLine(("Teaches up to %s%s"):format(CS.RANKS[t.teaches] and CS.RANKS[t.teaches].name or ("rank " .. t.teaches),
                t.confirmed and " (seen at trainer)" or " (from title)"), 1, 1, 1)
        else
            GT:AddLine("Rank taught unknown - visit once to record it", 0.7, 0.7, 0.7)
        end
        GT:AddLine("Click: waypoint", 0.5, 0.5, 0.5)
    elseif d.tip then
        GT:AddLine(d.tip, 1, 1, 1, true)
    end
end

local function getRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r:SetHeight(ROW_H)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 2, 0); r.left:SetJustifyH("LEFT"); r.left:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -2, 0); r.right:SetJustifyH("RIGHT")
    r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnEnter", function(self)
        if not self.data then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local ok = pcall(addTooltipLines, self.data)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        local d = self.data
        if not d then return end
        if d.section then
            ui.collapsed[d.section] = not ui.collapsed[d.section]
            CS.Refresh(true)
        elseif d.kind == "trainer" then
            CS.Waypoint(d.t.npc, CS.PROF_NAMES[current] .. " trainer")
        elseif d.kind == "learn" and d.row.acq and d.row.acq.npc then
            CS.Waypoint(d.row.acq.npc, CS.RecipeName(d.profId, d.row.id, d.row.r))
        end
    end)
    rows[i] = r
    return r
end

local function addRow(left, right, data, indent)
    rowCount = rowCount + 1
    local r = getRow(rowCount)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", child, "TOPLEFT", indent or 0, -(rowCount - 1) * ROW_H)
    r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    r.left:SetText(left or ""); r.right:SetText(right or "")
    r.data = data
    r:Show()
end

local function section(key, title, count)
    local c = ui.collapsed[key]
    addRow(color(GOLD, (c and "+ " or "- ") .. title .. (count and (" (" .. count .. ")") or "")), "", { section = key })
    return not c
end

local function recipeLabel(profId, row)
    return color(CS.COLOR_HEX[row.color] or WHITE, CS.RecipeName(profId, row.id, row.r))
end

local function acqText(a)
    if not a then return "" end
    if a.kind == "trainer" or a.kind == "vendor" then
        local npc = a.npc
        local where = npc and (npc.zone or "?") or "?"
        return color(CYAN, ("%s: %s (%s)"):format(SOURCE_LABEL[a.kind], npc and npc.name or "?", where))
    elseif a.kind == "drop" then
        return color(DIM, ("Drop: %s%s"):format(a.example or "?", (a.count or 0) > 1 and (" +" .. (a.count - 1)) or ""))
    elseif a.kind == "quest" then
        return color(DIM, "Quest reward")
    elseif a.kind == "container" then
        return color(DIM, "Container")
    elseif a.kind == "auto" then
        return color(DIM, "With profession")
    end
    return color(DIM, "Source unknown")
end

local function render(prof)
    rowCount = 0
    local m = CS.BuildModel(prof)
    local maxRows = ui.maxRows or 20

    -- header
    skillBar:SetMinMaxValues(0, math.max(1, prof.max or 1)); skillBar:SetValue(prof.rank or 0)
    skillText:SetText(("%s %d / %d  (%s)"):format(prof.name or CS.PROF_NAMES[prof.id], prof.rank or 0, prof.max or 0,
        m.rank and m.rank.name or "?"))
    local info = {}
    if not m.libReady then
        info[#info + 1] = color(RED, "Recipe database not loaded.")
    elseif not m.scanned then
        info[#info + 1] = color(RED, ("Open your %s window once so I can read your known recipes."):format(prof.name or "profession"))
    end
    if m.nextRank then
        local capped = (prof.rank or 0) >= (prof.max or 0) - 0
        local line = ("Next: %s at %d skill, lvl %d"):format(m.nextRank.name, m.nextRank.reqSkill, m.nextRank.reqLevel)
        if m.canTrain then
            line = color(capped and RED or GREEN, line .. (capped and " - AT CAP, train now!" or " - you can train it"))
        else
            line = color(DIM, line)
        end
        info[#info + 1] = line
    end
    infoText:SetText(table.concat(info, "\n"))

    -- Craft now
    if section("craft", "Craft now (skill-ups, have mats)", #m.craftNow) then
        if #m.craftNow == 0 then addRow(color(DIM, "  nothing craftable that gives skill-ups"), "") end
        for i, row in ipairs(m.craftNow) do
            if i > maxRows then addRow(color(DIM, ("  +%d more"):format(#m.craftNow - maxRows)), "") break end
            addRow(recipeLabel(prof.id, row), color(GREEN, "x" .. row.craftable), { kind = "recipe", row = row, profId = prof.id })
        end
    end
    -- Need mats
    if ui.showNeedMats and #m.needMats > 0 and section("mats", "Skill-ups, missing mats", #m.needMats) then
        for i, row in ipairs(m.needMats) do
            if i > maxRows then addRow(color(DIM, ("  +%d more"):format(#m.needMats - maxRows)), "") break end
            local miss = row.missing[1]
            local txt = miss and (("%d %s"):format(miss.short, CS.ItemName(miss.id) or ("#" .. miss.id))) or ""
            if #row.missing > 1 then txt = txt .. (" +%d"):format(#row.missing - 1) end
            addRow(recipeLabel(prof.id, row), color(RED, txt), { kind = "recipe", row = row, profId = prof.id })
        end
    end
    -- Next rank trainers
    if m.nextRank and m.trainers and section("rank", ("Trainers (next rank: %s)"):format(m.nextRank.name), #m.trainers) then
        local shown = 0
        for _, t in ipairs(m.trainers) do
            shown = shown + 1
            if shown > 8 then break end
            local rk = t.teaches and CS.RANKS[t.teaches] and CS.RANKS[t.teaches].name or "?"
            local good = t.teaches and t.teaches >= m.nextRankIndex
            local left = color(good and GREEN or WHITE, t.npc.name or "?") .. color(DIM, (" (%s%s)"):format(rk, t.confirmed and "" or "?"))
            addRow(left, color(DIM, (t.npc.zone or "?") .. " " .. CS.FormatDistance(t.dist)), { kind = "trainer", t = t })
        end
        if #m.trainers == 0 then addRow(color(DIM, "  no trainer data (needs Questie)"), "") end
    end
    -- Learn now
    if ui.showLearn and section("learn", "Learn now (not known yet)", #m.learn) then
        if #m.learn == 0 then addRow(color(DIM, "  nothing new to learn at your skill"), "") end
        for i, row in ipairs(m.learn) do
            if i > maxRows then addRow(color(DIM, ("  +%d more"):format(#m.learn - maxRows)), "") break end
            local right = ""
            if row.acq.kind == "trainer" or row.acq.kind == "vendor" then right = CS.FormatDistance(row.acq.dist) end
            addRow(recipeLabel(prof.id, row), color(DIM, right), { kind = "learn", row = row, profId = prof.id })
            addRow(acqText(row.acq), "", { kind = "learn", row = row, profId = prof.id }, 10)
        end
    end
    -- Upcoming
    if ui.showUpcoming and #m.upcoming > 0 and section("upcoming", ("Coming up (next %d skill)"):format(ui.upcomingRange or 25), #m.upcoming) then
        for i, row in ipairs(m.upcoming) do
            if i > maxRows then addRow(color(DIM, ("  +%d more"):format(#m.upcoming - maxRows)), "") break end
            addRow(color(DIM, CS.RecipeName(prof.id, row.id, row.r)), color(DIM, "at " .. row.req), { kind = "learn", row = row, profId = prof.id })
        end
    end

    for i = rowCount + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
    child:SetHeight(math.max(1, rowCount * ROW_H))
    child:SetWidth(scroll:GetWidth())
    local maxScroll = math.max(0, rowCount * ROW_H - scroll:GetHeight())
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
end

local function renderTabs(profs)
    for _, t in ipairs(tabs) do t:Hide() end
    local x = 0
    for i, p in ipairs(profs) do
        local t = tabs[i]
        if not t then
            t = CreateFrame("Button", nil, tabBar)
            t:SetHeight(18)
            t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetAllPoints()
            t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t.text:SetPoint("CENTER")
            t:SetScript("OnClick", function(self) current = self.profId; ui.lastTab = self.profId; CS.Refresh(true) end)
            tabs[i] = t
        end
        t.profId = p.id
        t.text:SetText(("%s %d"):format(p.name or CS.PROF_NAMES[p.id], p.rank or 0))
        local w = (t.text:GetStringWidth() or 60) + 16
        t:SetWidth(w)
        t:ClearAllPoints(); t:SetPoint("LEFT", tabBar, "LEFT", x, 0)
        x = x + w + 4
        if p.id == current then t.bg:SetColorTexture(0.9, 0.6, 0.1, 0.35) else t.bg:SetColorTexture(1, 1, 1, 0.08) end
        t:Show()
    end
end

local function savePos()
    local p, _, rp, x, y = F:GetPoint(1)
    ui.point = { p, rp, x, y }
    ui.w, ui.h = F:GetWidth(), F:GetHeight()
end

local function createFrame()
    F = CreateFrame("Frame", "CraftScoutFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    F:SetSize(ui.w, ui.h)
    if ui.point then F:SetPoint(ui.point[1], UIParent, ui.point[2], ui.point[3], ui.point[4])
    else F:SetPoint("LEFT", UIParent, "LEFT", 60, 0) end
    F:SetFrameStrata("MEDIUM"); F:SetClampedToScreen(true); F:SetMovable(true); F:SetResizable(true)
    if F.SetResizeBounds then F:SetResizeBounds(260, 200, 800, 1400) elseif F.SetMinResize then F:SetMinResize(260, 200) end
    if F.SetBackdrop then
        F:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        F:SetBackdropColor(0, 0, 0, ui.alpha); F:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    end

    local title = CreateFrame("Button", nil, F)
    title:SetPoint("TOPLEFT", 4, -4); title:SetPoint("TOPRIGHT", -26, -4); title:SetHeight(16)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() if not ui.locked then F:StartMoving() end end)
    title:SetScript("OnDragStop", function() F:StopMovingOrSizing(); savePos() end)
    local tt = title:CreateFontString(nil, "OVERLAY", "GameFontNormal"); tt:SetPoint("LEFT", 2, 0); tt:SetText("CraftScout")

    local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        ui.shown = false; F:Hide()
        msg("hidden - /craftscout to show it again")
    end)

    tabBar = CreateFrame("Frame", nil, F)
    tabBar:SetPoint("TOPLEFT", 6, -22); tabBar:SetPoint("TOPRIGHT", -6, -22); tabBar:SetHeight(18)

    skillBar = CreateFrame("StatusBar", nil, F)
    skillBar:SetPoint("TOPLEFT", 6, -44); skillBar:SetPoint("TOPRIGHT", -6, -44); skillBar:SetHeight(14)
    skillBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    skillBar:SetStatusBarColor(0.8, 0.55, 0.1, 1)
    local bg = skillBar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    skillText = skillBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); skillText:SetPoint("CENTER")

    infoText = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", skillBar, "BOTTOMLEFT", 0, -3)
    infoText:SetPoint("TOPRIGHT", skillBar, "BOTTOMRIGHT", 0, -3)
    infoText:SetJustifyH("LEFT")

    scroll = CreateFrame("ScrollFrame", nil, F)
    scroll:SetPoint("TOPLEFT", 6, -90); scroll:SetPoint("BOTTOMRIGHT", -6, 10)
    child = CreateFrame("Frame", nil, scroll); child:SetSize(ui.w - 12, 10)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_H * 3)))
    end)
    scroll:SetScript("OnSizeChanged", function() child:SetWidth(scroll:GetWidth()) end)

    local grip = CreateFrame("Button", nil, F)
    grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() if not ui.locked then F:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() F:StopMovingOrSizing(); savePos(); CS.Refresh(true) end)
    F.grip = grip
    grip:SetShown(not ui.locked)
    F:SetShown(ui.shown)
end

-------------------------------------------------------------------------------
-- refresh (throttled, with a watchdog in case the client drops our timer)
-------------------------------------------------------------------------------
local pending, pendingAt = false, 0
function CS.Refresh(immediate)
    if not F or not F:IsShown() then return end
    local function go()
        pending = false
        local ok, err = pcall(function()
            local profs = CS.GetPlayerProfessions()
            -- crafting professions with recipe data first; gathering ones have no recipes
            local craft = {}
            for _, p in ipairs(profs) do
                if CS.Lib() and CS.Lib():GetRecipes(p.id) then craft[#craft + 1] = p end
            end
            local found
            for _, p in ipairs(craft) do if p.id == current then found = p end end
            if not found then
                for _, p in ipairs(craft) do if p.id == ui.lastTab then found = p end end
                found = found or craft[1]
                current = found and found.id
            end
            renderTabs(craft)
            if found then
                render(found)
            else
                rowCount = 0
                skillText:SetText("No crafting profession learned")
                infoText:SetText("")
                for i = 1, #rows do rows[i]:Hide() end
            end
        end)
        if not ok then CS.LogError("render", err) end
    end
    if immediate then go() return end
    if pending and (GetTime() - pendingAt) < 3 then return end
    pending, pendingAt = true, GetTime()
    C_Timer.After(0.5, go)
end

function CS.SetShown(v)
    if not F then return end
    ui.shown = v and true or false
    F:SetShown(ui.shown)
    if ui.shown then CS.Refresh(true) end
end
function CS.ApplyLock() if F then F.grip:SetShown(not ui.locked) end end
function CS.SetAlpha(a) ui.alpha = a; if F and F.SetBackdropColor then F:SetBackdropColor(0, 0, 0, a) end end
function CS.ResetPosition()
    ui.point = nil; ui.w, ui.h = CS.DEFAULTS.w, CS.DEFAULTS.h
    F:ClearAllPoints(); F:SetPoint("LEFT", UIParent, "LEFT", 60, 0); F:SetSize(ui.w, ui.h)
    CS.Refresh(true)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    initUI()
    local ok, err = pcall(createFrame)
    if not ok then msg("window failed to build: " .. tostring(err)) return end
    -- Questie needs a few seconds to start; NPC data appears after that
    C_Timer.After(2, function() CS.Refresh(true) end)
    C_Timer.After(15, function() CS.Refresh(true) end)
end)

-------------------------------------------------------------------------------
-- slash + addon compartment
-------------------------------------------------------------------------------
SLASH_CRAFTSCOUT1 = "/craftscout"
SLASH_CRAFTSCOUT2 = "/cscout"
SlashCmdList.CRAFTSCOUT = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "" or arg == "ui" then
        CS.SetShown(not (F and F:IsShown()))
    elseif arg == "config" or arg == "options" then
        if CS.OpenOptions then CS.OpenOptions() end
    elseif arg == "scan" then
        local pid, n = CS.ScanOpenProfession()
        if pid then msg(("scanned %s: %d known recipes"):format(CS.PROF_NAMES[pid], n)) else msg("open a profession window first") end
        CS.Refresh(true)
    elseif arg == "resetui" then
        CS.ResetPosition()
    elseif arg == "trainers" then
        local n = 0
        for _, t in pairs(CS.DB().trainers) do
            n = n + 1
            print(("  %s - %s, rank %s (%s)"):format(tostring(t.name), CS.PROF_NAMES[t.prof] or "?",
                t.rankTaught and CS.RANKS[t.rankTaught] and CS.RANKS[t.rankTaught].name or "?", tostring(t.zone)))
        end
        msg(n .. " trainers recorded")
    else
        msg("/craftscout [ui|config|scan|trainers|resetui]")
    end
end

function CraftScout_OnCompartmentClick(_, button)
    if button == "RightButton" and CS.OpenOptions then CS.OpenOptions()
    else CS.SetShown(not (F and F:IsShown())) end
end
