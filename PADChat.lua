-- PAD Chat: Tribes 2 Voice Game System style quick chat for WoW Forever gamepads.
--
-- The player presses the "PADChat" macro (placed anywhere on their bars). Its
-- /click hits a SecureHandler button whose snippet takes over A/X/Y/B/LB/RB with
-- priority override bindings, walks the menu one press at a time, and releases
-- the buttons again when a message is chosen or B cancels. Binding changes have
-- to happen in a secure snippet to work in combat.
--
-- The snippet can't send chat, so it bumps a "sentseq" attribute; the OnClick
-- hook below runs right after it, inside the same button press (a hardware
-- event, which /say needs outdoors), and sends the message.
--
-- Never touches the chat edit box or registers slash commands, which taint
-- Forever's gamepad UI.

local ADDON, ns = ...

local MACRO_NAME = "PADChat"
-- Macros need a numeric icon file ID; a texture path is accepted but leaves
-- the macro iconless, and the client then won't let it be placed on a bar.
local MACRO_ICON = 132333 -- Ability_Warrior_BattleShout
local MACRO_FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark
local MACRO_BODY = "/click PADChatOpen LeftButton 1"

-- Xbox naming; the PAD codes are the same on every controller.
local KEYS = { A = "PAD1", B = "PAD2", X = "PAD3", Y = "PAD4", LB = "PADLSHOULDER", RB = "PADRSHOULDER",
	UP = "PADDUP", DOWN = "PADDDOWN" }
local CHOICES = { "A", "X", "Y" }
local KEY_COLOR = { A = "ff60d060", X = "ff4aa3ff", Y = "ffffd100", B = "ffff5050" }
local PRESSED_KEY_COLOR = "ff9d9d9d"

-- Paints a button path. The first `pressedCount` keys are the ones already
-- pressed, so they grey out and the remaining presses keep their colour.
local function FormatPath(path, pressedCount)
	local colored = {}
	for i = 1, #path do
		local key = path:sub(i, i)
		colored[i] = "|c" .. (i <= pressedCount and PRESSED_KEY_COLOR or KEY_COLOR[key]) .. key .. "|r"
	end
	return table.concat(colored)
end

local function Print(text) print("|cff33ff99PAD Chat|r: " .. text) end

ns.CHOICES, ns.KEY_COLOR, ns.Print = CHOICES, KEY_COLOR, Print
-- Battlegrounds aren't in the WoW: Forever beta, so the Battleground tab and
-- zone detection stay off until launch. Flip to true to re-enable them all.
ns.BATTLEGROUNDS_ENABLED = ns.BATTLEGROUNDS_ENABLED or false
-- Tabs, left to right. Whisper and Group both inherit Say's options; Say stays
-- the tab the menu opens on. LFG whispers like Whisper (and inherits it), but
-- only shows when Y on a Looking For Group listing opened the menu.
ns.CONTEXTS = { "LFG", "WHISPER", "DEFAULT", "GROUP", ns.BATTLEGROUNDS_ENABLED and "RAID" or nil }
-- Retain the saved RAID variant key for existing menus; it is now the BG tab.
ns.CONTEXT_LABELS = { LFG = "LFG", WHISPER = "Whisper", DEFAULT = "Say", GROUP = "Group", RAID = "Battleground" }
ns.MAX_WHISPERS = 10
ns.MAX_DEPTH = 4 -- presses per message, counting the last one

-- A node is a message (a leaf the player can pick) when it sends chat text, an
-- emote, or both. A node with neither opens one more level of options.
function ns.IsMessage(node)
	return type(node) == "table" and (node.text ~= nil or node.emote ~= nil)
end

-- Display name: the menu label, falling back to the text or the emote token.
function ns.NodeLabel(node)
	if not node then return "Empty slot" end
	if node.label and node.label ~= "" then return node.label end
	return node.text or node.emote or "Group"
end

local function HasText(node) return node.text ~= nil and node.text ~= "" end

------------------------------------------------------------------------
-- Saved menu. PADChatDB.menu is the player's copy, seeded from
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
	return ns.BATTLEGROUNDS_ENABLED and kind == "pvp"
end

function ns.GetContext()
	if ns.IsBattleground() then return "RAID" end
	return IsInGroup() and "GROUP" or "DEFAULT"
end

