local _, NS = ...
local RA = NS.RA

-- Turns a rotation's modes into macro text for the secure button. Each mode is one priority macro: off-GCD lines
-- first, then the rest in order. A /cast that can't happen (on cooldown, short on resources, not lit, out of range)
-- fails and the next line runs; the first one that casts starts the global cooldown, so the lines after it fail.
local Compiler = {}
RA.Compiler = Compiler

Compiler.MAX_MACRO, Compiler.MAX_LINE = 1023, 255
Compiler.STEP_BUTTON = "RotationAssistStep"

local trim = RA.Spells.Trim

-- The client's lookups by default; tests pass their own.
Compiler.env = {
	name = function(spell) return RA.Spells.Name(spell) end,
	known = function(name) return RA.Spells.Known(name) end,
}

-- Adds a condition to every [group] of a macro condition ("[harm][@focus]" + "nochanneling" ->
-- "[harm,nochanneling][@focus,nochanneling]"). No groups means always, so the result is just "[extra]".
function Compiler.Merge(when, extra)
	when = trim(when)
	local out = when
	if extra then
		local groups = {}
		for g in when:gmatch("%[(.-)%]") do
			g = trim(g)
			groups[#groups + 1] = "[" .. (g == "" and extra or (g .. "," .. extra)) .. "]"
		end
		out = #groups > 0 and table.concat(groups) or ("[" .. extra .. "]")
	end
	return out
end

-- The unit a condition casts on when it names one other than the target ("[@player]", "[target=focus]"), else nil.
function Compiler.Unit(when)
	local unit
	for g in trim(when):gmatch("%[(.-)%]") do
		local named = g:match("@%s*([%w]+)") or g:match("target%s*=%s*([%w]+)")
		if not unit and named and named:lower() ~= "target" then unit = named:lower() end
	end
	return unit
end

local function command(verb, cond, rest)
	return verb .. " " .. (cond ~= "" and (cond .. " ") or "") .. rest
end

-- A Steps line that isn't a slash command is a spell name to cast.
local function stepLine(line)
	line = trim(line)
	return (line:sub(1, 1) == "/" or line == "") and line or ("/cast " .. line)
end

-- One mode to { text, lines, status = { [actionIndex] = "ok" | "skipped" | "partial" }, skipped = { names },
-- casts = { { index, kind, name, cond, offGcd } }, steps = { { lines } }, warnings = { text } }. Steps blocks get
-- step buttons numbered from firstStep.
function Compiler.CompileMode(rotation, mode, env, firstStep)
	env = env or Compiler.env
	local options = rotation.options or {}
	local guard = options.channels and "nochanneling" or nil
	local smart = options.smart
	local result = { lines = {}, status = {}, skipped = {}, casts = {}, steps = {}, solo = {}, warnings = {}, smart = smart }
	local early, late, gates, earlyGates, soloClicks = {}, {}, {}, {}, {}

	-- Smart Picks gates each GCD line on [exists]: at press time the addon clears the target for every line but
	-- the one it picked, so only that one can cast. An off-GCD spell with a trigger is gated the same way, unless it
	-- casts on another unit, which clearing the target can't stop
	local function gated(action)
		local triggered = action.kind == "spell" and trim(action.trigger or "") ~= "" and not Compiler.Unit(action.when)
		return smart and (not action.offGcd or triggered)
	end

	local function condition(action, when)
		local cond = Compiler.Merge(when, guard)
		if gated(action) then cond = Compiler.Merge(cond, "exists") end
		return cond
	end

	local function emit(action, line, index)
		local into = action.offGcd and early or late
		into[#into + 1] = line
		if index and gated(action) then (action.offGcd and earlyGates or gates)[#into] = index end
	end

	-- A gated line that casts on another unit ([@player]) can't be stopped by clearing the target, since its
	-- [exists] checks that unit, so the cast goes on a step button behind a /click gated on the target instead.
	-- With no target there's nothing to clear, so it also gets a solo button, blank until Smart Picks fills in its
	-- pick out of combat (for buffing before a pull)
	local function emitCast(action, verb, rest, index)
		local unit = Compiler.Unit(action.when)
		if smart and unit and not action.offGcd then
			local line = command(verb, Compiler.Merge(action.when, guard), rest)
			local number = firstStep + #result.steps
			result.steps[#result.steps + 1] = { lines = { line } }
			emit(action, command("/click", condition(action, ""), Compiler.STEP_BUTTON .. number), index)
			result.steps[#result.steps + 1] = { lines = {}, solo = line }
			result.solo[#result.solo + 1] = { index = index, button = number + 1, line = line }
			soloClicks[#soloClicks + 1] = "/click [noexists] " .. Compiler.STEP_BUTTON .. (number + 1)
		else
			emit(action, command(verb, condition(action, action.when), rest), index)
		end
		return unit
	end

	for index, action in ipairs(mode.actions or {}) do
		local status = "ok"
		if action.kind == "spell" then
			local name = env.name(action.spell)
			if name and env.known(name) then
				local cond = Compiler.Merge(action.when, guard)
				local unit = emitCast(action, "/cast", name, index)
				result.casts[#result.casts + 1] = { index = index, kind = "spell", name = name, cond = cond, unit = unit, offGcd = action.offGcd, moving = action.moving, keep = action.keep, trigger = trim(action.trigger) }
			else
				status = "skipped"
				result.skipped[#result.skipped + 1] = name or ("#" .. tostring(action.spell))
			end
		elseif action.kind == "sequence" then
			local names, missing = {}, 0
			for _, spell in ipairs(action.spells or {}) do
				local name = env.name(spell)
				if name and env.known(name) then
					names[#names + 1] = name
				else
					missing = missing + 1
					result.skipped[#result.skipped + 1] = name or ("#" .. tostring(spell))
				end
			end
			if #names > 0 then
				-- a step no spell is named after never casts, so the sequence waits on it until it resets
				if action.once then names[#names + 1] = "null" end
				local reset = trim(action.reset)
				local cond = Compiler.Merge(action.when, guard)
				local unit = emitCast(action, "/castsequence", (reset ~= "" and ("reset=" .. reset .. " ") or "") .. table.concat(names, ", "), index)
				result.casts[#result.casts + 1] = { index = index, kind = "sequence", name = names[1], cond = cond, unit = unit, once = action.once }
				status = missing > 0 and "partial" or "ok"
			else
				status = "skipped"
			end
		elseif action.kind == "steps" then
			local lines = {}
			for _, line in ipairs(action.steps or {}) do
				local text = stepLine(line)
				if text ~= "" then lines[#lines + 1] = text end
			end
			if #lines > 0 then
				local number = firstStep + #result.steps
				result.steps[#result.steps + 1] = { lines = lines }
				emit(action, command("/click", condition(action, ""), Compiler.STEP_BUTTON .. number), index)
				result.casts[#result.casts + 1] = { index = index, kind = "steps" }
			else
				status = "skipped"
			end
		else
			local any = false
			for line in (action.text or ""):gmatch("[^\n]+") do
				line = trim(line)
				if line ~= "" then
					any = true
					emit(action, line)
				end
			end
			status = any and "ok" or "skipped"
		end
		result.status[index] = status
	end

	local lines = result.lines
	local attackLines = {}
	if options.attack then attackLines[#attackLines + 1] = "/startattack [harm,nodead]" end
	if options.pet then attackLines[#attackLines + 1] = "/petattack [harm,nodead]" end
	if options.target then lines[#lines + 1] = "/targetenemy [noharm][dead]" end
	local smartPress = smart and (#late > 0 or next(earlyGates) ~= nil)
	-- with Smart Picks, clearing the target stops auto-attack, so attacking comes last
	if not smartPress then
		for _, line in ipairs(attackLines) do lines[#lines + 1] = line end
		for _, line in ipairs(early) do lines[#lines + 1] = line end
	end
	local function addGated(from, gateOf)
		for i, line in ipairs(from) do
			if gateOf[i] then
				lines[#lines + 1] = ("/run RAGate(%d)"):format(gateOf[i])
				lines[#lines + 1] = line
				lines[#lines + 1] = "/targetlasttarget [noexists]"
			else
				lines[#lines + 1] = line
			end
		end
	end
	if smartPress then
		-- with no target, /targetlasttarget would grab an old one, so the gated lines need a target to start with
		lines[#lines + 1] = "/run RAPick()"
		for _, line in ipairs(soloClicks) do lines[#lines + 1] = line end
		lines[#lines + 1] = "/stopmacro [noexists]"
		addGated(late, gates)
		-- off-GCD lines come after every gate, since clearing the target stops auto-attack, and that drops a queued
		-- next-swing attack like Heroic Strike
		addGated(early, earlyGates)
		for _, line in ipairs(attackLines) do lines[#lines + 1] = line end
	elseif options.cycle and #late > 0 then
		-- One Spell per Press: the GCD lines go on a step button in GSE's priority order (1, 1 2, 1 2 3, ...), since
		-- a press stops at the first GCD spell that isn't ready
		local order = {}
		for i = 1, #late do
			for j = 1, i do order[#order + 1] = late[j] end
		end
		local number = firstStep + #result.steps
		result.steps[#result.steps + 1] = { lines = order, cycle = true }
		lines[#lines + 1] = "/click " .. Compiler.STEP_BUTTON .. number
	else
		for _, line in ipairs(late) do lines[#lines + 1] = line end
	end
	result.text = table.concat(lines, "\n")

	if #early + #late == 0 then result.warnings[#result.warnings + 1] = "Nothing to Cast in This Mode" end
	if #result.text > Compiler.MAX_MACRO then
		result.warnings[#result.warnings + 1] = ("Over %d Characters, So the End May Not Run"):format(Compiler.MAX_MACRO)
	end
	local long = false
	for _, line in ipairs(lines) do
		if #line > Compiler.MAX_LINE then long = true end
	end
	if long then result.warnings[#result.warnings + 1] = ("A Line Is Over %d Characters"):format(Compiler.MAX_LINE) end
	return result
end

-- Mode numbers a condition rule names ("[form:3] 2; 1"), with any that aren't modes.
function Compiler.RuleModes(rule, count)
	local named, bad = {}, {}
	for clause in (rule or ""):gmatch("[^;]+") do
		local value = trim(clause:gsub("%b[]", ""))
		local n = tonumber(value)
		if value ~= "" then
			if n and n >= 1 and n <= count and n == math.floor(n) then named[#named + 1] = n else bad[#bad + 1] = value end
		end
	end
	return named, bad
end

-- Every mode, plus how modes switch: { modes = { result }, steps = { { lines } }, toggle = { enter = { [mode] =
-- macro } } or nil, rule = text or nil, warnings }.
function Compiler.Compile(rotation, env)
	env = env or Compiler.env
	local out = { modes = {}, steps = {}, warnings = {} }
	for i, mode in ipairs(rotation.modes or {}) do
		local result = Compiler.CompileMode(rotation, mode, env, #out.steps + 1)
		out.modes[i] = result
		for _, step in ipairs(result.steps) do out.steps[#out.steps + 1] = step end
	end
	local count = #out.modes
	local switch = rotation.switch or { kind = "none" }
	if switch.kind == "toggle" and count > 1 then
		local enter = {}
		local name = switch.spell and env.name(switch.spell)
		if name and env.known(name) then
			enter[1] = "/cancelaura " .. name
			enter[2] = "/cast " .. name
		elseif name then
			out.warnings[#out.warnings + 1] = ("%s Isn't Known, So the Mode Key Only Switches Modes"):format(name)
		end
		out.toggle = { enter = enter, spell = name }
	elseif switch.kind == "rule" and count > 1 then
		local rule = trim(switch.rule)
		local named, bad = Compiler.RuleModes(rule, count)
		if rule == "" or #named == 0 then
			out.warnings[#out.warnings + 1] = "The Condition Rule Names No Mode"
		else
			out.rule = rule
		end
		for _, value in ipairs(bad) do
			out.warnings[#out.warnings + 1] = ("The Condition Rule's \"%s\" Isn't a Mode Number"):format(value)
		end
	end
	return out
end

-- Conditions: an action's macro conditions ("[@focus,harm][]"), read into groups of terms for the conditions
-- builder and written back. Each term is { kind, no, arg, key }: key keeps the word as written ("form" for stance,
-- "target=" for @), so text read and written back says the same. Terms the builder has no row for read as "other",
-- kept as typed.
local Conditions = {}
RA.Conditions = Conditions

local UNITS = {
	{ value = "target", text = "Your Target", says = "your target" },
	{ value = "player", text = "Yourself", says = "you" },
	{ value = "focus", text = "Your Focus", says = "your focus" },
	{ value = "mouseover", text = "Unit Under the Mouse", says = "the unit under the mouse" },
	{ value = "targettarget", text = "Target's Target", says = "your target's target" },
	{ value = "pet", text = "Your Pet", says = "your pet" },
	{ value = "playerlocation", text = "Ground at Your Feet", says = "the ground where you stand" },
	{ value = "cursor", text = "Ground at the Mouse", says = "the ground at the mouse" },
}
local UNIT_SAYS = {}
for _, u in ipairs(UNITS) do UNIT_SAYS[u.value] = u.says end

-- The builder's rows, in its order. arg: nil (none), "choice" (one of choices), "text" (optional) or "required".
-- yes/no say the term, with %s the unit for unit terms, else the arg; anyYes/anyNo say it with no arg. fixed: can't
-- be turned around with "no".
Conditions.TERMS = {
	{ kind = "unit", label = "Cast On", arg = "choice", choices = UNITS, fixed = true },
	{ kind = "harm", label = "Unit Is an Enemy", unit = true, yes = "%s is an enemy", no = "%s isn't an enemy" },
	{ kind = "help", label = "Unit Is Friendly", unit = true, yes = "%s is friendly", no = "%s isn't friendly" },
	{ kind = "exists", label = "Unit Exists", unit = true, yes = "%s exists", no = "there's no %s" },
	{ kind = "dead", label = "Unit Is Dead", unit = true, yes = "%s is dead", no = "%s is alive" },
	{ kind = "combat", label = "In Combat", yes = "you're in combat", no = "you're out of combat" },
	{ kind = "mod", label = "Holding a Key", arg = "choice", aliases = { "modifier" },
		choices = { { value = "", text = "Any Key" }, { value = "shift", text = "Shift" }, { value = "ctrl", text = "Ctrl" }, { value = "alt", text = "Alt" } },
		yes = "you hold %s", no = "you don't hold %s", anyYes = "you hold a modifier key", anyNo = "you hold no modifier key" },
	{ kind = "stance", label = "Stance or Form", arg = "text", aliases = { "form" }, placeholder = "1, or 1/2",
		yes = "you're in stance %s", no = "you're not in stance %s", anyYes = "you're in a stance or form", anyNo = "you're in no stance or form" },
	{ kind = "stealth", label = "Stealthed", yes = "you're stealthed", no = "you're not stealthed" },
	{ kind = "mounted", label = "Mounted", yes = "you're mounted", no = "you're not mounted" },
	{ kind = "flying", label = "Flying", yes = "you're flying", no = "you're not flying" },
	{ kind = "swimming", label = "Swimming", yes = "you're swimming", no = "you're not swimming" },
	{ kind = "flyable", label = "Can Fly Here", yes = "you can fly here", no = "you can't fly here" },
	{ kind = "indoors", label = "Indoors", yes = "you're indoors", no = "you're not indoors" },
	{ kind = "outdoors", label = "Outdoors", yes = "you're outdoors", no = "you're not outdoors" },
	{ kind = "channeling", label = "Channeling", arg = "text", placeholder = "Any, or a Spell",
		yes = "you're channeling %s", no = "you're not channeling %s", anyYes = "you're channeling", anyNo = "you're not channeling" },
	{ kind = "pet", label = "Have a Pet", arg = "text", placeholder = "Any, or a Name",
		yes = "your pet is %s", no = "your pet isn't %s", anyYes = "you have a pet", anyNo = "you have no pet" },
	{ kind = "group", label = "In a Group", arg = "choice",
		choices = { { value = "", text = "Any Group" }, { value = "party", text = "Party" }, { value = "raid", text = "Raid" } },
		yes = "you're in a %s", no = "you're not in a %s", anyYes = "you're in a group", anyNo = "you're not in a group" },
	{ kind = "spec", label = "Talent Spec", arg = "choice",
		choices = { { value = "1", text = "Spec 1" }, { value = "2", text = "Spec 2" } },
		yes = "you're in talent spec %s", no = "you're not in talent spec %s" },
	{ kind = "equipped", label = "Equipped", arg = "required", aliases = { "worn" }, placeholder = "Like Shields",
		yes = "you have %s equipped", no = "you don't have %s equipped" },
	{ kind = "always", label = "Otherwise (Always)", fixed = true },
	{ kind = "other", label = "Other (Typed)", arg = "required", fixed = true, placeholder = "Like actionbar:2" },
}
local DEFS, ALIASES = {}, {}
for _, t in ipairs(Conditions.TERMS) do
	DEFS[t.kind] = t
	ALIASES[t.kind] = t.kind
	for _, a in ipairs(t.aliases or {}) do ALIASES[a] = t.kind end
end
Conditions.DEFS = DEFS

-- One term's text to its parts. A unit is "@unit" or "target=unit"; anything unknown is kept as "other".
local function readCondition(term)
	local at = term:match("^@%s*(%S+)$")
	local eq = term:lower():match("^target%s*=%s*(%S+)$")
	local parts
	if at or eq then
		parts = { kind = "unit", arg = (at or eq):lower(), key = eq and "target=" or nil }
	else
		local word, arg = term:match("^(%a+)%s*:%s*(.-)$")
		word = (word or term):lower()
		local no, kind = false, ALIASES[word]
		if not kind and word:sub(1, 2) == "no" and ALIASES[word:sub(3)] then
			no, kind, word = true, ALIASES[word:sub(3)], word:sub(3)
		end
		local def = DEFS[kind]
		if def and not def.fixed and (arg == nil or def.arg ~= nil) then
			parts = { kind = kind, no = no or nil, arg = trim(arg), key = word ~= kind and word or nil }
		else
			parts = { kind = "other", arg = term }
		end
	end
	return parts
end

-- Condition text to groups of terms ({} for none; "[]" is a group holding only "always"), or nil and why when the
-- builder can't show it: text outside the brackets, which the macro would ignore or misread.
function Conditions.Read(text)
	text = trim(text)
	local groups = {}
	local problem = text:gsub("%[.-%]", ""):match("%S") and "Text Outside the Brackets: [a,b] Means And, [a][b] Means Or" or nil
	for body in text:gmatch("%[(.-)%]") do
		local group = {}
		for term in body:gmatch("[^,]+") do
			term = trim(term)
			if term ~= "" then group[#group + 1] = readCondition(term) end
		end
		if #group == 0 then group[1] = { kind = "always" } end
		groups[#groups + 1] = group
	end
	return (not problem) and groups or nil, problem
end

-- Whether a term has what it needs to be written.
function Conditions.Complete(p)
	local def = DEFS[p.kind]
	local needs = def ~= nil and (def.arg == "required" or p.kind == "unit")
	return def ~= nil and (not needs or trim(p.arg) ~= "")
end

function Conditions.WriteTerm(p)
	local arg, text = trim(p.arg), ""
	if p.kind == "unit" then
		text = (p.key == "target=" and "target=" or "@") .. arg
	elseif p.kind == "other" then
		text = arg
	elseif p.kind ~= "always" then
		text = (p.no and "no" or "") .. (p.key or p.kind) .. (arg ~= "" and (":" .. arg) or "")
	end
	return text
end

-- Groups back to condition text, in row order with no spaces (a macro is short on room). Unfinished terms are left
-- out; a group left with only "always" is "[]", and one left with nothing is dropped.
function Conditions.Write(groups)
	local out = {}
	for _, group in ipairs(groups or {}) do
		local terms, always = {}, false
		for _, p in ipairs(group) do
			if p.kind == "always" then always = true end
			if p.kind ~= "always" and Conditions.Complete(p) then terms[#terms + 1] = Conditions.WriteTerm(p) end
		end
		if #terms > 0 or always then out[#out + 1] = "[" .. table.concat(terms, ",") .. "]" end
	end
	return table.concat(out)
end

-- One term in plain English, starting in lower case; unit is the unit the group casts on.
function Conditions.DescribeTerm(p, unit)
	local def, arg = DEFS[p.kind], trim(p.arg)
	local text
	if p.kind == "other" then
		text = arg
	elseif def.unit then
		text = (p.no and def.no or def.yes):format(UNIT_SAYS[unit] or unit)
	elseif arg == "" and def.anyYes then
		text = p.no and def.anyNo or def.anyYes
	elseif def.arg then
		local shown = arg
		for _, c in ipairs(def.choices or {}) do
			if c.value ~= "" and c.value == arg:lower() then shown = c.text end
		end
		text = (p.no and def.no or def.yes):format(shown)
	else
		text = p.no and def.no or def.yes
	end
	return text
end

local function describeGroup(group)
	local unit, named, terms = "target", false, {}
	for _, p in ipairs(group) do
		if p.kind == "unit" and Conditions.Complete(p) then unit, named = trim(p.arg):lower(), true end
	end
	for _, p in ipairs(group) do
		if p.kind ~= "unit" and p.kind ~= "always" and Conditions.Complete(p) then terms[#terms + 1] = Conditions.DescribeTerm(p, unit) end
	end
	local on = named and ("on " .. (UNIT_SAYS[unit] or unit)) or nil
	local when = #terms > 0 and ("when " .. table.concat(terms, " and ")) or nil
	return on and when and (on .. ", " .. when) or on or when or "otherwise"
end

local function capital(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- Conditions in plain English, from their text or groups; nil when they can't be read. No conditions always hold.
-- compact: one paragraph instead of a line per group, for a small space.
function Conditions.Describe(conditions, compact)
	local groups = conditions
	if type(conditions) ~= "table" then groups = Conditions.Read(conditions) end
	local lines = {}
	for _, group in ipairs(groups or {}) do lines[#lines + 1] = describeGroup(group) end
	local text
	if groups and #lines == 0 then
		text = "Always, on your target."
	elseif #lines == 1 then
		text = capital(lines[1]) .. "."
	elseif #lines > 1 and compact then
		for i = 2, #lines do lines[i] = lines[i] == "otherwise" and "otherwise always" or ("otherwise " .. lines[i]) end
		text = capital(table.concat(lines, "; ")) .. "."
	elseif #lines > 1 then
		for i, line in ipairs(lines) do lines[i] = "- " .. capital(line) end
		text = "The first of these that holds:\n" .. table.concat(lines, "\n")
	end
	return text
end
