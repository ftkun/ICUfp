local addonName, ns = ...
local L = ns.L

-- Options: AceConfig option table shown by AceConfigDialog (standalone via /icu and
-- embedded in Esc > Options > AddOns). Needs Libs/ (see embeds.xml).
local Options = {}
ns.Options = Options

local LibStub = LibStub
local ipairs, format, wipe = ipairs, string.format, wipe
local PlaySound, SOUNDKIT = PlaySound, SOUNDKIT
local APP = "ICUfp"

local ACR = LibStub and LibStub("AceConfigRegistry-3.0", true)
local ACD = LibStub and LibStub("AceConfigDialog-3.0", true)
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Rebuilds the action list args (set in ActionsGroup) before each redraw.
local actionList
function Options.Refresh()
    if actionList then actionList() end
    if ACR then ACR:NotifyChange(APP) end
end

---------------------------------------------------------------- helpers
local function DB() return ns.db end

-- AceGUI only enables the slider mouse wheel after a click on it. Own widget type =
-- stock Slider with the wheel always on (bar + label / value area). Pooled under its
-- own type, so other addons' sliders are unchanged.
local WHEEL_SLIDER = "ICUfp_WheelSlider"
if AceGUI and AceGUI.WidgetRegistry and not AceGUI:GetWidgetVersion(WHEEL_SLIDER) then
    AceGUI:RegisterWidgetType(WHEEL_SLIDER, function()
        local w = AceGUI.WidgetRegistry.Slider()
        w.type = WHEEL_SLIDER
        local acquire = w.OnAcquire
        w.OnAcquire = function(self)
            acquire(self)
            self.slider:EnableMouseWheel(true)
            self.frame:EnableMouseWheel(true)
        end
        w.frame:SetScript("OnMouseWheel", function(_, d)
            local f = w.slider:GetScript("OnMouseWheel")
            if f then f(w.slider, d) end
        end)
        return w
    end, 1)
end

-- Range option using the wheel slider (wheel moves by step).
local function Range(t)
    if AceGUI and AceGUI:GetWidgetVersion(WHEEL_SLIDER) then t.dialogControl = WHEEL_SLIDER end
    t.type = "range"
    return t
end

-- select values table from a key list and a names table (pair with sorting = list).
local function Values(list, names)
    local v = {}
    for _, k in ipairs(list) do v[k] = names[k] or k end
    return v
end

-- Texture / font select: LSM preview widget when SharedMediaWidgets is loaded.
local function MediaSelect(kind, widget, key, name, order)
    local hasWidget = AceGUI and AceGUI:GetWidgetVersion(widget)
    return {
        type = "select", name = name, order = order, width = 1.2,
        dialogControl = hasWidget and widget or nil,
        values = function() return LSM and LSM:HashTable(kind) or {} end,
        get = function() return DB()[key] end,
        set = function(_, v) DB()[key] = v ns.UI.ApplyAppearance() end,
    }
end

---------------------------------------------------------------- General
local function GeneralGroup()
    local channels = { type = "group", inline = true, name = L.SEC_CHANNELS, order = 1, args = {} }
    for i, key in ipairs(ns.CHANNELS) do
        channels.args[key] = {
            type = "toggle", order = i, width = 0.8,
            name = L.CHANNEL_NAMES[key], desc = L.CHANNEL_TIPS[key],
            get = function() return DB().channels[key] end,
            set = function(_, v) DB().channels[key] = v or nil end,
        }
    end
    return {
        type = "group", name = L.GRP_GENERAL, order = 1,
        args = {
            channels = channels,
            misc = {
                type = "group", inline = true, name = L.SEC_MISC, order = 2,
                args = {
                    prefix = {
                        type = "input", name = L.OPT_PREFIX, order = 1,
                        get = function() return DB().prefix or "" end,
                        set = function(_, v) DB().prefix = v end,
                    },
                    debug = {
                        type = "toggle", name = L.OPT_DEBUG, order = 2,
                        get = function() return DB().debug end,
                        set = function(_, v) DB().debug = v end,
                    },
                },
            },
            defaults = {
                type = "execute", name = L.OPT_DEFAULTS, desc = L.OPT_DEFAULTS_TIP, order = 3,
                confirm = function() PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) return L.OPT_DEFAULTS_CONFIRM end,
                func = function()
                    ns.ResetDefaults()
                    ns.Print(L.DEFAULTS_DONE)
                    Options.Refresh()
                end,
            },
        },
    }
