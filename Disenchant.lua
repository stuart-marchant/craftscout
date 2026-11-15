-- CraftScout disenchant tooltips: what an item disenchants into, whether any of
-- that is a mat your Enchanting skill-ups need, and a sell / disenchant hint.
--
-- Data: DisenchantForever (MIT, APGM82): Forever client disenchant brackets
-- (class / quality / item level), Classic-derived odds, plus no-disenchant and
-- special-loot item lists. Odds are Classic estimates, not measured on Forever.

local _, ns = ...
local CS = CraftScout
if not CS then return end
local S, try = CS.S, CS.try

local ENCHANTING = 333

-- Classic skill needed to disenchant, by item level (Forever not confirmed)
local function requiredSkill(quality, ilvl)
    if quality == 4 then
        if ilvl <= 60 then return 225 end
        return 300
    end
    if ilvl <= 20 then return 1 end
    if ilvl <= 25 then return 25 end
    if ilvl <= 60 then return 25 * math.ceil((ilvl - 20) / 5) end
    return 225
end

-- lesser <-> greater essences convert 3:1, so a need for one counts for the other
local function essencePartner(itemId)
    local M = ns.materials
    local p = M and M.pairs and M.pairs[itemId]
    return p and p[1]
end

local function matName(id)
    return CS.ItemName(id) or (ns.materials and ns.materials.names and ns.materials.names[id]) or ("item " .. id)
end

-------------------------------------------------------------------------------
-- what my Enchanting skill-ups need (cached; invalidated by refresh events)
-------------------------------------------------------------------------------
local needsCache, needsAt = nil, 0

function CS.InvalidateDENeeds() needsCache = nil end

