local addonName, ns = ...

-- UI: popup with secure rows (one per blip name). Rows run target / focus / mark
-- macros; announce / ping / close run in PostClick. Out of combat only.
local UI = {}
ns.UI = UI

local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local SetPortraitTexture = SetPortraitTexture
local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS
local Minimap = Minimap
local ipairs, tonumber, min, floor = ipairs, tonumber, math.min, math.floor
local wipe, tinsert, tremove = wipe, table.insert, table.remove
local GetCursorPosition, UISpecialFrames = GetCursorPosition, UISpecialFrames
local SetOverrideBindingClick, ClearOverrideBindings = SetOverrideBindingClick, ClearOverrideBindings

local MAX_ROWS   = ns.MAX_ROWS
local ROW_HEIGHT = 24
local ICON       = 20
local PAD        = 6
local CLASS_TEX  = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- Fallback paths when LibSharedMedia is missing or a saved name is not registered.
local DEFAULT_MEDIA = {
    statusbar  = "Interface\\TargetingFrame\\UI-StatusBar",
    background = "Interface\\Buttons\\WHITE8X8", -- flat fill: alpha 1 = fully solid
    border     = "Interface\\Tooltips\\UI-Tooltip-Border",
    font       = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
}
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local function Media(kind, name)
    local path = LSM and name and LSM:Fetch(kind, name, true)
    return path or DEFAULT_MEDIA[kind]
end

-- popup point, relative point on minimap
local ANCHORS = {
    BOTTOMRIGHT = { "TOPRIGHT",    "BOTTOMRIGHT" },
    TOPRIGHT    = { "BOTTOMRIGHT", "TOPRIGHT" },
    BOTTOM      = { "TOP",         "BOTTOM" },
    TOP         = { "BOTTOM",      "TOP" },
    BOTTOMLEFT  = { "TOPLEFT",     "BOTTOMLEFT" },
    TOPLEFT     = { "BOTTOMLEFT",  "TOPLEFT" },
    RIGHT       = { "RIGHT",       "LEFT" },
    LEFT        = { "LEFT",        "RIGHT" },
}

local popup
local rows = {}

-- Secure attribute suffixes per mouse button. Button4/5 get both forms ("4" and
-- "-Button4") since the template's suffix rule for them is not verified here.
local BUTTON_SUFFIX = {
    LeftButton = { "1" }, RightButton = { "2" }, MiddleButton = { "3" },
    Button4 = { "4", "-Button4" }, Button5 = { "5", "-Button5" },
}
local KEY_BTN   = "ICUK"      -- virtual button for key action i: "ICUK" .. i
local CLOSE_BTN = "ICUKCLOSE" -- virtual button for a key close binding
local KEY_PREFIX_PAT = "^" .. KEY_BTN          -- any virtual key button (incl. CLOSE_BTN)
local KEY_INDEX_PAT  = "^" .. KEY_BTN .. "(%d+)$" -- key action index

-- "ALT-CTRL" -> "alt-ctrl-" (secure attribute modifier prefix); "NONE" -> "".
local function ModPrefix(mods)
    if not mods or mods == "NONE" then return "" end
    return mods:lower() .. "-"
end

-- Macro text for a row's unit action. /targetexact avoids partial-name matches.
-- FOCUS: target, focus, then restore the previous target.
-- mark (ns.MARK_LIST key): /tm in the macro (SetRaidTarget is protected). Target is
-- cleared first, so a failed /targetexact (out of range) leaves no target and the
-- [@target,exists] guard skips the mark instead of marking the old target.
-- Unit NONE + mark: target only for the mark, then restore the previous target.
local function UnitMacro(action, name, mark)
    if not mark or mark == "NONE" then
        if action == "TARGET" then
            return "/targetexact " .. name
        elseif action == "FOCUS" then
            return "/targetexact " .. name .. "\n/focus\n/targetlasttarget"
        end
        return "/stopmacro" -- NONE: harmless no-op
    end
    local m = "/cleartarget\n/targetexact " .. name
        .. "\n/tm [@target,exists] " .. (mark == "CLEAR" and "0" or mark)
    if action == "TARGET" then
        return m
    elseif action == "FOCUS" then
        return m .. "\n/focus [@target,exists]\n/targetlasttarget"
    end
    return m .. "\n/targetlasttarget"
