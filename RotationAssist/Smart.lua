local _, NS = ...
local RA = NS.RA

-- Smart Picks: the macro's /run lines call these at press time. RAPick asks the Rotation Button's prediction
-- (hints included) which action to cast; RAGate clears the target before every other GCD line, so its
-- [exists] condition fails, and the line after it retargets. ClearTarget is allowed in combat on 3.3.5;
-- ClearFocus isn't.
local Smart = {}
RA.Smart = Smart

function RAPick()
	local compiled = RA.Engine.compiled
	local mode = compiled and compiled.modes[RA.Engine.ModeIndex()]
	local cast = mode and RA.RotationButton.Predict(mode.casts)
	Smart.pick = cast and cast.index
end

-- With nothing looking ready, no line is gated and the press works like a plain priority list.
function RAGate(index)
	if Smart.pick and Smart.pick ~= index then ClearTarget() end
end
