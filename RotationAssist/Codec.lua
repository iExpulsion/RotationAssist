local _, NS = ...
local RA = NS.RA

-- Rotation strings for sharing: !RA1!key=value;...! with every mode and action. Values are URL-style escaped,
-- numbers are base 36, and a spell ID is written #id so it can't be read as a spell name.
--
-- n= name, c= classes, o= options that are on, w= switch (t:spell or r:rule), x= notes, then m= a mode's label
-- followed by that mode's a= actions in order:
--   s:spell:when:trigger:flags   q:spell.spell:reset:when:flags   p:line.line   k:text:flags
-- Flags: g off the global cooldown, o once per reset.
local Codec = {}
RA.Codec = Codec

local FORMAT = 1
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
-- Whitespace is escaped too, because Decode drops raw whitespace that chat line wrapping adds.
local RESERVED = "[%%;,:!/=|#.%s]"

local function esc(s)
	return (tostring(s or ""):gsub(RESERVED, function(c) return ("%%%02X"):format(c:byte()) end))
end

local function unesc(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function split(s, sep)
	local out = {}
	if s ~= "" then
		local start = 1
		while true do
			local i = s:find(sep, start, true)
			out[#out + 1] = s:sub(start, (i or 0) - 1)
			if not i then break end
			start = i + 1
		end
	end
	return out
end

local function b36(n)
	n = math.floor(n)
	local s = ""
	repeat
		local r = n % 36
		s = DIGITS:sub(r + 1, r + 1) .. s
		n = (n - r) / 36
	until n == 0
	return s
end

local function spellOut(spell)
	return type(spell) == "number" and ("#" .. b36(spell)) or esc(spell)
end

-- A spell name, an ID, or nil and false when the ID is damaged.
local function spellIn(s)
	local id = s:match("^#(%w+)$")
	local spell = id and tonumber(id, 36) or (s:sub(1, 1) ~= "#" and unesc(s) or nil)
	return spell, spell ~= nil
end

local function listOut(items, write, sep)
	local parts = {}
	for i, item in ipairs(items or {}) do parts[i] = write(item) end
	return table.concat(parts, sep or ".")
end

local function flags(action)
	return (action.offGcd and "g" or "") .. (action.once and "o" or "")
end

-- Parts joined by ":", with trailing empty ones left off.
local function joinParts(parts)
	local last = 0
	for i = 1, #parts do
		if parts[i] ~= "" then last = i end
	end
	return table.concat(parts, ":", 1, last)
end

local writers = {
	spell = function(a) return { "s", spellOut(a.spell), esc(a.when), esc(a.trigger), flags(a) } end,
	sequence = function(a) return { "q", listOut(a.spells, spellOut), esc(a.reset), esc(a.when), flags(a) } end,
	steps = function(a) return { "p", listOut(a.steps, esc) } end,
	macro = function(a) return { "k", esc(a.text), flags(a) } end,
}

function Codec.Encode(rotation)
	local f = { "n=" .. esc(rotation.name) }
	if rotation.classes and #rotation.classes > 0 then f[#f + 1] = "c=" .. listOut(rotation.classes, esc, ",") end
	local on = {}
	for key, value in pairs(rotation.options or {}) do
		if value == true then on[#on + 1] = esc(key) end
	end
	table.sort(on)
	if #on > 0 then f[#f + 1] = "o=" .. table.concat(on, ",") end
	local switch = rotation.switch or {}
	if switch.kind == "toggle" then
		f[#f + 1] = "w=t" .. (switch.spell and (":" .. spellOut(switch.spell)) or "")
	elseif switch.kind == "rule" then
		f[#f + 1] = "w=r:" .. esc(switch.rule)
	end
	if rotation.notes and rotation.notes ~= "" then f[#f + 1] = "x=" .. esc(rotation.notes) end
	for _, mode in ipairs(rotation.modes or {}) do
		f[#f + 1] = "m=" .. esc(mode.label)
		for _, action in ipairs(mode.actions or {}) do
			local write = writers[action.kind]
			if write then f[#f + 1] = "a=" .. joinParts(write(action)) end
		end
	end
	return ("!RA%d!%s!"):format(FORMAT, table.concat(f, ";"))
end

local function readFlags(action, s)
	if (s or ""):find("g", 1, true) then action.offGcd = true end
	if (s or ""):find("o", 1, true) then action.once = true end
	return action
end

local function readSpells(s)
	local spells, ok = {}, true
	for _, part in ipairs(split(s or "", ".")) do
		local spell, good = spellIn(part)
		if good then spells[#spells + 1] = spell else ok = false end
	end
	return spells, ok
end

-- Each returns the action, or nil when it's damaged.
local readers = {
	s = function(p)
		local spell, ok = spellIn(p[2] or "")
		return ok and readFlags({ kind = "spell", spell = spell, when = unesc(p[3] or ""), trigger = unesc(p[4] or "") }, p[5]) or nil
	end,
	q = function(p)
		local spells, ok = readSpells(p[2])
		return ok and readFlags({ kind = "sequence", spells = spells, reset = unesc(p[3] or ""), when = unesc(p[4] or "") }, p[5]) or nil
	end,
	p = function(p)
		local steps = {}
		for i, line in ipairs(split(p[2] or "", ".")) do steps[i] = unesc(line) end
		return { kind = "steps", steps = steps }
	end,
	k = function(p) return readFlags({ kind = "macro", text = unesc(p[2] or "") }, p[3]) end,
}

local function readSwitch(v)
	local kind, rest = v:match("^(%a)(.*)$")
	local switch = { kind = "none" }
	if kind == "t" then
		switch = { kind = "toggle", spell = rest ~= "" and spellIn(rest:sub(2)) or nil }
	elseif kind == "r" then
		switch = { kind = "rule", rule = unesc(rest:sub(2)) }
	end
	return switch
end

-- Returns a new rotation, or nil and a status line saying what's wrong. Unknown fields and action kinds are
-- passed over.
function Codec.Decode(text)
	text = (text or ""):gsub("%s", "")
	local fmt, body = text:match("^!RA(%d+)!(.*)!$")
	local rotation = { name = "", classes = {}, modes = {}, switch = { kind = "none" }, options = {}, notes = "" }
	local err
	if not fmt then
		err = "Not a Rotation Assist String"
	elseif tonumber(fmt) > FORMAT then
		err = "Made by a Newer Rotation Assist: Update to Import It"
	else
		for _, field in ipairs(split(body, ";")) do
			local key, v = field:match("^(%w+)=(.*)$")
			local mode = rotation.modes[#rotation.modes]
			if key == "n" then
				rotation.name = RA.Spells.Trim(unesc(v))
			elseif key == "c" then
				for i, class in ipairs(split(v, ",")) do rotation.classes[i] = unesc(class) end
			elseif key == "o" then
				for _, option in ipairs(split(v, ",")) do rotation.options[unesc(option)] = true end
			elseif key == "w" then
				rotation.switch = readSwitch(v)
			elseif key == "x" then
				rotation.notes = unesc(v)
			elseif key == "m" then
				rotation.modes[#rotation.modes + 1] = { label = unesc(v), actions = {} }
			elseif key == "a" then
				local parts = split(v, ":")
				local read = readers[parts[1]]
				local action = read and read(parts)
				if not mode or (read and not action) then
					err = err or "This String Is Damaged"
				elseif action then
					mode.actions[#mode.actions + 1] = action
				end
			end
		end
		if not err and rotation.name == "" then
			err = "This String Has No Rotation Name"
		elseif not err and #rotation.modes == 0 then
			err = "This String Has No Modes"
		elseif not err and #rotation.modes > RA.Rotation.MAX_MODES then
			err = ("This String Has More Than %d Modes"):format(RA.Rotation.MAX_MODES)
		end
	end
	if not err and #rotation.classes == 0 then rotation.classes = RA:PlayerClasses() end
	return (not err) and rotation or nil, err
end