end

-- Action for a click: key clicks by virtual button, mouse clicks by button + held mods.
-- Returns action table, or "CLOSE", or nil.
local function ResolveClick(button)
    local list = ns.db.clickActions
    if button == CLOSE_BTN then return "CLOSE" end
    local ki = button:match(KEY_INDEX_PAT)
    if ki then
        ki = tonumber(ki)
        return list[ki] and not ns.ActionShadowed(ki) and list[ki] or nil
    end
    local mods = ns.CurrentMods()
    local cb = ns.db.closeBind
    if cb.trigger == button and (cb.mods or "NONE") == mods then return "CLOSE" end
    for i, a in ipairs(list) do
        if a.trigger == button and (a.mods or "NONE") == mods and not ns.ActionShadowed(i) then
            return a
        end
    end
end

-- Runs after the secure macro (rows register up + down so the macro follows the
-- ActionButtonUseKeyDown CVar). Insecure part (announce, ping, close) runs once per
-- press: mouse on release; key on the first of down/up (binding clicks may send one or both).
local function Row_PostClick(self, button, down)
    if button:find(KEY_PREFIX_PAT) then
        if down then
            self.keySeen[button] = true
        elseif self.keySeen[button] then
            self.keySeen[button] = nil
            return
        end
    elseif down then
        return
    end
    local a = ResolveClick(button)
    if a == "CLOSE" then UI.Hide() return end
    if not a or not self.entry then return end
    local e = self.entry
    -- Row macro just targeted / focused the unit: read full stats from it.
    local token = (a.unit == "TARGET" and "target") or (a.unit == "FOCUS" and "focus") or nil
    local fresh = token and ns.Scan.FreshEntry(e.name, token)
    if fresh then e = fresh end
    ns.Debug("row click: " .. tostring(token) .. " fresh=" .. tostring(fresh ~= nil))
    ns.AnnounceMode(e.chat or e.text, a.announce, e.chatSelf)
    if a.ping then ns.Scan.Ping() end
end

local function CreateRow(i)
    local row = CreateFrame("Button", "ICUfpRow" .. i, popup, "SecureActionButtonTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -PAD - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", popup, "RIGHT", -PAD, 0)
    row:RegisterForClicks("AnyUp", "AnyDown")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.attrKeys = {} -- secure attributes set by the last FillRow (cleared on refill)
    row.keySeen = {}  -- virtual key buttons whose down event already ran (Row_PostClick)
    -- Key bindings only while this row is hovered (popup is never shown in combat).
    row:SetScript("OnEnter", function(self) UI.BindKeys(self) end)
    row:SetScript("OnLeave", function() UI.BindKeys(nil) end)

    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(ICON, ICON)
    row.portrait:SetPoint("LEFT", 2, 0)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(ICON, ICON)
    row.classIcon:SetPoint("LEFT", row.portrait, "RIGHT", 2, 0)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 4, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    row.bar:SetStatusBarTexture(DEFAULT_MEDIA.statusbar)
    row.bar:SetMinMaxValues(0, 100)
    row.bar:SetFrameLevel(row:GetFrameLevel())

    row.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(DEFAULT_MEDIA.statusbar)

    row.text = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.bar, "LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")

    row:SetScript("PostClick", Row_PostClick)
    row:Hide()
    return row
end

