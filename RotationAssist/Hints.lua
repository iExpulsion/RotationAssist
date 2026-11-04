local _, NS = ...
local RA = NS.RA

-- Hints: conditions the secure button can't check (buffs, procs, debuffs, health, power), written like macro
-- conditions. They only change what the Rotation Button suggests; what a press casts stays the same.
--
--   [buff:Freezing Fog]            the player has the buff
--   [nobuff:Horn of Winter]        the player doesn't have the buff
--   [nodebuff:Blood Plague<3]      the target has none of the player's Blood Plague, or it ends within 3 seconds
--   [debuff:Frost Fever>5]         the player's Frost Fever on the target has more than 5 seconds left
--   [power>=40] [hp<35] [targethp<20]
--
-- Terms in a group must all hold; any one group holding is enough ("[buff:A][buff:B]" is A or B).
local Hints = {}
RA.Hints = Hints

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
local function aura(kind, name)
	local unit, filter = "player", "HELPFUL"
	if kind == "debuff" then unit, filter = "target", "HARMFUL|PLAYER" end
	local found, _, _, _, _, _, expires = UnitAura(unit, name, nil, filter)
	local left
	if found then left = (expires and expires > 0) and (expires - GetTime()) or math.huge end
	return found ~= nil, left
end

local function percent(unit)
	local max = UnitHealthMax(unit) or 0
	return max > 0 and (UnitHealth(unit) / max * 100) or 0
end

local VALUES = {
	power = function() return UnitPower("player") or 0 end,
	hp = function() return percent("player") end,
	targethp = function() return UnitExists("target") and percent("target") or 0 end,
}

-- One term to a test function, or nil and why it isn't understood.
local function parseTerm(term)
	local test, problem
	local no, kind, rest = term:match("^(n?o?)(%a+):%s*(.+)$")
	if kind == "buff" or kind == "debuff" then
		local negate = no == "no"
		local name, op, number = rest:match("^(.-)%s*([<>]=?)%s*(%d+%.?%d*)$")
		name = trim(name or rest)
		if no ~= "" and not negate then
			problem = ("\"%s\" Isn't a Hint"):format(term)
		else
			local limit = op and tonumber(number)
			test = function()
				-- debuff terms need an enemy target, so nodebuff doesn't light up with nothing targeted
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
			problem = ("\"%s\" Isn't a Hint"):format(term)
		end
	end
	return test, problem
end

-- Text to { groups = { { test, ... } }, problems = { text } }; text without brackets is one group.
function Hints.Parse(text)
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

-- Whether the hint holds now. No hint always holds.
function Hints.Holds(text)
	local parsed = Hints.Parse(text)
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

function Hints.Problems(text)
	return Hints.Parse(text).problems
end

function Hints.Has(text)
	return trim(text) ~= ""
end
