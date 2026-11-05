local _, NS = ...
local RA = NS.RA

-- Triggers: conditions the secure button can't check (buffs, procs, debuffs, health, power, enemies), written like
-- macro conditions. A ready spell whose trigger is met goes first in the Rotation Button's pick, and a spell whose
-- trigger isn't met is passed over; with Smart Picks that's what a press casts.
--
--   [buff:Freezing Fog]            the player has the buff
--   [nobuff:Horn of Winter]        the player doesn't have the buff
--   [nodebuff:Blood Plague<3]      the target has none of the player's Blood Plague, or it ends within 3 seconds
--   [debuff:Frost Fever>5]         the player's Frost Fever on the target has more than 5 seconds left
--   [noanydebuff:Faerie Fire]      the target has no Faerie Fire from anyone (also for debuffs a server credits
--                                  to someone other than the player, which plain nodebuff never sees)
--   [nocast:Icy Touch]             the player hasn't cast it on this target this fight (for spells with no
--                                  aura to see); [nocast:X>30] also holds when the last one was over 30s ago
--   [power>=40] [hp<35] [targethp<20] [combo>=5]
--   [enemies>=3]                   enemies in the fight (see Enemies.lua)
--   [without:Blood Plague>=1]      enemies in the fight that don't carry your Blood Plague
--   [stacks:Maelstrom Weapon>=5]   stacks of a buff on the player (0 when it's missing)
--   [debuffstacks:Sunder Armor<5]  stacks of the player's debuff on the target; anydebuffstacks counts anyone's
--
-- Terms in a group must all hold; any one group holding is enough ("[buff:A][buff:B]" is A or B).
local Triggers = {}
RA.Triggers = Triggers

local trim = RA.Spells.Trim
local cache = {}

local COMPARE = {
	["<"] = function(a, b) return a < b end,
	["<="] = function(a, b) return a <= b end,
	[">"] = function(a, b) return a > b end,
	[">="] = function(a, b) return a >= b end,
	["="] = function(a, b) return a == b end,
}

-- The aura on the unit (the player's own when it's a debuff) and its seconds left; permanent auras never run out.
-- For cast terms it's whether the player cast it on the current target, and how many seconds ago.
local casts = {}
local function aura(kind, name)
	local present, left
	if kind == "cast" then
		local at = casts[name] and casts[name][UnitGUID("target") or ""]
		present, left = at ~= nil, at and (GetTime() - at)
	else
		local unit, filter = "player", "HELPFUL"
		if kind == "debuff" then unit, filter = "target", "HARMFUL|PLAYER" end
		if kind == "anydebuff" then unit, filter = "target", "HARMFUL" end
		local found, _, _, _, _, _, expires = UnitAura(unit, name, nil, filter)
		present = found ~= nil
		if found then left = (expires and expires > 0) and (expires - GetTime()) or math.huge end
	end
	return present, left
end

local STACKS = {
	stacks = { "player", "HELPFUL" },
	debuffstacks = { "target", "HARMFUL|PLAYER" },
	anydebuffstacks = { "target", "HARMFUL" },
}

-- Stacks of the aura, 0 when it's missing. A single-stack aura reports 0, so it counts as 1.
local function stacks(kind, name)
	local unit, filter = STACKS[kind][1], STACKS[kind][2]
	local found, _, _, count = UnitAura(unit, name, nil, filter)
	return found and math.max(count or 0, 1) or 0
end

-- the target when the cast lands; Smart Picks has put it back by then
local tracker = CreateFrame("Frame")
tracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:SetScript("OnEvent", function(_, event, unit, spell)
	local guid = UnitGUID("target")
	if event == "PLAYER_REGEN_ENABLED" then
		casts = {}
	elseif unit == "player" and spell and guid then
		casts[spell] = casts[spell] or {}
		casts[spell][guid] = GetTime()
	end
end)

local function percent(unit)
	local max = UnitHealthMax(unit) or 0
	return max > 0 and (UnitHealth(unit) / max * 100) or 0
end

local VALUES = {
	power = function() return UnitPower("player") or 0 end,
	hp = function() return percent("player") end,
	targethp = function() return UnitExists("target") and percent("target") or 0 end,
	enemies = function() return RA.Enemies.Count() end,
	combo = function() return GetComboPoints("player", "target") or 0 end,
}

-- One term to a test function, or nil and why it isn't understood.
local function parseTerm(term)
	local test, problem
	local no, kind, rest = term:match("^(n?o?)(%a+):%s*(.+)$")
	local missing, countOp, count = (rest or ""):match("^(.-)%s*([<>=]=?)%s*(%d+%.?%d*)$")
	if no == "" and kind == "without" and missing and COMPARE[countOp] then
		local limit = tonumber(count)
		missing = trim(missing)
		test = function() return COMPARE[countOp](RA.Enemies.Without(missing), limit) end
	elseif kind == "without" then
		problem = ("\"%s\" Needs a Count, Like without:Corruption>=1"):format(term)
	elseif no == "" and STACKS[kind] and missing and COMPARE[countOp] then
		local limit = tonumber(count)
		missing = trim(missing)
		test = function()
			local can = kind == "stacks" or (UnitExists("target") and UnitCanAttack("player", "target"))
			return can and COMPARE[countOp](stacks(kind, missing), limit) == true
		end
	elseif STACKS[kind] then
		problem = ("\"%s\" Needs a Count, Like stacks:Maelstrom Weapon>=5"):format(term)
	elseif kind == "buff" or kind == "debuff" or kind == "anydebuff" or kind == "cast" then
		local negate = no == "no"
		local name, op, number = rest:match("^(.-)%s*([<>]=?)%s*(%d+%.?%d*)$")
		name = trim(name or rest)
		if no ~= "" and not negate then
			problem = ("\"%s\" Isn't a Trigger"):format(term)
		else
			local limit = op and tonumber(number)
			test = function()
				-- debuff and cast terms need an enemy target, so nodebuff doesn't light up with nothing targeted
				local can = kind == "buff" or (UnitExists("target") and UnitCanAttack("player", "target"))
				local present, left = aura(kind, name)
				local holds = present
				if limit then holds = present and COMPARE[op](left, limit) end
				if negate then holds = not present or (limit ~= nil and holds) end
				return can and holds == true
			end
		end
	else
		local key, op, number = term:match("^(%a+)%s*([<>=]=?)%s*(%d+%.?%d*)$")
		if key and VALUES[key] and COMPARE[op] then
			local limit = tonumber(number)
			test = function() return COMPARE[op](VALUES[key](), limit) end
		else
			problem = ("\"%s\" Isn't a Trigger"):format(term)
		end
	end
	return test, problem
end

-- Text to { groups = { { test, ... } }, problems = { text } }; text without brackets is one group.
function Triggers.Parse(text)
	text = trim(text)
	local parsed = cache[text]
	if not parsed then
		parsed = { groups = {}, problems = {} }
		local bodies = {}
		for body in text:gmatch("%[(.-)%]") do bodies[#bodies + 1] = body end
		if #bodies == 0 and text ~= "" then bodies[1] = text end
		for _, body in ipairs(bodies) do
			local group = {}
			for term in body:gmatch("[^,]+") do
				term = trim(term)
				if term ~= "" then
					local test, problem = parseTerm((term:gsub("^%a+", string.lower)))
					if test then group[#group + 1] = test else parsed.problems[#parsed.problems + 1] = problem end
				end
			end
			parsed.groups[#parsed.groups + 1] = group
		end
		cache[text] = parsed
	end
	return parsed
end

-- Whether the trigger is met now. No trigger always is.
function Triggers.Holds(text)
	local parsed = Triggers.Parse(text)
	local holds = #parsed.groups == 0
	for _, group in ipairs(parsed.groups) do
		local all = true
		for _, test in ipairs(group) do
			if all and not test() then all = false end
		end
		if all then holds = true end
	end
	return holds
end

function Triggers.Problems(text)
	return Triggers.Parse(text).problems
end

function Triggers.Has(text)
	return trim(text) ~= ""
end