-- Set a secure attribute and remember its key so the next FillRow can clear it.
local function SetAttr(row, k, v)
    row:SetAttribute(k, v)
    row.attrKeys[#row.attrKeys + 1] = k
end

local function FillRow(row, e)
    row.entry = e
    -- Secure unit actions from the action list (caller guarantees out of combat).
    for _, k in ipairs(row.attrKeys) do row:SetAttribute(k, nil) end
    wipe(row.attrKeys)
    for i, a in ipairs(ns.db.clickActions) do
        if not ns.ActionShadowed(i) then
            local macro = UnitMacro(a.unit, e.name, a.mark)
            if a.trigger == "KEY" then
                SetAttr(row, "*type-" .. KEY_BTN .. i, "macro")
                SetAttr(row, "*macrotext-" .. KEY_BTN .. i, macro)
            elseif BUTTON_SUFFIX[a.trigger] then
                local p = ModPrefix(a.mods)
                for _, sfx in ipairs(BUTTON_SUFFIX[a.trigger]) do
                    SetAttr(row, p .. "type" .. sfx, "macro")
                    SetAttr(row, p .. "macrotext" .. sfx, macro)
                end
            end
        end
    end

    -- Portrait slot only when enabled; otherwise class icon takes the row's left edge.
    row.classIcon:ClearAllPoints()
    if ns.db.showPortraits then
        row.classIcon:SetPoint("LEFT", row.portrait, "RIGHT", 2, 0)
        if e.unit then
            SetPortraitTexture(row.portrait, e.unit)
            row.portrait:Show()
        else
            row.portrait:Hide()
        end
    else
        row.classIcon:SetPoint("LEFT", 2, 0)
        row.portrait:Hide()
    end
    local tc = e.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.classFile]
    if tc then
        row.classIcon:SetTexture(CLASS_TEX)
        row.classIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        row.classIcon:Show()
    else
        row.classIcon:Hide()
    end

    row.bar:SetStatusBarColor(e.r, e.g, e.b, 0.6)
    if e.hpSecret then
        -- Secret health: widgets accept it directly.
        row.bar:SetMinMaxValues(0, e.hpMaxS)
        row.bar:SetValue(e.hpS)
    else
        row.bar:SetMinMaxValues(0, 100)
        row.bar:SetValue(e.health or 0)
    end
    row.bg:SetVertexColor(e.r, e.g, e.b, 0.15)
    -- Width from a separate FontString that never holds secrets (row.text keeps a
    -- secret width once it has shown a secret value).
    popup.measure:SetText(e.measure or e.text)
    local w = popup.measure:GetStringWidth()
    row.text:SetText(e.text)
    if e.rowColor then
        row.text:SetTextColor(e.rr, e.rg, e.rb) -- reaction color, whole row
    else
        row.text:SetTextColor(min(e.r + 0.3, 1), min(e.g + 0.3, 1), min(e.b + 0.3, 1)) -- lighter than bar
    end
    row:Show()
    return w
end

UI.ANCHOR_LIST = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "CURSOR", "FREE" }
UI.unlocked = false      -- true while the FREE move preview is shown
UI.layoutPending = false -- layout change blocked by combat; applied on PLAYER_REGEN_ENABLED

UI.cursorX, UI.cursorY = nil, nil -- click point (UIParent coords) for CURSOR mode

-- Popup holds secure rows, so it can't be moved in combat: defer instead.
function UI.SetAnchor()
    if not popup then return end
    if InCombatLockdown() then UI.layoutPending = true return end
    popup:ClearAllPoints()
    local ox, oy = ns.db.popupX or 0, ns.db.popupY or 0
    if ns.db.anchor == "CURSOR" then
        -- Popup center at the click point (+ offsets); stays until hidden.
        if UI.cursorX then
            popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", UI.cursorX + ox, UI.cursorY + oy)
        else
            popup:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        end
    elseif ns.db.anchor == "FREE" then
        local pos = ns.db.popupPos
        if pos then
            popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
        else
            popup:SetPoint("TOPLEFT", UIParent, "CENTER", 0, 0)
        end
    else
        local a = ANCHORS[ns.db.anchor] or ANCHORS.BOTTOMRIGHT
        popup:SetPoint(a[1], MinimapCluster or Minimap, a[2], ox, oy)
    end
end

