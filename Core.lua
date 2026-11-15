-- CraftScout core: data access (LibProfessionDB, Questie, client), scanning,
-- trainer capture, waypoints. UI lives in UI.lua, options in Options.lua.

local ADDON = ...
local CS = {}
_G.CraftScout = CS
CS.VERSION = "0.2.0"

-------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------
local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) and true or false end
local function S(v) if isSecret(v) then return nil end return v end
local function try(f, ...)
    if type(f) ~= "function" then return end
    return (function(ok, ...) if ok then return ... end end)(pcall(f, ...))
end
local function msg(...) print("|cffe0a040CraftScout|r:", ...) end
CS.S, CS.try, CS.msg, CS.isSecret = S, try, msg, isSecret

function CS.round(x, n)
    if type(x) ~= "number" then return x end
    local m = 10 ^ (n or 1)
    return math.floor(x * m + 0.5) / m
end

-------------------------------------------------------------------------------
-- professions
-------------------------------------------------------------------------------
-- LibProfessionDB keys professions by skill line id
CS.PROF_NAMES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [185] = "Cooking", [333] = "Enchanting",
    [202] = "Engineering", [129] = "First Aid", [356] = "Fishing", [165] = "Leatherworking",
    [186] = "Mining", [197] = "Tailoring", [182] = "Herbalism", [393] = "Skinning",
}
local NAME_TO_ID = {}
for id, n in pairs(CS.PROF_NAMES) do NAME_TO_ID[n:lower()] = id end
function CS.ProfIdByName(name)
    return name and NAME_TO_ID[tostring(name):lower()] or nil
end

-- words used in NPC subtitles / trainer services for each profession
CS.PROF_WORDS = {
    [197] = { "Tailor" }, [333] = { "Enchant" }, [171] = { "Alchemist", "Alchemy" },
    [164] = { "Blacksmith", "Armorsmith", "Weaponsmith" }, [202] = { "Engineer" },
    [165] = { "Leatherwork" }, [185] = { "Cook", "Chef" }, [129] = { "First Aid", "Physician", "Surgeon" },
    [186] = { "Mining", "Miner" }, [356] = { "Fish" }, [182] = { "Herbalis" }, [393] = { "Skinn" },
}

-- Classic rank rules (Forever appears to keep them; shown as "classic rules" in UI)
CS.RANKS = {
    { name = "Apprentice", max = 75,  reqSkill = 0,   reqLevel = 5 },
    { name = "Journeyman", max = 150, reqSkill = 50,  reqLevel = 10 },
    { name = "Expert",     max = 225, reqSkill = 125, reqLevel = 20 },
    { name = "Artisan",    max = 300, reqSkill = 200, reqLevel = 35 },
}
CS.RANK_INDEX = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4, Master = 5 }