end

---------------------------------------------------------------- Announce format
local function FormatGroup()
    local function F() return DB().formats end
    local templates = { type = "group", inline = true, name = L.SEC_TEMPLATES, order = 1, args = {} }
    for i, key in ipairs(ns.FORMAT_KEYS) do
        templates.args[key] = {
            type = "input", name = L.FORMAT_NAMES[key], order = i * 2 - 1, width = 2.2,
            get = function() return ns.GetFormat(key) end,
            set = function(_, v) F()[key] = v end,
            disabled = function() return key ~= "npc" and F()[key .. "Same"] end,
        }
        if key ~= "npc" then
            templates.args[key .. "Same"] = {
                type = "toggle", name = L.OPT_SAME, order = i * 2, width = 1,
                get = function() return F()[key .. "Same"] end,
                set = function(_, v)
                    -- Unticking starts the own template from the current Chat NPC one.
                    if not v then F()[key] = F().npc end
                    F()[key .. "Same"] = v
                end,
            }
        else
            templates.args.npcPad = { type = "description", name = "", order = i * 2, width = 1 }
        end
    end

    -- Tag reference (replaces the old separate Tags window).
    local lines = {}
    for _, tag in ipairs(ns.TAGS) do
        lines[#lines + 1] = format("|cffffd100[%s]|r  %s", tag, L.TAG_DESC[tag] or "")
    end
    lines[#lines + 1] = " "
    for _, line in ipairs(L.TAGS_NOTE) do lines[#lines + 1] = "|cffaaaaaa" .. line .. "|r" end

    return {
        type = "group", name = L.GRP_FORMAT, order = 2,
        args = {
            templates = templates,
            tags = {
                type = "group", inline = true, name = L.SEC_TAGS, order = 2,
                args = {
                    list = { type = "description", name = table.concat(lines, "\n"), fontSize = "medium", order = 1 },
                },
            },
        },
    }
end

---------------------------------------------------------------- Popup
local function PopupGroup()
    local function isFree() return DB().anchor == "FREE" end
    local function offset(key, name, order)
        return Range({
            name = name, order = order, min = -200, max = 200, step = 1, width = 1.2,
            disabled = isFree,
            get = function() return DB()[key] or 0 end,
            set = function(_, v) DB()[key] = v ns.UI.SetAnchor() end,
        })
    end
    local function colorRow(modeKey, customKey, name, modes, order)
        return {
            type = "group", inline = true, name = name, order = order,
            args = {
                mode = {
                    type = "select", name = "", order = 1, width = 1,
                    values = Values(modes, L.COLOR_MODE_NAMES), sorting = modes,
                    get = function() return DB()[modeKey] end,
                    set = function(_, v) DB()[modeKey] = v end,
                },
                color = {
                    type = "color", name = L.OPT_CUSTOM_COLOR, order = 2, width = 1,
                    hidden = function() return DB()[modeKey] ~= "CUSTOM" end,
                    get = function() local c = DB()[customKey] return c.r, c.g, c.b end,
                    set = function(_, r, g, b) DB()[customKey] = { r = r, g = g, b = b } end,
                },
            },
        }
    end

    return {
        type = "group", name = L.GRP_POPUP, order = 3, childGroups = "tab",
        args = {
            position = {
                type = "group", name = L.TAB_POSITION, order = 1,
                args = {
                    pos = {
                        type = "group", inline = true, name = L.SEC_POSITION, order = 1,
                        args = {
                            anchor = {
                                type = "select", name = L.OPT_ANCHOR, order = 1, width = 1.2,
                                values = Values(ns.UI.ANCHOR_LIST, L.ANCHOR_NAMES), sorting = ns.UI.ANCHOR_LIST,
                                get = function() return DB().anchor end,
                                set = function(_, v) DB().anchor = v ns.UI.ApplyLayout() end,
                            },
                            lock = {
                                type = "toggle", name = L.OPT_LOCK, order = 2,
                                disabled = function() return not isFree() end,
                                get = function() return DB().popupLocked end,
                                set = function(_, v) DB().popupLocked = v ns.UI.ApplyLayout() end,
                            },
                        },
                    },
                    offset = {
                        type = "group", inline = true, name = L.SEC_OFFSET, order = 2,
                        args = {
                            x = offset("popupX", L.OPT_OFFSET_X, 1),
                            y = offset("popupY", L.OPT_OFFSET_Y, 2),
                        },
                    },
                },
            },
            behavior = {
                type = "group", name = L.TAB_BEHAVIOR, order = 2,
                args = {
                    close = {
                        type = "group", inline = true, name = L.SEC_CLOSE, order = 1,
                        args = {
                            closeTimer = {
                                type = "toggle", name = L.OPT_CLOSE_TIMER, order = 1, width = 0.7,
                                get = function() return DB().closeTimer end,
                                set = function(_, v) DB().closeTimer = v end,
                            },
                            closeEsc = {
                                type = "toggle", name = L.OPT_CLOSE_ESC, order = 2, width = 0.7,
                                get = function() return DB().closeEsc end,
                                set = function(_, v) DB().closeEsc = v ns.UI.ApplyEsc() end,
                            },
                            closeClick = {
                                type = "toggle", name = L.OPT_CLOSE_CLICK, order = 3, width = 1,
                                get = function() return DB().closeClick end,
                                set = function(_, v) DB().closeClick = v end,
                            },
                            closeDelay = Range({
                                name = L.OPT_CLOSE_DELAY, order = 4, width = 1.2,
                                min = 0, max = 10, step = 0.5,
                                disabled = function() return not DB().closeTimer end,
                                get = function() return DB().closeDelay or 1.5 end,
                                set = function(_, v) DB().closeDelay = v end,
                            }),
                            note = { type = "description", name = L.OPT_CLOSE_NOTE, order = 5 },
                        },
                    },
                },
            },
            appearance = {
                type = "group", name = L.TAB_APPEARANCE, order = 3,
                args = {
                    textures = {
                        type = "group", inline = true, name = L.SEC_TEXTURES, order = 1,
                        args = {
                            bar    = MediaSelect("statusbar",  "LSM30_Statusbar",  "barTexture",    L.OPT_BAR_TEX, 1),
                            bg     = MediaSelect("background", "LSM30_Background", "bgTexture",     L.OPT_BG_TEX, 2),
                            border = MediaSelect("border",     "LSM30_Border",     "borderTexture", L.OPT_BORDER_TEX, 3),
                            borderSize = Range({
                                name = L.OPT_BORDER_SIZE, order = 4, width = 1.2,
                                min = 4, max = 32, step = 1,
                                get = function() return DB().borderSize or 16 end,
                                set = function(_, v) DB().borderSize = v ns.UI.ApplyAppearance() end,
                            }),
                            font = MediaSelect("font", "LSM30_Font", "font", L.OPT_FONT, 5),
                            fontSize = Range({
                                name = L.OPT_FONT_SIZE, order = 6, width = 1.2,
                                min = 6, max = 18, step = 1,
                                get = function() return DB().fontSize or 10 end,
                                set = function(_, v) DB().fontSize = v ns.UI.ApplyAppearance() end,
                            }),
                            alpha = Range({
                                name = L.OPT_OPACITY, order = 7, width = 1.2,
                                min = 0.05, max = 1, step = 0.01, isPercent = true, -- wheel / drag 1%
                                get = function() return DB().popupAlpha or 0.9 end,
                                set = function(_, v) DB().popupAlpha = v ns.UI.ApplyAlpha() end,
                            }),
                        },
                    },
                    colors = {
                        type = "group", inline = true, name = L.SEC_COLORS, order = 2,
                        args = {
                            npc      = colorRow("colorNpc", "customNpc", L.OPT_COLOR_NPC, { "REACTION", "CUSTOM" }, 1),
                            enemy    = colorRow("colorEnemy", "customEnemy", L.OPT_COLOR_ENEMY, ns.COLOR_MODES, 2),
                            friendly = colorRow("colorFriendly", "customFriendly", L.OPT_COLOR_FRIENDLY, ns.COLOR_MODES, 3),
                        },
                    },
                    text = {
                        type = "group", inline = true, name = L.SEC_TEXT, order = 3,
                        args = {
                            nameColor = {
                                type = "select", name = L.OPT_NAMECOLOR, order = 1,
                                values = Values({ "OFF", "NAME", "ROW" }, L.NAMECOLOR_NAMES),
                                sorting = { "OFF", "NAME", "ROW" },
                                get = function() return DB().nameColor end,
                                set = function(_, v) DB().nameColor = v end,
                            },
                            nameColorSelf = {
                                type = "toggle", name = L.OPT_NAMECOLOR_SELF, order = 2,
                                disabled = function() return DB().nameColor == "OFF" end,
                                get = function() return DB().nameColorSelf end,
                                set = function(_, v) DB().nameColorSelf = v end,
                            },
                            portraits = {
                                type = "toggle", name = L.OPT_PORTRAITS, order = 3,
                                get = function() return DB().showPortraits end,
                                set = function(_, v) DB().showPortraits = v end,
                            },
                        },
                    },
                },
            },
        },
    }
end

---------------------------------------------------------------- Actions
-- Binding fields (button / mods / key) for binding table getB(), orders base..base+2.
local function BindArgs(args, getB, triggers, base)
    args.mods = {
        type = "select", name = L.COL_MODS, order = base + 1, width = 0.9,
        values = Values(ns.MOD_LIST, L.MOD_NAMES), sorting = ns.MOD_LIST,
        disabled = function() local t = getB().trigger return t == "KEY" or t == "NONE" end,
        get = function() return getB().mods or "NONE" end,
        set = function(_, v) getB().mods = v Options.Refresh() end,
    }
    args.trigger = {
        type = "select", name = L.COL_TRIGGER, order = base, width = 0.8,
        values = Values(triggers, L.TRIGGER_NAMES), sorting = triggers,
        get = function() return getB().trigger end,
        set = function(_, v) getB().trigger = v Options.Refresh() end,
    }
    args.key = {
        type = "keybinding", name = L.OPT_KEYBIND, desc = L.OPT_KEYBIND_TIP, order = base + 2, width = 0.8,
        hidden = function() return getB().trigger ~= "KEY" end,
        get = function() return getB().key or "" end,
        set = function(_, v) getB().key = (v ~= "" and v) or nil Options.Refresh() end,
    }
end

local function ActionsGroup()
    local closeArgs = {}
    BindArgs(closeArgs, function() return DB().closeBind end, ns.CLOSE_TRIGGERS, 1)

    local listArgs = {}
    local group = {
        type = "group", name = L.GRP_ACTIONS, order = 6,
        args = {
            close = { type = "group", inline = true, name = L.SEC_CLOSEBIND, order = 1, args = closeArgs },
            combat = {
                type = "group", inline = true, name = L.SEC_COMBAT, order = 2,
                args = {
                    announce = {
                        type = "select", name = L.COL_ANNOUNCE, order = 1, width = 0.9,
                        values = Values(ns.ANNOUNCE_MODES, L.ANNOUNCE_NAMES), sorting = ns.ANNOUNCE_MODES,
                        get = function() return DB().combat.announce end,
                        set = function(_, v) DB().combat.announce = v end,
                    },
                    ping = {
                        type = "toggle", name = L.COL_PING, order = 2, width = 0.5,
                        get = function() return DB().combat.ping end,
                        set = function(_, v) DB().combat.ping = v end,
                    },
                },
            },
            list = { type = "group", inline = true, name = L.SEC_ACTIONLIST, order = 3, args = listArgs },
        },
    }

    -- One inline group per action; rebuilt by Options.Refresh (add / remove / rebind).
    actionList = function()
        if not ns.db then return end
        wipe(listArgs)
        listArgs.note = { type = "description", name = L.OPT_ACTIONS_NOTE, order = 0 }
        local list = DB().clickActions
        for i = 1, #list do
            local function A() return DB().clickActions[i] or {} end
            local args = {}
            BindArgs(args, A, ns.TRIGGERS, 1)
            args.unit = {
                type = "select", name = L.COL_UNIT, order = 4, width = 0.7,
                values = Values(ns.UNIT_ACTIONS, L.UNIT_NAMES), sorting = ns.UNIT_ACTIONS,
                get = function() return A().unit end,
                set = function(_, v) A().unit = v end,
            }
            args.mark = {
                type = "select", name = L.COL_MARK, order = 5, width = 0.8,
                values = Values(ns.MARK_LIST, L.MARK_NAMES), sorting = ns.MARK_LIST,
                get = function() return A().mark or "NONE" end,
                set = function(_, v) A().mark = v end,
            }
            args.announce = {
                type = "select", name = L.COL_ANNOUNCE, order = 6, width = 0.8,
                values = Values(ns.ANNOUNCE_MODES, L.ANNOUNCE_NAMES), sorting = ns.ANNOUNCE_MODES,
                get = function() return A().announce end,
                set = function(_, v) A().announce = v end,
            }
            args.ping = {
                type = "toggle", name = L.COL_PING, order = 7, width = 0.4,
                get = function() return A().ping end,
                set = function(_, v) A().ping = v end,
            }
            args.delete = {
                type = "execute", name = "X", desc = L.OPT_DEL_ACTION, order = 8, width = 0.3,
                confirm = true, confirmText = L.OPT_DEL_CONFIRM,
                func = function()
                    table.remove(DB().clickActions, i)
                    Options.Refresh()
                end,
            }
            local title = format(L.ACTION_N, i)
            if ns.ActionShadowed(i) then title = "|cffff3030" .. title .. L.ACTION_IGNORED .. "|r" end
            listArgs["a" .. i] = { type = "group", inline = true, name = title, order = i, args = args }
        end
        listArgs.add = {
            type = "execute", name = L.OPT_ADD_ACTION, order = #list + 1,
            func = function()
                local l = DB().clickActions
                l[#l + 1] = { mods = "NONE", trigger = "LeftButton", unit = "NONE", mark = "NONE", announce = "SELF", ping = false }
                Options.Refresh()
            end,
        }
    end
    return group
end

---------------------------------------------------------------- Minimap click / ping
local function BlipGroup()
    local args = {}
    BindArgs(args, function() return DB().blipBind end, ns.MOUSE_BUTTONS, 1)
    return {
        type = "group", name = L.GRP_BLIP, order = 4,
        args = { bind = { type = "group", inline = true, name = L.SEC_BLIPBIND, order = 1, args = args } },
    }
end

local function PingGroup()
    local args = {}
    BindArgs(args, function() return DB().pingBind end, ns.PING_TRIGGERS, 1)
    args.note = { type = "description", name = L.OPT_PING_NOTE, order = 10 }
    return {
        type = "group", name = L.GRP_PING, order = 5,
        args = {
            bind = {
                type = "group", inline = true, order = 1, args = args,
                name = function()
                    if ns.db and ns.PingShadowed() then
                        return "|cffff3030" .. L.SEC_PINGBIND .. L.ACTION_IGNORED .. "|r"
                    end
                    return L.SEC_PINGBIND
                end,
            },
        },
    }
end

---------------------------------------------------------------- registration
local registered = false

local function Register()
    if registered then return true end
    if not (ACR and ACD) then
        ns.Print(L.LIBS_MISSING)
        return false
    end
    local root = {
        type = "group", name = L.OPT_TITLE, childGroups = "tree",
        args = {
            general = GeneralGroup(),
            format  = FormatGroup(),
            popup   = PopupGroup(),
            blip    = BlipGroup(),
            ping    = PingGroup(),
            actions = ActionsGroup(),
        },
    }
    actionList()
    ACR:RegisterOptionsTable(APP, root)
    ACD:SetDefaultSize(APP, 860, 640)
    registered = true
    return true
end

function Options.ToggleWindow()
    if not Register() then return end
    if ACD.OpenFrames[APP] then
        ACD:Close(APP)
    else
        actionList()
        ACD:Open(APP)
    end
end

function Options.OpenSettings()
    if Options.categoryID and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(Options.categoryID)
    else
        Options.ToggleWindow()
    end
end

function Options.Init()
    if not Register() then return end
    -- Esc > Options > AddOns: the same tree embedded in the Blizzard settings panel.
    local ok, frame, id = pcall(ACD.AddToBlizOptions, ACD, APP, "ICUfp")
    if ok and frame then
        Options.categoryID = id or frame.name
    else
        ns.Debug("AddToBlizOptions failed: " .. tostring(frame))
    end
end