function ns.GetBattlegroundNode(node, context, instanceID)
	if not (node and node.battlegrounds and context == "RAID") then return node end
	if instanceID == nil then
		if not ns.IsBattleground() then return node end
		local _, _, _, _, _, _, _, currentID = GetInstanceInfo()
		instanceID = currentID
	end
	return node.battlegrounds[instanceID] or node
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
	return (text:gsub("{location}", location):gsub("{LEVEL}", UnitLevel("player")):gsub("{CLASS}", (UnitClass("player"))))
end

-- A variant replaces one option (including its children). Missing variants
-- inherit; false explicitly clears the slot. Empty anchors hold variants for
-- a slot that has no default option.
function ns.PickNode(node, context)
	if not node then return nil end
	local variants, condition = node.variants, nil
	if variants then
		if context == "LFG" and variants.LFG ~= nil then condition = "LFG"
		elseif context == "WHISPER" or context == "LFG" then
			if variants.WHISPER ~= nil then condition = "WHISPER" end
		elseif context == "RAID" and variants.RAID ~= nil then condition = "RAID"
		elseif context ~= "DEFAULT" and variants.GROUP ~= nil then condition = "GROUP" end
	end
	if condition then node = variants[condition] end
	return node and not node.empty and node or nil, condition
end

function ns.ResolveNode(node, context, instanceID)
	node = ns.PickNode(node, context)
	node = ns.GetBattlegroundNode(node, context, instanceID)
	if not node then return nil end
	local result = { label = node.label, text = node.text, chat = node.chat, emote = node.emote }
	if not ns.IsMessage(node) then
		for _, key in ipairs(CHOICES) do result[key] = ns.ResolveNode(node[key], context, instanceID) end
	end
	return result
end

function ns.ChannelAvailable(context)
	return ns.GetChannel(context) ~= nil
end

-- Emote-only messages work anywhere; a message that sends text needs its channel.
function ns.IsAvailable(node, context)
	if not ns.IsMessage(node) then return false end
	return node.emote ~= nil or HasText(node) and ns.ChannelAvailable(context)
end

-- Group follows the player's current party/raid. Instance chat takes priority
-- over a separate home group, matching the game's chat channel rules.
function ns.GetChannel(chat)
	if not chat or chat == "SAY" or chat == "DEFAULT" then return "SAY" end
	if chat == "WHISPER" or chat == "LFG" then return ns.GetWhisperTarget() and "WHISPER" or nil end
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
	for _, battleground in pairs(node.battlegrounds or {}) do ns.MigrateMenu(battleground) end
end

-- Add new tab defaults only to unchanged stock branches. Explicit overrides
-- (including disabled slots) and edited Say branches stay intact.
function ns.UpgradeDefaults(menu, includeMissing)
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
				local saved = node.variants[context]
				if saved == nil and includeMissing ~= false then node.variants[context] = DeepCopy(variant)
				elseif Matches(saved, variant) and variant.battlegrounds then
					saved.battlegrounds = saved.battlegrounds or {}
					for instanceID, battleground in pairs(variant.battlegrounds) do
						if saved.battlegrounds[instanceID] == nil then saved.battlegrounds[instanceID] = DeepCopy(battleground) end
					end
				end
			end
		end
	end
end

-- The first release sent Wave as "/e waves.", which MigrateMenu later turned
-- into said text. Unedited Greet options take the shipped ones, so Wave plays
-- the emote and Goodbye waves too.
local OLD_GREETINGS = { A = { "Hello", "Well met!" }, X = { "Goodbye", "Farewell!" }, Y = { "Wave", "waves." } }
function ns.UpgradeGreetings(menu)
	local greet = menu.X and menu.X.A
	if type(greet) ~= "table" then return end
	for key, old in pairs(OLD_GREETINGS) do
		local node = greet[key]
		if type(node) == "table" and node.label == old[1] and node.text == old[2] and node.emote == nil and not node.variants then
			greet[key] = DeepCopy(ns.DefaultMenu.X.A[key])
		end
	end
end

-- A whisper can't deliver an emote. Unedited Goodbye and Wave options pick up
-- the shipped text-only Whisper versions.
local WHISPER_UPGRADES = { X = { "Goodbye", "Farewell" }, Y = { "Wave", nil } }
function ns.UpgradeWhisper(menu)
	local greet = menu.X and menu.X.A
	if type(greet) ~= "table" then return end
	for key, old in pairs(WHISPER_UPGRADES) do
		local node = greet[key]
		if type(node) == "table" and node.label == old[1] and node.text == old[2] and node.emote == "WAVE" and not node.variants then
			node.variants = DeepCopy(ns.DefaultMenu.X.A[key].variants)
		end
	end
