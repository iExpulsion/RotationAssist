local _, NS = ...
local RA = NS.RA

-- Triggers: conditions the secure button can't check (buffs, procs, debuffs, health, power, enemies), written like
-- macro conditions. A ready spell whose trigger is met goes first in the Rotation Button's pick, and a spell whose
-- trigger isn't met is passed over; with Smart Picks that's what a press casts.
--
--   [buff:Freezing Fog]            the player has the buff
--   [nobuff:Horn of Winter]        the player doesn't have the buff
--   [noselfdebuff:Weakened Soul]   the player doesn't have the debuff, from anyone
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

local trim, lower, findAura = RA.Spells.Trim, RA.Spells.Lower, RA.Spells.FindAura
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
		local key = lower[name]
		local at = casts[key] and casts[key][UnitGUID("target") or ""]
		present, left = at ~= nil, at and (GetTime() - at)
	else
		local unit, filter = "player", "HELPFUL"
		if kind == "debuff" then unit, filter = "target", "HARMFUL|PLAYER" end
		if kind == "anydebuff" then unit, filter = "target", "HARMFUL" end
		if kind == "selfdebuff" then filter = "HARMFUL" end
		local found, _, expires = findAura(unit, name, filter)
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
	local found, count = findAura(unit, name, filter)
	return found and math.max(count or 0, 1) or 0
end

