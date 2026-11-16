local _, NS = ...
local RA = NS.RA

-- Minimap button (S.MinimapButton): left-click opens the window, right-click opens the rotation linked to the
-- active spec, and a green dot shows while the Rotation Button is running. Position and visibility are saved in
-- RotationAssistDB.minimap. When a LibDataBroker display is installed, a launcher is registered there too.
local MinimapButton = {}
RA.MinimapButton = MinimapButton

local ICON = "Interface\\Icons\\Ability_Warrior_Rampage"
local button

local function onClick(_, mouse)
	local active = RA:ActiveRotation()
	if mouse == "RightButton" and active then
		RA.Window.Open(active.name)
	elseif mouse == "RightButton" then
		RA:Print("No rotation is linked to %s yet. Pick one and click Use Rotation.", RA:SpecName(RA:ActiveGroup()))
	else
		RA.Window.Toggle()
	end
end

local function fillTooltip(tt)
	tt:AddLine("Rotation Assist", 1, 0.77, 0)
	local active = RA:ActiveRotation()
	tt:AddLine(RA:SpecName(RA:ActiveGroup()) .. ": " .. (active and active.name or "no rotation"), 1, 1, 1)
	if RA.RotationButton.Running() then tt:AddLine("Running: the rotation key is being pressed.", 0.4, 0.85, 0.5) end
	tt:AddLine("Left-click to open or close the rotation window.", 0.8, 0.8, 0.8)
	tt:AddLine("Right-click to open this spec's rotation.", 0.8, 0.8, 0.8)
end

-- the Rotation Button's running dot, for when that button is hidden
local function addRunningDot()
	button.running = CreateFrame("Frame", nil, button)
	button.running:SetSize(8, 8)
	button.running:SetPoint("CENTER", button.icon, "BOTTOMRIGHT", -1, 1)
	button.running:SetFrameLevel(button:GetFrameLevel() + 2)
	RA.Style.Panel(button.running, RA.Style.colors.good, { 0, 0, 0, 1 })
	button.running:Hide()
	local elapsed = 0
	button:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 0.1 then
			elapsed = 0
			if RA.RotationButton.Running() then button.running:Show() else button.running:Hide() end
		end
	end)
end

-- Registered while the addon loads, not at login: displays like ElvUI fill their panels on PLAYER_LOGIN before
-- our handler runs, and a launcher created after that never lands in the panel set to it.
LibStub("LibDataBroker-1.1"):NewDataObject("RotationAssist", {
	type = "launcher",
	icon = ICON,
	label = "Rotation Assist",
	text = "Rotation Assist",
	OnClick = onClick,
	OnTooltipShow = fillTooltip,
})

function MinimapButton.Refresh()
	button:Refresh()
end

function MinimapButton.Toggle()
	RA.db.minimap.hide = not RA.db.minimap.hide
	button:Refresh()
	RA:Print(RA.db.minimap.hide and "Minimap button hidden. /rota minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.ResetPosition()
	button:ResetPosition()
	RA:Print("Minimap button moved back to the minimap.")
end

function MinimapButton.Frame()
	return button
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	RA.db.minimap = RA.db.minimap or {}
	button = RA.Style.MinimapButton({
		name = "RotationAssistMinimapButton", icon = ICON, db = RA.db.minimap, angle = 230,
		onClick = onClick, tooltip = fillTooltip, hint = "/rota minimap hides it; /rota minimap reset puts it back.",
		onReparent = function(b) if b.running then b.running:SetFrameLevel(b:GetFrameLevel() + 2) end end,
	})
	addRunningDot()
	self:UnregisterEvent("PLAYER_LOGIN")
end)
