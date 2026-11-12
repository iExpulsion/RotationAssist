local _, NS = ...
local RA = NS.RA

-- Smart Picks: the macro's /run lines call these at press time. RAPick asks the Rotation Button's prediction
-- (triggers included) which action to cast; RAGate clears the target before another GCD line that could get in
-- its way, so that line's [exists] condition fails, and the line after it retargets. In combat the client logs
-- each ClearTarget from here as blocked (and prints "Interface action failed" once) but still clears the target.
local Smart = {}
RA.Smart = Smart

local NONE_SOLO = {}

local function currentMode()
	local compiled = RA.Engine.compiled
	return compiled and compiled.modes[RA.Engine.ModeIndex()]
end

local function currentCasts()
	local mode = currentMode()
	return mode and mode.casts or {}
end

-- With no target, only casts on another unit ([@player]) can go, through their solo buttons.
local unitCasts = {}
local function castsOnUnits(casts)
	for k in pairs(unitCasts) do unitCasts[k] = nil end
	for _, cast in ipairs(casts) do
		if cast.unit then unitCasts[#unitCasts + 1] = cast end
	end
	return unitCasts
end

-- Out of combat only: the picked solo cast goes on its button and the rest are blanked. A secure button can't be
-- changed in combat, so there the solo buttons stay blank and a press with no target does nothing.
local function fillSolo(pickIndex)
	local mode = currentMode()
	for _, solo in ipairs(mode and mode.solo or NONE_SOLO) do
		local button = _G[RA.Compiler.STEP_BUTTON .. solo.button]
		if button then
			button:SetAttribute("count", 1)
			button:SetAttribute("s1", solo.index == pickIndex and solo.line or "")
		end
	end
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
			-- a refused self-cast (Power Word: Shield under Weakened Soul) still stops the press, unusable or not
			clear = cast.unit ~= nil or not RB.FailsQuietly(cast)
		end
	end
	return clear
end

-- Which lines' gates clear the target, reused from press to press.
local clears, NONE = {}, {}

-- The pick, and which lines' gates clear the target, all decided before the first gate runs.
local function pick()
	local casts = currentCasts()
	local targeted = UnitExists("target")
	local cast = RA.RotationButton.Predict(targeted and casts or castsOnUnits(casts))
	-- with the hold on, nothing is tried during the global cooldown: the cast could only fail, and a failed cast
	-- plays the spell's fizzle sound on every press
	local waiting = RA:HoldsDuringGcd() and RA.RotationButton.OnGlobalCooldown(casts)
	if not InCombatLockdown() then fillSolo(not targeted and not waiting and cast and cast.index) end
	for k in pairs(clears) do clears[k] = nil end
	local refused, T = RA.RotationButton.Refused, RA.Triggers
	for _, other in ipairs(casts) do
		if waiting and not other.offGcd then
			clears[other.index] = true
		elseif not other.offGcd and other ~= cast then
			-- with no pick the press runs as a plain list, but a spell the game just refused would end it again and
			-- a spell whose trigger isn't met mustn't cast, so both are still held back
			local spell = other.kind == "spell"
			local held = spell and refused(other)
			local unmet = spell and T.Has(other.trigger) and not T.Holds(other.trigger)
			clears[other.index] = held or (cast == nil and unmet) or (cast ~= nil and mustClear(other, cast.index))
		end
	end
	return cast and cast.index, clears
end

-- An error here would run the error handler inside the macro, and the game blocks the rest of the press ("Interface
-- action failed because of an AddOn"), so a failed pick falls back to the plain list instead.
function RAPick()
	local ok, index, picked = pcall(pick)
	Smart.pick = ok and index or nil
	Smart.clears = ok and picked or NONE
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

-- Combat lockdown starts right after this event, so a solo cast picked before the pull doesn't keep firing.
local blanker = CreateFrame("Frame")
blanker:RegisterEvent("PLAYER_REGEN_DISABLED")
blanker:SetScript("OnEvent", function()
	local compiled = RA.Engine.compiled
	for _, mode in ipairs(compiled and compiled.modes or NONE_SOLO) do
		for _, solo in ipairs(mode.solo or NONE_SOLO) do
			local button = _G[RA.Compiler.STEP_BUTTON .. solo.button]
			if button then button:SetAttribute("s1", "") end
		end
	end
end)

-- With nothing looking ready, only lines the game just refused or whose trigger isn't met are gated, and the rest of
-- the press works like a plain list.
function RAGate(index)
	if Smart.clears and Smart.clears[index] then ClearTarget() end
end
