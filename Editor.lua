-- Menu editor: a standalone window, opened by the "VGSEdit" macro.
--
-- Left: the A / X / Y slots of the level being edited, drawn as controller
-- buttons. Tap a slot to edit it; tap the arrow on a category to go inside it.
-- Right: the selected slot, which is empty, a message, or a category. Every
-- change is saved at once and pushed to the secure menu (or queued until
-- combat ends).
--
-- No slash command: tested 2026-10-03, typing an addon slash command with the
-- gamepad UI on taints the chat box's gamepad focus stack, and the next
-- Open Chat locks the game ("insecure scripts exceeded execution limit").
-- The macro runs outside the chat box, so it's safe. No UISpecialFrames
-- either: Escape-to-close runs through Blizzard's secure window code.

local _, ns = ...

local WIDTH, HEIGHT = 720, 470
local FORM_X = 360

local editor = CreateFrame("Frame", "VGSChatEditor", UIParent)
editor:SetSize(WIDTH, HEIGHT)
editor:SetPoint("CENTER")
editor:SetFrameStrata("DIALOG")
editor:SetToplevel(true)
editor:SetMovable(true)
editor:SetClampedToScreen(true)
editor:EnableMouse(true)
editor:RegisterForDrag("LeftButton")
editor:SetScript("OnDragStart", editor.StartMoving)
editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
editor:Hide()

local bg = editor:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.06, 0.06, 0.09, 0.95)

local edge = editor:CreateTexture(nil, "BORDER")
edge:SetPoint("TOPLEFT", 0, 0)
edge:SetPoint("TOPRIGHT", 0, 0)
edge:SetHeight(36)
edge:SetColorTexture(0.12, 0.12, 0.18, 1)

-- The "VGSEdit" macro clicks this.
local toggle = CreateFrame("Button", "VGSChatEditorToggle", UIParent)
-- /click sends a single press (up unless told otherwise); accept either.
toggle:RegisterForClicks("AnyUp", "AnyDown")
toggle:SetScript("OnClick", function()
	editor:SetShown(not editor:IsShown())
end)

local path = ""      -- level being edited ("" = top, "X" = inside X, ...)
local selected = "A" -- slot selected on that level

------------------------------------------------------------------------
-- Model helpers
------------------------------------------------------------------------
local function LevelAt(p)
	local node = ns.GetMenu()
	for i = 1, #p do
		node = node and node[p:sub(i, i)]
	end
	return node
end

local function SelectedNode()
	local level = LevelAt(path)
	return level and level[selected]
end

local function KindOf(node)
	if not node then return "empty" end
	return node.text and "message" or "category"
end

local function NameOf(node)
	return (node.label and node.label ~= "") and node.label or node.text or "?"
end

local function ChatLabel(chat)
	chat = chat or "SAY"
	return chat:sub(1, 1) .. chat:sub(2):lower()
end

local function CountChildren(node)
	local n = 0
	for _, key in ipairs(ns.CHOICES) do
		if node[key] then n = n + 1 end
	end
	return n
end

local function Breadcrumb()
	local parts, node = { "Top" }, ns.GetMenu()
	for i = 1, #path do
		local key = path:sub(i, i)
		node = node[key]
		parts[#parts + 1] = "|c" .. ns.KEY_COLOR[key] .. key .. "|r " .. NameOf(node)
	end
	return table.concat(parts, "  >  ")
end

------------------------------------------------------------------------
-- Header
------------------------------------------------------------------------
local Refresh -- defined below

local title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -10)
title:SetText("VGS Chat: edit menu")

local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local crumb = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
crumb:SetPoint("TOPLEFT", 16, -52)
crumb:SetWidth(FORM_X - 130)
crumb:SetJustifyH("LEFT")
crumb:SetWordWrap(false)

local back = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
back:SetSize(90, 28)
back:SetPoint("TOPLEFT", FORM_X - 106, -46)
back:SetText("< Back")
back:SetScript("OnClick", function()
	selected = path:sub(-1)
	path = path:sub(1, -2)
	Refresh()
end)

------------------------------------------------------------------------
-- Slot cards (the A / X / Y spots)
------------------------------------------------------------------------
local CARD_W, CARD_H, CARD_GAP = FORM_X - 32, 64, 10

local function HexToRGB(hex) -- "ffRRGGBB"
	return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

local function MakeBadge(parent, key)
	local badge = parent:CreateTexture(nil, "ARTWORK")
	badge:SetSize(40, 40)
	badge:SetPoint("LEFT", 12, 0)
	badge:SetColorTexture(HexToRGB(ns.KEY_COLOR[key]))
	local mask = parent:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(badge)
	badge:AddMaskTexture(mask)
	local letter = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	letter:SetPoint("CENTER", badge, "CENTER", 0, 0)
	letter:SetTextColor(0.05, 0.05, 0.05)
	letter:SetText(key)
	return badge
end