-- Key actions + key close binding as override bindings while the mouse is over a
-- popup row (row) or the popup background (row = nil, close key only -> row 1).
-- Owner = popup; any call first clears the previous set. Out of combat only.
function UI.BindKeys(row, closeOnly)
    if not popup or InCombatLockdown() then return end
    ClearOverrideBindings(popup)
    if closeOnly == "clear" then return end
    local cb = ns.db.closeBind
    local target = row or (closeOnly and rows[1])
    if not target then return end
    if cb.trigger == "KEY" and cb.key then
        SetOverrideBindingClick(popup, true, cb.key, target:GetName(), CLOSE_BTN)
    end
    if not row then return end
    for i, a in ipairs(ns.db.clickActions) do
        if a.trigger == "KEY" and a.key and not ns.ActionShadowed(i) then
            SetOverrideBindingClick(popup, true, a.key, row:GetName(), KEY_BTN .. i)
        end
    end
end

function UI.Hide()
    if not popup or InCombatLockdown() then return end
    if UI.unlocked then return end -- keep move preview visible
    for i = 1, MAX_ROWS do
        rows[i].entry = nil
        rows[i]:Hide()
    end
    popup:Hide()
end

-- Fill rows and show the popup. Width follows the widest row text.
function UI.Show(entries)
    if InCombatLockdown() or UI.unlocked then return false end
    UI.Hide()
    local maxW = 0
    local n = min(#entries, MAX_ROWS)
    for i = 1, n do
        local w = FillRow(rows[i], entries[i])
        if w > maxW then maxW = w end
    end
    if n == 0 then return false end
    local icons = ns.db.showPortraits and (2 * ICON + 24) or (ICON + 22) -- icons + gaps
    popup:SetWidth(maxW + icons + 2 * PAD)
    popup:SetHeight(n * ROW_HEIGHT + 2 * PAD)
    popup.hideTimer = 0
    if ns.db.anchor == "CURSOR" then
        -- Remember the click point; popup stays there while shown.
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        UI.cursorX, UI.cursorY = x / s, y / s
        UI.SetAnchor()
    end
    popup:Show()
    return true
end

-- Free-move preview: shown while anchor == FREE and the lock box is unticked.
function UI.Unlock()
    if not popup or InCombatLockdown() or ns.db.anchor ~= "FREE" then return end
    UI.unlocked = false
    UI.Hide()
    UI.unlocked = true
    popup.moveLabel:Show()
    popup:SetSize(220, 40)
    popup:SetMovable(true)
    popup:Show()
end

-- End the move preview and tick the Locked box. No-op if the preview is not open.
function UI.Lock()
    if not popup or not UI.unlocked then return end
    UI.unlocked = false
    popup.moveLabel:Hide()
    popup:StopMovingOrSizing()
    popup:SetMovable(false)
    if not ns.db.popupLocked then
        ns.db.popupLocked = true
        ns.Options.Refresh()
    end
    UI.Hide()
end

-- Background opacity from db.popupAlpha (rows / text / border stay opaque).
function UI.ApplyAlpha()
    if not popup then return end
    popup:SetBackdropColor(0.09, 0.09, 0.19, ns.db.popupAlpha or 0.9) -- 0.05..1
end

-- Textures + font from db (backdrop, row bars, row text). Safe in combat: no
-- secure attributes or positions change.
function UI.ApplyAppearance()
    if not popup then return end
    local db = ns.db
    local edge = db.borderSize or 16
    local inset = floor(edge / 4 + 0.5)
    popup:SetBackdrop({
        bgFile   = Media("background", db.bgTexture),
        edgeFile = Media("border", db.borderTexture),
        tile = true, tileSize = 16, edgeSize = edge,
        insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    popup:SetBackdropBorderColor(1, 1, 1, 1)
    UI.ApplyAlpha()
    local bar = Media("statusbar", db.barTexture)
    local font, size = Media("font", db.font), db.fontSize or 10
    for i = 1, MAX_ROWS do
        local r = rows[i]
        r.bar:SetStatusBarTexture(bar)
        r.bg:SetTexture(bar)
        r.text:SetFont(font, size, "")
    end
    popup.measure:SetFont(font, size, "")
end

-- Esc closes the popup only when db.closeEsc is on (UISpecialFrames membership).
function UI.ApplyEsc()
    local idx
    for i, name in ipairs(UISpecialFrames) do
        if name == "ICUfpPopup" then idx = i break end
    end
    if ns.db.closeEsc and not idx then
        tinsert(UISpecialFrames, "ICUfpPopup")
    elseif not ns.db.closeEsc and idx then
        tremove(UISpecialFrames, idx)
    end
end

-- Apply db.anchor / db.popupLocked (deferred to end of combat if needed).
function UI.ApplyLayout()
    if InCombatLockdown() then UI.layoutPending = true return end
    UI.layoutPending = false
    UI.SetAnchor()
    if ns.db.anchor == "FREE" and not ns.db.popupLocked then
        UI.Unlock()
    elseif UI.unlocked then
        UI.Lock()
    end
end

function UI.Init()
    popup = CreateFrame("Frame", "ICUfpPopup", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:EnableMouse(true)
    popup:SetClampedToScreen(true)
    popup:Hide()

    popup.moveLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.moveLabel:SetPoint("CENTER")
    popup.moveLabel:SetText(ns.L.MOVE_PREVIEW)
    popup.moveLabel:Hide()

    -- Width-measuring FontString (never holds secrets, see FillRow).
    popup.measure = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    popup.measure:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, 10000) -- off-screen
    popup.measure:SetAlpha(0)

    for i = 1, MAX_ROWS do rows[i] = CreateRow(i) end
    UI.ApplyAppearance()
    -- Media registered by addons loading after us: re-apply only when a name the
    -- popup uses gets registered (not once per registration of every media pack).
    if LSM then
        local USED = { statusbar = "barTexture", background = "bgTexture", border = "borderTexture", font = "font" }
        LSM.RegisterCallback(UI, "LibSharedMedia_Registered", function(_, mediatype, key)
            local field = USED[mediatype]
            if field and ns.db[field] == key then UI.ApplyAppearance() end
        end)
    end

    -- Dragging (only while unlocked).
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self)
        if UI.unlocked and not InCombatLockdown() then self:StartMoving() end
    end)
    popup:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.db.popupPos = { self:GetLeft(), self:GetTop() }
        UI.SetAnchor()
    end)

    -- Timer close (db.closeTimer): db.closeDelay seconds after the mouse leaves
    -- minimap + popup. Throttled to 0.1s; runs only while shown.
    local elapsedSum = 0
    popup.hideTimer = 0
    popup:SetScript("OnUpdate", function(self, elapsed)
        elapsedSum = elapsedSum + elapsed
        if elapsedSum < 0.1 then return end
        local step = elapsedSum
        elapsedSum = 0
        if UI.unlocked then return end
        if Minimap:IsMouseOver() or self:IsMouseOver() then
            self.hideTimer = 0
            return
        end
        if not ns.db.closeTimer then return end
        self.hideTimer = self.hideTimer + step
        if self.hideTimer < (ns.db.closeDelay or 1.5) then return end
        UI.Hide()
    end)
    -- Close binding on the popup background (mouse) / while hovering it (key).
    popup:SetScript("OnMouseUp", function(_, button)
        local cb = ns.db.closeBind
        if not UI.unlocked and cb.trigger == button and (cb.mods or "NONE") == ns.CurrentMods() then
            UI.Hide()
        end
    end)
    popup:SetScript("OnEnter", function() if not UI.unlocked then UI.BindKeys(nil, true) end end)
    popup:SetScript("OnLeave", function() UI.BindKeys(nil, "clear") end)
    -- Click-outside close (db.closeClick): listen only while shown.
    popup:SetScript("OnEvent", function(self)
        if not UI.unlocked and not self:IsMouseOver() then UI.Hide() end
    end)
    popup:SetScript("OnShow", function(self)
        if ns.db.closeClick and not UI.unlocked then
            pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
        end
    end)
    -- Esc during move preview = done moving.
    popup:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        if not InCombatLockdown() then ClearOverrideBindings(self) end
        if UI.unlocked then UI.Lock() end
    end)
    UI.ApplyEsc()
    UI.ApplyLayout()
end
