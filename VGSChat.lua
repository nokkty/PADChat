-- VGS Chat: Tribes 2 Voice Game System style quick chat for WoW Forever gamepads.
--
-- The player presses the "VGSChat" macro (placed anywhere on their bars). Its
-- /click hits a SecureHandler button whose snippet takes over A/X/Y/B with
-- priority override bindings, walks the menu one press at a time, and releases
-- the buttons again when a message is chosen or B cancels. Binding changes have
-- to happen in a secure snippet to work in combat.
--
-- The snippet can't send chat, so it bumps a "sentseq" attribute; the OnClick
-- hook below runs right after it, inside the same button press (a hardware
-- event, which /say needs outdoors), and sends the message.
--
-- Never touches the chat edit box and registers no slash commands: both taint
-- Forever's gamepad UI.

local ADDON, ns = ...

local MACRO_NAME = "VGSChat"
-- Macros need a numeric icon file ID; a texture path is accepted but leaves
-- the macro iconless, and the client then won't let it be placed on a bar.
local MACRO_ICON = 132333 -- Ability_Warrior_BattleShout
local MACRO_FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark
local MACRO_BODY = "/click VGSChatOpen LeftButton 1"

-- Xbox naming; the PAD codes are the same on every controller.
local KEYS = { A = "PAD1", B = "PAD2", X = "PAD3", Y = "PAD4" }
local CHOICES = { "A", "X", "Y" }
local KEY_COLOR = { A = "ff60d060", X = "ff4aa3ff", Y = "ffffd100", B = "ffff5050" }
local ALLOWED_CHAT = { SAY = true, YELL = true, EMOTE = true }

local function Print(text) print("|cff33ff99VGS Chat|r: " .. text) end

ns.CHOICES, ns.KEY_COLOR, ns.Print = CHOICES, KEY_COLOR, Print
ns.CHAT_TYPES = { "SAY", "YELL", "EMOTE" }
ns.MAX_DEPTH = 4 -- presses per message, counting the last one

------------------------------------------------------------------------
-- Saved menu. VGSChatDB.menu is the player's copy, seeded from
-- ns.DefaultMenu (Messages.lua) on first run and by "Reset to defaults".
------------------------------------------------------------------------
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end

function ns.GetMenu()
	return ns.DB and ns.DB.menu or ns.DefaultMenu
end

------------------------------------------------------------------------
-- Menu lookup
------------------------------------------------------------------------
local function NodeAt(path)
	local node = ns.GetMenu()
	for i = 1, #path do
		node = node and node[path:sub(i, i)]
	end
	return node
end

local function PathLabels(path)
	local labels, node = {}, ns.GetMenu()
	for i = 1, #path do
		node = node[path:sub(i, i)]
		labels[#labels + 1] = node.label or "?"
	end
	return table.concat(labels, " > ")
end

------------------------------------------------------------------------
-- Secure open button (the state machine)
------------------------------------------------------------------------
local open = CreateFrame("Button", "VGSChatOpen", UIParent, "SecureHandlerClickTemplate")
open:RegisterForClicks("AnyDown")

-- LeftButton = the macro (toggle); A/X/Y/B = the override-bound pad buttons,
-- which click this same button with the letter as the mouse button.
-- The restricted environment rejects the word "function" anywhere in a
-- snippet, comments included, so the close steps are repeated inline.
open:SetAttribute("_onclick", ([[
	if button == "LeftButton" then
		if self:GetAttribute("open") then
			self:ClearBindings()
			self:SetAttribute("open", nil)
			self:SetAttribute("path", "")
		else
			self:SetAttribute("open", 1)
			self:SetAttribute("path", "")
			self:SetBindingClick(true, "%s", "VGSChatOpen", "A")
			self:SetBindingClick(true, "%s", "VGSChatOpen", "X")
			self:SetBindingClick(true, "%s", "VGSChatOpen", "Y")
			self:SetBindingClick(true, "%s", "VGSChatOpen", "B")
		end
		return
	end

	if not self:GetAttribute("open") then return end
	if button == "B" then
		self:ClearBindings()
		self:SetAttribute("open", nil)
		self:SetAttribute("path", "")
		return
	end

	local path = (self:GetAttribute("path") or "") .. button
	local kind = self:GetAttribute("node-" .. path)
	if kind == "leaf" then
		self:SetAttribute("sentpath", path)
		self:SetAttribute("sentseq", (self:GetAttribute("sentseq") or 0) + 1)
		self:ClearBindings()
		self:SetAttribute("open", nil)
		self:SetAttribute("path", "")
	elseif kind == "branch" then
		self:SetAttribute("path", path)
	end
]]):format(KEYS.A, KEYS.X, KEYS.Y, KEYS.B))

-- The snippet only knows the menu's shape, published as node-<path> attributes.
-- Protected attributes can only be set out of combat, so edits made in combat
-- wait for PLAYER_REGEN_ENABLED.
local publishedPaths = {}
local menuDirty = true

local function PublishMenu()
	if not menuDirty or InCombatLockdown() then return end
	for path in pairs(publishedPaths) do
		open:SetAttribute("node-" .. path, nil)
	end
	wipe(publishedPaths)
	local function Walk(node, path)
		for _, key in ipairs(CHOICES) do
			local child = node[key]
			if child then
				local childPath = path .. key
				open:SetAttribute("node-" .. childPath, child.text and "leaf" or "branch")
				publishedPaths[childPath] = true
				if not child.text then Walk(child, childPath) end
			end
		end
	end
	Walk(ns.GetMenu(), "")
	menuDirty = false
end

-- Called by the editor after every change.
function ns.MenuChanged()
	menuDirty = true
	PublishMenu()
end

function ns.IsPublishPending() return menuDirty end

function ns.ResetToDefaults()
	ns.DB.menu = DeepCopy(ns.DefaultMenu)
	ns.MenuChanged()
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
local lastSeq = 0

local function SendNode(node)
	if not (node and node.text and node.text ~= "") then return end
	local chatType = node.chat and node.chat:upper() or "SAY"
	if not ALLOWED_CHAT[chatType] then chatType = "SAY" end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok, err = pcall(send, node.text, chatType)
	if not ok then Print("|cffff5050Couldn't send:|r " .. tostring(err)) end
end
ns.SendNode = SendNode -- the editor's "Send now" (a click, so /say is allowed)

------------------------------------------------------------------------
-- On-screen menu
------------------------------------------------------------------------
local menu = CreateFrame("Frame", "VGSChatMenu", UIParent)
menu:SetSize(260, 150)
menu:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
menu:SetFrameStrata("HIGH")
menu:Hide()

local bg = menu:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.7)

