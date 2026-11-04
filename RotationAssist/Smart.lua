local _, NS = ...
local RA = NS.RA

-- Smart Picks: the macro's /run lines call these at press time. RAPick asks the Rotation Button's prediction
-- (hints included) which action to cast; RAGate clears the target before every other GCD line, so its
-- [exists] condition fails, and the line after it retargets. ClearTarget is allowed in combat on 3.3.5;
-- ClearFocus isn't.
local Smart = {}
RA.Smart = Smart

local function pick()
	local compiled = RA.Engine.compiled
	local mode = compiled and compiled.modes[RA.Engine.ModeIndex()]
	local cast = mode and RA.RotationButton.Predict(mode.casts)
	return cast and cast.index
end

-- An error here would run the error handler inside the macro, and the game blocks the rest of the press ("Interface
-- action failed because of an AddOn"), so a failed pick falls back to the plain list instead.
function RAPick()
	local ok, index = pcall(pick)
	Smart.pick = ok and index or nil
	if not ok then Smart.failed = index end
end

-- the error still gets reported, on the next frame, once the macro is done
local reporter = CreateFrame("Frame")
reporter:SetScript("OnUpdate", function()
	local failed = Smart.failed
	if failed then
		Smart.failed = nil
		geterrorhandler()(failed)
	end
end)

-- With nothing looking ready, no line is gated and the press works like a plain priority list.
function RAGate(index)
	if Smart.pick and Smart.pick ~= index then ClearTarget() end
end