local cards = {}
local function MakeCard(key, index)
	local card = CreateFrame("Button", nil, editor)
	card:SetSize(CARD_W, CARD_H)
	card:SetPoint("TOPLEFT", 16, -86 - (index - 1) * (CARD_H + CARD_GAP))

	card.bg = card:CreateTexture(nil, "BACKGROUND")
	card.bg:SetAllPoints()
	card.bg:SetColorTexture(1, 1, 1, 0.06)

	card.sel = card:CreateTexture(nil, "BORDER")
	card.sel:SetAllPoints()
	card.sel:SetColorTexture(1, 0.82, 0, 0.18)

	card.hl = card:CreateTexture(nil, "HIGHLIGHT")
	card.hl:SetAllPoints()
	card.hl:SetColorTexture(1, 1, 1, 0.06)

	MakeBadge(card, key)
	if key == "B" then card:Disable() end

	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	card.name:SetPoint("TOPLEFT", 64, -12)
	card.name:SetPoint("RIGHT", -52, 0)
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)

	card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.sub:SetPoint("RIGHT", -52, 0)
	card.sub:SetJustifyH("LEFT")
	card.sub:SetWordWrap(false)

	if key ~= "B" then
		card:SetScript("OnClick", function()
			selected = key
			Refresh()
		end)

		-- Go inside a category.
		card.open = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
		card.open:SetSize(40, CARD_H - 16)
		card.open:SetPoint("RIGHT", -8, 0)
		card.open:SetText(">")
		card.open:SetScript("OnClick", function()
			path = path .. key
			selected = "A"
			Refresh()
		end)
	end
	cards[key] = card
	return card
end

