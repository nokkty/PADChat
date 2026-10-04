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

local function Print(text) print("|cff33ff99VGS Chat|r: " .. text) end

ns.CHOICES, ns.KEY_COLOR, ns.Print = CHOICES, KEY_COLOR, Print
ns.CHAT_TYPES = { "SAY", "GROUP", "RAID" }
ns.CHAT_LABELS = { SAY = "Say", GROUP = "Group", RAID = "Raid/Battleground" }
ns.CONTEXTS = { "DEFAULT", "GROUP", "RAID" }
ns.CONTEXT_LABELS = { DEFAULT = "Default", GROUP = "Group", RAID = "Raid/BG" }
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
ns.CopyMenu = DeepCopy

function ns.GetMenu()
	return ns.DB and ns.DB.menu or ns.DefaultMenu
end

function ns.GetContext()
	if IsInRaid() then return "RAID" end
	return IsInGroup() and "GROUP" or "DEFAULT"
end

-- A variant replaces one option (including its children). Missing variants
-- inherit; false explicitly clears the slot. Empty anchors hold variants for
-- a slot that has no default option.
function ns.PickNode(node, context)
	if not node then return nil end
	local variants, condition = node.variants, nil
	if variants then
		if context == "RAID" and variants.RAID ~= nil then condition = "RAID"
		elseif context ~= "DEFAULT" and variants.GROUP ~= nil then condition = "GROUP" end
	end
	if condition then node = variants[condition] end
	return node and not node.empty and node or nil, condition
end

function ns.ResolveNode(node, context)
	node = ns.PickNode(node, context)
	if not node then return nil end
	local result = { label = node.label, text = node.text, chat = node.chat }
	if node.text == nil then
		for _, key in ipairs(CHOICES) do result[key] = ns.ResolveNode(node[key], context) end
	end
	return result
end

function ns.ChannelAvailable(chat, context)
	return chat == "SAY" or chat == nil or chat == "GROUP" and context ~= "DEFAULT" or chat == "RAID" and context == "RAID"
end

-- Group follows the player's current party/raid. Instance chat takes priority
-- over a separate home group, matching the game's chat channel rules.
function ns.GetChannel(chat)
	if not chat or chat == "SAY" then return "SAY" end
	local instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	if chat == "GROUP" then
		if instance then return "INSTANCE_CHAT" end
		if IsInRaid() then return "RAID" end
		if IsInGroup() then return "PARTY" end
	elseif chat == "RAID" then
		if instance and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
		if IsInRaid(LE_PARTY_CATEGORY_HOME) then return "RAID" end
	end
end

function ns.MigrateMenu(node)
	if type(node) ~= "table" then return end
	if node.text ~= nil then
		local chat = node.chat and node.chat:upper() or "SAY"
		if chat == "PARTY" then chat = "GROUP"
		elseif chat == "INSTANCE_CHAT" or chat == "BATTLEGROUND" then chat = "RAID" end
		node.chat = ns.CHAT_LABELS[chat] and chat or "SAY"
	end
	for _, key in ipairs(CHOICES) do ns.MigrateMenu(node[key]) end
	for _, variant in pairs(node.variants or {}) do ns.MigrateMenu(variant) end
end

local activeMenus = {}
for _, context in ipairs(ns.CONTEXTS) do activeMenus[context] = ns.ResolveNode(ns.DefaultMenu, context) end

------------------------------------------------------------------------
-- Menu lookup
------------------------------------------------------------------------
local function NodeAt(path, context)
	local node = activeMenus[context or "DEFAULT"]
	for i = 1, #path do
		node = node and node[path:sub(i, i)]
	end
	return node
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
			self:SetAttribute("menucontext", self:GetAttribute("state-context") or "DEFAULT")
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
	local context = self:GetAttribute("menucontext") or "DEFAULT"
	local kind = self:GetAttribute("node-" .. context .. "-" .. path)
	if kind == "leaf" then
		self:SetAttribute("sentpath", path)
		self:SetAttribute("sentcontext", context)
		self:SetAttribute("sentseq", (self:GetAttribute("sentseq") or 0) + 1)
		self:ClearBindings()
		self:SetAttribute("open", nil)
		self:SetAttribute("path", "")
	elseif kind == "branch" then
		self:SetAttribute("path", path)
	end
]]):format(KEYS.A, KEYS.X, KEYS.Y, KEYS.B))

