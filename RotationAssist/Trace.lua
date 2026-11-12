local _, NS = ...
local RA = NS.RA

-- /rota trace: for a moment after each press of the rotation button, prints what the client reports in order
-- (spells sent, succeeded or failed, and error text), to see which line of a priority macro takes the press.
local Trace = {}
RA.Trace = Trace

Trace.WINDOW = 0.5
local on, watchUntil, press = false, 0, 0

local frame = CreateFrame("Frame")
local EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UI_ERROR_MESSAGE" }
local LABELS = { UNIT_SPELLCAST_SENT = "Sent", UNIT_SPELLCAST_SUCCEEDED = "Cast", UNIT_SPELLCAST_FAILED = "Failed" }

frame:SetScript("OnEvent", function(_, event, a, b)
	if GetTime() < watchUntil then
		if event == "UI_ERROR_MESSAGE" then
			RA:Print("  |cffff6060Error|r %s", tostring(a))
		elseif a == "player" then
			RA:Print("  %s %s", LABELS[event], tostring(b))
		end
	end
end)

-- With no pick: why each spell that could have been picked (no trigger, or a met one) isn't ready.
function Trace.NoPick(casts)
	local T, RB = RA.Triggers, RA.RotationButton
	local reasons = {}
	for _, cast in ipairs(casts or {}) do
		local candidate = cast.kind == "spell" and not cast.offGcd and (not T.Has(cast.trigger) or T.Holds(cast.trigger))
		local why = candidate and RB.NotReady(cast)
		if why then reasons[#reasons + 1] = cast.name .. ": " .. why end
	end
	return #reasons > 0 and ("none (" .. table.concat(reasons, "; ") .. ")") or "none"
end

function Trace.Pressed()
	if on then
		press = press + 1
		watchUntil = GetTime() + Trace.WINDOW
		local mode = RA.Engine.rotation and RA.Engine.rotation.modes[RA.Engine.ModeIndex()]
		local compiled = RA.Engine.compiled and RA.Engine.compiled.modes[RA.Engine.ModeIndex()]
		local pick = compiled and RA.RotationButton.Predict(compiled.casts)
		local waiting = compiled and compiled.smart and RA:HoldsDuringGcd() and RA.RotationButton.OnGlobalCooldown(compiled.casts)
		RA:Print("Press %d (%s, %d enemies), pick: %s%s", press, mode and mode.label or "no rotation", RA.Enemies.Count(),
			pick and (pick.name or ("action " .. pick.index)) or Trace.NoPick(compiled and compiled.casts),
			waiting and ", held for the global cooldown" or "")
	end
end

function Trace.Toggle()
	on = not on
	for _, event in ipairs(EVENTS) do
		if on then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
	end
	return on
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	local exec = RA.Engine.Buttons()
	exec:HookScript("PreClick", Trace.Pressed)
	self:UnregisterEvent("PLAYER_LOGIN")
end)