end

-- The LFG tab is new, so every saved menu takes its shipped options.
function ns.UpgradeLFG(menu)
	for _, key in ipairs(CHOICES) do
		menu[key] = menu[key] or { empty = true }
		local node = menu[key]
		node.variants = node.variants or {}
		if node.variants.LFG == nil then node.variants.LFG = DeepCopy(ns.DefaultMenu[key].variants.LFG) end
	end
end

local activeMenus = {}
for _, context in ipairs(ns.CONTEXTS) do activeMenus[context] = ns.ResolveNode(ns.DefaultMenu, context, 0) end
activeMenus.WSG = ns.ResolveNode(ns.DefaultMenu, "RAID", 489)

------------------------------------------------------------------------
-- Menu lookup
------------------------------------------------------------------------
local function NodeAt(path, context, profile)
	context = context or "DEFAULT"
	local node = activeMenus[context == "RAID" and profile == "WSG" and "WSG" or context]
	for i = 1, #path do
		node = node and node[path:sub(i, i)]
	end
	return node
end

------------------------------------------------------------------------
-- Secure open button (the state machine)
------------------------------------------------------------------------
local open = CreateFrame("Button", "PADChatOpen", UIParent, "SecureHandlerClickTemplate")
open:RegisterForClicks("AnyDown")
for key, binding in pairs(KEYS) do open:SetAttribute("key-" .. key, binding) end
open:SetAttribute("battlegrounds", ns.BATTLEGROUNDS_ENABLED)