-- Native state drivers can switch between already-published menu shapes in
-- combat. The context stays fixed during an open menu so button paths don't
-- change meaning halfway through a selection.
RegisterStateDriver(open, "context", "[group:raid] RAID; [group] GROUP; DEFAULT")

-- The snippet only knows the menu's shape, published as node-<path> attributes.
-- Protected attributes can only be set out of combat. Keep the active data and
-- shape together until combat ends and the current quick chat menu closes.
local publishedPaths = {}
local menuDirty = true

local function PublishMenu()
	if not menuDirty or InCombatLockdown() or open:GetAttribute("open") then return end
	local snapshots = {}
	for path in pairs(publishedPaths) do
		open:SetAttribute("node-" .. path, nil)
	end
	wipe(publishedPaths)
	local function Walk(node, path, context)
		for _, key in ipairs(CHOICES) do
			local child = node[key]
			if child then
				local childPath = path .. key
				local attributePath = context .. "-" .. childPath
				if not child.text or ns.ChannelAvailable(child.chat, context) then
					open:SetAttribute("node-" .. attributePath, child.text and "leaf" or "branch")
					publishedPaths[attributePath] = true
				end
				if not child.text then Walk(child, childPath, context) end
			end
		end
	end
	for _, context in ipairs(ns.CONTEXTS) do
		snapshots[context] = ns.ResolveNode(ns.GetMenu(), context)
		Walk(snapshots[context], "", context)
	end
	activeMenus = snapshots
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
	local chatType = ns.GetChannel(node.chat)
	if not chatType then
		Print("Join a " .. (node.chat == "RAID" and "raid or battleground" or "group") .. " to send this message.")
		return
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok, err = pcall(send, node.text, chatType)
	if not ok then Print("|cffff5050Couldn't send:|r " .. tostring(err)) end
end
ns.SendNode = SendNode -- the editor's "Send now" (a click, so /say is allowed)

