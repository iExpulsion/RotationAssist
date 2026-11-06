local _, NS = ...
local RA = NS.RA

-- Minimap button: left-click opens the window, right-click opens the rotation linked to the active spec, drag
-- moves it around the minimap and Shift-drag anywhere on screen. Position and visibility are saved in RotationAssistDB.minimap. When a
-- LibDataBroker display is installed, a launcher is registered there too.
local MinimapButton = {}
RA.MinimapButton = MinimapButton

local ICON = "Interface\\Icons\\Ability_Warrior_Rampage"
local DEFAULT_ANGLE = 230
local button

-- Which quadrants of each minimap shape are round, in the order GetMinimapShape addons use.
local SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- Shift-drag frees the button: it moves to UIParent at a saved spot (db.minimap.free), so it stays up even when
-- the minimap is hidden. A plain drag puts it back on the minimap's edge.
local function place()
	local free = RA.db.minimap.free
	local parent = free and UIParent or Minimap
	if button:GetParent() ~= parent then
		button:SetParent(parent)
		button:SetFrameStrata("MEDIUM")
		button:SetFrameLevel(8)
		button.running:SetFrameLevel(button:GetFrameLevel() + 2)
	end
	button:ClearAllPoints()
	if free then
		button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", free.x, free.y)
	else
		local angle = math.rad(RA.db.minimap.angle or DEFAULT_ANGLE)
		local x, y = math.cos(angle), math.sin(angle)
		local quadrant = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
		local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
		local radius = Minimap:GetWidth() / 2 + 5
		if (SHAPES[shape] or SHAPES.ROUND)[quadrant] then
			x, y = x * radius, y * radius
		else
			local diagonal = math.sqrt(2 * radius * radius) - 10
			x = math.max(-radius, math.min(x * diagonal, radius))
			y = math.max(-radius, math.min(y * diagonal, radius))
		end
		button:SetPoint("CENTER", Minimap, "CENTER", x, y)
	end
end

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
	tt:AddLine("Drag to move it around the minimap, Shift-drag to place it anywhere.", 0.6, 0.6, 0.66)
	tt:AddLine("/rota minimap hides it; /rota minimap reset puts it back.", 0.6, 0.6, 0.66)
end

-- Ends on the mouse release itself: a reparent mid-drag can cost the OnDragStop.
local function onDragUpdate()
	if IsMouseButtonDown("LeftButton") then
		local px, py = GetCursorPosition()
		if RA.db.minimap.free then
			local scale = UIParent:GetEffectiveScale()
			RA.db.minimap.free.x, RA.db.minimap.free.y = px / scale, py / scale
		else
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			RA.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
		end
		place()
	else
		button.dragging = false
	end
end

local function create()
	button = CreateFrame("Button", "RotationAssistMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ICON)
	button.icon:SetSize(17, 17)
	button.icon:SetPoint("TOPLEFT", 7, -6)
	button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	-- the Rotation Button's running dot, for when that button is hidden
	button.running = CreateFrame("Frame", nil, button)
	button.running:SetSize(8, 8)
	button.running:SetPoint("CENTER", button.icon, "BOTTOMRIGHT", -1, 1)
	button.running:SetFrameLevel(button:GetFrameLevel() + 2)
	RA.Style.Panel(button.running, RA.Style.colors.good, { 0, 0, 0, 1 })
	button.running:Hide()
	local elapsed = 0
	button:SetScript("OnUpdate", function(_, dt)
		if button.dragging then onDragUpdate() end
		elapsed = elapsed + dt
		if elapsed >= 0.1 then
			elapsed = 0
			if RA.RotationButton.Running() then button.running:Show() else button.running:Hide() end
		end
	end)

	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		fillTooltip(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		RA.db.minimap.free = IsShiftKeyDown() and (RA.db.minimap.free or {}) or nil
		self.dragging = true
	end)
	button:SetScript("OnDragStop", function(self) self.dragging = false end)
	place()
end

local function registerBroker()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if ldb then
		ldb:NewDataObject("RotationAssist", {
			type = "launcher",
			icon = ICON,
			label = "Rotation Assist",
			OnClick = onClick,
			OnTooltipShow = fillTooltip,
		})
	end
end

function MinimapButton.Refresh()
	if RA.db.minimap.hide then button:Hide() else button:Show() end
end

function MinimapButton.Toggle()
	RA.db.minimap.hide = not RA.db.minimap.hide
	MinimapButton.Refresh()
	RA:Print(RA.db.minimap.hide and "Minimap button hidden. /rota minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.ResetPosition()
	RA.db.minimap.free, RA.db.minimap.angle = nil, nil
	place()
	RA:Print("Minimap button moved back to the minimap.")
end

function MinimapButton.Frame()
	return button
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	RA.db.minimap = RA.db.minimap or {}
	create()
	registerBroker()
	MinimapButton.Refresh()
	self:UnregisterEvent("PLAYER_LOGIN")
end)
