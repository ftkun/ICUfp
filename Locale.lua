local addonName, ns = ...

local L = {}
ns.L = L

L.PREFIX          = "|cff33ff99ICU|r: "
L.LOADED          = "loaded. /icu = options, /icu help = commands."
L.CHANNEL_TOGGLED = "announce to %s: %s"
L.CHANNEL_BAD     = "invalid channel. Valid: auto, party, raid, say, yell, self"
L.ANCHOR_SET      = "anchor set to: %s"
L.ANCHOR_BAD      = "invalid anchor. Valid: top, topleft, topright, bottom, bottomleft, bottomright, left, right, cursor, free"
L.DEBUG_SET       = "debug: %s"
L.HELP = {
    "/icu - options window, /icu config - Blizzard options panel",
    "/icu announce <auto|party|raid|say|yell|self> - switch a channel on/off",
    "/icu anchor <top|topleft|topright|bottom|bottomleft|bottomright|left|right|cursor|free>",
    "/icu debug - toggle debug output",
    "Click blip: popup (out of combat) / announce only (in combat). Ctrl-click minimap (default): ping.",
    "Minimap click / ping bindings and popup row actions are set in /icu.",
}
L.NPC             = "NPC"
L.PLAYER          = "Player"
L.DEAD            = "Dead"
L.RANK_NAMES      = { elite = "Elite", rare = "Rare", rareelite = "Rare Elite", worldboss = "Boss" }
L.REACTION_NAMES  = { HOSTILE = "Hostile", NEUTRAL = "Neutral", FRIENDLY = "Friendly" }
L.SEX_NAMES       = { [2] = "Male", [3] = "Female" }

-- Announce format
L.OPT_SAME        = "Same as Chat NPC"
L.FORMAT_NAMES    = { npc = "Chat NPC", popupNpc = "Popup NPC", player = "Chat Player", popupPlayer = "Popup Player" }
-- Tag colors: green = tested readable, orange = secret (popup only), red = secret and
-- needs math (empty for restricted units), white = not tested yet.
local OK, POP, NO = "|cff40ff40", "|cffff9933", "|cffff4040"
L.TAGS_NOTE = {
    "Text outside tags is kept as typed: <[guild]> -> <Guild>.",
    "Tags without a value are removed, then empty <> () [] are cleaned.",
    "Only [name] works if the unit is not you / target / focus / mouseover / group / nameplate.",
    "In combat blip clicks announce names only.",
    OK .. "Green|r = tested, works in chat and popup.",
    POP .. "Orange|r = restricted by the game: popup only, empty in chat.",
    NO .. "Red|r = restricted and needs math: empty for most units (works for you).",
    "White = not tested yet.",
    "Popup lines with orange values skip the <> () [] / space cleanup.",
}
L.TAG_DESC = {
    ["name"]      = OK .. "Name|r",
    ["level"]     = OK .. "Level (?? if unknown / skull)|r",
    ["hp"]        = POP .. "Current health|r",
    ["hpmax"]     = POP .. "Max health|r",
    ["hp%"]       = POP .. "Health percent (may not work)|r",
    ["mana"]      = POP .. "Current mana|r",
    ["manamax"]   = POP .. "Max mana|r",
    ["mana%"]     = NO .. "Mana percent|r",
    ["power"]     = POP .. "Current main resource (mana, rage, energy...)|r",
    ["powermax"]  = POP .. "Max main resource|r",
    ["power%"]    = NO .. "Main resource percent|r",
    ["powertype"] = "Main resource name",
    ["race"]      = "Race (players only)",
    ["class"]     = "Class (players only)",
    ["guild"]     = "Guild (players only)",
    ["type"]      = OK .. "Creature type: Beast, Humanoid...|r",
    ["family"]    = "Beast family: Wolf, Cat...",
    ["rank"]      = OK .. "Elite / Rare / Rare Elite / Boss|r",
    ["reaction"]  = OK .. "Hostile / Neutral / Friendly|r",
    ["faction"]   = "Alliance / Horde",
    ["sex"]       = "Male / Female",
    ["dead"]      = "\"Dead\" if dead or ghost",
    ["target"]    = "Name of the unit's target",
    ["kind"]      = "NPC / Player",
}
L.SECRET          = "tooltip data is restricted right now."
L.MOVE_PREVIEW    = "ICUfp popup - drag to move"

-- Options UI
L.OPT_TITLE       = "ICUfp options"
L.OPT_DEBUG       = "Debug output"
L.OPT_PREFIX      = "Message prefix:"
L.OPT_ANCHOR      = "Popup position:"
L.OPT_LOCK        = "Locked"
L.OPT_NAMECOLOR      = "Reaction color:"
L.OPT_NAMECOLOR_SELF = "Also in Self chat"
L.NAMECOLOR_NAMES    = { OFF = "Off", NAME = "Name only", ROW = "Whole row" }
L.OPT_PORTRAITS      = "Show portraits"
L.OPT_OFFSET_X       = "X offset:"
L.OPT_OFFSET_Y       = "Y offset:"
L.OPT_CLOSE_TIMER    = "Timer"
L.OPT_CLOSE_ESC      = "Esc"
L.OPT_CLOSE_CLICK    = "Click outside"
L.OPT_CLOSE_DELAY    = "Timer delay:"
L.OPT_CLOSE_NOTE     = "Timer starts when the mouse leaves the minimap and popup. Close binding: Actions tab."
L.OPT_ACTIONS_NOTE = "Key actions work while the mouse is over a popup row. Red row = ignored (same binding as an earlier row or the close binding, or no key set)."
L.COL_UNIT        = "Unit"
L.COL_ANNOUNCE    = "Announce"
L.COL_PING        = "Ping"
L.COL_MARK        = "Raid mark"
-- Raid mark names: game's own localized names + icon. Keys match ns.MARK_LIST.
L.MARK_NAMES = { NONE = "None", CLEAR = "Clear" }
for i = 1, 8 do
    L.MARK_NAMES[tostring(i)] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":14|t "
        .. (_G["RAID_TARGET_" .. i] or ("Mark " .. i))
