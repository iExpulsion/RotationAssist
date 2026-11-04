local _, NS = ...
local RA = NS.RA

-- The on-screen Rotation Button: the secure rotation button itself, drawn as a flat square with the spell it will
-- most likely cast next, the mode's name under it and the key in the corner, plus a smaller Mode button beside it.
-- It can be clicked with the mouse like the key. Showing, hiding, moving and scaling only happen out of combat.
local RB = {}
RA.RotationButton = RB

local S = RA.Style
local C = S.colors
local SIZE, TOGGLE_SIZE = 56, 30
local THROTTLE = 0.1
local GCD = 1.5

local exec, toggle, mover

local function savePosition()
	local point, _, relPoint, x, y = exec:GetPoint()
	RA.db.button.point = { point = point, relPoint = relPoint, x = x, y = y }
end

local function place()
	local pos = RA.db.button.point
	exec:ClearAllPoints()
	if pos then exec:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y) else exec:SetPoint("CENTER", 0, -180) end
	exec:SetScale(RA.db.button.scale or 1)
end

local function dress(b, size, iconInset)
	b:SetSize(size, size)
	S.Panel(b, C.well, C.border)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", iconInset, -iconInset)
	b.icon:SetPoint("BOTTOMRIGHT", -iconInset, iconInset)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local hover = S.Solid(b, "HIGHLIGHT", C.hover)
	hover:SetAllPoints()
	b:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
	b:GetPushedTexture():SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
	b.key = S.Text(b, "small", C.text, "OVERLAY")
	b.key:SetPoint("TOPRIGHT", -3, -3)
	b.key:SetJustifyH("RIGHT")
end

