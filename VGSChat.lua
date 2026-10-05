-- VGS Chat: Tribes 2 Voice Game System style quick chat for WoW Forever gamepads.
--
-- The player presses the "VGSChat" macro (placed anywhere on their bars). Its
-- /click hits a SecureHandler button whose snippet takes over A/X/Y/B/LB/RB with
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
local KEYS = { A = "PAD1", B = "PAD2", X = "PAD3", Y = "PAD4", LB = "PADLSHOULDER", RB = "PADRSHOULDER" }
local CHOICES = { "A", "X", "Y" }
local KEY_COLOR = { A = "ff60d060", X = "ff4aa3ff", Y = "ffffd100", B = "ffff5050" }

local function Print(text) print("|cff33ff99VGS Chat|r: " .. text) end

ns.CHOICES, ns.KEY_COLOR, ns.Print = CHOICES, KEY_COLOR, Print
ns.CONTEXTS = { "DEFAULT", "GROUP", "RAID" }
-- Retain the saved RAID variant key for existing menus; it is now the BG tab.
ns.CONTEXT_LABELS = { DEFAULT = "Say", GROUP = "Group", RAID = "Battleground" }
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

function ns.IsBattleground()
	local _, kind = IsInInstance()
	return kind == "pvp"
end

function ns.GetContext()
	if ns.IsBattleground() then return "RAID" end
	return IsInGroup() and "GROUP" or "DEFAULT"
end

local AB_LOCATIONS = { Blacksmith = "BS", ["Lumber Mill"] = "LM", ["Gold Mine"] = "GM", Farm = "Farm", Stables = "ST" }
function ns.FormatMessage(text, context)
	local location = "here"
	if context == "RAID" and ns.IsBattleground() then
		local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
		-- ponytail: English AB subzones only; add localized names or map
		-- coordinates when supporting other locales or objective boundaries.
		if instanceID == 529 then location = AB_LOCATIONS[GetSubZoneText()] or "here" end
	end
	return (text:gsub("{location}", location))
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
	local result = { label = node.label, text = node.text, chat = node.chat, emote = node.emote }
	if node.text == nil then
		for _, key in ipairs(CHOICES) do result[key] = ns.ResolveNode(node[key], context) end
	end
	return result
end

function ns.ChannelAvailable(context)
	return ns.GetChannel(context) ~= nil
end

-- Group follows the player's current party/raid. Instance chat takes priority
-- over a separate home group, matching the game's chat channel rules.
function ns.GetChannel(chat)
	if not chat or chat == "SAY" or chat == "DEFAULT" then return "SAY" end
	local instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	if chat == "GROUP" then
		if instance then return "INSTANCE_CHAT" end
		if IsInRaid() then return "RAID" end
		if IsInGroup() then return "PARTY" end
	elseif chat == "RAID" then
		if ns.IsBattleground() and instance then return "INSTANCE_CHAT" end
	end
end

-- Keep legacy destination fields for saved-menu compatibility. Sending now
-- follows the selected tab, including messages inherited from another tab.
function ns.MigrateMenu(node)
	if type(node) ~= "table" then return end
	if node.text ~= nil then
		local chat = node.chat and node.chat:upper() or "SAY"
		if chat == "PARTY" then chat = "GROUP"
		elseif chat == "INSTANCE_CHAT" or chat == "BATTLEGROUND" then chat = "RAID" end
		node.chat = (chat == "SAY" or chat == "GROUP" or chat == "RAID") and chat or "SAY"
	end
	for _, key in ipairs(CHOICES) do ns.MigrateMenu(node[key]) end
	for _, variant in pairs(node.variants or {}) do ns.MigrateMenu(variant) end
end

-- Add new tab defaults only to unchanged stock branches. Explicit overrides
-- (including disabled slots) and edited Say branches stay intact.
function ns.UpgradeDefaults(menu)
	local function Matches(node, default)
		if not node or not default then return node == default end
		if node.empty or node.label ~= default.label or node.text ~= default.text or node.emote ~= default.emote then return false end
		for _, key in ipairs(CHOICES) do if not Matches(node[key], default[key]) then return false end end
		return true
	end
	for _, key in ipairs(CHOICES) do
		local node, default = menu[key], ns.DefaultMenu[key]
		if Matches(node, default) and default.variants then
			node.variants = node.variants or {}
			for context, variant in pairs(default.variants) do
				if node.variants[context] == nil then node.variants[context] = DeepCopy(variant) end
			end
		end
	end
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
for key, binding in pairs(KEYS) do open:SetAttribute("key-" .. key, binding) end

