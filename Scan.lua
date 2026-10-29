local addonName, ns = ...
local L = ns.L

-- Scan: minimap click handling. Reads blip names from the minimap tooltip, maps
-- them to readable unit tokens, builds popup row entries, minimap pings.
local Scan = {}
ns.Scan = Scan

local GameTooltip, Minimap = GameTooltip, Minimap
local InCombatLockdown = InCombatLockdown
local GetCursorPosition, GetTime = GetCursorPosition, GetTime
local UnitExists, UnitName, UnitLevel, UnitRace, UnitClass = UnitExists, UnitName, UnitLevel, UnitRace, UnitClass
local UnitIsPlayer, UnitHealth, UnitHealthMax, UnitReaction = UnitIsPlayer, UnitHealth, UnitHealthMax, UnitReaction
local GetGuildInfo, GetNumGroupMembers, IsInRaid = GetGuildInfo, GetNumGroupMembers, IsInRaid
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local UnitCreatureType, UnitCreatureFamily, UnitClassification = UnitCreatureType, UnitCreatureFamily, UnitClassification
local UnitFactionGroup, UnitSex, UnitIsDeadOrGhost = UnitFactionGroup, UnitSex, UnitIsDeadOrGhost
local UnitIsEnemy, format, floor = UnitIsEnemy, string.format, math.floor
local MANA_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local C_NamePlate = C_NamePlate
-- Secret-value test. Must run BEFORE any comparison / boolean test on a value that
-- can be secret (those operations error on secrets). Accepts nil.
local IsSecret = issecretvalue or function() return false end
local ipairs, tinsert, tconcat = ipairs, table.insert, table.concat
local gsub, gmatch, match = string.gsub, string.gmatch, string.match

local MAX_ROWS = ns.MAX_ROWS

-- Remove color / texture / atlas markup and turn |n into newlines.
local function Clean(s)
    s = gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = gsub(s, "|cn[^:]+:", "") -- named colors: |cnNORMAL_FONT_COLOR:
    s = gsub(s, "|r", "")
    s = gsub(s, "|T.-|t", "")
    s = gsub(s, "|A.-|a", "")
    s = gsub(s, "|n", "\n")
    return s
end

-- Collect unique names from the minimap tooltip (one name per line).
-- Returns list, or nil + true if the tooltip text is secret.
local function ReadTooltipNames()
    if not GameTooltip:IsShown() then return nil end
    local names, seen = {}, {}
    for i = 1, GameTooltip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if IsSecret(text) then return nil, true end
        if text and text ~= "" then
            for line in gmatch(Clean(text), "[^\n]+") do
                local name = match(line, "^%s*(.-)%s*$")
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    tinsert(names, name)
                    if #names >= MAX_ROWS then return names end
                end
            end
        end
    end
    return names
end

-- Add unit token u to map under "Name" and "Name-Realm". First token added wins,
-- so callers add units in priority order. Secret names are skipped.
local function AddUnit(map, u)
    if not UnitExists(u) then return end
    local n, realm = UnitName(u)
    if IsSecret(n) or not n then return end
    if not map[n] then map[n] = u end
    if not IsSecret(realm) and realm and realm ~= "" then
        local full = n .. "-" .. realm
        if not map[full] then map[full] = u end
    end
end

-- name -> unit token for every unit readable without changing the target.
-- Built once per click: one API pass instead of one pass per tooltip name.
local function UnitMap()
    local map = {}
    AddUnit(map, "player")
    AddUnit(map, "target")
    AddUnit(map, "focus")
    AddUnit(map, "mouseover")
    AddUnit(map, "softenemy")
    AddUnit(map, "softfriend")
    local n = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, n do AddUnit(map, "raid" .. i) end
    else
        for i = 1, n - 1 do AddUnit(map, "party" .. i) end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if u then AddUnit(map, u) end
        end
    end
    return map
end

-- Value or nil if secret / empty string. Secret check first (see IsSecret).
local function Safe(v)
    if IsSecret(v) or v == nil or v == "" then return nil end
    return v
end

-- Secret value kept for display only (popup text / bar), never read.
-- Wrapped in a table so presence checks never test the secret itself.
local function Raw(v)
    if IsSecret(v) then return { v } end
end

local function Pct(cur, max)
    return floor(cur / max * 100 + 0.5) .. "%"
end

