-- Tree-and-details editor, opened by the VGSEdit macro or /vgs.
-- Custom controls only: no Blizzard widget templates or UISpecialFrames (the
-- latter taints Forever's gamepad chat focus stack). /vgs is a deliberate
-- exception for keyboard players, though slash commands may taint it too.
local _, ns = ...
local WIDTH, HEIGHT, SPLIT = 760, 650, 350
local selected, expanded = "A", { X = true, XA = true }
local context = "DEFAULT"
local history, typingField = {}, nil
local Refresh, nameBox, textBox, detail, move, confirm, emotePanel, emoteField, DrawEmotes

-- Return the saved slot, following the selected condition through its parents.
-- Ownership prevents edits to inherited nodes from changing the default menu.
local function Slot(path)
	local node = ns.GetMenu()
	local owned = context == "DEFAULT"
	for i = 1, #path - 1 do
		local condition
		node, condition = ns.PickNode(node[path:sub(i, i)], context)
		node = ns.GetBattlegroundNode(node, context)
		owned = condition == context or owned and condition == nil
		if not node or ns.IsMessage(node) then return nil end
	end
	return node, path:sub(-1), owned
end
local function At(path)
	if path == "" then return ns.GetMenu(), context == "DEFAULT" end
	local parent, key, owned = Slot(path)
	if not parent then return nil, false end
	local node, condition = ns.PickNode(parent[key], context)
	node = ns.GetBattlegroundNode(node, context)
	return node, condition == context or owned and condition == nil
end
local function Put(path, node)
	local parent, key, owned = Slot(path)
	local raw = parent[key]
	local _, condition = ns.PickNode(raw, context)
	if context == "DEFAULT" then
		local variants = raw and raw.variants
		parent[key] = node or (variants and { empty = true })
		if parent[key] then parent[key].variants = variants end
	elseif owned and condition == nil then
		parent[key] = node
	else
		if not raw then raw = { empty = true }; parent[key] = raw end
		raw.variants = raw.variants or {}
		raw.variants[context] = node or false
	end
end
local function IsGroup(node) return type(node) == "table" and not ns.IsMessage(node) end
local function Breadcrumb(path)
	local parts = { "Top" }
	for i = 1, #path do parts[#parts + 1] = ns.NodeLabel(At(path:sub(1, i))) end
	return table.concat(parts, " / ")
end
local function Sequence(path) return (path:gsub(".", "%0 > ")):gsub(" > $", "") end
local function Remember(field)
	if field and typingField == field then return end
	history[#history + 1] = { menu = ns.CopyMenu(ns.GetMenu()), selected = selected, expanded = ns.CopyMenu(expanded), context = context }
	if #history > 20 then table.remove(history, 1) end
	typingField = field
end
local function Changed(textOnly)
	ns.MenuChanged()
	Refresh(textOnly)
end
local function Select(path)
	if nameBox then nameBox:ClearFocus(); textBox:ClearFocus() end
	if detail then detail:ScrollTo(0) end
	typingField, selected = nil, path
	if emotePanel then emotePanel:Hide() end
	for i = 1, #path - 1 do expanded[path:sub(1, i)] = true end
	Refresh()
end
-- Empty groups still need room for a message below them.
local function Depth(node)
	if not node then return 0 end
	local depth = node.empty and 0 or (IsGroup(node) and 2 or 1)
	if IsGroup(node) then
		for _, key in ipairs(ns.CHOICES) do depth = math.max(depth, node[key] and 1 + Depth(node[key]) or 0) end
	end
	for _, variant in pairs(node.variants or {}) do if variant then depth = math.max(depth, Depth(variant)) end end
	return depth
end
local function CanMove(from, to)
	if from == to or from:sub(1, #to) == to or to:sub(1, #from) == from then return false end
	local source, owned = At(from)
	if not source or not owned then return false end
	local target = At(to)
	if context == "DEFAULT" then
		local parent, key = Slot(from); source = parent[key]
		parent, key = Slot(to); target = parent and parent[key]
	end
	return IsGroup(At(to:sub(1, -2)))
		and #to + Depth(source) - 1 <= ns.MAX_DEPTH
		and #from + Depth(target) - 1 <= ns.MAX_DEPTH
end

local function Surface(parent, r, g, b)
	local edge = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
	edge:SetAllPoints(); edge:SetColorTexture(0.22, 0.22, 0.23, 1)
	local bg = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(r, g, b, 1)
	return bg
end
local function Text(parent, font, x, y, width, value)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	text:SetPoint("TOPLEFT", x, y); text:SetWidth(width); text:SetJustifyH("LEFT")
	text:SetWordWrap(false); text:SetText(value or "")
	return text
end
local function Button(parent, label, x, y, width, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 28); button:SetPoint("TOPLEFT", x, y)
	button.bg = Surface(button, 0.16, 0.16, 0.17)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.label:SetPoint("CENTER"); button.label:SetWidth(width - 12)
	button.label:SetWordWrap(false); button.label:SetText(label)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.07)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnable", function(self) self.label:SetAlpha(1) end)
	button:SetScript("OnDisable", function(self) self.label:SetAlpha(0.4) end)
	return button
end
-- Template-free scroll areas; mouse wheel plus small, flat scroll buttons.
local function Scroll(parent, x, y, width, height)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetPoint("TOPLEFT", x, y); scroll:SetSize(width, height)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
	content:SetSize(width - 16, height); scroll:SetScrollChild(content)
	scroll.content, scroll.offset, scroll.maximum = content, 0, 0
	local track = scroll:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOPRIGHT", -3, -30); track:SetSize(3, height - 60)
	track:SetColorTexture(1, 1, 1, 0.06)
	local thumb = scroll:CreateTexture(nil, "ARTWORK")
	thumb:SetWidth(3); thumb:SetColorTexture(0.65, 0.61, 0.52, 0.7)
	function scroll:ScrollTo(offset)
		self.offset = math.max(0, math.min(self.maximum, offset))
		self:SetVerticalScroll(self.offset)
		local thumbHeight = math.max(20, (height - 60) * height / math.max(height, content:GetHeight()))
		thumb:SetHeight(thumbHeight)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", -3, -30 - (self.maximum > 0 and self.offset / self.maximum * (height - 60 - thumbHeight) or 0))
	end
	local up = Button(scroll, "^", width - 14, 0, 14, function() scroll:ScrollTo(scroll.offset - 60) end)
	local down = Button(scroll, "v", width - 14, -height + 28, 14, function() scroll:ScrollTo(scroll.offset + 60) end)
	up.label:SetWidth(14); down.label:SetWidth(14)
	function scroll:ContentHeight(value)
		content:SetHeight(math.max(height, value)); self.maximum = math.max(0, value - height)
		track:SetShown(self.maximum > 0); thumb:SetShown(self.maximum > 0)
		up:SetShown(self.maximum > 0); down:SetShown(self.maximum > 0)
		self:ScrollTo(self.offset)
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.offset - delta * 34) end)
	return scroll