-- learned professions: { {id, name, rank, max} }
function CS.GetPlayerProfessions()
    local out, seen = {}, {}
    if GetProfessions and GetProfessionInfo then
        local list = { try(GetProfessions) }
        for i = 1, 6 do
            local idx = list[i]
            if idx then
                local name, _, rank, max, _, _, skillLine = try(GetProfessionInfo, idx)
                name, rank, max, skillLine = S(name), S(rank), S(max), S(skillLine)
                local id = (skillLine and CS.PROF_NAMES[skillLine] and skillLine) or CS.ProfIdByName(name)
                if id and not seen[id] then
                    seen[id] = true
                    out[#out + 1] = { id = id, name = name or CS.PROF_NAMES[id], rank = rank or 0, max = max or 0 }
                end
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- saved data
-------------------------------------------------------------------------------
-- CraftScoutDB (account): { ui = {...}, trainers = { [npcId] = {...} } }
-- CraftScoutCharDB (character): { known = { [profId] = { [recipeId] = true } }, scannedAt = {} }
local db, cdb
function CS.InitDB()
    CraftScoutDB = CraftScoutDB or {}
    CraftScoutCharDB = CraftScoutCharDB or {}
    db, cdb = CraftScoutDB, CraftScoutCharDB
    db.trainers = db.trainers or {}
    db.ui = db.ui or {}
    cdb.known = cdb.known or {}
    cdb.scannedAt = cdb.scannedAt or {}
    cdb.errors = cdb.errors or {}
end
function CS.DB() return db end
function CS.CharDB() return cdb end

function CS.LogError(where, err)
    if not cdb then return end
    cdb.errors[#cdb.errors + 1] = { time(), where, tostring(err) }
    while #cdb.errors > 50 do table.remove(cdb.errors, 1) end
end

-------------------------------------------------------------------------------
-- recipe DB
-------------------------------------------------------------------------------
function CS.Lib()
    local lib = LibStub and LibStub("LibProfessionDB-1.0", true)
    if lib and lib.IsReady and lib:IsReady() then return lib end
end

-- recipe -> profession lookup (built lazily)
local recipeProf
function CS.ProfForRecipe(recipeId)
    local lib = CS.Lib()
    if not lib then return nil end
    if not recipeProf then
        recipeProf = {}
        for profId in pairs(CS.PROF_NAMES) do
            local t = lib:GetRecipes(profId)
            if t then for rid in pairs(t) do recipeProf[rid] = profId end end
        end
    end
    return recipeProf[recipeId]
end

-- name of a recipe (spell) / item, with async load requests
local requested = {}
function CS.SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = try(C_Spell.GetSpellInfo, id)
        if type(info) == "table" and S(info.name) then return info.name end
        if not requested["s" .. id] and C_Spell.RequestLoadSpellData then
            requested["s" .. id] = true
            try(C_Spell.RequestLoadSpellData, id)
        end
    elseif GetSpellInfo then
        local n = try(GetSpellInfo, id)
        if n then return n end
    end
end

function CS.ItemName(id)
    if not id then return nil end
    local n
    if C_Item and C_Item.GetItemNameByID then n = try(C_Item.GetItemNameByID, id) end
    if not n and C_Item and C_Item.GetItemInfo then n = try(C_Item.GetItemInfo, id) end
    if not n and GetItemInfo then n = try(GetItemInfo, id) end
    if n then return S(n) end
    if not requested["i" .. id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested["i" .. id] = true
        try(C_Item.RequestLoadItemDataByID, id)
    end
end

function CS.RecipeName(profId, recipeId, r)
    local n = CS.SpellName(recipeId)
    if n then return n end
    r = r or (CS.Lib() and CS.Lib():GetRecipe(profId, recipeId))
    if r and r.name then return r.name end
    if r and r.craftedItemId then
        local iname = CS.ItemName(r.craftedItemId)
        if iname then return iname end
    end
    return "Recipe #" .. tostring(recipeId)
end

-- difficulty colour for a recipe at a skill level
-- returns "orange"|"yellow"|"green"|"gray"|"locked"
function CS.Color(r, skill)
    local d = r and r.difficulty
    if type(d) ~= "table" or not d[4] then return "unknown" end
    local req = r.requiredSkill or d[1] or 0
    if skill < req then return "locked" end
    if skill >= d[4] then return "gray" end
    if skill >= d[3] then return "green" end
    if skill >= d[2] then return "yellow" end
    return "orange"
end
CS.COLOR_ORDER = { orange = 1, yellow = 2, green = 3, unknown = 4, gray = 5, locked = 6 }
CS.COLOR_HEX = { orange = "ffff8040", yellow = "ffffff00", green = "ff40c040", gray = "ff808080",
                 locked = "ffc04040", unknown = "ffd0d0d0" }

-------------------------------------------------------------------------------
-- inventory
-------------------------------------------------------------------------------
function CS.ItemCount(itemId, includeBank)
    if C_Item and C_Item.GetItemCount then
        return S(try(C_Item.GetItemCount, itemId, includeBank and true or false, false)) or 0
    end
    if GetItemCount then return S(try(GetItemCount, itemId, includeBank and true or false)) or 0 end
    return 0
end

-- craftable count + missing reagents
function CS.Reagents(r, includeBank)
    local craftable, missing, list = math.huge, {}, {}
    if type(r) ~= "table" or type(r.reagents) ~= "table" then return 0, missing, list end
    for itemId, need in pairs(r.reagents) do
        local have = CS.ItemCount(itemId, includeBank)
        list[#list + 1] = { id = itemId, need = need, have = have }
        craftable = math.min(craftable, math.floor(have / need))
        if have < need then missing[#missing + 1] = { id = itemId, short = need - have } end
    end
    if craftable == math.huge then craftable = 0 end
    table.sort(list, function(a, b) return a.id < b.id end)
    return craftable, missing, list
end

-------------------------------------------------------------------------------
-- Questie bridge (NPC names, subtitles, spawns, faction)
-------------------------------------------------------------------------------
local Q = {}
CS.Q = Q
function CS.QuestieReady()
    if not (QuestieLoader and Questie and Questie.started) then return false end
    if not Q.DB then
        Q.DB = try(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
        Q.Zone = try(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    end
    return Q.DB ~= nil and Q.DB.GetNPC ~= nil
end

local npcCache = {}
-- { id, name, subName, friendly, areaId, zone, x, y, uiMap }
function CS.NPC(id)
    if npcCache[id] ~= nil then return npcCache[id] or nil end
    local lib = CS.Lib()
    local out = { id = id, name = lib and lib:GetSourceName(id) }
    if CS.QuestieReady() then
        local n = try(Q.DB.GetNPC, Q.DB, id)
        if type(n) == "table" then
            out.name = n.name or out.name
            out.subName = n.subName
            out.friendly = n.friendly
            if type(n.spawns) == "table" then
                -- prefer a spawn in a real zone (some list instance copies)
                for areaId, coords in pairs(n.spawns) do
                    if type(coords) == "table" and coords[1] and coords[1][1] and coords[1][1] >= 0 then
                        out.areaId, out.x, out.y = areaId, coords[1][1], coords[1][2]
                        break
                    end
                end
            end
        end
    else
        -- Questie may not be ready yet; don't cache the partial result
        return out
    end
    if out.areaId then
        out.zone = C_Map and S(try(C_Map.GetAreaInfo, out.areaId))
        if Q.Zone and Q.Zone.GetUiMapIdByAreaId then
            out.uiMap = try(Q.Zone.GetUiMapIdByAreaId, Q.Zone, out.areaId)
        end
    end
    npcCache[id] = out
    return out
end

-------------------------------------------------------------------------------
-- distance (world coordinates; different continent = far)
-------------------------------------------------------------------------------
local function worldPos(uiMap, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and uiMap and x and y) then return end
    local cont, pos = try(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(x, y))
    if cont and pos then
        local px, py = pos:GetXY()
        return cont, px, py
    end
end

local playerPos = {}
function CS.UpdatePlayerPos()
    playerPos = {}
    local m = C_Map and S(try(C_Map.GetBestMapForUnit, "player"))
    if not m then return end
    local p = try(C_Map.GetPlayerMapPosition, m, "player")
    if p and p.GetXY then
        local x, y = p:GetXY()
        if S(x) and S(y) then
            playerPos.cont, playerPos.x, playerPos.y = worldPos(m, x, y)
        end
    end
end

-- yards-ish distance, or nil if unknown; huge if other continent
function CS.Distance(npc)
    if not (npc and npc.uiMap and playerPos.cont) then return nil end
    if npc.wcont == nil then
        npc.wcont, npc.wx, npc.wy = worldPos(npc.uiMap, npc.x / 100, npc.y / 100)
        npc.wcont = npc.wcont or false
    end
    if not npc.wcont then return nil end
    if npc.wcont ~= playerPos.cont then return 1e9 end
    local dx, dy = npc.wx - playerPos.x, npc.wy - playerPos.y
    return math.sqrt(dx * dx + dy * dy)
end

function CS.FormatDistance(d)
    if not d then return "" end
    if d >= 1e9 then return "other continent" end
    if d >= 1000 then return ("%.1fk yd"):format(d / 1000) end
    return ("%d yd"):format(d)
end

-------------------------------------------------------------------------------
-- waypoints
-------------------------------------------------------------------------------
function CS.Waypoint(npc, label)
    if not (npc and npc.uiMap and npc.x and npc.y) then
        msg("no known location for " .. tostring(npc and npc.name or label))
        return
    end
    local title = (label and (label .. ": ") or "") .. (npc.name or "?")
    if TomTom and TomTom.AddWaypoint then
        try(TomTom.AddWaypoint, TomTom, npc.uiMap, npc.x / 100, npc.y / 100,
            { title = title, persistent = false, minimap = true, world = true, from = "CraftScout" })
        msg(("TomTom -> %s (%s %.1f, %.1f)"):format(title, npc.zone or "?", npc.x, npc.y))
    elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        local pt = try(UiMapPoint.CreateFromCoordinates, npc.uiMap, npc.x / 100, npc.y / 100)
        if pt then try(C_Map.SetUserWaypoint, pt) end
        msg(("map pin -> %s (%s %.1f, %.1f)"):format(title, npc.zone or "?", npc.x, npc.y))
    end
end

-------------------------------------------------------------------------------
-- known-recipe scan (profession window open)
-------------------------------------------------------------------------------
local function openProfession()
    local T = C_TradeSkillUI
    if not T then return end
    local child = T.GetChildProfessionInfo and try(T.GetChildProfessionInfo)
    if type(child) == "table" and child.professionID and child.professionID ~= 0
        and child.professionName and child.professionName ~= "" then
        return child
    end
    local base = T.GetBaseProfessionInfo and try(T.GetBaseProfessionInfo)
    if type(base) == "table" and base.professionName and base.professionName ~= "" then return base end
end

function CS.ScanOpenProfession()
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeInfo) or not cdb then return end
    if T.IsTradeSkillLinked and try(T.IsTradeSkillLinked) then return end
    if T.IsNPCCrafting and try(T.IsNPCCrafting) then return end
    if T.IsDataSourceChanging and try(T.IsDataSourceChanging) then return end
    local p = openProfession()
    if not p then return end
    local profId = (CS.PROF_NAMES[p.professionID] and p.professionID)
        or CS.ProfIdByName(p.parentProfessionName) or CS.ProfIdByName(p.professionName)
    if not profId then return end
    local listFn = T.GetAllRecipeIDs or T.GetFilteredRecipeIDs
    if not listFn then return end
    local ids = try(listFn) or {}
    local known = cdb.known[profId] or {}
    local n = 0
    for _, id in ipairs(ids) do
        local info = try(T.GetRecipeInfo, id)
        if type(info) == "table" and info.learned and not info.isDummyRecipe and not info.isGatheringRecipe then
            -- skip recipes the DB places in a different profession (list may lag a switch)
            local owner = CS.ProfForRecipe(id)
            if not owner or owner == profId then
                known[id] = true
                n = n + 1
            end
        end
    end
    if n > 0 then
        cdb.known[profId] = known  -- additive merge: a filtered list can't remove recipes
        cdb.scannedAt[profId] = time()
    end
    return profId, n
end

function CS.MarkLearned(recipeId)
    if not cdb or not recipeId then return end
    local profId = CS.ProfForRecipe(recipeId)
    if not profId then return end
    cdb.known[profId] = cdb.known[profId] or {}
    cdb.known[profId][recipeId] = true
end

-------------------------------------------------------------------------------
-- trainer capture (authoritative data from trainers you visit)
-------------------------------------------------------------------------------
local function npcIdFromGUID(guid)
    if not guid or isSecret(guid) then return nil end
    local id = select(6, strsplit("-", guid))
    return tonumber(id)
end

function CS.CaptureTrainer()
    if not db or not GetNumTrainerServices then return end
    local n = S(try(GetNumTrainerServices)) or 0
    if n == 0 then return end
    local npcId = npcIdFromGUID(try(UnitGUID, "npc"))
    local name = S(try(UnitName, "npc"))
    local votes, services, rankTaught = {}, {}, 0
    for i = 1, n do
        local sname, ssub, stype = try(GetTrainerServiceInfo, i)
        sname = S(sname)
        if sname and stype ~= "header" then
            local skillName, reqRank = try(GetTrainerServiceSkillReq, i)
            skillName, reqRank = S(skillName), S(reqRank)
            local pid = CS.ProfIdByName(skillName)
            if pid then votes[pid] = (votes[pid] or 0) + 1 end
            local cost = GetTrainerServiceCost and S(try(GetTrainerServiceCost, i))
            local lvl = GetTrainerServiceLevelReq and S(try(GetTrainerServiceLevelReq, i))
            services[#services + 1] = { name = sname, sub = S(ssub), type = S(stype),
                                        reqSkill = reqRank, reqLevel = lvl, cost = cost }
            local rk = sname:match("^(%a+) ")
            if rk and CS.RANK_INDEX[rk] then rankTaught = math.max(rankTaught, CS.RANK_INDEX[rk]) end
        end
    end
    local prof, best = nil, 0
    for pid, v in pairs(votes) do if v > best then prof, best = pid, v end end
    if not prof then
        -- no skill requirement info: guess from service names
        for _, s in ipairs(services) do
            for pid, words in pairs(CS.PROF_WORDS) do
                for _, w in ipairs(words) do
                    if s.name:find(w) then prof = pid break end
                end
                if prof then break end
            end
            if prof then break end
        end
    end
    if not prof then return end
    local key = npcId or name
    if not key then return end
    db.trainers[key] = {
        npcId = npcId, name = name, prof = prof, seen = time(),
        rankTaught = rankTaught > 0 and rankTaught or nil,
        zone = S(try(GetRealZoneText)), services = services,
    }
    if CS.Refresh then CS.Refresh() end
end

-------------------------------------------------------------------------------
-- trainers for a profession (union of recipe trainer sources + visited)
-------------------------------------------------------------------------------
local trainerIdsByProf = {}
function CS.TrainerIds(profId)
    if trainerIdsByProf[profId] then return trainerIdsByProf[profId] end
    local lib, set = CS.Lib(), {}
    if lib and lib.sources then
        local recipes = lib:GetRecipes(profId) or {}
        for rid in pairs(recipes) do
            local src = lib.sources[rid]
            if src and src.t then for _, id in ipairs(src.t) do set[id] = true end end
        end
    end
    if db then
        for key, t in pairs(db.trainers) do
            if t.prof == profId and t.npcId then set[t.npcId] = true end
        end
    end
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    trainerIdsByProf[profId] = list
    return list
end

-- parse rank from an NPC subtitle ("Expert Tailor", "Artisan Enchanter")
function CS.SubtitleRank(sub)
    if type(sub) ~= "string" then return nil end
    local rk = sub:match("(%a+)")
    return rk and CS.RANK_INDEX[rk] or nil
end

function CS.IsProfessionSubtitle(profId, sub)
    if type(sub) ~= "string" then return false end
    if sub:find("Supplies") or sub:find("Clothier") or sub:find("Vendor") then return false end
    for _, w in ipairs(CS.PROF_WORDS[profId] or {}) do
        if sub:find(w) then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- events
-------------------------------------------------------------------------------
local f = CreateFrame("Frame")
local H = {}

function H.ADDON_LOADED(name)
    if name == ADDON then CS.InitDB() end
end

local scanPending = false
local function scheduleScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.5, function()
        scanPending = false
        local ok, err = pcall(CS.ScanOpenProfession)
        if not ok then CS.LogError("scan", err) end
        if CS.Refresh then CS.Refresh() end
    end)
end
H.TRADE_SKILL_SHOW = scheduleScan
H.TRADE_SKILL_LIST_UPDATE = scheduleScan
H.TRADE_SKILL_DATA_SOURCE_CHANGED = scheduleScan

function H.NEW_RECIPE_LEARNED(recipeId)
    CS.MarkLearned(S(recipeId))
    if CS.Refresh then CS.Refresh() end
end

function H.TRAINER_SHOW() C_Timer.After(0.3, function() pcall(CS.CaptureTrainer) end) end
function H.TRAINER_UPDATE() C_Timer.After(0.3, function() pcall(CS.CaptureTrainer) end) end

local function refresh() if CS.Refresh then CS.Refresh() end end
H.BAG_UPDATE_DELAYED = refresh
H.SKILL_LINES_CHANGED = refresh
H.CHAT_MSG_SKILL = refresh
H.PLAYER_LEVEL_UP = refresh
H.ZONE_CHANGED_NEW_AREA = refresh
H.SPELL_DATA_LOAD_RESULT = refresh
H.ITEM_DATA_LOAD_RESULT = refresh

f:SetScript("OnEvent", function(_, event, ...)
    local h = H[event]
    if h then
        local ok, err = pcall(h, ...)
        if not ok then CS.LogError(event, err) end
    end
end)
for ev in pairs(H) do pcall(f.RegisterEvent, f, ev) end