-- Collect tag values for a unit. Readable values go to vals (chat + popup);
-- secret ones go to sec as { v } (popup only, see ns.FormatUnit).
-- Returns readable reaction (1-8) and class file token (players) for BuildEntry.
local function UnitTags(unit, isPlayer, vals, sec)
    local level = Safe(UnitLevel(unit))
    if level then vals.level = level > 0 and level or "??" end

    local rHp, rHpMax = UnitHealth(unit), UnitHealthMax(unit)
    local hp, hpMax = Safe(rHp), Safe(rHpMax)
    if hp and hpMax and hpMax > 0 then
        vals.hp, vals.hpmax, vals["hp%"] = hp, hpMax, Pct(hp, hpMax)
    else
        sec.hp, sec.hpmax = Raw(rHp), Raw(rHpMax)
        -- 0-100 secret percent, formatted without reading it; any failure = no tag.
        -- Only for secret health: readable hp with hpMax 0 must not create a sec entry
        -- (it would force the no-cleanup secret path in ns.FormatUnit).
        if (sec.hp or sec.hpmax) and UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            local ok, p = pcall(UnitHealthPercent, unit, false, CurveConstants.ScaleTo100)
            if ok then
                local ok2, s = pcall(string.format, "%.0f%%", p)
                if ok2 then sec["hp%"] = { s } end
            end
        end
    end

    local rMana, rManaMax = UnitPower(unit, MANA_TYPE), UnitPowerMax(unit, MANA_TYPE)
    local mana, manaMax = Safe(rMana), Safe(rManaMax)
    if mana and manaMax then
        if manaMax > 0 then
            vals.mana, vals.manamax, vals["mana%"] = mana, manaMax, Pct(mana, manaMax)
        end
    else
        sec.mana, sec.manamax = Raw(rMana), Raw(rManaMax)
    end

    local rPw, rPwMax = UnitPower(unit), UnitPowerMax(unit)
    local pw, pwMax = Safe(rPw), Safe(rPwMax)
    local hasPower = false
    if pw and pwMax then
        if pwMax > 0 then
            vals.power, vals.powermax, vals["power%"] = pw, pwMax, Pct(pw, pwMax)
            hasPower = true
        end
    else
        sec.power, sec.powermax = Raw(rPw), Raw(rPwMax)
        hasPower = sec.power ~= nil
    end
    if hasPower then
        local _, token = UnitPowerType(unit)
        token = Safe(token)
        if token then vals.powertype = _G[token] or token end
    end

    local classFile
    if isPlayer then
        local className, file = UnitClass(unit)
        vals.race = Safe(UnitRace(unit))
        vals.class = Safe(className)
        vals.guild = Safe((GetGuildInfo(unit)))
        classFile = Safe(file)
    end

    vals.type = Safe(UnitCreatureType(unit))
    vals.family = Safe(UnitCreatureFamily(unit))
    local cls = Safe(UnitClassification(unit))
    vals.rank = cls and L.RANK_NAMES[cls]

    local reaction = Safe(UnitReaction(unit, "player"))
    if reaction then
        vals.reaction = reaction <= 3 and L.REACTION_NAMES.HOSTILE
            or reaction == 4 and L.REACTION_NAMES.NEUTRAL or L.REACTION_NAMES.FRIENDLY
    end

    local fEng, fLoc = UnitFactionGroup(unit)
    vals.faction = Safe(fLoc) or Safe(fEng)
    local sex = Safe(UnitSex(unit))
    vals.sex = sex and L.SEX_NAMES[sex]
    local dead = UnitIsDeadOrGhost(unit)
    if not IsSecret(dead) and dead then vals.dead = L.DEAD end

    local tu = unit .. "target"
    if UnitExists(tu) then vals.target = Safe((UnitName(tu))) end
    vals.kind = isPlayer and L.PLAYER or L.NPC
    return reaction, classFile
end

-- Popup row data: name, unit, chat (plain text), text (may be secret), measure
-- (width stand-in when text is secret), health 0-100 or hpS/hpMaxS secrets, color.
-- unit nil = name only (unit not readable). Default color: gold.
local function BuildEntry(name, unit)
    local e = { name = name, r = 1, g = 0.82, b = 0 }
    local vals, sec = { name = name }, {}
    local isPlayer = false
    if unit then
        e.unit = unit
        isPlayer = UnitIsPlayer(unit) and true or false
        local reaction, classFile = UnitTags(unit, isPlayer, vals, sec)
        if vals["hp%"] then e.health = vals.hp / vals.hpmax * 100 end
        if sec.hp and sec.hpmax then
            e.hpSecret, e.hpS, e.hpMaxS = true, sec.hp[1], sec.hpmax[1]
        end
        -- Reaction color (FACTION_BAR_COLORS): NPC bars, name / row text option.
        local rc = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if rc then
            e.rr, e.rg, e.rb = rc.r, rc.g, rc.b
            e.r, e.g, e.b = rc.r, rc.g, rc.b
        end
        -- Bar color mode per group (CLASS / REACTION / CUSTOM). CLASS falls back to
        -- reaction when the class is unknown; reaction falls back to default gold.
        local db = ns.db
        local mode, custom
        if isPlayer then
            e.classFile = classFile
            if Safe(UnitIsEnemy("player", unit)) then
                mode, custom = db.colorEnemy, db.customEnemy
            else
                mode, custom = db.colorFriendly, db.customFriendly
            end
        else
            mode, custom = db.colorNpc, db.customNpc
        end
        if mode == "CUSTOM" and custom then
            e.r, e.g, e.b = custom.r, custom.g, custom.b
        elseif mode == "CLASS" then
            local c = e.classFile and C_ClassColor and C_ClassColor.GetClassColor(e.classFile)
            if c then e.r, e.g, e.b = c.r, c.g, c.b end
        end
    end
    -- |cffRRGGBB code for the reaction color (nil if unknown or option off).
    local mode = ns.db.nameColor
    local code = e.rr and mode ~= "OFF"
        and format("|cff%02x%02x%02x", floor(e.rr * 255 + 0.5), floor(e.rg * 255 + 0.5), floor(e.rb * 255 + 0.5))
    e.rowColor = code and mode == "ROW" or nil
    local chatKey, popupKey = "npc", "popupNpc"
    if isPlayer then chatKey, popupKey = "player", "popupPlayer" end
    local chat = ns.FormatUnit(ns.GetFormat(chatKey), vals)
    -- NAME mode: colored [name] in popup (and Self chat); |r returns to the row color.
    if code and mode == "NAME" then vals.name = code .. name .. "|r" end
    local popup, measure = ns.FormatUnit(ns.GetFormat(popupKey), vals, sec)
    e.chat = chat ~= "" and chat or name
    if code and ns.db.nameColorSelf then
        if mode == "NAME" then
            local cs = ns.FormatUnit(ns.GetFormat(chatKey), vals)
            e.chatSelf = cs ~= "" and cs or vals.name
        else
            e.chatSelf = code .. e.chat .. "|r"
        end
    end
    if measure then
        e.text, e.measure = popup, measure -- secret text; measure = width stand-in
    else
        e.text = popup ~= "" and popup or name
    end
    return e
