-- Run from the addon directory: lua tests/editor.lua
-- Exercises the real editor callbacks and secure snippet with a small WoW API stub.
local objects, combat, secure = {}, false, false
local homeGroup, instanceGroup = "SOLO", "SOLO"
local instanceType = "none"
local instanceID, subzone = 529, ""
local subzoneReads = 0
function IsInInstance() return instanceType ~= "none", instanceType end
function GetInstanceInfo() return "Arathi Basin", instanceType, 0, "", 0, 0, false, instanceID end
function GetSubZoneText() subzoneReads = subzoneReads + 1; return subzone end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
function IsInGroup(category)
	if category == LE_PARTY_CATEGORY_HOME then return homeGroup ~= "SOLO" end
	if category == LE_PARTY_CATEGORY_INSTANCE then return instanceGroup ~= "SOLO" end
	return homeGroup ~= "SOLO" or instanceGroup ~= "SOLO"
end
function IsInRaid(category)
	if category == LE_PARTY_CATEGORY_HOME then return homeGroup == "RAID" end
	if category == LE_PARTY_CATEGORY_INSTANCE then return instanceGroup == "RAID" end
	return homeGroup == "RAID" or instanceGroup == "RAID"
end
local methods = {}
regenDisabling = false
local function Object(kind, name, parent, template)
	local obj = setmetatable({ kind = kind, parent = parent, template = template, shown = true,
		attributes = {}, scripts = {}, hooks = {}, events = {}, text = "", width = 0, height = 0 }, { __index = methods })
	objects[#objects + 1] = obj
	if name then _G[name] = obj end
	return obj
end
for _, method in ipairs({ "SetFrameStrata", "SetToplevel", "SetMovable", "SetClampedToScreen", "EnableMouse",
	"EnableMouseWheel", "EnableKeyboard", "RegisterForDrag", "RegisterForClicks", "SetAllPoints", "SetTextColor",
	"SetJustifyH", "SetColorTexture", "SetTexture", "AddMaskTexture", "SetFontObject", "SetTextInsets",
	"SetAutoFocus", "SetMaxLetters", "SetScale", "SetScrollChild", "SetHighlightTexture", "SetOwner", "AddLine", "SetVerticalScroll", "StartMoving", "StopMovingOrSizing" }) do
	methods[method] = function() end
end
function methods:CreateTexture() return Object("Texture", nil, self) end
function methods:CreateMaskTexture() return Object("Mask", nil, self) end
function methods:CreateFontString(_, _, font) return Object("Text", nil, self, font) end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetScale(value) self.scale = value end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetParent() return self.parent end
function methods:SetParent(parent) self.parent = parent end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:GetFrameLevel() return self.frameLevel or 0 end
function methods:SetWordWrap(value) self.wrap = value end
function methods:SetText(value)
	self.text = value or ""
	if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function methods:GetText() return self.text end
function methods:GetStringHeight()
	local text = self.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return 14 * (self.wrap and self.width > 0 and math.max(1, math.ceil(#text * 7 / self.width)) or 1)
end
function methods:SetAttribute(key, value)
	assert(not combat or secure, "Insecure protected attribute write during combat")
	self.attributes[key] = value
end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:SetScript(key, fn) self.scripts[key] = fn end
function methods:HookScript(key, fn)
	self.hooks[key] = self.hooks[key] or {}; table.insert(self.hooks[key], fn)
end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:Show()
	local old = self.shown; self.shown = true
	if not old and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
	local old = self.shown; self.shown = false
	if old and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetEnabled(value)
	self.enabled = value
	local fn = self.scripts[value and "OnEnable" or "OnDisable"]; if fn then fn(self) end
end
function methods:ClearFocus() if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
function methods:ClearBindings() self.bound, self.bindings = false, {} end
function methods:ClearBinding(key) assert(secure); if self.bindings then self.bindings[key] = nil end end
function methods:SetBindingClick(priority, key, target, button)
	assert(secure and priority and target == "PADChatOpen")
	self.bindings = self.bindings or {}; self.bindings[key] = button; self.bound = true
end
function CreateFrame(...) return Object(...) end
UIParent = Object("Frame"); UIParent:SetSize(960, 540)
Minimap = Object("Frame", nil, UIParent); Minimap:SetSize(198, 198)
GameTooltip = Object("GameTooltip", nil, UIParent)
function methods:GetCenter() return 800, 400 end
function methods:GetEffectiveScale() return 1 end
local cursorX, cursorY = 0, 0
function GetCursorPosition() return cursorX, cursorY end
function InCombatLockdown() return combat end
SlashCmdList = {}
function RegisterStateDriver(frame, state, driver)
	assert(not combat and state == "context" and (driver == "[group] GROUP; DEFAULT" or driver == "RAID" or driver == "WSG"))
	frame.driver = driver
	frame:SetAttribute("state-context", driver ~= "[group] GROUP; DEFAULT" and driver or IsInGroup() and "GROUP" or "DEFAULT")
end
function wipe(t) for key in pairs(t) do t[key] = nil end end
local overrides = {}
function SetOverrideBindingClick(owner, priority, key, target, button)
	assert(not combat and priority, "Override bindings are protected in combat")
	overrides[key] = { owner = owner, target = target, button = button }
end
function ClearOverrideBindings(owner)
	assert(not combat or regenDisabling, "Override bindings are protected in combat")
	for key, binding in pairs(overrides) do if binding.owner == owner then overrides[key] = nil end end
end
function hooksecurefunc(t, name, hook)
	local original = t[name]
	t[name] = function(...) local result = original(...); hook(...); return result end
end
local lfgResults = {}
C_LFGList = { GetSearchResultInfo = function(id) return lfgResults[id] end }
C_Timer = { After = function(_, fn) fn() end }
local sent
local emotes = {}
function DoEmote(token) emotes[#emotes + 1] = token end
function SendChatMessage(text, channel, _, target) sent = { text, channel, target } end
-- Blizzard's Recent Allies, the Whisper tab's only source.
local alliesEnabled, alliesReady, allies = true, true, {}
local function Ally(name, online, ...)
	local interactions = {}
	for i, timestamp in ipairs({ ... }) do interactions[i] = { timestamp = timestamp } end
	return { characterData = { fullName = name }, stateData = { isOnline = online }, interactionData = { interactions = interactions } }
end
C_RecentAllies = {
	IsSystemEnabled = function() return alliesEnabled end,
	IsRecentAllyDataReady = function() return alliesReady end,
	-- Restricted: an addon calling it gets "blocked from an action only available to the Blizzard UI".
	TryRequestRecentAlliesData = function() error("ADDON_ACTION_BLOCKED: TryRequestRecentAlliesData") end,
	GetRecentAllies = function() return allies end,
}
function Ambiguate(name) return (name:gsub("%-Faerlina$", "")) end
local ns = { BATTLEGROUNDS_ENABLED = true } -- keep the post-launch BG paths covered
assert(loadfile("Messages.lua"))("PADChat", ns)
assert(loadfile("PADChat.lua"))("PADChat", ns)
assert(loadfile("Integrations.lua"))("PADChat", ns)
local shippedDefaults = ns.CopyMenu(ns.DefaultMenu)
-- Exercise the existing editor and inheritance against a pre-upgrade menu;
-- the new shipped defaults and upgrade are checked separately below.
for _, key in ipairs(ns.CHOICES) do ns.DefaultMenu[key].variants = nil end
for _, frame in ipairs(objects) do
	if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "PADChat") end
end
assert(loadfile("Editor.lua"))("PADChat", ns)
assert(loadfile("MinimapButton.lua"))("PADChat", ns)
PADChatEditor:Show()
local function Find(predicate, optional)
	for _, obj in ipairs(objects) do if obj:IsVisible() and predicate(obj) then return obj end end
	if optional then return nil end
	error("Visible control not found")
end
local function Click(button)
	assert(button.enabled ~= false, "Disabled control clicked")
	button.scripts.OnClick(button)
end
local function Button(label) return Find(function(o) return o.kind == "Button" and o.label and o.label.text == label end) end
local function Row(path) return Find(function(o) return o.path == path and o.selection ~= nil end) end
local function Select(path) Click(Row(path)) end
local function Expand(path) Click(Row(path).expand) end
local function Undo() Click(Button("Undo")) end
local function Field(y) return Find(function(o) return o.kind == "EditBox" and o.point[3] == y end) end
local function emotePanelShown()
	for _, o in ipairs(objects) do
		if o.kind == "Text" and o.text == "Emote" then return o.parent:IsShown() end
	end
end
local function Type(box, text) box.text = text; box.scripts.OnTextChanged(box, true) end
local function Move(from, to)
	Select(from); Click(Button("Move / swap..."))
	Click(Find(function(o) return o.path == to and o.description ~= nil end))
	local node = ns.GetMenu()
	for key in to:gmatch(".") do node = node and node[key] end
	Click(Button(node and "Swap options" or "Move option"))
end
local function Pad(button)
	for _, fn in ipairs(PADChatOpen.hooks.PreClick or {}) do fn(PADChatOpen, button) end
	secure = true
	local env = { self = PADChatOpen, button = button }
	local snippet = PADChatOpen.attributes._onclick
	local chunk = loadstring and setfenv(assert(loadstring(snippet, "secure click")), env)
		or assert(load(snippet, "secure click", "t", env))
	chunk()
	secure = false
	for _, fn in ipairs(PADChatOpen.hooks.OnClick) do fn(PADChatOpen) end
end
local function Event(event, ...)
	for _, frame in ipairs(objects) do if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end end
end
local function Group(home, instance, kind)
	homeGroup, instanceGroup = home or "SOLO", instance or "SOLO"
	instanceType = kind or "none"
	-- Emulate the native secure state driver (including in combat).
	secure = true
	PADChatOpen:SetAttribute("state-context", PADChatOpen.driver ~= "[group] GROUP; DEFAULT" and PADChatOpen.driver or IsInGroup() and "GROUP" or "DEFAULT")
	secure = false
	Event("GROUP_ROSTER_UPDATE")
end

local function LeafLabels(view)
	local labels = {}
	for _, obj in ipairs(objects) do
		if obj.kind == "Text" and obj:IsVisible() and obj.parent.parent.parent == view then
			labels[#labels + 1] = obj.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		end
	end
	return labels
end

-- Expanded is the saved default; both views use the same secure button paths.
assert(ns.DB.compact == false)
Pad("LeftButton")
local labels = LeafLabels(PADChatMenu)
assert(table.concat(labels, ",") == "AA - Yes,AX - No,AY - Thanks,XAA - Hello,XAX - Goodbye,XAY - Wave,XXA - Invite please!,XXX - Want to group?,XXY - Inviting you,YA - Help!,YX - Incoming!,YY - Follow me")
local expandedHeight = PADChatMenu:GetHeight()
Click(Button("Compact: Off"))
assert(ns.DB.compact and PADChatMenu:GetHeight() < expandedHeight and #LeafLabels(PADChatMenu) == 0)
assert(Find(function(o) return o.kind == "Text" and o.parent.parent == PADChatMenu and o.text == "Respond" end))
Event("ADDON_LOADED", "PADChat"); assert(ns.DB.compact, "Loading saved settings must preserve Compact")
combat = true
Click(Button("Compact: On")); Pad("X"); Pad("A")
assert(table.concat(LeafLabels(PADChatMenu), ",") == "XAA - Hello,XAX - Goodbye,XAY - Wave")
Click(Button("Compact: Off")); assert(PADChatOpen:GetAttribute("path") == "XA")
Pad("A"); assert(sent[1] == "Hello" and not PADChatMenu:IsShown())
combat = false; Click(Button("Compact: On"))

-- Shoulder overrides cover modifier keys, wrap tabs, reset a partial sequence,
-- and release on send, cancel, and macro toggle. Closed menus ignore shoulders.
local function Released()
	assert(not PADChatOpen.bound and next(PADChatOpen.bindings) == nil and not PADChatMenu:IsShown())
end
Pad("RB"); Released()
Pad("LeftButton")
assert(PADChatOpen:GetAttribute("menucontext") == "DEFAULT")
assert(PADChatOpen.bindings.PADLSHOULDER == "LB" and PADChatOpen.bindings.PADRSHOULDER == "RB")
assert(PADChatOpen.bindings["CTRL-PAD1"] == "A" and PADChatOpen.bindings["ALT-CTRL-SHIFT-PADRSHOULDER"] == "RB")
Pad("X"); Pad("A"); Pad("RB")
assert(PADChatOpen:GetAttribute("menucontext") == "GROUP" and PADChatOpen:GetAttribute("path") == "")
Pad("RB"); assert(PADChatOpen:GetAttribute("menucontext") == "RAID")
Pad("RB"); assert(PADChatOpen:GetAttribute("menucontext") == "WHISPER")
assert(PADChatOpen.bindings.PADDUP == "UP" and PADChatOpen.bindings["SHIFT-PADDDOWN"] == "DOWN")
Pad("RB"); assert(PADChatOpen:GetAttribute("menucontext") == "DEFAULT")
assert(PADChatOpen.bindings.PADDUP == nil and PADChatOpen.bindings["SHIFT-PADDDOWN"] == nil, "D-pad is only taken on the Whisper tab")
Pad("LB"); assert(PADChatOpen:GetAttribute("menucontext") == "WHISPER")
Pad("LB"); assert(PADChatOpen:GetAttribute("menucontext") == "RAID")
Pad("LB"); assert(PADChatOpen:GetAttribute("menucontext") == "GROUP")
Pad("LB"); assert(PADChatOpen:GetAttribute("menucontext") == "DEFAULT")
PADChatOpen:SetAttribute("battlegrounds", false) -- beta: the BG tab is skipped
Pad("RB"); Pad("RB"); assert(PADChatOpen:GetAttribute("menucontext") == "WHISPER")
Pad("LB"); assert(PADChatOpen:GetAttribute("menucontext") == "GROUP")
PADChatOpen:SetAttribute("battlegrounds", true)
Pad("B"); Released()
Pad("LeftButton"); Pad("LeftButton"); Released()

-- Whisper sends the Say menu to the ally picked with the D-pad. Up/Down wrap,
-- the list is newest first, and a list change mid-pick doesn't move it.
combat = true
Pad("LeftButton"); Pad("LB"); assert(PADChatWhispers:IsVisible())
assert(Find(function(o) return o.kind == "Text" and o.text == "No allies online" end))
local beforeEmpty = sent
Pad("A"); Pad("A"); assert(sent == beforeEmpty, "Nothing to whisper without a recipient"); Released()
allies = { Ally("Bob-Grobbulus", true, 100), Ally("alice", true, 200), Ally("Cara", true, 300) }
Pad("LeftButton"); assert(PADChatOpen:GetAttribute("menucontext") == "DEFAULT" and not PADChatWhispers:IsVisible())
Pad("LB"); assert(ns.GetWhisperTarget() == "Cara")
Pad("DOWN"); Pad("DOWN"); assert(ns.GetWhisperTarget() == "Bob-Grobbulus")
Pad("DOWN"); assert(ns.GetWhisperTarget() == "Cara")
Pad("UP"); assert(ns.GetWhisperTarget() == "Bob-Grobbulus")
allies[#allies + 1] = Ally("Dan", true, 999)
assert(ns.GetWhisperTarget() == "Bob-Grobbulus")
Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Hello" and sent[2] == "WHISPER" and sent[3] == "Bob-Grobbulus"); Released()
assert(ns.GetWhispers()[1] == "Dan", "The next menu sees the newer ally")
Pad("LeftButton"); Pad("DOWN"); assert(PADChatOpen:GetAttribute("whisperindex") == 0, "Up/Down do nothing off the Whisper tab")
Pad("B"); Released()
combat = false

-- Enhance LFG Window (on by default): Y on a selected listing opens the
-- Whisper tab with its leader picked; Y does nothing without a selection, when
-- the window is closed, when the setting is off, or in combat.
assert(ns.DB.enhanceLFG == true)
LFGParentFrame = CreateFrame("Frame"); LFGParentFrame:Hide()
LFGBrowseFrame = CreateFrame("Frame", nil, LFGParentFrame)
LFGBrowseFrame.SendMessageButton = CreateFrame("Button", nil, LFGBrowseFrame)
local lfgSelection
LFGBrowseFrame.selectionBehavior = {
	HasSelection = function() return lfgSelection ~= nil end,
	GetSelectedElementData = function() return { lfgSelection and { data = { resultID = lfgSelection } } } end,
}
LFGBrowseFrame.UpdateButtonState = function() end
local function SelectListing(id) lfgSelection = id; LFGBrowseFrame:UpdateButtonState() end
local function FireHooks(frame, script) for _, fn in ipairs(frame.hooks[script] or {}) do fn(frame) end end
lfgResults[7] = { leaderName = "Kira-Faerlina" }
lfgResults[8] = { leaderName = "Animal" }
Event("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
local lfgHint
for _, o in ipairs(objects) do
	if o.parent == LFGBrowseFrame and o.point and o.point[2] == LFGBrowseFrame.SendMessageButton then lfgHint = o end
end
assert(lfgHint and lfgHint.point[3] == "RIGHT", "Y prompt sits right of Send Message")
assert(overrides.PAD4 == nil and not lfgHint:IsVisible())
LFGParentFrame:Show(); FireHooks(LFGBrowseFrame, "OnShow")
assert(lfgHint:IsVisible() and lfgHint.alpha ~= 1 and overrides.PAD4 == nil, "Dimmed, unbound with nothing selected")
SelectListing(7)
assert(lfgHint.alpha == 1 and overrides.PAD4.target == "PADChatOpen" and overrides.PAD4.button == "WHISPER")
Pad(overrides.PAD4.button)
assert(PADChatOpen:GetAttribute("menucontext") == "WHISPER" and ns.GetWhisperTarget() == "Kira")
assert(PADChatOpen.bindings.PAD4 == "Y" and PADChatOpen.bindings.PADDDOWN == "DOWN", "Quick chat takes Y and the D-pad while open")
Pad("WHISPER"); assert(PADChatOpen:GetAttribute("open"), "Y in the open menu never re-opens it")
Pad("A"); Pad("A"); assert(sent[1] == "Yes!" and sent[2] == "WHISPER" and sent[3] == "Kira"); Released()
assert(overrides.PAD4, "Y stays ready for the next listing")
SelectListing(8); Pad("WHISPER"); Pad("DOWN")
assert(ns.GetWhisperTarget() == "Dan", "The rest of the whisper list stays reachable")
Pad("B"); Released()
SelectListing(nil); assert(overrides.PAD4 == nil)
SelectListing(7)
regenDisabling = true; Event("PLAYER_REGEN_DISABLED"); regenDisabling = false
combat = true; assert(overrides.PAD4 == nil, "Y goes back to the action bar in combat")
SelectListing(8); assert(overrides.PAD4 == nil)
combat = false; Event("PLAYER_REGEN_ENABLED"); assert(overrides.PAD4)
local function Toggle(setting) return Find(function(o) return o.kind == "Button" and o.setting == setting end) end
Click(Button("Settings")); assert(Toggle("enhanceLFG").label.text == "On"); Click(Toggle("enhanceLFG"))
assert(ns.DB.enhanceLFG == false and Toggle("enhanceLFG").label.text == "Off" and overrides.PAD4 == nil and not lfgHint:IsVisible())
Click(Toggle("enhanceLFG")); assert(ns.DB.enhanceLFG and overrides.PAD4 and lfgHint:IsVisible())
Click(Button("Done")); assert(Find(function(o) return o.label and o.label.text == "Done" end, true) == nil)
LFGParentFrame:Hide(); FireHooks(LFGBrowseFrame, "OnHide"); assert(overrides.PAD4 == nil)

-- Enhance Recent Allies Window (on by default): the online ally under the
-- cursor gets a Y line at the bottom of its tooltip, and Y whispers them.
assert(ns.DB.enhanceRecentAllies == true)
local tooltipLines = {}
local allyTooltip = { AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end }
RecentAlliesSocialCardMixin = {
	BuildTooltip = function(self, tooltip) tooltip:AddLine(self.elementData.characterData.fullName) end,
	HideTooltip = function() end,
}
Event("ADDON_LOADED", "Blizzard_RecentAllies")
local function Card(name, online)
	local card = CreateFrame("Button", nil, UIParent)
	for key, fn in pairs(RecentAlliesSocialCardMixin) do card[key] = fn end -- what Mixin() does on creation
	card.elementData = { characterData = { fullName = name }, stateData = { isOnline = online } }
	return card
end
local function Hover(card) tooltipLines = {}; card:BuildTooltip(allyTooltip) end
local bo, trixie = Card("Bo-Faerlina", true), Card("Trixie", false)
Hover(bo)
assert(tooltipLines[1] == "Bo-Faerlina" and tooltipLines[#tooltipLines]:find("Y|r Whisper with quick chat"), "Y line goes last")
assert(overrides.PAD4 and overrides.PAD4.button == "WHISPER")
combat = true
Pad("WHISPER"); assert(PADChatOpen:GetAttribute("menucontext") == "WHISPER" and ns.GetWhisperTarget() == "Bo")
Pad("A"); Pad("X"); assert(sent[1] == "No." and sent[2] == "WHISPER" and sent[3] == "Bo"); Released()
combat = false
bo:HideTooltip(); assert(overrides.PAD4 == nil, "Y is released when the cursor leaves the card")
Hover(trixie); assert(#tooltipLines == 1 and overrides.PAD4 == nil, "Offline allies can't be whispered")
trixie:HideTooltip()
LFGParentFrame:Show(); FireHooks(LFGBrowseFrame, "OnShow"); SelectListing(7)
Hover(bo); assert(ns.IntegrationTarget() == "Bo-Faerlina", "The card under the cursor wins over the LFG selection")
bo:HideTooltip(); assert(ns.IntegrationTarget() == "Kira-Faerlina" and overrides.PAD4)
LFGParentFrame:Hide(); FireHooks(LFGBrowseFrame, "OnHide")
regenDisabling = true; Event("PLAYER_REGEN_DISABLED"); regenDisabling = false; combat = true
Hover(bo); assert(#tooltipLines == 1 and overrides.PAD4 == nil, "No Y line in combat, when Y can't be claimed")
bo:HideTooltip(); combat = false; Event("PLAYER_REGEN_ENABLED")
Click(Button("Settings")); Click(Toggle("enhanceRecentAllies"))
assert(ns.DB.enhanceRecentAllies == false and Toggle("enhanceRecentAllies").label.text == "Off")
Hover(bo); assert(#tooltipLines == 1 and overrides.PAD4 == nil)
bo:HideTooltip(); Click(Toggle("enhanceRecentAllies")); Click(Button("Done"))
Hover(bo); assert(overrides.PAD4); bo:HideTooltip()

-- The LFG window's Who tab (same setting): Y whispers the player whose row,
-- or its invite button, the cursor is on, and a Y glyph sits on that row.
LFGWhoListButtonMixin = { OnEnter = function() end }
WhoInviteButtonMixin = { OnEnter = function() end }
Event("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
LFGWhoListFrame = CreateFrame("Frame", nil, LFGParentFrame)
local function WhoRow(name)
	local row = CreateFrame("Button", nil, LFGWhoListFrame)
	row.OnEnter = LFGWhoListButtonMixin.OnEnter -- what Mixin() does on creation
	row.InviteButton = CreateFrame("Button", nil, row)
	row.InviteButton.OnEnter = WhoInviteButtonMixin.OnEnter
	row.InviteButton.info = { fullName = name }
	return row
end
local function Leave(frame) FireHooks(frame, "OnLeave") end
local whoHint
local horse, umbra = WhoRow("Horse-Faerlina"), WhoRow("Umbra")
LFGBrowseFrame:Hide(); LFGParentFrame:Show() -- Who and Browse are separate tabs
horse:OnEnter()
for _, o in ipairs(objects) do if o.parent == horse and o.point and o.point[2] == horse.InviteButton then whoHint = o end end
assert(whoHint and whoHint:IsVisible() and whoHint.point[1] == "RIGHT" and whoHint.point[3] == "LEFT", "Y glyph sits left of the row's invite button")
assert(overrides.PAD4 and ns.IntegrationTarget() == "Horse-Faerlina")
Leave(horse); horse.InviteButton:OnEnter()
assert(ns.IntegrationTarget() == "Horse-Faerlina" and overrides.PAD4, "The invite button counts as its row")
combat = true
Pad("WHISPER"); assert(PADChatOpen:GetAttribute("menucontext") == "WHISPER" and ns.GetWhisperTarget() == "Horse")
Pad("A"); Pad("Y"); assert(sent[1] == "Thanks!" and sent[2] == "WHISPER" and sent[3] == "Horse"); Released()
combat = false
Leave(horse.InviteButton); umbra:OnEnter()
assert(ns.IntegrationTarget() == "Umbra" and whoHint.parent == umbra and whoHint:IsVisible())
Leave(umbra); assert(overrides.PAD4 == nil and not whoHint:IsShown(), "Y is released off the list")
umbra:OnEnter(); LFGParentFrame:Hide(); ns.UpdateIntegrations()
assert(overrides.PAD4 == nil, "A hidden Who tab can't be whispered from")
LFGParentFrame:Show(); ns.UpdateIntegrations(); assert(overrides.PAD4)
Click(Button("Settings")); Click(Toggle("enhanceLFG"))
assert(overrides.PAD4 == nil and not whoHint:IsShown(), "Enhance LFG Window covers the Who tab")
Click(Toggle("enhanceLFG")); Click(Button("Done")); assert(overrides.PAD4)
regenDisabling = true; Event("PLAYER_REGEN_DISABLED"); regenDisabling = false; combat = true
Leave(umbra); horse:OnEnter(); assert(overrides.PAD4 == nil and not whoHint:IsShown(), "No glyph in combat")
combat = false; Event("PLAYER_REGEN_ENABLED"); assert(overrides.PAD4 and whoHint:IsShown())
Leave(horse); LFGParentFrame:Hide(); LFGBrowseFrame:Show(); ns.UpdateIntegrations()

-- The Whisper tab lists online Recent Allies by most recent interaction (at
-- most ten), and nothing while that system is off or loading. A picked player
-- still goes first.
alliesReady = false
allies = { Ally("Old-Faerlina", true, 100), Ally("Gone", false, 900), Ally("Quiet", true), Ally("Fresh", true, 500, 50) }
for i = 1, 9 do allies[#allies + 1] = Ally("Filler" .. i, true, 10 + i) end
Event("PLAYER_ENTERING_WORLD") -- never asks for the data itself (the stub raises if it does)
assert(#ns.GetWhispers() == 0, "Nothing listed until the data arrives")
Pad("LeftButton"); Pad("LB")
assert(Find(function(o) return o.kind == "Text" and o.text == "Open Recent Allies to load" end), "Says how to load the list")
Pad("B"); Released()
alliesReady = true
local list = ns.GetWhispers()
assert(list[1] == "Fresh" and list[2] == "Old" and list[3] == "Filler9" and #list == 10, "Newest first, ten at most")
for _, name in ipairs(list) do assert(name ~= "Gone" and name ~= "Quiet", "No offline allies; no-interaction allies sort last") end
combat = true
Pad("LeftButton"); Pad("LB"); assert(ns.GetWhisperTarget() == "Fresh"); Pad("DOWN")
allies[#allies + 1] = Ally("Newest", true, 999)
assert(ns.GetWhisperTarget() == "Old", "An open menu keeps its list")
Pad("A"); Pad("A"); assert(sent[3] == "Old"); Released()
assert(ns.GetWhispers()[1] == "Newest")
combat = false
LFGBrowseFrame:Show(); LFGParentFrame:Show(); FireHooks(LFGBrowseFrame, "OnShow"); SelectListing(7)
Pad("WHISPER"); assert(ns.GetWhisperTarget() == "Kira" and ns.GetWhispers()[2] == "Newest", "A picked stranger goes first")
Pad("B"); Released()
Pad("LeftButton"); Pad("LB"); assert(ns.GetWhisperTarget() == "Newest", "A picked player only heads that one menu")
Pad("B"); Released()
alliesEnabled = false
assert(#ns.GetWhispers() == 0, "System off: nothing listed")
Pad("WHISPER"); assert(ns.GetWhisperTarget() == "Kira" and #ns.GetWhispers() == 1, "A picked player can still be whispered")
Pad("B"); Released()
SelectListing(nil); LFGParentFrame:Hide(); FireHooks(LFGBrowseFrame, "OnHide")
alliesEnabled = true

-- Auto-selection distinguishes solo, parties, normal raids, PvE instances,
-- arenas, and battlegrounds. The chosen tab overrides old per-message channels.
for _, scenario in ipairs({
	{ nil, nil, "none", "DEFAULT", "SAY" },
	{ "PARTY", nil, "none", "GROUP", "PARTY" },
	{ "RAID", nil, "none", "GROUP", "RAID" },
	{ nil, "PARTY", "party", "GROUP", "INSTANCE_CHAT" },
	{ nil, "RAID", "raid", "GROUP", "INSTANCE_CHAT" },
	{ nil, "PARTY", "arena", "GROUP", "INSTANCE_CHAT" },
	{ "PARTY", "RAID", "pvp", "RAID", "INSTANCE_CHAT" },
}) do
	Group(scenario[1], scenario[2], scenario[3]); combat = true
	Pad("LeftButton"); assert(PADChatOpen:GetAttribute("menucontext") == scenario[4])
	Pad("A"); Pad("A"); assert(sent[1] == "Yes!" and sent[2] == scenario[5]); Released()
	combat = false
end
Group("PARTY"); combat = true
Pad("LeftButton"); Pad("LB"); Pad("A"); Pad("A")
assert(sent[2] == "SAY"); Released()
Group(); Pad("LeftButton"); Pad("RB")
local beforeUnavailable = sent
Pad("A"); Pad("A"); assert(sent == beforeUnavailable); Released()
combat = false

-- Entering a battleground during lockdown defers only the automatic default;
-- manual tab switching works immediately, and combat end refreshes the driver.
combat = true; Group(nil, "RAID", "pvp"); Event("ZONE_CHANGED_NEW_AREA")
Pad("LeftButton"); assert(PADChatOpen:GetAttribute("menucontext") == "GROUP")
Pad("RB"); Pad("A"); Pad("A"); assert(sent[2] == "INSTANCE_CHAT"); Released()
combat = false; Event("PLAYER_REGEN_ENABLED")
Pad("LeftButton"); assert(PADChatOpen:GetAttribute("menucontext") == "RAID")
Pad("B"); Released(); Group()

-- No Blizzard control templates were introduced.
for _, obj in ipairs(objects) do assert(not obj.template or obj.kind == "Text" or obj.template == "SecureHandlerClickTemplate") end
Select("XY"); Click(Button("+ Group")); assert(ns.DB.menu.X.Y and not ns.DB.menu.X.Y.text)
Select("XYA"); Click(Button("+ Message")); assert(ns.DB.menu.X.Y.A.text == "Hello!")
Type(Field(-94), "Custom"); Type(Field(-94), "Custom greeting"); Undo()
assert(ns.DB.menu.X.Y.A.label == "New message", "Typing should undo as one change")
Type(Field(-154), "Greetings!")
assert(Button("Group").enabled ~= false) -- Mapping selector remains available while solo.
assert(Button("Battleground").enabled ~= false, "Inactive tabs remain editable")
Group("PARTY")
Click(Button("Group"))
Click(Button("Send now")); assert(sent[1] == "Greetings!" and sent[2] == "PARTY")
Group()
Click(Button("Say"))
Select("XY"); Click(Button("Remove")); assert(ns.DB.menu.X.Y, "Group deletion needs confirmation")
Click(Button("Cancel")); assert(ns.DB.menu.X.Y)
Click(Button("Remove")); Click(Button("Remove group")); assert(ns.DB.menu.X.Y == nil)
Undo(); assert(ns.DB.menu.X.Y.A.text == "Greetings!")
Select("XY"); Click(Button("Remove")); Click(Button("Remove group"))
Move("A", "XY")
assert(ns.DB.menu.A == nil and ns.DB.menu.X.Y.A.text == "Yes!", "Move must preserve children")
assert(Row("XY").selection.shown, "Moved option should stay selected")
Undo(); assert(ns.DB.menu.A.A.text == "Yes!" and ns.DB.menu.X.Y == nil)
Move("A", "XAA")
assert(ns.DB.menu.A.text == "Hello" and ns.DB.menu.X.A.A.A.text == "Yes!", "Swap must preserve both subtrees")
Undo(); assert(ns.DB.menu.A.A.text == "Yes!" and ns.DB.menu.X.A.A.text == "Hello")

-- A depth-four destination must reject a group, and descendants cannot receive their parent.
Select("XAA"); Click(Button("Remove")); Click(Button("+ Group"))
Select("XAAA"); Click(Button("+ Message"))
Select("A"); Click(Button("Move / swap..."))
for _, obj in ipairs(objects) do
	if obj:IsVisible() and obj.description then assert(obj.path ~= "XAAA" and obj.path ~= "AA") end
end
Click(Button("Cancel"))
Select("XAAA"); assert(Find(function(o) return o.label and o.label.text == "+ Group" end, true) == nil)
Select("XAAX"); assert(Button("+ Group").enabled == false, "Depth-four slots only accept messages")
Undo(); Undo(); Undo(); assert(ns.DB.menu.X.A.A.text == "Hello")

-- Editing an open menu leaves its active shape and text together until it closes.
Expand("A"); Select("AA"); Pad("LeftButton")
Type(Field(-154), "Changed!"); assert(ns.IsPublishPending())
Pad("A"); Pad("A"); assert(sent[1] == "Yes!" and not ns.IsPublishPending())
Pad("LeftButton"); Pad("A"); Pad("A"); assert(sent[1] == "Changed!")
Undo(); assert(ns.DB.menu.A.A.text == "Yes!")

-- Moving while in combat cannot write protected attributes or change an active send.
combat = true
Move("A", "XY"); assert(ns.IsPublishPending())
Pad("LeftButton"); Pad("A"); Pad("A"); assert(sent[1] == "Yes!")
assert(ns.IsPublishPending())
combat = false; Event("PLAYER_REGEN_ENABLED"); assert(not ns.IsPublishPending())
Pad("LeftButton"); Pad("X"); Pad("Y"); Pad("A"); assert(sent[1] == "Yes!")
Undo(); assert(ns.DB.menu.A and not ns.DB.menu.X.Y)

Click(Button("Reset defaults")); Click(Button("Reset")); assert(ns.DB.menu.A.label == "Respond")
Undo(); assert(ns.DB.menu.A.A.text == "Yes!")
-- All destinations route by current membership, without falling back to Say.
local previous = sent
ns.SendNode({ text = "Private" }, "GROUP"); assert(sent == previous)
assert(ns.GetChannel("RAID") == nil and ns.GetChannel("SAY") == "SAY")
Group("PARTY"); assert(ns.GetChannel("GROUP") == "PARTY" and ns.GetChannel("RAID") == nil)
Group("RAID"); assert(ns.GetChannel("GROUP") == "RAID" and ns.GetChannel("RAID") == nil)
Group(nil, "PARTY"); assert(ns.GetChannel("GROUP") == "INSTANCE_CHAT" and ns.GetChannel("RAID") == nil)
Group(nil, "RAID", "pvp"); assert(ns.GetChannel("GROUP") == "INSTANCE_CHAT" and ns.GetChannel("RAID") == "INSTANCE_CHAT")
Group()

-- A branch override inherits until customized, keeps defaults intact, and
-- updates the actual secure menu as membership changes, even during combat.
Select("X"); Click(Button("Group"))
assert(Button("Remove").enabled == false and Button("Customize option").enabled)
local defaultSocial = ns.CopyMenu(ns.DB.menu.X)
Click(Button("Customize option")); assert(ns.DB.menu.X.variants.GROUP.label == "Social")
Select("XAA"); Type(Field(-94), "Thanks for the group"); Type(Field(-154), "Thanks for the group!")
assert(Button("Send now").enabled == false)
assert(ns.DB.menu.X.A.A.text == defaultSocial.A.A.text)
assert(ns.ResolveNode(ns.GetMenu(), "GROUP").X.A.A.text == "Thanks for the group!")
combat = true; Group("PARTY")
Pad("LeftButton"); Pad("X"); Pad("A")
assert(LeafLabels(PADChatMenu)[1] == "XAA - Thanks for the group")
Pad("A")
assert(sent[1] == "Thanks for the group!" and sent[2] == "PARTY")
Pad("LeftButton"); Pad("LB"); Pad("X"); Pad("A")
assert(LeafLabels(PADChatMenu)[1] == "XAA - Hello", "Switching to Say must restore its own mapping")
Pad("A"); assert(sent[1] == "Hello" and sent[2] == "SAY")
Group("RAID"); Pad("LeftButton"); Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Thanks for the group!" and sent[2] == "RAID", "Raid inherits the broad Group override")
Group(); Pad("LeftButton"); Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Hello" and sent[2] == "SAY")
combat = false; Event("PLAYER_REGEN_ENABLED")

-- More specific overrides, undo, and restoration of inheritance.
Select("X"); Click(Button("Battleground")); Click(Button("Customize option"))
Select("XAA"); Type(Field(-154), "Thanks for the raid!")
Group(nil, "RAID", "pvp"); Pad("LeftButton"); Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Thanks for the raid!" and sent[2] == "INSTANCE_CHAT")
Pad("LeftButton"); Pad("LB"); Pad("X"); Pad("A")
assert(LeafLabels(PADChatMenu)[1] == "XAA - Thanks for the group", "Switching from Battleground must restore Group's mapping")
Pad("A"); assert(sent[1] == "Thanks for the group!" and sent[2] == "INSTANCE_CHAT")
Group("PARTY"); Pad("LeftButton"); Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Thanks for the group!" and sent[2] == "PARTY")
Select("X"); Click(Button("Use inherited")); assert(not ns.DB.menu.X.variants.RAID)
assert(ns.ResolveNode(ns.GetMenu(), "RAID").X.A.A.text == "Thanks for the group!")
Undo(); assert(ns.DB.menu.X.variants.RAID.A.A.text == "Thanks for the raid!")

-- Conditional empty slots, deletion, move/swap and inheritance restoration.
Click(Button("Group")); Select("XY"); Click(Button("+ Message"))
Type(Field(-154), "Group only"); assert(ns.ResolveNode(ns.GetMenu(), "DEFAULT").X.Y == nil)
Select("XY"); Click(Button("Remove")); assert(ns.DB.menu.X.variants.GROUP.Y == nil)
Select("X"); Click(Button("Use inherited")); assert(ns.DB.menu.X.variants.GROUP == nil)
Select("XY"); Click(Button("Customize option")); Click(Button("+ Message"))
assert(ns.DB.menu.X.Y.empty and ns.DB.menu.X.Y.variants.GROUP.text == "Hello!")
Select("XY"); Click(Button("Remove")); assert(ns.DB.menu.X.Y.variants.GROUP == false)
Click(Button("Use inherited")); assert(ns.DB.menu.X.Y == nil)
Select("X"); Click(Button("Customize option")); Select("XAA")
Type(Field(-154), "Moved group greeting")
Move("XAA", "Y")
assert(ns.ResolveNode(ns.GetMenu(), "GROUP").Y.text == "Moved group greeting")
assert(ns.DB.menu.Y.label == "Callout" and ns.DB.menu.Y.variants.GROUP.text == "Moved group greeting")
assert(ns.ResolveNode(ns.GetMenu(), "GROUP").X.A.A.label == "Callout")
Undo(); assert(ns.ResolveNode(ns.GetMenu(), "GROUP").X.A.A.text == "Moved group greeting")

-- Default moves carry all variants; conditional depth also constrains moves.
Click(Button("Say")); Move("X", "Y")
assert(ns.DB.menu.Y.variants.GROUP.A.A.text == "Moved group greeting")
assert(ns.DB.menu.Y.variants.RAID.A.A.text == "Thanks for the raid!")
Undo()

-- Changing membership during an open selection keeps its path stable, but
-- losing the destination never makes a private message public.
Group("PARTY"); Pad("LeftButton"); Pad("X"); Group()
previous = sent; Pad("A"); Pad("A"); assert(sent == previous)

local legacy = { A = { text = "Old emote", chat = "EMOTE" }, X = { text = "Party", chat = "PARTY" },
	Y = { variants = { RAID = { text = "BG", chat = "INSTANCE_CHAT" } } } }
ns.MigrateMenu(legacy)
assert(legacy.A.chat == "SAY" and legacy.X.chat == "GROUP" and legacy.Y.variants.RAID.chat == "RAID")

-- Replace Social with a one-press message in Group while keeping a nested
-- Raid mapping. All three shapes must remain usable in combat.
Select("X"); Click(Button("Group")); Click(Button("Remove")); Click(Button("Remove group"))
assert(ns.DB.menu.X.variants.GROUP == false)
Click(Button("+ Message")); Type(Field(-94), "Thanks for the group"); Type(Field(-154), "Thanks for the group!")
assert(ns.DB.menu.X.A.A.text == "Hello")
combat = true
Group(); Pad("LeftButton"); Pad("X"); assert(PADChatOpen:GetAttribute("path") == "X")
Pad("A"); Pad("A"); assert(sent[1] == "Hello")
Group("PARTY"); Pad("LeftButton"); Pad("X")
assert(not PADChatOpen:GetAttribute("open") and sent[1] == "Thanks for the group!" and sent[2] == "PARTY")
combat = false; Group(nil, "RAID", "pvp"); combat = true
Pad("LeftButton"); Pad("X"); assert(PADChatOpen:GetAttribute("path") == "X")
Pad("A"); Pad("A"); assert(sent[1] == "Thanks for the raid!" and sent[2] == "INSTANCE_CHAT")
combat = false; Group(); Event("PLAYER_REGEN_ENABLED")

-- Default deletion keeps explicit variants, and default moves account for
-- the depth of variant subtrees even when the default option is a leaf.
Click(Button("Say")); Select("X"); Click(Button("Remove")); Click(Button("Remove group"))
assert(ns.DB.menu.X.empty and ns.ResolveNode(ns.GetMenu(), "GROUP").X.text == "Thanks for the group!")
Click(Button("+ Message")); assert(ns.DB.menu.X.text == "Hello!" and ns.DB.menu.X.variants.RAID.A.A.text == "Thanks for the raid!")
Expand("Y"); Select("YA"); Click(Button("Remove")); Click(Button("+ Group")); Select("YAA"); Click(Button("+ Group"))
Select("X"); Click(Button("Move / swap..."))
for _, obj in ipairs(objects) do
	if obj:IsVisible() and obj.description then assert(obj.path ~= "YAAA", "A variant subtree must not exceed four presses") end
end
Click(Button("Cancel")); Undo(); Undo(); Undo(); Undo(); Undo()
assert(ns.DB.menu.X.A.A.text == "Hello")

-- Long labels and conditional controls keep the preview inside the right
-- viewport. The preview is only scaled when its wrapped content needs it.
Select("XAA"); Type(Field(-94), string.rep("Long ", 8)); Click(Button("Say"))
local details = Find(function(o) return o.kind == "ScrollFrame" and o.point[2] == 368 end)
assert(details.maximum == 0, "The HUD preview must fit without scrolling")
local scaledPreview = Find(function(o) return o.kind == "Frame" and o.Display ~= nil and o.parent.parent == details.content end)
assert(scaledPreview.scale <= 1 and scaledPreview.parent:GetHeight() <= details:GetHeight() - 258)
Undo()

-- The largest editable tree stays on screen, scrolls to every leaf, and
-- discards old rows when switching to a smaller or empty branch.
local function FullTree(depth)
	if depth == 0 then return { text = "Test", label = "Test" } end
	local node = {}
	for _, key in ipairs(ns.CHOICES) do node[key] = FullTree(depth - 1) end
	return node
end
local view = ns.CreateMenuView(UIParent)
view:Display(FullTree(ns.MAX_DEPTH), "Quick Chat")
assert(#LeafLabels(view) == 81 and view:GetHeight() < UIParent:GetHeight())
local list = Find(function(o) return o.kind == "ScrollFrame" and o.parent == view end)
assert(list.maximum > 0)
list.scripts.OnMouseWheel(list, -1000); assert(list.offset == list.maximum)
list.scripts.OnMouseWheel(list, 1000); assert(list.offset == 0)
view:Display({ A = { text = "Fallback", label = "" } }, "Quick Chat", "XX")
assert(table.concat(LeafLabels(view), ",") == "XXA - Fallback" and list.maximum == 0)
view:Display({}, "Empty"); assert(#LeafLabels(view) == 0)
view:Hide()

-- A new profile and Reset both install distinct Group/Battleground defaults.
ns.DefaultMenu = shippedDefaults
PADChatDB = nil; Event("ADDON_LOADED", "PADChat")
ns.MenuChanged()
assert(ns.DB.version == 7 and ns.savedLoaded == false)
assert(ns.ResolveNode(ns.GetMenu(), "GROUP").X.A.A.emote == "OOM")
Group("PARTY"); combat = true
Pad("LeftButton"); Pad("X"); Pad("A")
assert(LeafLabels(PADChatMenu)[1] == "XAA - Need mana")
Pad("A"); assert(sent[1] == "Need mana." and sent[2] == "PARTY" and emotes[#emotes] == "OOM"); Released()
local voiceCount = #emotes
Pad("LeftButton"); Pad("X"); Pad("A"); Pad("Y")
assert(sent[1] == "Wait up!" and #emotes == voiceCount)

-- The shipped Wave option is emote-only: it waves without touching chat, even
-- with no channel. Goodbye says its line and waves.
Group()
Pad("LeftButton"); Pad("X"); Pad("A")
assert(table.concat(LeafLabels(PADChatMenu), ",") == "XAA - Hello,XAX - Goodbye,XAY - Wave")
local previousSend = sent
Pad("Y")
assert(#emotes == voiceCount + 1 and emotes[#emotes] == "WAVE" and sent == previousSend)
assert(not PADChatMenu:IsShown() and ns.ResolveNode(ns.GetMenu(), "DEFAULT").X.A.Y.text == nil)
Pad("LeftButton"); Pad("X"); Pad("A"); Pad("X")
assert(sent[1] == "Farewell" and sent[2] == "SAY" and emotes[#emotes] == "WAVE")
assert(not ns.IsAvailable({ text = "hi" }, "GROUP") and ns.IsAvailable({ emote = "WAVE" }, "GROUP"))
combat = false

-- The emote picker sets a token, clears it, and accepts a typed one; each
-- change is undoable.
voiceCount = #emotes
Click(Button("Group")); Select("XAA"); Click(Button("Emote: Out of mana"))
Click(Button("No emote")); assert(ns.DB.menu.X.variants.GROUP.A.A.emote == nil)
Group("PARTY"); Click(Button("Send now"))
assert(sent[1] == "Need mana." and sent[2] == "PARTY" and #emotes == voiceCount)
Type(Field(-394), "wave"); assert(ns.DB.menu.X.variants.GROUP.A.A.emote == "WAVE")
assert(Button("Emote: Wave"))
Select("XAA"); assert(not emotePanelShown())
Undo(); assert(ns.DB.menu.X.variants.GROUP.A.A.emote == nil)
Undo(); assert(ns.DB.menu.X.variants.GROUP.A.A.emote == "OOM")
ns.ResetToDefaults(); assert(ns.DB.menu.X.variants.GROUP.A.A.emote == "OOM")

-- AB objective names affect labels and sends, even while the menu is open in
-- combat; the secure paths stay unchanged and other BGs use generic calls.
Group(nil, "RAID", "pvp"); subzone = "Blacksmith"; combat = true
Pad("LeftButton")
assert(table.concat(LeafLabels(PADChatMenu), ","):find("AA - 2-3 inc BS,AX - 4-6 inc BS,AY - Big INC BS!", 1, true))
Pad("A"); Pad("X"); assert(sent[1] == "4-6 inc BS" and sent[2] == "INSTANCE_CHAT")
Pad("LeftButton"); Pad("A"); Pad("A"); assert(sent[1] == "2-3 inc BS")
Pad("LeftButton"); Pad("A"); Pad("Y"); assert(sent[1] == "Big INC BS!")
Pad("LeftButton"); Pad("A"); subzone = "Lumber Mill"; Event("ZONE_CHANGED")
assert(PADChatOpen:GetAttribute("path") == "A" and LeafLabels(PADChatMenu)[1] == "AA - 2-3 inc LM")
Pad("A"); assert(sent[1] == "2-3 inc LM")
for zone, abbreviation in pairs({ ["Gold Mine"] = "GM", Stables = "ST", Farm = "Farm" }) do
	subzone = zone; assert(ns.FormatMessage("Defend {location}!", "RAID") == "Defend " .. abbreviation .. "!")
end
subzone = "Unknown"; assert(ns.FormatMessage("2-3 inc {location}", "RAID") == "2-3 inc here")
instanceID = 489; subzone = "Blacksmith"
assert(ns.FormatMessage("2-3 inc {location}", "RAID") == "2-3 inc here")
instanceID = 529
combat = false; Click(Button("Compact: Off"))
Pad("LeftButton"); Pad("A")
assert(Find(function(o) return o.kind == "Text" and o.parent.parent == PADChatMenu and o.text == "2-3 inc BS" end))
Pad("B"); Click(Button("Compact: On"))
Group(); voiceCount = #emotes
ns.SendNode({ text = "Need mana.", emote = "OOM" }, "GROUP")
assert(#emotes == voiceCount, "Unavailable chat must not play an emote")
local originalSend = SendChatMessage
SendChatMessage = function() error("send failed") end
Group("PARTY"); ns.SendNode({ text = "Need mana.", emote = "OOM" }, "GROUP")
assert(#emotes == voiceCount, "A failed send must not play an emote")
SendChatMessage = originalSend

-- Upgrades keep custom options and explicit disabled slots; stock branches
-- gain the new defaults once without sharing the shipped tables.
local legacyMenu = ns.CopyMenu(shippedDefaults)
for _, key in ipairs(ns.CHOICES) do legacyMenu[key].variants = nil end
legacyMenu.X.variants = { GROUP = { label = "My group", A = { label = "Custom", text = "Custom!" } }, RAID = false }
legacyMenu.Y.A.text = "My help"
PADChatDB = { menu = legacyMenu, compact = true, version = 2 }; Event("ADDON_LOADED", "PADChat")
assert(ns.DB.version == 7 and ns.DB.compact)
assert(ns.DB.menu.X.variants.GROUP.A.text == "Custom!" and ns.DB.menu.X.variants.RAID == false)
assert(ns.DB.menu.Y.A.text == "My help" and ns.DB.menu.Y.variants == nil)
assert(ns.DB.menu.A.variants.RAID.A.text == "2-3 inc {location}")
ns.DB.menu.A.variants.RAID.A.text = "Edited incoming"
Event("ADDON_LOADED", "PADChat"); assert(ns.DB.menu.A.variants.RAID.A.text == "Edited incoming")
assert(shippedDefaults.A.variants.RAID.A.text == "2-3 inc {location}")

-- First-release Greet options (Wave was "/e waves.", later demoted to Say)
-- become the shipped ones; an edited greeting stays.
local oldGreet = ns.CopyMenu(shippedDefaults)
oldGreet.X.A.A = { label = "Hello", text = "Well met!", chat = "SAY" }
oldGreet.X.A.X = { label = "Goodbye", text = "See ya!", chat = "SAY" }
oldGreet.X.A.Y = { label = "Wave", text = "waves.", chat = "SAY" }
PADChatDB = { menu = oldGreet, compact = false, version = 4 }; Event("ADDON_LOADED", "PADChat")
assert(ns.DB.version == 7 and ns.DB.menu.X.A.A.text == "Hello" and ns.DB.menu.X.A.X.text == "See ya!")
assert(ns.DB.menu.X.A.Y.text == nil and ns.DB.menu.X.A.Y.emote == "WAVE" and ns.DB.menu.X.A.Y ~= shippedDefaults.X.A.Y)

-- Wave can't reach a whisper target, so the Whisper tab swaps it for a thank
-- you. Saves from before the Whisper tab gain it unless Wave was edited.
local preWhisper = ns.CopyMenu(shippedDefaults)
preWhisper.X.A.X.variants, preWhisper.X.A.Y.variants = nil, nil
PADChatDB = { menu = preWhisper, compact = false, version = 5 }; Event("ADDON_LOADED", "PADChat")
assert(ns.DB.version == 7 and ns.DB.menu.X.A.Y.variants.WHISPER.text == "Thanks for the group!")
assert(ns.DB.menu.X.A.X.variants.WHISPER.text == "Farewell" and ns.DB.menu.X.A.X.variants.WHISPER.emote == nil)
assert(ns.DB.menu.X.A.Y.variants ~= shippedDefaults.X.A.Y.variants)
local editedWave = ns.CopyMenu(shippedDefaults)
editedWave.X.A.X = { label = "Goodbye", text = "Later!", emote = "WAVE" }
editedWave.X.A.Y = { label = "Bow", emote = "BOW" }
PADChatDB = { menu = editedWave, compact = false, version = 5 }; Event("ADDON_LOADED", "PADChat")
assert(ns.DB.menu.X.A.X.variants == nil and ns.DB.menu.X.A.Y.variants == nil)
ns.ResetToDefaults(); ns.DB.compact = false
assert(ns.ResolveNode(ns.GetMenu(), "DEFAULT").X.A.Y.emote == "WAVE")
assert(ns.ResolveNode(ns.GetMenu(), "WHISPER").X.A.Y.text == "Thanks for the group!")
assert(ns.ResolveNode(ns.GetMenu(), "WHISPER").X.A.A.text == "Hello", "Whisper inherits Say, not Group")
Group("PARTY"); allies = { Ally("Erin", true, 1) }; combat = true
Pad("LeftButton"); Pad("LB"); Pad("LB"); Pad("X"); Pad("A")
assert(table.concat(LeafLabels(PADChatMenu), ",") == "XAA - Hello,XAX - Goodbye,XAY - Thanks for the group")
local emotesBefore = #emotes
Pad("Y"); assert(sent[1] == "Thanks for the group!" and sent[2] == "WHISPER" and sent[3] == "Erin" and #emotes == emotesBefore)
Released()
Pad("LeftButton"); Pad("LB"); Pad("LB"); Pad("X"); Pad("A"); Pad("X")
assert(sent[1] == "Farewell" and sent[2] == "WHISPER" and #emotes == emotesBefore, "Whisper Goodbye doesn't wave")
Released()
Pad("LeftButton"); Pad("LB"); Pad("X"); Pad("A"); Pad("X")
assert(sent[1] == "Farewell" and sent[2] == "SAY" and emotes[#emotes] == "WAVE", "Say Goodbye still waves")
Released(); combat = false; Group()
Click(Button("Whisper")); Select("XAY")
assert(Button("Send now").enabled == false, "The editor has no whisper target to send to")
Click(Button("Say"))

-- Warsong has fixed CTF calls, independent of subzone names. Both HUD modes
-- and secure sends use the Warsong profile, including manual tab switching.
ns.ResetToDefaults(); ns.DB.compact = false
instanceID = 489; subzone = "Blacksmith"; Group(nil, "RAID", "pvp")
local readsBeforeWarsong = subzoneReads
combat = true; Pad("LeftButton")
assert(PADChatOpen:GetAttribute("menucontext") == "RAID" and PADChatOpen:GetAttribute("menuprofile") == "WSG")
assert(table.concat(LeafLabels(PADChatMenu), ",") == "AA - Flag going ramp,AX - Flag going tunnel,AY - Flag going graveyard,XA - Escort our carrier,XX - Intercept enemy carrier,XY - Return our flag,YA - Regroup,YX - Need healing,YY - Need mana")
Pad("LB"); assert(PADChatOpen:GetAttribute("menucontext") == "GROUP")
Pad("RB"); assert(LeafLabels(PADChatMenu)[1] == "AA - Flag going ramp")
Pad("B"); Released()
for _, call in ipairs({
	{ "AA", "Flag going ramp!" }, { "AX", "Flag going tunnel!" },
	{ "AY", "Flag going graveyard!" }, { "XA", "Escort our flag carrier!" },
	{ "XX", "Intercept the enemy flag carrier!" }, { "XY", "Return our flag!" },
}) do
	Pad("LeftButton")
	for key in call[1]:gmatch(".") do Pad(key) end
	assert(sent[1] == call[2] and sent[2] == "INSTANCE_CHAT"); Released()
end
assert(subzoneReads == readsBeforeWarsong, "Warsong calls must not read the player's subzone")
combat = false; Event("PLAYER_ENTERING_WORLD"); Click(Button("Compact: Off"))
Pad("LeftButton")
assert(Find(function(o) return o.kind == "Text" and o.parent.parent == PADChatMenu and o.text == "Flag route" end))
Pad("A")
assert(Find(function(o) return o.kind == "Text" and o.parent.parent == PADChatMenu and o.text == "Flag going tunnel" end))
Pad("X"); assert(sent[1] == "Flag going tunnel!")
Click(Button("Compact: On"))

-- Editing Warsong preserves AB, undo, and open-menu snapshots. Its separately
-- published shape also allows editing the layout without breaking combat input.
Click(Button("Battleground")); Select("A")
if not Find(function(o) return o.path == "AA" and o.selection ~= nil end, true) then Expand("A") end
Select("AA"); Pad("LeftButton"); Pad("A")
Type(Field(-154), "Flag moving ramp!"); assert(ns.IsPublishPending())
Pad("A"); assert(sent[1] == "Flag going ramp!")
Pad("LeftButton"); Pad("A"); Pad("A"); assert(sent[1] == "Flag moving ramp!")
assert(ns.DB.menu.A.variants.RAID.A.text == "2-3 inc {location}")
Undo(); Select("AX"); Click(Button("Remove")); Click(Button("+ Group"))
Select("AXA"); Click(Button("+ Message"))
assert(PADChatOpen:GetAttribute("node-WSG-AX") == "branch" and PADChatOpen:GetAttribute("node-RAID-AX") == "leaf")
combat = true; Pad("LeftButton"); Pad("A"); Pad("X")
assert(PADChatOpen:GetAttribute("open") and PADChatOpen:GetAttribute("path") == "AX")
Pad("A"); assert(sent[1] == "Hello!" and sent[2] == "INSTANCE_CHAT"); Released()
combat = false; Undo(); Undo(); Undo()
instanceID = 529; Event("ZONE_CHANGED_NEW_AREA")
Pad("LeftButton"); Pad("A"); Pad("A"); assert(sent[1] == "2-3 inc BS")
instanceID = 30; Event("ZONE_CHANGED_NEW_AREA")
Pad("LeftButton"); Pad("A"); Pad("A"); assert(sent[1] == "2-3 inc here")

-- Version-three profiles gain Warsong only on stock BG branches; customized
-- messages and intentionally restored inheritance survive the version upgrade.
local versionThree = ns.CopyMenu(shippedDefaults)
versionThree.A.variants.RAID.battlegrounds = nil
versionThree.X.variants.RAID.battlegrounds = nil
versionThree.X.variants.RAID.A.text = "Custom defense."
versionThree.Y.variants.GROUP = nil
PADChatDB = { menu = versionThree, compact = false, version = 3 }
Event("ADDON_LOADED", "PADChat")
assert(ns.DB.version == 7 and ns.DB.menu.A.variants.RAID.battlegrounds[489].A.text == "Flag going ramp!")
assert(ns.DB.menu.X.variants.RAID.A.text == "Custom defense." and ns.DB.menu.X.variants.RAID.battlegrounds == nil)
assert(ns.DB.menu.Y.variants.GROUP == nil)
ns.DB.menu.A.variants.RAID.battlegrounds[489].A.text = "Custom flag call!"
ns.DB.version = 3; Event("ADDON_LOADED", "PADChat")
assert(ns.DB.menu.A.variants.RAID.battlegrounds[489].A.text == "Custom flag call!")
assert(shippedDefaults.A.variants.RAID.battlegrounds[489].A.text == "Flag going ramp!")

assert(next(SlashCmdList) == nil, "slash commands taint Forever's gamepad UI")

-- The minimap button toggles the editor; dragging slides it round the map
-- edge and saves the angle.
local minimapButton = PADChatMinimapButton
assert(minimapButton.parent == Minimap and minimapButton.point[2] == Minimap)
local wasShown = PADChatEditor:IsShown()
minimapButton.scripts.OnClick(minimapButton); assert(PADChatEditor:IsShown() ~= wasShown)
minimapButton.scripts.OnClick(minimapButton); assert(PADChatEditor:IsShown() == wasShown)
minimapButton.scripts.OnDragStart(minimapButton)
cursorX, cursorY = 800, 500; minimapButton.scripts.OnUpdate(minimapButton)
minimapButton.scripts.OnDragStop(minimapButton)
assert(ns.DB.minimapAngle == 90 and minimapButton.scripts.OnUpdate == nil)
assert(math.abs(minimapButton.point[4]) < 1e-9 and minimapButton.point[5] == 104)

print("Editor checks passed: no slash commands, minimap button, Warsong CTF calls and editing, AB objectives, BG migrations, mana voice, smart tabs, binding cleanup, scrolling, inheritance, undo, and combat snapshots.")
