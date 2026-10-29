local addonName, ns = ...
local L = ns.L

-- Core: SavedVariables + defaults, [tag] template formatting, chat announce,
-- binding helpers, main event frame (ADDON_LOADED / combat enter + leave).

local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local LE_PARTY_CATEGORY_HOME = LE_PARTY_CATEGORY_HOME
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
local IsAltKeyDown, IsControlKeyDown, IsShiftKeyDown = IsAltKeyDown, IsControlKeyDown, IsShiftKeyDown
local pairs, ipairs, type, tostring, wipe = pairs, ipairs, type, tostring, wipe
local gsub, gmatch, lower, find, sub, byte = string.gsub, string.gmatch, string.lower, string.find, string.sub, string.byte

-- Popup / tooltip row limit (shared by Scan and UI).
ns.MAX_ROWS = 10

-- Announce channels in send order (also used by the options UI).
ns.CHANNELS = { "AUTO", "PARTY", "RAID", "SAY", "YELL", "SELF" }

local DEFAULTS = {
    channels       = { AUTO = true },
    anchor         = "BOTTOMRIGHT",
    debug          = false,
    prefix         = "ICU ->",
    popupLocked    = true,
    popupPos       = false, -- { left, top } when anchor == "FREE"
    popupAlpha     = 0.9,   -- popup background opacity (0..1)
    -- Bar color mode per unit group: CLASS / REACTION / CUSTOM (NPC: REACTION / CUSTOM).
    colorNpc       = "REACTION",
    colorEnemy     = "CLASS",
    colorFriendly  = "CLASS",
    customNpc      = { r = 1,   g = 0.82, b = 0 },
    customEnemy    = { r = 0.9, g = 0.2,  b = 0.2 },
    customFriendly = { r = 0.2, g = 0.6,  b = 1 },
    -- Popup look (LibSharedMedia names; built-in paths used if LSM is missing).
    barTexture     = "Blizzard",
    bgTexture      = "Solid",
    borderTexture  = "Blizzard Tooltip",
    borderSize     = 16,
    font           = "Friz Quadrata TT",
    fontSize       = 10,
    nameColor      = "NAME", -- reaction color on popup text: OFF / NAME / ROW
    nameColorSelf  = false,  -- also apply nameColor to Self chat output
    showPortraits  = false,  -- portrait slot in popup rows
    popupX         = 0,      -- popup offset (minimap anchors + CURSOR), -200..200
    popupY         = 0,
    closeTimer     = true,   -- close closeDelay sec after mouse leaves minimap + popup
    closeDelay     = 1.5,    -- 0..10
    closeEsc       = true,   -- Esc closes popup
    closeClick     = true,   -- any click outside the popup closes it
    -- Popup row actions (list, user-editable; first match wins).
    -- mods: ns.MOD_LIST entry; trigger: mouse button name or "KEY" (key = "ALT-CTRL-F" style)
    -- unit: TARGET / FOCUS / NONE; announce: CHANNELS / SELF / NONE; ping: bool
    clickActions = {
        { mods = "NONE",       trigger = "LeftButton", unit = "TARGET", mark = "NONE", announce = "SELF",     ping = false },
        { mods = "CTRL-SHIFT", trigger = "LeftButton", unit = "TARGET", mark = "NONE", announce = "CHANNELS", ping = true },
    },
    -- Minimap click that reads the blip tooltip (mouse button + exact modifiers).
    blipBind = { mods = "NONE", trigger = "LeftButton" },
    -- Minimap click that pings at the cursor (trigger "NONE" = off).
    pingBind = { mods = "CTRL", trigger = "LeftButton" },
    -- Binding that closes the popup (trigger "NONE" = off).
    closeBind = { mods = "NONE", trigger = "RightButton" },
    -- Blip click while in combat (no popup).
    combat = { announce = "CHANNELS", ping = true },
    -- Text templates ([tag] syntax). *Same = use the Chat NPC template.
    formats = {
        npc         = "[name] [level] [race] [class] <[guild]> [[hp%]]",
        popupNpc    = "[name] [level] [race] [class] <[guild]> [[hp%]]",
        player      = "[name] [level] [race] [class] <[guild]> [[hp%]]",
        popupPlayer = "[name] [level] [race] [class] <[guild]> [[hp%]]",
        popupNpcSame    = true,
        playerSame      = true,
        popupPlayerSame = true,
    },
}

-- Template slots in options order; tags in help-window order.
ns.FORMAT_KEYS = { "npc", "popupNpc", "player", "popupPlayer" }
ns.TAGS = {
    "name", "level", "hp", "hpmax", "hp%", "mana", "manamax", "mana%",
    "power", "powermax", "power%", "powertype", "race", "class", "guild",
    "type", "family", "rank", "reaction", "faction", "sex", "dead", "target", "kind",
}
local TAG_SET = {}
for _, t in ipairs(ns.TAGS) do TAG_SET[t] = true end