-- the target when the cast lands; Smart Picks has put it back by then
local tracker = CreateFrame("Frame")
tracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:SetScript("OnEvent", function(_, event, unit, spell)
	-- this fires for every unit's casts, so the target is only looked up for the player's
	local guid = event ~= "PLAYER_REGEN_ENABLED" and unit == "player" and spell and UnitGUID("target")
	if event == "PLAYER_REGEN_ENABLED" then
		casts = {}
	elseif guid then
		local key = lower[spell]
		casts[key] = casts[key] or {}
		casts[key][guid] = GetTime()
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

-- The kinds of term, in the order the trigger builder lists them. shape: "aura" (has it or not, and optionally its
-- time left, or for cast the seconds since), "count" (a name and a count to compare) or "value" (a number).
Triggers.TERMS = {
	{ kind = "buff", shape = "aura", label = "Buff on You" },
	{ kind = "selfdebuff", shape = "aura", label = "Debuff on You" },
	{ kind = "debuff", shape = "aura", label = "Your Debuff on the Target" },
	{ kind = "anydebuff", shape = "aura", label = "Anyone's Debuff on the Target" },
	{ kind = "cast", shape = "aura", label = "Your Cast on the Target" },
	{ kind = "stacks", shape = "count", label = "Stacks of a Buff on You" },
	{ kind = "debuffstacks", shape = "count", label = "Stacks of Your Debuff" },
	{ kind = "anydebuffstacks", shape = "count", label = "Stacks of Anyone's Debuff" },
	{ kind = "power", shape = "value", label = "Your Power" },
	{ kind = "hp", shape = "value", label = "Your Health %" },
	{ kind = "targethp", shape = "value", label = "Target's Health %" },
	{ kind = "combo", shape = "value", label = "Combo Points" },
	{ kind = "enemies", shape = "value", label = "Enemies in the Fight" },
	{ kind = "without", shape = "count", label = "Enemies Without Your Aura" },
}
local SHAPES = {}
for _, t in ipairs(Triggers.TERMS) do SHAPES[t.kind] = t.shape end
Triggers.SHAPES = SHAPES

-- One term's text to its parts { kind, no, name, op, value }, or nil and why it isn't understood. Aura terms
-- compare their time with < <= > >= only; "=" there is part of the name, as it always was.
local function readTerm(term)
	local parts, problem
	local no, kind, rest = term:match("^(n?o?)(%a+):%s*(.+)$")
	local name, op, number = (rest or ""):match("^(.-)%s*([<>=]=?)%s*(%d+%.?%d*)$")
	local shape = SHAPES[kind]
	if shape == "count" and no == "" and name and COMPARE[op] then
		parts = { kind = kind, name = trim(name), op = op, value = tonumber(number) }
	elseif kind == "without" then
		problem = ("\"%s\" Needs a Count, Like without:Corruption>=1"):format(term)
	elseif shape == "count" then
		problem = ("\"%s\" Needs a Count, Like stacks:Maelstrom Weapon>=5"):format(term)
	elseif shape == "aura" and (no == "" or no == "no") then
		local timed = name and op ~= "=" and COMPARE[op]
		parts = { kind = kind, no = no == "no", name = trim(timed and name or rest), op = timed and op or nil, value = timed and tonumber(number) or nil }
	else
		local key, valueOp, valueNumber = term:match("^(%a+)%s*([<>=]=?)%s*(%d+%.?%d*)$")
		if key and SHAPES[key] == "value" and COMPARE[valueOp] then
			parts = { kind = key, op = valueOp, value = tonumber(valueNumber) }
		else
			problem = ("\"%s\" Isn't a Trigger"):format(term)
		end
	end
	return parts, problem
end

-- A term's parts to its test function.
local function compile(p)
	local test
	local kind, name, op, limit = p.kind, p.name, p.op, p.value
	if kind == "without" then
		test = function() return COMPARE[op](RA.Enemies.Without(name), limit) end
	elseif SHAPES[kind] == "count" then
		test = function()
			local can = kind == "stacks" or (UnitExists("target") and UnitCanAttack("player", "target"))
			return can and COMPARE[op](stacks(kind, name), limit) == true
		end
	elseif SHAPES[kind] == "aura" then
		local negate = p.no
		test = function()
			-- debuff and cast terms need an enemy target, so nodebuff doesn't light up with nothing targeted
			local can = kind == "buff" or kind == "selfdebuff" or (UnitExists("target") and UnitCanAttack("player", "target"))
			local present, left = aura(kind, name)
			local holds = present
			if op then holds = present and COMPARE[op](left, limit) end
			if negate then holds = not present or (op ~= nil and holds) end
			return can and holds == true
		end
	else
		test = function() return COMPARE[op](VALUES[kind](), limit) end
	end
	return test
end

local OUTSIDE = "Text Outside the Brackets: [a, b] Means And, [a][b] Means Or"

-- Trimmed text to its bracket groups' bodies, and whether there's text outside them; text without brackets is one
-- group.
local function bodiesOf(text)
	local bodies = {}
	for body in text:gmatch("%[(.-)%]") do bodies[#bodies + 1] = body end
	if #bodies == 0 and text ~= "" then bodies[1] = text end
	return bodies, #bodies > 0 and text:gsub("%[.-%]", ""):match("%S") ~= nil
end

-- A group's body to its terms' texts, the leading word in lower case ("Buff:X" reads as buff).
local function termsOf(body)
	local terms = {}
	for term in body:gmatch("[^,]+") do
		term = trim(term)
		if term ~= "" then terms[#terms + 1] = (term:gsub("^%a+", string.lower)) end
	end
	return terms
end

-- Trimmed text to { groups = { { test, ... } }, problems = { text } }.
local function build(text)
	local parsed = { groups = {}, problems = {} }
	local bodies, outside = bodiesOf(text)
	if outside then parsed.problems[#parsed.problems + 1] = OUTSIDE end
	for _, body in ipairs(bodies) do
		local group = {}
		for _, term in ipairs(termsOf(body)) do
			local parts, problem = readTerm(term)
			if parts then group[#group + 1] = compile(parts) else parsed.problems[#parsed.problems + 1] = problem end
		end
		parsed.groups[#parsed.groups + 1] = group
	end
	return parsed
end

-- Trigger text to groups of term parts for the builder ({} for none), or nil and why when it can't be shown that
-- way: a term it doesn't understand, text outside the brackets, or an empty group (which always holds).
function Triggers.Read(text)
	local bodies, outside = bodiesOf(trim(text))
	local groups, problem = {}, outside and OUTSIDE or nil
	for _, body in ipairs(bodies) do
		local group = {}
		for _, term in ipairs(termsOf(body)) do
			local parts, why = readTerm(term)
			if parts then group[#group + 1] = parts else problem = problem or why end
		end
		if #group == 0 then problem = problem or "An Empty Group [] Always Holds" end
		groups[#groups + 1] = group
	end
	return (not problem) and groups or nil, problem
end

local function number(v)
	return v == math.floor(v) and ("%d"):format(v) or tostring(v)
end

-- Whether a term has everything it needs to be written: a name where its kind takes one, and a number where it
-- compares.
function Triggers.Complete(p)
	local shape = SHAPES[p.kind]
	local named = shape == "value" or trim(p.name) ~= ""
	local counted = (shape == "aura" and not p.op) or (COMPARE[p.op] ~= nil and type(p.value) == "number")
	return shape ~= nil and named and counted
end

function Triggers.WriteTerm(p)
	local shape = SHAPES[p.kind]
	local compare = p.op and (p.op .. number(p.value)) or ""
	local text
	if shape == "value" then
		text = p.kind .. compare
	elseif shape == "count" then
		text = p.kind .. ":" .. trim(p.name) .. compare
	else
		text = (p.no and "no" or "") .. p.kind .. ":" .. trim(p.name) .. compare
	end
	return text
end

-- Groups of term parts back to trigger text, leaving out terms that aren't filled in and groups left empty.
function Triggers.Write(groups)
	local out = {}
	for _, group in ipairs(groups or {}) do
		local terms = {}
		for _, p in ipairs(group) do
			if Triggers.Complete(p) then terms[#terms + 1] = Triggers.WriteTerm(p) end
		end
		if #terms > 0 then out[#out + 1] = "[" .. table.concat(terms, ", ") .. "]" end
	end
	return table.concat(out)
end

local COUNT_WORDS = {
	["<"] = "fewer than %s", ["<="] = "%s or fewer", [">"] = "more than %s", [">="] = "%s or more", ["="] = "exactly %s",
}
local VALUE_WORDS = {
	["<"] = "under %s", ["<="] = "%s or less", [">"] = "over %s", [">="] = "%s or more", ["="] = "exactly %s",
}
local TIME_WORDS = {
	["<"] = "under %s seconds", ["<="] = "%s seconds or less", [">"] = "over %s seconds", [">="] = "%s seconds or more",
}

local AURA_SAYS = {
	buff = { "you have %s", "you don't have %s" },
	selfdebuff = { "you have the debuff %s", "you don't have the debuff %s" },
	debuff = { "the target has your %s", "the target doesn't have your %s" },
	anydebuff = { "the target has %s from anyone", "the target has no %s from anyone" },
	cast = { "you've cast %s on this target this fight", "you haven't cast %s on this target this fight" },
}
local COUNT_SAYS = {
	stacks = "you have %s stacks of %s",
	debuffstacks = "the target has %s stacks of your %s",
	anydebuffstacks = "the target has %s stacks of %s from anyone",
	without = "%s enemies in the fight don't have your %s",
}
local VALUE_SAYS = {
	power = "your power is %s",
	hp = "your health is %s%%",
	targethp = "the target's health is %s%%",
	combo = "you have %s combo points",
	enemies = "%s enemies are in the fight",
}

-- One term in plain English, starting in lower case.
function Triggers.DescribeTerm(p)
	local shape, text = SHAPES[p.kind], nil
	if shape == "aura" then
		local time = p.op and TIME_WORDS[p.op]:format(number(p.value))
		text = AURA_SAYS[p.kind][p.no and 2 or 1]:format(p.name)
		if time and p.kind == "cast" then
			text = text .. (p.no and (", or did " .. time .. " ago") or (", " .. time .. " ago"))
		elseif time then
			text = text .. (p.no and (", or it has " .. time .. " left") or (" with " .. time .. " left"))
		end
	elseif shape == "count" then
		text = COUNT_SAYS[p.kind]:format(COUNT_WORDS[p.op]:format(number(p.value)), p.name)
	else
		text = VALUE_SAYS[p.kind]:format(VALUE_WORDS[p.op]:format(number(p.value)))
	end
	return text
end

local function capital(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- A trigger in plain English, from its text or its groups: one sentence, or a line per group when any of several
-- will do. nil when there's no trigger or it can't be read.
function Triggers.Describe(trigger)
	local groups = type(trigger) == "table" and trigger or Triggers.Read(trigger)
	local lines = {}
	for _, group in ipairs(groups or {}) do
		local terms = {}
		for _, p in ipairs(group) do
			if Triggers.Complete(p) then terms[#terms + 1] = Triggers.DescribeTerm(p) end
		end
		if #terms > 0 then lines[#lines + 1] = table.concat(terms, " and ") end
	end
	local text
	if #lines == 1 then
		text = "When " .. lines[1] .. "."
	elseif #lines > 1 then
		for i, line in ipairs(lines) do lines[i] = "- " .. capital(line) end
		text = "When any of these holds:\n" .. table.concat(lines, "\n")
	end
	return text
end

-- A trigger as parsed, kept for the next time: the rotation checks the same triggers many times a second.
function Triggers.Parse(text)
	text = trim(text)
	local parsed = cache[text] or build(text)
	cache[text] = parsed
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

-- The editor checks every partial text typed, so those aren't kept.
function Triggers.Problems(text)
	local trimmed = trim(text)
	return (cache[trimmed] or build(trimmed)).problems
end

function Triggers.Has(text)
	return trim(text) ~= ""
end
