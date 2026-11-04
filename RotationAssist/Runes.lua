local _, NS = ...
local RA = NS.RA

-- Rune costs for the Rotation Button's guess. IsUsableSpell says yes to a Death Knight spell whose runes are still
-- recharging, so without this a Smart Pick could wait on a spell that can't cast while another could. Death runes
-- stand in for any type. Spells not listed, and characters without runes, are left to IsUsableSpell.
local Runes = {}
RA.Runes = Runes

local BLOOD, UNHOLY, FROST, DEATH = 1, 2, 3, 4
local MAX_RUNES = 24
local B, U, F = { [BLOOD] = 1 }, { [UNHOLY] = 1 }, { [FROST] = 1 }
local FU, BFU = { [FROST] = 1, [UNHOLY] = 1 }, { [BLOOD] = 1, [FROST] = 1, [UNHOLY] = 1 }

Runes.COSTS = {
	["Blood Strike"] = B, ["Heart Strike"] = B, ["Pestilence"] = B, ["Blood Boil"] = B, ["Rune Tap"] = B,
	["Strangulate"] = B, ["Dark Command"] = B,
	["Icy Touch"] = F, ["Chains of Ice"] = F, ["Unbreakable Armor"] = F, ["Mark of Frost"] = F,
	["Plague Strike"] = U, ["Bone Shield"] = U, ["Anti-Magic Zone"] = U,
	["Death Strike"] = FU, ["Obliterate"] = FU, ["Scourge Strike"] = FU, ["Howling Blast"] = FU,
	["Death and Decay"] = BFU, ["Army of the Dead"] = BFU,
}

-- Whether the ready runes cover the spell's cost.
function Runes.Enough(name)
	local cost = Runes.COSTS[name]
	local enough = true
	if cost and GetRuneCooldown and GetRuneCooldown(1) ~= nil then
		local ready = { [BLOOD] = 0, [UNHOLY] = 0, [FROST] = 0, [DEATH] = 0 }
		local i = 1
		while i <= MAX_RUNES and GetRuneCooldown(i) ~= nil do
			local _, _, isReady = GetRuneCooldown(i)
			local kind = GetRuneType(i)
			if isReady and ready[kind] then ready[kind] = ready[kind] + 1 end
			i = i + 1
		end
		local short = 0
		for kind, count in pairs(cost) do short = short + math.max(0, count - ready[kind]) end
		enough = short <= ready[DEATH]
	end
	return enough
end