end

-- Rebuild an entry from a unit token (e.g. "target" after the row's macro ran).
-- Returns nil if that unit is not the named one.
function Scan.FreshEntry(name, unit)
    local map = {}
    AddUnit(map, unit)
    if map[name] then return BuildEntry(name, unit) end
end

-- Cursor position as offset from the minimap center (same math as Blizzard's
-- Minimap_OnClick).
local function CursorOffset()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    return x / scale - cx, y / scale - cy
end

-- Ping the minimap at offset (x, y); errors only reach debug output.
local function PingAt(x, y)
    if not Minimap.PingLocation then
        ns.Debug("ping skipped: PingLocation missing")
        return
    end
    local ok, err = pcall(Minimap.PingLocation, Minimap, x, y)
    if not ok then ns.Debug("ping failed: " .. tostring(err)) end
end

-- Ping at the last blip click (stored by OnBlipClick; used by popup row actions).
function Scan.Ping()
    if Scan.pingX then
        PingAt(Scan.pingX, Scan.pingY)
    else
        ns.Debug("ping skipped: no location")
    end
end

local lastClick = 0

local function OnBlipClick()
    local now = GetTime()
    if now - lastClick < 0.25 then return end -- debounce
    lastClick = now
    local names, secret = ReadTooltipNames()
    if secret then ns.Print(L.SECRET) return end
    if not names or #names == 0 then
        ns.Debug("no tooltip names")
        return
    end
    ns.Debug("tooltip: " .. tconcat(names, " | "))
    Scan.pingX, Scan.pingY = CursorOffset()

    if InCombatLockdown() then
        -- Announce-only mode: secure rows can't be rebuilt in combat.
        local c = ns.db.combat
        ns.AnnounceMode(tconcat(names, ", "), c.announce)
        if c.ping then Scan.Ping() end
        return
    end

    local map = UnitMap()
    local entries = {}
    for i, name in ipairs(names) do
        local unit = map[name]
        entries[i] = BuildEntry(name, unit)
        if ns.db.debug then
            local key = (unit and UnitIsPlayer(unit)) and "player" or "npc"
            ns.Debug(name .. ": unit=" .. tostring(unit) .. " tpl=" .. ns.GetFormat(key)
                .. " -> " .. entries[i].chat)
        end
    end
    ns.UI.Show(entries)
end

-- Mouse binding b matches button + exact held modifiers.
local function BindMatch(b, button)
    return b and b.trigger == button and (b.mods or "NONE") == ns.CurrentMods()
end

function Scan.Init()
    -- Replace Blizzard's OnMouseUp (Minimap_OnClick pings on any button): only the
    -- blip binding over a blip runs ICU, ping binding pings; other clicks do nothing.
    local hadOrig = Minimap:GetScript("OnMouseUp") ~= nil
    Minimap:SetScript("OnMouseUp", function(_, button)
        if BindMatch(ns.db.blipBind, button) and GameTooltip:IsShown() then
            OnBlipClick()
        elseif not ns.PingShadowed() and BindMatch(ns.db.pingBind, button) then
            PingAt(CursorOffset()) -- own coords: Scan.pingX/Y stay for popup rows
        end
    end)
    ns.Debug("Minimap OnMouseUp replaced (original existed: " .. tostring(hadOrig) .. ")")
end