-- LeftButton = the macro (toggle); A/X/Y/B/LB/RB = override-bound pad buttons,
-- which click this same button with the letter as the mouse button.
-- The restricted environment rejects the word "function" anywhere in a
-- snippet, comments included, so the close steps are repeated inline.
open:SetAttribute("_onclick", [[
	if button == "LeftButton" then
		if self:GetAttribute("open") then
			self:ClearBindings()
			self:SetAttribute("open", nil)
			self:SetAttribute("path", "")
		else
			self:SetAttribute("open", 1)
			self:SetAttribute("menucontext", self:GetAttribute("state-context") or "DEFAULT")
			self:SetAttribute("path", "")
			for prefix in ("NONE SHIFT- CTRL- ALT- CTRL-SHIFT- ALT-SHIFT- ALT-CTRL- ALT-CTRL-SHIFT-"):gmatch("%S+") do
				if prefix == "NONE" then prefix = "" end
				for key in ("A X Y B LB RB"):gmatch("%S+") do
					self:SetBindingClick(true, prefix .. self:GetAttribute("key-" .. key), "VGSChatOpen", key)
				end
			end
		end
		return
	end

	if not self:GetAttribute("open") then return end
	if button == "LB" or button == "RB" then
		local context = self:GetAttribute("menucontext") or "DEFAULT"
		if button == "RB" then
			context = context == "DEFAULT" and "GROUP" or context == "GROUP" and "RAID" or "DEFAULT"
		else
			context = context == "DEFAULT" and "RAID" or context == "RAID" and "GROUP" or "DEFAULT"
		end
		self:SetAttribute("menucontext", context)
		self:SetAttribute("path", "")
		return
	end
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
]])

-- Native state drivers can switch between already-published menu shapes in
-- combat. The context stays fixed during an open menu so button paths don't
-- change meaning halfway through a selection.
local contextDriver
local function UpdateContextDriver()
	if InCombatLockdown() then return end
	-- ponytail: zone changes during combat refresh at combat end; group changes
	-- use the native state driver immediately, without protected writes.
	local driver = ns.IsBattleground() and "RAID" or "[group] GROUP; DEFAULT"
	if driver ~= contextDriver then RegisterStateDriver(open, "context", driver); contextDriver = driver end
end
UpdateContextDriver()

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
				open:SetAttribute("node-" .. attributePath, child.text and "leaf" or "branch")
				publishedPaths[attributePath] = true
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