-- LeftButton = the macro (toggle); A/X/Y/B/LB/RB/UP/DOWN = override-bound pad
-- buttons, which click this same button with the letter as the mouse button.
-- WHISPER / LFG = Y in an integrated Blizzard window (Integrations.lua), which
-- opens straight onto the Whisper or LFG tab with that window's player picked.
-- The LFG tab only joins the LB/RB cycle of a menu it opened.
-- The restricted environment rejects the word "function" anywhere in a
-- snippet, comments included, so the close steps are repeated inline.
open:SetAttribute("_onclick", [[
	if button == "LeftButton" or button == "WHISPER" or button == "LFG" then
		if self:GetAttribute("open") then
			if button ~= "LeftButton" then return end
			self:ClearBindings()
			self:SetAttribute("open", nil)
			self:SetAttribute("path", "")
		else
			self:SetAttribute("open", 1)
			local context = button ~= "LeftButton" and button or self:GetAttribute("state-context") or "DEFAULT"
			self:SetAttribute("menucontext", context == "WSG" and "RAID" or context)
			self:SetAttribute("menuprofile", context == "WSG" and "WSG" or "DEFAULT")
			self:SetAttribute("lfgopen", button == "LFG" and 1 or nil)
			self:SetAttribute("path", "")
			self:SetAttribute("whisperindex", 0)
			for modifier in ("NONE SHIFT- CTRL- ALT- CTRL-SHIFT- ALT-SHIFT- ALT-CTRL- ALT-CTRL-SHIFT-"):gmatch("%S+") do
				local prefix = modifier == "NONE" and "" or modifier
				for key in (button ~= "LeftButton" and "A X Y B LB RB UP DOWN" or "A X Y B LB RB"):gmatch("%S+") do
					self:SetBindingClick(true, prefix .. self:GetAttribute("key-" .. key), "PADChatOpen", key)
				end
			end
		end
		return
	end

	if not self:GetAttribute("open") then return end
	if button == "LB" or button == "RB" then
		local context = self:GetAttribute("menucontext") or "DEFAULT"
		local first = self:GetAttribute("lfgopen") and "LFG" or "WHISPER"
		if button == "RB" then
			context = context == "LFG" and "WHISPER" or context == "WHISPER" and "DEFAULT" or context == "DEFAULT" and "GROUP" or context == "GROUP" and "RAID" or first
		else
			if context == "WHISPER" and first == "LFG" then context = "LFG"
			elseif context == "WHISPER" or context == "LFG" then context = "RAID"
			else context = context == "RAID" and "GROUP" or context == "GROUP" and "DEFAULT" or "WHISPER" end
		end
		if context == "RAID" and not self:GetAttribute("battlegrounds") then
			context = button == "RB" and first or "GROUP"
		end
		self:SetAttribute("menucontext", context)
		self:SetAttribute("path", "")
		-- The D-pad only belongs to PAD Chat while a whisper tab is showing.
		for modifier in ("NONE SHIFT- CTRL- ALT- CTRL-SHIFT- ALT-SHIFT- ALT-CTRL- ALT-CTRL-SHIFT-"):gmatch("%S+") do
			local prefix = modifier == "NONE" and "" or modifier
			for key in ("UP DOWN"):gmatch("%S+") do
				if context == "WHISPER" or context == "LFG" then
					self:SetBindingClick(true, prefix .. self:GetAttribute("key-" .. key), "PADChatOpen", key)
				else
					self:ClearBinding(prefix .. self:GetAttribute("key-" .. key))
				end
			end
		end
		return
	end
	-- An unbounded step; the list itself can change in combat, so the
	-- insecure side wraps it onto however many names there are.
	if button == "UP" or button == "DOWN" then
		local context = self:GetAttribute("menucontext")
		if context == "WHISPER" or context == "LFG" then
			self:SetAttribute("whisperindex", (self:GetAttribute("whisperindex") or 0) + (button == "UP" and -1 or 1))
		end
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
	local shape = context == "RAID" and self:GetAttribute("menuprofile") == "WSG" and "WSG" or context
	local kind = self:GetAttribute("node-" .. shape .. "-" .. path)
	if kind == "leaf" then
		self:SetAttribute("sentpath", path)
		self:SetAttribute("sentcontext", context)
		self:SetAttribute("sentprofile", self:GetAttribute("menuprofile"))
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
	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local driver = ns.IsBattleground() and (instanceID == 489 and "WSG" or "RAID") or "[group] GROUP; DEFAULT"
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
				local leaf = ns.IsMessage(child)
				open:SetAttribute("node-" .. attributePath, leaf and "leaf" or "branch")
				publishedPaths[attributePath] = true
				if not leaf then Walk(child, childPath, context) end
			end
		end
	end
	for _, context in ipairs(ns.CONTEXTS) do
		snapshots[context] = ns.ResolveNode(ns.GetMenu(), context, 0)
		Walk(snapshots[context], "", context)
	end
	snapshots.WSG = ns.ResolveNode(ns.GetMenu(), "RAID", 489)
	Walk(snapshots.WSG, "", "WSG")
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
-- Recent whispers
------------------------------------------------------------------------
-- The Whisper tab lists the players the addon has seen tells to or from, most
-- recent first, then online group members, at most MAX_WHISPERS in all.
-- An open menu works from a snapshot so a list change mid-pick can't slide the
-- selection onto someone else.
local whisperSnapshot, pendingWhisper

-- Same-realm names drop their realm, so every source spells a player alike.
local function ShortName(name)
	return Ambiguate and Ambiguate(name, "none") or name
end

-- Moves `name` to the front of `list`, keeping it at most MAX_WHISPERS long.
local function PutFirst(list, name)
	if type(name) ~= "string" or name == "" then return list end
	name = ShortName(name)
	for i = #list, 1, -1 do
		if list[i]:lower() == name:lower() then table.remove(list, i) end
	end
	table.insert(list, 1, name)
	for i = #list, ns.MAX_WHISPERS + 1, -1 do list[i] = nil end
	return list
end

-- Tells either way, saved so they outlast a /reload.
local tells = CreateFrame("Frame")
tells:RegisterEvent("CHAT_MSG_WHISPER")
tells:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
tells:SetScript("OnEvent", function(_, _, _, name) PutFirst(ns.DB.recentTells, name) end)

-- ponytail: a raid lists its first members only; scroll the list if that matters.
local function GroupNames()
	local names, prefix = {}, IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		local unit = prefix .. i
		if #names < ns.MAX_WHISPERS and UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit) then
			names[#names + 1] = ShortName(GetUnitName(unit, true))
		end
	end
	return names
end

local function LiveWhispers()
	local list = GroupNames()
	for i = #ns.DB.recentTells, 1, -1 do PutFirst(list, ns.DB.recentTells[i]) end
	return list
end

function ns.GetWhispers()
	return whisperSnapshot or LiveWhispers()
end

-- A player picked in another window (Integrations.lua) heads the next menu's
-- list, whether or not they're on it yet.
function ns.SetPendingWhisper(name) pendingWhisper = name end

local function TakeSnapshot()
	local list = {}
	for i, name in ipairs(LiveWhispers()) do list[i] = name end
	PutFirst(list, pendingWhisper)
	pendingWhisper = nil
	return list
end

function ns.GetWhisperIndex()
	local count = #ns.GetWhispers()
	if count == 0 then return nil end
	return (open:GetAttribute("whisperindex") or 0) % count + 1
end

function ns.GetWhisperTarget()
	local index = ns.GetWhisperIndex()
	return index and ns.GetWhispers()[index]
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
local lastSeq = 0

local function SendNode(node, context)
	if not (node and ns.IsMessage(node)) then return end
	if HasText(node) then
		local chatType = ns.GetChannel(context)
		if not chatType then
			Print((context == "WHISPER" or context == "LFG") and "No one to whisper." or "Join a " .. (context == "RAID" and "battleground" or "group") .. " to send this message.")
			return
		end
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		local ok, err = pcall(send, ns.FormatMessage(node.text, context), chatType, nil, chatType == "WHISPER" and ns.GetWhisperTarget() or nil)
		if not ok then Print("|cffff5050Couldn't send:|r " .. tostring(err)); return end
	end
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
	for _, context in ipairs(ns.CONTEXTS) do
		local tab = CreateFrame("Frame", nil, menu)
		tab:SetSize(({ LFG = 36, WHISPER = 56, DEFAULT = 40, GROUP = 48, RAID = 82 })[context], 24)
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

	-- `lfg` shows the LFG tab even while another tab is picked.
	function menu:Display(node, heading, path, context, lfg)
		path = path or ""
		context = context or "DEFAULT"
		title:SetText("Quick Chat")
		-- ponytail: all five tabs overflow the HUD by ~20px once battlegrounds launch; narrow the tabs then.
		local tabX = 14
		for _, tabContext in ipairs(ns.CONTEXTS) do
			local tab = tabs[tabContext]
			tab:SetShown(tabContext ~= "LFG" or lfg or context == "LFG")
			if tab:IsShown() then tab:SetPoint("TOPLEFT", tabX, -34); tabX = tabX + tab:GetWidth() + 2 end
		end
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
				row.label:SetText(child and ns.FormatMessage(ns.NodeLabel(child), context) or "—")
				local available = ns.IsAvailable(child, context)
				row.label:SetTextColor(available and 0.94 or 0.5, available and 0.92 or 0.5, available and 0.89 or 0.5)
				row.badge:SetAlpha(available and 1 or 0.35)
				row.arrow:SetShown(child ~= nil and not ns.IsMessage(child))
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
						if ns.IsMessage(child) then
							count = count + 1
							local label = leaves[count]
							if not label then
								label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
								label:SetWidth(232); label:SetJustifyH("LEFT"); label:SetWordWrap(true)
								leaves[count] = label
							end
							local available = ns.IsAvailable(child, context)
							local buttons = available and FormatPath(childPath, #path) or childPath
							label:SetText(buttons .. " - " .. ns.FormatMessage(ns.NodeLabel(child), context))
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

local menu = ns.CreateMenuView(UIParent, "PADChatMenu")
menu:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
menu:SetFrameStrata("HIGH")
menu:SetClampedToScreen(true)

-- Recent whispers, docked to the right of the HUD while the Whisper tab shows.
local whisperList = CreateFrame("Frame", "PADChatWhispers", menu)
whisperList:SetPoint("TOPLEFT", menu, "TOPRIGHT", 6, 0)
whisperList:SetWidth(170)
do
	local edge = whisperList:CreateTexture(nil, "BACKGROUND", nil, 0)
	edge:SetAllPoints()
	edge:SetColorTexture(0.29, 0.27, 0.22, 0.9)
	local bg = whisperList:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.09, 0.09, 0.1, 0.96)
	local title = whisperList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Whisper to")
	local hint = whisperList:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPRIGHT", -14, -12)
	hint:SetText("Up / Down")
	hint:SetTextColor(0.7, 0.68, 0.63)
	local line = whisperList:CreateTexture(nil, "ARTWORK")
	line:SetSize(142, 1)
	line:SetPoint("TOPLEFT", 14, -34)
	line:SetColorTexture(0.29, 0.27, 0.22, 0.7)
end
local whisperHighlight = whisperList:CreateTexture(nil, "ARTWORK")
whisperHighlight:SetColorTexture(0.22, 0.2, 0.15, 1)
local whisperRows = {}

function whisperList:Display(names, selected)
	local y = 40
	for i = 1, math.max(1, #names) do
		local row = whisperRows[i]
		if not row then
			row = whisperList:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row:SetWidth(134); row:SetJustifyH("LEFT"); row:SetWordWrap(false)
			whisperRows[i] = row
		end
		row:SetPoint("TOPLEFT", 18, -y - 5)
		row:Show()
		if #names == 0 then
			row:SetText("No one to whisper")
			row:SetTextColor(0.5, 0.5, 0.5)
		else
			row:SetText(Ambiguate and Ambiguate(names[i], "short") or names[i])
			if i == selected then
				row:SetTextColor(1, 0.82, 0.4)
				whisperHighlight:SetPoint("TOPLEFT", 14, -y)
				whisperHighlight:SetSize(142, 22)
			else
				row:SetTextColor(0.94, 0.92, 0.89)
			end
		end
		y = y + 22
	end
	for i = math.max(1, #names) + 1, #whisperRows do whisperRows[i]:Hide() end
	whisperHighlight:SetShown(selected ~= nil)
	self:SetHeight(y + 12)
end

local function UpdateMenu()
	if not open:GetAttribute("open") then menu:Hide(); return end
	local path = open:GetAttribute("path") or ""
	local context = open:GetAttribute("menucontext") or "DEFAULT"
	local node = NodeAt(path, context, open:GetAttribute("menuprofile"))
		or NodeAt("", context, open:GetAttribute("menuprofile"))
	menu:Display(node, path == "" and "Quick Chat" or (node.label ~= "" and node.label or nil) or "Group", path, context, open:GetAttribute("lfgopen"))
	local whispering = context == "WHISPER" or context == "LFG"
	whisperList:SetShown(whispering)
	if whispering then whisperList:Display(ns.GetWhispers(), ns.GetWhisperIndex()) end
end
ns.UpdateMenu = UpdateMenu

-- Runs after the secure snippet, inside the same button press.
open:HookScript("OnClick", function(self)
	local seq = self:GetAttribute("sentseq") or 0
	if seq ~= lastSeq then
		lastSeq = seq
		local context = self:GetAttribute("sentcontext")
		SendNode(NodeAt(self:GetAttribute("sentpath") or "", context, self:GetAttribute("sentprofile")), context)
	end
	if self:GetAttribute("open") then
		whisperSnapshot = whisperSnapshot or TakeSnapshot()
	else
		whisperSnapshot = nil
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
		hint = "|cffffd100PADChat|r (opens the quick chat menu)" },
	{ name = "PADEdit", body = "/click PADChatEditorToggle", icon = MACRO_FALLBACK_ICON,
		hint = "|cffffd100PADEdit|r (opens the menu editor)" },
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

-- Pre-rename macros whose /click targets no longer exist.
local OLD_MACROS = { "VGSChat", "VGSEdit" }

local function EnsureMacro()
	if InCombatLockdown() then return false end
	for _, name in ipairs(OLD_MACROS) do
		local index = GetMacroIndexByName(name)
		if index and index > 0 then DeleteMacro(index); Print("Removed the old " .. name .. " macro.") end
	end
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
		ns.savedLoaded = type(PADChatDB) == "table" and type(PADChatDB.menu) == "table"
		if type(PADChatDB) ~= "table" then PADChatDB = {} end
		ns.DB = PADChatDB
		if type(ns.DB.compact) ~= "boolean" then ns.DB.compact = false end
		if type(ns.DB.enhanceLFG) ~= "boolean" then ns.DB.enhanceLFG = true end
		ns.DB.enhanceRecentAllies = nil -- setting from before the integration was removed
		if type(ns.DB.recentTells) ~= "table" then ns.DB.recentTells = {} end
		if type(ns.DB.menu) ~= "table" then ns.DB.menu = DeepCopy(ns.DefaultMenu) end
		local version = tonumber(ns.DB.version) or 0
		if version < 4 then ns.UpgradeDefaults(ns.DB.menu, version < 3) end
		if version < 5 then ns.UpgradeGreetings(ns.DB.menu) end
		if version < 7 then ns.UpgradeWhisper(ns.DB.menu) end
		if version < 8 then ns.UpgradeLFG(ns.DB.menu) end
		ns.MigrateMenu(ns.DB.menu)
		ns.DB.version = 8
	end
	UpdateContextDriver()
	PublishMenu()
	UpdateMenu()
	if event == "UPDATE_MACROS" then macrosLoaded = true end
	if macrosLoaded and not macroReady then macroReady = EnsureMacro() end
end)