local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -10)
title:SetPoint("RIGHT", -12, 0)
title:SetJustifyH("LEFT")

local rows = {}
for i, key in ipairs({ "A", "X", "Y", "B" }) do
	local fs = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	fs:SetPoint("TOPLEFT", 14, -10 - i * 28)
	fs:SetPoint("RIGHT", -12, 0)
	fs:SetJustifyH("LEFT")
	rows[key] = fs
end

local function UpdateMenu()
	if not open:GetAttribute("open") then
		menu:Hide()
		return
	end
	local path = open:GetAttribute("path") or ""
	local node = NodeAt(path) or ns.GetMenu()
	title:SetText(path == "" and "Quick Chat" or ("Quick Chat > " .. PathLabels(path)))
	for _, key in ipairs(CHOICES) do
		local child = node[key]
		local label = child and ((child.label or child.text) .. (child.text and "" or "  >")) or "|cff808080-|r"
		rows[key]:SetText("|c" .. KEY_COLOR[key] .. key .. "|r   " .. label)
	end
	rows.B:SetText("|c" .. KEY_COLOR.B .. "B|r   Cancel")
	menu:Show()
end

-- Runs after the secure snippet, inside the same button press.
open:HookScript("OnClick", function(self)
	local seq = self:GetAttribute("sentseq") or 0
	if seq ~= lastSeq then
		lastSeq = seq
		SendNode(NodeAt(self:GetAttribute("sentpath") or ""))
	end
	UpdateMenu()
end)

------------------------------------------------------------------------
-- The macro the player puts on a bar
------------------------------------------------------------------------
-- Two account macros: one opens the quick chat menu, one opens the editor.
local MACROS = {
	{ name = MACRO_NAME, body = MACRO_BODY, icon = MACRO_ICON,
		hint = "|cffffd100VGSChat|r (opens the quick chat menu)" },
	{ name = "VGSEdit", body = "/click VGSChatEditorToggle", icon = MACRO_FALLBACK_ICON,
		hint = "|cffffd100VGSEdit|r (opens the menu editor)" },
}

local function EnsureOneMacro(m)
	local index = GetMacroIndexByName(m.name)
	if index and index > 0 then
		local _, icon, body = GetMacroInfo(index)
		-- Keep whatever icon the player picked; only fill one in if it's missing.
		local fixIcon = (icon == nil or icon == 0 or icon == "")
		if body ~= m.body or fixIcon then
			EditMacro(index, m.name, fixIcon and m.icon or nil, m.body)
		end
		return true
	end
	local numAccount = GetNumMacros()
	if numAccount and numAccount >= (MAX_ACCOUNT_MACROS or 120) then
		Print("|cffff5050No free account macro slot|r for " .. m.hint .. ". Free one and /reload.")
		return true
	end
	if not pcall(CreateMacro, m.name, m.icon, m.body, nil) then
		CreateMacro(m.name, MACRO_FALLBACK_ICON, m.body, nil)
	end
	Print("Created the " .. m.hint .. " macro. Find it in the Macros window (account tab) and put it on a bar.")
	return true
end

local function EnsureMacro()
	if InCombatLockdown() then return false end
	for _, m in ipairs(MACROS) do EnsureOneMacro(m) end
	return true
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
-- Macros arrive from the server a moment after login; checking before
-- UPDATE_MACROS would miss the existing macro and create a duplicate.
local macrosLoaded, macroReady = false, false
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UPDATE_MACROS")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		-- Whether the client handed back saved settings; the editor shows it so
		-- a return of the beta's "SavedVariables never load" bug is visible.
		ns.savedLoaded = type(VGSChatDB) == "table" and type(VGSChatDB.menu) == "table"
		if type(VGSChatDB) ~= "table" then VGSChatDB = {} end
		ns.DB = VGSChatDB
		if type(ns.DB.menu) ~= "table" then ns.DB.menu = DeepCopy(ns.DefaultMenu) end
		ns.DB.version = 1
	end
	PublishMenu()
	if event == "UPDATE_MACROS" then macrosLoaded = true end
	if macrosLoaded and not macroReady then macroReady = EnsureMacro() end
end)