function CS.EnchantingNeeds()
    if needsCache and GetTime() - needsAt < 10 then return needsCache end
    local out = { has = false, skill = nil, mats = {} }
    for _, p in ipairs(CS.GetPlayerProfessions()) do
        if p.id == ENCHANTING then out.has, out.skill = true, p.rank end
    end
    local lib, cdb = CS.Lib(), CS.CharDB()
    if out.has and lib and cdb then
        local known = cdb.known[ENCHANTING] or {}
        local ui = CS.GetUI and CS.GetUI() or {}
        for rid, r in pairs(lib:GetRecipes(ENCHANTING) or {}) do
            local isKnown = known[rid] or (lib.IsAutoTaughtRecipe and lib:IsAutoTaughtRecipe(rid))
            local col = CS.Color(r, out.skill or 0)
            if isKnown and (col == "orange" or col == "yellow" or col == "green") and type(r.reagents) == "table" then
                for mat, n in pairs(r.reagents) do
                    local have = CS.ItemCount(mat, ui.includeBank)
                    local e = out.mats[mat] or { recipes = {}, short = false }
                    out.mats[mat] = e
                    e.recipes[#e.recipes + 1] = { id = rid, r = r, color = col, need = n }
                    if have < n then e.short = true end
                end
            end
        end
        local CO = CS.COLOR_ORDER
        for _, e in pairs(out.mats) do
            table.sort(e.recipes, function(a, b) return CO[a.color] < CO[b.color] end)
        end
    end
    out.scanned = cdb and cdb.known[ENCHANTING] ~= nil
    needsCache, needsAt = out, GetTime()
    return out
end

local function needFor(needs, mat)
    local e = needs.mats[mat]
    if e then return e end
    local partner = essencePartner(mat)
    return partner and needs.mats[partner] or nil
end

-------------------------------------------------------------------------------
-- item -> disenchant info
-------------------------------------------------------------------------------
local function itemInfo(item)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name, link, quality, ilvl, _, _, _, _, slot, _, vendor, classID, subclassID = pcall(fn, item)
    if not ok then return nil end
    name, quality, ilvl, slot, vendor, classID = S(name), S(quality), S(ilvl), S(slot), S(vendor), S(classID)
    if not name or type(ilvl) ~= "number" then return nil end
    if quality ~= 2 and quality ~= 3 and quality ~= 4 then return nil end
    if classID ~= 2 and classID ~= 4 then return nil end
    if type(slot) ~= "string" or slot == "" or slot == "INVTYPE_BODY" or slot == "INVTYPE_TABARD" or slot == "INVTYPE_BAG" then
        return nil
    end
    local levelFn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if levelFn then
        local okL, lvl = pcall(levelFn, item)
        lvl = okL and S(lvl)
        if type(lvl) == "number" and lvl >= 1 then ilvl = lvl end
    end
    return { name = name, quality = quality, ilvl = math.floor(ilvl), classID = classID,
             subclassID = S(subclassID), vendor = type(vendor) == "number" and vendor or 0 }
end

-- returns a model for the tooltip, or nil when the item can't be disenchanted
function CS.DisenchantModel(item, itemId)
    local M = ns.materials
    if not (M and M.Find) then return nil end
    if itemId and ns.noDisenchant and ns.noDisenchant[itemId] then return nil end
    local info = itemInfo(item)
    if not info then return nil end
    local special = itemId and ns.ownLoot and ns.ownLoot[itemId]
    local row = (not special) and M.Find(info.classID, info.quality, info.ilvl)
    if not row and not special then return nil end
    local m = { info = info, special = special, row = row, outcomes = {},
                reqSkill = requiredSkill(info.quality, info.ilvl) }
    if row then
        for i = 3, #row do
            local chance, lo, hi, mat = unpack(row[i])
            m.outcomes[#m.outcomes + 1] = { chance = chance, lo = lo, hi = hi, mat = mat }
        end
        m.unconfirmed = row.unconfirmed
    end
    return m
end

local function fmtCoin(c)
    if not c or c <= 0 then return "0c" end
    if GetCoinTextureString then
        local s = try(GetCoinTextureString, c)
        if s then return s end
    end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return ("%dg %ds"):format(g, s) end
    if s > 0 then return ("%ds %dc"):format(s, cp) end
    return ("%dc"):format(cp)
end

-- optional market prices (Auctionator), copper per item
local function marketPrice(itemId)
    local A = Auctionator and Auctionator.API and Auctionator.API.v1
    if A and A.GetAuctionPriceByItemID then
        return S(try(A.GetAuctionPriceByItemID, "CraftScout", itemId))
    end
end

-------------------------------------------------------------------------------
-- tooltip
-------------------------------------------------------------------------------
local function addLines(tt, item, itemId)
    local ui = CS.GetUI and CS.GetUI()
    if not ui or not ui.deTooltip then return end
    local needs = CS.EnchantingNeeds()
    if ui.deOnlyEnchanters and not needs.has then return end
    local m = CS.DisenchantModel(item, itemId)
    if not m then return end

    tt:AddLine(" ")
    tt:AddLine(("Disenchant (item level %d)%s"):format(m.info.ilvl, m.unconfirmed and " - unconfirmed bracket" or ""), 0.75, 0.55, 1)
    if m.special then
        tt:AddLine("  Disenchants into its own special loot", 0.8, 0.8, 0.8)
        return
    end

    local neededHits = {}
    local deValue, priced = 0, true
    for _, o in ipairs(m.outcomes) do
        local qty = o.lo == o.hi and tostring(o.lo) or (o.lo .. "-" .. o.hi)
        local e = needs.has and needFor(needs, o.mat)
        local r, g, b = 0.85, 0.85, 0.85
        local mark = ""
        if e then
            r, g, b = 0.3, 1, 0.3
            mark = e.short and "  |cff40ff40needed|r" or "  |cff80c080used|r"
            neededHits[#neededHits + 1] = { o = o, e = e }
        end
        tt:AddLine(("  %d%%  %s x %s%s"):format(o.chance, qty, matName(o.mat), mark), r, g, b)
        local p = marketPrice(o.mat)
        if p then deValue = deValue + o.chance / 100 * (o.lo + o.hi) / 2 * p else priced = false end
    end

    if needs.has and needs.skill and needs.skill < m.reqSkill then
        tt:AddLine(("  Needs %d Enchanting to disenchant (you have %d)"):format(m.reqSkill, needs.skill), 1, 0.4, 0.4)
    end
    if not ui.deAdvice then return end

    -- advice
    local vendor = m.info.vendor or 0
    local canDE = needs.has and (not needs.skill or needs.skill >= m.reqSkill)
    -- a hit only counts if it's the likely outcome (>= 20%) or the item is blue/purple (always shards)
    local strongHit
    for _, h in ipairs(neededHits) do
        if h.o.chance >= 20 then strongHit = h break end
    end
    if canDE and strongHit then
        local top = strongHit.e.recipes[1]
        local rname = top and CS.RecipeName(ENCHANTING, top.id, top.r) or "a skill-up"
        local hex = top and CS.COLOR_HEX[top.color] or "ffffffff"
        tt:AddLine(("Disenchant: %s for |c%s%s|r%s"):format(matName(strongHit.o.mat), hex, rname,
            #strongHit.e.recipes > 1 and (" (+%d more)"):format(#strongHit.e.recipes - 1) or ""), 0.3, 1, 0.3, true)
    elseif priced and deValue > 0 and canDE then
        if deValue > vendor then
            tt:AddLine(("Disenchant: mats worth ~%s vs vendor %s"):format(fmtCoin(math.floor(deValue)), fmtCoin(vendor)), 0.3, 1, 0.3, true)
        else
            tt:AddLine(("Sell: vendor %s vs mats ~%s"):format(fmtCoin(vendor), fmtCoin(math.floor(deValue))), 1, 0.82, 0, true)
        end
    elseif vendor > 0 then
        if not needs.scanned and needs.has then
            tt:AddLine("Open your Enchanting window once so I can check your skill-up mats", 0.7, 0.7, 0.7, true)
        else
            if #neededHits > 0 and canDE then
                tt:AddLine(("Sell: vendor %s - a needed mat only comes %d%% of the time"):format(
                    fmtCoin(vendor), neededHits[1].o.chance), 1, 0.82, 0, true)
            else
                tt:AddLine(("Sell: vendor %s - no skill-up of yours needs these mats"):format(fmtCoin(vendor)), 1, 0.82, 0, true)
            end
        end
    end
end

local function itemFromTooltip(tt, data)
    local itemId = data and S(data.id)
    local link
    if tt.GetItem then
        local _, l, id = try(tt.GetItem, tt)
        link = S(l)
        itemId = itemId or S(id)
    end
    if type(itemId) ~= "number" and link then itemId = tonumber(link:match("item:(%d+)")) end
    return link or itemId, itemId
end

local function onTooltip(tt, data)
    if not tt or not tt.AddLine then return end
    if tt.IsForbidden and tt:IsForbidden() then return end
    local ok, err = pcall(function()
        local item, itemId = itemFromTooltip(tt, data)
        if item then addLines(tt, item, itemId) end
    end)
    if not ok then CS.LogError("detooltip", err) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tt) onTooltip(tt) end)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) onTooltip(tt) end) end
end

-- invalidate the needs cache when bags / skills / known recipes change
local ev = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "TRADE_SKILL_LIST_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() needsCache = nil end)
