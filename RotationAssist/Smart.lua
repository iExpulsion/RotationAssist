local _, NS = ...
local RA = NS.RA

-- Smart Picks: the macro's /run lines call these at press time. RAPick asks the Rotation Button's prediction
-- (triggers included) which action to cast; RAGate clears the target before another GCD line that could get in
-- its way, so that line's [exists] condition fails, and the line after it retargets. In combat the client logs
-- each ClearTarget from here as blocked (and prints "Interface action failed" once) but still clears the target.
local Smart = {}
RA.Smart = Smart

local function currentCasts()
	local compiled = RA.Engine.compiled
	local mode = compiled and compiled.modes[RA.Engine.ModeIndex()]
	return mode and mode.casts or {}
end

-- Every clear flickers the target frames, so a line keeps the target unless it could cast or stop the press.
-- Before the pick, a spell that would only fail quietly can keep it. After the pick has cast, the global cooldown
-- stops the rest, so only a ready spell whose trigger isn't met needs clearing, in case the pick failed.
local function mustClear(cast, pickIndex)
	local RB, T = RA.RotationButton, RA.Triggers
	local after = cast.index > pickIndex
	local clear = not after
	if cast.kind == "spell" then
		if after then
			clear = T.Has(cast.trigger) and not T.Holds(cast.trigger) and RB.LooksReady(cast)
		else
			clear = not RB.FailsQuietly(cast)
		end
	end
	return clear
end

-- The pick, and which lines' gates clear the target, all decided before the first gate runs.
local function pick()
	local casts = currentCasts()
	local cast = RA.RotationButton.Predict(casts)
	local clears = {}
	if cast then
		for _, other in ipairs(casts) do
			if other.index ~= cast.index and not other.offGcd then clears[other.index] = mustClear(other, cast.index) end
		end
	end
	return cast and cast.index, clears
end

-- An error here would run the error handler inside the macro, and the game blocks the rest of the press ("Interface
-- action failed because of an AddOn"), so a failed pick falls back to the plain list instead.
function RAPick()
	local ok, index, clears = pcall(pick)
	Smart.pick = ok and index or nil
	Smart.clears = ok and clears or {}
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
	if Smart.clears and Smart.clears[index] then ClearTarget() end
end