end

local editor = CreateFrame("Frame", "VGSChatEditor", UIParent)
editor:SetSize(WIDTH, HEIGHT); editor:SetPoint("CENTER"); editor:SetFrameStrata("DIALOG")
editor:SetToplevel(true); editor:SetMovable(true); editor:SetClampedToScreen(true); editor:EnableMouse(true)
Surface(editor, 0.09, 0.09, 0.1)
editor:Hide()
local header = CreateFrame("Frame", nil, editor)
header:SetPoint("TOPLEFT", 1, -1); header:SetSize(WIDTH - 2, 60)
header:EnableMouse(true); header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function() editor:StartMoving() end)
header:SetScript("OnDragStop", function() editor:StopMovingOrSizing() end)
Text(header, "GameFontNormalLarge", 18, -12, 320, "VGS Chat")
local subtitle = Text(header, "GameFontHighlightSmall", 18, -34, 320, "Menu setup")
subtitle:SetTextColor(0.7, 0.68, 0.63)
local compact = Button(header, "", WIDTH - 284, -16, 114, function()
	ns.DB.compact = not ns.DB.compact
	ns.UpdateMenu(); Refresh(true)
end)
local undo = Button(header, "Undo", WIDTH - 160, -16, 66, function()
	local previous = table.remove(history)
	if not previous then return end
	nameBox:ClearFocus(); textBox:ClearFocus(); typingField = nil
	move:Hide(); confirm:Hide(); emotePanel:Hide()
	ns.DB.menu, selected, expanded = previous.menu, previous.selected, previous.expanded
	context = previous.context
	Changed()
end)
Button(header, "Close", WIDTH - 84, -16, 64, function() editor:Hide() end)
local divider = editor:CreateTexture(nil, "ARTWORK")
divider:SetPoint("TOPLEFT", SPLIT, -60); divider:SetPoint("BOTTOMLEFT", SPLIT, 52)
divider:SetWidth(1); divider:SetColorTexture(0.22, 0.22, 0.23, 1)
local footerLine = editor:CreateTexture(nil, "ARTWORK")
footerLine:SetPoint("BOTTOMLEFT", 1, 52); footerLine:SetPoint("BOTTOMRIGHT", -1, 52)
footerLine:SetHeight(1); footerLine:SetColorTexture(0.22, 0.22, 0.23, 1)
local status = Text(editor, "GameFontHighlightSmall", 18, -HEIGHT + 40, WIDTH - 190)
status:SetTextColor(0.89, 0.77, 0.48)
local cancelHint = Text(editor, "GameFontHighlightSmall", 18, -HEIGHT + 23, WIDTH - 190, "|c" .. ns.KEY_COLOR.B .. "B|r always cancels  ·  Four presses maximum")
cancelHint:SetTextColor(0.7, 0.68, 0.63)
local mappingCaption = Text(editor, "GameFontHighlightSmall", 18, -74, 324)
mappingCaption:SetTextColor(0.7, 0.68, 0.63)
local mappings = {}
for i, condition in ipairs(ns.CONTEXTS) do
	mappings[condition] = Button(editor, ns.CONTEXT_LABELS[condition], 16 + (i - 1) * 110, -94, 104, function()
		nameBox:ClearFocus(); textBox:ClearFocus(); move:Hide(); confirm:Hide(); emotePanel:Hide()
		typingField, context = nil, condition; detail:ScrollTo(0); Refresh()
	end)
