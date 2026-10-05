-- Run from the addon directory: lua tests/editor.lua
-- Exercises the real editor callbacks and secure snippet with a small WoW API stub.
local objects, combat, secure = {}, false, false
local homeGroup, instanceGroup = "SOLO", "SOLO"
local instanceType = "none"
local instanceID, subzone = 529, ""
function IsInInstance() return instanceType ~= "none", instanceType end
function GetInstanceInfo() return "Arathi Basin", instanceType, 0, "", 0, 0, false, instanceID end
function GetSubZoneText() return subzone end
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
local function Object(kind, name, parent, template)
	local obj = setmetatable({ kind = kind, parent = parent, template = template, shown = true,
		attributes = {}, scripts = {}, hooks = {}, events = {}, text = "", width = 0, height = 0 }, { __index = methods })
	objects[#objects + 1] = obj
	if name then _G[name] = obj end
	return obj
end
for _, method in ipairs({ "SetFrameStrata", "SetToplevel", "SetMovable", "SetClampedToScreen", "EnableMouse",
	"EnableMouseWheel", "EnableKeyboard", "RegisterForDrag", "RegisterForClicks", "SetAllPoints", "SetTextColor", "SetAlpha",
	"SetJustifyH", "SetColorTexture", "SetTexture", "AddMaskTexture", "SetFontObject", "SetTextInsets",
	"SetAutoFocus", "SetMaxLetters", "SetScale", "SetScrollChild", "SetVerticalScroll", "StartMoving", "StopMovingOrSizing" }) do
	methods[method] = function() end
end
function methods:CreateTexture() return Object("Texture", nil, self) end
function methods:CreateMaskTexture() return Object("Mask", nil, self) end
function methods:CreateFontString(_, _, font) return Object("Text", nil, self, font) end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetScale(value) self.scale = value end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetParent() return self.parent end
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
function methods:SetBindingClick(priority, key, target, button)
	assert(secure and priority and target == "VGSChatOpen")
	self.bindings = self.bindings or {}; self.bindings[key] = button; self.bound = true
end
function CreateFrame(...) return Object(...) end
UIParent = Object("Frame"); UIParent:SetSize(960, 540)
function InCombatLockdown() return combat end
function RegisterStateDriver(frame, state, driver)
	assert(not combat and state == "context" and (driver == "[group] GROUP; DEFAULT" or driver == "RAID"))
	frame.driver = driver
	frame:SetAttribute("state-context", driver == "RAID" and "RAID" or IsInGroup() and "GROUP" or "DEFAULT")
end
function wipe(t) for key in pairs(t) do t[key] = nil end end
C_Timer = { After = function(_, fn) fn() end }
local sent
local emotes = {}
function DoEmote(token) emotes[#emotes + 1] = token end
function SendChatMessage(text, channel) sent = { text, channel } end
local ns = {}
assert(loadfile("Messages.lua"))("VGSChat", ns)
assert(loadfile("VGSChat.lua"))("VGSChat", ns)
local shippedDefaults = ns.CopyMenu(ns.DefaultMenu)
-- Exercise the existing editor and inheritance against a pre-upgrade menu;
-- the new shipped defaults and upgrade are checked separately below.
for _, key in ipairs(ns.CHOICES) do ns.DefaultMenu[key].variants = nil end
for _, frame in ipairs(objects) do
	if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "VGSChat") end
end
assert(loadfile("Editor.lua"))("VGSChat", ns)
VGSChatEditor:Show()
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
local function Type(box, text) box.text = text; box.scripts.OnTextChanged(box, true) end
local function Move(from, to)
	Select(from); Click(Button("Move / swap..."))
	Click(Find(function(o) return o.path == to and o.description ~= nil end))
	local node = ns.GetMenu()
	for key in to:gmatch(".") do node = node and node[key] end
	Click(Button(node and "Swap options" or "Move option"))
end
local function Pad(button)
	secure = true
	local env = { self = VGSChatOpen, button = button }
	local snippet = VGSChatOpen.attributes._onclick
	local chunk = loadstring and setfenv(assert(loadstring(snippet, "secure click")), env)
		or assert(load(snippet, "secure click", "t", env))
	chunk()
	secure = false
	for _, fn in ipairs(VGSChatOpen.hooks.OnClick) do fn(VGSChatOpen) end
end
local function Event(event, arg)
	for _, frame in ipairs(objects) do if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, arg) end end
