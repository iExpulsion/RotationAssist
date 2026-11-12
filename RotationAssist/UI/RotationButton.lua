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
RB.RUNNING = 1

local exec, toggle, mover, lastPress

-- Whether the Rotation key, a click or a mouse macro pressed the rotation button in the last second.
function RB.Running()
	return lastPress ~= nil and GetTime() - lastPress < RB.RUNNING
end

function RB.Pressed()
	lastPress = GetTime()
end

-- A spell the game refused while neither it nor the global cooldown was running (Power Word: Shield under Weakened
-- Soul, or a trigger that's met too often) is passed over for a moment, so it can't stall every press.
-- Keyed by lower-case name: the event names the spell as the game spells it, and a rotation may not.
-- A spell refused while it read as unusable (Hunger For Blood with no bleed) is remembered for the session: the
-- client still tries it and the refusal ends the press, so it can't be trusted to fail quietly.
RB.REFUSED_HOLD = 2
local refusedAt, refusedUnusable = {}, {}
local lowered = setmetatable({}, { __index = function(t, name)
	local key = name:lower()
	t[name] = key
	return key
end })
local refusals = CreateFrame("Frame")
refusals:RegisterEvent("UNIT_SPELLCAST_FAILED")
refusals:SetScript("OnEvent", function(_, _, unit, spell)
	local start = unit == "player" and spell and GetSpellCooldown(spell)
	if start == 0 then
		local key = lowered[spell]
		refusedAt[key] = GetTime()
		if not IsUsableSpell(spell) then refusedUnusable[key] = true end
	end
end)

local function refused(cast)
	local at = refusedAt[lowered[cast.name]]
	return at ~= nil and GetTime() - at < RB.REFUSED_HOLD
end

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
		GameTooltip:AddLine("The green dot shows while presses keep coming, from the key, clicks or a mouse macro, and goes out a second after the last one.", 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

-- IsUsableSpell says yes to these with no combo points.
local FINISHERS = {
	Eviscerate = true, ["Slice and Dice"] = true, Rupture = true, ["Kidney Shot"] = true, ["Expose Armor"] = true,
	Envenom = true, ["Deadly Throw"] = true, Rip = true, ["Ferocious Bite"] = true, Maim = true, ["Savage Roar"] = true,
}

-- For server modules: names = { "Spell Name", ... }, spells that need combo points.
function RA:AddFinishers(names)
	for _, name in ipairs(names) do FINISHERS[name] = true end
end

-- What IsUsableSpell misses: combo points for a finisher, and standing still for a spell with a cast time, unless
-- it's marked Cast While Moving.
local function castableNow(cast)
	local castTime = select(7, GetSpellInfo(cast.name)) or 0
	local moving = GetUnitSpeed ~= nil and (GetUnitSpeed("player") or 0) > 0
	local comboOk = not FINISHERS[cast.name] or (GetComboPoints("player", "target") or 0) > 0
	return comboOk and not (moving and castTime > 0 and not cast.moving)
end

-- The parse text is kept on the cast, which lives until the rotation is compiled again.
local function condOk(cast)
	local ok = (cast.cond or "") == ""
	if not ok then
		cast.condText = cast.condText or (cast.cond .. " x")
		ok = SecureCmdOptionParse(cast.condText) == "x"
	end
	return ok
end

local function offCooldown(cast)
	local start, duration = GetSpellCooldown(cast.name)
	return start == nil or start == 0 or (duration or 0) <= GCD
end

local function outOfRange(cast)
	return IsSpellInRange(cast.name, cast.unit or "target") == 0
end

-- Why the spell isn't ready, or nil when it is: conditions hold, usable, the runes are up, castable now, off
-- cooldown (or only on the global cooldown), in range of the unit the conditions cast on, and not just refused.
function RB.NotReady(cast)
	local why
	if not condOk(cast) then
		why = "conditions"
	elseif not IsUsableSpell(cast.name) then
		why = "not usable"
	elseif not RA.Runes.Enough(cast.name) then
		why = "runes"
	elseif not castableNow(cast) then
		why = "moving or no combo points"
	elseif not offCooldown(cast) then
		why = "on cooldown"
	elseif outOfRange(cast) then
		why = "out of range"
	elseif refused(cast) then
		why = "just refused"
	end
	return why
end

local function looksReady(cast)
	return RB.NotReady(cast) == nil
end

-- Whether the global cooldown is running, judged from the first spell in the list whose cooldown is only the
-- global one. A cast tried now can only fail, and 3.3.5 has no spell queue to hold it.
function RB.OnGlobalCooldown(casts)
	local now = GetTime()
	for _, cast in ipairs(casts) do
		if cast.kind == "spell" then
			local start, duration = GetSpellCooldown(cast.name)
			if start and start > 0 and duration > 0 and duration <= GCD then return start + duration > now end
		end
	end
	return false
end
RB.LooksReady = looksReady
RB.Refused = refused

-- Whether a /cast of the spell fails without stopping the press: its condition fails, or it can't be afforded,
-- isn't lit or is out of range. A cooldown or short runes fail as "not ready", which stops the press.
function RB.FailsQuietly(cast)
	local blocked = not offCooldown(cast) or not RA.Runes.Enough(cast.name)
	local quiet = (not IsUsableSpell(cast.name) and not refusedUnusable[lowered[cast.name]]) or outOfRange(cast)
	return not condOk(cast) or (not blocked and quiet)
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
		if spell and T.Has(cast.trigger) and T.Holds(cast.trigger) and looksReady(cast) then return cast, true end
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
	-- this runs ten times a second, so each part is only set when it changes
	local idle = upcoming == nil
	if icon ~= exec.shownIcon or idle ~= exec.shownIdle then
		exec.shownIcon, exec.shownIdle = icon, idle
		exec.icon:SetTexture(icon)
		exec.icon:SetDesaturated(idle)
	end
	if RB.Running() then exec.running:Show() else exec.running:Hide() end
	local label = modeLabel()
	if label ~= exec.shownMode then
		exec.shownMode = label
		exec.mode:SetText(label)
	end
	local mainKey, toggleKey = RA.Keys.Get("main"), RA.Keys.Get("toggle")
	if mainKey ~= exec.shownKey or not exec.keyShown then
		exec.shownKey, exec.keyShown = mainKey, true
		exec.key:SetText(mainKey and RA.Keys.Text("main") or "")
	end
	if toggleKey ~= toggle.shownKey or not toggle.keyShown then
		toggle.shownKey, toggle.keyShown = toggleKey, true
		toggle.key:SetText(toggleKey and RA.Keys.Text("toggle") or "")
	end
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
	-- shown while presses keep coming, so a mouse macro left on is easy to spot
	exec.running = CreateFrame("Frame", nil, exec)
	exec.running:SetSize(10, 10)
	exec.running:SetPoint("TOPLEFT", 4, -4)
	exec.running:SetFrameLevel(exec:GetFrameLevel() + 3)
	S.Panel(exec.running, C.good, { 0, 0, 0, 1 })
	exec.running:Hide()
	exec:HookScript("PreClick", RB.Pressed)
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