end
local customize = Button(editor, "Customize option", 16, -130, 168, function()
	local node, owned = At(selected)
	if context == "DEFAULT" or owned then return end
	Remember(); Put(selected, ns.ResolveNode(node, context)); Changed()
end)
local inherit = Button(editor, "Use inherited", 194, -130, 146, function()
	local parent, key = Slot(selected)
	local raw = parent and parent[key]
	if context == "DEFAULT" or not raw or not raw.variants or raw.variants[context] == nil then return end
	Remember(); raw.variants[context] = nil
	if not next(raw.variants) then raw.variants = nil; if raw.empty then parent[key] = nil end end
	Changed()
end)
local mappingHint = Text(editor, "GameFontHighlightSmall", 18, -168, 324)
mappingHint:SetTextColor(0.7, 0.68, 0.63)
local tree = Scroll(editor, 16, -190, SPLIT - 26, HEIGHT - 252)
detail = Scroll(editor, SPLIT + 18, -76, WIDTH - SPLIT - 32, HEIGHT - 140)
local form = detail.content
local formTitle = Text(form, "GameFontHighlightLarge", 0, 0, form:GetWidth())
formTitle:SetWordWrap(true)
local formPath = Text(form, "GameFontHighlightSmall", 0, -28, form:GetWidth())
formPath:SetTextColor(0.7, 0.68, 0.63)
local formKind = Text(form, "GameFontHighlightSmall", 0, -46, form:GetWidth())
formKind:SetTextColor(0.7, 0.68, 0.63)

local function Field(label, y, maxLetters, property)
	local caption = Text(form, "GameFontHighlightSmall", 0, y, form:GetWidth(), label)
	caption:SetTextColor(0.7, 0.68, 0.63)
	local box = CreateFrame("EditBox", nil, form)
	box:SetSize(form:GetWidth(), 30); box:SetPoint("TOPLEFT", 0, y - 18)
	box:SetAutoFocus(false); box:SetMaxLetters(maxLetters); box:SetFontObject("GameFontHighlight")
	box:SetTextInsets(9, 9, 0, 0); Surface(box, 0.055, 0.055, 0.065)
	box:SetScript("OnTextChanged", function(self, userInput)
		local node, owned = At(selected)
		if userInput and owned and node and node[property] ~= self:GetText() then
			Remember(self); node[property] = self:GetText(); Changed(true)
		end
	end)
	box:SetScript("OnEditFocusLost", function() typingField = nil end)
	box:SetScript("OnEnterPressed", box.ClearFocus); box:SetScript("OnEscapePressed", box.ClearFocus)
	return caption, box
