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
	local result = { lines = {}, status = {}, skipped = {}, casts = {}, steps = {}, warnings = {}, smart = smart }
	local early, late, gates = {}, {}, {}

	-- Smart Picks gates each GCD line on [exists]: at press time the addon clears the target for every line but
	-- the one it picked, so only that one can cast
	local function condition(action, when)
		local cond = Compiler.Merge(when, guard)
		if smart and not action.offGcd then cond = Compiler.Merge(cond, "exists") end
		return cond
	end

	local function emit(action, line, index)
		local into = action.offGcd and early or late
		into[#into + 1] = line
		if not action.offGcd then gates[#late] = index end
	end

	-- A gated line that casts on another unit ([@player]) can't be stopped by clearing the target, since its
	-- [exists] checks that unit, so the cast goes on a step button behind a /click gated on the target instead
	local function emitCast(action, verb, rest, index)
		local unit = Compiler.Unit(action.when)
		if smart and unit and not action.offGcd then
			local number = firstStep + #result.steps
			result.steps[#result.steps + 1] = { lines = { command(verb, Compiler.Merge(action.when, guard), rest) } }
			emit(action, command("/click", condition(action, ""), Compiler.STEP_BUTTON .. number), index)
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
				result.casts[#result.casts + 1] = { index = index, kind = "spell", name = name, cond = cond, unit = unit, offGcd = action.offGcd, moving = action.moving, trigger = trim(action.trigger) }
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
	-- with Smart Picks, clearing the target stops auto-attack, so attacking comes last
	if not smart then
		for _, line in ipairs(attackLines) do lines[#lines + 1] = line end
	end
	for _, line in ipairs(early) do lines[#lines + 1] = line end
	if smart and #late > 0 then
		-- with no target, /targetlasttarget would grab an old one, so the gated lines need a target to start with
		lines[#lines + 1] = "/stopmacro [noexists]"
		lines[#lines + 1] = "/run RAPick()"
		for i, line in ipairs(late) do
			if gates[i] then
				lines[#lines + 1] = ("/run RAGate(%d)"):format(gates[i])
				lines[#lines + 1] = line
				lines[#lines + 1] = "/targetlasttarget [noexists]"
			else
				lines[#lines + 1] = line
			end
		end
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