local function tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local rotation = RA.Engine.rotation
	GameTooltip:AddLine(rotation and rotation.name or "No Rotation", 1, 1, 1)
	if self == toggle then
		GameTooltip:AddLine("Click or press the Mode key to go to the next mode.", 0.8, 0.8, 0.8, true)
	else
		GameTooltip:AddLine("Click or press the Rotation key to cast the first ready spell. The icon is the likely next one; a glow means a trigger picked it, such as a proc.", 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

-- IsUsableSpell says yes to these with no combo points.
local FINISHERS = {
	Eviscerate = true, ["Slice and Dice"] = true, Rupture = true, ["Kidney Shot"] = true, ["Expose Armor"] = true,
	Envenom = true, ["Deadly Throw"] = true, Rip = true, ["Ferocious Bite"] = true, Maim = true, ["Savage Roar"] = true,
}

-- What IsUsableSpell misses: combo points for a finisher, and standing still for a spell with a cast time, unless
-- a proc buff its trigger checks makes it instant.
local function castableNow(name, proc)
	local castTime = select(7, GetSpellInfo(name)) or 0
	local moving = GetUnitSpeed ~= nil and (GetUnitSpeed("player") or 0) > 0
	local comboOk = not FINISHERS[name] or (GetComboPoints("player", "target") or 0) > 0
	return comboOk and not (moving and castTime > 0 and not proc)
end

-- Conditions hold, usable, the runes are up, off cooldown (or only on the global cooldown) and in range.
local function looksReady(cast, proc)
	local condOk = cast.cond == "" or SecureCmdOptionParse(cast.cond .. " x") == "x"
	local start, duration = GetSpellCooldown(cast.name)
	local ready = start == nil or start == 0 or (duration or 0) <= GCD
	local range = IsSpellInRange(cast.name, "target")
	return condOk and IsUsableSpell(cast.name) and RA.Runes.Enough(cast.name) and castableNow(cast.name, proc) and ready
		and range ~= 0
end

-- The spell to suggest next, and whether a trigger picked it. A ready spell whose trigger is met comes first,
-- wherever it is in the list. Otherwise it's the first ready GCD spell without a trigger (a spell with a trigger is
-- only suggested while it's met). A Sequence or Steps block stops that search, since which spell it casts isn't
-- known; a once-per-reset Sequence is passed over, since most presses find it already done.
function RB.Predict(casts)
	casts = casts or {}
	local T = RA.Triggers
	for _, cast in ipairs(casts) do
		local spell = cast.kind == "spell" and not cast.offGcd
		local met, proc = false, false
		if spell and T.Has(cast.trigger) then met, proc = T.Holds(cast.trigger) end
		if met and looksReady(cast, proc) then return cast, true end
	end
	for _, cast in ipairs(casts) do
		if not cast.offGcd and not cast.once then
			if cast.kind ~= "spell" then return cast, false end
			if not T.Has(cast.trigger) and looksReady(cast) then return cast, false end
		end
	end
	return nil, false
end

local function modeLabel()
	local rotation = RA.Engine.rotation
	local mode = rotation and rotation.modes[RA.Engine.ModeIndex()]
	return mode and mode.label or ""
end

local function update()
	local compiled = RA.Engine.compiled
	local mode = compiled and compiled.modes[RA.Engine.ModeIndex()]
	local upcoming, triggered = nil, false
	if mode then upcoming, triggered = RB.Predict(mode.casts) end
	RB.triggered = triggered
	if triggered then
		exec.glow:Show()
		exec.glow:SetAlpha(0.55 + 0.45 * math.sin(GetTime() * 6))
	else
		exec.glow:Hide()
	end
	local icon = RA.Spells.QUESTION
	if upcoming and upcoming.kind == "spell" then
		icon = RA.Spells.Icon(upcoming.name)
	elseif upcoming then
		icon = RA.Rotation.ActionIcon(RA.Engine.rotation.modes[RA.Engine.ModeIndex()].actions[upcoming.index])
	end
	exec.icon:SetTexture(icon)
	exec.icon:SetDesaturated(upcoming == nil)
	exec.mode:SetText(modeLabel())
	exec.key:SetText(RA.Keys.Get("main") and RA.Keys.Text("main") or "")
	toggle.key:SetText(RA.Keys.Get("toggle") and RA.Keys.Text("toggle") or "")
end

local function create()
	exec, toggle = RA.Engine.Buttons()
	exec:SetParent(UIParent)
	exec:SetFrameStrata("MEDIUM")
	exec:SetMovable(true)
	exec:SetClampedToScreen(true)
	dress(exec, SIZE, 3)
	exec:SetBackdropBorderColor(unpack(C.accent))
	-- shown while a trigger picked the suggestion, such as a proc
	exec.glow = CreateFrame("Frame", nil, exec)
	exec.glow:SetPoint("TOPLEFT", -3, 3)
	exec.glow:SetPoint("BOTTOMRIGHT", 3, -3)
	exec.glow:SetFrameLevel(exec:GetFrameLevel() + 2)
	exec.glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
	exec.glow:SetBackdropBorderColor(unpack(C.warn))
	exec.glow:Hide()
	exec.mode = S.Text(exec, "small", C.muted, "OVERLAY")
	exec.mode:SetPoint("TOP", exec, "BOTTOM", 0, -4)
	exec.mode:SetJustifyH("CENTER")
	exec:SetScript("OnEnter", tooltip)
	exec:SetScript("OnLeave", function() GameTooltip:Hide() end)

	dress(toggle, TOGGLE_SIZE, 2)
	toggle:SetParent(exec)
	toggle:ClearAllPoints()
	toggle:SetPoint("BOTTOMLEFT", exec, "BOTTOMRIGHT", 4, 0)
	toggle:SetScript("OnEnter", tooltip)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	toggle:HookScript("OnClick", update)

	-- an insecure cover that takes the mouse while unlocked, so dragging never clicks the secure button
	mover = CreateFrame("Frame", nil, exec)
	mover:SetAllPoints()
	mover:SetFrameLevel(exec:GetFrameLevel() + 5)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	local tint = S.Solid(mover, "OVERLAY", C.selected)
	tint:SetAllPoints()
	mover:SetScript("OnDragStart", function()
		if not InCombatLockdown() then exec:StartMoving() end
	end)
	mover:SetScript("OnDragStop", function()
		exec:StopMovingOrSizing()
		savePosition()
	end)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Drag to move. Lock it in Settings or with /rota lock.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local elapsed = 0
	exec:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= THROTTLE then
			elapsed = 0
			update()
		end
	end)
	place()
end

-- Out of combat: shows the button when a rotation is active and the player wants it, and the Mode button when the
-- rotation has more than one mode.
function RB.Refresh()
	if exec and not InCombatLockdown() then
		local active = RA.Engine.rotation ~= nil
		if active and RA.db.button.shown then exec:Show() else exec:Hide() end
		if RA.Engine.ModeCount() > 1 then toggle:Show() else toggle:Hide() end
		if RA.db.button.locked then mover:Hide() else mover:Show() end
		place()
		update()
	end
end

-- Entering combat locks the button, since a protected frame can't move then.
function RB.Lock()
	if mover then mover:Hide() end
end

function RB.SetShown(on)
	RA.db.button.shown = on and true or false
	RB.Refresh()
end

function RB.SetLocked(on)
	RA.db.button.locked = on and true or false
	RB.Refresh()
end

function RB.SetScale(scale)
	RA.db.button.scale = scale
	RB.Refresh()
end

function RB.ResetPosition()
	RA.db.button.point = nil
	RB.Refresh()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	create()
	RB.Refresh()
	self:UnregisterEvent("PLAYER_LOGIN")
end)