end
local nameLabel, textLabel
nameLabel, nameBox = Field("Menu label", -76, 40, "label")
textLabel, textBox = Field("Message", -136, 255, "text")
local emptyHint = Text(form, "GameFontHighlight", 0, -80, form:GetWidth(), "Choose what this button should do.")
emptyHint:SetWordWrap(true)
local addMessage = Button(form, "+ Message", 0, -118, 124, function()
	local node, owned = At(selected)
	if node or not owned then return end
	Remember(); Put(selected, { label = "New message", text = "Hello!" }); Changed()
end)
local addGroup = Button(form, "+ Group", 134, -118, 104, function()
	local node, owned = At(selected)
	if node or not owned or #selected >= ns.MAX_DEPTH then return end
	Remember(); Put(selected, { label = "New group" }); expanded[selected] = true; Changed()
end)

-- One custom confirmation panel for deleting a group or resetting the menu.
confirm = CreateFrame("Frame", nil, editor)
confirm:SetSize(420, 160); confirm:SetPoint("CENTER"); confirm:SetFrameLevel(editor:GetFrameLevel() + 30)
confirm:EnableMouse(true); Surface(confirm, 0.12, 0.12, 0.13); confirm:Hide()
local confirmTitle = Text(confirm, "GameFontHighlightLarge", 18, -18, 384)
local confirmText = Text(confirm, "GameFontHighlight", 18, -50, 384)
confirmText:SetWordWrap(true)
local confirmAction
Button(confirm, "Cancel", 18, -114, 82, function() confirm:Hide() end)
local confirmApply = Button(confirm, "Remove", 270, -114, 132, function()
	local action = confirmAction; confirm:Hide(); if action then action() end
end)
confirmApply.label:SetTextColor(1, 0.4, 0.4)
local function Ask(title, message, label, action)
	nameBox:ClearFocus(); textBox:ClearFocus()
	if move then move:Hide(); emotePanel:Hide() end
	confirmTitle:SetText(title); confirmText:SetText(message); confirmApply.label:SetText(label)
	confirmAction = action; confirm:Show()
end
Button(editor, "Reset defaults", WIDTH - 148, -HEIGHT + 39, 130, function()
	Ask("Reset your menu?", "Replace all options with the defaults. You can undo this change.", "Reset", function()
		Remember(); selected, expanded, context = "A", { X = true, XA = true }, "DEFAULT"; ns.ResetToDefaults(); Refresh()
	end)
end)