-- Effective template for a slot (follows Chat NPC when its "same" box is ticked).
function ns.GetFormat(key)
    local f = ns.db.formats
    if key ~= "npc" and f[key .. "Same"] then key = "npc" end
    return f[key] or ""
end

-- Template with secret values: plain concatenation only (secrets allow `..` but no
-- gsub/compare), so no <> () [] cleanup. Returns secret text + a readable stand-in
-- of similar width ("000000" per secret) for measuring the popup row.
local function FormatSecret(template, vals, sec)
    local out, measure, pos = "", "", 1
    while true do
        local s, e, tag = find(template, "%[([%w%%]+)%]", pos)
        if not s then break end
        local lit = sub(template, pos, s - 1)
        out, measure = out .. lit, measure .. lit
        local t = lower(tag)
        if sec[t] then
            out, measure = out .. sec[t][1], measure .. "000000"
        elseif TAG_SET[t] then
            local v = vals[t]
            if v ~= nil then
                v = tostring(v)
                out, measure = out .. v, measure .. v
            end
        else
            local raw = sub(template, s, e)
            out, measure = out .. raw, measure .. raw
        end
        pos = e + 1
    end
    local rest = sub(template, pos)
    return out .. rest, measure .. rest
end

-- Replace [tag] with vals[tag]; known tags without value vanish, unknown text stays.
-- sec (optional): secret values wrapped as { v }; if the template uses one, returns text, measure.
function ns.FormatUnit(template, vals, sec)
    template = template or ""
    if sec then
        for tag in gmatch(template, "%[([%w%%]+)%]") do
            if sec[lower(tag)] then return FormatSecret(template, vals, sec) end
        end
    end
    local s = gsub(template, "%[([%w%%]+)%]", function(tag)
        tag = lower(tag)
        if not TAG_SET[tag] then return nil end
        local v = vals[tag]
        return v ~= nil and tostring(v) or ""
    end)
    s = gsub(s, "<%s*>", "")
    s = gsub(s, "%(%s*%)", "")
    s = gsub(s, "%[%s*%]", "")
    s = gsub(s, "%s%s+", " ")
    s = gsub(s, "^%s+", "")
    s = gsub(s, "%s+$", "")
    return s
end

ns.UNIT_ACTIONS   = { "TARGET", "FOCUS", "NONE" }
ns.ANNOUNCE_MODES = { "CHANNELS", "SELF", "NONE" }
ns.COLOR_MODES    = { "CLASS", "REACTION", "CUSTOM" }
-- Raid mark per action: NONE / "1".."8" (Star..Skull) / CLEAR (removes mark).
ns.MARK_LIST      = { "NONE", "1", "2", "3", "4", "5", "6", "7", "8", "CLEAR" }
-- Modifier combos in WoW binding order (ALT-CTRL-SHIFT).
ns.MOD_LIST       = { "NONE", "SHIFT", "CTRL", "ALT", "CTRL-SHIFT", "ALT-SHIFT", "ALT-CTRL", "ALT-CTRL-SHIFT" }
ns.MOUSE_BUTTONS  = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
ns.TRIGGERS       = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5", "KEY" }
ns.CLOSE_TRIGGERS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5", "KEY", "NONE" }
ns.PING_TRIGGERS  = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5", "NONE" }

-- Modifiers held right now, as a MOD_LIST entry.
function ns.CurrentMods()
    local s = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
    return s == "" and "NONE" or s:sub(1, -2)
end

-- Unique id of a binding ({ mods, trigger, key }); nil if it can't fire.
function ns.BindId(b)
    if not b or b.trigger == "NONE" then return nil end
    if b.trigger == "KEY" then return b.key and ("KEY:" .. b.key) or nil end
    return (b.mods or "NONE") .. ":" .. b.trigger
end

-- Action i is ignored when its binding is unset, used by the close binding or
-- by an earlier action (first wins).
function ns.ActionShadowed(i)
    local list = ns.db.clickActions
    local id = ns.BindId(list[i])
    if not id or id == ns.BindId(ns.db.closeBind) then return true end
    for j = 1, i - 1 do
        if ns.BindId(list[j]) == id then return true end
    end
    return false
end

-- Ping binding is ignored when off or equal to the blip click binding.
function ns.PingShadowed()
    local id = ns.BindId(ns.db.pingBind)
    return not id or id == ns.BindId(ns.db.blipBind)
end

