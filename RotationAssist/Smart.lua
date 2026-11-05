local _, NS = ...
local RA = NS.RA

-- Smart Picks: at press time RAPick asks the Rotation Button's prediction (triggers included) which action to cast,
-- and writes the lines that must lose the target to a CVar, as ",1,3,". Each gate line in the macro reads that and
-- clears the target, so its [exists] condition fails, and the line after it retargets. The gate can't call addon
-- code: that taints the line, and the game then blocks ClearTarget in combat.
local Smart = {}
RA.Smart = Smart

local CVAR = RA.Compiler.GATE_CVAR
if RegisterCVar then RegisterCVar(CVAR, "") end

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
	local list = {}
	for i, clear in pairs(Smart.clears) do
		if clear then list[#list + 1] = i end
	end
	table.sort(list)
	SetCVar(CVAR, #list > 0 and ("," .. table.concat(list, ",") .. ",") or "")
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