-- Destination picker includes empty slots and swaps, without overwriting data.
move = CreateFrame("Frame", nil, editor)
move:SetSize(WIDTH - SPLIT - 20, HEIGHT - 124); move:SetPoint("TOPLEFT", SPLIT + 10, -66)
move:SetFrameLevel(editor:GetFrameLevel() + 20); move:EnableMouse(true); Surface(move, 0.12, 0.12, 0.13); move:Hide()
local moveTitle = Text(move, "GameFontHighlightLarge", 14, -14, move:GetWidth() - 28)
local moveHint = Text(move, "GameFontHighlightSmall", 14, -40, move:GetWidth() - 28, "Choose a destination. Occupied slots swap.")
moveHint:SetTextColor(0.7, 0.68, 0.63)
local destinations = Scroll(move, 10, -68, move:GetWidth() - 20, move:GetHeight() - 124)
local destinationRows, destination, moveSource = {}, nil, nil
local DrawDestinations
local applyMove = Button(move, "Move option", move:GetWidth() - 146, -move:GetHeight() + 42, 132, function()
	if not (moveSource and destination and At(moveSource) and CanMove(moveSource, destination)) then return end
	Remember()
	if context == "DEFAULT" then
		local sourceParent, sourceKey = Slot(moveSource)
		local targetParent, targetKey = Slot(destination)
		sourceParent[sourceKey], targetParent[targetKey] = targetParent[targetKey], sourceParent[sourceKey]
	else
		local source, target = ns.ResolveNode(At(moveSource), context), ns.ResolveNode(At(destination), context)
		Put(moveSource, target); Put(destination, source)
	end
	local movedExpanded = {}
	for path, value in pairs(expanded) do
		local targetPath = path
		if path:sub(1, #moveSource) == moveSource then targetPath = destination .. path:sub(#moveSource + 1)
		elseif path:sub(1, #destination) == destination then targetPath = moveSource .. path:sub(#destination + 1) end
		movedExpanded[targetPath] = value
	end
	expanded = movedExpanded; move:Hide(); selected = destination
	for i = 1, #selected - 1 do expanded[selected:sub(1, i)] = true end
	Changed()
end)
Button(move, "Cancel", 14, -move:GetHeight() + 42, 82, function() move:Hide() end)
DrawDestinations = function()
	local paths = {}
	local function Walk(node, parent)
		for _, key in ipairs(ns.CHOICES) do
			local path = parent .. key
			if CanMove(moveSource, path) then paths[#paths + 1] = path end
			local child = At(path)
			if IsGroup(child) and #path < ns.MAX_DEPTH then Walk(child, path) end
		end
	end
	Walk(ns.GetMenu(), "")
	local valid = false
	for _, path in ipairs(paths) do if path == destination then valid = true end end
	if not valid then destination = nil end
	for i, path in ipairs(paths) do
		local row = destinationRows[i]
		if not row then
			row = Button(destinations.content, "", 0, -(i - 1) * 46, destinations.content:GetWidth(), function(self)
				destination = self.path; DrawDestinations()
			end)
			row:SetHeight(42); row.label:Hide()
			row.name = Text(row, "GameFontHighlightSmall", 10, -6, row:GetWidth() - 20)
			row.description = Text(row, "GameFontHighlightSmall", 10, -23, row:GetWidth() - 20)
			destinationRows[i] = row
		end
		row.path = path; row.name:SetText(Breadcrumb(path:sub(1, -2)))
		row.description:SetText("|c" .. ns.KEY_COLOR[path:sub(-1)] .. Sequence(path) .. "|r  ·  " .. (At(path) and "Swap with " .. ns.NodeLabel(At(path)) or "Empty slot"))
		row.bg:SetColorTexture(path == destination and 0.22 or 0.16, path == destination and 0.2 or 0.16, path == destination and 0.15 or 0.17, 1)
		row:Show()
	end
	for i = #paths + 1, #destinationRows do destinationRows[i]:Hide() end
	destinations:ContentHeight(#paths * 46)
	applyMove:SetEnabled(destination ~= nil)
	applyMove.label:SetText(destination and At(destination) and "Swap options" or "Move option")
	moveHint:SetText(#paths > 0 and "Choose a destination. Occupied slots swap." or "No destination fits the four-press limit.")
end
local moveButton = Button(form, "Move / swap...", 0, -264, 122, function()
	nameBox:ClearFocus(); textBox:ClearFocus()
	confirm:Hide(); emotePanel:Hide()
	moveSource, destination = selected, nil; destinations:ScrollTo(0)
	moveTitle:SetText("Move " .. ns.NodeLabel(At(selected))); DrawDestinations(); move:Show()
end)
local remove = Button(form, "Remove", 132, -264, 80, function()
	local path = selected
	local node, owned = At(path)
	if not node or not owned then return end
	local function Delete()
		Remember(); Put(path, nil); Changed()
	end
	if IsGroup(node) then
		Ask("Remove " .. ns.NodeLabel(node) .. "?", "This removes the group and every option inside it. Undo restores the whole group.", "Remove group", Delete)
	else Delete() end
end)
remove.label:SetTextColor(1, 0.4, 0.4)
local sendNow = Button(form, "Send now", 222, -264, 90, function() ns.SendNode(At(selected), context) end)

-- Emote picker: a scrollable list of common emotes plus a token box for the
-- rest. An emote fires along with the text, or alone when the message has none
-- (the shipped "Wave" option is emote-only).
local EMOTES = {
	{ name = "No emote" },
	{ name = "Wave", token = "WAVE" },
	{ name = "Hello", token = "HELLO" },
	{ name = "Goodbye", token = "BYE" },
	{ name = "Thanks", token = "THANK" },
	{ name = "Cheer", token = "CHEER" },
	{ name = "Applaud", token = "APPLAUD" },
	{ name = "Congratulate", token = "CONGRATULATE" },
	{ name = "Bow", token = "BOW" },
	{ name = "Salute", token = "SALUTE" },
	{ name = "Dance", token = "DANCE" },
	{ name = "Laugh", token = "LAUGH" },
	{ name = "Joke", token = "JOKE" },
	{ name = "Silly", token = "SILLY" },
	{ name = "Point", token = "POINT" },
	{ name = "Roar", token = "ROAR" },
	{ name = "Agree", token = "AGREE" },
	{ name = "Sigh", token = "SIGH" },
	{ name = "Out of mana", token = "OOM" },
}
local EMOTE_NAMES = {}
for _, emote in ipairs(EMOTES) do
	if emote.token then EMOTE_NAMES[emote.token] = emote.name end
end

local emoteButton = Button(form, "", 0, -232, 160, function()
	local node, owned = At(selected)
	if not (owned and ns.IsMessage(node)) then return end
	nameBox:ClearFocus(); textBox:ClearFocus(); emoteField:ClearFocus()
	move:Hide(); confirm:Hide(); emotePanel:Show(); DrawEmotes()
end)

emotePanel = CreateFrame("Frame", nil, editor)
emotePanel:SetSize(WIDTH - SPLIT - 20, HEIGHT - 124); emotePanel:SetPoint("TOPLEFT", SPLIT + 10, -66)
emotePanel:SetFrameLevel(editor:GetFrameLevel() + 20); emotePanel:EnableMouse(true)
Surface(emotePanel, 0.12, 0.12, 0.13); emotePanel:Hide()
Text(emotePanel, "GameFontHighlightLarge", 14, -14, emotePanel:GetWidth() - 28, "Emote")
local emoteHint = Text(emotePanel, "GameFontHighlightSmall", 14, -44, emotePanel:GetWidth() - 28, "Plays with the message, or alone when Message is empty.")
emoteHint:SetTextColor(0.7, 0.68, 0.63)
local emoteList = Scroll(emotePanel, 10, -66, emotePanel:GetWidth() - 20, emotePanel:GetHeight() - 224)
local emoteRows = {}
local emoteTokenLabel = Text(emotePanel, "GameFontHighlightSmall", 14, -emotePanel:GetHeight() + 150, emotePanel:GetWidth() - 28, "Custom emote token, for example KISS")
emoteTokenLabel:SetTextColor(0.7, 0.68, 0.63)
emoteField = CreateFrame("EditBox", nil, emotePanel)
emoteField:SetSize(emotePanel:GetWidth() - 28, 28); emoteField:SetPoint("TOPLEFT", 14, -emotePanel:GetHeight() + 132)
emoteField:SetAutoFocus(false); emoteField:SetMaxLetters(24); emoteField:SetFontObject("GameFontHighlight")
emoteField:SetTextInsets(9, 9, 0, 0); Surface(emoteField, 0.055, 0.055, 0.065)
emoteField:SetScript("OnTextChanged", function(self, userInput)
	local node, owned = At(selected)
	if not (userInput and owned and ns.IsMessage(node)) then return end
	Remember(self)
	local token = self:GetText():gsub("%s", ""):upper()
	node.emote = token ~= "" and token or nil
	Changed(true); DrawEmotes()
end)
emoteField:SetScript("OnEditFocusLost", function() typingField = nil end)
emoteField:SetScript("OnEnterPressed", emoteField.ClearFocus); emoteField:SetScript("OnEscapePressed", emoteField.ClearFocus)
local function SetEmote(token)
	local node, owned = At(selected)
	if not (owned and ns.IsMessage(node)) then return end
	Remember(); node.emote = token; Changed(); DrawEmotes()
end
DrawEmotes = function()
	local node = At(selected)
	local current = node and ns.IsMessage(node) and node.emote or nil
	for i, emote in ipairs(EMOTES) do
		local row = emoteRows[i]
		if not row then
			row = Button(emoteList.content, "", 0, -(i - 1) * 34, emoteList.content:GetWidth(), function(self) SetEmote(self.token) end)
			emoteRows[i] = row
		end
		row.token = emote.token
		row.label:SetText(emote.token and emote.name .. "  ·  /" .. emote.token:lower() or emote.name)
		local active = current == emote.token
		row.bg:SetColorTexture(active and 0.22 or 0.16, active and 0.2 or 0.16, active and 0.15 or 0.17, 1)
		row:Show()
	end
	emoteList:ContentHeight(#EMOTES * 34 + 4)
	emoteField:SetText(current or "")
end
Button(emotePanel, "Close", 14, -emotePanel:GetHeight() + 40, 82, function() emotePanel:Hide() end)

local groupHint = Text(form, "GameFontHighlightSmall", 0, -184, form:GetWidth(), "Expand the group in the tree to edit its options.")
groupHint:SetTextColor(0.7, 0.68, 0.63); groupHint:SetWordWrap(true)
local previewCaption = Text(form, "GameFontHighlightSmall", 0, -316, form:GetWidth(), "HUD preview")
previewCaption:SetTextColor(0.7, 0.68, 0.63)
local previewArea = CreateFrame("Frame", nil, form)
previewArea:SetPoint("TOPLEFT", 0, -338)
local preview = ns.CreateMenuView(previewArea)
preview:SetPoint("TOPLEFT", previewArea, "TOPLEFT", 0, 0)

local rows = {}
local function DrawTree()
	local visible = {}
	local function Walk(node, parent)
		for _, key in ipairs(ns.CHOICES) do
			local path = parent .. key
			visible[#visible + 1] = path
			local child = At(path)
			if IsGroup(child) and expanded[path] and #path < ns.MAX_DEPTH then Walk(child, path) end
		end
	end
	Walk(ns.GetMenu(), "")
	for i, path in ipairs(visible) do
		local row = rows[i]
		if not row then
			row = CreateFrame("Button", nil, tree.content)
			row:SetHeight(32)
			row.selection = row:CreateTexture(nil, "BACKGROUND")
			row.selection:SetAllPoints(); row.selection:SetColorTexture(0.22, 0.2, 0.15, 1)
			local hover = row:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.05)
			row.expand = Button(row, ">", 0, -2, 22, function(self)
				local p = self:GetParent().path
				move:Hide(); confirm:Hide(); emotePanel:Hide()
				expanded[p] = not expanded[p]
				if not expanded[p] and selected:sub(1, #p) == p then Select(p) else Refresh() end
			end)
			row.badges = {}
			for _, key in ipairs(ns.CHOICES) do
				local holder = CreateFrame("Frame", nil, row)
				holder:SetSize(22, 22); holder:SetPoint("LEFT", 26, 0)
				local badge = ns.MakeBadge(holder, key, 22); badge:SetPoint("LEFT", 0, 0)
				row.badges[key] = holder
			end
			row.label = Text(row, "GameFontHighlight", 58, -9, 160)
			row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.kind:SetPoint("RIGHT", -6, 0); row.kind:SetTextColor(0.7, 0.68, 0.63)
			row:SetScript("OnClick", function(self) move:Hide(); confirm:Hide(); emotePanel:Hide(); Select(self.path) end)
			rows[i] = row
		end
		local node, indent = At(path), (#path - 1) * 14
		row.path = path; row:SetWidth(tree.content:GetWidth() - indent)
		row:SetPoint("TOPLEFT", indent, -(i - 1) * 34)
		row.selection:SetShown(path == selected)
		row.expand:SetShown(IsGroup(node)); row.expand.label:SetText(expanded[path] and "v" or ">")
		for key, badge in pairs(row.badges) do badge:SetShown(key == path:sub(-1)); badge:SetAlpha(node and 1 or 0.4) end
		row.label:SetWidth(row:GetWidth() - 104)
		row.label:SetText(node and ns.NodeLabel(node) or "+ Add option")
		row.label:SetTextColor(path == selected and 0.89 or (node and 0.94 or 0.6), path == selected and 0.77 or (node and 0.92 or 0.6), path == selected and 0.48 or (node and 0.89 or 0.6))
		local _, owned = At(path)
		row.kind:SetText(context ~= "DEFAULT" and owned and "Custom" or (IsGroup(node) and "Group" or ""))
		row:Show()
	end
	for i = #visible + 1, #rows do rows[i]:Hide() end
	tree:ContentHeight(#visible * 34 + 4)
end

Refresh = function(textOnly)
	compact.label:SetText(ns.DB.compact and "Compact: On" or "Compact: Off")
	while #selected > 1 and not IsGroup(At(selected:sub(1, -2))) do selected = selected:sub(1, -2) end
	local node, owned = At(selected)
	local message, group = node and ns.IsMessage(node), IsGroup(node)
	mappingCaption:SetText("Edit tab  ·  Active: " .. ns.CONTEXT_LABELS[ns.GetContext()])
	for condition, button in pairs(mappings) do
		local active = condition == context
		button.bg:SetColorTexture(active and 0.22 or 0.16, active and 0.2 or 0.16, active and 0.15 or 0.17, 1)
		button.label:SetTextColor(active and 0.89 or 0.94, active and 0.77 or 0.92, active and 0.48 or 0.89)
	end
	customize:SetShown(context ~= "DEFAULT"); customize:SetEnabled(not owned)
	inherit:SetShown(context ~= "DEFAULT")
	local slotParent, slotKey = Slot(selected)
	local raw = slotParent[slotKey]
	inherit:SetEnabled(context ~= "DEFAULT" and raw and raw.variants and raw.variants[context] ~= nil or false)
	mappingHint:SetText(context == "DEFAULT" and "Say tab · other tabs inherit these options" or (owned and "Custom tab · editing this branch" or "Inherited · customize to make changes"))
	DrawTree(); undo:SetEnabled(#history > 0)
	formTitle:SetText("|c" .. ns.KEY_COLOR[selected:sub(-1)] .. selected:sub(-1) .. "|r  " .. (node and ns.NodeLabel(node) or "Add an option"))
	-- Keep long labels in their field; avoid a heading growing into the controls.
	formTitle:SetWordWrap(false)
	formPath:SetText(Breadcrumb(selected:sub(1, -2)))
	formKind:SetText(Sequence(selected) .. "  ·  " .. (message and "Message" or (group and "Group" or "Empty slot")) .. (context ~= "DEFAULT" and (owned and " · Custom" or " · Inherited") or ""))
	if not textOnly then nameBox:SetText(node and node.label or ""); textBox:SetText(message and node.text or "") end
	nameLabel:SetShown(node ~= nil); nameBox:SetShown(node ~= nil)
	textLabel:SetShown(message); textBox:SetShown(message)
	for _, box in ipairs({ nameBox, textBox }) do box:EnableMouse(owned); box:EnableKeyboard(owned); box:SetAlpha(owned and 1 or 0.5) end
	emptyHint:SetShown(node == nil); addMessage:SetShown(node == nil); addGroup:SetShown(node == nil)
	addMessage:SetEnabled(owned); addGroup:SetEnabled(owned and #selected < ns.MAX_DEPTH); groupHint:SetShown(group)
	moveButton:SetShown(node ~= nil); remove:SetShown(node ~= nil); sendNow:SetShown(message)
	moveButton:SetEnabled(owned); remove:SetEnabled(owned); 	sendNow:SetEnabled(ns.IsAvailable(node, context))
	emoteButton:SetShown(message); emoteButton:SetEnabled(owned)
	emoteButton.label:SetText("Emote: " .. (node and node.emote and (EMOTE_NAMES[node.emote] or node.emote) or "Off"))
	local actionY = message and -196 or -136
	moveButton:SetPoint("TOPLEFT", 0, actionY); remove:SetPoint("TOPLEFT", 132, actionY)
	sendNow:SetPoint("TOPLEFT", 222, actionY)
	local previewY = message and 284 or (group and 232 or 190)
	previewCaption:SetPoint("TOPLEFT", 0, -previewY + 22)
	previewArea:SetPoint("TOPLEFT", 0, -previewY)
	local parent = group and selected or selected:sub(1, -2)
	previewCaption:SetText("HUD preview · " .. ns.CONTEXT_LABELS[context])
	preview:Display(ns.ResolveNode(At(parent), context), parent == "" and "Quick Chat" or ns.NodeLabel(At(parent)), parent, context)
	-- Fit wrapped HUD labels too, keeping the right side free of scrolling.
	local previewScale = math.min(1, (detail:GetHeight() - previewY - 10) / preview:GetHeight())
	preview:SetScale(previewScale)
	previewArea:SetSize(preview:GetWidth() * previewScale, preview:GetHeight() * previewScale)
	detail:ContentHeight(previewY + previewArea:GetHeight() + 10)
	if ns.IsPublishPending() then
		status:SetText(InCombatLockdown() and "Changes apply after combat and when quick chat closes." or "Close quick chat to apply changes.")
	else
		status:SetText(ns.savedLoaded == false and "Default menu loaded (first run or saved settings unavailable)." or "Changes saved")
	end
end

local toggle = CreateFrame("Button", "VGSChatEditorToggle", UIParent)
toggle:RegisterForClicks("AnyUp", "AnyDown")
-- VGSEdit, /vgs and the minimap button all open the editor through this.
function ns.ToggleEditor() editor:SetShown(not editor:IsShown()) end
toggle:SetScript("OnClick", ns.ToggleEditor)
-- /vgs toggles the editor for keyboard players; gamepad players use VGSEdit.
SLASH_VGSCHAT1 = "/vgs"
SlashCmdList.VGSCHAT = ns.ToggleEditor
editor:SetScript("OnShow", function()
	editor:SetScale(math.min(1, (UIParent:GetWidth() - 32) / WIDTH, (UIParent:GetHeight() - 32) / HEIGHT))
	Refresh()
end)
editor:SetScript("OnHide", function()
	nameBox:ClearFocus(); textBox:ClearFocus(); move:Hide(); confirm:Hide(); emotePanel:Hide()
end)
-- Also clears a deferred status once the secure menu receives the new snapshot.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
watcher:RegisterEvent("ZONE_CHANGED")
watcher:SetScript("OnEvent", function() if editor:IsShown() then C_Timer.After(0, function() Refresh(true) end) end end)
local open = _G.VGSChatOpen
open:HookScript("OnClick", function() if editor:IsShown() then Refresh(true) end end)