for i, key in ipairs(ns.CHOICES) do MakeCard(key, i) end
local cancelCard = MakeCard("B", #ns.CHOICES + 1)
cancelCard.sel:Hide()
cancelCard.name:SetText("|cff808080Cancel|r")
cancelCard.sub:SetText("Always closes the menu")

------------------------------------------------------------------------
-- Form for the selected slot
------------------------------------------------------------------------
local divider = editor:CreateTexture(nil, "BORDER")
divider:SetPoint("TOPLEFT", FORM_X - 8, -46)
divider:SetPoint("BOTTOMLEFT", FORM_X - 8, 50)
divider:SetWidth(1)
divider:SetColorTexture(1, 1, 1, 0.12)

local formTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
formTitle:SetPoint("TOPLEFT", FORM_X + 8, -52)

local formPress = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
formPress:SetPoint("TOPLEFT", formTitle, "BOTTOMLEFT", 0, -4)

local kindLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
kindLabel:SetPoint("TOPLEFT", FORM_X + 8, -100)
kindLabel:SetText("This button does")

local kindButtons = {}
local function SetKind(kind)
	local level = LevelAt(path)
	local old = level[selected]
	if KindOf(old) == kind then return end
	if kind == "empty" then
		level[selected] = nil
	elseif kind == "message" then
		local label = old and old.label or "New message"
		level[selected] = { label = label, text = label, chat = "SAY" }
	else
		level[selected] = { label = old and old.label or "New group" }
	end
	ns.MenuChanged()
	Refresh()
end

for i, entry in ipairs({ { "message", "Send a message" }, { "category", "Open a group" }, { "empty", "Nothing" } }) do
	local b = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
	b:SetSize(108, 30)
	b:SetPoint("TOPLEFT", FORM_X + 8 + (i - 1) * 114, -116)
	b:SetText(entry[2])
	b:SetScript("OnClick", function() SetKind(entry[1]) end)
	kindButtons[entry[1]] = b
end

local function MakeField(labelText, y, maxLetters, onChange)
	local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", FORM_X + 8, y)
	label:SetText(labelText)
	local box = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
	box:SetSize(WIDTH - FORM_X - 36, 28)
	box:SetPoint("TOPLEFT", FORM_X + 14, y - 16)
	box:SetAutoFocus(false)
	box:SetMaxLetters(maxLetters)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then onChange(self:GetText()) end
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	return label, box
end

local nameLabel, nameBox = MakeField("Name in the menu", -162, 40, function(text)
	local node = SelectedNode()
	if node then
		node.label = text
		Refresh(true)
	end
end)

local textLabel, textBox = MakeField("Message that gets sent", -218, 255, function(text)
	local node = SelectedNode()
	if node and node.text then
		node.text = text
		Refresh(true)
	end
end)

local chatButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
chatButton:SetSize(160, 30)
chatButton:SetPoint("TOPLEFT", FORM_X + 8, -276)
chatButton:SetScript("OnClick", function()
	local node = SelectedNode()
	if not (node and node.text) then return end
	local types, current = ns.CHAT_TYPES, node.chat or "SAY"
	local nextIndex = 1
	for i, t in ipairs(types) do
		if t == current then nextIndex = i % #types + 1 end
	end
	node.chat = types[nextIndex]
	Refresh()
end)

-- A real click, so even /say outdoors goes through.
local sendNow = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
sendNow:SetSize(160, 30)
sendNow:SetPoint("LEFT", chatButton, "RIGHT", 10, 0)
sendNow:SetText("Send now")
sendNow:SetScript("OnClick", function() ns.SendNode(SelectedNode()) end)

local openGroup = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
openGroup:SetSize(220, 34)
openGroup:SetPoint("TOPLEFT", FORM_X + 8, -222)
openGroup:SetText("Edit what's inside  >")
openGroup:SetScript("OnClick", function()
	path = path .. selected
	selected = "A"
	Refresh()
end)

local note = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
note:SetPoint("TOPLEFT", FORM_X + 8, -320)
note:SetWidth(WIDTH - FORM_X - 30)
note:SetJustifyH("LEFT")

------------------------------------------------------------------------
-- Footer
------------------------------------------------------------------------
local status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", 16, 18)
status:SetPoint("RIGHT", -200, 0)
status:SetJustifyH("LEFT")

local resetArmed = false
local reset = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
reset:SetSize(170, 28)
reset:SetPoint("BOTTOMRIGHT", -16, 12)
reset:SetScript("OnClick", function(self)
	if not resetArmed then
		resetArmed = true
		self:SetText("Tap again to reset")
		C_Timer.After(4, function()
			resetArmed = false
			if editor:IsShown() then Refresh(true) end
		end)
		return
	end
	resetArmed = false
	ns.ResetToDefaults()
	path, selected = "", "A"
	Refresh()
end)

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function DescribeCard(card, node)
	local kind = KindOf(node)
	card.open:SetShown(kind == "category")
	if kind == "empty" then
		card.name:SetText("|cff808080(empty)|r")
		card.sub:SetText("Does nothing")
	elseif kind == "category" then
		card.name:SetText(NameOf(node))
		local n = CountChildren(node)
		card.sub:SetText("Group  -  " .. n .. (n == 1 and " item" or " items"))
	else
		card.name:SetText(NameOf(node))
		card.sub:SetText(ChatLabel(node.chat) .. ":  " .. (node.text ~= "" and node.text or "(no text)"))
	end
end

-- textOnly: called while typing, so leave the edit boxes alone.
Refresh = function(textOnly)
	-- The level being edited may have vanished (reset, or a parent turned into a message).
	while path ~= "" and KindOf(LevelAt(path)) ~= "category" do
		path = path:sub(1, -2)
	end
	local level = LevelAt(path)

	crumb:SetText(Breadcrumb())
	back:SetEnabled(path ~= "")
	for _, key in ipairs(ns.CHOICES) do
		local card = cards[key]
		DescribeCard(card, level[key])
		card.sel:SetShown(key == selected)
	end

	local node = level[selected]
	local kind = KindOf(node)
	local depth = #path + 1
	local presses = {}
	for i = 1, #path do presses[#presses + 1] = path:sub(i, i) end
	presses[#presses + 1] = selected
	formTitle:SetText("|c" .. ns.KEY_COLOR[selected] .. selected .. "|r button")
	formPress:SetText("In game: macro, then " .. table.concat(presses, " > "))

	if not textOnly then
		for k, b in pairs(kindButtons) do
			b:SetEnabled(k ~= kind and not (k == "category" and depth >= ns.MAX_DEPTH))
			if k == kind then b:LockHighlight() else b:UnlockHighlight() end
		end
		nameBox:SetText(node and node.label or "")
		textBox:SetText(node and node.text or "")
	end

	local isMessage, isCategory = kind == "message", kind == "category"
	nameLabel:SetShown(node ~= nil); nameBox:SetShown(node ~= nil)
	textLabel:SetShown(isMessage); textBox:SetShown(isMessage)
	chatButton:SetShown(isMessage); sendNow:SetShown(isMessage)
	openGroup:SetShown(isCategory)
	chatButton:SetText("Channel: " .. ChatLabel(node and node.chat))

	if isCategory then
		note:SetText("Switching this to a message or nothing deletes everything inside it.")
	elseif kind == "empty" then
		note:SetText("Pressing this button here does nothing.")
	elseif depth >= ns.MAX_DEPTH then
		note:SetText("Deepest level: buttons here can only send messages.")
	else
		note:SetText("")
	end

	local notes = {}
	if ns.IsPublishPending() then
		notes[#notes + 1] = "|cffffd100Changes apply when combat ends.|r"
	end
	if not ns.savedLoaded then
		notes[#notes + 1] = "First run (or saved settings didn't load): using the default menu."
	end
	status:SetText(table.concat(notes, "  "))
	if not resetArmed then reset:SetText("Reset to defaults") end
end

editor:SetScript("OnShow", function() Refresh() end)

-- Pick up the "changes apply after combat" note going away.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function()
	if editor:IsShown() then C_Timer.After(0, function() Refresh(true) end) end
end)

