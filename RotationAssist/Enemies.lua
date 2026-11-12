local _, NS = ...
local RA = NS.RA

-- Enemies in the fight, for the [enemies>=N] trigger: every hostile unit you or your pet hit (damage, a miss, an
-- aura) or that hit you within the last few seconds, until it dies, plus your target. 3.3.5 has no nameplate
-- units, so this is what an addon can count; mobs that haven't been touched yet don't count.
-- It also follows which of them carry your auras, for [without:Blood Plague>=1] (enemies missing your disease).
local Enemies = {}
RA.Enemies = Enemies

Enemies.WINDOW = 4
local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1
-- neutral too: training dummies and plenty of mobs are yellow, not red
local HOSTILE = (COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40) + (COMBATLOG_OBJECT_REACTION_NEUTRAL or 0x20)
local AURAS = { SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_APPLIED_DOSE = true }
local DEATHS = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

-- seen[guid] = last contact; auras[guid][lower-case spell name] = true while it carries that aura from you
local seen, auras = {}, {}
local lower, findAura = RA.Spells.Lower, RA.Spells.FindAura

local function has(flags, flag)
	return bit.band(flags or 0, flag) ~= 0
end

local function contact(event)
	return event:find("_DAMAGE$") ~= nil or event:find("_MISSED$") ~= nil or AURAS[event] == true
end

local function forget(guid)
	seen[guid], auras[guid] = nil, nil
end

-- a periodic tick proves the aura is still there even if its application was missed
local function track(sub, guid, spell)
	if AURAS[sub] or sub == "SPELL_PERIODIC_DAMAGE" then
		auras[guid] = auras[guid] or {}
		auras[guid][lower[spell]] = true
	elseif sub == "SPELL_AURA_REMOVED" and auras[guid] then
		auras[guid][lower[spell]] = nil
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, _, sub, srcGUID, _, srcFlags, dstGUID, _, dstFlags, _, spell)
	local mine = has(srcFlags, MINE) and has(dstFlags, HOSTILE) and dstGUID ~= nil
	if event == "PLAYER_REGEN_ENABLED" then
		seen, auras = {}, {}
	elseif DEATHS[sub] and dstGUID then
		forget(dstGUID)
	elseif sub then
		if mine and spell then track(sub, dstGUID, spell) end
		if contact(sub) then
			if mine then seen[dstGUID] = GetTime() end
			if has(dstFlags, MINE) and has(srcFlags, HOSTILE) and srcGUID then seen[srcGUID] = GetTime() end
		end
	end
end)

-- Drops the stale enemies, then gives the target's GUID and whether it counts before its first hit. The fight is
-- the fresh seen entries plus that target; triggers ask several times a second, so it's counted in place rather
-- than copied into a list.
local function prune()
	local now = GetTime()
	for guid, at in pairs(seen) do
		if now - at > Enemies.WINDOW then forget(guid) end
	end
	local target = UnitGUID("target")
	local extra = target ~= nil and not seen[target] and UnitCanAttack("player", "target") and not UnitIsDead("target")
	return target, extra
end

function Enemies.Count()
	local _, extra = prune()
	local count = extra and 1 or 0
	for _ in pairs(seen) do count = count + 1 end
	return count
end

-- Whether an enemy lacks your aura: the target is read directly, the rest come from the log.
local function missing(guid, target, name)
	local carries
	if guid == target then
		carries = findAura("target", name, "HARMFUL|PLAYER") ~= nil
	else
		carries = auras[guid] ~= nil and auras[guid][lower[name]] == true
	end
	return not carries
end

-- How many enemies in the fight don't carry your aura.
function Enemies.Without(name)
	local target, extra = prune()
	local count = (extra and missing(target, target, name)) and 1 or 0
	for guid in pairs(seen) do
		if missing(guid, target, name) then count = count + 1 end
	end
	return count
end
