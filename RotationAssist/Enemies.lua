local _, NS = ...
local RA = NS.RA

-- Enemies in the fight, for the [enemies>=N] hint: every hostile unit you or your pet hit (damage, a miss, an
-- aura) or that hit you within the last few seconds, until it dies, plus your target. 3.3.5 has no nameplate
-- units, so this is what an addon can count; mobs that haven't been touched yet don't count.
local Enemies = {}
RA.Enemies = Enemies

Enemies.WINDOW = 4
local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1
-- neutral too: training dummies and plenty of mobs are yellow, not red
local HOSTILE = (COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40) + (COMBATLOG_OBJECT_REACTION_NEUTRAL or 0x20)
local AURAS = { SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_APPLIED_DOSE = true }
local DEATHS = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

local seen = {}

local function has(flags, flag)
	return bit.band(flags or 0, flag) ~= 0
end

local function contact(event)
	return event:find("_DAMAGE$") ~= nil or event:find("_MISSED$") ~= nil or AURAS[event] == true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, _, sub, srcGUID, _, srcFlags, dstGUID, _, dstFlags)
	if event == "PLAYER_REGEN_ENABLED" then
		seen = {}
	elseif DEATHS[sub] and dstGUID then
		seen[dstGUID] = nil
	elseif sub and contact(sub) then
		if has(srcFlags, MINE) and has(dstFlags, HOSTILE) and dstGUID then seen[dstGUID] = GetTime() end
		if has(dstFlags, MINE) and has(srcFlags, HOSTILE) and srcGUID then seen[srcGUID] = GetTime() end
	end
end)

function Enemies.Count()
	local now, count = GetTime(), 0
	for guid, at in pairs(seen) do
		if now - at <= Enemies.WINDOW then count = count + 1 else seen[guid] = nil end
	end
	local target = UnitGUID("target")
	local fresh = target and seen[target]
	if target and not fresh and UnitCanAttack("player", "target") and not UnitIsDead("target") then count = count + 1 end
	return count
end
