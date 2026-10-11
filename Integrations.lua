-- Integrations with Blizzard's own windows, each switched on in the editor's
-- Settings. Both let Y open quick chat on the Whisper tab with a player picked.
--
-- Enhance LFG Window: the leader of the group or player selected in the
-- Looking For Group window (Blizzard_GroupFinder_VanillaStyle's LFGBrowseFrame).
-- A Y prompt sits beside Blizzard's Send Message button. Send Message itself
-- opens the chat edit box, which taints Forever's gamepad UI, so this never
-- calls it. The same setting covers the window's Who tab (LFGWhoListFrame):
-- the player whose row (or its invite button) the cursor is on, with a Y glyph
-- on that row. Who rows only show a tooltip when their text is cut off, so the
-- glyph stands in for one.
--
-- Enhance Recent Allies Window: the online ally whose card the cursor is on
-- (smart navigation runs the card's enter/leave scripts, which show and hide
-- its tooltip). The card's tooltip gains a Y line at the bottom.
--
-- Smart navigation owns the D-pad, A and B in these windows; Y is free.
-- Override bindings can't change in combat, so Y is released as combat starts
-- (PLAYER_REGEN_DISABLED still allows it) and restored when combat ends.

local _, ns = ...

local Y_KEY = "PAD4" -- Y / Triangle
local owner = CreateFrame("Frame")
local lfgHint, lfgHooked, alliesHooked, focusedAlly, bound
local whoHint, whoHooked, focusedWho

-- The controller's own glyph for Y (Triangle on PlayStation pads), when the
-- client offers it.
local function YAtlas()
	local util = InputIconTextureSetUtility
	local ok, atlas = pcall(function() return util and util.GetNormalActiveInputIconButtonTexture(Y_KEY) end)
	return ok and atlas or nil
end

------------------------------------------------------------------------
-- Looking For Group
------------------------------------------------------------------------
-- The leader of the selected listing, read the way Send Message reads it.
function ns.LFGSelectedLeader()
	local browse = LFGBrowseFrame
	local selection = browse and browse.selectionBehavior
	if not (selection and selection:HasSelection()) then return nil end
	local selected = selection:GetSelectedElementData()[1]
	local resultID = selected and selected.data and selected.data.resultID
	local info = resultID and C_LFGList.GetSearchResultInfo(resultID)
	return info and info.leaderName
end

local function ShowingLFG()
	return ns.DB and ns.DB.enhanceLFG and LFGBrowseFrame and LFGBrowseFrame:IsVisible()
end

local function LFGTarget()
	return ShowingLFG() and ns.LFGSelectedLeader() or nil
end

-- Rows keep their player on the invite button; the row's own name text can
-- carry a Timerunning icon.
local function WhoName(row)
	local info = row and row.InviteButton and row.InviteButton.info
	return info and info.fullName or nil
end

local function WhoTarget()
	if not (ns.DB and ns.DB.enhanceLFG and focusedWho and focusedWho:IsVisible()) then return nil end
	return WhoName(focusedWho)
end

------------------------------------------------------------------------
-- Recent Allies
------------------------------------------------------------------------
-- Offline allies can't be whispered, so they get neither the line nor Y.
local function AllyName(card)
	local data = card and card.elementData
	return data and data.stateData and data.stateData.isOnline and data.characterData and data.characterData.fullName or nil
end

local function AllyTarget()
	if not (ns.DB and ns.DB.enhanceRecentAllies and focusedAlly and focusedAlly:IsVisible()) then return nil end
	return AllyName(focusedAlly)
end

------------------------------------------------------------------------
-- The shared Y binding
------------------------------------------------------------------------
-- A focused ally card or Who row wins over the LFG selection: it's what the
-- cursor is on.
function ns.IntegrationTarget()
	return AllyTarget() or WhoTarget() or LFGTarget()
end

function ns.UpdateIntegrations()
	if lfgHint then
		lfgHint:SetShown(ShowingLFG() and true or false)
		-- Dims with Send Message while nothing is selected.
		lfgHint:SetAlpha(LFGTarget() and 1 or 0.35)
	end
	if whoHint then
		local row = WhoTarget() and focusedWho
		if row then
			whoHint:SetParent(row)
			whoHint:ClearAllPoints()
			whoHint:SetPoint("RIGHT", row.InviteButton, "LEFT", -4, 0)
		end
		-- Y can't be claimed in combat, so the glyph doesn't promise it.
		whoHint:SetShown(row and not InCombatLockdown() and true or false)
	end
	if InCombatLockdown() then return end
	local target = ns.IntegrationTarget()
	if target and not bound then
		SetOverrideBindingClick(owner, true, Y_KEY, "PADChatOpen", "WHISPER")
		bound = true
	elseif not target and bound then
		ClearOverrideBindings(owner)
		bound = false
	end
end
ns.UpdateLFG = ns.UpdateIntegrations

local function CreateYHint(parent)
	local hint = CreateFrame("Frame", nil, parent)
	hint:SetSize(26, 26)
	local atlas = YAtlas()
	if atlas then
		local icon = hint:CreateTexture(nil, "OVERLAY")
		icon:SetAllPoints()
		icon:SetAtlas(atlas)
	else
		ns.MakeBadge(hint, "Y", 22):SetPoint("CENTER", 0, 0)
	end
	return hint
end

local function SetupLFG()
	local browse = LFGBrowseFrame
	if lfgHooked or not (browse and browse.SendMessageButton and browse.UpdateButtonState) then return end
	lfgHooked = true
	lfgHint = CreateYHint(browse)
	lfgHint:SetPoint("LEFT", browse.SendMessageButton, "RIGHT", 4, 0)
	browse:HookScript("OnShow", ns.UpdateIntegrations)
	browse:HookScript("OnHide", ns.UpdateIntegrations)
	-- Runs on every selection change and result refresh.
	hooksecurefunc(browse, "UpdateButtonState", ns.UpdateIntegrations)
	ns.UpdateIntegrations()
end

-- Rows and their invite buttons copy the mixins' OnEnter when the list first
-- creates them, after this hook. A row's OnLeave is a plain function, so each
-- frame gets its leave hook the first time the cursor arrives.
local function SetupWho()
	local row, invite = LFGWhoListButtonMixin, WhoInviteButtonMixin
	if whoHooked or not (row and row.OnEnter and invite and invite.OnEnter) then return end
	whoHooked = true
	whoHint = CreateYHint(UIParent)
	whoHint:Hide()
	local function Leave(frame)
		if focusedWho == (frame.InviteButton and frame or frame:GetParent()) then focusedWho = nil end
		ns.UpdateIntegrations()
	end
	local function Enter(frame, rowFrame)
		if not frame.padchatLeaveHooked then
			frame.padchatLeaveHooked = true
			frame:HookScript("OnLeave", Leave)
		end
		focusedWho = rowFrame
		ns.UpdateIntegrations()
	end
	hooksecurefunc(row, "OnEnter", function(self) Enter(self, self) end)
	hooksecurefunc(invite, "OnEnter", function(self) Enter(self, self:GetParent()) end)
end

-- Cards copy the mixin's methods when the list first creates them, which
-- happens on first show, after this hook.
local function SetupRecentAllies()
	local card = RecentAlliesSocialCardMixin
	if alliesHooked or not (card and card.BuildTooltip and card.HideTooltip) then return end
	alliesHooked = true
	hooksecurefunc(card, "BuildTooltip", function(self, tooltip)
		focusedAlly = self
		ns.UpdateIntegrations()
		if not (ns.DB and ns.DB.enhanceRecentAllies and AllyName(self)) or InCombatLockdown() then return end
		if SocialUIUtil and SocialUIUtil.AddSeparatorToTooltip then
			SocialUIUtil.AddSeparatorToTooltip(tooltip)
		else
			tooltip:AddLine(" ")
		end
		local atlas = YAtlas()
		local key = atlas and CreateAtlasMarkup and CreateAtlasMarkup(atlas, 20, 20) or ("|c" .. ns.KEY_COLOR.Y .. "Y|r")
		tooltip:AddLine(key .. " Whisper with quick chat", 0.4, 1, 0.4)
	end)
	hooksecurefunc(card, "HideTooltip", function(self)
		if focusedAlly == self then focusedAlly = nil end
		ns.UpdateIntegrations()
	end)
end

-- Runs before the secure snippet opens the menu, so the player is first in the
-- whisper list the menu snapshots and starts on.
PADChatOpen:HookScript("PreClick", function(_, button)
	if button == "WHISPER" then ns.SetPendingWhisper(ns.IntegrationTarget()) end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == "Blizzard_GroupFinder_VanillaStyle" then SetupLFG(); SetupWho()
		elseif name == "Blizzard_RecentAllies" then SetupRecentAllies() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if bound then ClearOverrideBindings(owner); bound = false end
	else
		ns.UpdateIntegrations()
	end
end)
-- In case either Blizzard addon loaded first.
SetupLFG()
SetupWho()
SetupRecentAllies()