------------------------------------------------------------------------
-- On-screen menu
------------------------------------------------------------------------
-- Shared with the editor so controller buttons look the same in both places.
function ns.MakeBadge(parent, key, size)
	size = size or 40
	local hex = KEY_COLOR[key]
	local badge = parent:CreateTexture(nil, "ARTWORK")
	badge:SetSize(size, size)
	badge:SetPoint("LEFT", 12, 0)
	badge:SetColorTexture(tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(badge)
	badge:AddMaskTexture(mask)
	local letter = parent:CreateFontString(nil, "OVERLAY", size >= 40 and "GameFontNormalHuge" or "GameFontHighlight")
	letter:SetPoint("CENTER", badge, "CENTER", 0, 0)
	letter:SetTextColor(0.05, 0.05, 0.05)
	letter:SetText(key)
	return badge
end

-- The editor uses the same view for its preview.
function ns.CreateMenuView(parent, name)
	local menu = CreateFrame("Frame", name, parent)
	menu:SetSize(260, 160)
	menu:Hide()

	local edge = menu:CreateTexture(nil, "BACKGROUND", nil, 0)
	edge:SetAllPoints()
	edge:SetColorTexture(0.29, 0.27, 0.22, 0.9)

	local bg = menu:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.09, 0.09, 0.1, 0.96)

	local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetWidth(232)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(true)

	local sequence = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sequence:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sequence:SetTextColor(0.7, 0.68, 0.63)

	local headerLine = menu:CreateTexture(nil, "ARTWORK")
	headerLine:SetSize(232, 1)
	headerLine:SetColorTexture(0.29, 0.27, 0.22, 0.7)

	local rows = {}
	for _, key in ipairs(CHOICES) do
		local row = CreateFrame("Frame", nil, menu)
		row:SetSize(232, 30)
		row.badge = ns.MakeBadge(row, key, 22)
		row.badge:SetPoint("LEFT", 0, 0)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		row.label:SetPoint("TOPLEFT", 34, -6)
		row.label:SetWidth(178)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(true)
		row.arrow = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		row.arrow:SetPoint("RIGHT", 0, 0)
		row.arrow:SetText(">")
		row.arrow:SetTextColor(0.7, 0.68, 0.63)
		rows[key] = row
	end

	local footer = CreateFrame("Frame", nil, menu)
	footer:SetSize(232, 28)
	local footerLine = footer:CreateTexture(nil, "ARTWORK")
	footerLine:SetPoint("TOPLEFT")
	footerLine:SetPoint("TOPRIGHT")
	footerLine:SetHeight(1)
	footerLine:SetColorTexture(0.29, 0.27, 0.22, 0.7)
	local cancelBadge = ns.MakeBadge(footer, "B", 18)
	cancelBadge:SetPoint("LEFT", 0, -4)
	cancelBadge:SetAlpha(0.65)
	local cancel = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cancel:SetPoint("LEFT", cancelBadge, "RIGHT", 8, 0)
	cancel:SetText("Cancel")
	cancel:SetTextColor(0.7, 0.68, 0.63)

	function menu:Display(node, heading, path, context)
		path = path or ""
		title:SetText(heading)
		sequence:SetShown(path ~= "")
		sequence:SetText((path:gsub(".", "%0  ")):gsub("  $", ""))
		local y = 12 + title:GetStringHeight() + (path ~= "" and 18 or 0) + 10
		headerLine:SetPoint("TOPLEFT", 14, -y)
		y = y + 5
		for _, key in ipairs(CHOICES) do
			local child = node[key]
			local row = rows[key]
			row.label:SetText(child and ((child.label ~= "" and child.label) or child.text or "?") or "—")
			local available = child and (not child.text or ns.ChannelAvailable(child.chat, context or ns.GetContext()))
			row.label:SetTextColor(available and 0.94 or 0.5, available and 0.92 or 0.5, available and 0.89 or 0.5)
			row.badge:SetAlpha(available and 1 or 0.35)
			row.arrow:SetShown(child ~= nil and not child.text)
			local height = math.max(30, row.label:GetStringHeight() + 12)
			row:SetHeight(height)
			row:SetPoint("TOPLEFT", 14, -y)
			y = y + height
		end
		footer:SetPoint("TOPLEFT", 14, -y - 4)
		menu:SetHeight(y + 4 + 28 + 12)
		menu:Show()
	end
	return menu
end

local menu = ns.CreateMenuView(UIParent, "VGSChatMenu")
menu:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
menu:SetFrameStrata("HIGH")

local function UpdateMenu()
	if not open:GetAttribute("open") then menu:Hide(); return end
	local path = open:GetAttribute("path") or ""
	local context = open:GetAttribute("menucontext") or "DEFAULT"
	local node = NodeAt(path, context) or activeMenus[context]
	menu:Display(node, path == "" and "Quick Chat" or (node.label ~= "" and node.label or nil) or "Group", path, ns.GetContext())
end

-- Runs after the secure snippet, inside the same button press.
open:HookScript("OnClick", function(self)
	local seq = self:GetAttribute("sentseq") or 0
	if seq ~= lastSeq then
		lastSeq = seq
		SendNode(NodeAt(self:GetAttribute("sentpath") or "", self:GetAttribute("sentcontext")))
	end
	PublishMenu()
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
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		-- Whether the client handed back saved settings; the editor shows it so
		-- a return of the beta's "SavedVariables never load" bug is visible.
		ns.savedLoaded = type(VGSChatDB) == "table" and type(VGSChatDB.menu) == "table"
		if type(VGSChatDB) ~= "table" then VGSChatDB = {} end
		ns.DB = VGSChatDB
		if type(ns.DB.menu) ~= "table" then ns.DB.menu = DeepCopy(ns.DefaultMenu) end
		ns.MigrateMenu(ns.DB.menu)
		ns.DB.version = 2
	end
	PublishMenu()
	UpdateMenu()
	if event == "UPDATE_MACROS" then macrosLoaded = true end
	if macrosLoaded and not macroReady then macroReady = EnsureMacro() end
end)
