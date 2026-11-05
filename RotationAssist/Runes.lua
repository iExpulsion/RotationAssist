local _, NS = ...
local RA = NS.RA

-- Rune costs for the Rotation Button's guess. IsUsableSpell says yes to a Death Knight spell whose runes are still
-- recharging, so without this a Smart Pick could wait on a spell that can't cast while another could. Death runes
-- stand in for any type. Spells not listed, and characters without runes, are left to IsUsableSpell.
local Runes = {}
RA.Runes = Runes

local BLOOD, UNHOLY, FROST, DEATH = 1, 2, 3, 4
local RUNES = 6
local B, U, F = { [BLOOD] = 1 }, { [UNHOLY] = 1 }, { [FROST] = 1 }
local FU, BFU = { [FROST] = 1, [UNHOLY] = 1 }, { [BLOOD] = 1, [FROST] = 1, [UNHOLY] = 1 }

Runes.COSTS = {
	["Blood Strike"] = B, ["Heart Strike"] = B, ["Pestilence"] = B, ["Blood Boil"] = B, ["Rune Tap"] = B,
	["Strangulate"] = B, ["Dark Command"] = B,
	["Icy Touch"] = F, ["Chains of Ice"] = F, ["Unbreakable Armor"] = F,
	["Plague Strike"] = U, ["Bone Shield"] = U, ["Anti-Magic Zone"] = U,
	["Death Strike"] = FU, ["Obliterate"] = FU, ["Scourge Strike"] = FU, ["Howling Blast"] = FU,
	["Death and Decay"] = BFU, ["Army of the Dead"] = BFU,
}

local KINDS = { blood = BLOOD, unholy = UNHOLY, frost = FROST }

-- For server modules: costs = { ["Spell Name"] = { frost = 1, unholy = 1 }, ... }.
function RA:AddRuneCosts(costs)
	for name, cost in pairs(costs) do
		local entry = {}
		for kind, count in pairs(cost) do
			if KINDS[kind] then entry[KINDS[kind]] = count end
		end
		Runes.COSTS[name] = entry
	end
end

-- Ready runes by kind, reused: the button asks several times a second.
local ready = {}

-- Whether the ready runes cover the spell's cost.
function Runes.Enough(name)
	local cost = Runes.COSTS[name]
	local enough = true
	if cost and GetRuneCooldown and GetRuneCooldown(1) ~= nil then
		ready[BLOOD], ready[UNHOLY], ready[FROST], ready[DEATH] = 0, 0, 0, 0
		-- the client raises "Invalid slot" past the last rune rather than returning nil
		-- some clients leave the runeReady flag false on idle runes, so the cooldown decides
		local now = GetTime()
		for i = 1, RUNES do
			local start, duration, isReady = GetRuneCooldown(i)
			local kind = GetRuneType(i)
			local up = isReady or (start or 0) == 0 or (start + (duration or 0)) <= now
			if up and ready[kind] then ready[kind] = ready[kind] + 1 end
		end
		local short = 0
		for kind, count in pairs(cost) do short = short + math.max(0, count - ready[kind]) end
		enough = short <= ready[DEATH]
	end
	return enough
end
