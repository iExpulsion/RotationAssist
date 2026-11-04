local _, NS = ...
local RA = NS.RA

-- Rotations: one or more modes, each an ordered list of actions the button tries top to bottom.
--
-- rotation = { name, classes, modes = { { label, actions } }, switch, options, notes }
-- action   = { kind = "spell", spell, when, offGcd }
--          | { kind = "sequence", spells = { ... }, reset, when, once }   (once: stop after the last spell until reset)
--          | { kind = "steps", steps = { "line", ... } }
--          | { kind = "macro", text, offGcd }
-- switch   = { kind = "none" } | { kind = "toggle", spell } | { kind = "rule", rule = "[form:3] 2; 1" }
local Rotation = {}
RA.Rotation = Rotation

Rotation.MAX_MODES = 6
Rotation.KINDS = {
	{ value = "spell", text = "Spell", tooltip = "Cast one spell when it's ready." },
	{ value = "sequence", text = "Sequence", tooltip = "/castsequence: moves to the next spell only when a cast succeeds." },
	{ value = "steps", text = "Steps", tooltip = "One macro line per press, in order, whether or not it casts." },
	{ value = "macro", text = "Macro", tooltip = "A macro line run as it is, such as /use 13." },
}

function Rotation.New(name, classes)
	return {
		name = name,
		classes = classes or RA:PlayerClasses(),
		modes = { { label = "Main", actions = {} } },
		switch = { kind = "none" },
		options = { target = true, attack = true },
		notes = "",
	}
end

local function copy(value)
	local out = value
	if type(value) == "table" then
		out = {}
		for k, v in pairs(value) do out[k] = copy(v) end
	end
	return out
end
Rotation.Copy = copy

function Rotation.UniqueName(base)
	local name, n = base, 2
	while RA.db.rotations[name] do
		name = ("%s %d"):format(base, n)
		n = n + 1
	end
	return name
end

function Rotation.Add(rotation)
	RA.db.rotations[rotation.name] = rotation
	RA:Changed()
	return rotation
end

function Rotation.Rename(rotation, newName)
	local ok = newName ~= "" and newName ~= rotation.name and RA.db.rotations[newName] == nil
	if ok then
		local old = rotation.name
		RA.db.rotations[old] = nil
		rotation.name = newName
		RA.db.rotations[newName] = rotation
		for _, links in pairs(RA.db.links) do
			for g, linked in pairs(links) do
				if linked == old then links[g] = newName end
			end
		end
		RA:Changed()
	end
	return ok
end

function Rotation.Duplicate(rotation)
	local dup = copy(rotation)
	dup.name = Rotation.UniqueName(rotation.name .. " Copy")
	return Rotation.Add(dup)
end

function Rotation.Delete(rotation)
	RA.db.rotations[rotation.name] = nil
	for _, links in pairs(RA.db.links) do
		for g, linked in pairs(links) do
			if linked == rotation.name then links[g] = nil end
		end
	end
	RA:Changed()
end

function Rotation.AddMode(rotation, label)
	local ok = #rotation.modes < Rotation.MAX_MODES
	if ok then rotation.modes[#rotation.modes + 1] = { label = label, actions = {} } end
	return ok
end

-- Swaps list[i] with list[i + delta] when both exist.
function Rotation.Move(list, i, delta)
	local j = i + delta
	local ok = list[i] ~= nil and list[j] ~= nil
	if ok then list[i], list[j] = list[j], list[i] end
	return ok
end

-- A short label for an action in lists.
function Rotation.ActionText(action)
	local text
	if action.kind == "spell" then
		text = RA.Spells.Name(action.spell) or ("Spell #" .. tostring(action.spell))
	elseif action.kind == "sequence" then
		text = "Sequence: " .. RA.Spells.ListText(action.spells)
	elseif action.kind == "steps" then
		text = RA.Style.Count(#(action.steps or {}), "Step")
	else
		text = action.text ~= "" and action.text or "Empty Macro"
	end
	return text
end

function Rotation.ActionIcon(action)
	local spell = action.kind == "spell" and action.spell or action.kind == "sequence" and (action.spells or {})[1]
	return spell and RA.Spells.Icon(spell) or "Interface\\Icons\\INV_Misc_Note_01"
end

-- Starting points offered by New Rotation. Spells are by name, so they turn into IDs only on characters that
-- have them; tune the order in game.
Rotation.TEMPLATES = {
	{
		key = "frostLich",
		label = "Frost Death Knight with Lich Form",
		classes = { "DEATHKNIGHT" },
		build = function()
			local function spell(name, when, offGcd)
				return { kind = "spell", spell = name, when = when, offGcd = offGcd }
			end
			local function once(spells, reset)
				return { kind = "sequence", spells = spells, reset = reset or "target/combat", once = true }
			end
			return {
				modes = {
					{ label = "Melee", actions = {
						spell("Deathchill", "[combat]", true),
						spell("Blood Tap", "[combat]", true),
						spell("Unbreakable Armor", "[combat]", true),
						spell("Obliterate"),
						spell("Blood Strike"),
						spell("Frost Strike"),
						-- with Glyph of Howling Blast this also keeps Frost Fever up
						spell("Howling Blast"),
						-- low, so it's tried now and then and keeps Blood Plague up without taking many runes
						spell("Plague Strike"),
						spell("Horn of Winter"),
					} },
					{ label = "Lich Form AoE", actions = {
						spell("Deathchill", "[combat]", true),
						once({ "Mark of Frost" }),
						spell("Howling Blast"),
						spell("Icy Touch"),
						spell("Death Coil"),
						spell("Horn of Winter"),
					} },
				},
				switch = { kind = "toggle", spell = "Lich Form" },
				options = { target = true, attack = true, cycle = true },
				notes = "One Spell per Press is on: each press tries one spell, top ones most often, so mash the key. A Death Knight spell waiting on runes stops the rest of a press, so a plain priority list would stall.\nMelee: Obliterate on Frost and Unholy runes, Blood Strike on Blood runes, Frost Strike with Runic Power, Howling Blast (Glyph of Howling Blast keeps Frost Fever up), and Plague Strike now and then to keep Blood Plague up. Deathchill, Blood Tap and Unbreakable Armor go off on cooldown every press.\nLich Form: Mark of Frost once per target, then Howling Blast on every rune pair, Icy Touch with a leftover rune, Death Coil to spend Runic Power.\nThe Mode key casts Lich Form and moves to the AoE mode in one press; pressing it again leaves Lich Form. Leave it to heal.",
			}
		end,
	},
}

function Rotation.FromTemplate(key, name)
	local rotation = Rotation.New(name)
	for _, t in ipairs(Rotation.TEMPLATES) do
		if t.key == key then
			local parts = t.build()
			rotation.classes = t.classes
			rotation.modes, rotation.switch, rotation.options, rotation.notes = parts.modes, parts.switch, parts.options, parts.notes
		end
	end
	return rotation
end