local function SendNode(node, context)
	if not (node and node.text and node.text ~= "") then return end
	local chatType = ns.GetChannel(context)
	if not chatType then
		Print("Join a " .. (context == "RAID" and "battleground" or "group") .. " to send this message.")
		return
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok, err = pcall(send, ns.FormatMessage(node.text, context), chatType)
	if not ok then Print("|cffff5050Couldn't send:|r " .. tostring(err)); return end
	if node.emote then
		local emoteOK, emoteError = pcall(DoEmote, node.emote)
		if not emoteOK then Print("|cffff5050Couldn't play emote:|r " .. tostring(emoteError)) end
	end
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
	sequence:SetWidth(232); sequence:SetWordWrap(false); sequence:SetJustifyH("LEFT")
	sequence:SetTextColor(0.7, 0.68, 0.63)
	local tabs = {}
	for i, context in ipairs(ns.CONTEXTS) do
		local tab = CreateFrame("Frame", nil, menu)
		tab:SetSize(({ 52, 64, 104 })[i], 24)
		tab:SetPoint("TOPLEFT", 14 + ({ 0, 58, 128 })[i], -34)
		tab.bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.bg:SetAllPoints()
		tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tab.label:SetPoint("CENTER"); tab.label:SetText(ns.CONTEXT_LABELS[context])
		tabs[context] = tab
	end

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

	local list = CreateFrame("ScrollFrame", nil, menu)
	local content = CreateFrame("Frame", nil, list)
	content:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
	content:SetSize(232, 26)
	list:SetScrollChild(content)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, delta)
		self.offset = math.max(0, math.min(self.maximum, self.offset - delta * 30))
		self:SetVerticalScroll(self.offset)
	end)
	local leaves = {}

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
	local scrollHint = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scrollHint:SetPoint("RIGHT", 0, -4)
	scrollHint:SetText("Scroll for more")
	scrollHint:SetTextColor(0.7, 0.68, 0.63)
	local tabHint = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tabHint:SetPoint("TOPRIGHT", -14, -12); tabHint:SetText("LB / RB")
	tabHint:SetTextColor(0.7, 0.68, 0.63)

	function menu:Display(node, heading, path, context)
		path = path or ""
		context = context or "DEFAULT"
		title:SetText("Quick Chat")
		for tabContext, tab in pairs(tabs) do
			local active = context == tabContext
			tab.bg:SetColorTexture(active and 0.22 or 0.12, active and 0.2 or 0.12, active and 0.15 or 0.13, 1)
			local available = ns.ChannelAvailable(tabContext)
			tab.label:SetTextColor(active and 1 or (available and 0.8 or 0.5), active and 0.82 or (available and 0.8 or 0.5), active and 0.4 or (available and 0.8 or 0.5))
		end
		sequence:SetPoint("TOPLEFT", 14, -62)
		sequence:SetShown(path ~= "")
		sequence:SetText(path .. "  -  " .. heading)
		local y = 64 + (path ~= "" and 18 or 0)
		headerLine:SetPoint("TOPLEFT", 14, -y)
		y = y + 5
		local compact = ns.DB and ns.DB.compact == true
		list:SetShown(not compact)
		scrollHint:Hide()
		for _, row in pairs(rows) do row:SetShown(compact) end
		if compact then
			for _, key in ipairs(CHOICES) do
				local child = node[key]
				local row = rows[key]
				row.label:SetText(child and ns.FormatMessage((child.label ~= "" and child.label) or child.text or "?", context) or "—")
				local available = child and ns.ChannelAvailable(context)
				row.label:SetTextColor(available and 0.94 or 0.5, available and 0.92 or 0.5, available and 0.89 or 0.5)
				row.badge:SetAlpha(available and 1 or 0.35)
				row.arrow:SetShown(child ~= nil and not child.text)
				local height = math.max(30, row.label:GetStringHeight() + 12)
				row:SetHeight(height)
				row:SetPoint("TOPLEFT", 14, -y)
				y = y + height
			end
		else
			local count, height = 0, 0
			local function Walk(branch, prefix)
				for _, key in ipairs(CHOICES) do
					local child = branch[key]
					if child then
						local childPath = prefix .. key
						if child.text ~= nil then
							count = count + 1
							local label = leaves[count]
							if not label then
								label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
								label:SetWidth(232); label:SetJustifyH("LEFT"); label:SetWordWrap(true)
								leaves[count] = label
							end
							local available = ns.ChannelAvailable(context)
							local buttons = available and childPath:gsub(".", function(k) return "|c" .. KEY_COLOR[k] .. k .. "|r" end) or childPath
							label:SetText(buttons .. " - " .. ns.FormatMessage((child.label ~= "" and child.label) or child.text, context))
							label:SetTextColor(available and 0.94 or 0.5, available and 0.92 or 0.5, available and 0.89 or 0.5)
							label:SetPoint("TOPLEFT", 0, -height - 4); label:Show()
							height = height + math.max(26, label:GetStringHeight() + 8)
						else Walk(child, childPath) end
					end
				end
			end
			Walk(node, path)
			for i = count + 1, #leaves do leaves[i]:Hide() end
			local visibleHeight = math.min(math.max(26, height), math.max(80, UIParent:GetHeight() - y - 100))
			content:SetHeight(math.max(26, height))
			list:SetSize(232, visibleHeight); list:SetPoint("TOPLEFT", 14, -y)
			list.offset, list.maximum = 0, math.max(0, height - visibleHeight)
			list:SetVerticalScroll(0)
			scrollHint:SetShown(list.maximum > 0)
			y = y + visibleHeight
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
menu:SetClampedToScreen(true)

local function UpdateMenu()
	if not open:GetAttribute("open") then menu:Hide(); return end
	local path = open:GetAttribute("path") or ""
	local context = open:GetAttribute("menucontext") or "DEFAULT"
	local node = NodeAt(path, context) or activeMenus[context]
	menu:Display(node, path == "" and "Quick Chat" or (node.label ~= "" and node.label or nil) or "Group", path, context)
end
ns.UpdateMenu = UpdateMenu

-- Runs after the secure snippet, inside the same button press.
open:HookScript("OnClick", function(self)
	local seq = self:GetAttribute("sentseq") or 0
	if seq ~= lastSeq then
		lastSeq = seq
		local context = self:GetAttribute("sentcontext")
		SendNode(NodeAt(self:GetAttribute("sentpath") or "", context), context)
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
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		-- Whether the client handed back saved settings; the editor shows it so
		-- a return of the beta's "SavedVariables never load" bug is visible.
		ns.savedLoaded = type(VGSChatDB) == "table" and type(VGSChatDB.menu) == "table"
		if type(VGSChatDB) ~= "table" then VGSChatDB = {} end
		ns.DB = VGSChatDB
		if type(ns.DB.compact) ~= "boolean" then ns.DB.compact = false end
		if type(ns.DB.menu) ~= "table" then ns.DB.menu = DeepCopy(ns.DefaultMenu) end
		if (tonumber(ns.DB.version) or 0) < 3 then ns.UpgradeDefaults(ns.DB.menu) end
		ns.MigrateMenu(ns.DB.menu)
		ns.DB.version = 3
	end
	UpdateContextDriver()
	PublishMenu()
	UpdateMenu()
	if event == "UPDATE_MACROS" then macrosLoaded = true end
	if macrosLoaded and not macroReady then macroReady = EnsureMacro() end
end)