end
local function Group(home, instance, kind)
	homeGroup, instanceGroup = home or "SOLO", instance or "SOLO"
	instanceType = kind or "none"
	-- Emulate the native secure state driver (including in combat).
	secure = true
	VGSChatOpen:SetAttribute("state-context", VGSChatOpen.driver == "RAID" and "RAID" or IsInGroup() and "GROUP" or "DEFAULT")
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
local labels = LeafLabels(VGSChatMenu)
assert(table.concat(labels, ",") == "AA - Yes,AX - No,AY - Thanks,XAA - Hello,XAX - Goodbye,XAY - Wave,XXA - Invite please!,XXX - Want to group?,XXY - Inviting you,YA - Help!,YX - Incoming!,YY - Follow me")
local expandedHeight = VGSChatMenu:GetHeight()
Click(Button("Compact: Off"))
assert(ns.DB.compact and VGSChatMenu:GetHeight() < expandedHeight and #LeafLabels(VGSChatMenu) == 0)
assert(Find(function(o) return o.kind == "Text" and o.parent.parent == VGSChatMenu and o.text == "Respond" end))
Event("ADDON_LOADED", "VGSChat"); assert(ns.DB.compact, "Loading saved settings must preserve Compact")
combat = true
Click(Button("Compact: On")); Pad("X"); Pad("A")
assert(table.concat(LeafLabels(VGSChatMenu), ",") == "XAA - Hello,XAX - Goodbye,XAY - Wave")
Click(Button("Compact: Off")); assert(VGSChatOpen:GetAttribute("path") == "XA")
Pad("A"); assert(sent[1] == "Well met!" and not VGSChatMenu:IsShown())
combat = false; Click(Button("Compact: On"))

-- Shoulder overrides cover modifier keys, wrap tabs, reset a partial sequence,
-- and release on send, cancel, and macro toggle. Closed menus ignore shoulders.
local function Released()
	assert(not VGSChatOpen.bound and next(VGSChatOpen.bindings) == nil and not VGSChatMenu:IsShown())
end
Pad("RB"); Released()
Pad("LeftButton")
assert(VGSChatOpen:GetAttribute("menucontext") == "DEFAULT")
assert(VGSChatOpen.bindings.PADLSHOULDER == "LB" and VGSChatOpen.bindings.PADRSHOULDER == "RB")
assert(VGSChatOpen.bindings["CTRL-PAD1"] == "A" and VGSChatOpen.bindings["ALT-CTRL-SHIFT-PADRSHOULDER"] == "RB")
Pad("X"); Pad("A"); Pad("RB")
assert(VGSChatOpen:GetAttribute("menucontext") == "GROUP" and VGSChatOpen:GetAttribute("path") == "")
Pad("RB"); assert(VGSChatOpen:GetAttribute("menucontext") == "RAID")
Pad("RB"); assert(VGSChatOpen:GetAttribute("menucontext") == "DEFAULT")
Pad("LB"); assert(VGSChatOpen:GetAttribute("menucontext") == "RAID")
Pad("LB"); assert(VGSChatOpen:GetAttribute("menucontext") == "GROUP")
Pad("LB"); assert(VGSChatOpen:GetAttribute("menucontext") == "DEFAULT")
Pad("B"); Released()
Pad("LeftButton"); Pad("LeftButton"); Released()

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
	Pad("LeftButton"); assert(VGSChatOpen:GetAttribute("menucontext") == scenario[4])
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
Pad("LeftButton"); assert(VGSChatOpen:GetAttribute("menucontext") == "GROUP")
Pad("RB"); Pad("A"); Pad("A"); assert(sent[2] == "INSTANCE_CHAT"); Released()
combat = false; Event("PLAYER_REGEN_ENABLED")
Pad("LeftButton"); assert(VGSChatOpen:GetAttribute("menucontext") == "RAID")
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
assert(ns.DB.menu.A.text == "Well met!" and ns.DB.menu.X.A.A.A.text == "Yes!", "Swap must preserve both subtrees")
Undo(); assert(ns.DB.menu.A.A.text == "Yes!" and ns.DB.menu.X.A.A.text == "Well met!")

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
Undo(); Undo(); Undo(); assert(ns.DB.menu.X.A.A.text == "Well met!")

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
assert(LeafLabels(VGSChatMenu)[1] == "XAA - Thanks for the group")
Pad("A")
assert(sent[1] == "Thanks for the group!" and sent[2] == "PARTY")
Pad("LeftButton"); Pad("LB"); Pad("X"); Pad("A")
assert(LeafLabels(VGSChatMenu)[1] == "XAA - Hello", "Switching to Say must restore its own mapping")
Pad("A"); assert(sent[1] == "Well met!" and sent[2] == "SAY")
Group("RAID"); Pad("LeftButton"); Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Thanks for the group!" and sent[2] == "RAID", "Raid inherits the broad Group override")
Group(); Pad("LeftButton"); Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Well met!" and sent[2] == "SAY")
combat = false; Event("PLAYER_REGEN_ENABLED")

-- More specific overrides, undo, and restoration of inheritance.
Select("X"); Click(Button("Battleground")); Click(Button("Customize option"))
Select("XAA"); Type(Field(-154), "Thanks for the raid!")
Group(nil, "RAID", "pvp"); Pad("LeftButton"); Pad("X"); Pad("A"); Pad("A")
assert(sent[1] == "Thanks for the raid!" and sent[2] == "INSTANCE_CHAT")
Pad("LeftButton"); Pad("LB"); Pad("X"); Pad("A")
assert(LeafLabels(VGSChatMenu)[1] == "XAA - Thanks for the group", "Switching from Battleground must restore Group's mapping")
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
assert(ns.DB.menu.X.A.A.text == "Well met!")
combat = true
Group(); Pad("LeftButton"); Pad("X"); assert(VGSChatOpen:GetAttribute("path") == "X")
Pad("A"); Pad("A"); assert(sent[1] == "Well met!")
Group("PARTY"); Pad("LeftButton"); Pad("X")
assert(not VGSChatOpen:GetAttribute("open") and sent[1] == "Thanks for the group!" and sent[2] == "PARTY")
combat = false; Group(nil, "RAID", "pvp"); combat = true
Pad("LeftButton"); Pad("X"); assert(VGSChatOpen:GetAttribute("path") == "X")
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
assert(ns.DB.menu.X.A.A.text == "Well met!")

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
VGSChatDB = nil; Event("ADDON_LOADED", "VGSChat")
ns.MenuChanged()
assert(ns.DB.version == 3 and ns.savedLoaded == false)
assert(ns.ResolveNode(ns.GetMenu(), "GROUP").X.A.A.emote == "OOM")
Group("PARTY"); combat = true
Pad("LeftButton"); Pad("X"); Pad("A")
assert(LeafLabels(VGSChatMenu)[1] == "XAA - Need mana")
Pad("A"); assert(sent[1] == "Need mana." and sent[2] == "PARTY" and emotes[#emotes] == "OOM"); Released()
local voiceCount = #emotes
Pad("LeftButton"); Pad("X"); Pad("A"); Pad("Y")
assert(sent[1] == "Wait up!" and #emotes == voiceCount)
combat = false
Click(Button("Group")); Select("XAA"); Click(Button("Mana voice: On"))
assert(ns.DB.menu.X.variants.GROUP.A.A.emote == nil)
Click(Button("Send now")); assert(#emotes == voiceCount)
Undo(); assert(ns.DB.menu.X.variants.GROUP.A.A.emote == "OOM")
ns.ResetToDefaults(); assert(ns.DB.menu.X.variants.GROUP.A.A.emote == "OOM")

-- AB objective names affect labels and sends, even while the menu is open in
-- combat; the secure paths stay unchanged and other BGs use generic calls.
Group(nil, "RAID", "pvp"); subzone = "Blacksmith"; combat = true
Pad("LeftButton")
assert(table.concat(LeafLabels(VGSChatMenu), ","):find("AA - 2-3 inc BS,AX - 4-6 inc BS,AY - Big INC BS!", 1, true))
Pad("A"); Pad("X"); assert(sent[1] == "4-6 inc BS" and sent[2] == "INSTANCE_CHAT")
Pad("LeftButton"); Pad("A"); Pad("A"); assert(sent[1] == "2-3 inc BS")
Pad("LeftButton"); Pad("A"); Pad("Y"); assert(sent[1] == "Big INC BS!")
Pad("LeftButton"); Pad("A"); subzone = "Lumber Mill"; Event("ZONE_CHANGED")
assert(VGSChatOpen:GetAttribute("path") == "A" and LeafLabels(VGSChatMenu)[1] == "AA - 2-3 inc LM")
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
assert(Find(function(o) return o.kind == "Text" and o.parent.parent == VGSChatMenu and o.text == "2-3 inc BS" end))
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
VGSChatDB = { menu = legacyMenu, compact = true, version = 2 }; Event("ADDON_LOADED", "VGSChat")
assert(ns.DB.version == 3 and ns.DB.compact)
assert(ns.DB.menu.X.variants.GROUP.A.text == "Custom!" and ns.DB.menu.X.variants.RAID == false)
assert(ns.DB.menu.Y.A.text == "My help" and ns.DB.menu.Y.variants == nil)
assert(ns.DB.menu.A.variants.RAID.A.text == "2-3 inc {location}")
ns.DB.menu.A.variants.RAID.A.text = "Edited incoming"
Event("ADDON_LOADED", "VGSChat"); assert(ns.DB.menu.A.variants.RAID.A.text == "Edited incoming")
assert(shippedDefaults.A.variants.RAID.A.text == "2-3 inc {location}")

print("Editor checks passed: group/BG defaults, mana voice, live AB objectives, migration, smart tabs, binding cleanup, scrolling, editing, inheritance, undo, and combat snapshots.")
