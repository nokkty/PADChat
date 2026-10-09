-- A gamepad button on the edge of the minimap that opens the editor, the same
-- as the PADEdit macro. Drag it to slide it around the map's edge;
-- the angle is saved in PADChatDB.minimapAngle.
-- Parented to the minimap, so moving or scaling the map takes it along.
local _, ns = ...
local DEFAULT_ANGLE = 200 -- degrees counterclockwise from the right: left, a little low
local ICON = "Interface\\AddOns\\PADChat\\Media\\Gamepad"

local minimap = _G.Minimap
if not minimap then return end

local button = CreateFrame("Button", "PADChatMinimapButton", minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM"); button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("LeftButton")

local back = button:CreateTexture(nil, "BACKGROUND")
back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
back:SetSize(24, 24); back:SetPoint("CENTER")
local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON)
icon:SetSize(20, 20); icon:SetPoint("CENTER")
local ring = button:CreateTexture(nil, "OVERLAY")
ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
ring:SetSize(50, 50); ring:SetPoint("TOPLEFT")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function Angle() return ns.DB and tonumber(ns.DB.minimapAngle) or DEFAULT_ANGLE end
local function Place()
	local angle, radius = math.rad(Angle()), minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end
ns.PlaceMinimapButton = Place

-- The pointer arrives in screen units; the map has a scale of its own.
local function FollowCursor()
	local cx, cy = minimap:GetCenter()
	if not (cx and ns.DB) then return end
	local scale = minimap:GetEffectiveScale()
	local x, y = GetCursorPosition()
	ns.DB.minimapAngle = math.floor(math.deg((math.atan2 or math.atan)(y / scale - cy, x / scale - cx)) % 360 + 0.5)
	Place()
end
local function StopDrag(self)
	self.dragging = nil
	self:SetScript("OnUpdate", nil)
	icon:SetPoint("CENTER", 0, 0)
end

button:SetScript("OnClick", function() ns.ToggleEditor() end)
button:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, -1) end)
button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 0) end)
button:SetScript("OnDragStart", function(self)
	self.dragging = true; GameTooltip:Hide()
	self:SetScript("OnUpdate", FollowCursor)
end)
button:SetScript("OnDragStop", StopDrag)
button:SetScript("OnHide", StopDrag)
button:SetScript("OnEnter", function(self)
	if self.dragging then return end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("PAD Chat")
	GameTooltip:AddLine("Click to open or close the editor.", 1, 1, 1)
	GameTooltip:AddLine("Drag to move this button.", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- PADChat.lua loads the saved angle on ADDON_LOADED; place again once it has.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", Place)
Place()
