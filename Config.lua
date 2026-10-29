local addonName, ns = ...
local L = ns.L

local function Slash(msg)
    msg = (msg or ""):upper()
    local cmd, arg = msg:match("^%s*(%S*)%s*(%S*)")

    if cmd == "" then
        ns.Options.ToggleWindow()
    elseif cmd == "CONFIG" then
        ns.Options.OpenSettings()
    elseif cmd == "ANNOUNCE" then
        if arg == "PR" then arg = "AUTO" end
        if L.CHANNEL_NAMES[arg] then
            ns.db.channels[arg] = not ns.db.channels[arg] or nil
            ns.Print(L.CHANNEL_TOGGLED:format(arg, ns.db.channels[arg] and "on" or "off"))
            ns.Options.Refresh()
        else
            ns.Print(L.CHANNEL_BAD)
        end
    elseif cmd == "ANCHOR" then
        if L.ANCHOR_NAMES[arg] then
            ns.db.anchor = arg
            ns.UI.ApplyLayout()
            ns.Print(L.ANCHOR_SET:format(arg))
            ns.Options.Refresh()
        else
            ns.Print(L.ANCHOR_BAD)
        end
    elseif cmd == "DEBUG" then
        ns.db.debug = not ns.db.debug
        ns.Print(L.DEBUG_SET:format(tostring(ns.db.debug)))
        ns.Options.Refresh()
    else
        for _, line in ipairs(L.HELP) do ns.Print(line) end
    end
end

SLASH_ICUFP1 = "/icu"
SlashCmdList.ICUFP = Slash