end
L.OPT_ADD_ACTION  = "Add action"
L.OPT_DEL_ACTION  = "Remove this action"
L.COL_MODS        = "Modifiers"
L.COL_TRIGGER     = "Button"
L.MOD_NAMES = {
    NONE = "None", SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt",
    ["CTRL-SHIFT"] = "Shift + Ctrl", ["ALT-SHIFT"] = "Shift + Alt", ["ALT-CTRL"] = "Ctrl + Alt",
    ["ALT-CTRL-SHIFT"] = "Shift + Ctrl + Alt",
}
L.TRIGGER_NAMES = {
    LeftButton = "Left", RightButton = "Right", MiddleButton = "Middle",
    Button4 = "Button 4", Button5 = "Button 5", KEY = "Keyboard key", NONE = "Off",
}
L.UNIT_NAMES      = { TARGET = "Target", FOCUS = "Focus", NONE = "Nothing" }
L.ANNOUNCE_NAMES  = { CHANNELS = "Channels", SELF = "Self only", NONE = "None" }
L.CHANNEL_NAMES = { AUTO = "Auto", PARTY = "Party", RAID = "Raid", SAY = "Say", YELL = "Yell", SELF = "Self" }
L.CHANNEL_TIPS = {
    AUTO = "Sends to instance chat, raid or party - whichever group you are in. When solo, prints to your chat frame only.",
    SELF = "Prints to your own chat frame only.",
}
L.ANCHOR_NAMES = {
    TOPLEFT = "Above, left", TOP = "Above", TOPRIGHT = "Above, right",
    LEFT = "Right side", RIGHT = "Left side",
    BOTTOMLEFT = "Below, left", BOTTOM = "Below", BOTTOMRIGHT = "Below, right",
    CURSOR = "At mouse cursor",
    FREE = "Free (movable)",
}

-- Options tree (AceConfig)
L.LIBS_MISSING    = "options need Ace3 + LibSharedMedia in ICUfp\\Libs (see embeds.xml)."
L.GRP_GENERAL     = "General"
L.GRP_FORMAT      = "Announce format"
L.GRP_POPUP       = "Popup"
L.GRP_ACTIONS     = "Actions"
L.GRP_BLIP        = "Minimap click"
L.GRP_PING        = "Minimap ping"
L.TAB_POSITION    = "Position"
L.TAB_BEHAVIOR    = "Behavior"
L.TAB_APPEARANCE  = "Appearance"
L.SEC_CHANNELS    = "Announce to"
L.SEC_MISC        = "Misc"
L.SEC_TEMPLATES   = "Templates"
L.SEC_TAGS        = "Tags"
L.SEC_POSITION    = "Position"
L.SEC_OFFSET      = "Offset (minimap positions and cursor)"
L.SEC_CLOSE       = "Popup closes on"
L.SEC_TEXTURES    = "Textures and font"
L.SEC_COLORS      = "Bar colors"
L.SEC_TEXT        = "Text"
L.SEC_BLIPBIND    = "Minimap click"
L.SEC_PINGBIND    = "Ping"
L.OPT_PING_NOTE   = "Pings the minimap at the cursor. Ignored when Off or same as the Minimap click binding."
L.SEC_CLOSEBIND   = "Close popup"
L.SEC_COMBAT      = "Blip in combat"
L.SEC_ACTIONLIST  = "Popup row actions"
L.OPT_BAR_TEX     = "Bar texture"
L.OPT_BG_TEX      = "Background"
L.OPT_BORDER_TEX  = "Border"
L.OPT_BORDER_SIZE = "Border size"
L.OPT_FONT        = "Font"
L.OPT_FONT_SIZE   = "Font size"
L.OPT_OPACITY     = "Background opacity"
L.OPT_COLOR_NPC      = "NPC"
L.OPT_COLOR_ENEMY    = "Enemy player"
L.OPT_COLOR_FRIENDLY = "Friendly player"
L.OPT_CUSTOM_COLOR   = "Color"
L.COLOR_MODE_NAMES = { CLASS = "Class", REACTION = "Reaction", CUSTOM = "Custom" }
L.ACTION_N        = "Action %d"
L.ACTION_IGNORED  = " (ignored)"
L.OPT_KEYBIND     = "Key"
L.OPT_KEYBIND_TIP = "Click, then press a key (with Shift / Ctrl / Alt if wanted). Esc clears."
L.OPT_DEL_CONFIRM = "Remove this action?"
L.OPT_DEFAULTS         = "Defaults"
L.OPT_DEFAULTS_TIP     = "Reset all ICUfp settings (every tab) to defaults."
L.OPT_DEFAULTS_CONFIRM = "Reset ALL ICUfp settings to defaults?"
L.DEFAULTS_DONE        = "all settings reset to defaults."