-- Fill missing keys from defaults (recursive). An existing channels table is left
-- as the user set it: disabled channels are nil, so defaults must not re-add AUTO.
local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                MergeDefaults(dst[k], v)
            elseif k ~= "channels" and k ~= "clickActions" then -- user-owned tables
                MergeDefaults(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Reset every setting to defaults. Wipes in place so ns.db / ICUfpDB stay the same table.
function ns.ResetDefaults()
    local ver = ICUfpDB.actionsVersion
    wipe(ICUfpDB)
    ICUfpDB.actionsVersion = ver
    MergeDefaults(ICUfpDB, DEFAULTS)
    ns.UI.ApplyLayout() -- deferred to PLAYER_REGEN_ENABLED in combat
    ns.UI.ApplyAppearance()
    ns.UI.ApplyEsc()
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(L.PREFIX .. tostring(msg))
end

function ns.Debug(msg)
    if ns.db and ns.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888ICU dbg:|r " .. tostring(msg))
    end
end

-- Map a channel key to a chat type; "SELF" = local print; nil = skip.
local function Resolve(key)
    if key == "AUTO" then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
            return "INSTANCE_CHAT"
        elseif IsInRaid() then
            return "RAID"
        elseif IsInGroup() then
            return "PARTY"
        end
        return "SELF" -- solo fallback, as old "PR"
    elseif key == "PARTY" then
        return IsInGroup(LE_PARTY_CATEGORY_HOME) and "PARTY" or nil
    elseif key == "RAID" then
        return IsInRaid(LE_PARTY_CATEGORY_HOME) and "RAID" or nil
    elseif key == "SAY" or key == "YELL" then
        return key -- needs hardware event: only call from click handlers
    elseif key == "SELF" then
        return "SELF"
    end
end

-- Announce text. mode: "CHANNELS" (default) / "SELF" / "NONE".
-- selfText (optional): colored variant used for local (Self) output only.
function ns.AnnounceMode(text, mode, selfText)
    if mode == "NONE" then return end
    ns.Announce(text, mode == "SELF", selfText)
end

-- Chat messages are limited to 255 bytes. Cut on a UTF-8 boundary: step back while
-- the first dropped byte is a continuation byte (0x80-0xBF).
local MAX_CHAT = 255
local function ChatLimit(msg)
    if #msg <= MAX_CHAT then return msg end
    local n = MAX_CHAT
    while n > 0 do
        local b = byte(msg, n + 1)
        if b < 0x80 or b >= 0xC0 then break end
        n = n - 1
    end
    return sub(msg, 1, n)
end

-- Announce text to every enabled channel. selfOnly forces local output.
-- text must be a plain (non-secret) string: entry.chat never holds secrets.
function ns.Announce(text, selfOnly, selfText)
    local db = ns.db
    local prefix = db.prefix or ""
    prefix = prefix ~= "" and (prefix .. " ") or ""
    local msg = prefix .. text
    local selfMsg = prefix .. (selfText or text)
    if selfOnly then
        DEFAULT_CHAT_FRAME:AddMessage(selfMsg, 1, 1, 1)
        return
    end
    local sent = {} -- AUTO may resolve to the same chat type as PARTY/RAID/SELF
    for _, key in ipairs(ns.CHANNELS) do
        if db.channels[key] then
            local ch = Resolve(key)
            if ch and not sent[ch] then
                sent[ch] = true
                if ch == "SELF" then
                    DEFAULT_CHAT_FRAME:AddMessage(selfMsg, 1, 1, 1)
                else
                    SendChat(ChatLimit(msg), ch)
                end
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Fires just before lockdown: last chance to hide the secure popup.
        ns.UI.Lock()
        ns.UI.Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Apply anchor / lock changes that were blocked during combat.
        if ns.UI.layoutPending then ns.UI.ApplyLayout() end
    elseif arg1 == addonName then -- ADDON_LOADED
        self:UnregisterEvent("ADDON_LOADED")
        if type(ICUfpDB) ~= "table" then ICUfpDB = {} end
        if type(ICUfpCharDB) ~= "table" then ICUfpCharDB = {} end
        -- v2: per-situation actions replaced by the clickActions list (old ones dropped).
        if (ICUfpDB.actionsVersion or 1) < 2 then
            ICUfpDB.actions = nil
            ICUfpDB.clickActions = nil
            ICUfpDB.actionsVersion = 2
        end
        -- Old class-color checkboxes -> color modes.
        if ICUfpDB.colorEnemy == nil and ICUfpDB.classBarsEnemy == false then ICUfpDB.colorEnemy = "REACTION" end
        if ICUfpDB.colorFriendly == nil and ICUfpDB.classBarsFriendly == false then ICUfpDB.colorFriendly = "REACTION" end
        ICUfpDB.classBarsEnemy, ICUfpDB.classBarsFriendly = nil, nil
        MergeDefaults(ICUfpDB, DEFAULTS)
        ns.db = ICUfpDB
        ns.UI.Init()
        ns.Scan.Init()
        ns.Options.Init()
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.Print(L.LOADED)
    end
end)
